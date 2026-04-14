// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

/**
 * @title AuthorizerUpgradeable
 * @notice A minimal, upgradeable authorization registry that records which
 *         addresses ("wards") are permitted to act on behalf of specific target
 *         addresses ("aims").
 *
 * @dev Designed to sit behind a proxy (e.g. TransparentProxy).  The split
 *      between the constructor and {init} is the standard "initializer pattern"
 *      required by upgradeable contracts:
 *
 *      • The constructor runs once on the *implementation* contract and
 *        permanently freezes it (sets needsInit = 0) so that the bare
 *        implementation can never be initialized or exploited directly.
 *
 *      • {init} runs once on the *proxy* (via delegatecall), where storage
 *        starts with needsInit = 1, allowing a one-time bootstrap of wards.
 *
 *  Storage layout (proxy context):
 *  ┌─────────────────────────────────────────────────────┐
 *  │ slot 0 │ needsInit : uint256  (0 = frozen/inited)   │
 *  │ slot 1 │ wards     : mapping(address =>             │
 *  │        │               mapping(address => uint256)) │
 *  └─────────────────────────────────────────────────────┘
 *
 * @custom:security The one-time init guard relies entirely on `needsInit`.
 *         If a proxy is deployed but {init} is never called, `needsInit`
 *         remains 1 and anyone can call {init} — callers should initialize
 *         atomically in the same transaction as deployment.
 */
contract AuthorizerUpgradeable {

    // -------------------------------------------------------------------------
    // State
    // -------------------------------------------------------------------------

    /**
     * @notice Initialization gate.
     *         • 1 (default in proxy storage) → {init} has not yet been called;
     *           initialization is still permitted.
     *         • 0 → contract is frozen; {init} will revert.
     * @dev    Declared with a default value of 1 so that a freshly deployed
     *         proxy (whose storage is all zeros) would need a special case.
     *         Instead the value is written as `1` here, meaning the *proxy's*
     *         storage slot inherits `1` before {init} is called.
     *         The constructor immediately overrides this to `0` on the
     *         implementation contract itself, permanently freezing it.
     */
    uint256 public needsInit = 1;

    /**
     * @notice Two-dimensional authorization map.
     *         wards[usr][aim] == 1  →  `usr` is authorized to act on `aim`.
     *         wards[usr][aim] == 0  →  not authorized (default).
     * @dev    Kept private; external access is provided through {can}.
     */
    mapping(address => mapping(address => uint256)) private wards;

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    /**
     * @notice Emitted whenever a ward–aim relationship is established.
     * @param usr The address being granted authorization (the ward).
     * @param aim The target address `usr` is now authorized to act on.
     */
    event Rely(address indexed usr, address aim);

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    /**
     * @notice Freezes the *implementation* contract so it can never be
     *         initialized or used directly.
     * @dev    In an upgradeable proxy setup the constructor only executes in
     *         the context of the implementation's own storage — not the proxy's.
     *         Setting `needsInit = 0` here ensures that if someone calls {init}
     *         directly on the implementation address, the `needsInit != 0` guard
     *         will revert, preventing an attacker from taking over the bare
     *         implementation and potentially poisoning shared state.
     *
     * @custom:security This mirrors OpenZeppelin's `_disableInitializers()` pattern.
     */
    constructor() {
        needsInit = 0; // freeze implementation — only the proxy's storage stays at 1
    }

    // -------------------------------------------------------------------------
    // Initializer (runs via delegatecall through the proxy, once)
    // -------------------------------------------------------------------------

    /**
     * @notice One-time initialization: registers an ordered list of ward–aim
     *         pairs and then permanently locks the contract against re-init.
     * @dev    Callable exactly once per proxy instance. After this call,
     *         `needsInit` is set to 0 and any subsequent call reverts.
     *
     *         The function accepts parallel arrays instead of a struct array to
     *         keep ABI encoding simple; callers must ensure the arrays are the
     *         same length — if `_aims` is shorter than `_wards` the loop will
     *         revert with an out-of-bounds panic.
     *
     * @param _wards Ordered list of addresses to authorize.
     * @param _aims  Ordered list of target addresses corresponding to each ward.
     *
     * @custom:security No access control beyond the `needsInit` guard — whoever
     *         calls this first wins. Deploy and initialize in a single atomic
     *         transaction to eliminate the front-running window.
     */
    function init(address[] memory _wards, address[] memory _aims) external {
        // Prevent re-initialization; also prevents direct calls on the
        // frozen implementation where needsInit was set to 0 in the constructor.
        require(needsInit != 0, "cannot init");

        // Register each ward–aim pair.
        for (uint256 i = 0; i < _wards.length; i++) {
            _rely(_wards[i], _aims[i]);
        }

        // Lock the contract — no further initialization is possible.
        needsInit = 0;
    }

    // -------------------------------------------------------------------------
    // Internal helpers
    // -------------------------------------------------------------------------

    /**
     * @notice Grants `usr` authorization to act on `aim`.
     * @dev    Sets the mapping entry to 1 and emits {Rely}.
     *         Writing `1` (rather than `true`) keeps the value type consistent
     *         with `needsInit` and avoids a bool-to-uint conversion.
     *         Private visibility ensures only {init} can invoke this.
     * @param usr Address to authorize.
     * @param aim Target address `usr` will be authorized against.
     */
    function _rely(address usr, address aim) private {
        wards[usr][aim] = 1;
        emit Rely(usr, aim);
    }

    // -------------------------------------------------------------------------
    // Views
    // -------------------------------------------------------------------------

    /**
     * @notice Checks whether `usr` is authorized to act on `aim`.
     * @dev    Returns `true` iff `wards[usr][aim] == 1`.  Any unset entry
     *         defaults to 0 (unauthorized) due to Solidity's zero-initialization
     *         of storage.
     * @param usr Address whose authorization is being queried.
     * @param aim Target address to check authorization against.
     * @return    `true` if authorized, `false` otherwise.
     */
    function can(address usr, address aim) external view returns (bool) {
        return wards[usr][aim] == 1;
    }
}
