 forge test --match-path Withdrawal.t.sol -vvvv 
[⠊] Compiling...
[⠃] Compiling 6 files with Solc 0.8.25
[⠊] Solc 0.8.25 finished in 1.80s
Compiler run successful!

Ran 2 tests for test/withdrawal/Withdrawal.t.sol:WithdrawalChallenge
[PASS] test_assertInitialState() (gas: 50741)
Traces:
  [50741] WithdrawalChallenge::test_assertInitialState()
    ├─ [2327] L1Forwarder::owner() [staticcall]
    │   └─ ← [Return] deployer: [0xaE0bDc4eEAC5E950B67C6819B118761CaAF61946]
    ├─ [0] VM::assertEq(deployer: [0xaE0bDc4eEAC5E950B67C6819B118761CaAF61946], deployer: [0xaE0bDc4eEAC5E950B67C6819B118761CaAF61946]) [staticcall]
    │   └─ ← [Return]
    ├─ [2371] L1Forwarder::gateway() [staticcall]
    │   └─ ← [Return] L1Gateway: [0x1240FA2A84dd9157a0e76B5Cfe98B1d52268B264]
    ├─ [0] VM::assertEq(L1Gateway: [0x1240FA2A84dd9157a0e76B5Cfe98B1d52268B264], L1Gateway: [0x1240FA2A84dd9157a0e76B5Cfe98B1d52268B264]) [staticcall]
    │   └─ ← [Return]
    ├─ [2349] L1Gateway::owner() [staticcall]
    │   └─ ← [Return] deployer: [0xaE0bDc4eEAC5E950B67C6819B118761CaAF61946]
    ├─ [0] VM::assertEq(deployer: [0xaE0bDc4eEAC5E950B67C6819B118761CaAF61946], deployer: [0xaE0bDc4eEAC5E950B67C6819B118761CaAF61946]) [staticcall]
    │   └─ ← [Return]
    ├─ [2631] L1Gateway::rolesOf(player: [0x44E97aF4418b7a17AABD8090bEA0A471a366305C]) [staticcall]
    │   └─ ← [Return] 1
    ├─ [304] L1Gateway::OPERATOR_ROLE() [staticcall]
    │   └─ ← [Return] 1
    ├─ [0] VM::assertEq(1, 1) [staticcall]
    │   └─ ← [Return]
    ├─ [305] L1Gateway::DELAY() [staticcall]
    │   └─ ← [Return] 604800 [6.048e5]
    ├─ [0] VM::assertEq(604800 [6.048e5], 604800 [6.048e5]) [staticcall]
    │   └─ ← [Return]
    ├─ [2337] L1Gateway::root() [staticcall]
    │   └─ ← [Return] 0x4e0f53ae5c8d5bc5fd1a522b9f37edfd782d6f4c7d8e0df1391534c081233d9e
    ├─ [0] VM::assertEq(0x4e0f53ae5c8d5bc5fd1a522b9f37edfd782d6f4c7d8e0df1391534c081233d9e, 0x4e0f53ae5c8d5bc5fd1a522b9f37edfd782d6f4c7d8e0df1391534c081233d9e) [staticcall]
    │   └─ ← [Return]
    ├─ [2516] DamnValuableToken::balanceOf(TokenBridge: [0x9c52B2C4A89E2BE37972d18dA937cbAd8AA8bd50]) [staticcall]
    │   └─ ← [Return] 1000000000000000000000000 [1e24]
    ├─ [0] VM::assertEq(1000000000000000000000000 [1e24], 1000000000000000000000000 [1e24]) [staticcall]
    │   └─ ← [Return]
    ├─ [2293] TokenBridge::totalDeposits() [staticcall]
    │   └─ ← [Return] 1000000000000000000000000 [1e24]
    ├─ [0] VM::assertEq(1000000000000000000000000 [1e24], 1000000000000000000000000 [1e24]) [staticcall]
    │   └─ ← [Return]
    └─ ← [Stop]

