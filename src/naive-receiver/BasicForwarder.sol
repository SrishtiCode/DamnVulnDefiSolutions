// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {EIP712} from "solady/utils/EIP712.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";

/**
 * @dev Interface to verify that a target contract recognizes and trusts this forwarder.
 * Any contract that wants to receive meta-transactions must implement this.
 */
interface IHasTrustedForwarder {
    function trustedForwarder() external view returns (address);
}

/**
 * @title BasicForwarder
 * @notice A meta-transaction forwarder that allows a relayer to submit transactions
 *         on behalf of users (the `from` address), following the EIP-712 typed data
 *         signing standard. Users sign requests off-chain; relayers execute them on-chain.
 * @dev Inherits EIP712 from solady for domain separator and typed data hashing utilities.
 */
contract BasicForwarder is EIP712 {

    /**
     * @notice Represents a meta-transaction request signed by the original sender.
     * @param from      The original sender (signer) of the request.
     * @param target    The contract to forward the call to.
     * @param value     ETH (in wei) to forward with the call.
     * @param gas       Gas limit to forward to the target call.
     * @param nonce     Replay-protection nonce; must match the sender's current nonce.
     * @param data      ABI-encoded calldata to send to the target.
     * @param deadline  Unix timestamp after which this request is considered expired.
     */
    struct Request {
        address from;
        address target;
        uint256 value;
        uint256 gas;
        uint256 nonce;
        bytes data;
        uint256 deadline;
    }

    // --- Custom Errors ---

    /// @notice Thrown when msg.value does not match request.value.
    error InvalidSigner();

    /// @notice Thrown when the sender's current nonce does not match request.nonce.
    error InvalidNonce();

    /// @notice Thrown when block.timestamp has passed the request deadline.
    error OldRequest();

    /// @notice Thrown when the target contract does not recognize this forwarder.
    error InvalidTarget();

    /// @notice Thrown when msg.value does not match the requested ETH value.
    error InvalidValue();

    /**
     * @dev EIP-712 typehash for the Request struct.
     *      Computed once at compile time from the canonical string representation
     *      of the struct fields. Used when hashing a request for signature verification.
     *      Note: `bytes data` is hashed to bytes32 before encoding (per EIP-712 spec).
     */
    bytes32 private constant _REQUEST_TYPEHASH = keccak256(
        "Request(address from,address target,uint256 value,uint256 gas,uint256 nonce,bytes data,uint256 deadline)"
    );

    /**
     * @notice Tracks the current nonce for each address.
     * @dev Nonces are incremented after each successful execution to prevent replay attacks.
     *      A request is only valid if request.nonce == nonces[request.from].
     */
    mapping(address => uint256) public nonces;

    /**
     * @notice Validates a forwarding request before execution.
     * @dev Performs five checks:
     *      1. msg.value matches request.value (prevents ETH theft or shortfall).
     *      2. The request has not expired (block.timestamp <= deadline).
     *      3. The nonce is current (prevents replay attacks).
     *      4. The target contract trusts this forwarder (prevents unintended forwarding).
     *      5. The signature was produced by `request.from` (proves authorization).
     * @param request   The meta-transaction request to validate.
     * @param signature The EIP-712 signature over the request, signed by `request.from`.
     */
    function _checkRequest(Request calldata request, bytes calldata signature) private view {
        // Ensure the ETH value sent by the relayer exactly matches what the user specified
        if (request.value != msg.value) revert InvalidValue();

        // Ensure the request hasn't expired; deadline is an inclusive Unix timestamp
        if (block.timestamp > request.deadline) revert OldRequest();

        // Ensure nonce matches to prevent replay of already-executed requests
        if (nonces[request.from] != request.nonce) revert InvalidNonce();

        // Ensure the target explicitly trusts this forwarder contract;
        // prevents forwarding calls to contracts that don't support meta-transactions
        if (IHasTrustedForwarder(request.target).trustedForwarder() != address(this)) revert InvalidTarget();

        // Recover the signer from the EIP-712 typed data hash and verify it matches `from`
        address signer = ECDSA.recover(_hashTypedData(getDataHash(request)), signature);
        if (signer != request.from) revert InvalidSigner();
    }

    /**
     * @notice Executes a validated meta-transaction on behalf of the original sender.
     * @dev After validation, the nonce is incremented to prevent replay. The call is
     *      made via inline assembly to have fine-grained control over gas forwarding.
     *      Crucially, `request.from` is appended to the calldata so the target can
     *      extract the original sender (compatible with ERC-2771 `_msgSender()` pattern).
     *      A griefing check ensures the relayer cannot silently under-supply gas.
     * @param request   The meta-transaction request (validated before execution).
     * @param signature The EIP-712 signature authorizing the request.
     * @return success  True if the forwarded call succeeded, false otherwise.
     */
    function execute(Request calldata request, bytes calldata signature) public payable returns (bool success) {
        // Validate all request fields and the signature
        _checkRequest(request, signature);

        // Increment nonce before execution to prevent reentrancy-based replay attacks
        nonces[request.from]++;

        uint256 gasLeft;
        uint256 value = request.value;       // ETH to forward (in wei)
        address target = request.target;     // Contract to call

        // Append `request.from` to the calldata (ERC-2771 convention):
        // The target contract can read the last 20 bytes to identify the true sender
        bytes memory payload = abi.encodePacked(request.data, request.from);

        uint256 forwardGas = request.gas;

        assembly {
            // Forward the call with the specified gas, value, and appended-sender payload.
            // Return data is intentionally not copied (last two args = 0, 0).
            success := call(forwardGas, target, value, add(payload, 0x20), mload(payload), 0, 0)
            gasLeft := gas() // Capture remaining gas immediately after the call
        }

        // Gas griefing protection (EIP-2771 / OpenGSN pattern):
        // If the remaining gas is less than 1/63 of the requested forwarded gas,
        // the relayer likely under-provided gas to cause a silent failure in the target.
        // `invalid()` consumes all gas and reverts the entire transaction.
        if (gasLeft < request.gas / 63) {
            assembly {
                invalid()
            }
        }
    }

    /**
     * @notice Returns the EIP-712 domain name and version for this forwarder.
     * @dev Required by the solady EIP712 base contract to construct the domain separator.
     *      The domain separator binds signatures to this specific contract and chain,
     *      preventing cross-contract and cross-chain signature replay.
     */
    function _domainNameAndVersion() internal pure override returns (string memory name, string memory version) {
        name = "BasicForwarder";
        version = "1";
    }

    /**
     * @notice Computes the EIP-712 struct hash for a given Request.
     * @dev Encodes all fields per the EIP-712 specification:
     *      - Static types (address, uint256) are encoded directly.
     *      - Dynamic types (bytes) are replaced by their keccak256 hash.
     *      This hash is then combined with the domain separator in `_hashTypedData`
     *      to produce the final signable digest.
     * @param request The request struct to hash.
     * @return        The keccak256 hash of the ABI-encoded request struct.
     */
    function getDataHash(Request memory request) public pure returns (bytes32) {
        return keccak256(
            abi.encode(
                _REQUEST_TYPEHASH,
                request.from,
                request.target,
                request.value,
                request.gas,
                request.nonce,
                keccak256(request.data), // Dynamic `bytes` field must be hashed per EIP-712
                request.deadline
            )
        );
    }

    /**
     * @notice Exposes the EIP-712 domain separator for off-chain use.
     * @dev Clients need the domain separator to construct the full typed data hash
     *      before signing. It encodes the contract name, version, chain ID, and address.
     * @return The domain separator bytes32 value.
     */
    function domainSeparator() external view returns (bytes32) {
        return _domainSeparator();
    }

    /**
     * @notice Returns the EIP-712 typehash for the Request struct.
     * @dev Useful for off-chain clients and tests to verify they are using the
     *      correct struct layout when constructing signatures.
     * @return The _REQUEST_TYPEHASH constant.
     */
    function getRequestTypehash() external pure returns (bytes32) {
        return _REQUEST_TYPEHASH;
    }
}

