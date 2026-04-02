// SPDX-License-Identifier: MIT
pragma solidity =0.8.25;

// ReentrancyGuard: prevents a function from being called again
// while it's still executing (protects against reentrancy attacks)
import {ReentrancyGuard} from "solady/utils/ReentrancyGuard.sol";

// FixedPointMathLib: math helpers for numbers with 18 decimal places (WAD format)
// e.g. 0.05 ether = 0.05 * 1e18 = 5% in WAD
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

// Owned: gives the contract an `owner` and an `onlyOwner` modifier
import {Owned} from "solmate/auth/Owned.sol";

// ERC4626: the "tokenized vault" standard
//   - users deposit ERC20 tokens → receive "shares" in return
//   - shares represent proportional ownership of the vault's assets
// SafeTransferLib: safe wrappers around ERC20 transfer/transferFrom
//   (reverts on failure instead of returning false silently)
import {SafeTransferLib, ERC4626, ERC20} from "solmate/tokens/ERC4626.sol";

// Pausable: lets the owner freeze the contract in an emergency
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

// ERC3156: standard interface for flash loans
//   IERC3156FlashLender   = this contract (it lends tokens)
//   IERC3156FlashBorrower = the contract that borrows tokens
import {IERC3156FlashBorrower, IERC3156FlashLender} from "@openzeppelin/contracts/interfaces/IERC3156.sol";

/**
 * WHAT THIS CONTRACT DOES
 * ─────────────────────────────────────────────────────
 * 1. ERC4626 vault:
 *      deposit token  →  receive shares (tDVT)
 *      burn shares    →  withdraw token
 *
 * 2. ERC3156 flash loan lender:
 *      borrow up to totalAssets() in one transaction
 *      must repay principal + fee in the same transaction
 *
 * KEY INVARIANT (must never break):
 * ─────────────────────────────────────────────────────
 *   convertToShares(totalSupply) == totalAssets()
 *
 *   In plain English:
 *     "If you convert ALL outstanding shares back to tokens,
 *      you should get exactly the token balance this contract holds."
 *
 *   This is checked at the top of flashLoan().
 *   If it breaks → flashLoan() reverts FOREVER → vault is bricked.
 */