[PASS] test_withdrawal() (gas: 468592)
Logs:
  token.balanceOf(address(l1TokenBridge) 999970000000000000000000

Traces:
  [591005] WithdrawalChallenge::test_withdrawal()
    ├─ [0] VM::startPrank(player: [0x44E97aF4418b7a17AABD8090bEA0A471a366305C], player: [0x44E97aF4418b7a17AABD8090bEA0A471a366305C])
    │   └─ ← [Return]
    ├─ [139049] L1Gateway::finalizeWithdrawal(0, l2Handler: [0x87EAD3e78Ef9E26de92083b75a3b037aC2883E16], L1Forwarder: [0xfF2Bd636B9Fc89645C2D336aeaDE2E4AbaFe1eA5], 1718182115 [1.718e9], 0x01210a38000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000009c52b2c4a89e2be37972d18da937cbad8aa8bd500000000000000000000000000000000000000000000000000000000000000080000000000000000000000000000000000000000000000000000000000000004481191e5100000000000000000000000044e97af4418b7a17aabd8090bea0a471a366305c00000000000000000000000000000000000000000000be951906eba2aa80000000000000000000000000000000000000000000000000000000000000, [])
    │   ├─ [80755] L1Forwarder::forwardMessage(0, 0x0000000000000000000000000000000000000000, TokenBridge: [0x9c52B2C4A89E2BE37972d18dA937cbAd8AA8bd50], 0x81191e5100000000000000000000000044e97af4418b7a17aabd8090bea0a471a366305c00000000000000000000000000000000000000000000be951906eba2aa800000)
    │   │   ├─ [425] L1Gateway::xSender() [staticcall]
    │   │   │   └─ ← [Return] l2Handler: [0x87EAD3e78Ef9E26de92083b75a3b037aC2883E16]
    │   │   ├─ [38934] TokenBridge::executeTokenWithdrawal(player: [0x44E97aF4418b7a17AABD8090bEA0A471a366305C], 900000000000000000000000 [9e23])
    │   │   │   ├─ [364] L1Forwarder::getSender() [staticcall]
    │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   │   │   ├─ [29670] DamnValuableToken::transfer(player: [0x44E97aF4418b7a17AABD8090bEA0A471a366305C], 900000000000000000000000 [9e23])
    │   │   │   │   ├─ emit Transfer(from: TokenBridge: [0x9c52B2C4A89E2BE37972d18dA937cbAd8AA8bd50], to: player: [0x44E97aF4418b7a17AABD8090bEA0A471a366305C], amount: 900000000000000000000000 [9e23])
    │   │   │   │   └─ ← [Return] true
    │   │   │   └─ ← [Stop]
    │   │   └─ ← [Stop]
    │   ├─ emit FinalizedWithdrawal(leaf: 0x87402b64b810a01ef199fa33add571f05140bbeb44415e4e8f654b38ed0e7d10, success: true, isOperator: true)
    │   └─ ← [Stop]
    ├─ [0] VM::warp(1719478115 [1.719e9])
    │   └─ ← [Return]
    ├─ [107949] L1Gateway::finalizeWithdrawal(0, l2Handler: [0x87EAD3e78Ef9E26de92083b75a3b037aC2883E16], L1Forwarder: [0xfF2Bd636B9Fc89645C2D336aeaDE2E4AbaFe1eA5], 1718786915 [1.718e9], 0x01210a380000000000000000000000000000000000000000000000000000000000000000000000000000000000000000328809bc894f92807417d2dad6b7c998c1afdac60000000000000000000000009c52b2c4a89e2be37972d18da937cbad8aa8bd500000000000000000000000000000000000000000000000000000000000000080000000000000000000000000000000000000000000000000000000000000004481191e51000000000000000000000000328809bc894f92807417d2dad6b7c998c1afdac60000000000000000000000000000000000000000000000008ac7230489e8000000000000000000000000000000000000000000000000000000000000, [])
    │   ├─ [78055] L1Forwarder::forwardMessage(0, 0x328809Bc894f92807417D2dAD6b7C998c1aFdac6, TokenBridge: [0x9c52B2C4A89E2BE37972d18dA937cbAd8AA8bd50], 0x81191e51000000000000000000000000328809bc894f92807417d2dad6b7c998c1afdac60000000000000000000000000000000000000000000000008ac7230489e80000)
    │   │   ├─ [425] L1Gateway::xSender() [staticcall]
    │   │   │   └─ ← [Return] l2Handler: [0x87EAD3e78Ef9E26de92083b75a3b037aC2883E16]
    │   │   ├─ [26834] TokenBridge::executeTokenWithdrawal(0x328809Bc894f92807417D2dAD6b7C998c1aFdac6, 10000000000000000000 [1e19])
    │   │   │   ├─ [364] L1Forwarder::getSender() [staticcall]
    │   │   │   │   └─ ← [Return] 0x328809Bc894f92807417D2dAD6b7C998c1aFdac6
    │   │   │   ├─ [24870] DamnValuableToken::transfer(0x328809Bc894f92807417D2dAD6b7C998c1aFdac6, 10000000000000000000 [1e19])
    │   │   │   │   ├─ emit Transfer(from: TokenBridge: [0x9c52B2C4A89E2BE37972d18dA937cbAd8AA8bd50], to: 0x328809Bc894f92807417D2dAD6b7C998c1aFdac6, amount: 10000000000000000000 [1e19])
    │   │   │   │   └─ ← [Return] true
    │   │   │   └─ ← [Stop]
    │   │   └─ ← [Stop]
    │   ├─ emit FinalizedWithdrawal(leaf: 0xeaebef7f15fdaa66ecd4533eefea23a183ced29967ea67bc4219b0f1f8b0d3ba, success: true, isOperator: true)
    │   └─ ← [Stop]
    ├─ [107949] L1Gateway::finalizeWithdrawal(1, l2Handler: [0x87EAD3e78Ef9E26de92083b75a3b037aC2883E16], L1Forwarder: [0xfF2Bd636B9Fc89645C2D336aeaDE2E4AbaFe1eA5], 1718786965 [1.718e9], 0x01210a3800000000000000000000000000000000000000000000000000000000000000010000000000000000000000001d96f2f6bef1202e4ce1ff6dad0c2cb002861d3e0000000000000000000000009c52b2c4a89e2be37972d18da937cbad8aa8bd500000000000000000000000000000000000000000000000000000000000000080000000000000000000000000000000000000000000000000000000000000004481191e510000000000000000000000001d96f2f6bef1202e4ce1ff6dad0c2cb002861d3e0000000000000000000000000000000000000000000000008ac7230489e8000000000000000000000000000000000000000000000000000000000000, [])
    │   ├─ [78055] L1Forwarder::forwardMessage(1, 0x1D96F2f6BeF1202E4Ce1Ff6Dad0c2CB002861d3e, TokenBridge: [0x9c52B2C4A89E2BE37972d18dA937cbAd8AA8bd50], 0x81191e510000000000000000000000001d96f2f6bef1202e4ce1ff6dad0c2cb002861d3e0000000000000000000000000000000000000000000000008ac7230489e80000)
    │   │   ├─ [425] L1Gateway::xSender() [staticcall]
    │   │   │   └─ ← [Return] l2Handler: [0x87EAD3e78Ef9E26de92083b75a3b037aC2883E16]
    │   │   ├─ [26834] TokenBridge::executeTokenWithdrawal(0x1D96F2f6BeF1202E4Ce1Ff6Dad0c2CB002861d3e, 10000000000000000000 [1e19])
    │   │   │   ├─ [364] L1Forwarder::getSender() [staticcall]
    │   │   │   │   └─ ← [Return] 0x1D96F2f6BeF1202E4Ce1Ff6Dad0c2CB002861d3e
    │   │   │   ├─ [24870] DamnValuableToken::transfer(0x1D96F2f6BeF1202E4Ce1Ff6Dad0c2CB002861d3e, 10000000000000000000 [1e19])
    │   │   │   │   ├─ emit Transfer(from: TokenBridge: [0x9c52B2C4A89E2BE37972d18dA937cbAd8AA8bd50], to: 0x1D96F2f6BeF1202E4Ce1Ff6Dad0c2CB002861d3e, amount: 10000000000000000000 [1e19])
    │   │   │   │   └─ ← [Return] true
    │   │   │   └─ ← [Stop]
    │   │   └─ ← [Stop]
    │   ├─ emit FinalizedWithdrawal(leaf: 0x0b130175aeb6130c81839d7ad4f580cd18931caf177793cd3bab95b8cbb8de60, success: true, isOperator: true)
    │   └─ ← [Stop]
    ├─ [82513] L1Gateway::finalizeWithdrawal(2, l2Handler: [0x87EAD3e78Ef9E26de92083b75a3b037aC2883E16], L1Forwarder: [0xfF2Bd636B9Fc89645C2D336aeaDE2E4AbaFe1eA5], 1718787050 [1.718e9], 0x01210a380000000000000000000000000000000000000000000000000000000000000002000000000000000000000000ea475d60c118d7058bef4bdd9c32ba51139a74e00000000000000000000000009c52b2c4a89e2be37972d18da937cbad8aa8bd500000000000000000000000000000000000000000000000000000000000000080000000000000000000000000000000000000000000000000000000000000004481191e51000000000000000000000000ea475d60c118d7058bef4bdd9c32ba51139a74e000000000000000000000000000000000000000000000d38be6051f27c260000000000000000000000000000000000000000000000000000000000000, [])
    │   ├─ [52619] L1Forwarder::forwardMessage(2, 0xea475d60c118d7058beF4bDd9c32bA51139a74e0, TokenBridge: [0x9c52B2C4A89E2BE37972d18dA937cbAd8AA8bd50], 0x81191e51000000000000000000000000ea475d60c118d7058bef4bdd9c32ba51139a74e000000000000000000000000000000000000000000000d38be6051f27c2600000)
    │   │   ├─ [425] L1Gateway::xSender() [staticcall]
    │   │   │   └─ ← [Return] l2Handler: [0x87EAD3e78Ef9E26de92083b75a3b037aC2883E16]
    │   │   ├─ [1420] TokenBridge::executeTokenWithdrawal(0xea475d60c118d7058beF4bDd9c32bA51139a74e0, 999000000000000000000000 [9.99e23])
    │   │   │   ├─ [364] L1Forwarder::getSender() [staticcall]
    │   │   │   │   └─ ← [Return] 0xea475d60c118d7058beF4bDd9c32bA51139a74e0
    │   │   │   └─ ← [Revert] panic: arithmetic underflow or overflow (0x11)
    │   │   └─ ← [Stop]
    │   ├─ emit FinalizedWithdrawal(leaf: 0xbaee8dea6b24d327bc9fcd7ce867990427b9d6f48a92f4b331514ea688909015, success: true, isOperator: true)
    │   └─ ← [Stop]
    ├─ [107949] L1Gateway::finalizeWithdrawal(3, l2Handler: [0x87EAD3e78Ef9E26de92083b75a3b037aC2883E16], L1Forwarder: [0xfF2Bd636B9Fc89645C2D336aeaDE2E4AbaFe1eA5], 1718787127 [1.718e9], 0x01210a380000000000000000000000000000000000000000000000000000000000000003000000000000000000000000671d2ba5bf3c160a568aae17de26b51390d6bd5b0000000000000000000000009c52b2c4a89e2be37972d18da937cbad8aa8bd500000000000000000000000000000000000000000000000000000000000000080000000000000000000000000000000000000000000000000000000000000004481191e51000000000000000000000000671d2ba5bf3c160a568aae17de26b51390d6bd5b0000000000000000000000000000000000000000000000008ac7230489e8000000000000000000000000000000000000000000000000000000000000, [])
    │   ├─ [78055] L1Forwarder::forwardMessage(3, 0x671d2ba5bF3C160A568Aae17dE26B51390d6BD5b, TokenBridge: [0x9c52B2C4A89E2BE37972d18dA937cbAd8AA8bd50], 0x81191e51000000000000000000000000671d2ba5bf3c160a568aae17de26b51390d6bd5b0000000000000000000000000000000000000000000000008ac7230489e80000)
    │   │   ├─ [425] L1Gateway::xSender() [staticcall]
    │   │   │   └─ ← [Return] l2Handler: [0x87EAD3e78Ef9E26de92083b75a3b037aC2883E16]
    │   │   ├─ [26834] TokenBridge::executeTokenWithdrawal(0x671d2ba5bF3C160A568Aae17dE26B51390d6BD5b, 10000000000000000000 [1e19])
    │   │   │   ├─ [364] L1Forwarder::getSender() [staticcall]
    │   │   │   │   └─ ← [Return] 0x671d2ba5bF3C160A568Aae17dE26B51390d6BD5b
    │   │   │   ├─ [24870] DamnValuableToken::transfer(0x671d2ba5bF3C160A568Aae17dE26B51390d6BD5b, 10000000000000000000 [1e19])
    │   │   │   │   ├─ emit Transfer(from: TokenBridge: [0x9c52B2C4A89E2BE37972d18dA937cbAd8AA8bd50], to: 0x671d2ba5bF3C160A568Aae17dE26B51390d6BD5b, amount: 10000000000000000000 [1e19])
    │   │   │   │   └─ ← [Return] true
    │   │   │   └─ ← [Stop]
    │   │   └─ ← [Stop]
    │   ├─ emit FinalizedWithdrawal(leaf: 0x9a8dbccb6171dc54bfcff6471f4194716688619305b6ededc54108ec35b39b09, success: true, isOperator: true)
    │   └─ ← [Stop]
    ├─ [2970] DamnValuableToken::transfer(TokenBridge: [0x9c52B2C4A89E2BE37972d18dA937cbAd8AA8bd50], 900000000000000000000000 [9e23])
    │   ├─ emit Transfer(from: player: [0x44E97aF4418b7a17AABD8090bEA0A471a366305C], to: TokenBridge: [0x9c52B2C4A89E2BE37972d18dA937cbAd8AA8bd50], amount: 900000000000000000000000 [9e23])
    │   └─ ← [Return] true
    ├─ [516] DamnValuableToken::balanceOf(TokenBridge: [0x9c52B2C4A89E2BE37972d18dA937cbAd8AA8bd50]) [staticcall]
    │   └─ ← [Return] 999970000000000000000000 [9.999e23]
    ├─ [0] console::log("token.balanceOf(address(l1TokenBridge)", 999970000000000000000000 [9.999e23]) [staticcall]
    │   └─ ← [Stop]
    ├─ [0] VM::stopPrank()
    │   └─ ← [Return]
    ├─ [516] DamnValuableToken::balanceOf(TokenBridge: [0x9c52B2C4A89E2BE37972d18dA937cbAd8AA8bd50]) [staticcall]
    │   └─ ← [Return] 999970000000000000000000 [9.999e23]
    ├─ [0] VM::assertLt(999970000000000000000000 [9.999e23], 1000000000000000000000000 [1e24]) [staticcall]
    │   └─ ← [Return]
    ├─ [516] DamnValuableToken::balanceOf(TokenBridge: [0x9c52B2C4A89E2BE37972d18dA937cbAd8AA8bd50]) [staticcall]
    │   └─ ← [Return] 999970000000000000000000 [9.999e23]
    ├─ [0] VM::assertGt(999970000000000000000000 [9.999e23], 990000000000000000000000 [9.9e23]) [staticcall]
    │   └─ ← [Return]
    ├─ [516] DamnValuableToken::balanceOf(player: [0x44E97aF4418b7a17AABD8090bEA0A471a366305C]) [staticcall]
    │   └─ ← [Return] 0
    ├─ [0] VM::assertEq(0, 0) [staticcall]
    │   └─ ← [Return]
    ├─ [383] L1Gateway::counter() [staticcall]
    │   └─ ← [Return] 5
    ├─ [0] VM::assertGe(5, 4, "Not enough finalized withdrawals") [staticcall]
    │   └─ ← [Return]
    ├─ [503] L1Gateway::finalizedWithdrawals(0xeaebef7f15fdaa66ecd4533eefea23a183ced29967ea67bc4219b0f1f8b0d3ba) [staticcall]
    │   └─ ← [Return] true
    ├─ [0] VM::assertTrue(true, "First withdrawal not finalized") [staticcall]
    │   └─ ← [Return]
    ├─ [503] L1Gateway::finalizedWithdrawals(0x0b130175aeb6130c81839d7ad4f580cd18931caf177793cd3bab95b8cbb8de60) [staticcall]
    │   └─ ← [Return] true
    ├─ [0] VM::assertTrue(true, "Second withdrawal not finalized") [staticcall]
    │   └─ ← [Return]
    ├─ [503] L1Gateway::finalizedWithdrawals(0xbaee8dea6b24d327bc9fcd7ce867990427b9d6f48a92f4b331514ea688909015) [staticcall]
    │   └─ ← [Return] true
    ├─ [0] VM::assertTrue(true, "Third withdrawal not finalized") [staticcall]
    │   └─ ← [Return]
    ├─ [503] L1Gateway::finalizedWithdrawals(0x9a8dbccb6171dc54bfcff6471f4194716688619305b6ededc54108ec35b39b09) [staticcall]
    │   └─ ← [Return] true
    ├─ [0] VM::assertTrue(true, "Fourth withdrawal not finalized") [staticcall]
    │   └─ ← [Return]
    └─ ← [Stop]

Suite result: ok. 2 passed; 0 failed; 0 skipped; finished in 7.73ms (1.88ms CPU time)

Ran 1 test suite in 41.96ms (7.73ms CPU time): 2 tests passed, 0 failed, 0 skipped (2 total tests)
