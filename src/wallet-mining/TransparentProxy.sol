// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import {AuthorizerUpgradeable} from "./AuthorizerUpgradeable.sol";

/**
 * @title TransparentProxy
 * @notice A transparent upgradeable proxy that separates upgrade privileges from
 *         regular call routing. An "upgrader" role (managed by the ERC1967 admin)
 *         is the only address allowed to trigger implementation upgrades.
 *
 * @dev Inherits OpenZeppelin's ERC1967Proxy for storage-slot-standardized proxy
 *      behaviour. The admin (set at construction) can reassign the upgrader via
 *      {setUpgrader}. All non-upgrader callers are forwarded transparently to the
 *      current implementation.
 *
 * ┌─────────────┐   upgradeToAndCall   ┌──────────────────────┐
 * │   upgrader  │ ───────────────────► │  TransparentProxy    │
 * └─────────────┘                      │  (_dispatchUpgrade)  │
 *                                      └──────────┬───────────┘
 *      other callers                              │ delegatecall
 *          │                                      ▼
 *          └──────────────────────────► Implementation contract
 */
contract TransparentProxy is ERC1967Proxy {

    // -------------------------------------------------------------------------
    // State
    // -------------------------------------------------------------------------

    /**
     * @notice Address that holds the exclusive right to upgrade the proxy's
     *         implementation. Defaults to the deployer; can be changed by the
     *         ERC1967 admin via {setUpgrader}.
     */
    address public upgrader = msg.sender;

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    /**
     * @notice Deploys the proxy, points it at `_logic`, and optionally calls an
     *         initialiser on the implementation.
     * @dev    Also records `msg.sender` as the ERC1967 admin so that admin-only
     *         functions (e.g. {setUpgrader}) are protected from day one.
     * @param _logic Address of the initial implementation contract.
     * @param _data  ABI-encoded initialiser call forwarded to `_logic` via
     *               delegatecall. Pass an empty bytes value to skip initialisation.
     */
    constructor(address _logic, bytes memory _data) ERC1967Proxy(_logic, _data) {
        // Store deployer as the ERC1967 admin in the standardised storage slot.
        ERC1967Utils.changeAdmin(msg.sender);
    }

    // -------------------------------------------------------------------------
    // Admin functions
    // -------------------------------------------------------------------------

    /**
     * @notice Transfers the upgrader role to `who`.
     * @dev    Caller must be the current ERC1967 admin. The admin itself is NOT
     *         automatically granted the upgrader role — those two roles are
     *         intentionally separate.
     * @param who New upgrader address.
     */
    function setUpgrader(address who) external {
        require(msg.sender == ERC1967Utils.getAdmin(), "!admin");
        upgrader = who;
    }

    // -------------------------------------------------------------------------
    // View helpers
    // -------------------------------------------------------------------------

    /**
     * @notice Returns `true` when `who` holds the upgrader role.
     * @param who Address to check.
     */
    function isUpgrader(address who) public view returns (bool) {
        return who == upgrader;
    }

    // -------------------------------------------------------------------------
    // Internal routing
    // -------------------------------------------------------------------------

    /**
     * @notice Intercepts every call before it reaches the implementation.
     * @dev    Two routing paths exist:
     *
     *         1. **Upgrader path** — when `msg.sender == upgrader`:
     *            Only the `upgradeToAndCall(address,bytes)` selector is accepted.
     *            Any other selector reverts, preventing the upgrader from
     *            accidentally (or maliciously) invoking implementation logic.
     *
     *         2. **Default path** — all other callers are delegated transparently
     *            to the current implementation via the parent `_fallback`.
     *
     * @custom:security The selector check `msg.sig == bytes4(keccak256(...))` is
     *         the primary guard against an upgrader calling arbitrary functions.
     *         Note: the keccak256 argument has a space after the comma
     *         ("address, bytes") which must match exactly when encoding calldata
     *         off-chain, otherwise the selector comparison will fail.
     */
    function _fallback() internal override {
        if (isUpgrader(msg.sender)) {
            // Upgrader is only permitted to call upgradeToAndCall — enforce the
            // expected 4-byte selector before dispatching.
            require(msg.sig == bytes4(keccak256("upgradeToAndCall(address, bytes)")));
            _dispatchUpgradeToAndCall();
        } else {
            // Regular callers: forward the full calldata to the implementation
            // via delegatecall (handled by ERC1967Proxy._fallback).
            super._fallback();
        }
    }

    /**
     * @notice Decodes upgrade calldata and performs the implementation swap.
     * @dev    Strips the 4-byte selector from `msg.data`, then ABI-decodes the
     *         remaining bytes into `(address newImplementation, bytes data)`.
     *         Delegates the actual slot update and optional initialiser call to
     *         {ERC1967Utils.upgradeToAndCall}, which emits an {Upgraded} event.
     *
     * @custom:security This function is `private` — it can only be reached
     *         through {_fallback} after the upgrader check has passed.
     */
    function _dispatchUpgradeToAndCall() private {
        // msg.data[4:] skips the 4-byte function selector to isolate the
        // ABI-encoded (address, bytes) arguments.
        (address newImplementation, bytes memory data) = abi.decode(msg.data[4:], (address, bytes));

        // Validate the new address, update the ERC1967 implementation slot,
        // and optionally delegatecall the initialiser `data` on the new impl.
        ERC1967Utils.upgradeToAndCall(newImplementation, data);
    }
}
