// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {TrustfulOracle} from "./TrustfulOracle.sol";

/**
 * @title  TrustfulOracleInitializer
 * @notice A one-shot factory contract that deploys a TrustfulOracle and seeds it
 *         with an initial set of (source, symbol, price) triples — all in a single
 *         atomic transaction.
 *
 * @dev    Design rationale — why a separate initializer contract?
 *         TrustfulOracle's setupInitialPrices() is gated behind INITIALIZER_ROLE,
 *         which is granted to whoever deploys it (if enableInitialization = true).
 *         By deploying through this factory:
 *           1. The factory's constructor becomes the INITIALIZER_ROLE holder.
 *           2. It immediately calls setupInitialPrices(), which self-revokes the role.
 *           3. Once the constructor returns, no address holds INITIALIZER_ROLE ever again.
 *         This means initial prices are set trustlessly in one tx with zero lingering privileges.
 *
 * @dev VULNERABILITY NOTE (Damn Vulnerable DeFi):
 *      The security of the resulting oracle depends entirely on the integrity of the
 *      `sources` addresses passed in at deployment. If an attacker controls a majority
 *      of those private keys, they can manipulate the median price at will.
 *      This contract itself is not the vulnerability — it is a correct deployment pattern.
 *      The weakness lives in how sources are chosen and secured off-chain.
 */
contract TrustfulOracleInitializer {

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    /**
     * @notice Emitted once the TrustfulOracle has been deployed and initialized.
     * @dev    Allows off-chain tooling (scripts, front-ends, indexers) to discover
     *         the oracle address without needing to read contract storage directly.
     * @param oracleAddress The address of the newly deployed TrustfulOracle contract.
     */
    event NewTrustfulOracle(address oracleAddress);

    // -------------------------------------------------------------------------
    // State
    // -------------------------------------------------------------------------

    /**
     * @notice The TrustfulOracle deployed and initialized by this factory.
     * @dev    Public so any external caller or contract can read the oracle address
     *         after deployment. Immutability is implicit — it is only written once
     *         in the constructor and never updated again.
     */
    TrustfulOracle public oracle;

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    /**
     * @notice Deploys a TrustfulOracle and seeds it with initial prices atomically.
     *
     * @dev    Execution flow:
     *           Step 1 — new TrustfulOracle(sources, true)
     *                    Deploys the oracle and grants INITIALIZER_ROLE to THIS contract
     *                    (msg.sender inside TrustfulOracle's constructor = this factory).
     *
     *           Step 2 — oracle.setupInitialPrices(sources, symbols, initialPrices)
     *                    Uses the INITIALIZER_ROLE to bulk-set all starting prices,
     *                    then self-revokes the role via renounceRole() at the end.
     *                    After this call, INITIALIZER_ROLE is permanently burned —
     *                    no address can ever call setupInitialPrices() again.
     *
     *           Step 3 — emit NewTrustfulOracle(address(oracle))
     *                    Broadcasts the oracle address for off-chain consumers.
     *
     *         All three steps execute inside one transaction, so there is no window
     *         where the oracle is deployed-but-uninitialized and vulnerable to
     *         front-running by a third party trying to call setupInitialPrices() first.
     *
     * @dev    Array alignment requirement (enforced inside setupInitialPrices):
     *           sources.length == symbols.length == initialPrices.length
     *         Each index i represents one (source, symbol, price) triple:
     *           sources[i]       → the trusted reporter address for this entry
     *           symbols[i]       → the token symbol this reporter is pricing (e.g. "DVNFT")
     *           initialPrices[i] → the starting price in wei reported by sources[i]
     *
     * @param sources        Addresses of the trusted price-reporting sources.
     *                       These are granted TRUSTED_SOURCE_ROLE in TrustfulOracle
     *                       and will be able to call postPrice() after deployment.
     * @param symbols        Token symbols each source is reporting a price for.
     *                       Multiple sources can report prices for the same symbol —
     *                       the oracle will compute their median.
     * @param initialPrices  Starting prices in wei for each (source, symbol) pair.
     *                       These become the oracle's on-chain prices immediately.
     */
    constructor(
        address[] memory sources,
        string[]  memory symbols,
        uint256[] memory initialPrices
    ) {
        // Step 1: Deploy the TrustfulOracle.
        // Passing `true` grants INITIALIZER_ROLE to this contract (the deployer)
        // so that Step 2 is authorized. Without this flag the next call would revert.
        oracle = new TrustfulOracle(sources, true);

        // Step 2: Seed the oracle with initial prices.
        // Internally, setupInitialPrices() iterates the arrays, calls _setPrice() for
        // each triple, then calls renounceRole(INITIALIZER_ROLE, msg.sender) — permanently
        // burning the role. After this line, no one can ever call setupInitialPrices() again.
        oracle.setupInitialPrices(sources, symbols, initialPrices);

        // Step 3: Announce the oracle address on-chain for off-chain consumers.
        // Indexers, deployment scripts, and front-ends can listen for this event
        // instead of hard-coding or storing the address separately.
        emit NewTrustfulOracle(address(oracle));
    }
}
