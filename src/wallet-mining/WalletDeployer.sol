// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeProxyFactory} from "@safe-global/safe-smart-account/contracts/proxies/SafeProxyFactory.sol";

/**
 * @title WalletDeployer
 * @notice Rewards users for deploying Safe wallets
 *
 * CORE IDEA:
 * - Deploy a Safe via factory
 * - If deployment matches expected address → reward tokens
 * - Optional authorization via external contract (mom)
 */
contract WalletDeployer {

    /// @notice Safe factory used for deployment
    SafeProxyFactory public immutable cook;

    /// @notice Safe singleton (implementation contract)
    address public immutable cpy;

    /// @notice Reward amount (1 token)
    uint256 public constant pay = 1 ether;

    /// @notice Admin who can set authorizer
    address public immutable chief;

    /// @notice ERC20 token used as reward
    address public immutable gem;

    /// @notice Authorization contract (optional)
    address public mom;

    /// @notice Unused variable (likely placeholder / misleading)
    address public hat;

    /// @dev Generic error
    error Boom();

    /**
     * @param _gem Token address (reward token)
     * @param _cook Safe factory
     * @param _cpy Safe singleton
     * @param _chief Admin address
     */
    constructor(address _gem, address _cook, address _cpy, address _chief) {
        gem = _gem;
        cook = SafeProxyFactory(_cook);
        cpy = _cpy;
        chief = _chief;
    }

    /**
     * @notice Sets authorization contract
     *
     * CONDITIONS:
     * - Only chief can call
     * - Can only be set once
     * - Cannot be zero address
     */
    function rule(address _mom) external {
        if (msg.sender != chief || _mom == address(0) || mom != address(0)) {
            revert Boom();
        }
        mom = _mom;
    }

    /**
     * @notice Deploy Safe wallet and receive reward
     *
     * @param aim Expected Safe address
     * @param wat Initialization calldata (Safe.setup)
     * @param num Nonce used in CREATE2 deployment
     *
     * FLOW:
     * 1. Check authorization (if enabled)
     * 2. Deploy Safe using factory
     * 3. Verify deployed address matches expected (aim)
     * 4. Transfer reward
     */
    function drop(address aim, bytes memory wat, uint256 num) external returns (bool) {

        // Authorization check (optional)
        // Calls external contract (mom) via `can()`
        if (mom != address(0) && !can(msg.sender, aim)) {
            return false;
        }

        // Deploy Safe using CREATE2 via factory
        // IMPORTANT: Address depends on (cpy, wat, num)
        if (address(cook.createProxyWithNonce(cpy, wat, num)) != aim) {
            return false;
        }

        // Reward user if contract has enough tokens
        if (IERC20(gem).balanceOf(address(this)) >= pay) {
            IERC20(gem).transfer(msg.sender, pay);
        }

        return true;
    }

    /**
     * @notice Authorization check via external contract
     *
     * Calls:
     * mom.can(user, walletAddress)
     *
     * IMPLEMENTED IN ASSEMBLY:
     * - Function selector = 0x4538c4eb
     * - Equivalent to: can(address,address)
     *
     * CRITICAL:
     * - If `mom` is malicious → arbitrary behavior
     * - If call fails → execution stops (not revert)
     */
    function can(address u, address a) public view returns (bool y) {
        assembly {
            // Load mom address from storage slot 0
            let m := sload(0)

            // Ensure mom is a contract
            if iszero(extcodesize(m)) { stop() }

            // Prepare calldata
            let p := mload(0x40)
            mstore(0x40, add(p, 0x44))

            // function selector: can(address,address)
            mstore(p, shl(0xe0, 0x4538c4eb))

            // arguments
            mstore(add(p, 0x04), u)
            mstore(add(p, 0x24), a)

            // Call external contract
            if iszero(staticcall(gas(), m, p, 0x44, p, 0x20)) { stop() }

            // Load return value
            y := mload(p)
        }
    }
}