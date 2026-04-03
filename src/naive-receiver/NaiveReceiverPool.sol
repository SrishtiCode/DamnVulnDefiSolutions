// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

// ERC3156 flash loan interfaces
import {IERC3156FlashLender} from "@openzeppelin/contracts/interfaces/IERC3156FlashLender.sol";
import {IERC3156FlashBorrower} from "@openzeppelin/contracts/interfaces/IERC3156FlashBorrower.sol";

// Receiver + multicall utility
import {FlashLoanReceiver} from "./FlashLoanReceiver.sol";
import {Multicall} from "./Multicall.sol";

// WETH token (wraps ETH)
import {WETH} from "solmate/tokens/WETH.sol";

/**
 * @title NaiveReceiverPool
 * @notice Flash loan pool with deposits and meta-transaction support
 */
contract NaiveReceiverPool is Multicall, IERC3156FlashLender {

    // Fixed fee for every flash loan (1 ETH)
    uint256 private constant FIXED_FEE = 1e18;

    // Expected return value from borrower callback
    bytes32 private constant CALLBACK_SUCCESS =
        keccak256("ERC3156FlashBorrower.onFlashLoan");

    // WETH token used in the pool
    WETH public immutable weth;

    // Trusted forwarder for meta-transactions
    address public immutable trustedForwarder;

    // Address receiving flash loan fees
    address public immutable feeReceiver;

    // User deposits (accounting)
    mapping(address => uint256) public deposits;

    // Total pool deposits
    uint256 public totalDeposits;

    // Custom errors
    error RepayFailed();
    error UnsupportedCurrency();
    error CallbackFailed();

    /**
     * @notice Constructor initializes pool
     * Deposits initial ETH into WETH
     */
    constructor(address _trustedForwarder, address payable _weth, address _feeReceiver) payable {
        weth = WETH(_weth);
        trustedForwarder = _trustedForwarder;
        feeReceiver = _feeReceiver;

        // Wrap ETH → WETH and store as deposit
        _deposit(msg.value);
    }

    /**
     * @notice Max amount available for flash loan
     */
    function maxFlashLoan(address token) external view returns (uint256) {
        if (token == address(weth)) {
            return weth.balanceOf(address(this));
        }
        return 0;
    }

    /**
     * @notice Fixed flash loan fee
     */
    function flashFee(address token, uint256) external view returns (uint256) {
        if (token != address(weth)) revert UnsupportedCurrency();
        return FIXED_FEE;
    }

    /**
     * @notice Core flash loan function
     */
    function flashLoan(IERC3156FlashBorrower receiver,address token,uint256 amount,bytes calldata data) external
        returns (bool)
    {
        if (token != address(weth)) revert UnsupportedCurrency();

        /**
         * STEP 1: Transfer funds to borrower
         */
        weth.transfer(address(receiver), amount);

        // Update internal accounting
        totalDeposits -= amount;

        /**
         * STEP 2: Call borrower callback
         */
        if (
            receiver.onFlashLoan(msg.sender, address(weth),amount, FIXED_FEE,
                data
            ) != CALLBACK_SUCCESS
        ) {
            revert CallbackFailed();
        }

        /**
         * STEP 3: Pull repayment (amount + fee)
         */
        uint256 amountWithFee = amount + FIXED_FEE;

        // Pull funds from borrower
        weth.transferFrom(address(receiver), address(this), amountWithFee);

        // Update accounting
        totalDeposits += amountWithFee;

        /**
         * STEP 4: Assign fee to feeReceiver
         */
        deposits[feeReceiver] += FIXED_FEE;

        return true;
    }

    /**
     * @notice Withdraw deposited WETH
     */
    function withdraw(uint256 amount, address payable receiver) external {

        // Deduct from user's balance
        deposits[_msgSender()] -= amount;

        // Update total pool balance
        totalDeposits -= amount;

        // Transfer WETH (not ETH!)
        weth.transfer(receiver, amount);
    }

    /**
     * @notice Deposit ETH → converted to WETH
     */
    function deposit() external payable {
        _deposit(msg.value);
    }

    /**
     * @dev Internal deposit logic
     */
    function _deposit(uint256 amount) private {

        // Convert ETH → WETH
        weth.deposit{value: amount}();

        // Credit sender
        deposits[_msgSender()] += amount;

        // Update total deposits
        totalDeposits += amount;
    }

    /**
     * @notice Meta-transaction support
     * Extracts real sender from calldata if called via trusted forwarder
     */
    function _msgSender() internal view override returns (address) {

        if (msg.sender == trustedForwarder && msg.data.length >= 20) {

            // Last 20 bytes = original sender
            // @audit - Here we can control msg.data as it has to be trusted forwarder so we can change the last 20 bytes with the account on whose behalf we wantto perform withdraw function   
            return address(bytes20(msg.data[msg.data.length - 20:]));

        } else {
            return super._msgSender();
        }
    }
}
