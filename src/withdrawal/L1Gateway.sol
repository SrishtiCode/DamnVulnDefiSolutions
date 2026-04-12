// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {OwnableRoles} from "solady/auth/OwnableRoles.sol";

/**
 * @title L1Gateway
 * @notice Entry point for finalizing L2→L1 withdrawals on L1.
 *
 * @dev WITHDRAWAL FLOW
 *      1. Owner publishes a Merkle root (`setRoot`) containing all pending
 *         withdrawal leaves from L2.
 *      2. After a mandatory 7-day delay, anyone may call `finalizeWithdrawal`
 *         with a valid Merkle proof to execute the withdrawal on L1.
 *      3. Privileged operators may finalize without supplying a proof, intended
 *         for emergency use or automated relayers.
 *
 * @dev SECURITY PROPERTIES
 *      • Replay protection  — each leaf is marked finalized after first execution.
 *      • Timelock           — a 7-day delay between message timestamp and execution
 *                             gives the owner time to rotate the root if fraud is detected.
 *      • xSender isolation  — the L2 sender is written to storage before the external
 *                             call and reset afterwards, so downstream contracts
 *                             (e.g. L1Forwarder) can read it during execution via
 *                             gateway.xSender().
 *      • CEI ordering       — state is updated (finalizedWithdrawals, counter, xSender)
 *                             before the external call to mitigate re-entrancy.
 *                             NOTE: there is no ReentrancyGuard here; the CEI pattern
 *                             is the sole re-entrancy defence.
 */
