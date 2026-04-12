// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {L1Forwarder} from "./L1Forwarder.sol";
import {L2MessageStore} from "./L2MessageStore.sol";

/**
 * @title L2Handler
 * @notice L2-side entry point for initiating cross-chain messages to L1.
 *
 * @dev NOT DEPLOYED in the challenge. Provided purely as reference to show
 *      how the withdrawal logs (the off-chain Merkle tree inputs) were
 *      originally produced. Understanding this contract explains:
 *        - The exact ABI encoding of each withdrawal leaf.
 *        - Why `nonce` appears in every leaf (sequencing + collision resistance).
 *        - How `msg.sender` becomes the `l2Sender` field seen by L1Forwarder.
 *
 * @dev CROSS-CHAIN FLOW (end-to-end)
 *      1. A user calls sendMessage(target, message) on L2.
 *      2. L2Handler wraps the call into a forwardMessage payload and stores it
 *         in L2MessageStore, emitting a log.
 *      3. An off-chain relayer reads those logs, builds a Merkle tree of all
 *         pending withdrawals, and submits the root to L1Gateway.setRoot().
 *      4. After the 7-day timelock, anyone supplies the Merkle proof to
 *         L1Gateway.finalizeWithdrawal(), which calls L1Forwarder.forwardMessage(),
 *         which in turn calls `target` on L1 with the original `message`.
 */
contract L2Handler {

    // -------------------------------------------------------------------------
    // Immutables & state
    // -------------------------------------------------------------------------

    /// @notice The L2 store that persists outbound messages as on-chain logs.
    /// @dev Immutable: set once in the constructor and never changed.
    L2MessageStore public immutable l2MessageStore;

    /// @notice Monotonically increasing counter used to sequence outbound messages.
    /// @dev Included in every stored message so that two otherwise identical
    ///      messages (same sender, target, and payload) produce different leaves
    ///      in the Merkle tree, preventing leaf collision attacks.
    ///      Uses unchecked arithmetic — overflow after 2^256 messages is not a
    ///      realistic concern.
    uint256 public nonce;

    /// @notice The L1Forwarder contract that will receive and execute messages on L1.
    /// @dev Its address is baked into every outbound message as the `target` for
    ///      L1Gateway, and its forwardMessage selector is used for ABI encoding.
    L1Forwarder public immutable l1Forwarder;

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    /**
     * @param _l2MessageStore The L2 contract that logs outbound cross-chain messages.
     * @param _l1Forwarder    The L1 contract that will relay the message to its
     *                        final destination on L1.
     */
    constructor(L2MessageStore _l2MessageStore, L1Forwarder _l1Forwarder) {
        l2MessageStore = _l2MessageStore;
        l1Forwarder = _l1Forwarder;
    }

    // -------------------------------------------------------------------------
    // Outbound messaging
    // -------------------------------------------------------------------------

    /**
     * @notice Initiates a cross-chain message from L2 to an L1 target contract.
     *
     * @dev ENCODING
     *      The payload stored in L2MessageStore is the ABI encoding of:
     *        L1Forwarder.forwardMessage(nonce, msg.sender, target, message)
     *
     *      This is exactly what L1Gateway will pass as `message` when it calls
     *      L1Forwarder, so the four fields must match what L1Forwarder expects:
     *        • nonce     — this contract's current counter value.
     *        • l2Sender  — msg.sender (the user initiating the withdrawal on L2).
     *        • target    — the final L1 contract to invoke.
     *        • message   — the calldata to pass to that L1 target.
     *
     * @dev LEAF DERIVATION (for reference)
     *      On L1, L1Gateway computes the Merkle leaf as:
     *        keccak256(abi.encode(nonce, l2Sender, target, timestamp, message))
     *      where `message` is the encoded forwardMessage call above. The relayer
     *      must capture the L2MessageStore log to reconstruct these fields and
     *      build the tree correctly.
     *
     * @dev NONCE SAFETY
     *      Incremented with `unchecked` — saves ~40 gas per call. Overflow is
     *      not a practical concern (would require 2^256 messages).
     *
     * @param target  The final L1 contract address to call after bridging.
     * @param message ABI-encoded calldata to forward to `target` on L1.
     */
    function sendMessage(address target, bytes calldata message) external {
        // Store the outbound message in L2MessageStore.
        // - `target` for the L2 store is always L1Forwarder (the L1 bridge entry point).
        // - `data` is the full ABI-encoded forwardMessage call, which bundles:
        //     • the current nonce (for sequencing and collision resistance)
        //     • msg.sender as l2Sender (preserved across the bridge for L1 auth)
        //     • the user-supplied target and message (the actual L1 action)
        l2MessageStore.store({
            target: address(l1Forwarder),
            data: abi.encodeCall(
                L1Forwarder.forwardMessage,
                (nonce, msg.sender, target, message)
            )
        });

        // Advance the nonce after storing so the logged message always reflects
        // the value used, not the next one. unchecked saves gas; overflow is harmless.
        unchecked {
            nonce++;
        }
    }
}
