// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

// ─────────────────────────────────────────────
// IMPORTS
// ─────────────────────────────────────────────

// Initializable: Prevents re-initialization of upgradeable contracts.
// Replaces constructor logic with an `initialize()` function called once.
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

// OwnableUpgradeable: Upgradeable version of Ownable.
// Adds `onlyOwner` modifier and ownership transfer — but must be explicitly initialized.
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

// UUPSUpgradeable: Universal Upgradeable Proxy Standard.
// The implementation contract itself controls upgrade logic (vs. transparent proxy).
// Upgrade auth lives in `_authorizeUpgrade()` — must be guarded carefully.
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

// Standard ERC20 interface — used to call balanceOf() and transfer().
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Gas-optimized, revert-safe token transfer library from Solady.
// Safer than raw IERC20.transfer() — handles non-standard tokens that don't return bool.
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";

// The timelock contract that acts as this vault's owner.
// All privileged actions must be scheduled → delayed → executed through it.
import {ClimberTimelock} from "./ClimberTimelock.sol";

// WITHDRAWAL_LIMIT: Max tokens that can be withdrawn per call (rate-limiting cap).
// WAITING_PERIOD:   Minimum seconds that must elapse between withdrawals.
import {WITHDRAWAL_LIMIT, WAITING_PERIOD} from "./ClimberConstants.sol";

// Custom error types (gas-efficient vs. revert strings):
// CallerNotSweeper      — msg.sender is not the authorized sweeper
// InvalidWithdrawalAmount — requested amount exceeds the per-call cap
// InvalidWithdrawalTime   — cooldown period has not elapsed yet
import {CallerNotSweeper, InvalidWithdrawalAmount, InvalidWithdrawalTime} from "./ClimberErrors.sol";

// ─────────────────────────────────────────────
// CONTRACT
// ─────────────────────────────────────────────

/**
 * @title  ClimberVault
 * @notice A UUPS-upgradeable ERC20 vault rate-limited by a timelock.
 *
 * ARCHITECTURE OVERVIEW
 * ┌──────────┐   owns/controls   ┌──────────────────┐
 * │ Timelock │ ────────────────► │  ClimberVault     │
 * │ (owner)  │                   │  (proxy + impl)   │
 * └──────────┘                   └──────────────────┘
 *       ▲
 *  proposals scheduled by `proposer`,
 *  admin can grant/revoke roles
 *
 * TRUST MODEL
 * - Owner (timelock):  can withdraw (rate-limited) and authorize upgrades.
 * - Sweeper:           can drain ALL funds instantly — highest-privilege role.
 * - Admin/Proposer:    control the timelock's scheduling queue.
 *
 * ATTACK SURFACE
 * - Compromising the timelock → unrestricted upgrade → total takeover.
 * - Compromising the sweeper  → instant full fund loss.
 *
 * @dev Inherits Initializable, OwnableUpgradeable, UUPSUpgradeable.
 *      Storage layout must remain append-only across upgrades.
 */
