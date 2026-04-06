// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

// OpenZeppelin upgradeable utilities
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

// ERC20 interface
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Safe token transfer library
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";

// Custom contracts
import {ClimberTimelock} from "./ClimberTimelock.sol";
import {WITHDRAWAL_LIMIT, WAITING_PERIOD} from "./ClimberConstants.sol";
import {CallerNotSweeper, InvalidWithdrawalAmount, InvalidWithdrawalTime} from "./ClimberErrors.sol";

/**
 * @title ClimberVault
 * @notice Upgradeable vault contract protected by a timelock.
 * @dev Uses UUPS proxy pattern → implementation logic can be upgraded by owner.
 *
 * KEY IDEA:
 * - Owner = Timelock contract (NOT an EOA)
 * - Timelock controls upgrades & withdrawals
 */
contract ClimberVault is Initializable, OwnableUpgradeable, UUPSUpgradeable {

    // Timestamp of last withdrawal (used for rate-limiting)
    uint256 private _lastWithdrawalTimestamp;

    // Address allowed to sweep all funds (privileged role)
    address private _sweeper;

    /**
     * @dev Restricts access to sweeper only
     */
    modifier onlySweeper() {
        if (msg.sender != _sweeper) {
            revert CallerNotSweeper();
        }
        _;
    }

    /**
     * @dev Disable constructor for upgradeable pattern
     * Prevents implementation contract from being initialized directly
     */
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the vault
     * @param admin Address with admin role in timelock
     * @param proposer Address allowed to schedule operations
     * @param sweeper Address allowed to sweep all funds
     *
     * FLOW:
     * 1. Initializes ownership
     * 2. Deploys timelock contract
     * 3. Transfers ownership to timelock
     * 4. Sets sweeper and withdrawal timestamp
     */
    function initialize(address admin, address proposer, address sweeper) external initializer {
        // Initialize parent contracts
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();

        // Deploy timelock and make it the owner
        // ⚠️ Owner becomes a contract, not user
        transferOwnership(address(new ClimberTimelock(admin, proposer)));

        // Set privileged sweeper
        _setSweeper(sweeper);

        // Initialize withdrawal timestamp
        _updateLastWithdrawalTimestamp(block.timestamp);
    }

    /**
     * @notice Withdraw limited tokens periodically
     * @dev Only callable by owner (timelock)
     *
     * SECURITY CONTROLS:
     * - Withdrawal amount capped
     * - Cooldown period enforced
     */
    function withdraw(address token, address recipient, uint256 amount) external onlyOwner {

        // Ensure amount is within allowed limit
        if (amount > WITHDRAWAL_LIMIT) {
            revert InvalidWithdrawalAmount();
        }

        // Ensure enough time has passed since last withdrawal
        if (block.timestamp <= _lastWithdrawalTimestamp + WAITING_PERIOD) {
            revert InvalidWithdrawalTime();
        }

        // Update withdrawal timestamp BEFORE transfer (prevents reentrancy issues)
        _updateLastWithdrawalTimestamp(block.timestamp);

        // Transfer tokens safely
        SafeTransferLib.safeTransfer(token, recipient, amount);
    }

    /**
     * @notice Sweep ALL tokens to sweeper address
     * @dev Bypasses withdrawal limits → highly privileged function
     *
     * ⚠️ SECURITY CRITICAL:
     * If sweeper is compromised → all funds lost
     */
    function sweepFunds(address token) external onlySweeper {
        SafeTransferLib.safeTransfer(
            token,
            _sweeper,
            IERC20(token).balanceOf(address(this))
        );
    }

    /**
     * @notice Returns sweeper address
     */
    function getSweeper() external view returns (address) {
        return _sweeper;
    }

    /**
     * @dev Internal function to set sweeper
     */
    function _setSweeper(address newSweeper) private {
        _sweeper = newSweeper;
    }

    /**
     * @notice Returns last withdrawal timestamp
     */
    function getLastWithdrawalTimestamp() external view returns (uint256) {
        return _lastWithdrawalTimestamp;
    }

    /**
     * @dev Updates withdrawal timestamp
     */
    function _updateLastWithdrawalTimestamp(uint256 timestamp) private {
        _lastWithdrawalTimestamp = timestamp;
    }

    /**
     * @notice Authorizes contract upgrade (UUPS pattern)
     * @dev Only owner (timelock) can upgrade implementation
     *
     * ⚠️ CRITICAL SECURITY POINT:
     * If attacker gains control of timelock → full upgrade control → total takeover
     */
    function _authorizeUpgrade(address newImplementation)
        internal
        override
        onlyOwner
    {}
}