contract UnstoppableVault is IERC3156FlashLender, ReentrancyGuard, Owned, ERC4626, Pausable {
    using SafeTransferLib for ERC20;     // attach safe transfer methods to ERC20
    using FixedPointMathLib for uint256; // attach WAD math to uint256

    // ─────────────────────────────────────────────────────
    // CONSTANTS
    // ─────────────────────────────────────────────────────

    // Flash loan fee = 5%
    // 0.05 ether = 0.05 * 1e18 in WAD notation
    // mulWadUp(amount, FEE_FACTOR) = amount * 0.05 rounded up
    uint256 public constant FEE_FACTOR = 0.05 ether;

    // Grace period: 30 days from deployment
    // Flash loans can be FREE during this window (see flashFee)
    uint64 public constant GRACE_PERIOD = 30 days;

    // Precomputed end timestamp — set once at deploy, never changes
    uint64 public immutable end = uint64(block.timestamp) + GRACE_PERIOD;

    // Address that receives flash loan fee income
    address public feeRecipient;

    // ─────────────────────────────────────────────────────
    // CUSTOM ERRORS (cheaper than require strings)
    // ─────────────────────────────────────────────────────
    error InvalidAmount(uint256 amount);  // amount == 0
    error InvalidBalance();               // key invariant broken ← BUG SURFACE
    error CallbackFailed();               // borrower didn't return magic value
    error UnsupportedCurrency();          // token != vault's asset

    event FeeRecipientUpdated(address indexed newFeeRecipient);

    // ─────────────────────────────────────────────────────
    // CONSTRUCTOR
    // ─────────────────────────────────────────────────────
    constructor(ERC20 _token, address _owner, address _feeRecipient)
        ERC4626(_token, "Too Damn Valuable Token", "tDVT")
        Owned(_owner)
    {
        feeRecipient = _feeRecipient;
        emit FeeRecipientUpdated(_feeRecipient);
    }

    // ─────────────────────────────────────────────────────
    // maxFlashLoan
    // ─────────────────────────────────────────────────────

    // nonReadReentrant: blocks reentrant view calls
    // (prevents read-only reentrancy that manipulates price oracles)
    //
    // Returns 0 for any token that isn't this vault's underlying asset.
    // Returns totalAssets() otherwise.
    //
    // ATTACK NOTE:
    //   totalAssets() reads the LIVE balanceOf() from the ERC20 contract.
    //   Anyone can inflate this by sending tokens directly to the vault,
    //   bypassing deposit() → no shares minted → invariant breaks.
    function maxFlashLoan(address _token) public view nonReadReentrant returns (uint256) {
        if (address(asset) != _token) {
            return 0;
        }
        return totalAssets(); // live balanceOf — externally manipulable
    }

    // ─────────────────────────────────────────────────────
    // flashFee
    // ─────────────────────────────────────────────────────

    // FREE if BOTH conditions hold:
    //   1. block.timestamp < end   (within the 30-day grace period)
    //   2. _amount < maxFlashLoan  (borrowing less than the full pool)
    //
    // Otherwise: fee = amount * 5% rounded up
    function flashFee(address _token, uint256 _amount) public view returns (uint256 fee) {
        if (address(asset) != _token) {
            revert UnsupportedCurrency();
        }

        if (block.timestamp < end && _amount < maxFlashLoan(_token)) {
            return 0;
        } else {
            return _amount.mulWadUp(FEE_FACTOR);
        }
    }

    // ─────────────────────────────────────────────────────
    // totalAssets
    // ─────────────────────────────────────────────────────

    // IMPORTANT: reads from the REAL WORLD (ERC20 contract's storage),
    // NOT from any internal counter tracked by this vault.
    //
    // This means the return value can be changed by ANYONE at any time
    // simply by calling token.transfer(address(vault), someAmount).
    //
    // That direct transfer changes totalAssets() without changing totalSupply.
    // That's exactly what breaks the invariant checked in flashLoan().
    function totalAssets() public view override nonReadReentrant returns (uint256) {
        return asset.balanceOf(address(this)); // live ERC20 state — not an internal counter
    }

    // ─────────────────────────────────────────────────────
    // flashLoan  ← CONTAINS THE VULNERABLE CHECK
    // ─────────────────────────────────────────────────────

    // TOKEN FLOW:
    //
    //   vault ──(amount)──► receiver.onFlashLoan()
    //                              │
    //                              └──(amount + fee)──► vault
    //                                                      │
    //                                                      └──(fee)──► feeRecipient
    //
    function flashLoan(IERC3156FlashBorrower receiver, address _token, uint256 amount, bytes calldata data)
        external
        returns (bool)
    {
        // Reject zero-amount loans immediately
        if (amount == 0) revert InvalidAmount(0);

        // Only lend the vault's own underlying token
        if (address(asset) != _token) revert UnsupportedCurrency();

        // Snapshot the vault's token balance before the loan goes out
        // balanceBefore = asset.balanceOf(address(this)) right now
        uint256 balanceBefore = totalAssets();

        // ╔═══════════════════════════════════════════════════════════════╗
        // ║  THE KEY INVARIANT CHECK  ←  THIS IS THE BUG                ║
        // ║                                                               ║
        // ║  convertToShares(totalSupply) computes:                      ║
        // ║    totalSupply * totalAssets() / totalSupply = totalAssets() ║
        // ║                                                               ║
        // ║  Healthy vault:                                               ║
        // ║    totalAssets() == totalAssets()  → always passes           ║
        // ║                                                               ║
        // ║  After a direct token.transfer() to the vault:               ║
        // ║    totalSupply   → unchanged (no shares minted)              ║
        // ║    totalAssets() → increased (real balance is higher)        ║
        // ║                                                               ║
        // ║  Now: convertToShares(totalSupply) < balanceBefore           ║
        // ║  → revert InvalidBalance()  → FOREVER                        ║
        // ╚═══════════════════════════════════════════════════════════════╝
        if (convertToShares(totalSupply) != balanceBefore) revert InvalidBalance();

        // Send tokens to the borrower
        // (totalAssets() temporarily drops by `amount` after this)
        ERC20(_token).safeTransfer(address(receiver), amount);

        // Calculate the fee (may be 0 during grace period)
        uint256 fee = flashFee(_token, amount);

        // Call the borrower's callback
        // Borrower MUST return this exact magic value (EIP-3156 spec)
        // Your MockReceiver in tests needs to return this
        if (
            receiver.onFlashLoan(msg.sender, address(asset), amount, fee, data)
                != keccak256("IERC3156FlashBorrower.onFlashLoan")
        ) {
            revert CallbackFailed();
        }

        // Pull back principal + fee from the borrower
        // Borrower must have approved this vault to spend (amount + fee)
        ERC20(_token).safeTransferFrom(address(receiver), address(this), amount + fee);

        // Forward the fee to the fee recipient
        // If fee == 0 (grace period), this is a no-op
        ERC20(_token).safeTransfer(feeRecipient, fee);

        return true;
    }

    // ─────────────────────────────────────────────────────
    // ERC4626 HOOKS
    // ─────────────────────────────────────────────────────

    // Called BEFORE a withdrawal executes.
    // nonReentrant blocks reentrant calls (write-lock, not just read-lock).
    // Body is empty — the guard is the only purpose here.
    function beforeWithdraw(uint256 assets, uint256 shares) internal override nonReentrant {}

    // Called AFTER a deposit executes.
    // whenNotPaused: deposits are blocked when paused, withdrawals are not.
    // This asymmetry is intentional — users can always exit, never get trapped.
    function afterDeposit(uint256 assets, uint256 shares) internal override nonReentrant whenNotPaused {}

    // ─────────────────────────────────────────────────────
    // OWNER FUNCTIONS
    // ─────────────────────────────────────────────────────

    // Change who receives flash loan fees.
    // Guards against setting the vault itself as recipient
    // (fees would be trapped inside with no way to claim them).
    function setFeeRecipient(address _feeRecipient) external onlyOwner {
        if (_feeRecipient != address(this)) {
            feeRecipient = _feeRecipient;
            emit FeeRecipientUpdated(_feeRecipient);
        }
    }

    // Execute arbitrary logic on any target via delegatecall.
    //
    // delegatecall: runs the target's code in THIS contract's context
    //   → target can read and write THIS contract's storage
    //   → target can spend ETH held by THIS contract
    //   → extremely powerful, extremely dangerous
    //
    // Only callable when paused — the pause acts as a "break glass" gate.
    //
    // NOTE: this does NOT fix the InvalidBalance bug.
    // There is no recovery path for the bricked flashLoan() through
    // any existing function — that's part of what makes it critical.
    function execute(address target, bytes memory data) external onlyOwner whenPaused {
        (bool success,) = target.delegatecall(data);
        require(success);
    }

    // Pause or unpause the contract.
    // true  → pause  (blocks deposits, enables execute())
    // false → unpause (re-enables deposits, blocks execute())
    function setPause(bool flag) external onlyOwner {
        if (flag) _pause();
        else _unpause();
    }
}
