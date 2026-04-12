// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {Ownable} from "solady/auth/Ownable.sol";
import {L1Gateway} from "./L1Gateway.sol";

/**
 * @title L1Forwarder
 * @notice Receives cross-chain messages from L2 (via L1Gateway) and forwards
 *         them to their intended target contracts on L1.
 * @dev Two execution paths exist:
 *        1. FIRST ATTEMPT  — called by the L1Gateway (authenticated L2 message).
 *           Reverts if the message has already failed (no double-processing).
 *        2. RETRY ATTEMPT  — called by anyone after a first attempt failed.
 *           Reverts if the message has NOT previously failed (no unsolicited retries).
 *      In both cases a successful delivery is recorded so it can never be replayed.
 *      Inherits ReentrancyGuard to block re-entrant calls through the low-level
 *      `call` performed inside forwardMessage.
 */
contract L1Forwarder is ReentrancyGuard, Ownable {
    using Address for address;

    // -------------------------------------------------------------------------
    // State
    // -------------------------------------------------------------------------

    /// @notice Tracks messages that were successfully forwarded to their target.
    /// @dev Keyed by the deterministic messageId. Once true, the message can
    ///      never be forwarded again (replay protection).
    mapping(bytes32 messageId => bool seen) public successfulMessages;

    /// @notice Tracks messages whose low-level call to the target reverted.
    /// @dev Keyed by the same deterministic messageId. A failed message may be
    ///      retried by anyone via forwardMessage (permissionless retry path).
    mapping(bytes32 messageId => bool seen) public failedMessages;

    /// @notice The L1Gateway contract authorised to deliver first-attempt messages.
    L1Gateway public gateway;

    /// @notice The L2 contract address whose messages the gateway is allowed to relay.
    /// @dev Only messages originating from this address on L2 pass the first-attempt
    ///      authentication check.
    address public l2Handler;

    // -------------------------------------------------------------------------
    // Transient context (set/restored around every forwarded call)
    // -------------------------------------------------------------------------

    /**
     * @notice Holds the original L2 sender for the duration of a forwarded call.
     * @dev Written before the low-level call so that the target contract can read
     *      it back via getSender(). Restored to the previous value afterwards to
     *      support nested/re-entrant context correctly (though re-entrancy is
     *      blocked by the nonReentrant modifier at the outer level).
     */
    struct Context {
        address l2Sender;
    }

    /// @dev Global context slot. Only meaningful while forwardMessage is executing.
    Context public context;

    // -------------------------------------------------------------------------
    // Errors
    // -------------------------------------------------------------------------

    /// @notice Thrown when trying to forward a message that already succeeded.
    error AlreadyForwarded(bytes32 messageId);

    /// @notice Thrown when the target is this contract or the gateway itself,
    ///         which would allow privilege escalation.
    error BadTarget();

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    /**
     * @param _gateway The L1Gateway contract that will deliver authenticated
     *                 cross-chain messages to this forwarder.
     */
    constructor(L1Gateway _gateway) {
        _initializeOwner(msg.sender);
        gateway = _gateway;
    }

    // -------------------------------------------------------------------------
    // Admin
    // -------------------------------------------------------------------------

    /**
     * @notice Sets the L2 address whose messages the gateway is trusted to relay.
     * @dev Only the owner can update this. Changing it mid-flight could affect
     *      in-flight messages, so should be done with care.
     * @param _l2Handler The L2 contract address to authorise.
     */
    function setL2Handler(address _l2Handler) external onlyOwner {
        l2Handler = _l2Handler;
    }

    // -------------------------------------------------------------------------
    // Core forwarding logic
    // -------------------------------------------------------------------------

    /**
     * @notice Forwards a cross-chain message to its L1 target.
     *
     * @dev MESSAGE ID
     *      A deterministic ID is derived by hashing the ABI-encoded call
     *      signature together with all four parameters. This ties the ID to the
     *      exact content of the message, making spoofing or collision attacks
     *      computationally infeasible.
     *
     * @dev AUTHORISATION (two paths)
     *      PATH A – first attempt (msg.sender == gateway AND gateway.xSender() == l2Handler):
     *        • The call is authenticated: it originates from the known gateway
     *          relaying a message from the trusted L2 handler.
     *        • Reverts if the message has already been marked failed, preventing
     *          an attacker from forcing a re-run of a message that was already tried.
     *
     *      PATH B – retry (any caller):
     *        • Permissionless: anyone may retry a previously failed message.
     *        • Reverts if the message has NOT failed yet, preventing unsolicited
     *          first-attempt calls from bypassing the gateway authentication.
     *
     * @dev REPLAY PROTECTION
     *      After PATH A or PATH B, if successfulMessages[messageId] is true the
     *      function reverts immediately — a successful message can never be
     *      forwarded again regardless of who calls it.
     *
     * @dev TARGET RESTRICTIONS
     *      Calls to address(this) or address(gateway) are blocked to prevent a
     *      malicious L2 message from hijacking owner privileges or draining the
     *      gateway.
     *
     * @dev LOW-LEVEL CALL
     *      Uses inline assembly rather than Address.functionCall so that:
     *        - Return data is NOT copied (saves gas, avoids memory bloat).
     *        - The call never reverts even if the target reverts; success/failure
     *          is captured in the `success` boolean and recorded in the mappings.
     *        - No ETH is forwarded (`value = 0`). The `payable` modifier exists
     *          only so the function can receive ETH if needed in future extensions.
     *
     * @dev CONTEXT SAVE/RESTORE
     *      `context` is written with the current l2Sender before the call and
     *      restored to the previous value after. This lets target contracts call
     *      getSender() during execution while keeping the slot clean for any
     *      future (non-re-entrant) call.
     *
     * @param nonce     Unique sequence number assigned by the L2 bridge.
     * @param l2Sender  Original sender address on L2.
     * @param target    L1 contract to invoke with the forwarded message.
     * @param message   ABI-encoded calldata to pass to `target`.
     */
    function forwardMessage(
        uint256 nonce,
        address l2Sender,
        address target,
        bytes memory message
    ) external payable nonReentrant {

        // Derive a deterministic ID from the full message contents.
        // Any change to nonce, sender, target, or payload produces a different ID.
        bytes32 messageId = keccak256(
            abi.encodeWithSignature(
                "forwardMessage(uint256,address,address,bytes)",
                nonce, l2Sender, target, message
            )
        );

        // --- Authorisation check ---
        if (msg.sender == address(gateway) && gateway.xSender() == l2Handler) {
            // PATH A: authenticated first attempt via the gateway.
            // The message must not have already failed (avoid re-processing).
            require(!failedMessages[messageId]);
        } else {
            // PATH B: permissionless retry.
            // The message must have previously failed — no unsolicited forwarding.
            require(failedMessages[messageId]);
        }

        // --- Replay protection ---
        // A message that already succeeded must never be executed again.
        if (successfulMessages[messageId]) {
            revert AlreadyForwarded(messageId);
        }

        // --- Target sanity check ---
        // Disallow calls back into this contract or into the gateway to prevent
        // privilege escalation (e.g., calling setL2Handler or owner-only functions).
        if (target == address(this) || target == address(gateway)) revert BadTarget();

        // --- Context setup ---
        // Save any pre-existing context (defensive: nonReentrant makes this a no-op
        // in practice, but correct for future composability).
        Context memory prevContext = context;
        context = Context({l2Sender: l2Sender});

        // --- Low-level call ---
        // `message` is a bytes value in memory. In ABI encoding, the first 32 bytes
        // are the length prefix, so `add(message, 0x20)` skips to the actual payload.
        // `mload(message)` reads the length from those first 32 bytes.
        bool success;
        assembly {
            success := call(
                gas(),              // forward all remaining gas
                target,             // call destination
                0,                  // send 0 ETH
                add(message, 0x20), // calldata start (skip 32-byte length prefix)
                mload(message),     // calldata length
                0,                  // returndata offset (don't copy)
                0                   // returndata length (don't copy)
            )
        }

        // --- Context restore ---
        context = prevContext;

        // --- Result recording ---
        if (success) {
            // Mark as successfully forwarded; blocks any future replay.
            successfulMessages[messageId] = true;
        } else {
            // Mark as failed; enables a permissionless retry via PATH B.
            failedMessages[messageId] = true;
        }
    }

    // -------------------------------------------------------------------------
    // Context accessor
    // -------------------------------------------------------------------------

    /**
     * @notice Returns the L2 sender for the message currently being forwarded.
     * @dev Intended to be called by the `target` contract during a forwardMessage
     *      execution to identify who initiated the cross-chain action on L2.
     *      Returns address(0) when not inside a forwardMessage call.
     * @return The l2Sender stored in the current execution context.
     */
    function getSender() external view returns (address) {
        return context.l2Sender;
    }
}
