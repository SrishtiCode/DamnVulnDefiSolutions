// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

/**
 * @notice AccessControlEnumerable extends OpenZeppelin's AccessControl by allowing
 *         enumeration of all members holding a specific role.
 *         This lets us iterate over all TRUSTED_SOURCE_ROLE holders to collect prices.
 */
import {AccessControlEnumerable} from "@openzeppelin/contracts/access/extensions/AccessControlEnumerable.sol";

/**
 * @notice LibSort provides gas-efficient sorting utilities.
 *         Used here to sort price arrays via insertionSort before computing the median.
 */
import {LibSort} from "solady/utils/LibSort.sol";

/**
 * @title  TrustfulOracle
 * @notice A decentralized price oracle where multiple trusted sources each report
 *         a price for a given token symbol. The canonical price returned to callers
 *         is always the MEDIAN across all source-reported prices — not the mean —
 *         making single outlier manipulation harder (but not impossible).
 *
 * @dev VULNERABILITY (Damn Vulnerable DeFi):
 *      "Trustful" is intentionally ironic. If an attacker compromises or controls
 *      the PRIVATE KEYS of a majority of trusted sources, they can push crafted
 *      prices and shift the median arbitrarily.
 *
 *      Attack surface example (3 sources: A, B, C):
 *        Normal prices  → [10, 11, 12]  → median = 11
 *        Attacker owns A & B and sets both to 0:
 *        Poisoned prices → [0, 0, 12]   → median = 0
 *        Now NFTs can be bought for free and sold back at 12 ETH — draining the Exchange.
 *
 *      Rule of thumb: controlling ⌊N/2⌋ + 1 sources lets you set any median you want.
 */
