// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {AuthorizedExecutor} from "./AuthorizedExecutor.sol";

/**
 * @title SelfAuthorizedVault
 * @dev A token vault that can ONLY be operated by calling through its own `execute`
 *      function (inherited from AuthorizedExecutor). Every sensitive action is guarded
 *      by the `onlyThis` modifier, meaning the vault must be both the *caller* and the
 *      *target* of every execution — hence "self-authorized".
 *
 * Architecture flow:
 *   External actor → AuthorizedExecutor.execute(address(this), calldata)
 *                        └─ permission check (selector + caller + target)
 *                        └─ _beforeFunctionCall: enforces target == address(this)
 *                        └─ this.withdraw() / this.sweepFunds()
 *                               └─ onlyThis: enforces msg.sender == address(this)
 *
 * Key invariants:
 *   • No direct external call can reach withdraw() or sweepFunds() — both require
 *     msg.sender == address(this), which is only possible via the execute() relay.
 *   • execute() itself requires a pre-registered permission for the
 *     (selector, executor, target) triple, set once during initialization.
 *   • Withdrawals are rate-limited: max 1 ETH-worth of tokens per 15-day window.
 *
 *   Known design consideration (intentional for the CTF):
 *   `setPermissions` in the parent has NO access control — the very first external
 *   caller can register arbitrary permissions. Deployers must call it in the same
 *   transaction as deployment (or via constructor) to prevent front-running.
 */
