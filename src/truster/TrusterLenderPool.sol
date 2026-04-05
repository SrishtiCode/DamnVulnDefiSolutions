// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {DamnValuableToken} from "../DamnValuableToken.sol";

contract TrusterLenderPool is ReentrancyGuard {
    using Address for address; // Enables .functionCall() on address types

    // The ERC20 token this pool lends out (immutable = set once at deploy, cheaper to read)
    DamnValuableToken public immutable token;

    // Custom error for gas-efficient revert when borrower fails to repay
    error RepayFailed();

    // Set the token address once at deployment
    constructor(DamnValuableToken _token) {
        token = _token;
    }

    /**
     * @notice Flash loan function — lends `amount` tokens to `borrower`,
     *         then makes an arbitrary call to `target` with `data`,
     *         and finally checks that the pool balance has been restored.
     *
     * @param amount    Number of tokens to lend
     * @param borrower  Address that receives the loaned tokens
     * @param target    Address to call after transferring tokens (attacker-controlled ⚠️)
     * @param data      Calldata to pass to target (attacker-controlled ⚠️)
     *
     * VULNERABILITY: `target` and `data` are fully attacker-controlled.
     * An attacker can pass target=token, data=approve(attacker, pool_balance),
     * causing the pool to approve the attacker to spend all its tokens.
     * After the flashloan ends (balance check passes since no tokens left yet),
     * the attacker calls transferFrom() to drain the pool — in a separate tx.
     */
    function flashLoan(uint256 amount, address borrower, address target, bytes calldata data)
        external
        nonReentrant  // Prevents re-entering this function mid-execution
        returns (bool)
    {
        // Snapshot pool balance before lending to compare against after repayment
        uint256 balanceBefore = token.balanceOf(address(this));

        // Transfer requested tokens to the borrower
        token.transfer(borrower, amount);

        // ⚠️ CRITICAL VULNERABILITY: arbitrary external call made as the pool itself
        // CRITICAL VULNERABILITY: arbitrary external call made as the pool itself
        // The pool (msg.sender context) executes whatever `data` is on `target`
        // e.g. attacker sets target=token, data=token.approve(attacker, type(uint256).max)
        target.functionCall(data);

        // Repayment check: pool balance must be >= balance before the loan
        // Note: only checks token balance, not WHO sent it back
        // Also note: approve() attack passes this check since no tokens moved yet
        if (token.balanceOf(address(this)) < balanceBefore) {
            revert RepayFailed();
        }

        return true;
    }
}
