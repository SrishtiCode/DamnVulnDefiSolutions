 // SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

// Utility library for low-level calls (safe wrappers)
import {Address} from "@openzeppelin/contracts/utils/Address.sol";

// Provides msg.sender abstraction (useful for meta-transactions)
import {Context} from "@openzeppelin/contracts/utils/Context.sol";

/**
 * @title Multicall
 * @notice Allows batching multiple function calls into a single transaction
 */
abstract contract Multicall is Context {

    /**
     * @notice Execute multiple function calls in a single transaction
     * @param data Array of encoded function calls (ABI encoded)
     * @return results Array of return data from each call
     */
    function multicall(bytes[] calldata data)
        external
        virtual
        returns (bytes[] memory results)
    {
        // Initialize array to store results of each call
        results = new bytes[](data.length);

        /**
         * Loop through each encoded function call
         */
        for (uint256 i = 0; i < data.length; i++) {

            /**
             * delegatecall to self:
             * - Executes function in THIS contract's context
             * - msg.sender remains the original caller
             * - storage modifications affect THIS contract
             */
            results[i] = Address.functionDelegateCall(
                address(this), // target is this contract
                data[i]        // encoded function call
            );
        }

        // Return all results
        return results;
    }
}
