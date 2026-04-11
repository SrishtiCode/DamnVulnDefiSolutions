// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

// ─────────────────────────────────────────────
// IMPORTS
// ─────────────────────────────────────────────

// Address: OpenZeppelin utility library for address-related helpers.
// Used here specifically for `functionCallWithValue()` — a safe low-level
// call wrapper that forwards ETH value and reverts with the original revert
// reason if the call fails (unlike raw `.call{value:}()`).
import {Address} from "@openzeppelin/contracts/utils/Address.sol";

// Abstract base: defines Operation struct, OperationState enum,
// `operations` mapping, `delay` variable, `getOperationState()`,
// and `getOperationId()`. See ClimberTimelockBase.sol.
import {ClimberTimelockBase} from "./ClimberTimelockBase.sol";

// Compile-time constants:
// ADMIN_ROLE    — bytes32 role ID for administrators (can manage roles, update delay)
// PROPOSER_ROLE — bytes32 role ID for proposers (can call schedule())
// MAX_TARGETS   — upper bound on calls per batch (prevents gas-limit DoS)
// MIN_TARGETS   — lower bound on calls per batch (currently 0, prevents empty batches)
// MAX_DELAY     — ceiling on `delay` value (prevents timelock being set to infinity)
import {ADMIN_ROLE, PROPOSER_ROLE, MAX_TARGETS, MIN_TARGETS, MAX_DELAY} from "./ClimberConstants.sol";

// Custom revert errors (gas-efficient vs. revert strings):
// InvalidTargetsCount     — batch target array length is out of [MIN, MAX) range
// InvalidDataElementsCount — dataElements length != targets length
// InvalidValuesCount      — values length != targets length
// OperationAlreadyKnown   — operation ID already exists in the registry
// NotReadyForExecution    — operation state is not ReadyForExecution at end of execute()
// CallerNotTimelock       — updateDelay() caller is not address(this)
// NewDelayAboveMax        — proposed delay exceeds MAX_DELAY constant
import {
    InvalidTargetsCount,
    InvalidDataElementsCount,
    InvalidValuesCount,
    OperationAlreadyKnown,
    NotReadyForExecution,
    CallerNotTimelock,
    NewDelayAboveMax
} from "./ClimberErrors.sol";

// ─────────────────────────────────────────────
// CONTRACT
// ─────────────────────────────────────────────

/**
 * @title  ClimberTimelock
 * @notice Concrete timelock implementation for the Climber vault system.
 *         Governs all privileged vault actions through a schedule → wait → execute flow.
 *
 * STANDARD TIMELOCK FLOW
 *
 *   [PROPOSER]                 [delay elapses]            [anyone]
 *       │                            │                        │
 *   schedule(targets,            (on-chain,              execute(targets,
 *    values, data, salt)          automatic)               values, data, salt)
 *       │                            │                        │
 *       ▼                            ▼                        ▼
 *   op.known = true        op becomes ReadyForExecution   calls forwarded,
 *   op.readyAtTimestamp                                   op.executed = true
 *    = now + delay
 *
 * ⚠️ CRITICAL VULNERABILITY (the "Climber" challenge)
 * `execute()` forwards all calls BEFORE checking operation state.
 * This means a batch can include a call that sets delay = 0 and schedules
 * itself — by the time the state check runs, the operation is already
 * ReadyForExecution. The timelock delay guarantee is completely bypassed.
 *
 * SELF-ADMINISTRATION
 * The timelock grants ADMIN_ROLE to itself (`address(this)`).
 * This means role changes and delay updates must go through the timelock's
 * own execute() — no single EOA can unilaterally alter the governance config.
 *
 * @dev Inherits ClimberTimelockBase (AccessControl + Operation registry).
 *      Uses OpenZeppelin's Address library for safe low-level calls.
 */
