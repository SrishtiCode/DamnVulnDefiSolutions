// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {FixedPointMathLib} from "solady/utils/FixedPointMathLib.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {BitMaps} from "@openzeppelin/contracts/utils/structs/BitMaps.sol";

/**
 * @dev Tracks the state of a single token's reward distribution.
 *      Uses a Merkle tree per "batch" so new reward rounds can be
 *      added without redeploying. Claimed status is packed into
 *      256-bit words (bitmaps) to minimise storage costs.
 */
struct Distribution {
    uint256 remaining;       // Tokens left unclaimed in the current batch
    uint256 nextBatchNumber; // Auto-incrementing ID for the next batch
    // batchNumber → Merkle root for that batch
    mapping(uint256 batchNumber => bytes32 root) roots;
    // claimer → word-index → 256-bit packed claimed flags
    mapping(address claimer => mapping(uint256 word => uint256 bits)) claims;
}

/**
 * @dev A single claim request supplied by the caller.
 *      Multiple claims can be batched in one tx via `claimRewards`.
 */
struct Claim {
    uint256 batchNumber; // Which distribution batch this claim belongs to
    uint256 amount;      // Token amount the caller is entitled to
    uint256 tokenIndex;  // Index into the `inputTokens` array passed to claimRewards
    bytes32[] proof;     // Merkle proof showing (caller, amount) is in the tree
}

/**
 * @title  TheRewarderDistributor
 * @notice Gas-efficient airdrop / reward distributor that uses:
 *         - Merkle proofs  → callers prove entitlement without on-chain storage per user
 *         - Bitmap packing → one storage slot tracks 256 claimed flags simultaneously
 *         - Batch numbers  → multiple independent reward rounds per token
 */
