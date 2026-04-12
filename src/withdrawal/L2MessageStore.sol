// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

/**
 * @title L2MessageStore
 * @notice L2-side registry that records outbound cross-chain messages as both
 *         on-chain state and emitted logs.
 *
 * @dev NOT DEPLOYED in the challenge. Provided as reference to show how the
 *      withdrawal logs (the raw inputs to the off-chain Merkle tree) were
 *      originally produced.
 *
 * @dev ROLE IN THE BRIDGE PIPELINE
 *      L2Handler.sendMessage()
 *        └─► L2MessageStore.store()          ← this contract
 *              └─► emit MessageStored(...)   ← relayer reads this log
 *                    └─► off-chain: build Merkle tree, submit root to L1Gateway
 *                          └─► L1Gateway.finalizeWithdrawal()
 *                                └─► L1Forwarder.forwardMessage()
 *                                      └─► target.call(message)
 *
 *      This contract is the canonical source of truth for what was sent from L2.
 *      The message ID it computes must be reproduced identically by the relayer
 *      when constructing the Merkle leaf for L1Gateway.
 *
 * @dev STORAGE VS EVENTS
 *      Each message is stored in `messageStore` (for on-chain deduplication /
 *      auditability) AND emitted as a MessageStored event (for off-chain indexing
 *      by the relayer). The event is the primary data source for the relayer;
 *      the mapping is available for on-chain verification if needed.
 */
contract L2MessageStore {

    // -------------------------------------------------------------------------
    // State
    // -------------------------------------------------------------------------

    /// @notice Monotonically increasing counter; used as a sequencing field in
    ///         the message ID to prevent two otherwise identical messages from
    ///         producing the same ID (and therefore the same Merkle leaf).
    /// @dev Incremented with `unchecked` — overflow after 2^256 calls is not a
    ///      realistic concern and saves ~40 gas per store call.
    uint256 public nonce;

    /// @notice Mapping from message ID to existence flag.
    /// @dev Keyed by the keccak256 of (nonce, caller, target, timestamp, data).
    ///      Set to true the moment a message is stored; never unset.
    ///      Can be used on-chain to verify that a message was legitimately
    ///      registered before it is relayed to L1.
    mapping(bytes32 messageId => bool seen) public messageStore;

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    /**
     * @notice Emitted once per stored message. This is the primary signal the
     *         off-chain relayer consumes to learn about pending withdrawals.
     *
     * @dev FIELD NOTES
     *      • `id`        — the deterministic message ID; must match the Merkle
     *                      leaf the relayer builds for L1Gateway.
     *      • `nonce`     — indexed for efficient log filtering by sequence number.
     *      • `caller`    — indexed; the L2Handler address in normal operation,
     *                      but any contract can call store() directly.
     *      • `target`    — indexed; the L1 contract to ultimately call (always
     *                      L1Forwarder in the standard flow).
     *      • `timestamp` — block.timestamp at the time of storage; this is the
     *                      value L1Gateway uses to enforce the 7-day timelock.
     *      • `data`      — the full ABI-encoded forwardMessage(...) payload;
     *                      not indexed because it is variable-length and would
     *                      only be stored as a hash if indexed.
     */
    event MessageStored(
        bytes32 id,
        uint256 indexed nonce,
        address indexed caller,
        address indexed target,
        uint256 timestamp,
        bytes data
    );

    // -------------------------------------------------------------------------
    // Core storage logic
    // -------------------------------------------------------------------------

    /**
     * @notice Records an outbound cross-chain message and emits a log for the relayer.
     *
     * @dev MESSAGE ID CONSTRUCTION
     *      id = keccak256(abi.encode(nonce, msg.sender, target, block.timestamp, data))
     *
     *      Using `abi.encode` (padded) rather than `encodePacked` prevents hash
     *      collisions when variable-length fields (like `data`) are present.
     *      Every field that distinguishes one message from another is included:
     *        • nonce         — ensures two identical calls produce different IDs.
     *        • msg.sender    — binds the ID to the registering contract (L2Handler).
     *        • target        — the intended L1 recipient (L1Forwarder).
     *        • block.timestamp — captured here and later enforced as the timelock
     *                           start by L1Gateway; must be reproduced exactly by
     *                           the relayer when building the Merkle leaf.
     *        • data          — the full forwardMessage(...) calldata payload.
     *
     * @dev TIMESTAMP SENSITIVITY
     *      block.timestamp is baked into the ID at storage time. The relayer MUST
     *      read this value from the MessageStored event (not recompute it) when
     *      building the Merkle tree, because any difference would produce a
     *      different leaf hash and an invalid proof on L1.
     *
     * @dev PERMISSIONLESS
     *      Anyone can call store() directly — there is no access control. In the
     *      standard flow only L2Handler calls it, but a direct caller could craft
     *      a message with arbitrary `data`. The L1 side mitigates this via the
     *      Merkle proof check (only messages included in a root approved by the
     *      L1Gateway owner can be finalized by the public) and the operator path.
     *
     * @param target The L1 contract address to invoke after the message is bridged
     *               (L1Forwarder in the standard flow).
     * @param data   ABI-encoded calldata for `target`; in the standard flow this
     *               is an encoded L1Forwarder.forwardMessage(...) call.
     */
    function store(address target, bytes memory data) external {

        // Derive a deterministic, collision-resistant ID from all message fields.
        // The relayer reconstructs this same hash off-chain to build the Merkle tree.
        bytes32 id = keccak256(abi.encode(nonce, msg.sender, target, block.timestamp, data));

        // Persist the ID on-chain for auditability and potential on-chain verification.
        messageStore[id] = true;

        // Emit the full message so the off-chain relayer can index and process it.
        // `data` is emitted in full (not hashed) so the relayer can reconstruct the
        // exact payload to pass to L1Gateway.finalizeWithdrawal().
        emit MessageStored(id, nonce, msg.sender, target, block.timestamp, data);

        // Advance the nonce after emitting so the logged nonce matches the ID.
        // unchecked: overflow after 2^256 messages is not a realistic concern.
        unchecked {
            nonce++;
        }
    }
}