contract TrustfulOracle is AccessControlEnumerable {

    // -------------------------------------------------------------------------
    // Constants & Roles
    // -------------------------------------------------------------------------

    /**
     * @notice Minimum number of trusted price sources required at deployment.
     * @dev    Set to 1 here for simplicity, but production oracles should require
     *         at least 3 independent sources to make median manipulation harder.
     *         With only 1 source the "median" IS that single source — zero protection.
     */
    uint256 public constant MIN_SOURCES = 1;

    /**
     * @notice Role identifier for addresses allowed to post prices.
     * @dev    Computed as keccak256("TRUSTED_SOURCE_ROLE").
     *         Addresses granted this role can call postPrice() and influence the median.
     *         Compromising any majority subset of these addresses breaks the oracle.
     */
    bytes32 public constant TRUSTED_SOURCE_ROLE = keccak256("TRUSTED_SOURCE_ROLE");

    /**
     * @notice Role identifier for the one-time price initializer (typically the deployer).
     * @dev    Computed as keccak256("INITIALIZER_ROLE").
     *         This role is self-revoked at the end of setupInitialPrices(), so it can
     *         never be used again — preventing the deployer from resetting prices later.
     */
    bytes32 public constant INITIALIZER_ROLE = keccak256("INITIALIZER_ROLE");

    // -------------------------------------------------------------------------
    // State
    // -------------------------------------------------------------------------

    /**
     * @notice Nested mapping storing each source's reported price per symbol.
     * @dev    Layout: source address → token symbol → price in wei.
     *         Private — external callers must use getPriceBySource() or getMedianPrice().
     */
    mapping(address => mapping(string => uint256)) private _pricesBySource;

    // -------------------------------------------------------------------------
    // Errors & Events
    // -------------------------------------------------------------------------

    /// @notice Thrown in the constructor if fewer than MIN_SOURCES addresses are provided.
    error NotEnoughSources();

    /**
     * @notice Emitted every time a trusted source successfully updates a price.
     * @param source    The trusted source address that posted the update.
     * @param symbol    The token symbol whose price changed (e.g. "DVNFT").
     * @param oldPrice  The price recorded before this update (wei).
     * @param newPrice  The price recorded after this update (wei).
     */
    event UpdatedPrice(
        address indexed source,
        string  indexed symbol,
        uint256 oldPrice,
        uint256 newPrice
    );

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    /**
     * @notice Deploys the oracle, registers trusted sources, and optionally grants
     *         the deployer a one-time INITIALIZER_ROLE for bulk price seeding.
     *
     * @dev    All source addresses receive TRUSTED_SOURCE_ROLE immediately.
     *         The `unchecked` loop increment is safe — source array length is
     *         bounded by the caller and will never realistically overflow uint256.
     *
     * @param sources              Array of trusted price-reporter addresses.
     *                             Must contain at least MIN_SOURCES entries.
     * @param enableInitialization If true, msg.sender receives INITIALIZER_ROLE
     *                             so they can call setupInitialPrices() once.
     *                             Pass false if initial prices aren't needed.
     */
    constructor(address[] memory sources, bool enableInitialization) {
        // Revert early if the caller provides too few source addresses
        if (sources.length < MIN_SOURCES) {
            revert NotEnoughSources();
        }

        // Grant TRUSTED_SOURCE_ROLE to every supplied source address
        for (uint256 i = 0; i < sources.length;) {
            unchecked {
                _grantRole(TRUSTED_SOURCE_ROLE, sources[i]);
                ++i; // Gas-efficient increment; overflow impossible in practice
            }
        }

        // Conditionally grant the deployer a one-time initialization privilege
        if (enableInitialization) {
            _grantRole(INITIALIZER_ROLE, msg.sender);
        }
    }

    // -------------------------------------------------------------------------
    // External Functions
    // -------------------------------------------------------------------------

    /**
     * @notice Seeds the oracle with an initial batch of (source, symbol, price) triples.
     *         Can only be called by the INITIALIZER_ROLE holder, and only ONCE —
     *         because the role is self-revoked at the end of this function.
     *
     * @dev    Enforces strict 1-to-1-to-1 array alignment via require().
     *         After renounceRole() executes, no address holds INITIALIZER_ROLE,
     *         making this function permanently uncallable — acting as a one-shot setup.
     *
     * @param sources  Trusted source addresses that will "own" each price entry.
     * @param symbols  Token symbols corresponding to each source (e.g. "DVNFT").
     * @param prices   Initial prices in wei corresponding to each (source, symbol) pair.
     */
    function setupInitialPrices(
        address[] calldata sources,
        string[]  calldata symbols,
        uint256[] calldata prices
    )
        external
        onlyRole(INITIALIZER_ROLE)
    {
        // All three arrays must have identical lengths to ensure 1-to-1-to-1 mapping.
        // A mismatch would silently skip entries or read out-of-bounds — so we revert.
        require(sources.length == symbols.length && symbols.length == prices.length);

        for (uint256 i = 0; i < sources.length;) {
            unchecked {
                // Record each source's initial price for the given symbol
                _setPrice(sources[i], symbols[i], prices[i]);
                ++i;
            }
        }

        // Self-revoke INITIALIZER_ROLE so this function can never be called again.
        // This is an important trust-minimization step — the deployer cannot reset
        // prices after the system goes live.
        renounceRole(INITIALIZER_ROLE, msg.sender);
    }

    /**
     * @notice Allows a trusted source to post (or update) its price for a symbol.
     * @dev    Only addresses holding TRUSTED_SOURCE_ROLE may call this.
     *         The price is stored under msg.sender's key, so each source's report
     *         is independent — sources cannot overwrite each other's prices.
     *
     * @param symbol   The token symbol being priced (e.g. "DVNFT").
     * @param newPrice The price the caller is reporting, denominated in wei.
     */
    function postPrice(string calldata symbol, uint256 newPrice)
        external
        onlyRole(TRUSTED_SOURCE_ROLE)
    {
        // Attribute this price to the calling source address
        _setPrice(msg.sender, symbol, newPrice);
    }

    /**
     * @notice Returns the current median price for a given symbol across all trusted sources.
     * @dev    Delegates to _computeMedianPrice(). Result fluctuates as sources post updates.
     *         This is the primary price feed consumed by the Exchange contract.
     *
     * @param symbol The token symbol to price (e.g. "DVNFT").
     * @return       Median price in wei.
     */
    function getMedianPrice(string calldata symbol) external view returns (uint256) {
        return _computeMedianPrice(symbol);
    }

    /**
     * @notice Returns an array of every trusted source's reported price for a symbol.
     * @dev    Iterates over all TRUSTED_SOURCE_ROLE members using AccessControlEnumerable.
     *         Order of entries matches the internal role-member enumeration order,
     *         which is NOT guaranteed to be deterministic across different EVM runs.
     *         Used internally by _computeMedianPrice and also useful for off-chain monitoring.
     *
     * @param symbol The token symbol to query (e.g. "DVNFT").
     * @return prices Array of prices (wei), one entry per trusted source.
     */
    function getAllPricesForSymbol(string memory symbol)
        public
        view
        returns (uint256[] memory prices)
    {
        // Determine how many trusted sources are currently registered
        uint256 numberOfSources = getRoleMemberCount(TRUSTED_SOURCE_ROLE);
        prices = new uint256[](numberOfSources);

        for (uint256 i = 0; i < numberOfSources;) {
            // Resolve the i-th trusted source address from the enumerable role set
            address source = getRoleMember(TRUSTED_SOURCE_ROLE, i);

            // Read that source's last reported price for this symbol
            prices[i] = getPriceBySource(symbol, source);

            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice Returns the price for a specific symbol as reported by a specific source.
     * @dev    Returns 0 if the source has never posted a price for this symbol —
     *         callers should be aware that 0 is indistinguishable from "not set".
     *
     * @param symbol The token symbol to query.
     * @param source The trusted source address whose price report to retrieve.
     * @return       Price in wei reported by that source, or 0 if never set.
     */
    function getPriceBySource(string memory symbol, address source)
        public
        view
        returns (uint256)
    {
        return _pricesBySource[source][symbol];
    }

    // -------------------------------------------------------------------------
    // Private Helpers
    // -------------------------------------------------------------------------

    /**
     * @notice Writes a new price for a (source, symbol) pair and emits UpdatedPrice.
     * @dev    Always captures oldPrice before overwriting so the event contains a
     *         meaningful before/after diff for off-chain monitoring and alerting.
     *
     * @param source   The trusted source address whose price is being updated.
     * @param symbol   The token symbol being priced.
     * @param newPrice The new price in wei to record.
     */
    function _setPrice(address source, string memory symbol, uint256 newPrice) private {
        // Snapshot the previous price for inclusion in the event log
        uint256 oldPrice = _pricesBySource[source][symbol];

        // Overwrite with the new price
        _pricesBySource[source][symbol] = newPrice;

        emit UpdatedPrice(source, symbol, oldPrice, newPrice);
    }

    /**
     * @notice Computes the median of all trusted sources' prices for a symbol.
     *
     * @dev    Algorithm:
     *           1. Collect all source prices into a memory array.
     *           2. Sort ascending using LibSort.insertionSort (O(n²), acceptable for
     *              small n; gas cost grows quickly for large source counts).
     *           3. If the count is EVEN  → average the two middle values to avoid
     *              bias toward either neighbor.
     *              If the count is ODD   → return the single middle value directly.
     *
     *         Example (5 sources reporting [30, 10, 50, 20, 40]):
     *           Sorted  → [10, 20, 30, 40, 50]
     *           Median  → prices[2] = 30  ✓
     *
     *         Example (4 sources reporting [10, 40, 20, 30]):
     *           Sorted  → [10, 20, 30, 40]
     *           Median  → (prices[1] + prices[2]) / 2 = (20 + 30) / 2 = 25  ✓
     *
     * @param symbol The token symbol to compute a median price for.
     * @return       Median price in wei.
     */
    function _computeMedianPrice(string memory symbol) private view returns (uint256) {
        // Gather every trusted source's price into a local memory array
        uint256[] memory prices = getAllPricesForSymbol(symbol);

        // Sort the prices array in ascending order (in-place, memory array)
        LibSort.insertionSort(prices);

        if (prices.length % 2 == 0) {
            // Even number of sources: average the two central values
            uint256 leftPrice  = prices[(prices.length / 2) - 1]; // Lower middle
            uint256 rightPrice = prices[prices.length / 2];        // Upper middle
            return (leftPrice + rightPrice) / 2;
        } else {
            // Odd number of sources: the exact middle element is the median
            return prices[prices.length / 2];
        }
    }
}
