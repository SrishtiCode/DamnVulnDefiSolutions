// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeProxyFactory} from "@safe-global/safe-smart-account/contracts/proxies/SafeProxyFactory.sol";

/**
 * @title  WalletDeployer
 * @notice A permissioned Safe-wallet deployment bounty contract.
 *
 * OVERVIEW
 * ────────
 * Anyone who successfully deploys a Safe proxy at a pre-agreed address gets
 * paid a 1-token (1e18 wei) reward from this contract's token balance.
 *
 * An optional external "authorizer" contract (mom) can gate which
 * (caller, target-address) pairs are allowed to collect the reward.
 *
 * NAMING CONVENTION (obfuscated on purpose in the challenge)
 * ──────────────────────────────────────────────────────────
 *   cook  → SafeProxyFactory  (the thing that cooks up new proxies)
 *   cpy   → Safe singleton    (the implementation/copy that proxies delegate to)
 *   pay   → reward amount     (what you get paid)
 *   chief → admin             (the head honcho)
 *   gem   → ERC-20 token      (the reward gem)
 *   mom   → authorizer        (the rule-setter)
 *   hat   → unused slot       (red herring / placeholder)
 *   drop  → deploy + pay      (drop a wallet, collect bounty)
 *   rule  → set authorizer    (lay down the law)
 *   can   → is authorized?    (can you do this?)
 *   aim   → target address    (where the Safe must land)
 *   wat   → initializer data  (what to call on setup)
 *   num   → CREATE2 nonce     (number used once to hit the right address)
 */