contract ClimberVault is Initializable, OwnableUpgradeable, UUPSUpgradeable {

    // ─────────────────────────────────────────
    // STATE VARIABLES
    // ─────────────────────────────────────────

    /**
     * @dev Unix timestamp of the most recent successful withdrawal.
     *      Used to enforce the WAITING_PERIOD cooldown between withdrawals.
     *      Stored as private to prevent direct external manipulation.
     *
     * SLOT: 0 (after inherited OwnableUpgradeable's `_owner` slot)
     * ⚠️ Slot order matters — never reorder storage in upgradeable contracts.
     */
    uint256 private _lastWithdrawalTimestamp;

    /**
     * @dev Address authorized to call `sweepFunds()`.
     *      Bypasses all withdrawal limits — treat like a root/sudo account.
     *      Set once during `initialize()`; no public setter exists (intentional).
     *
     * SLOT: 1
     */
    address private _sweeper;

    // ─────────────────────────────────────────
    // MODIFIERS
    // ─────────────────────────────────────────

    /**
     * @dev Guards functions that only the sweeper may call.
     *      Reverts with a custom error (cheaper than require + string).
     */
    modifier onlySweeper() {
        if (msg.sender != _sweeper) {
            revert CallerNotSweeper();
        }
        _;
    }

    // ─────────────────────────────────────────
    // CONSTRUCTOR
    // ─────────────────────────────────────────

    /**
     * @dev Permanently disables the `initialize()` function on the raw
     *      implementation contract (not the proxy).
     *
     *      WHY THIS MATTERS (UUPS security):
     *      Without this, anyone could call `initialize()` directly on the
     *      implementation, become its owner, and call `upgradeToAndCall()`
     *      to selfdestruct or corrupt the implementation — bricking all proxies
     *      that point to it.
     *
     *      `_disableInitializers()` sets the internal version counter to
     *      type(uint64).max, making any future `initializer` call revert.
     */
    constructor() {
        _disableInitializers();
    }

    // ─────────────────────────────────────────
    // INITIALIZATION
    // ─────────────────────────────────────────

    /**
     * @notice One-time setup called by the proxy immediately after deployment.
     *         Replaces the constructor for upgradeable contracts.
     *
     * @param admin     Address granted the ADMIN role in the new timelock.
     *                  Can grant/revoke roles but cannot directly execute vault ops.
     * @param proposer  Address granted the PROPOSER role in the timelock.
     *                  Can schedule operations for delayed execution.
     * @param sweeper   Address that can instantly drain all vault funds.
     *
     * INITIALIZATION SEQUENCE
     * 1. __Ownable_init(msg.sender)      — temporarily sets deployer as owner
     * 2. __UUPSUpgradeable_init()        — sets up upgrade mechanism
     * 3. transferOwnership(timelock)     — permanently hands control to the timelock
     * 4. _setSweeper(sweeper)            — set privileged sweeper address
     * 5. _updateLastWithdrawalTimestamp  — start cooldown clock from deploy time
     *
     * @dev Protected by `initializer` modifier — reverts if called again.
     *      `msg.sender` here is the proxy contract, not an EOA.
     */
    function initialize(address admin, address proposer, address sweeper) external initializer {
        // Step 1 & 2: Initialize ownership and UUPS upgrade internals.
        // Must be called in this order — OwnableUpgradeable sets _owner,
        // which _authorizeUpgrade() later checks via `onlyOwner`.
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();

        // Step 3: Deploy a fresh ClimberTimelock and immediately transfer vault
        // ownership to it. After this line, the deployer has NO owner privileges.
        //
        // ⚠️ The vault can now only act via timelock-scheduled operations.
        //    Direct owner calls (e.g., withdraw) require going through the timelock queue.
        transferOwnership(address(new ClimberTimelock(admin, proposer)));

        // Step 4: Register the sweeper. No on-chain way to change this later
        // (no public setSweeper). Losing access to sweeper = losing sweep ability forever.
        _setSweeper(sweeper);

        // Step 5: Record deploy time as "last withdrawal" so the first withdrawal
        // must wait at least WAITING_PERIOD seconds after deployment.
        _updateLastWithdrawalTimestamp(block.timestamp);
    }

    // ─────────────────────────────────────────
    // OWNER-RESTRICTED FUNCTIONS (via Timelock)
    // ─────────────────────────────────────────

    /**
     * @notice Withdraws a limited amount of ERC20 tokens to a recipient.
     *
     * @param token     ERC20 token contract address to withdraw.
     * @param recipient Destination address for the tokens.
     * @param amount    Number of tokens (in base units) to transfer.
     *
     * SECURITY CONTROLS
     * ┌─────────────────────┬────────────────────────────────────────────┐
     * │ Control             │ Purpose                                     │
     * ├─────────────────────┼────────────────────────────────────────────┤
     * │ onlyOwner           │ Only callable via timelock (not directly)   │
     * │ WITHDRAWAL_LIMIT    │ Caps per-call amount — limits blast radius  │
     * │ WAITING_PERIOD      │ Enforces cooldown between withdrawals       │
     * │ CEI pattern         │ Timestamp updated BEFORE transfer           │
     * └─────────────────────┴────────────────────────────────────────────┘
     *
     * @dev Does NOT emit an event — consider adding one for off-chain monitoring.
     */
    function withdraw(address token, address recipient, uint256 amount) external onlyOwner {

        // Guard: Reject amounts above the configured per-withdrawal cap.
        // WITHDRAWAL_LIMIT is a compile-time constant — no on-chain way to change it.
        if (amount > WITHDRAWAL_LIMIT) {
            revert InvalidWithdrawalAmount();
        }

        // Guard: Reject calls made before the cooldown period has fully elapsed.
        // Uses `<=` (not `<`) to ensure a full WAITING_PERIOD has passed.
        if (block.timestamp <= _lastWithdrawalTimestamp + WAITING_PERIOD) {
            revert InvalidWithdrawalTime();
        }

        // CEI Pattern — update state BEFORE external call to prevent reentrancy.
        // Even though ERC20 transfers are generally safe, this is best practice.
        _updateLastWithdrawalTimestamp(block.timestamp);

        // Transfer tokens. SafeTransferLib handles tokens that:
        // - Don't return a bool (e.g., USDT)
        // - Return false instead of reverting
        // Reverts if transfer fails for any reason.
        SafeTransferLib.safeTransfer(token, recipient, amount);
    }

    // ─────────────────────────────────────────
    // SWEEPER-RESTRICTED FUNCTIONS
    // ─────────────────────────────────────────

    /**
     * @notice Transfers the vault's ENTIRE balance of a token to the sweeper.
     *
     * @param token ERC20 token address to sweep.
     *
     * ⚠️ EXTREME PRIVILEGE — NO LIMITS APPLY:
     *    - No amount cap (ignores WITHDRAWAL_LIMIT)
     *    - No cooldown (ignores WAITING_PERIOD)
     *    - No timelock delay required
     *    - One call drains everything
     *
     * INTENDED USE: Emergency recovery or end-of-life fund retrieval.
     * RISK:         If _sweeper is compromised, all vault assets are lost instantly.
     *
     * @dev Uses balanceOf at call time — amount is determined dynamically.
     *      If the vault receives tokens mid-call (via reentrancy), those are swept too.
     */
    function sweepFunds(address token) external onlySweeper {
        SafeTransferLib.safeTransfer(
            token,
            _sweeper,                           // destination = sweeper itself
            IERC20(token).balanceOf(address(this)) // full vault balance
        );
    }

    // ─────────────────────────────────────────
    // VIEW FUNCTIONS
    // ─────────────────────────────────────────

    /**
     * @notice Returns the currently configured sweeper address.
     * @dev Exposed as a view so external tooling can verify the sweeper
     *      without needing to decode storage slots directly.
     */
    function getSweeper() external view returns (address) {
        return _sweeper;
    }

    /**
     * @notice Returns the Unix timestamp of the last successful withdrawal.
     * @dev Useful for computing when the next withdrawal window opens:
     *      `nextAvailableAt = getLastWithdrawalTimestamp() + WAITING_PERIOD`
     */
    function getLastWithdrawalTimestamp() external view returns (uint256) {
        return _lastWithdrawalTimestamp;
    }

    // ─────────────────────────────────────────
    // INTERNAL / PRIVATE HELPERS
    // ─────────────────────────────────────────

    /**
     * @dev Sets the sweeper address in storage.
     *      Private — only callable during initialization.
     *      No validation: zero-address sweeper would permanently disable sweep.
     *
     * @param newSweeper The address to designate as sweeper.
     */
    function _setSweeper(address newSweeper) private {
        _sweeper = newSweeper;
    }

    /**
     * @dev Updates the last withdrawal timestamp in storage.
     *      Called both during initialization (to start the cooldown clock)
     *      and after each successful withdrawal (to reset it).
     *
     * @param timestamp New timestamp value, typically `block.timestamp`.
     */
    function _updateLastWithdrawalTimestamp(uint256 timestamp) private {
        _lastWithdrawalTimestamp = timestamp;
    }

    // ─────────────────────────────────────────
    // UPGRADE AUTHORIZATION (UUPS)
    // ─────────────────────────────────────────

    /**
     * @notice Hook called by `upgradeTo()` / `upgradeToAndCall()` before
     *         replacing the implementation address in the proxy.
     *
     * @param newImplementation Address of the new logic contract.
     *
     * UUPS UPGRADE FLOW
     *  EOA/script → proxy.upgradeTo(newImpl)
     *             → proxy delegatecalls → implementation._authorizeUpgrade()
     *             → [passes onlyOwner] → proxy stores newImpl in EIP-1967 slot
     *
     * WHY THIS IS CRITICAL:
     * The `onlyOwner` guard here is the SOLE on-chain protection against
     * arbitrary implementation replacement. If an attacker controls the
     * timelock (the owner), they can:
     *  1. Schedule an upgrade to a malicious contract
     *  2. Wait out the timelock delay
     *  3. Execute → gain full control of vault storage and all funds
     *
     * ⚠️ This is the root of the "Climber" challenge's vulnerability:
     *    a flaw in the timelock allows bypassing the delay entirely.
     *
     * @dev Empty body — authorization is enforced purely by `onlyOwner`.
     *      No additional implementation validation is performed.
     */
    function _authorizeUpgrade(address newImplementation)
        internal
        override
        onlyOwner
    {}
}
