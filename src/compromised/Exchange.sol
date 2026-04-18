// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {TrustfulOracle} from "./TrustfulOracle.sol";
import {DamnValuableNFT} from "../DamnValuableNFT.sol";

/**
 * @title Exchange
 * @notice A marketplace contract for buying and selling DamnValuableNFTs.
 *         Prices are determined dynamically by a trusted oracle (median price feed).
 *         Protected against reentrancy via OpenZeppelin's ReentrancyGuard.
 *
 * @dev VULNERABILITY NOTE (Damn Vulnerable DeFi):
 *      The oracle is "trustful" — if oracle sources are compromised or manipulated,
 *      an attacker can artificially deflate or inflate the NFT price to drain funds.
 *      This is an intentional oracle manipulation vulnerability for educational purposes.
 */
contract Exchange is ReentrancyGuard {
    using Address for address payable;

    /// @notice The NFT token contract created and managed by this exchange
    DamnValuableNFT public immutable token;

    /// @notice The oracle contract used to fetch the median NFT price in wei
    TrustfulOracle public immutable oracle;

    // -------------------------------------------------------------------------
    // Custom Errors
    // -------------------------------------------------------------------------

    /// @notice Thrown when ETH payment is zero or insufficient for the NFT price
    error InvalidPayment();

    /// @notice Thrown when the caller tries to sell an NFT they do not own
    /// @param id The token ID that was checked
    error SellerNotOwner(uint256 id);

    /// @notice Thrown when this contract is not approved to transfer the seller's NFT
    error TransferNotApproved();

    /// @notice Thrown when the exchange lacks enough ETH to pay the seller
    error NotEnoughFunds();

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    /// @notice Emitted when an NFT is successfully purchased
    /// @param buyer  Address of the buyer who received the NFT
    /// @param tokenId The newly minted token ID
    /// @param price  Amount of wei paid for the NFT (oracle median price)
    event TokenBought(address indexed buyer, uint256 tokenId, uint256 price);

    /// @notice Emitted when an NFT is successfully sold back to the exchange
    /// @param seller  Address of the seller who received the ETH payout
    /// @param tokenId The token ID that was burned
    /// @param price   Amount of wei paid out to the seller (oracle median price)
    event TokenSold(address indexed seller, uint256 tokenId, uint256 price);

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    /**
     * @notice Deploys the Exchange, creates the NFT contract, and seeds it with ETH.
     * @dev    Ownership of the NFT contract is immediately renounced so no single
     *         party controls minting after deployment — only this Exchange can mint
     *         (via safeMint called inside buyOne).
     * @param _oracle Address of the deployed TrustfulOracle price feed
     */
    constructor(address _oracle) payable {
        // Deploy a new DamnValuableNFT and store its reference
        token = new DamnValuableNFT();

        // Renounce NFT ownership so the exchange is the sole minting authority
        token.renounceOwnership();

        // Store the oracle reference for price lookups
        oracle = TrustfulOracle(_oracle);
    }

    // -------------------------------------------------------------------------
    // External Functions
    // -------------------------------------------------------------------------

    /**
     * @notice Allows a user to buy one NFT at the current oracle median price.
     * @dev    - Caller must send at least `oracle.getMedianPrice(token.symbol())` wei.
     *         - Any ETH sent above the price is refunded to the caller.
     *         - Uses `nonReentrant` to block reentrancy attacks during the ETH refund.
     *
     * @dev VULNERABILITY: If the oracle price is manipulated to 0 or near-0,
     *      an attacker can buy NFTs for free (or nearly free) and then sell them
     *      back at an inflated price to drain the contract's ETH balance.
     *
     * @return id The token ID of the newly minted NFT sent to msg.sender
     */
    function buyOne() external payable nonReentrant returns (uint256 id) {
        // Reject calls that send no ETH at all
        if (msg.value == 0) {
            revert InvalidPayment();
        }

        // Fetch the current NFT price in wei from the oracle's median calculation
        // Price is denominated as [wei / NFT]
        uint256 price = oracle.getMedianPrice(token.symbol());

        // Ensure the buyer has sent enough ETH to cover the oracle price
        if (msg.value < price) {
            revert InvalidPayment();
        }

        // Mint a new NFT directly to the buyer and record the new token ID
        id = token.safeMint(msg.sender);

        // Refund any ETH sent above the exact price back to the buyer
        // `unchecked` is safe here because msg.value >= price is guaranteed above
        unchecked {
            payable(msg.sender).sendValue(msg.value - price);
        }

        emit TokenBought(msg.sender, id, price);
    }

    /**
     * @notice Allows an NFT owner to sell their token back to the exchange for ETH.
     * @dev    - Caller must own the token and have approved this contract to transfer it.
     *         - The exchange must hold enough ETH to cover the oracle median price.
     *         - The NFT is transferred to the exchange and then permanently burned.
     *         - Uses `nonReentrant` to block reentrancy attacks during the ETH payout.
     *
     * @dev VULNERABILITY: If the oracle price is manipulated to an inflated value,
     *      an attacker can sell NFTs back to the exchange at a massive premium,
     *      draining all ETH held by the contract.
     *
     * @param id The token ID the seller wishes to sell
     */
    function sellOne(uint256 id) external nonReentrant {
        // Only the current owner of the NFT may sell it
        if (msg.sender != token.ownerOf(id)) {
            revert SellerNotOwner(id);
        }

        // The seller must have pre-approved this contract to move their token
        // (Required for the transferFrom call below)
        if (token.getApproved(id) != address(this)) {
            revert TransferNotApproved();
        }

        // Fetch the current NFT price in wei from the oracle's median calculation
        // Price is denominated as [wei / NFT]
        uint256 price = oracle.getMedianPrice(token.symbol());

        // Ensure the exchange has enough ETH in its balance to pay the seller
        if (address(this).balance < price) {
            revert NotEnoughFunds();
        }

        // Pull the NFT from the seller into this contract
        token.transferFrom(msg.sender, address(this), id);

        // Permanently destroy the NFT — it cannot be re-sold or re-used
        token.burn(id);

        // Pay the seller the oracle median price in ETH
        payable(msg.sender).sendValue(price);

        emit TokenSold(msg.sender, id, price);
    }

    // -------------------------------------------------------------------------
    // Fallback
    // -------------------------------------------------------------------------

    /**
     * @notice Allows the contract to receive plain ETH transfers (e.g., initial funding).
     * @dev    No logic is executed; ETH is simply added to the contract's balance.
     */
    receive() external payable {}
}
