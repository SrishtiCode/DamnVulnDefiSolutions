// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";

interface IFlashLoanEtherReceiver {
    function execute() external payable;
}

/**
 * @title SideEntranceLenderPool
 * @notice A simple ETH lending pool that supports flash loans.
 *
 * @dev !! VULNERABILITY: The flashLoan() repayment check only verifies that
 *      address(this).balance has been restored — it does NOT check HOW the ETH
 *      was returned. This means a borrower can repay the flash loan by calling
 *      deposit() inside execute(), which credits their internal balance while
 *      also satisfying the balance check. They can then call withdraw() to drain
 *      the entire pool. This is a classic "side entrance" accounting bug.
 *
 * Attack flow:
 *   1. Attacker calls flashLoan(poolBalance)
 *   2. In execute(), attacker calls deposit{value: poolBalance}()
 *      → Pool's ETH balance is restored ✓ (repayment check passes)
 *      → But attacker now has balances[attacker] = poolBalance (free credit!)
 *   3. Attacker calls withdraw()
 *      → Pool transfers poolBalance ETH to attacker
 *      → Pool is drained 
 */
contract SideEntranceLenderPool {

    // Tracks each user's deposited ETH balance (internal accounting)
    mapping(address => uint256) public balances;

    // Thrown when the pool's ETH balance is not restored after a flash loan
    error RepayFailed();

    event Deposit(address indexed who, uint256 amount);
    event Withdraw(address indexed who, uint256 amount);

    /**
     * @notice Deposit ETH into the pool.
     * @dev Increments the caller's internal balance by msg.value.
     *      Uses `unchecked` since overflow of uint256 is practically impossible.
     *
     *      !! VULNERABILITY ENTRY POINT: Calling this during a flash loan's
     *      execute() repays the loan at the ETH level, but also grants the
     *      caller a withdrawable balance — effectively stealing pool funds.
     */
    function deposit() external payable {
        unchecked {
            balances[msg.sender] += msg.value;
        }
        emit Deposit(msg.sender, msg.value);
    }

    /**
     * @notice Withdraw all of the caller's deposited ETH.
     * @dev Deletes the balance before transferring to prevent re-entrancy.
     *      Uses SafeTransferLib to safely send ETH (reverts on failure).
     */
    function withdraw() external {
        uint256 amount = balances[msg.sender];
        delete balances[msg.sender]; // Zero out balance before transfer (CEI pattern)
        emit Withdraw(msg.sender, amount);
        SafeTransferLib.safeTransferETH(msg.sender, amount);
    }

    /**
     * @notice Borrow ETH via a flash loan — must be repaid within the same tx.
     * @param amount The amount of ETH to borrow.
     *
     * @dev Repayment is validated by comparing address(this).balance before
     *      and after the external call.
     *
     *      !! VULNERABILITY: This check is insufficient — it only verifies the
     *      raw ETH balance, not whether the repaid ETH came from the borrower's
     *      own funds. Repaying via deposit() satisfies the check while silently
     *      minting a withdrawable balance for the attacker.
     *
     *      A safe fix would be to also verify that total tracked `balances`
     *      have not increased during the loan, or to use a reentrancy guard
     *      that blocks deposit() while a flash loan is active.
     */
    function flashLoan(uint256 amount) external {
        uint256 balanceBefore = address(this).balance;

        // Call the borrower's execute() function, sending `amount` ETH
        // The borrower MUST return the ETH by end of this call
        IFlashLoanEtherReceiver(msg.sender).execute{value: amount}();

        // !! WEAK CHECK: Only verifies raw ETH balance, not accounting integrity
        if (address(this).balance < balanceBefore) {
            revert RepayFailed();
        }
    }
}