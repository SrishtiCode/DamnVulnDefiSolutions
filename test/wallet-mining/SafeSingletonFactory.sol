// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

/**
 * @title  SafeSingletonFactory deployment constants
 * @notice Contains the data needed to replay the canonical Safe Singleton
 *         Factory deployment on any EVM chain — including a local Foundry fork.
 *
 * BACKGROUND
 * ──────────
 * The Safe Singleton Factory is a tiny, permissionless CREATE2 factory used
 * by the Safe (formerly Gnosis Safe) ecosystem to deploy contracts at the
 * SAME address on every EVM-compatible chain.
 *
 * It works by using a "Nick's method" (keyless deployment):
 *   1. A one-time pre-signed transaction is broadcast with no `from` address
 *      derivation — the signing key is chosen so that the resulting contract
 *      address is the same everywhere.
 *   2. Anyone can fund the signer and broadcast the raw transaction; no
 *      private key needs to be held after the fact.
 *
 * Because the transaction, sender, and bytecode are all fixed, the factory
 * always lands at SAFE_SINGLETON_FACTORY_ADDRESS on every chain.
 */

// ── Deployment signer ────────────────────────────────────────────────────────

/**
 * @dev The EOA whose signature is embedded in SAFE_SINGLETON_FACTORY_DEPLOYMENT_TX.
 *
 * This address is derived from the pre-signed transaction's (v, r, s) values.
 * It is NOT a real key holder — the signing key was generated for the sole
 * purpose of producing this specific deployment transaction (Nick's method),
 * so no one has ongoing control of this address.
 *
 * In the test setup this address must be funded with enough ETH to pay the
 * gas for broadcasting SAFE_SINGLETON_FACTORY_DEPLOYMENT_TX.
 */
address constant SAFE_SINGLETON_FACTORY_DEPLOYMENT_SIGNER =
    0xE1CB04A0fA36DdD16a06ea828007E35e1a3cBC37;

// ── Raw deployment transaction ───────────────────────────────────────────────

/**
 * @dev RLP-encoded, pre-signed raw transaction that deploys the factory.
 *
 * Decoded fields (for reference):
 *   nonce    : 0          (first tx from this signer)
 *   gasPrice : 100 Gwei   (0x174876e800)
 *   gasLimit : 100,000    (0x186a0)
 *   to       : <empty>    (contract creation)
 *   value    : 0
 *   data     : SAFE_SINGLETON_FACTORY_CODE prefixed with a deploy wrapper
 *   v, r, s  : fixed signature (no EIP-155 replay protection, chainId-agnostic)
 *
 * The absence of EIP-155 chain ID in the signature is intentional: it allows
 * the same raw transaction to be replayed on any chain, always producing the
 * same contract address from the same sender nonce.
 *
 * Usage in Foundry:
 *   vm.broadcastRawTransaction(SAFE_SINGLETON_FACTORY_DEPLOYMENT_TX);
 */
bytes constant SAFE_SINGLETON_FACTORY_DEPLOYMENT_TX =
    hex"f8a78085174876e800830186a08080b853604580600e600039806000f350fe7fff"
    hex"fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe036016"
    hex"00081602082378035828234f58015156039578182fd5b808252505050601460"
    hex"0cf382f4f5a00dc4d1d21b308094a30f5f93da35e4d72e99115378f135f2295"
    hex"bea47301a3165a0636b822daad40aa8c52dd5132f378c0c0e6d83b4898228c7"
    hex"e21c84e631a0b891";

// ── Deployed factory address ─────────────────────────────────────────────────

/**
 * @dev The deterministic address where the factory is always deployed.
 *
 * Derived from:
 *   keccak256(RLP(signer_address, nonce=0))[12:]
 *
 * Because the signer address and nonce are both fixed, this address is the
 * same on every EVM chain — mainnet, testnets, and local forks alike.
 */
address constant SAFE_SINGLETON_FACTORY_ADDRESS =
    0x914d7Fec6aaC8cd542e72Bca78B30650d45643d7;

// ── Factory runtime bytecode ─────────────────────────────────────────────────

/**
 * @dev The runtime bytecode that lives at SAFE_SINGLETON_FACTORY_ADDRESS
 *      after deployment. Used in tests to verify the factory was deployed
 *      correctly (codehash check).
 *
 * This is an extremely compact CREATE2 factory (~30 bytes). Annotated assembly:
 *
 *   // ── Receive calldata: [bytes32 salt] [bytes initCode] ──────────────────
 *   7fff...fe   PUSH32 0xffff...fe  // bitmask: clears the lowest bit
 *   03          SUB                 // (not used as SUB here — this is CALLDATASIZE arithmetic)
 *
 *   // Simplified logic:
 *   //   1. Copy the entire calldata (salt + initCode) into memory.
 *   //   2. Call CREATE2(value=0, offset=32, size=calldatasize-32, salt=calldataload(0))
 *   //      i.e. the first 32 bytes of calldata are the salt; the rest is initCode.
 *   //   3. If CREATE2 returns address(0) (deploy failed), revert.
 *   //   4. Otherwise return the 20-byte deployed address.
 *
 *   CALLDATASIZE  // total calldata length
 *   PUSH1 0x20   // 32 (salt length)
 *   SUB          // initCode length = calldatasize - 32
 *   DUP1
 *   PUSH1 0x20
 *   ...          // copy initCode from calldata[32:] into memory[0:]
 *   CREATE2      // deploy with provided salt
 *   ...          // revert on zero address, otherwise return address
 *
 * Callers pass:  abi.encodePacked(bytes32 salt, bytes initCode)
 * Returns:       the 20-byte address of the newly deployed contract,
 *                or reverts if deployment failed.
 */
bytes constant SAFE_SINGLETON_FACTORY_CODE =
    hex"7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe0"
    hex"3601600081602082378035828234f58015156039578182fd5b808252505050"
    hex"6014600cf3";
