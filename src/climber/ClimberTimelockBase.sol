// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

// ─────────────────────────────────────────────
// IMPORTS
// ─────────────────────────────────────────────

// AccessControl: Role-based permission system from OpenZeppelin.
// Provides `hasRole()`, `grantRole()`, `revokeRole()`, and the `onlyRole()` modifier.
// Roles are identified by bytes32 constants (e.g., keccak256("ADMIN_ROLE")).
// This replaces simple Ownable with multi-role governance suited for a timelock.
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

// ─────────────────────────────────────────────
// CONTRACT
// ─────────────────────────────────────────────

/**
 * @title  ClimberTimelockBase
 * @notice Abstract base contract for the ClimberTimelock.
 *         Defines the shared data structures, state, and read-only logic
 *         used by the concrete timelock implementation.
 *
 * WHAT IS A TIMELOCK?
 * A timelock is a governance safety mechanism:
 *  1. A privileged proposer SCHEDULES an operation (targets + calldata + salt).
 *  2. The operation enters a waiting period (`delay` seconds).
 *  3. After the delay, anyone (or a specific executor) can EXECUTE it.
 *
 * This pattern prevents sudden unilateral changes — observers have a window
 * to react (exit, veto, etc.) before any scheduled action takes effect.
 *
 * ROLE MODEL (inherited from AccessControl)
 * ┌───────────────┬──────────────────────────────────────────────────┐
 * │ Role          │ Capability                                        │
 * ├───────────────┼──────────────────────────────────────────────────┤
 * │ ADMIN_ROLE    │ Grant/revoke roles, update delay                  │
 * │ PROPOSER_ROLE │ Schedule new operations                           │
 * └───────────────┴──────────────────────────────────────────────────┘
 *
 * @dev Abstract — cannot be deployed directly.
 *      Concrete child (ClimberTimelock) implements schedule() and execute().
 */
