// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {AccessControlEnumerable} from "@openzeppelin/contracts/access/extensions/AccessControlEnumerable.sol";//List all members holding a specific role. 
import {LibSort} from "solady/utils/LibSort.sol";//Sort array. 

/**
 * @notice A price oracle with a number of trusted sources that individually report prices for symbols.
 *         The oracle's price for a given symbol is the median price of the symbol over all sources. question-can we increase or decrease the price, if we can control the enough sources than we can control medium 
 */
contract TrustfulOracle is AccessControlEnumerable {
    uint256 public constant MIN_SOURCES = 1;//minimum source should be 1 otherwise it will revert but secure systems require multiple sources (≥3 ideally) 
    bytes32 public constant TRUSTED_SOURCE_ROLE = keccak256("TRUSTED_SOURCE_ROLE");//initializing a state variable for trusted source role
    bytes32 public constant INITIALIZER_ROLE = keccak256("INITIALIZER_ROLE");//initializing a initial role

    // Source address => (symbol => price)
    mapping(address => mapping(string => uint256)) private _pricesBySource;

    error NotEnoughSources();//Error if the sources are not enough
  
    event UpdatedPrice(address indexed source, string indexed symbol, uint256 oldPrice, uint256 newPrice);//Update the logs

    constructor(address[] memory sources, bool enableInitialization) {
        if (sources.length < MIN_SOURCES) {
            revert NotEnoughSources();
        }
        for (uint256 i = 0; i < sources.length;) {
            unchecked {
                _grantRole(TRUSTED_SOURCE_ROLE, sources[i]);//it grant role to the sources which later help in prize
                ++i;
            }
        }
        if (enableInitialization) {
            _grantRole(INITIALIZER_ROLE, msg.sender);//make the caller -> initializer 
        }
    }

    // A handy utility allowing the deployer to setup initial prices (only once)
    function setupInitialPrices(address[] calldata sources, string[] calldata symbols, uint256[] calldata prices)
        external
        onlyRole(INITIALIZER_ROLE)
    {
        // Only allow one (symbol, price) per source
        require(sources.length == symbols.length && symbols.length == prices.length);// Ensures 1-to-1 mapping between (source, symbol, price). Prevents mismatched array inputs
        for (uint256 i = 0; i < sources.length;) {
            unchecked {
                _setPrice(sources[i], symbols[i], prices[i]);//It sets the price for the symbols
                ++i;
            }
        }
        renounceRole(INITIALIZER_ROLE, msg.sender);//Removing the caller from the initalizer role
    }

    function postPrice(string calldata symbol, uint256 newPrice) external onlyRole(TRUSTED_SOURCE_ROLE) {
        _setPrice(msg.sender, symbol, newPrice);
    }

    function getMedianPrice(string calldata symbol) external view returns (uint256) {//computing the medium price
        return _computeMedianPrice(symbol);
    }

    function getAllPricesForSymbol(string memory symbol) public view returns (uint256[] memory prices) {
        uint256 numberOfSources = getRoleMemberCount(TRUSTED_SOURCE_ROLE);
        prices = new uint256[](numberOfSources);
        for (uint256 i = 0; i < numberOfSources;) {
            address source = getRoleMember(TRUSTED_SOURCE_ROLE, i);
            prices[i] = getPriceBySource(symbol, source);
            unchecked {
                ++i;
            }
        }
    }

    function getPriceBySource(string memory symbol, address source) public view returns (uint256) {//Getting the new price from the source 
        return _pricesBySource[source][symbol];
    }

    function _setPrice(address source, string memory symbol, uint256 newPrice) private {//Adding the new price from the source
        uint256 oldPrice = _pricesBySource[source][symbol];
        _pricesBySource[source][symbol] = newPrice;
        emit UpdatedPrice(source, symbol, oldPrice, newPrice);
    }

    function _computeMedianPrice(string memory symbol) private view returns (uint256) {//calculating the medium
        uint256[] memory prices = getAllPricesForSymbol(symbol);
        LibSort.insertionSort(prices);
        if (prices.length % 2 == 0) {
            uint256 leftPrice = prices[(prices.length / 2) - 1];
            uint256 rightPrice = prices[prices.length / 2];
            return (leftPrice + rightPrice) / 2;
        } else {
            return prices[prices.length / 2];
        }
    }
}
