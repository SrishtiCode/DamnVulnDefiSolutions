// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

/**
 * @notice SafeCast prevents silent truncation when downcasting uint256 → uint160.
 *         Used when calling permit2.transferFrom(), which requires a uint160 amount.
 *         Without SafeCast, a large amount would silently wrap to a smaller value.
 */
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

/// @notice Standard ERC20 interface — used to transfer borrowAsset and collateralAsset.
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

/**
 * @notice ReentrancyGuard adds the nonReentrant modifier to prevent reentrancy attacks.
 *         Critical here because deposit/withdraw/liquidate all transfer tokens and
 *         could otherwise be exploited via malicious ERC20 hooks or fallback functions.
 */
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @notice FixedPointMathLib provides WAD (1e18) fixed-point arithmetic.
 *         mulWadDown / mulWadUp / divWadDown multiply or divide by WAD with
 *         configurable rounding direction (Down = floor, Up = ceiling).
 *         Used throughout for price × amount calculations.
 */
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

/**
 * @notice Permit2 is Uniswap's universal token approval contract.
 *         Instead of requiring users to call approve() on every token separately,
 *         Permit2 lets users sign off-chain permits once. _pullAssets() uses it
 *         to pull tokens from the caller without a separate on-chain approval step.
 */
import {IPermit2} from "permit2/interfaces/IPermit2.sol";

/**
 * @notice IStableSwap is the Curve StableSwap pool interface.
 *         Used to read:
 *           - lp_token()         → address of the Curve LP token (the borrow asset)
 *           - coins(0)           → address of the first underlying token (e.g. stETH)
 *           - get_virtual_price()→ Curve's internal LP token price (manipulation target)
 */
import {IStableSwap} from "./IStableSwap.sol";

/**
 * @notice CurvyPuppetOracle provides on-chain USD prices for assets.
 *         getPrice(asset).value returns the price in WAD (18-decimal fixed point).
 *         VULNERABILITY: If get_virtual_price() or the oracle itself can be
 *         manipulated (e.g. via a flash loan inflating the Curve pool), the
 *         LP token price returned by _getLPTokenPrice() becomes exploitable.
 */
import {CurvyPuppetOracle} from "./CurvyPuppetOracle.sol";

import {console} from "forge-std/console.sol"; // Development only — remove before mainnet

/**
 * @title  CurvyPuppetLending
 * @notice A collateralized lending protocol where:
 *           - COLLATERAL: any ERC20 (e.g. stETH, wstETH) priced via CurvyPuppetOracle.
 *           - BORROW ASSET: Curve LP token from the associated StableSwap pool,
 *                           priced as: oracle.getPrice(coins(0)) × get_virtual_price()
 *
 *         Loan-to-Value (LTV) ratio: 100/175 ≈ 57.1%
 *           → Borrow value must not exceed 57.1% of collateral value.
 *           → Liquidation triggers when: borrowValue × 175 > collateralValue × 100
 *
 * @dev VULNERABILITY (Damn Vulnerable DeFi — CurvyPuppet):
 *      _getLPTokenPrice() uses Curve's get_virtual_price() which can be transiently
 *      inflated via a flash loan (add liquidity → manipulate price → liquidate → remove).
 *      An attacker can:
 *        1. Flash-loan a large amount of the underlying asset.
 *        2. Add it to the Curve pool → get_virtual_price() rises.
 *        3. LP token price spikes → borrowValue spikes → all positions become undercollateralized.
 *        4. Liquidate victim positions at the inflated price, collecting collateral cheaply.
 *        5. Remove liquidity → repay flash loan.
 *
 *      Fix: Use a TWAP or Curve's own manipulation-resistant price oracle rather than
 *           spot get_virtual_price().
 */
