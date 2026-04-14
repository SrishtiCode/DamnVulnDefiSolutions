// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {TransparentProxy} from "./TransparentProxy.sol";
import {AuthorizerUpgradeable} from "./AuthorizerUpgradeable.sol";

/**
 * @title AuthorizerFactory
 * @notice Atomic factory for deploying a fully initialized and configured
 *         AuthorizerUpgradeable instance behind a TransparentProxy in a
 *         single transaction.
 *
 * @dev Bundling deployment, initialization, and upgrader assignment into one
 *      transaction is a critical security property: it eliminates the
 *      front-running window that would exist if these steps were performed
 *      separately, preventing an attacker from calling {AuthorizerUpgradeable.init}
 *      or {TransparentProxy.setUpgrader} before the legitimate owner does.
 *
 * Deployment sequence (all within one transaction):
 *
 *  1. Deploy AuthorizerUpgradeable  ←  bare implementation (frozen by constructor)
 *         │
 *         ▼
 *  2. Deploy TransparentProxy       ←  wraps impl; delegatecalls init(wards, aims)
 *         │
 *         ▼
 *  3. Assert needsInit == 0         ←  proves init ran; reverts everything if not
 *         │
 *         ▼
 *  4. setUpgrader(upgrader)         ←  hands upgrade rights to the intended party
 */
contract AuthorizerFactory {

    // -------------------------------------------------------------------------
    // External functions
    // -------------------------------------------------------------------------

    /**
     * @notice Deploys a new AuthorizerUpgradeable behind a TransparentProxy,
     *         initializes it with the supplied ward–aim pairs, and assigns the
     *         upgrader role — all atomically.
     *
     * @dev Execution steps in detail:
     *
     *      Step 1 — Implementation deployment:
     *        `new AuthorizerUpgradeable()` deploys the logic contract. Its
     *        constructor immediately sets `needsInit = 0`, freezing the
     *        implementation so it cannot be initialized directly.
     *
     *      Step 2 — Proxy deployment + initialization:
     *        `new TransparentProxy(impl, initData)` deploys the proxy and,
     *        inside its constructor, delegatecalls `init(wards, aims)` on the
     *        implementation. Because delegatecall executes in the *proxy's*
     *        storage context (where `needsInit` starts at 1), the init guard
     *        passes, wards are registered, and `needsInit` is set to 0 in the
     *        proxy's storage.
     *
     *      Step 3 — Invariant assertion:
     *        Reads `needsInit` back through the proxy to confirm initialization
     *        completed successfully. If the value is not 0 the entire transaction
     *        reverts via `assert`, unwinding all deployments — no half-initialized
     *        proxy is ever left on-chain.
     *
     *      Step 4 — Upgrader assignment:
     *        Calls {TransparentProxy.setUpgrader} through the proxy (cast to
     *        `payable` to satisfy the call interface). At this point
     *        `AuthorizerFactory` is still the ERC1967 admin (set during proxy
     *        construction), so the `!admin` guard inside `setUpgrader` passes.
     *
     * @param wards    Ordered list of addresses to authorize as wards.
     *                 Must be the same length as `aims`.
     * @param aims     Ordered list of target addresses each ward may act on.
     *                 Must be the same length as `wards`.
     * @param upgrader Address that will receive the exclusive right to upgrade
     *                 the proxy's implementation via `upgradeToAndCall`.
     *
     * @return authorizer Address of the newly deployed TransparentProxy, which
     *                    also serves as the canonical authorizer endpoint.
     *
     * @custom:security No access control on this function — anyone can deploy a
     *         new authorizer instance. Callers are responsible for supplying
     *         correct `wards`, `aims`, and `upgrader` values, as none of these
     *         can be changed after deployment (wards are write-once; the upgrader
     *         can only be rotated by the ERC1967 admin, which remains this
     *         factory's deployer after the call).
     */
    function deployWithProxy(address[] memory wards, address[] memory aims, address upgrader)
        external
        returns (address authorizer)
    {
        authorizer = address(
            new TransparentProxy(                                   // Step 2: deploy proxy
                address(new AuthorizerUpgradeable()),               // Step 1: deploy & freeze implementation
                abi.encodeCall(AuthorizerUpgradeable.init, (wards, aims)) // Step 2a: encode init calldata
            )                                                       //   → proxy delegatecalls init on construction
        );

        // Step 3: Invariant check — init must have executed and set needsInit to 0.
        // Using `assert` (rather than `require`) signals this is an internal
        // invariant violation (a bug) rather than a user input error; it also
        // consumes all remaining gas, making failed deployments maximally visible.
        assert(AuthorizerUpgradeable(authorizer).needsInit() == 0);

        // Step 4: Transfer the upgrader role to the intended party.
        // The proxy is cast to `payable` because TransparentProxy inherits
        // ERC1967Proxy which has a `receive` function, requiring a payable address
        // to call its admin-facing functions without a compiler warning.
        TransparentProxy(payable(authorizer)).setUpgrader(upgrader);
    }
}