contract ClimberTimelock is ClimberTimelockBase {

    // Attach Address library methods to the `address` type.
    // Enables: `targets[i].functionCallWithValue(data, value)`
    using Address for address;

    // ─────────────────────────────────────────
    // CONSTRUCTOR
    // ─────────────────────────────────────────

    /**
     * @notice Bootstraps roles and sets the initial timelock delay.
     *
     * @param admin    Address granted ADMIN_ROLE. Can manage all roles
     *                 and schedule delay changes via the timelock queue.
     * @param proposer Address granted PROPOSER_ROLE. Can call schedule()
     *                 to register new operations.
     *
     * ROLE HIERARCHY SETUP
     * ┌────────────────┬────────────────────────────────────────────────┐
     * │ Action         │ Effect                                          │
     * ├────────────────┼────────────────────────────────────────────────┤
     * │ setRoleAdmin   │ ADMIN_ROLE manages itself (self-admin)          │
     * │ setRoleAdmin   │ ADMIN_ROLE manages PROPOSER_ROLE                │
     * │ grantRole      │ `admin` param receives ADMIN_ROLE               │
     * │ grantRole      │ address(this) receives ADMIN_ROLE (self-admin)  │
     * │ grantRole      │ `proposer` param receives PROPOSER_ROLE         │
     * └────────────────┴────────────────────────────────────────────────┘
     *
     * Self-granting ADMIN_ROLE to address(this) is intentional:
     * it ensures role management must go through the timelock queue itself,
     * preventing any single EOA from unilaterally revoking roles or
     * granting themselves proposer access.
     *
     * Initial delay = 1 hour. Long enough to observe scheduled operations,
     * short enough for practical vault management.
     */
    constructor(address admin, address proposer) {
        // Make ADMIN_ROLE its own role admin — only admins can grant/revoke ADMIN_ROLE.
        _setRoleAdmin(ADMIN_ROLE, ADMIN_ROLE);

        // Make ADMIN_ROLE the admin of PROPOSER_ROLE — only admins can grant/revoke proposers.
        _setRoleAdmin(PROPOSER_ROLE, ADMIN_ROLE);

        // Grant the external admin address full admin rights.
        _grantRole(ADMIN_ROLE, admin);

        // Grant the timelock contract itself admin rights.
        // Consequence: role changes must be executed through schedule() + execute(),
        // enforcing the timelock delay on governance actions.
        _grantRole(ADMIN_ROLE, address(this));

        // Grant proposer the right to schedule new operations.
        _grantRole(PROPOSER_ROLE, proposer);

        // Set initial delay. Operations scheduled at t=0 are executable at t=3600.
        delay = 1 hours;
    }

    // ─────────────────────────────────────────
    // PROPOSER FUNCTIONS
    // ─────────────────────────────────────────

    /**
     * @notice Registers a new batch operation in the timelock queue.
     *
     * @param targets      Ordered addresses of contracts to call during execution.
     * @param values       Ordered ETH values (wei) to forward with each call.
     * @param dataElements Ordered ABI-encoded calldata for each call.
     * @param salt         Arbitrary bytes32 to differentiate otherwise identical batches.
     *
     * VALIDATIONS (in order)
     * 1. Batch size within [MIN_TARGETS+1, MAX_TARGETS) — prevents empty/oversized batches.
     * 2. values.length == targets.length  — prevents index mismatch during execute().
     * 3. dataElements.length == targets.length — same reason.
     * 4. Operation ID must be Unknown — no double-scheduling.
     *
     * ON SUCCESS
     * - Computes a deterministic ID from the batch content + salt.
     * - Sets `readyAtTimestamp = block.timestamp + delay`.
     * - Marks operation as `known = true`.
     * - Does NOT emit an event — consider adding one for off-chain monitoring.
     *
     * @dev Restricted to PROPOSER_ROLE via `onlyRole` from AccessControl.
     *      Note the off-by-one in the bounds check:
     *      `targets.length == MIN_TARGETS` (not `<`) triggers the revert,
     *      meaning exactly MIN_TARGETS calls is also rejected (empty batch guard).
     */
    function schedule(
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata dataElements,
        bytes32 salt
    ) external onlyRole(PROPOSER_ROLE) {

        // Reject batches that are empty (== MIN_TARGETS) or too large (>= MAX_TARGETS).
        // Valid range: (MIN_TARGETS, MAX_TARGETS) exclusive on both ends.
        if (targets.length == MIN_TARGETS || targets.length >= MAX_TARGETS) {
            revert InvalidTargetsCount();
        }

        // Each target must have a corresponding ETH value, even if zero.
        if (targets.length != values.length) {
            revert InvalidValuesCount();
        }

        // Each target must have corresponding calldata, even if empty bytes.
        if (targets.length != dataElements.length) {
            revert InvalidDataElementsCount();
        }

        // Compute the deterministic operation ID from full batch content.
        // Any modification to targets/values/data/salt produces a different ID.
        bytes32 id = getOperationId(targets, values, dataElements, salt);

        // Prevent re-scheduling an operation that is already known.
        // Covers: Scheduled, ReadyForExecution, and Executed states.
        // To re-run the same logic, use a different salt.
        if (getOperationState(id) != OperationState.Unknown) {
            revert OperationAlreadyKnown(id);
        }

        // Record execution window: callable only after `delay` seconds have passed.
        // uint64 cast is safe — block.timestamp won't overflow uint64 for ~500B years.
        operations[id].readyAtTimestamp = uint64(block.timestamp) + delay;

        // Mark as known so future schedule() calls with the same ID are rejected.
        operations[id].known = true;
    }

    // ─────────────────────────────────────────
    // EXECUTION
    // ─────────────────────────────────────────

    /**
     * @notice Executes a previously scheduled batch operation.
     *
     * @param targets      Must exactly match what was passed to schedule().
     * @param values       Must exactly match what was passed to schedule().
     * @param dataElements Must exactly match what was passed to schedule().
     * @param salt         Must exactly match what was passed to schedule().
     *
     * EXECUTION FLOW
     * 1. Validate array lengths.
     * 2. Recompute operation ID from parameters.
     * 3. Forward each call via `functionCallWithValue()`.   ← ⚠️ BEFORE state check
     * 4. Assert operation is now ReadyForExecution.         ← state check happens HERE
     * 5. Mark operation as executed.
     *
     * ⚠️ CRITICAL VULNERABILITY — CHECKS AFTER EFFECTS
     * The state check (step 4) occurs AFTER all calls have already been
     * forwarded (step 3). This violates the Checks-Effects-Interactions pattern
     * and enables the following exploit:
     *
     *   Craft a batch that, when executed, calls:
     *     a) timelock.updateDelay(0)         → sets delay to 0
     *     b) timelock.schedule(thisBatch)    → schedules this very batch
     *                                          (now readyAt = now + 0 = now)
     *     c) vault.transferOwnership(...)    → or any other privileged action
     *
     *   By the time step 4 runs, the batch has scheduled itself with delay=0,
     *   so its state IS ReadyForExecution — the check passes. The timelock
     *   delay guarantee is entirely bypassed in a single transaction.
     *
     * @dev Callable by anyone (no role restriction) — the operation state
     *      check is the sole execution gate (and it's broken as noted above).
     *      Marked `payable` so the caller can supply ETH for value-forwarding calls.
     */
    function execute(
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata dataElements,
        bytes32 salt
    ) external payable {

        // Reject batches that are empty or too large (same bounds as schedule()).
        if (targets.length <= MIN_TARGETS) {
            revert InvalidTargetsCount();
        }

        // Array length consistency checks — prevent index-out-of-bounds during the loop.
        if (targets.length != values.length) {
            revert InvalidValuesCount();
        }

        if (targets.length != dataElements.length) {
            revert InvalidDataElementsCount();
        }

        // Compute the operation ID. Must match what was registered in schedule().
        // Any parameter mismatch → different ID → NotReadyForExecution revert.
        bytes32 id = getOperationId(targets, values, dataElements, salt);

        // ⚠️ VULNERABILITY: All external calls happen HERE, before state validation.
        // Each call is forwarded with its corresponding ETH value via OpenZeppelin's
        // `functionCallWithValue`, which:
        //   - Reverts with the original error if the target reverts.
        //   - Reverts if this contract has insufficient ETH balance for the value.
        //   - Does NOT protect against reentrancy into this contract.
        for (uint8 i = 0; i < targets.length; ++i) {
            targets[i].functionCallWithValue(dataElements[i], values[i]);
        }

        // State check occurs AFTER all calls — too late to prevent the exploit.
        // In a correct implementation this check should precede the call loop.
        if (getOperationState(id) != OperationState.ReadyForExecution) {
            revert NotReadyForExecution(id);
        }

        // Mark as executed — prevents replay of this exact operation.
        // Terminal state: `getOperationState()` will now return Executed forever.
        operations[id].executed = true;
    }

    // ─────────────────────────────────────────
    // ADMIN FUNCTIONS
    // ─────────────────────────────────────────

    /**
     * @notice Updates the mandatory delay between scheduling and execution.
     *
     * @param newDelay New delay in seconds. Must not exceed MAX_DELAY.
     *
     * ACCESS CONTROL — Self-call only
     * Restricted to `address(this)` — meaning this function can ONLY be
     * invoked as one of the calls forwarded inside execute(). It cannot
     * be called directly by any EOA or external contract.
     *
     * WHY SELF-CALL?
     * Ensures that changing the delay is itself subject to the current delay.
     * An admin cannot instantly reduce the delay — they must schedule the
     * updateDelay() call and wait out the existing delay period first.
     *
     * ⚠️ EXPLOIT INTERACTION:
     * Because execute() checks state AFTER forwarding calls, an attacker
     * can include updateDelay(0) as the first call in a malicious batch.
     * By the time the state check runs, delay is already 0 — allowing
     * the batch to self-schedule with immediate readyAtTimestamp.
     *
     * @dev Does NOT emit an event — consider adding one for auditability.
     *      Setting newDelay = 0 is valid (within MAX_DELAY) and fully
     *      disables the timelock protection.
     */
    function updateDelay(uint64 newDelay) external {
        // Enforce self-call restriction — only executable via the timelock's own execute().
        if (msg.sender != address(this)) {
            revert CallerNotTimelock();
        }

        // Enforce upper bound — prevents delay being set to an impractically
        // large value that would permanently freeze the timelock.
        if (newDelay > MAX_DELAY) {
            revert NewDelayAboveMax();
        }

        // Update the shared delay storage variable (defined in ClimberTimelockBase).
        // Takes effect immediately for all future schedule() calls.
        delay = newDelay;
    }
}