contract CurvyPuppetLending is ReentrancyGuard {
    using FixedPointMathLib for uint256; // Enables .mulWadDown(), .mulWadUp(), .divWadDown() on uint256

    // -------------------------------------------------------------------------
    // Immutable State
    // -------------------------------------------------------------------------

    /**
     * @notice The token users BORROW from this protocol.
     * @dev    Set to curvePool.lp_token() in the constructor — the Curve StableSwap
     *         LP token. Its price is computed dynamically via _getLPTokenPrice().
     */
    address public immutable borrowAsset;

    /**
     * @notice The token users deposit as COLLATERAL.
     * @dev    Priced via CurvyPuppetOracle. Can be any ERC20 (e.g. stETH, wstETH).
     */
    address public immutable collateralAsset;

    /**
     * @notice The Curve StableSwap pool associated with the borrow asset.
     * @dev    Used to read:
     *           - lp_token()          → borrowAsset address (set once in constructor)
     *           - coins(0)            → underlying token for LP price calculation
     *           - get_virtual_price() → current LP token price (MANIPULATION RISK)
     */
    IStableSwap public immutable curvePool;

    /**
     * @notice Permit2 contract used for gasless token pulls.
     * @dev    Users approve Permit2 once; this contract uses it to pull tokens
     *         from msg.sender without requiring per-transaction ERC20 approvals.
     */
    IPermit2 public immutable permit2;

    /**
     * @notice Price oracle for both collateral and LP token underlying assets.
     * @dev    Returns prices in WAD (1e18 = $1.00).
     *         oracle.getPrice(collateralAsset).value → collateral price in WAD
     *         oracle.getPrice(curvePool.coins(0)).value → underlying token price in WAD
     */
    CurvyPuppetOracle public immutable oracle;

    // -------------------------------------------------------------------------
    // Data Structures
    // -------------------------------------------------------------------------

    /**
     * @notice Tracks each user's outstanding position in the protocol.
     * @param collateralAmount Amount of collateralAsset deposited (in token units).
     * @param borrowAmount     Amount of borrowAsset currently owed (in token units).
     */
    struct Position {
        uint256 collateralAmount;
        uint256 borrowAmount;
    }

    /// @notice Maps each user address to their current lending position.
    mapping(address who => Position) public positions;

    // -------------------------------------------------------------------------
    // Custom Errors
    // -------------------------------------------------------------------------

    /// @notice Thrown when a zero amount is passed to a function that requires > 0.
    error InvalidAmount();

    /// @notice Thrown when a borrow or withdraw would push the position below the LTV threshold.
    error NotEnoughCollateral();

    /**
     * @notice Thrown when liquidate() is called on a position that is still healthy.
     * @param borrowValue     borrowAmount × lpPrice × 175 (scaled numerator)
     * @param collateralValue collateralAmount × collateralPrice × 100 (scaled numerator)
     */
    error HealthyPosition(uint256 borrowValue, uint256 collateralValue);

    /**
     * @notice Thrown when withdraw() would leave the position undercollateralized.
     *         i.e., borrowValue × 175 > remainingCollateralValue × 100
     */
    error UnhealthyPosition();

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    /**
     * @notice Initializes the lending pool by wiring up all external dependencies.
     * @dev    borrowAsset is derived from the Curve pool, not passed in directly —
     *         this guarantees the borrow asset and pool are always consistent.
     *
     * @param _collateralAsset ERC20 token address users will post as collateral.
     * @param _curvePool       Curve StableSwap pool whose LP token is the borrow asset.
     * @param _permit2         Permit2 contract for token pulls (avoids per-tx approvals).
     * @param _oracle          Price oracle for collateral and LP token underlying price.
     */
    constructor(address _collateralAsset, IStableSwap _curvePool, IPermit2 _permit2, CurvyPuppetOracle _oracle) {
        // Derive borrow asset directly from the pool — ensures perfect consistency
        borrowAsset = _curvePool.lp_token();
        collateralAsset = _collateralAsset;
        curvePool = _curvePool;
        permit2 = _permit2;
        oracle = _oracle;
    }

    // -------------------------------------------------------------------------
    // External Functions — User Actions
    // -------------------------------------------------------------------------

    /**
     * @notice Deposits collateral into the caller's position.
     * @dev    Increases collateralAmount and pulls tokens via Permit2.
     *         nonReentrant prevents reentrancy via ERC20 transfer hooks.
     *         No minimum amount check — even 0 deposits are allowed (no harm done).
     *
     * @param amount Amount of collateralAsset to deposit (in token units).
     */
    function deposit(uint256 amount) external nonReentrant {
        // Increase the caller's recorded collateral balance
        positions[msg.sender].collateralAmount += amount;

        // Pull collateral tokens from caller using Permit2
        // (requires caller to have pre-approved Permit2 for collateralAsset)
        _pullAssets(collateralAsset, amount);
    }

    /**
     * @notice Withdraws collateral from the caller's position.
     * @dev    The post-withdrawal position must remain healthy:
     *           borrowValue × 175 ≤ remainingCollateralValue × 100
     *         This enforces the 57.1% LTV cap even after partial withdrawals.
     *         nonReentrant prevents reentrancy during the collateral transfer.
     *
     * @param amount Amount of collateralAsset to withdraw (in token units).
     */
    function withdraw(uint256 amount) external nonReentrant {
        if (amount == 0) revert InvalidAmount();

        // Calculate what the position will look like after withdrawal
        uint256 remainingCollateral = positions[msg.sender].collateralAmount - amount;
        uint256 remainingCollateralValue = getCollateralValue(remainingCollateral);
        uint256 borrowValue = getBorrowValue(positions[msg.sender].borrowAmount);

        // Enforce LTV: borrowValue / collateralValue must not exceed 100/175 (~57.1%)
        // Multiply both sides by 175 and 100 to avoid division (integer precision)
        // Reverts if: borrowValue × 175 > remainingCollateralValue × 100
        if (borrowValue * 175 > remainingCollateralValue * 100) revert UnhealthyPosition();

        // Update state BEFORE transfer (checks-effects-interactions pattern)
        positions[msg.sender].collateralAmount = remainingCollateral;

        // Return collateral tokens to the caller
        IERC20(collateralAsset).transfer(msg.sender, amount);
    }

    /**
     * @notice Borrows LP tokens against the caller's deposited collateral.
     * @dev    Does NOT use nonReentrant — relies on checks-effects-interactions
     *         ordering (state updated before token transfer) for reentrancy safety.
     *
     *         LTV enforcement:
     *           currentBorrowValue + newBorrowValue ≤ collateralValue × (100/175)
     *
     *         Special case: passing amount = type(uint256).max borrows the maximum
     *         possible amount given the current collateral and borrow positions.
     *
     * @dev VULNERABILITY: _getLPTokenPrice() uses get_virtual_price() which is
     *      vulnerable to flash loan manipulation. If price is deflated, borrowers
     *      can borrow more LP tokens than their collateral is actually worth.
     *
     * @param amount LP token amount to borrow, or type(uint256).max to borrow maximum.
     */
    function borrow(uint256 amount) external {
        // Read current position values in USD (WAD-scaled)
        uint256 collateralValue = getCollateralValue(positions[msg.sender].collateralAmount);
        uint256 currentBorrowValue = getBorrowValue(positions[msg.sender].borrowAmount);

        // Maximum allowed borrow value = collateralValue × (100/175) ≈ 57.1% of collateral
        uint256 maxBorrowValue = collateralValue * 100 / 175;

        // Remaining headroom in USD before hitting the LTV cap
        uint256 availableBorrowValue = maxBorrowValue - currentBorrowValue;

        if (amount == type(uint256).max) {
            // Convert available USD headroom to LP token units using current LP price.
            // divWadDown divides by lpPrice (WAD) rounding down — conservative for borrower.
            // Formula: availableBorrowValue / lpTokenPrice = max borrowable LP tokens
            amount = availableBorrowValue.divWadDown(_getLPTokenPrice());
        }

        if (amount == 0) revert InvalidAmount();

        // Final solvency check: adding this borrow must not exceed the LTV cap
        uint256 borrowAmountValue = getBorrowValue(amount);
        if (currentBorrowValue + borrowAmountValue > maxBorrowValue) revert NotEnoughCollateral();

        // Update state BEFORE transfer (checks-effects-interactions)
        positions[msg.sender].borrowAmount += amount;

        // Send LP tokens to the borrower
        IERC20(borrowAsset).transfer(msg.sender, amount);
    }

    /**
     * @notice Repays borrowed LP tokens and optionally retrieves collateral.
     * @dev    Partial repayment is allowed — amount can be less than total borrowAmount.
     *         If the full debt is repaid (borrowAmount reaches 0), the entire
     *         collateral balance is automatically returned to the caller.
     *         nonReentrant prevents reentrancy during the collateral return transfer.
     *
     * @param amount Amount of borrowAsset (LP tokens) to repay.
     */
    function redeem(uint256 amount) external nonReentrant {
        if (amount == 0) revert InvalidAmount();

        // Reduce the borrow balance (reverts with underflow if amount > borrowAmount)
        positions[msg.sender].borrowAmount -= amount;

        // Pull repaid LP tokens from the caller via Permit2
        _pullAssets(borrowAsset, amount);

        // If debt is fully cleared, automatically return all collateral
        if (positions[msg.sender].borrowAmount == 0) {
            uint256 returnAmount = positions[msg.sender].collateralAmount;
            positions[msg.sender].collateralAmount = 0; // Zero out before transfer (CEI)
            IERC20(collateralAsset).transfer(msg.sender, returnAmount);
        }
    }

    /**
     * @notice Liquidates an undercollateralized position.
     * @dev    Liquidation condition:
     *           borrowValue × 175 > collateralValue × 100
     *           (i.e. position LTV has exceeded the 57.1% threshold)
     *
     *         The liquidator:
     *           1. Provides the full outstanding borrowAmount of LP tokens.
     *           2. Receives the full collateralAmount in return.
     *         No discount is applied — liquidator profit comes from external arbitrage.
     *
     * @dev VULNERABILITY: An attacker can flash-loan assets into the Curve pool to
     *      inflate get_virtual_price() → LP token price rises → borrowValue × 175
     *      exceeds collateralValue × 100 → healthy positions appear undercollateralized
     *      → attacker liquidates them, collecting collateral at a discount.
     *
     * @param target The address whose position should be liquidated.
     */
    function liquidate(address target) external nonReentrant {
        uint256 borrowAmount = positions[target].borrowAmount;
        uint256 collateralAmount = positions[target].collateralAmount;

        // Fetch current USD values and apply the LTV multipliers (×100 and ×175)
        // to avoid division when comparing against the threshold
        uint256 collateralValue = getCollateralValue(collateralAmount) * 100;
        uint256 borrowValue = getBorrowValue(borrowAmount) * 175;

        // Revert if position is still healthy (collateral covers the borrow with margin)
        // Liquidation only allowed when: borrowValue × 175 > collateralValue × 100
        if (collateralValue >= borrowValue) revert HealthyPosition(borrowValue, collateralValue);

        // Wipe the position BEFORE any transfers (checks-effects-interactions)
        delete positions[target];

        // Liquidator provides the full borrow amount (LP tokens) to repay the debt
        _pullAssets(borrowAsset, borrowAmount);

        // Liquidator receives the full collateral as compensation
        IERC20(collateralAsset).transfer(msg.sender, collateralAmount);
    }

    // -------------------------------------------------------------------------
    // Public View — Value Calculations
    // -------------------------------------------------------------------------

    /**
     * @notice Returns the USD value of a given LP token amount (the borrow asset).
     * @dev    Uses mulWadUp (rounds UP) — conservatively overstates borrow value,
     *         making solvency checks slightly stricter for the borrower.
     *         Formula: amount × lpTokenPrice (WAD) → USD value in WAD
     *
     * @param amount LP token quantity (in token units).
     * @return       USD value in WAD (1e18 = $1.00).
     */
    function getBorrowValue(uint256 amount) public view returns (uint256) {
        if (amount == 0) return 0;
        // mulWadUp: rounds UP → borrower's debt slightly overstated → safer for protocol
        return amount.mulWadUp(_getLPTokenPrice());
    }

    /**
     * @notice Returns the USD value of a given collateral amount.
     * @dev    Uses mulWadDown (rounds DOWN) — conservatively understates collateral value,
     *         making solvency checks slightly stricter for the borrower.
     *         Formula: amount × oracle.getPrice(collateralAsset).value → USD in WAD
     *
     * @param amount Collateral token quantity (in token units).
     * @return       USD value in WAD (1e18 = $1.00).
     */
    function getCollateralValue(uint256 amount) public view returns (uint256) {
        if (amount == 0) return 0;
        // mulWadDown: rounds DOWN → collateral value slightly understated → safer for protocol
        return amount.mulWadDown(oracle.getPrice(collateralAsset).value);
    }

    // -------------------------------------------------------------------------
    // External View — Position Getters
    // -------------------------------------------------------------------------

    /**
     * @notice Returns the outstanding borrow amount (LP tokens) for a given address.
     * @param who The address to query.
     * @return    Amount of borrowAsset (LP tokens) currently owed by `who`.
     */
    function getBorrowAmount(address who) external view returns (uint256) {
        return positions[who].borrowAmount;
    }

    /**
     * @notice Returns the deposited collateral amount for a given address.
     * @param who The address to query.
     * @return    Amount of collateralAsset currently held by the protocol for `who`.
     */
    function getCollateralAmount(address who) external view returns (uint256) {
        return positions[who].collateralAmount;
    }

    // -------------------------------------------------------------------------
    // Private Helpers
    // -------------------------------------------------------------------------

    /**
     * @notice Pulls `amount` of `asset` from msg.sender into this contract via Permit2.
     * @dev    SafeCast.toUint160() is critical here — Permit2's transferFrom() takes
     *         a uint160 amount. If amount > type(uint160).max, SafeCast reverts rather
     *         than silently truncating (which would pull far less than intended).
     *         Callers must have pre-approved Permit2 for the relevant asset and amount.
     *
     * @param asset  ERC20 token address to pull.
     * @param amount Amount to pull in token units (will be cast to uint160).
     */
    function _pullAssets(address asset, uint256 amount) private {
        permit2.transferFrom({
            from:   msg.sender,
            to:     address(this),
            amount: SafeCast.toUint160(amount), // Reverts if amount > type(uint160).max
            token:  asset
        });
    }

    /**
     * @notice Computes the current USD price of one LP token in WAD.
     * @dev    Formula:
     *           lpPrice = oracle.getPrice(coins(0)).value × get_virtual_price()
     *
     *         Where:
     *           coins(0)          = first underlying token in the Curve pool (e.g. stETH)
     *           get_virtual_price = Curve's internal LP token price relative to underlying
     *                               (starts at 1e18 and increases as fees accumulate)
     *
     *         mulWadDown: rounds down — slightly understates LP price → conservative
     *                     borrow value calculations protect the protocol.
     *
     * @dev VULNERABILITY: get_virtual_price() is a spot price and CAN be transiently
     *      inflated by adding large liquidity in a single transaction (flash loan attack).
     *      This makes all borrow valuations manipulable within a single block.
     *      A time-weighted average price (TWAP) would eliminate this attack vector.
     *
     * @return LP token price in WAD (1e18 = $1.00 equivalent).
     */
    function _getLPTokenPrice() private view returns (uint256) {
        // Step 1: Get the USD price of the first underlying pool token (e.g. stETH) from oracle
        // Step 2: Multiply by Curve's virtual price to scale up to LP token value
        // mulWadDown: divides the product by WAD (1e18), rounding down
        return oracle.getPrice(curvePool.coins(0)).value.mulWadDown(curvePool.get_virtual_price());
    }
}
