pragma solidity =0.8.25;

// Import interface for ERC3156 flash loan receiver
import {IERC3156FlashBorrower} from "@openzeppelin/contracts/interfaces/IERC3156FlashBorrower.sol";

// Import WETH token and the lending pool contract
import {WETH, NaiveReceiverPool} from "./NaiveReceiverPool.sol";

// This contract receives flash loans and implements the required callback
contract FlashLoanReceiver is IERC3156FlashBorrower {

    // Address of the lending pool
    address private pool;

    // Constructor sets the pool address at deployment
    constructor(address _pool) {
        pool = _pool;
    }

    /**
     * @notice Callback function executed by the pool during a flash loan
     * Address that initiated the loan (ignored here)
     * @param token Address of the token being borrowed
     * @param amount Amount borrowed
     * @param fee Fee to be paid on top of borrowed amount
     * Arbitrary data (unused here)
     */
    function onFlashLoan(
        address,//@audit - Did'nt use the parameter, it ignore the initiator. So, it doesn't have the context who requested the flash loan (ACCESS CONTROL PROBLEM) 
        address token,
        uint256 amount,
        uint256 fee,
        bytes calldata
    )
        external
        returns (bytes32)
    {
        // SECURITY CHECK (assembly for gas optimization):
        // Ensures that ONLY the trusted pool contract can call this function.
        // If caller != stored pool address → revert.
        assembly {
            if iszero(eq(sload(pool.slot), caller())) {
                mstore(0x00, 0x48f5c3ed)
                revert(0x1c, 0x04)
            }
        }

        /**
         * Validate that the borrowed token is WETH from the pool
         * Prevents receiving unexpected or malicious tokens
         */
        if (token != address(NaiveReceiverPool(pool).weth())) {
            revert NaiveReceiverPool.UnsupportedCurrency();
        }

        /**
         * Calculate total repayment amount
         * unchecked → gas optimization (safe since overflow is unrealistic here)
         */
        uint256 amountToBeRepaid;
        unchecked {
            amountToBeRepaid = amount + fee;
        }

        /**
         * Place where custom logic happens
         * Example: arbitrage, liquidation, collateral swap, etc.
         */
        _executeActionDuringFlashLoan();

        /**
         * Approve the pool to pull back the loan + fee
         * This is how repayment happens in ERC3156
         */
        WETH(payable(token)).approve(pool, amountToBeRepaid);

        /**
         * Must return this exact hash to signal success
         * Required by ERC3156 standard
         */
        return keccak256("ERC3156FlashBorrower.onFlashLoan");
    }

    /**
     * @notice Internal hook for executing custom logic with borrowed funds
     * Currently empty — should be overridden or extended
     */
    function _executeActionDuringFlashLoan() internal {}
}
