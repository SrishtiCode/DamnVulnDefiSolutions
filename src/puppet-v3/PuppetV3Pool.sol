// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {WETH} from "solmate/tokens/WETH.sol";
import {DamnValuableToken} from "../../src/DamnValuableToken.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {TransferHelper} from "@uniswap/v3-core/contracts/libraries/TransferHelper.sol";
import {OracleLibrary} from "@uniswap/v3-periphery/contracts/libraries/OracleLibrary.sol";

/**
 * @title PuppetV3Pool
 * @notice A lending pool that lets users borrow DVT tokens by depositing WETH as collateral.
 *         Improves on V1/V2 by using a Uniswap V3 TWAP oracle instead of a manipulable
 *         spot price, making oracle attacks significantly more expensive.
 *
 * @dev RESIDUAL VULNERABILITY: The TWAP window is only 10 minutes. An attacker with
 *      enough capital can skew the Uniswap V3 pool price for the full window duration
 *      and then borrow at an artificially low collateral requirement. The attack is
 *      costly but not impossible. A longer TWAP_PERIOD would raise the attack cost further.
 */
contract PuppetV3Pool {

    /// @notice Collateral multiplier — borrowers must deposit 3× the oracle WETH value of tokens
    uint256 public constant DEPOSIT_FACTOR = 3;

    /// @notice Time window for the TWAP oracle consultation (10 minutes)
    /// @dev Shorter = cheaper to manipulate; longer = safer but less price-responsive
    uint32 public constant TWAP_PERIOD = 10 minutes;

    /// @notice WETH token used as collateral currency
    WETH public immutable weth;

    /// @notice DVT token that users can borrow from this pool
    DamnValuableToken public immutable token;

    /// @notice Uniswap V3 DVT/WETH pool used as the TWAP price oracle
    IUniswapV3Pool public immutable uniswapV3Pool;

    /// @notice Tracks total WETH collateral deposited by each address
    /// @dev No withdrawal function is implemented — collateral is locked indefinitely
    mapping(address => uint256) public deposits;

    /// @notice Emitted on every successful borrow
    /// @param borrower      The address that borrowed tokens
    /// @param depositAmount WETH collateral locked from the borrower
    /// @param borrowAmount  DVT tokens sent to the borrower
    event Borrowed(address indexed borrower, uint256 depositAmount, uint256 borrowAmount);

    /**
     * @param _weth          Address of the WETH contract (used as collateral)
     * @param _token         Address of the DVT token contract (borrowed asset)
     * @param _uniswapV3Pool Address of the Uniswap V3 pool used as the TWAP oracle
     */
    constructor(WETH _weth, DamnValuableToken _token, IUniswapV3Pool _uniswapV3Pool) {
        weth = _weth;
        token = _token;
        uniswapV3Pool = _uniswapV3Pool;
    }

    /**
     * @notice Borrow `borrowAmount` of DVT tokens by locking 3× their TWAP value in WETH.
     *         Caller must pre-approve this contract to pull the required WETH amount.
     *
     * @dev ASSUMPTIONS:
     *      - WETH and DVT both use 18 decimals; price math breaks if they differ.
     *      - Caller has approved at least `calculateDepositOfWETHRequired(borrowAmount)` WETH.
     *
     * ORDER OF OPERATIONS (follows checks-effects-interactions pattern):
     *      1. Calculate required collateral  (check)
     *      2. Pull WETH from caller          (interaction — but WETH has no reentrant hooks)
     *      3. Update internal accounting     (effect)
     *      4. Transfer DVT to caller         (interaction)
     *
     * TODO: Replace manual transferFrom with Permit2 (0x000000000022D473030F116dDEE9F6B43aC78BA3)
     *       to avoid requiring a separate ERC-20 approve transaction.
     *
     * @param borrowAmount Number of DVT tokens the caller wants to borrow
     */
    function borrow(uint256 borrowAmount) external {
        // Compute required WETH collateral: TWAP price of borrowAmount DVT × 3
        uint256 depositOfWETHRequired = calculateDepositOfWETHRequired(borrowAmount);

        // Pull exact WETH collateral from caller — reverts if allowance or balance is insufficient
        weth.transferFrom(msg.sender, address(this), depositOfWETHRequired);

        // Update collateral ledger before sending tokens (good CEI hygiene)
        deposits[msg.sender] += depositOfWETHRequired;

        // Send borrowed DVT tokens to caller; safeTransfer reverts on failure
        TransferHelper.safeTransfer(address(token), msg.sender, borrowAmount);

        emit Borrowed(msg.sender, depositOfWETHRequired, borrowAmount);
    }

    /**
     * @notice Calculates the WETH collateral a borrower must deposit for `amount` DVT tokens.
     *         Formula: TWAP_quote(amount DVT → WETH) × DEPOSIT_FACTOR
     *
     * @param amount DVT token amount to price
     * @return WETH (in wei) the caller must deposit as collateral
     */
    function calculateDepositOfWETHRequired(uint256 amount) public view returns (uint256) {
        // Safely cast to uint128 (required by OracleLibrary), then apply 3× multiplier
        uint256 quote = _getOracleQuote(_toUint128(amount));
        return quote * DEPOSIT_FACTOR;
    }

    /**
     * @notice Returns the TWAP-derived WETH value of `amount` DVT tokens.
     *
     * @dev Two-step oracle process:
     *      1. `OracleLibrary.consult()` — reads Uniswap V3 cumulative tick accumulators
     *         and returns the arithmetic mean tick over the last `TWAP_PERIOD` seconds.
     *         The mean tick represents the geometric mean price over that window.
     *      2. `OracleLibrary.getQuoteAtTick()` — converts the mean tick to a token amount
     *         using the standard Uniswap V3 formula: price = 1.0001^tick.
     *
     * VULNERABILITY: 10-minute TWAP can still be manipulated by an attacker who
     *      sustains a distorted pool price for the full window before borrowing.
     *      Cost scales with pool liquidity × time, but is finite.
     *
     * @param amount DVT amount to price, expressed as uint128 (OracleLibrary requirement)
     * @return WETH equivalent of `amount` DVT at the current TWAP price
     */
    function _getOracleQuote(uint128 amount) private view returns (uint256) {
        // Step 1: Get the time-weighted arithmetic mean tick over the last 10 minutes
        (int24 arithmeticMeanTick,) = OracleLibrary.consult({
            pool: address(uniswapV3Pool),
            secondsAgo: TWAP_PERIOD        // look back 10 minutes
        });

        // Step 2: Convert mean tick → WETH amount for the given DVT input quantity
        return OracleLibrary.getQuoteAtTick({
            tick: arithmeticMeanTick,
            baseAmount: amount,            // how many DVT tokens to price
            baseToken: address(token),     // input  token: DVT
            quoteToken: address(weth)      // output token: WETH
        });
    }

    /**
     * @notice Safely downcasts a uint256 to uint128, reverting on overflow.
     *
     * @dev The assignment `n = uint128(amount)` truncates silently in Solidity.
     *      The equality check `amount == n` catches any truncation and reverts,
     *      making this equivalent to OpenZeppelin's SafeCast.toUint128().
     *
     * @param amount Value to downcast
     * @return n     The same value as uint128; reverts if amount > type(uint128).max
     */
    function _toUint128(uint256 amount) private pure returns (uint128 n) {
        require(amount == (n = uint128(amount)));
    }
}