abstract contract ClimberTimelockBase is AccessControl {

    // ─────────────────────────────────────────
    // TYPES
    // ─────────────────────────────────────────

    /**
     * @notice All possible lifecycle states of a scheduled operation.
     *
     * STATE MACHINE
     *
     *   [not registered]
     *         │  schedule() called
     *         ▼
     *      Unknown ──► Scheduled ──► ReadyForExecution ──► Executed
     *                  (waiting)      (delay elapsed)      (ran once)
     *
     * - Unknown:            Operation ID has never been scheduled.
     *                       `known == false` in storage.
     * - Scheduled:          Operation is registered but `block.timestamp`
     *                       has not yet reached `readyAtTimestamp`.
     * - ReadyForExecution:  Delay has elapsed; execute() may now be called.
     * - Executed:           execute() has already run; cannot run again.
     */
    enum OperationState {
        Unknown,            // Default (zero) value — operation does not exist
        Scheduled,          // Registered, delay not yet elapsed
        ReadyForExecution,  // Delay elapsed, awaiting execution
        Executed            // Already executed — terminal state
    }

    /**
     * @notice Metadata stored on-chain for each scheduled operation.
     *
     * PACKING NOTE:
     * `readyAtTimestamp` (uint64) + `known` (bool) + `executed` (bool)
     * all fit within a single 32-byte EVM storage slot — gas-efficient.
     *
     * FIELDS
     * - readyAtTimestamp: Unix timestamp after which execution is permitted.
     *                     Computed as: `block.timestamp + delay` at schedule time.
     * - known:            True once the operation has been scheduled.
     *                     Distinguishes "never seen" from "scheduled but not ready".
     * - executed:         True after a successful execute() call.
     *                     Prevents replay — an executed operation cannot run again.
     */
    struct Operation {
        uint64 readyAtTimestamp;  // Earliest execution time (schedule time + delay)
        bool known;               // Has this operation been registered?
        bool executed;            // Has this operation already been executed?
    }

    // ─────────────────────────────────────────
    // STATE VARIABLES
    // ─────────────────────────────────────────

    /**
     * @notice Registry of all known operations, keyed by their unique ID.
     *
     * KEY:   bytes32 operation ID — deterministic hash of (targets, values, data, salt).
     *        See `getOperationId()` for the exact encoding.
     * VALUE: Operation struct with lifecycle metadata.
     *
     * @dev Public — callers can read raw struct fields directly,
     *      or use `getOperationState()` for the interpreted enum state.
     *
     * ⚠️ SECURITY: Once `executed = true`, the operation is permanently
     *    blocked from re-execution. Never delete entries from this mapping.
     */
    mapping(bytes32 => Operation) public operations;

    /**
     * @notice Minimum number of seconds that must elapse between scheduling
     *         and executing an operation.
     *
     * @dev Stored as uint64 to pack with other small values if needed.
     *      Initialized in the concrete child constructor.
     *      Can typically be updated by ADMIN_ROLE via a scheduled operation
     *      (i.e., changing the delay itself is subject to the current delay).
     *
     * ⚠️ Setting delay = 0 effectively disables the timelock guarantee —
     *    schedule and execute become atomically composable in one transaction.
     *    This is the core vulnerability exploited in the Climber challenge.
     */
    uint64 public delay;

    // ─────────────────────────────────────────
    // VIEW FUNCTIONS
    // ─────────────────────────────────────────

    /**
     * @notice Returns the current lifecycle state of an operation.
     *
     * @param id  The bytes32 operation ID (from `getOperationId()`).
     * @return state  One of: Unknown, Scheduled, ReadyForExecution, Executed.
     *
     * DECISION TREE
     *  known == false          → Unknown
     *  known == true
     *    executed == true      → Executed
     *    block.timestamp < readyAtTimestamp → Scheduled
     *    otherwise             → ReadyForExecution
     *
     * @dev Reads from memory copy of storage struct — no state changes.
     *      Safe to call at any time; used by execute() to gate execution.
     */
    function getOperationState(bytes32 id) public view returns (OperationState state) {
        // Load the full Operation struct from storage into a memory copy.
        // Memory read is cheaper for multiple field accesses than repeated SLOAD.
        Operation memory op = operations[id];

        if (op.known) {
            // Operation has been scheduled at some point — determine sub-state.

            if (op.executed) {
                // Terminal state: operation ran successfully, cannot re-run.
                state = OperationState.Executed;

            } else if (block.timestamp < op.readyAtTimestamp) {
                // Still within the mandatory waiting period.
                // `block.timestamp` is miner-influenceable by ~15s, but delay
                // periods are typically hours/days, so this is acceptable.
                state = OperationState.Scheduled;

            } else {
                // Delay has fully elapsed — execution is now permitted.
                state = OperationState.ReadyForExecution;
            }

        } else {
            // Operation ID has never been seen by this contract.
            // Either not yet scheduled, or an invalid/wrong ID was passed.
            state = OperationState.Unknown;
        }
    }

    /**
     * @notice Computes the unique deterministic ID for a batch operation.
     *
     * @param targets      Ordered list of contract addresses to call.
     * @param values       Ordered list of ETH values (wei) for each call.
     * @param dataElements Ordered list of encoded calldata for each call.
     * @param salt         Arbitrary bytes32 to allow identical batches to
     *                     have distinct IDs (prevents ID collision).
     * @return             bytes32 keccak256 hash uniquely identifying this operation.
     *
     * ID PROPERTIES
     * - Deterministic: same inputs → same ID, always.
     * - Collision-resistant: different batches produce different IDs
     *   (assuming different salt or content).
     * - Binding: ID commits to the EXACT calldata — executing with any
     *   modification produces a different ID and will revert.
     *
     * SALT USES
     * - Re-scheduling the same logical operation a second time (use different salt).
     * - Human-readable tagging (e.g., salt = keccak256("upgrade-v2")).
     *
     * @dev Uses `abi.encode` (not `encodePacked`) to avoid hash collisions
     *      caused by ambiguous length boundaries in dynamic array encoding.
     *      Pure — no storage reads; safe to call off-chain for ID pre-computation.
     */
    function getOperationId(
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata dataElements,
        bytes32 salt
    ) public pure returns (bytes32) {
        // keccak256 over ABI-encoded tuple:
        // (address[], uint256[], bytes[], bytes32)
        // The resulting hash is used as the key in the `operations` mapping.
        return keccak256(abi.encode(targets, values, dataElements, salt));
    }

    // ─────────────────────────────────────────
    // ETHER HANDLING
    // ─────────────────────────────────────────

    /**
     * @notice Allows the timelock to receive plain ETH transfers.
     *
     * WHY NEEDED:
     * Scheduled operations may include ETH-valued calls (values[i] > 0).
     * The timelock must hold ETH to forward it during execute().
     * Without this, any direct ETH send (e.g., from a vault withdrawal
     * routed through the timelock) would revert.
     *
     * @dev Empty body — no logic, just marks the contract as ETH-receivable.
     *      Does NOT emit an event; add one in a child override if tracking is needed.
     */
    receive() external payable {}
}
