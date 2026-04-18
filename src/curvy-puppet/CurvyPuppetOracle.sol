// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

/**
 * @notice Ownable from Solady is a gas-optimized ownership implementation.
 *         Compared to OpenZeppelin's Ownable, Solady uses raw storage slots
 *         and assembly internally, saving gas on every ownership check.
 *         Provides: onlyOwner modifier, _initializeOwner(), transferOwnership().
 */
import {Ownable} from "solady/auth/Ownable.sol";

/**
 * @title  CurvyPuppetOracle
 * @notice A centralized, owner-controlled price oracle used by CurvyPuppetLending
 *         to price both the collateral asset and the Curve LP token's underlying.
 *
 * @dev    DESIGN:
 *         - The owner (typically a trusted deployer or keeper bot) pushes prices
 *           on-chain via setPrice(). No on-chain price discovery occurs.
 *         - Each price entry carries an expiration timestamp. Prices older than
 *           their expiration are treated as stale and will revert on read.
 *         - Expiration window is capped at 2 days to limit stale-price risk.
 *
 * @dev    TRUST ASSUMPTIONS & VULNERABILITY (Damn Vulnerable DeFi):
 *         This oracle is entirely trust-based — a single owner controls all prices.
 *         Attack surfaces:
 *           1. OWNER COMPROMISE: If the owner's private key is stolen, an attacker
 *              can set arbitrary prices, enabling free borrows or mass liquidations
 *              in CurvyPuppetLending.
 *           2. STALE PRICES: If the owner stops updating prices, all getPrice()
 *              calls revert after expiration, freezing the lending protocol.
 *           3. NO TWAP / NO MANIPULATION RESISTANCE: Prices are point-in-time
 *              snapshots. Combined with CurvyPuppetLending's use of
 *              get_virtual_price(), this creates a compounded flash-loan attack
 *              surface (see CurvyPuppetLending._getLPTokenPrice()).
 *
 *         Production fix: Replace with a decentralized oracle (e.g. Chainlink,
 *         Uniswap TWAP, or Curve's EMA oracle) with no single point of control.
 */
contract CurvyPuppetOracle is Ownable {

    // -------------------------------------------------------------------------
    // State
    // -------------------------------------------------------------------------

    /**
     * @notice Maps each asset address to its current price entry.
     * @dev    Public — external contracts (e.g. CurvyPuppetLending) can read
     *         raw storage directly, but should prefer getPrice() which enforces
     *         staleness and zero-value checks before returning.
     *         Layout: asset address → Price { value (WAD), expiration (unix timestamp) }
     */
    mapping(address asset => Price) public prices;

    // -------------------------------------------------------------------------
    // Data Structures
    // -------------------------------------------------------------------------

    /**
     * @notice Stores a single price observation for one asset.
     * @param value      Asset price in WAD (1e18 = $1.00). Must be > 0.
     * @param expiration Unix timestamp after which this price is considered stale.
     *                   Must be: block.timestamp < expiration ≤ block.timestamp + 2 days.
     */
    struct Price {
        uint256 value;
        uint256 expiration;
    }

    // -------------------------------------------------------------------------
    // Custom Errors
    // -------------------------------------------------------------------------

    /// @notice Thrown by setPrice() when value == 0.
    ///         A zero price would silently make all borrow/collateral valuations
    ///         zero, breaking the lending protocol's solvency checks entirely.
    error InvalidPrice();

    /**
     * @notice Thrown by setPrice() when the expiration is out of the valid window.
     *         Valid range: block.timestamp < expiration ≤ block.timestamp + 2 days.
     *         - expiration <= block.timestamp → already expired on arrival (useless).
     *         - expiration > block.timestamp + 2 days → price could remain "valid"
     *           for too long, allowing stale data to price loans for days without update.
     */
    error InvalidExpiration();

    /**
     * @notice Thrown by getPrice() when the stored price has passed its expiration.
     * @dev    Protects the lending protocol from acting on outdated prices.
     *         If this reverts, the lending protocol is effectively frozen until
     *         the owner pushes a fresh price — a liveness risk.
     */
    error StalePrice();

    /**
     * @notice Thrown by getPrice() when no price has ever been set for the asset.
     * @dev    Detected via price.value == 0 (the zero-value of uninitialized storage).
     *         Prevents the protocol from treating missing prices as "$0 assets".
     */
    error UnsupportedAsset();

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    /**
     * @notice Grants ownership to the deployer.
     * @dev    Solady's Ownable does not auto-initialize in the constructor —
     *         _initializeOwner() must be called explicitly. Without this call,
     *         the contract would have no owner and setPrice() would be uncallable.
     */
    constructor() {
        _initializeOwner(msg.sender);
    }

    // -------------------------------------------------------------------------
    // External Functions
    // -------------------------------------------------------------------------

    /**
     * @notice Returns the current valid price for a given asset.
     * @dev    Performs two safety checks before returning:
     *           1. price.value == 0 → asset was never registered → UnsupportedAsset
     *           2. block.timestamp > price.expiration → price is stale → StalePrice
     *
     *         Returns a memory copy — callers receive a snapshot of the price at
     *         call time. No re-entrancy risk since this is a pure view function.
     *
     *         Consumed by CurvyPuppetLending:
     *           - getCollateralValue() → oracle.getPrice(collateralAsset).value
     *           - _getLPTokenPrice()   → oracle.getPrice(curvePool.coins(0)).value
     *
     * @param asset The ERC20 token address to price.
     * @return      Price struct with value (WAD) and expiration (unix timestamp).
     */
    function getPrice(address asset) external view returns (Price memory) {
        Price memory price = prices[asset];

        // Check 1: value == 0 means this asset was never registered via setPrice()
        if (price.value == 0) revert UnsupportedAsset();

        // Check 2: Price has expired — owner must call setPrice() again to refresh
        if (block.timestamp > price.expiration) revert StalePrice();

        return price;
    }

    /**
     * @notice Sets or updates the price for a given asset.
     * @dev    onlyOwner — only the contract owner (deployer or transferred owner)
     *         can call this. This is the single point of trust in the entire oracle.
     *
     *         Expiration constraints (both checked to prevent misuse):
     *           - expiration > block.timestamp       → must be a future timestamp
     *           - expiration ≤ block.timestamp + 2d  → cannot set prices valid > 2 days
     *             (caps how long a single price update can remain authoritative)
     *
     *         Value constraint:
     *           - value > 0 → zero prices would break all downstream WAD math
     *
     * @dev    RISK: There is no price-change sanity check (e.g. max % deviation).
     *         The owner could set price to 1 wei or 1e36 with no on-chain resistance.
     *         A compromised owner key = total control over the lending protocol's
     *         solvency model.
     *
     * @param asset      ERC20 token address to set the price for.
     * @param value      New price in WAD (1e18 = $1.00). Must be > 0.
     * @param expiration Unix timestamp when this price expires. Must be within 2 days.
     */
    function setPrice(address asset, uint256 value, uint256 expiration) external onlyOwner {
        // Reject zero prices — would silently zero out all value calculations downstream
        if (value == 0) revert InvalidPrice();

        // Reject expirations that are already past OR more than 2 days in the future
        // Combined check: expiration must be in (now, now + 2 days]
        if (expiration <= block.timestamp || expiration > block.timestamp + 2 days) {
            revert InvalidExpiration();
        }

        // Write the new price entry — overwrites any previous price for this asset
        prices[asset] = Price(value, expiration);
    }
}