contract WalletDeployer {

    // ── Immutable configuration (set once in constructor) ────────────────────

    /// @notice The SafeProxyFactory used to deploy new Safe proxies.
    ///         Called `cook` because it "cooks up" wallets.
    SafeProxyFactory public immutable cook;

    /// @notice The Safe singleton (logic / implementation) contract address.
    ///         Every proxy deployed by `cook` delegates all calls here.
    ///         Called `cpy` because proxies are copies of this template.
    address public immutable cpy;

    /// @notice Fixed reward paid to a successful deployer: 1 token (1e18 wei).
    ///         The contract must hold at least this many tokens to pay out.
    ///         Named `pay` — it doubles as a function (pay()) that returns
    ///         the amount, letting setUp() read the value for pre-funding.
    uint256 public constant pay = 1 ether;

    /// @notice The privileged admin that may configure the authorizer once.
    ///         Immutable — set in the constructor and never changeable.
    address public immutable chief;

    /// @notice ERC-20 token distributed as the deployment reward.
    ///         Immutable — the gem never changes.
    address public immutable gem;

    // ── Mutable state ────────────────────────────────────────────────────────

    /// @notice Optional external authorizer contract.
    ///         If non-zero, every call to drop() is gated by mom.can(u, a).
    ///         Can only be set once (see rule()); starts as address(0).
    ///
    /// @dev STORAGE SLOT 0 — the assembly in can() relies on this being at
    ///      slot 0 so it can read it with `sload(0)`.
    address public mom;

    /// @notice Unused storage variable — likely a placeholder or deliberate
    ///         red herring to confuse auditors / challenge solvers.
    address public hat;

    /// @dev Catch-all revert error used everywhere in this contract.
    error Boom();

    // ── Constructor ──────────────────────────────────────────────────────────

    /**
     * @param _gem   Address of the ERC-20 reward token.
     * @param _cook  Address of the SafeProxyFactory.
     * @param _cpy   Address of the Safe singleton (implementation).
     * @param _chief Address of the admin who may later call rule().
     */
    constructor(address _gem, address _cook, address _cpy, address _chief) {
        gem   = _gem;
        cook  = SafeProxyFactory(_cook);
        cpy   = _cpy;
        chief = _chief;
    }

    // ── Admin ────────────────────────────────────────────────────────────────

    /**
     * @notice One-time setter for the authorization contract (mom).
     *
     * @param _mom Address of the AuthorizerUpgradeable contract that will
     *             gate deployments via its can(address,address) function.
     *
     * GUARDS (all must pass, otherwise reverts with Boom()):
     *   • msg.sender == chief   — only the admin may call this
     *   • _mom != address(0)    — zero address is not a valid authorizer
     *   • mom == address(0)     — can only be set once (write-once pattern)
     *
     * Once set, mom cannot be changed or removed.
     */
    function rule(address _mom) external {
        if (msg.sender != chief || _mom == address(0) || mom != address(0)) {
            revert Boom();
        }
        mom = _mom;
    }

    // ── Core logic ───────────────────────────────────────────────────────────

    /**
     * @notice Deploy a Safe proxy at `aim` and collect a token reward.
     *
     * @param aim Target address — the Safe proxy MUST land exactly here;
     *            computed off-chain via CREATE2 address prediction.
     * @param wat Initializer calldata, i.e. the ABI-encoded Safe.setup(...)
     *            call that configures owners, threshold, modules, etc.
     *            This data is also an input to the CREATE2 salt, so changing
     *            even one byte shifts the resulting address.
     * @param num The nonce passed to SafeProxyFactory.createProxyWithNonce().
     *            Together with keccak256(wat), it forms the CREATE2 salt:
     *              salt = keccak256(abi.encodePacked(keccak256(wat), num))
     *            Brute-forcing `num` is how we find the right salt to hit `aim`.
     * @return    true if the wallet was deployed and (if eligible) the reward
     *            was transferred; false if authorization failed or the deployed
     *            address didn't match `aim`.
     *
     * FLOW
     * ────
     *  1. Authorization gate  – skip if mom == 0, else call can(caller, aim).
     *                           Returns false (not reverts) on failure.
     *  2. Proxy deployment    – delegates to cook.createProxyWithNonce().
     *                           Returns false if deployed address ≠ aim.
     *  3. Reward transfer     – sends `pay` tokens to msg.sender if the
     *                           contract balance is sufficient.
     *
     * ATTACK SURFACE (relevant to the challenge)
     * ───────────────────────────────────────────
     * Step 1 calls can() which in turn calls mom.can().  If the attacker can
     * manipulate the authorizer (e.g. via the uninitialized-proxy bug), they
     * can pass the authorization check for any (caller, aim) pair and collect
     * the reward after deploying the Safe.
     */
    function drop(address aim, bytes memory wat, uint256 num) external returns (bool) {

        // ── Step 1: Authorization gate ────────────────────────────────────────
        // If an authorizer is configured, verify that msg.sender is allowed to
        // deploy a Safe at `aim`.  Silently returns false on failure rather than
        // reverting, so the caller knows the deployment was rejected.
        if (mom != address(0) && !can(msg.sender, aim)) {
            return false;
        }

        // ── Step 2: Deploy the Safe proxy ─────────────────────────────────────
        // createProxyWithNonce(singleton, initializer, saltNonce):
        //   - Creates a minimal SafeProxy whose fallback delegates to `cpy`.
        //   - Calls Safe.setup(...) with `wat` as the initializer.
        //   - Uses CREATE2 with salt = keccak256(keccak256(wat) ‖ num).
        //
        // If the resulting address doesn't match the pre-agreed `aim`, refuse
        // the reward — this prevents gaming the bounty for unintended addresses.
        if (address(cook.createProxyWithNonce(cpy, wat, num)) != aim) {
            return false;
        }

        // ── Step 3: Pay the reward ────────────────────────────────────────────
        // Transfer exactly `pay` (1e18) tokens to the caller.
        // Silently skips payment if the contract is underfunded, so callers
        // should check the balance before calling drop() if they need the reward.
        if (IERC20(gem).balanceOf(address(this)) >= pay) {
            IERC20(gem).transfer(msg.sender, pay);
        }

        return true;
    }

    // ── Internal helpers ─────────────────────────────────────────────────────

    /**
     * @notice Checks whether address `u` is authorized to deploy at address `a`.
     *
     * @param u  The caller whose permission is being checked (u = "user").
     * @param a  The target deployment address (a = "aim").
     * @return y True if the authorizer grants permission, false otherwise.
     *
     * IMPLEMENTATION DETAIL — hand-written assembly
     * ──────────────────────────────────────────────
     * This is equivalent to:
     *   IAuthorizer(mom).can(u, a)
     * but written in assembly to:
     *   (a) read mom from storage slot 0 directly,
     *   (b) skip ABI decoder overhead,
     *   (c) obfuscate intent (challenge flavor).
     *
     * SELECTOR: bytes4(keccak256("can(address,address)")) = 0x4538c4eb
     *
     * CALLDATA LAYOUT (68 bytes total):
     *   [0x00 – 0x03]  selector  0x4538c4eb
     *   [0x04 – 0x23]  u         (left-padded to 32 bytes)
     *   [0x24 – 0x43]  a         (left-padded to 32 bytes)
     *
     * FAILURE MODES:
     *   • mom has no code (extcodesize == 0) → stop()  [silent halt, no revert]
     *   • staticcall returns 0 (reverted)   → stop()  [silent halt, no revert]
     *
     * WHY stop() AND NOT revert()?
     *   stop() ends execution successfully (returns empty data) rather than
     *   reverting.  The caller (drop()) then receives `false` from the assembly
     *   return area — causing drop() to silently return false instead of
     *   bubbling up a revert.  This is intentional obfuscation.
     *
     * SECURITY NOTE (relevant to the exploit):
     *   The assembly reads mom from slot 0 with `sload(0)`.  This works because
     *   `mom` is declared as the FIRST storage variable in this contract.
     *   If the storage layout ever changes, this assembly breaks silently.
     */
    function can(address u, address a) public view returns (bool y) {
        assembly {
            // ── Load authorizer address from storage slot 0 (== mom) ──────────
            let m := sload(0)

            // ── Guard: mom must be a deployed contract ────────────────────────
            // If mom has no code (e.g. it's an EOA or was self-destructed),
            // stop() halts execution without reverting.
            if iszero(extcodesize(m)) { stop() }

            // ── Build calldata in scratch space ───────────────────────────────
            // p = free memory pointer; advance it by 0x44 (68 bytes).
            let p := mload(0x40)
            mstore(0x40, add(p, 0x44))

            // Write selector: can(address,address) → 0x4538c4eb
            // shl(0xe0, x) shifts x into the top 4 bytes of a 32-byte word,
            // which is how ABI encoding places a 4-byte selector.
            mstore(p, shl(0xe0, 0x4538c4eb))

            // Write first argument: u (caller address), ABI-padded to 32 bytes.
            mstore(add(p, 0x04), u)

            // Write second argument: a (target address), ABI-padded to 32 bytes.
            mstore(add(p, 0x24), a)

            // ── staticcall mom.can(u, a) ──────────────────────────────────────
            // staticcall prevents the authorizer from making state changes.
            // On failure (return value 0) → stop() instead of revert.
            // On success, the 32-byte return value is written back to p.
            if iszero(staticcall(gas(), m, p, 0x44, p, 0x20)) { stop() }

            // ── Read the boolean return value ─────────────────────────────────
            // A Solidity bool is ABI-encoded as a 32-byte word (0 or 1).
            y := mload(p)
        }
    }
}
