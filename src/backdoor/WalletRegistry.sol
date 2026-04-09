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
 * @title  WalletRegistry
 * @notice A registry for Gnosis Safe multisig wallets.
 *
 *         Flow:
 *           1. Owner registers beneficiary addresses off-chain.
 *           2. Each beneficiary deploys a Safe via SafeProxyFactory.createProxyWithCallback(),
 *              passing this registry as the callback.
 *           3. The factory calls proxyCreated() on this contract after deployment.
 *           4. The registry validates the new Safe (correct singleton, 1-of-1 setup,
 *              no fallback manager, owner is a registered beneficiary).
 *           5. On success, 10 DVT tokens are transferred to the new wallet as a reward.
 *
 * @dev    Implements IProxyCreationCallback so it can be set as the callback target
 *         in SafeProxyFactory.createProxyWithCallback().
 *
 *         KNOWN ATTACK SURFACE (Damn Vulnerable DeFi context):
 *         - The Safe.setup() initializer is decoded off-chain and passed in as raw bytes.
 *           If an attacker can embed a malicious `to`/`data` payload inside that initializer
 *           (Safe's optional delegatecall during setup), they may drain the wallet before
 *           or immediately after the reward is transferred—even though the registry itself
 *           never sees that field.
 *         - The registry only checks owners[], threshold, and fallbackManager *after*
 *           setup has already run, so any side-effects of setup (e.g. a delegatecall that
 *           pre-approves token spending) happen before the guards fire.
 */
contract WalletRegistry is IProxyCreationCallback, Ownable {

    // -------------------------------------------------------------------------
    // Constants — expected Safe configuration for a valid reward claim
    // -------------------------------------------------------------------------

    /// @dev Every registered Safe must have exactly one owner.
    uint256 private constant EXPECTED_OWNERS_COUNT = 1;

    /// @dev The Safe must be a 1-of-1 multisig (threshold == owners count).
    uint256 private constant EXPECTED_THRESHOLD = 1;

    /// @dev Reward paid out to each qualifying Safe wallet, in token base units (18 decimals → 10 tokens).
    uint256 private constant PAYMENT_AMOUNT = 10e18;

    // -------------------------------------------------------------------------
    // Immutable state — set once in the constructor, cannot be changed
    // -------------------------------------------------------------------------

    /// @notice Address of the canonical Safe singleton (master-copy / implementation).
    ///         Every proxy created through the official factory delegates calls here.
    ///         Checked in proxyCreated() to prevent attackers from supplying a fake
    ///         singleton that mimics the Safe ABI but has backdoors.
    address public immutable singletonCopy;

    /// @notice Address of the SafeProxyFactory that is allowed to call proxyCreated().
    ///         Acts as a strict allowlist: any call from a different address is rejected,
    ///         preventing anyone from triggering reward payouts by calling the callback directly.
    address public immutable walletFactory;

    /// @notice The ERC-20 token distributed as a reward (e.g. DVT in the CTF).
    IERC20 public immutable token;

    // -------------------------------------------------------------------------
    // Mutable state
    // -------------------------------------------------------------------------

    /// @notice Tracks addresses that are eligible to receive the token reward.
    ///         Set to false once the beneficiary has deployed and registered a wallet,
    ///         ensuring each address can only claim once.
    mapping(address => bool) public beneficiaries;

    /// @notice Maps each beneficiary address to the Safe wallet they deployed.
    ///         Populated in proxyCreated() after all validation passes.
    mapping(address => address) public wallets;

    // -------------------------------------------------------------------------
    // Custom errors — cheaper than require() + string, introduced in Solidity 0.8
    // -------------------------------------------------------------------------

    /// @dev Registry does not hold enough tokens to pay the reward.
    error NotEnoughFunds();

    /// @dev proxyCreated() was not called by the authorised walletFactory.
    error CallerNotFactory();

    /// @dev The proxy was deployed against an unexpected singleton (not singletonCopy).
    error FakeSingletonCopy();

    /// @dev The first four bytes of the initializer do not match Safe.setup.selector.
    error InvalidInitialization();

    /// @dev Safe threshold does not equal EXPECTED_THRESHOLD.
    error InvalidThreshold(uint256 threshold);

    /// @dev Owner count does not equal EXPECTED_OWNERS_COUNT.
    error InvalidOwnersCount(uint256 count);

    /// @dev The sole Safe owner is not a registered beneficiary.
    error OwnerIsNotABeneficiary();

    /// @dev A non-zero fallback manager was detected, which could allow arbitrary execution.
    error InvalidFallbackManager(address fallbackManager);

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    /**
     * @param singletonCopyAddress  Canonical Safe implementation address.
     * @param walletFactoryAddress  SafeProxyFactory address (the only allowed caller of proxyCreated).
     * @param tokenAddress          ERC-20 reward token.
     * @param initialBeneficiaries  Seed list of addresses that may claim a reward.
     */
    constructor(
        address singletonCopyAddress,
        address walletFactoryAddress,
        address tokenAddress,
        address[] memory initialBeneficiaries
    ) {
        // Assign msg.sender as the contract owner (uses Solady's Ownable pattern).
        _initializeOwner(msg.sender);

        // Lock in the expected Safe singleton and factory addresses.
        singletonCopy = singletonCopyAddress;
        walletFactory = walletFactoryAddress;

        // Store the reward token reference.
        token = IERC20(tokenAddress);

        // Register every address in the seed list as a beneficiary.
        // unchecked: array length cannot realistically overflow a uint256.
        for (uint256 i = 0; i < initialBeneficiaries.length; ++i) {
            unchecked {
                beneficiaries[initialBeneficiaries[i]] = true;
            }
        }
    }

    // -------------------------------------------------------------------------
    // Owner-only administration
    // -------------------------------------------------------------------------

    /**
     * @notice Adds a new beneficiary after deployment.
     * @dev    Only the contract owner may call this, preventing arbitrary self-registration.
     * @param beneficiary Address to mark as eligible for a reward.
     */
    function addBeneficiary(address beneficiary) external onlyOwner {
        beneficiaries[beneficiary] = true;
    }

    // -------------------------------------------------------------------------
    // IProxyCreationCallback implementation
    // -------------------------------------------------------------------------

    /**
     * @notice Callback invoked by SafeProxyFactory immediately after a new Safe proxy
     *         is deployed via createProxyWithCallback().
     *
     * @dev    Validation order matters — each check is a gate; failure reverts the
     *         entire factory transaction, so no proxy is left in a partially-registered state.
     *
     *         Checks (in order):
     *           1. Registry holds enough tokens for the reward.
     *           2. Caller is the authorised walletFactory.
     *           3. The proxy uses the expected singleton implementation.
     *           4. Initializer begins with Safe.setup selector.
     *           5. Deployed wallet has threshold == 1.
     *           6. Deployed wallet has exactly 1 owner.
     *           7. That owner is a registered beneficiary.
     *           8. No fallback manager is set on the wallet.
     *
     *         After all checks pass:
     *           - Beneficiary flag cleared (replay protection).
     *           - Wallet address recorded.
     *           - PAYMENT_AMOUNT tokens transferred to the new wallet.
     *
     * @param proxy       The newly deployed SafeProxy.
     * @param singleton   The Safe implementation the proxy delegates to.
     * @param initializer Raw calldata that was passed to the proxy's constructor
     *                    (should be an ABI-encoded call to Safe.setup()).
     */
    function proxyCreated(
        SafeProxy proxy,
        address singleton,
        bytes calldata initializer,
        uint256 // saltNonce — unused by this registry
    ) external override {

        // --- Guard 1: liquidity check ---
        // Revert early if the registry cannot fulfil the reward.
        // This avoids wasting gas on subsequent checks when payout is impossible.
        if (token.balanceOf(address(this)) < PAYMENT_AMOUNT) {
            revert NotEnoughFunds();
        }

        // Convenience cast: treat the proxy address as a payable address for
        // subsequent Safe interface calls (getThreshold, getOwners, getStorageAt).
        address payable walletAddress = payable(proxy);

        // --- Guard 2: authorised caller ---
        // Only the canonical walletFactory may trigger reward payouts.
        // Prevents an attacker from calling proxyCreated() directly with a crafted proxy.
        if (msg.sender != walletFactory) {
            revert CallerNotFactory();
        }

        // --- Guard 3: singleton integrity ---
        // Reject proxies that delegate to any address other than the official Safe implementation.
        // A malicious singleton could fake Safe.getOwners() / getThreshold() return values.
        if (singleton != singletonCopy) {
            revert FakeSingletonCopy();
        }

        // --- Guard 4: initializer selector ---
        // The first 4 bytes must be the function selector for Safe.setup().
        // Ensures the proxy was initialised with the standard Safe setup call and not
        // some other function that might configure the wallet differently.
        if (bytes4(initializer[:4]) != Safe.setup.selector) {
            revert InvalidInitialization();
        }

        // --- Guard 5: threshold ---
        // Read the threshold directly from the live proxy (post-setup state).
        // Must be exactly 1 to match EXPECTED_THRESHOLD (1-of-1 multisig).
        uint256 threshold = Safe(walletAddress).getThreshold();
        if (threshold != EXPECTED_THRESHOLD) {
            revert InvalidThreshold(threshold);
        }

        // --- Guard 6: owner count ---
        // Retrieve the owner list from the live proxy.
        // Must contain exactly 1 address to match EXPECTED_OWNERS_COUNT.
        address[] memory owners = Safe(walletAddress).getOwners();
        if (owners.length != EXPECTED_OWNERS_COUNT) {
            revert InvalidOwnersCount(owners.length);
        }

        // Extract the sole owner.
        // unchecked: array length was verified as 1 above; no bounds issue possible.
        address walletOwner;
        unchecked {
            walletOwner = owners[0];
        }

        // --- Guard 7: beneficiary check ---
        // The single owner must be a registered beneficiary.
        // Prevents anyone from deploying a Safe on behalf of an arbitrary address and
        // redirecting the reward to themselves via ownership tricks.
        if (!beneficiaries[walletOwner]) {
            revert OwnerIsNotABeneficiary();
        }

        // --- Guard 8: fallback manager ---
        // A non-zero fallback manager allows arbitrary contract logic to run whenever
        // the Safe receives an unknown call. An attacker could use this to execute
        // token transfers or approvals outside of the normal multisig flow.
        // Reading from the dedicated storage slot (keccak256("fallback_manager.handler.address"))
        // is the canonical way to inspect this setting without trusting the ABI surface.
        address fallbackManager = _getFallbackManager(walletAddress);
        if (fallbackManager != address(0)) {
            revert InvalidFallbackManager(fallbackManager);
        }

        // --- State update: mark beneficiary as claimed ---
        // Clear the flag before transferring tokens to follow the
        // checks-effects-interactions pattern and prevent reentrancy / double-claiming.
        beneficiaries[walletOwner] = false;

        // Record the wallet address for off-chain indexing and future lookups.
        wallets[walletOwner] = walletAddress;

        // --- Interaction: transfer reward ---
        // Send PAYMENT_AMOUNT tokens directly to the newly deployed Safe wallet.
        // SafeTransferLib.safeTransfer reverts on failure (handles non-standard ERC-20 tokens).
        SafeTransferLib.safeTransfer(address(token), walletAddress, PAYMENT_AMOUNT);
    }

    // -------------------------------------------------------------------------
    // Internal helpers
    // -------------------------------------------------------------------------

    /**
     * @notice Reads the fallback manager address stored inside a Safe wallet.
     *
     * @dev    Gnosis Safe stores the fallback handler at a bespoke storage slot
     *         derived from keccak256("fallback_manager.handler.address") to avoid
     *         collisions with the proxy's own storage layout.
     *
     *         Safe.getStorageAt(slot, length) returns `length` words of raw storage
     *         starting at `slot`. We request 0x20 (32 bytes = 1 word) and ABI-decode
     *         the result as an address (zero-padded to 32 bytes by the EVM).
     *
     *         WHY THIS MATTERS (security):
     *         If a fallback manager is set, an attacker who cannot pass the owner/threshold
     *         checks can still gain arbitrary execution over the wallet by crafting calls
     *         that hit the fallback path — potentially draining the reward tokens that
     *         were just transferred in.
     *
     * @param  wallet  The Safe proxy whose fallback manager slot is being inspected.
     * @return         The address stored as the fallback manager, or address(0) if unset.
     */
    function _getFallbackManager(address payable wallet) private view returns (address) {
        return abi.decode(
            Safe(wallet).getStorageAt(
                uint256(keccak256("fallback_manager.handler.address")), // storage slot
                0x20  // read exactly 32 bytes (one EVM word)
            ),
            (address)  // decode the 32-byte word as an Ethereum address
        );
    }
}