contract L1Gateway is OwnableRoles {

    // -------------------------------------------------------------------------
    // Constants
    // -------------------------------------------------------------------------

    /// @notice Minimum time that must elapse between the L2 message timestamp
    ///         and when it can be finalized on L1.
    /// @dev Acts as a fraud-proof window: the owner can update the Merkle root
    ///      to exclude a fraudulent leaf before the delay expires.
    uint256 public constant DELAY = 7 days;

    /// @notice Role identifier for privileged operators.
    /// @dev Operators may call finalizeWithdrawal without a Merkle proof.
    ///      Uses Solady's bitmask role system; _ROLE_0 == 1 << 0.
    uint256 public constant OPERATOR_ROLE = _ROLE_0;

    // -------------------------------------------------------------------------
    // State
    // -------------------------------------------------------------------------

    /// @notice Current Merkle root representing the set of valid pending withdrawals.
    /// @dev Updated by the owner via setRoot. Only one root is active at a time;
    ///      replacing it invalidates proofs against the old root, so the owner must
    ///      ensure all in-flight withdrawals have been finalized first (or re-included).
    bytes32 public root;

    /// @notice Total number of withdrawals finalized through this gateway.
    uint256 public counter;

    /// @notice The L2 sender of the withdrawal currently being finalized.
    /// @dev Written to storage immediately before the external call and reset to
    ///      0xBADBEEF afterwards. Downstream contracts (e.g. L1Forwarder) read
    ///      this mid-execution to authenticate the originating L2 address.
    ///      Sentinel value 0xBADBEEF signals "no active withdrawal".
    address public xSender = address(0xBADBEEF);

    /// @notice Tracks which withdrawal leaves have already been finalized.
    /// @dev Keyed by the leaf hash. Prevents replay of the same withdrawal.
    mapping(bytes32 id => bool finalized) public finalizedWithdrawals;

    // -------------------------------------------------------------------------
    // Errors
    // -------------------------------------------------------------------------

    /// @notice Thrown when the proposed new root is zero or identical to the current root.
    error BadNewRoot();

    /// @notice Thrown when block.timestamp < message timestamp + DELAY.
    error EarlyWithdrawal();

    /// @notice Thrown when the supplied Merkle proof does not verify against the current root.
    error InvalidProof();

    /// @notice Thrown when a withdrawal leaf has already been finalized.
    error AlreadyFinalized(bytes32 leaf);

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    /// @notice Emitted when a non-operator caller supplies a valid Merkle proof.
    /// @param proof  The Merkle proof that was verified.
    /// @param root   The root it was verified against.
    /// @param leaf   The leaf that was proven.
    event ValidProof(bytes32[] proof, bytes32 root, bytes32 leaf);

    /// @notice Emitted after each finalization attempt, regardless of whether
    ///         the downstream call succeeded.
    /// @param leaf       The withdrawal leaf that was finalized.
    /// @param success    Whether the low-level call to `target` succeeded.
    /// @param isOperator Whether the caller used the operator (no-proof) path.
    event FinalizedWithdrawal(bytes32 leaf, bool success, bool isOperator);

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    constructor() {
        // Deployer becomes the owner; no OPERATOR_ROLE is granted by default.
        _initializeOwner(msg.sender);
    }

    // -------------------------------------------------------------------------
    // Admin
    // -------------------------------------------------------------------------

    /**
     * @notice Publishes a new Merkle root of pending L2→L1 withdrawals.
     * @dev Reverts if the root is zero (likely an accident) or unchanged
     *      (likely a redundant call). Only callable by the owner.
     * @param _root New Merkle root to set.
     */
    function setRoot(bytes32 _root) external onlyOwner {
        if (_root == bytes32(0) || _root == root) revert BadNewRoot();
        root = _root;
    }

    // -------------------------------------------------------------------------
    // Core finalization logic
    // -------------------------------------------------------------------------

    /**
     * @notice Finalizes an L2→L1 withdrawal by executing its payload on L1.
     *
     * @dev LEAF CONSTRUCTION
     *      The leaf is the keccak256 of the tightly ABI-encoded withdrawal
     *      parameters. Using `abi.encode` (rather than `encodePacked`) avoids
     *      hash collisions when fields of variable length are adjacent.
     *
     * @dev AUTHORISATION (two paths)
     *      PATH A – operator (no proof required):
     *        hasAnyRole(msg.sender, OPERATOR_ROLE) == true
     *        The proof array is ignored entirely.
     *
     *      PATH B – public (proof required):
     *        The caller must supply a valid Merkle proof for the leaf against
     *        the current root. Reverts with InvalidProof if verification fails.
     *
     * @dev TIMELOCK
     *      `timestamp` is the time the message was registered on L2. The call
     *      reverts if less than DELAY (7 days) has elapsed since then, giving
     *      the owner a window to react to fraudulent leaves.
     *
     * @dev CEI (Checks-Effects-Interactions) ORDER
     *      1. Checks  — timelock, proof/operator, replay guard.
     *      2. Effects — mark finalized, increment counter, set xSender.
     *      3. Interact— low-level call to target.
     *      4. Cleanup — reset xSender sentinel.
     *      State is mutated before the call so that re-entrant attempts to
     *      finalize the same leaf hit the AlreadyFinalized guard.
     *
     * @dev LOW-LEVEL CALL
     *      Identical pattern to L1Forwarder: raw `call` with 0 value, no return
     *      data copied. The call's success/failure is captured and emitted but
     *      does NOT revert the transaction — the leaf is marked finalized either
     *      way to prevent replay.
     *
     * @dev xSender LIFECYCLE
     *      xSender = l2Sender  →  external call  →  xSender = 0xBADBEEF
     *      The sentinel ensures that any read of xSender outside an active
     *      finalization returns an obviously invalid address, preventing
     *      downstream contracts from being tricked into trusting a stale value.
     *
     * @param nonce     Unique sequence number from L2.
     * @param l2Sender  Address of the originating account on L2.
     * @param target    L1 contract to call with the withdrawal payload.
     * @param timestamp Block timestamp on L2 when the withdrawal was initiated.
     * @param message   ABI-encoded calldata to pass to `target`.
     * @param proof     Merkle proof showing the leaf is included in `root`.
     *                  Ignored when called by an operator.
     */
    function finalizeWithdrawal(
        uint256 nonce,
        address l2Sender,
        address target,
        uint256 timestamp,
        bytes memory message,
        bytes32[] memory proof
    ) external {

        // --- CHECK: timelock ---
        // The 7-day delay must have fully elapsed since the L2 message timestamp.
        if (timestamp + DELAY > block.timestamp) revert EarlyWithdrawal();

        // --- Leaf construction ---
        // Hash all parameters that uniquely identify this withdrawal.
        // Must match exactly what was hashed when the Merkle tree was built off-chain.
        bytes32 leaf = keccak256(abi.encode(nonce, l2Sender, target, timestamp, message));

        // --- CHECK: authorisation ---
        bool isOperator = hasAnyRole(msg.sender, OPERATOR_ROLE);
        if (!isOperator) {
            // Public path: verify the Merkle proof against the current root.
            if (MerkleProof.verify(proof, root, leaf)) {
                emit ValidProof(proof, root, leaf);
            } else {
                revert InvalidProof();
            }
        }
        // Operator path: proof array is accepted but never read.

        // --- CHECK: replay protection ---
        // Revert if this exact leaf was already finalized (regardless of caller).
        if (finalizedWithdrawals[leaf]) revert AlreadyFinalized(leaf);

        // --- EFFECTS ---
        // All state mutations happen before the external call (CEI pattern).
        finalizedWithdrawals[leaf] = true; // block replay
        counter++;                          // track total finalizations
        xSender = l2Sender;                // expose L2 sender for downstream reads

        // --- INTERACTION: low-level call to target ---
        // `message` layout in memory: [32-byte length][payload bytes]
        // add(message, 0x20) skips the length prefix to point at the raw payload.
        // mload(message) reads the length from those first 32 bytes.
        // No ETH is forwarded; return data is discarded.
        bool success;
        assembly {
            success := call(
                gas(),              // forward all remaining gas
                target,             // call destination
                0,                  // ETH value: 0
                add(message, 0x20), // calldata start (skip 32-byte length prefix)
                mload(message),     // calldata length
                0,                  // returndata offset (don't copy)
                0                   // returndata length (don't copy)
            )
        }

        // --- CLEANUP: reset xSender sentinel ---
        // Restoring 0xBADBEEF signals that no withdrawal is active.
        // Any downstream contract reading xSender after this point gets an
        // obviously invalid address rather than a stale l2Sender value.
        xSender = address(0xBADBEEF);

        // Emit result regardless of success — the leaf is finalized either way.
        emit FinalizedWithdrawal(leaf, success, isOperator);
    }
}
