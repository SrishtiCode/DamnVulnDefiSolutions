// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {DamnValuableToken} from "../DamnValuableToken.sol";

/**
 * @title PuppetPool
 * @notice A lending pool that allows users to borrow DVT tokens by depositing ETH as collateral.
 *         The required collateral is calculated using the spot price from a Uniswap V1 pair,
 *         making it vulnerable to price oracle manipulation via flash loans or large swaps.
 *
 * @dev VULNERABILITY: The oracle price is derived solely from the Uniswap pair's ETH/token
 *      spot ratio. An attacker can dump tokens into the pair to crash the token price,
 *      making the required ETH collateral near-zero, then borrow the entire pool for cheap.
 */
contract PuppetPool is ReentrancyGuard {
    using Address for address payable;

    /// @notice Collateral multiplier — borrowers must deposit 2x the token value in ETH
    uint256 public constant DEPOSIT_FACTOR = 2;

    /// @notice The Uniswap V1 pair used as the price oracle (ETH/DVT)
    address public immutable uniswapPair;

    /// @notice The DVT token that can be borrowed from this pool
    DamnValuableToken public immutable token;

    /// @notice Tracks how much ETH collateral each address has deposited
    mapping(address => uint256) public deposits;

    /// @notice Thrown when the ETH sent is less than the required collateral
    error NotEnoughCollateral();

    /// @notice Thrown when the token transfer to the recipient fails
    error TransferFailed();

    /// @notice Emitted when a successful borrow occurs
    /// @param account    The address that initiated the borrow
    /// @param recipient  The address that received the borrowed tokens
    /// @param depositRequired  Amount of ETH collateral locked
    /// @param borrowAmount     Amount of DVT tokens borrowed
    event Borrowed(address indexed account, address recipient, uint256 depositRequired, uint256 borrowAmount);

    /**
     * @param tokenAddress       Address of the DVT token contract
     * @param uniswapPairAddress Address of the Uniswap V1 ETH/DVT pair used as price oracle
     */
    constructor(address tokenAddress, address uniswapPairAddress) {
        token = DamnValuableToken(tokenAddress);
        uniswapPair = uniswapPairAddress;
    }

    /**
     * @notice Borrow DVT tokens from the pool by depositing ETH collateral.
     *         Collateral required = 2x the current oracle value of `amount` tokens in ETH.
     *         Any excess ETH sent is refunded to the caller.
     *
     * @dev Protected against reentrancy via `nonReentrant`.
     *      VULNERABILITY: Oracle price can be manipulated before calling this function.
     *
     * @param amount    Number of DVT tokens to borrow
     * @param recipient Address that will receive the borrowed tokens
     */
    function borrow(uint256 amount, address recipient) external payable nonReentrant {
        // Calculate how much ETH collateral is needed at the current oracle price
        uint256 depositRequired = calculateDepositRequired(amount);

        // Revert if the caller hasn't sent enough ETH to cover the collateral
        if (msg.value < depositRequired) {
            revert NotEnoughCollateral();
        }

        // Refund any ETH sent above the required collateral amount
        if (msg.value > depositRequired) {
            unchecked {
                payable(msg.sender).sendValue(msg.value - depositRequired);
            }
        }

        // Record the collateral deposited by this borrower
        unchecked {
            deposits[msg.sender] += depositRequired;
        }

        // Transfer the requested tokens to the recipient; revert if pool is illiquid
        if (!token.transfer(recipient, amount)) {
            revert TransferFailed();
        }

        emit Borrowed(msg.sender, recipient, depositRequired, amount);
    }

    /**
     * @notice Computes the ETH collateral required to borrow `amount` DVT tokens.
     *         Formula: amount × oraclePrice × DEPOSIT_FACTOR / 1e18
     *
     * @param amount Number of DVT tokens the caller wants to borrow
     * @return ETH (in wei) that must be deposited as collateral
     */
    function calculateDepositRequired(uint256 amount) public view returns (uint256) {
        return amount * _computeOraclePrice() * DEPOSIT_FACTOR / 10 ** 18;
    }

    /**
     * @notice Computes the current DVT token price in wei using the Uniswap pair balances.
     *         Price = ETH balance of pair / DVT balance of pair
     *
     * @dev VULNERABILITY: This is a spot price oracle with no TWAP or manipulation resistance.
     *      Anyone can shift this price by swapping tokens in the Uniswap pair immediately
     *      before borrowing, collapsing the required collateral to near zero.
     *
     * @return Token price in wei (ETH per DVT token, scaled by 1e18)
     */
    function _computeOraclePrice() private view returns (uint256) {
        // ETH balance of the pair divided by DVT token balance of the pair
        return uniswapPair.balance * (10 ** 18) / token.balanceOf(uniswapPair);
    }
}
