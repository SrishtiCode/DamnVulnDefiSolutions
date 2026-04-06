// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

// Import ownership utility (onlyOwner modifier)
import {Ownable} from "solady/auth/Ownable.sol";

// Safe ERC20 transfers (handles non-standard tokens safely)
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";

// Standard ERC20 interface
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Gnosis Safe contracts
import {Safe} from "safe-smart-account/contracts/Safe.sol";
import {SafeProxy} from "safe-smart-account/contracts/proxies/SafeProxy.sol";
import {IProxyCreationCallback} from "safe-smart-account/contracts/proxies/IProxyCreationCallback.sol";

/**
 * @notice A registry for Safe multisig wallets.
 *         When known beneficiaries deploy and register their wallets,
 *         the registry awards tokens to the wallet.
 *
 * @dev The registry enforces strict validation to ensure only legitimate Safe wallets
 *      (with expected configuration) receive rewards.
 */
contract WalletRegistry is IProxyCreationCallback, Ownable {
    
    // Expected wallet configuration
    uint256 private constant EXPECTED_OWNERS_COUNT = 1;   // Only 1 owner allowed
    uint256 private constant EXPECTED_THRESHOLD = 1;      // 1-of-1 multisig
    uint256 private constant PAYMENT_AMOUNT = 10e18;      // Reward amount (10 tokens)

    // Immutable configuration set at deployment
    address public immutable singletonCopy;  // Safe master copy (implementation)
    address public immutable walletFactory;  // Safe proxy factory
    IERC20 public immutable token;           // Token to distribute

    // Tracks eligible users who can claim rewards
    mapping(address => bool) public beneficiaries;

    // Maps beneficiary → deployed wallet address
    mapping(address => address) public wallets;

    // Custom errors (gas efficient)
    error NotEnoughFunds();
    error CallerNotFactory();
    error FakeSingletonCopy();
    error InvalidInitialization();
    error InvalidThreshold(uint256 threshold);
    error InvalidOwnersCount(uint256 count);
    error OwnerIsNotABeneficiary();
    error InvalidFallbackManager(address fallbackManager);

    /**
     * @notice Constructor initializes registry configuration
     * @param singletonCopyAddress Safe master copy contract
     * @param walletFactoryAddress Safe proxy factory
     * @param tokenAddress ERC20 reward token
     * @param initialBeneficiaries List of allowed users
     */
    constructor(
        address singletonCopyAddress,
        address walletFactoryAddress,
        address tokenAddress,
        address[] memory initialBeneficiaries
    ) {
        // Set contract owner
        _initializeOwner(msg.sender);

        // Set immutable addresses
        singletonCopy = singletonCopyAddress;
        walletFactory = walletFactoryAddress;
        token = IERC20(tokenAddress);

        // Register initial beneficiaries
        for (uint256 i = 0; i < initialBeneficiaries.length; ++i) {
            unchecked {
                beneficiaries[initialBeneficiaries[i]] = true;
            }
        }
    }

    /**
     * @notice Adds a new beneficiary (only owner)
     */
    function addBeneficiary(address beneficiary) external onlyOwner {
        beneficiaries[beneficiary] = true;
    }

    /**
     * @notice Callback function triggered when a Safe wallet is created
     *         via SafeProxyFactory.createProxyWithCallback()
     *
     * @param proxy The deployed SafeProxy instance
     * @param singleton The implementation contract used
     * @param initializer Initialization calldata (Safe.setup)
     */
    function proxyCreated(
        SafeProxy proxy,
        address singleton,
        bytes calldata initializer,
        uint256
    ) external override {

        // Ensure registry has enough tokens before proceeding
        if (token.balanceOf(address(this)) < PAYMENT_AMOUNT) {
            revert NotEnoughFunds();
        }

        // Cast proxy to wallet address
        address payable walletAddress = payable(proxy);

        // Ensure only the official factory can call this
        if (msg.sender != walletFactory) {
            revert CallerNotFactory();
        }

        // Ensure correct Safe implementation is used
        if (singleton != singletonCopy) {
            revert FakeSingletonCopy();
        }

        // Ensure initializer is calling Safe.setup()
        if (bytes4(initializer[:4]) != Safe.setup.selector) {
            revert InvalidInitialization();
        }

        // Verify wallet threshold (must be 1-of-1)
        uint256 threshold = Safe(walletAddress).getThreshold();
        if (threshold != EXPECTED_THRESHOLD) {
            revert InvalidThreshold(threshold);
        }

        // Verify number of owners (must be exactly 1)
        address[] memory owners = Safe(walletAddress).getOwners();
        if (owners.length != EXPECTED_OWNERS_COUNT) {
            revert InvalidOwnersCount(owners.length);
        }

        // Extract the single owner
        address walletOwner;
        unchecked {
            walletOwner = owners[0];
        }

        // Ensure owner is an eligible beneficiary
        if (!beneficiaries[walletOwner]) {
            revert OwnerIsNotABeneficiary();
        }

        // Ensure no fallback manager is set (security check)
        // fallback manager can enable arbitrary execution via fallback
        address fallbackManager = _getFallbackManager(walletAddress);
        if (fallbackManager != address(0)) {
            revert InvalidFallbackManager(fallbackManager);
        }

        // Mark beneficiary as claimed (prevent reuse)
        beneficiaries[walletOwner] = false;

        // Register the wallet
        wallets[walletOwner] = walletAddress;

        // Transfer reward tokens to the new wallet
        SafeTransferLib.safeTransfer(address(token), walletAddress, PAYMENT_AMOUNT);
    }

    /**
     * @notice Reads fallback manager from Safe storage
     * @dev Uses low-level storage slot access
     *
     * WHY IMPORTANT:
     * If fallbackManager is set, attacker can:
     * - hijack execution via fallback
     * - bypass intended Safe behavior
     */
    function _getFallbackManager(address payable wallet) private view returns (address) {
        return abi.decode(
            Safe(wallet).getStorageAt(
                uint256(keccak256("fallback_manager.handler.address")),
                0x20
            ),
            (address)
        );
    }
}