contract SelfAuthorizedVault is AuthorizedExecutor {

    // ─────────────────────────────────────────────
    // Constants
    // ─────────────────────────────────────────────

    /// @notice Maximum token amount (in wei) that can be withdrawn in a single call.
    ///         Denominated in 1 ether (1e18) regardless of the token's own decimals,
    ///         so the vault assumes the token has 18 decimals for this limit to be meaningful.
    uint256 public constant WITHDRAWAL_LIMIT = 1 ether;

    /// @notice Minimum time that must elapse between two successive withdrawals.
    ///         Acts as a rate-limiting cooldown to slow token drainage.
    uint256 public constant WAITING_PERIOD = 15 days;

    // ─────────────────────────────────────────────
    // State
    // ─────────────────────────────────────────────

    /// @dev Timestamp of the most recent successful withdrawal.
    ///      Initialized to deployment time so the first withdrawal cannot happen
    ///      until at least WAITING_PERIOD after deployment.
    ///      Private — exposed via `getLastWithdrawalTimestamp()`.
    uint256 private _lastWithdrawalTimestamp = block.timestamp;

    // ─────────────────────────────────────────────
    // Errors
    // ─────────────────────────────────────────────

    /// @dev Thrown by `_beforeFunctionCall` when the execute() target is not this vault.
    ///      Prevents the vault's executor permissions from being weaponized against
    ///      other contracts.
    error TargetNotAllowed();

    /// @dev Thrown by `onlyThis` when a sensitive function is called directly
    ///      (i.e. not relayed through execute()).
    error CallerNotAllowed();

    /// @dev Thrown when the requested withdrawal amount exceeds WITHDRAWAL_LIMIT.
    error InvalidWithdrawalAmount();

    /// @dev Thrown when withdraw() is called before the cooldown window has elapsed.
    error WithdrawalWaitingPeriodNotEnded();

    // ─────────────────────────────────────────────
    // Modifiers
    // ─────────────────────────────────────────────

    /**
     * @dev Restricts a function so it can only be invoked when msg.sender is the
     *      vault contract itself. In practice this means the call must have been
     *      routed through AuthorizedExecutor.execute(), which performs:
     *        target.functionCall(actionData)  →  address(this).call(actionData)
     *      making msg.sender == address(this) from the callee's perspective.
     *
     *      Direct external calls will always fail this check because an EOA or
     *      another contract can never spoof msg.sender to equal address(this).
     */
    modifier onlyThis() {
        if (msg.sender != address(this)) {
            revert CallerNotAllowed();
        }
        _;
    }

    // ─────────────────────────────────────────────
    // External functions
    // ─────────────────────────────────────────────

    /**
     * @notice Transfers a limited amount of `token` to `recipient`.
     * @dev    Rate-limited by two independent guards:
     *           1. Amount cap  — amount must be ≤ WITHDRAWAL_LIMIT (1 ether).
     *           2. Time lock   — at least WAITING_PERIOD (15 days) must have passed
     *                            since the last successful withdrawal.
     *         Both checks must pass; otherwise the transaction reverts.
     *         On success, `_lastWithdrawalTimestamp` is updated to now, resetting
     *         the cooldown clock.
     *
     *         Only callable via execute() due to `onlyThis`.
     *
     * @param token     ERC-20 token contract address to withdraw from.
     * @param recipient Destination address that receives the tokens.
     * @param amount    Number of token units (in the token's own decimals) to send.
     */
    function withdraw(address token, address recipient, uint256 amount) external onlyThis {
        // Guard 1: enforce the per-withdrawal token amount cap.
        if (amount > WITHDRAWAL_LIMIT) {
            revert InvalidWithdrawalAmount();
        }

        // Guard 2: enforce the cooldown period between withdrawals.
        // Uses <= so that a call at the exact expiry timestamp is still rejected;
        // the block must be strictly after the deadline.
        if (block.timestamp <= _lastWithdrawalTimestamp + WAITING_PERIOD) {
            revert WithdrawalWaitingPeriodNotEnded();
        }

        // Reset the cooldown clock BEFORE the transfer (checks-effects-interactions).
        _lastWithdrawalTimestamp = block.timestamp;

        // SafeTransferLib reverts on failure (including tokens that return false
        // instead of reverting), protecting against non-standard ERC-20 tokens.
        SafeTransferLib.safeTransfer(token, recipient, amount);
    }

    /**
     * @notice Drains the vault's entire balance of `token` to `receiver`.
     * @dev    No amount cap or time lock — this is an emergency/admin sweep meant
     *         to be called only by a fully authorized party.
     *         Only callable via execute() due to `onlyThis`.
     *
     *         Because there are no rate limits here, an attacker who obtains
     *         a valid permission for this selector can empty the vault in one call.
     *         This is the primary target in the CTF challenge.
     *
     * @param receiver Destination address for all drained tokens.
     * @param token    ERC-20 token whose full vault balance is swept.
     */
    function sweepFunds(address receiver, IERC20 token) external onlyThis {
        // Reads the vault's own token balance and transfers everything in one shot.
        // `token.balanceOf(address(this))` is evaluated first; if it returns 0
        // the transfer is a no-op (SafeTransferLib still succeeds).
        SafeTransferLib.safeTransfer(address(token), receiver, token.balanceOf(address(this)));
    }

    /**
     * @notice Returns the timestamp of the most recent successful withdrawal.
     * @dev    Useful off-chain for computing when the next withdrawal becomes available:
     *           nextAllowed = getLastWithdrawalTimestamp() + WAITING_PERIOD
     * @return Unix timestamp (seconds) of the last withdrawal, or deployment time
     *         if no withdrawal has occurred yet.
     */
    function getLastWithdrawalTimestamp() external view returns (uint256) {
        return _lastWithdrawalTimestamp;
    }

    // ─────────────────────────────────────────────
    // Internal overrides
    // ─────────────────────────────────────────────

    /**
     * @dev Pre-execution hook required by AuthorizedExecutor.
     *      Called inside execute() before the external call is forwarded.
     *
     *      This implementation enforces a hard rule: the vault may only call *itself*.
     *      If `target` is any address other than address(this), the entire execute()
     *      transaction is reverted.
     *
     *      Why this matters:
     *        Without this check, a permission holder could use the vault as a relay
     *        to call arbitrary contracts (e.g. token.transfer(attacker, balance)),
     *        turning the vault into a general-purpose proxy. Restricting target to
     *        address(this) means the only reachable functions are withdraw() and
     *        sweepFunds(), both of which are further protected by `onlyThis`.
     *
     * @param target     The address execute() intends to call — must equal address(this).
     *                   The `actionData` parameter is intentionally unnamed/unused here.
     */
    function _beforeFunctionCall(address target, bytes memory) internal view override {
        // Revert immediately if someone attempts to point execute() at a foreign contract.
        if (target != address(this)) {
            revert TargetNotAllowed();
        }
    }
}