contract TheRewarderDistributor {
    using BitMaps for BitMaps.BitMap;

    /// @notice Deployer becomes the permanent owner (receives leftover tokens via `clean`)
    address public immutable owner = msg.sender;

    /// @notice One Distribution record per ERC-20 token
    mapping(IERC20 token => Distribution) public distributions;

    // -------------------------------------------------------------------------
    // Errors
    // -------------------------------------------------------------------------

    /// @dev Raised when trying to create a new batch while tokens from the last one remain
    error StillDistributing();
    /// @dev Raised when a zero-value Merkle root is supplied
    error InvalidRoot();
    /// @dev Raised when the bitmap shows the caller already claimed this batch
    error AlreadyClaimed();
    /// @dev Raised when the supplied Merkle proof does not verify against the stored root
    error InvalidProof();
    /// @dev Raised when `amount == 0` on distribution creation
    error NotEnoughTokensToDistribute();

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    event NewDistribution(IERC20 token, uint256 batchNumber, bytes32 newMerkleRoot, uint256 totalAmount);

    // -------------------------------------------------------------------------
    // View helpers
    // -------------------------------------------------------------------------

    /// @notice Returns unclaimed token balance for a given distribution
    function getRemaining(address token) external view returns (uint256) {
        return distributions[IERC20(token)].remaining;
    }

    /// @notice Returns the batch number that will be used by the *next* createDistribution call
    function getNextBatchNumber(address token) external view returns (uint256) {
        return distributions[IERC20(token)].nextBatchNumber;
    }

    /// @notice Returns the Merkle root stored for a specific token + batch
    function getRoot(address token, uint256 batchNumber) external view returns (bytes32) {
        return distributions[IERC20(token)].roots[batchNumber];
    }

    // -------------------------------------------------------------------------
    // Admin functions
    // -------------------------------------------------------------------------

    /**
     * @notice Creates a new reward batch for `token`.
     * @dev    Caller must have approved this contract to pull `amount` tokens.
     *         Only one active distribution per token is allowed at a time —
     *         `remaining` must be zero before a new batch can start.
     * @param token   The ERC-20 reward token
     * @param newRoot Merkle root committing to (address, amount) pairs
     * @param amount  Total tokens to distribute in this batch
     */
    function createDistribution(IERC20 token, bytes32 newRoot, uint256 amount) external {
        if (amount == 0) revert NotEnoughTokensToDistribute();
        if (newRoot == bytes32(0)) revert InvalidRoot();
        if (distributions[token].remaining != 0) revert StillDistributing(); // previous batch not exhausted

        distributions[token].remaining = amount;

        uint256 batchNumber = distributions[token].nextBatchNumber;
        distributions[token].roots[batchNumber] = newRoot;
        distributions[token].nextBatchNumber++; // increment for the next future batch

        // Pull tokens from the caller into this contract
        SafeTransferLib.safeTransferFrom(address(token), msg.sender, address(this), amount);

        emit NewDistribution(token, batchNumber, newRoot, amount);
    }

    /**
     * @notice Sweeps any fully-distributed token balances to the owner.
     * @dev    Only transfers tokens whose `remaining` counter has reached zero,
     *         preventing accidental sweeping of active distributions.
     * @param tokens List of token addresses to check and potentially sweep
     */
    function clean(IERC20[] calldata tokens) external {
        for (uint256 i = 0; i < tokens.length; i++) {
            IERC20 token = tokens[i];
            if (distributions[token].remaining == 0) {
                // Safe to send leftovers (e.g. rounding dust) to owner
                token.transfer(owner, token.balanceOf(address(this)));
            }
        }
    }

    // -------------------------------------------------------------------------
    // Core claim logic
    // -------------------------------------------------------------------------

    /**
     * @notice Claim rewards for one or more tokens in a single transaction.
     * @dev    Claims MUST be grouped by token (same tokenIndex consecutively).
     *         The bitmap check + update is deferred until the token changes or
     *         the loop ends, so multiple batches of the same token are accumulated
     *         before a single _setClaimed call is made.
     *
     *         ⚠️  VULNERABILITY NOTE (Damn Vulnerable DeFi):
     *         The transfer happens inside the loop BEFORE `_setClaimed` is called
     *         for all items of the same token. An attacker can interleave claims
     *         across tokens to bypass the AlreadyClaimed check and drain funds.
     *
     * @param inputClaims Array of Claim structs (batch, amount, tokenIndex, proof)
     * @param inputTokens Deduplicated list of ERC-20 tokens referenced by tokenIndex
     */
    function claimRewards(Claim[] memory inputClaims, IERC20[] memory inputTokens) external {
        Claim memory inputClaim;
        IERC20 token;
        uint256 bitsSet; // Accumulates claimed batch bits for CURRENT token
        uint256 amount;  // Accumulates total amount for CURRENT token

        for (uint256 i = 0; i < inputClaims.length; i++) {
            inputClaim = inputClaims[i];

            // Each batch maps to a specific bitmap word + bit
            uint256 wordPosition = inputClaim.batchNumber / 256;
            uint256 bitPosition  = inputClaim.batchNumber % 256;

            if (token != inputTokens[inputClaim.tokenIndex]) {
                // ⚠️ VULNERABILITY PART 1:
                // When token changes, contract "flushes" previous accumulated claims

                if (address(token) != address(0)) {
                    // ❗ PROBLEM:
                    // _setClaimed uses ONLY ONE wordPosition (from CURRENT iteration)
                    // but bitsSet may contain bits from DIFFERENT wordPositions
                    // → incorrect bitmap update
                    if (!_setClaimed(token, amount, wordPosition, bitsSet)) revert AlreadyClaimed();
                }

                // Switch to new token
                token  = inputTokens[inputClaim.tokenIndex];

                // Start fresh bitmap for this token
                bitsSet = 1 << bitPosition;

                // Reset accumulated amount
                amount  = inputClaim.amount;

            } else {
                // Same token → accumulate claims

                // ⚠️ VULNERABILITY PART 2:
                // bits from different batchNumbers (possibly different wordPositions)
                // are merged into ONE bitsSet
                bitsSet = bitsSet | (1 << bitPosition);

                // Amount also aggregated
                amount += inputClaim.amount;
            }

            // ⚠️ VULNERABILITY PART 3:
            // Final flush also uses ONLY ONE wordPosition
            // → earlier wordPositions may NEVER be marked claimed
            if (i == inputClaims.length - 1) {
                if (!_setClaimed(token, amount, wordPosition, bitsSet)) revert AlreadyClaimed();
            }

            // Verify Merkle proof (this part is correct)
            bytes32 leaf = keccak256(abi.encodePacked(msg.sender, inputClaim.amount));
            bytes32 root = distributions[token].roots[inputClaim.batchNumber];

            if (!MerkleProof.verify(inputClaim.proof, root, leaf)) revert InvalidProof();

            // ⚠️ VULNERABILITY PART 4 (CRITICAL EFFECT):
            // Tokens are transferred BEFORE correct state is ensured
            // → even if bitmap tracking is wrong, user already receives funds
            inputTokens[inputClaim.tokenIndex].transfer(msg.sender, inputClaim.amount);
        }
    }

    // -------------------------------------------------------------------------
    // Internal helpers
    // -------------------------------------------------------------------------

    /**
     * @notice Atomically checks and sets claimed bits for a token + word position.
     * @dev    Uses a bitwise AND to detect any overlap with already-claimed bits.
     *         If none, ORs in the new bits and deducts `amount` from `remaining`.
     * @param token       The reward token
     * @param amount      Total amount being marked as claimed
     * @param wordPosition Index of the 256-bit storage word
     * @param newBits     Bitmask of batch positions being claimed
     * @return            True if successfully marked; false if any bit was already set
     */
    function _setClaimed(IERC20 token, uint256 amount, uint256 wordPosition, uint256 newBits) private returns (bool) {
        uint256 currentWord = distributions[token].claims[msg.sender][wordPosition];

        // If any bit in newBits is already set → at least one batch was claimed before
        if ((currentWord & newBits) != 0) return false;

        // Persist the updated bitmap (marks these batches as claimed)
        distributions[token].claims[msg.sender][wordPosition] = currentWord | newBits;

        // Reduce the pool's remaining balance by the total claimed amount
        distributions[token].remaining -= amount;

        return true;
    }
}
