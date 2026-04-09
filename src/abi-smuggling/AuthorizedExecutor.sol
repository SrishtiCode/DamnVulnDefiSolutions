// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";

/**
 * @title AuthorizedExecutor
 * @dev Abstract base contract that provides permission-controlled execution of arbitrary
 *      function calls on external contracts. Inheriting contracts must implement
 *      `_beforeFunctionCall` to add any pre-execution logic (e.g. logging, validation).
 *
 *      Permissions are set ONCE by the first caller of `setPermissions`, making
 *      initialization a one-shot, first-come-first-served operation.
 *
 * Security properties:
 *  - ReentrancyGuard prevents re-entrant calls into `execute`.
 *  - Permission keys are scoped to (selector, executor, target) so the same
 *    function cannot be called on a different target or by a different caller.
 */
abstract contract AuthorizedExecutor is ReentrancyGuard {

    // Brings in functionCall(), functionCallWithValue(), etc. for address types.
    using Address for address;

    // ─────────────────────────────────────────────
    // State
    // ─────────────────────────────────────────────

    /// @notice Becomes true after the first call to `setPermissions`, permanently
    ///         locking the permission table against further changes.
    bool public initialized;

    /// @notice Maps an action identifier → whether that action is permitted.
    ///         An action identifier encodes (function selector, executor address, target address),
    ///         so permission is granted per (who can call, what function, on which contract).
    mapping(bytes32 => bool) public permissions;

    // ─────────────────────────────────────────────
    // Errors  (custom errors are cheaper than revert strings)
    // ─────────────────────────────────────────────

    /// @dev Thrown when `execute` is called for an action that has no permission entry.
    error NotAllowed();

    /// @dev Thrown when `setPermissions` is called after initialization has already occurred.
    error AlreadyInitialized();

    // ─────────────────────────────────────────────
    // Events
    // ─────────────────────────────────────────────

    /// @notice Emitted once when permissions are first configured.
    /// @param who   The address that called `setPermissions`.
    /// @param ids   The list of action identifiers that were enabled.
    event Initialized(address who, bytes32[] ids);

    // ─────────────────────────────────────────────
    // External functions
    // ─────────────────────────────────────────────

    /**
     * @notice One-time setup: whitelists a set of action identifiers.
     * @dev    Can only be called once — whoever calls first "owns" the permission table.
     *         There is NO access control on who may call this, so inheriting contracts
     *         should expose their own initializer or call this in their constructor
     *         before any untrusted party can.
     * @param ids Array of action identifiers to enable (see `getActionId`).
     */
    function setPermissions(bytes32[] memory ids) external {
        // Prevent a second initialization attempt.
        if (initialized) {
            revert AlreadyInitialized();
        }

        // Grant permission for every supplied action identifier.
        // `unchecked` is safe here because ids.length can never realistically
        // overflow a uint256, saving a small amount of gas on the counter.
        for (uint256 i = 0; i < ids.length;) {
            unchecked {
                permissions[ids[i]] = true;
                ++i; // prefix increment is slightly cheaper than i++
            }
        }

        // Lock the contract — no further permission changes are possible.
        initialized = true;

        emit Initialized(msg.sender, ids);
    }

    /**
     * @notice Executes an arbitrary call on `target`, but only if the caller holds
     *         the required permission for that (selector, caller, target) triple.
     * @dev    Steps:
     *           1. Extract the 4-byte function selector from `actionData` via assembly.
     *           2. Derive the action identifier and check the permission mapping.
     *           3. Call the optional pre-execution hook `_beforeFunctionCall`.
     *           4. Forward the calldata to `target` using OpenZeppelin's `functionCall`.
     *
     *         Assembly note — why `calldataOffset = 4 + 32 * 3`?
     *           The raw calldata layout for this function is:
     *             [0..3]    selector of execute()          — 4 bytes
     *             [4..35]   address target (padded)        — 32 bytes
     *             [36..67]  offset pointer to actionData   — 32 bytes
     *             [68..99]  length of actionData           — 32 bytes
     *             [100..]   actionData content             ← selector lives here
     *           So byte 100 (= 4 + 96) is where actionData's own 4-byte selector starts.
     *
     * @param target     The contract to call.
     * @param actionData ABI-encoded calldata (including selector) to forward to `target`.
     * @return           The raw bytes returned by the target call.
     */
    function execute(address target, bytes calldata actionData)
        external
        nonReentrant   // Prevents re-entrant calls, guarding against callback attacks.
        returns (bytes memory)
    {
        // ── Step 1: extract the selector from actionData using inline assembly ──
        bytes4 selector;

        // Offset (in bytes) within the full transaction calldata where actionData begins.
        // Breakdown: 4 (execute selector) + 32 (target) + 32 (offset ptr) + 32 (length) = 100
        uint256 calldataOffset = 4 + 32 * 3;

        assembly {
            // `calldataload` reads 32 bytes from calldata starting at `calldataOffset`.
            // Assigning to `bytes4` automatically keeps only the leftmost 4 bytes.
            selector := calldataload(calldataOffset)
        }

        // ── Step 2: permission check ──
        // Build the action identifier and revert if the caller is not authorised.
        if (!permissions[getActionId(selector, msg.sender, target)]) {
            revert NotAllowed();
        }

        // ── Step 3: pre-execution hook (implemented by child contract) ──
        _beforeFunctionCall(target, actionData);

        // ── Step 4: forward the call ──
        // `functionCall` reverts with the target's revert reason if the call fails,
        // and bubbles up the return data on success.
        return target.functionCall(actionData);
    }

    // ─────────────────────────────────────────────
    // Internal hooks
    // ─────────────────────────────────────────────

    /**
     * @dev Hook called inside `execute` right before the external call is made.
     *      Inheriting contracts override this to add custom logic such as
     *      event emission, balance snapshots, or additional validation.
     * @param target     The address that will be called.
     * @param actionData The calldata that will be forwarded.
     */
    function _beforeFunctionCall(address target, bytes memory actionData) internal virtual;

    // ─────────────────────────────────────────────
    // Pure helpers
    // ─────────────────────────────────────────────

    /**
     * @notice Derives a unique action identifier from a (selector, executor, target) triple.
     * @dev    Hashing all three components together means:
     *           • The same function on a different target requires a separate permission.
     *           • The same function called by a different address requires a separate permission.
     *         This scoping prevents privilege escalation across addresses or contracts.
     * @param selector  4-byte function selector of the action being authorised.
     * @param executor  Address of the account that will call `execute`.
     * @param target    Address of the contract on which the action will be performed.
     * @return          keccak256 hash used as the permission map key.
     */
    function getActionId(bytes4 selector, address executor, address target)
        public
        pure
        returns (bytes32)
    {
        // `abi.encodePacked` produces a tight (no padding) byte sequence before hashing,
        // which is fine here because all three components have fixed sizes.
        return keccak256(abi.encodePacked(selector, executor, target));
    }
}
