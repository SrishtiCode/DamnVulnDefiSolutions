// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC3156FlashLender} from "@openzeppelin/contracts/interfaces/IERC3156FlashLender.sol";
import {IERC3156FlashBorrower} from "@openzeppelin/contracts/interfaces/IERC3156FlashBorrower.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {SimpleGovernance} from "./SimpleGovernance.sol";

// ================================================================
// CONTRACT OVERVIEW: SelfiePool
// ================================================================
// A flash loan pool that holds DVT governance tokens and exposes
// an emergencyExit() function exclusively callable by governance.
//
// CORE FLOW (normal):
//   1. Anyone calls flashLoan() to borrow DVT tokens fee-free
//   2. Borrower's onFlashLoan() callback executes
//   3. Borrower repays via transferFrom() before tx ends
//
// ATTACK FLOW (exploit):
//   1. Attacker flash-borrows the entire DVT pool balance
//   2. Inside the callback, attacker now holds >50% of supply
//   3. Attacker delegates votes to self → satisfies governance threshold
//   4. Attacker queues emergencyExit(attacker) via SimpleGovernance
//   5. Attacker repays the flash loan (votes drop, action stays queued)
//   6. After 2-day time-lock, anyone executes the action
//   7. emergencyExit() drains the pool to the attacker
//
// ROOT CAUSE: The pool's own tokens can be flash-borrowed to
// temporarily meet the governance voting threshold, then used to
// queue a call that drains those same tokens — a self-referential attack.
// ================================================================

contract SelfiePool is IERC3156FlashLender, ReentrancyGuard {

    // Return value the borrower's callback MUST return to confirm success
    // keccak256("ERC3156FlashBorrower.onFlashLoan") — ERC-3156 standard
    bytes32 private constant CALLBACK_SUCCESS = keccak256("ERC3156FlashBorrower.onFlashLoan");

    // The DVT token this pool lends — also the governance voting token
    // ⚠️ Same token used for both liquidity AND governance votes
    IERC20 public immutable token;

    // The governance contract that controls emergencyExit()
    // Only actions executed through SimpleGovernance can call onlyGovernance functions
    SimpleGovernance public immutable governance;

    // ----------------------------------------------------------------
    // Custom Errors (gas-efficient vs require strings)
    // ----------------------------------------------------------------
    error RepayFailed();           // borrower's transferFrom() returned false
    error CallerNotGovernance();   // emergencyExit() called by non-governance
    error UnsupportedCurrency();   // flash loan requested for wrong token
    error CallbackFailed();        // borrower's onFlashLoan() returned wrong hash

    // Emitted when governance drains the pool via emergencyExit()
    event EmergencyExit(address indexed receiver, uint256 amount);

    // ----------------------------------------------------------------
    // onlyGovernance modifier
    // Restricts function access to the bound SimpleGovernance contract.
    // ⚠️ Governance itself can be hijacked via flash loan — see attack flow above.
    // ----------------------------------------------------------------
    modifier onlyGovernance() {
        if (msg.sender != address(governance)) {
            revert CallerNotGovernance();
        }
        _;
    }

    // ----------------------------------------------------------------
    // Constructor: bind pool to a specific token + governance contract
    // ----------------------------------------------------------------
    constructor(IERC20 _token, SimpleGovernance _governance) {
        token = _token;
        governance = _governance;
    }

    // ================================================================
    // maxFlashLoan()
    // ================================================================
    // ERC-3156: returns the maximum borrowable amount for a given token.
    // Returns the pool's full DVT balance (fee-free, 100% utilization).
    // Returns 0 for any unsupported token (no revert per ERC-3156 spec).
    //
    // ⚠️ Returning the ENTIRE balance as borrowable means an attacker
    //    can always acquire >50% of supply in a single flash loan.
    // ================================================================
    function maxFlashLoan(address _token) external view returns (uint256) {
        if (address(token) == _token) {
            return token.balanceOf(address(this)); // full pool balance available
        }
        return 0; // unsupported token → 0 per ERC-3156
    }

    // ================================================================
    // flashFee()
    // ================================================================
    // ERC-3156: returns the fee charged for a flash loan.
    // Always returns 0 — this pool charges NO fee.
    //
    // NOTE: Zero fees make the attack completely cost-free for the attacker
    // (only pays gas for queue + execute transactions).
    // ================================================================
    function flashFee(address _token, uint256) external view returns (uint256) {
        if (address(token) != _token) {
            revert UnsupportedCurrency();
        }
        return 0; // fee-free flash loans
    }

    // ================================================================
    // flashLoan()
    // ================================================================
    // ERC-3156 compliant flash loan implementation.
    //
    // EXECUTION ORDER:
    //   1. Validate token is supported
    //   2. Transfer _amount to borrower
    //   3. Call borrower's onFlashLoan() callback — ⚠️ ATTACK HAPPENS HERE
    //      └─ attacker delegates votes + queues emergencyExit() in callback
    //   4. Verify callback returned CALLBACK_SUCCESS
    //   5. Pull repayment back via transferFrom()
    //
    // PROTECTIONS:
    //   - nonReentrant: prevents re-entering flashLoan() during callback
    //   - CALLBACK_SUCCESS check: ensures borrower acknowledged the loan
    //   - transferFrom repayment: borrower must approve pool before callback
    //
    // MISSING PROTECTION:
    //   - No snapshot of votes before/after — governance state is not restored
    // ================================================================
    function flashLoan(
        IERC3156FlashBorrower _receiver,
        address _token,
        uint256 _amount,
        bytes calldata _data        // arbitrary data forwarded to borrower callback
    )
        external
        nonReentrant               // prevents re-entrant flashLoan() calls
        returns (bool)
    {
        // Only DVT is supported — reject all other tokens
        if (_token != address(token)) {
            revert UnsupportedCurrency();
        }

        // Transfer loan amount to borrower
        // ⚠️ At this point the borrower temporarily holds up to 100% of supply
        token.transfer(address(_receiver), _amount);

        // Invoke ERC-3156 callback on borrower
        // ⚠️ THIS IS WHERE THE ATTACK OCCURS:
        //    Borrower calls _votingToken.delegate(self) → queues emergencyExit()
        //    The governance action is now permanently stored on-chain
        if (_receiver.onFlashLoan(msg.sender, _token, _amount, 0, _data) != CALLBACK_SUCCESS) {
            revert CallbackFailed();
        }

        // Borrower must have approved this pool to pull repayment
        // Reverts if borrower didn't repay — but the queued action survives
        if (!token.transferFrom(address(_receiver), address(this), _amount)) {
            revert RepayFailed();
        }

        return true;
    }

    // ================================================================
    // emergencyExit()
    // ================================================================
    // Transfers the pool's ENTIRE token balance to an arbitrary address.
    // Callable ONLY by the governance contract (via onlyGovernance).
    //
    // INTENDED USE: emergency protocol rescue by DAO vote.
    //
    // ⚠️ ACTUAL RISK: Because governance can be hijacked via flash loan
    //    (see SimpleGovernance._hasEnoughVotes), an attacker can queue
    //    emergencyExit(attacker) and drain the pool after 2 days.
    //
    // FIX WOULD BE: use ERC20Votes.getPastVotes(account, block.number - 1)
    //    instead of getVotes() in SimpleGovernance to prevent flash loan abuse.
    // ================================================================
    function emergencyExit(address receiver) external onlyGovernance {
        uint256 amount = token.balanceOf(address(this)); // drain 100% of pool
        token.transfer(receiver, amount);
        emit EmergencyExit(receiver, amount);
    }
}