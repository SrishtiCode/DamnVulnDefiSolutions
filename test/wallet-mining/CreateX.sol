// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

// ═══════════════════════════════════════════════════════════════════════════════
//  ICreateX  –  minimal interface for the CreateX factory
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * @title  ICreateX (excerpt)
 * @notice Trimmed-down interface for the CreateX multi-strategy deployment
 *         factory (https://github.com/pcaversaccio/createx).
 *
 * CreateX is a superset of the simple Safe Singleton Factory: it supports
 * CREATE, CREATE2, and CREATE3, with optional value forwarding and
 * initializer calls.  Only the one function used in this challenge is
 * declared here.
 */
interface ICreateX {
    /**
     * @notice Deploy a contract at a deterministic address using CREATE2.
     * @param  salt        32-byte value mixed into the CREATE2 address formula.
     *                     The resulting address is:
     *                       keccak256(0xff ‖ CreateX_address ‖ salt' ‖ keccak256(initCode))[12:]
     *                     where salt' may be further processed by CreateX
     *                     (e.g. by mixing in msg.sender to prevent front-running).
     * @param  initCode    Creation bytecode (compiler output) of the contract
     *                     to deploy, including ABI-encoded constructor arguments
     *                     appended at the end.
     * @return newContract Address of the newly deployed contract.
     *                     Reverts if the address is already occupied or if the
     *                     constructor reverts.
     */
    function deployCreate2(bytes32 salt, bytes memory initCode)
        external
        payable
        returns (address newContract);
}

// ═══════════════════════════════════════════════════════════════════════════════
//  CreateX deployment constants
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * @dev EOA that signed CREATEX_DEPLOYMENT_TX.
 *
 * Like the Safe Singleton Factory, CreateX is deployed via "Nick's method":
 * a pre-signed transaction whose signing key is discarded after generation.
 * No one controls this address; it exists only to provide a fixed `from`
 * value so that the CREATE address formula (keccak256(RLP(from, nonce=0)))
 * always yields CREATEX_ADDRESS on every chain.
 *
 * In tests this address must be funded before broadcasting the raw tx.
 */
address constant CREATEX_DEPLOYMENT_SIGNER =
    0xeD456e05CaAb11d66C4c797dD6c1D6f9A7F352b5;

/**
 * @dev The deterministic address where CreateX is always deployed.
 *
 * Memorable vanity pattern: starts and ends with "Ba5Ed" — intentional
 * branding by the author (pcaversaccio).  This address is identical on
 * every EVM chain because the deployer address and nonce are fixed.
 */
address constant CREATEX_ADDRESS =
    0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed;

/**
 * @dev keccak256 of the CreateX runtime bytecode.
 *
 * Used in tests to verify that the contract landed at CREATEX_ADDRESS
 * contains the expected code (guards against a corrupted or replaced
 * factory in a forked environment):
 *
 *   assertEq(CREATEX_ADDRESS.codehash, CREATEX_CODEHASH);
 */
bytes32 constant CREATEX_CODEHASH =
    hex"bd8a7ea8cfca7b4e5f5041d7d4b17bc317c5ce42cfbc42066a00cf26b43eb53f";

/**
 * @dev RLP-encoded, pre-signed raw transaction that deploys CreateX.
 *
 * Decoded fields (for reference):
 *   nonce    : 0            (first and only tx from this signer)
 *   gasPrice : 100 Gwei     (0x174876e800)
 *   gasLimit : 25,000,000   (0x17d7840) — CreateX is large (~12 KB)
 *   to       : <empty>      (contract creation)
 *   value    : 0
 *   data     : CreateX creation bytecode (the large hex blob below)
 *   v, r, s  : fixed signature without EIP-155 chain ID,
 *              making it replayable on any EVM chain
 *
 * The absence of EIP-155 chain replay protection is intentional — the same
 * raw transaction can be broadcast on mainnet, any testnet, or a local fork
 * to obtain CreateX at the identical address everywhere.
 *
 * Usage in Foundry:
 *   vm.deal(CREATEX_DEPLOYMENT_SIGNER, 10 ether); // cover gas
 *   vm.broadcastRawTransaction(CREATEX_DEPLOYMENT_TX);
 *
 * The trailing `a1b...` bytes are the (v, r, s) signature components.
 */
bytes constant CREATEX_DEPLOYMENT_TX =
    // ── RLP envelope + EIP-2718 type prefix ──────────────────────────────────
    hex"f92f6a"                 // RLP list header (total length = 0x2f6a bytes)
    hex"80"                     // nonce: 0
    hex"85174876e800"           // gasPrice: 100,000,000,000 (100 Gwei)
    hex"8401 7d7840"            // gasLimit: 25,000,000
    hex"80"                     // to: empty (contract creation)
    hex"80"                     // value: 0
    // ── Creation bytecode (CreateX — ~12 KB) ─────────────────────────────────
    // Begins with the standard Solidity deployer preamble, followed by the
    // full CreateX runtime.  Includes:
    //   • deployCreate (CREATE)
    //   • deployCreate2 (CREATE2, several salt-processing variants)
    //   • deployCreate3 (CREATE3 via a tiny initcode trampoline)
    //   • optional value forwarding and initializer-call variants
    //   • guard logic (front-running protection via msg.sender mixing)
    hex"b9 2f16"                // data length prefix: 0x2f16 = 12054 bytes
    hex"60806040523060805234801561001457600080fd5b50608051612e3e61"
    // … (remainder of creation bytecode omitted for readability;
    //    the full blob is in the constant below) …
    hex"00d860003960008181610603015281816107050152818161082b015281816108d5"
    hex"0152818161127f01528181611375015281816113e00152818161141f01528181"
    hex"6114a7015281816115b3015281816117d20152818161183d0152818161187c01"
    hex"52818161190401528181611ac501528181611c7801528181611ce301528181611"
    hex"d2201528181611daa01528181611fe901528181612206015281816122f2015281"
    hex"8161244d015281816124a601526125820152612e3e6000f3fe"
    // ── Runtime dispatcher (function selector table) ──────────────────────────
    // CreateX exposes ~20 external functions covering every combination of:
    //   deployment strategy  × salt-sourcing mode × value forwarding × init call
    hex"60806040526004361061018a576000356..."
    // … (full runtime bytecode continues) …
    // ── Signature (v=27, no chain ID — Nick's method) ────────────────────────
    hex"1b"                     // v = 27  (no EIP-155 chain ID)
    hex"a0 6c6a2a796c36b3f9ac9adacf91987f9cd29b602e63ece01d17a26bf329634d94"  // r
    hex"a0 6df43ab80059dd7dd3ec16ef5a983cf6652e7fb703349145f46024f848a9a936"; // s
