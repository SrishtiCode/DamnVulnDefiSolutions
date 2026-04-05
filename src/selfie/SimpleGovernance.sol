// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {DamnValuableVotes} from "../DamnValuableVotes.sol";
import {ISimpleGovernance} from "./ISimpleGovernance.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";

// ================================================================
// CONTRACT OVERVIEW: SimpleGovernance
// ================================================================
// A minimal on-chain governance contract that allows token holders
// with >50% of voting supply to queue arbitrary contract calls,
// which can be executed after a mandatory 2-day time-lock delay.
//
// CORE FLOW:
//   1. Proposer holds > 50% of vote supply
//   2. Proposer calls queueAction(target, value, data)
//   3. Anyone waits 2 days
//   4. Anyone calls executeAction(actionId) to run the queued call
//
// VULNERABILITY SURFACE:
//   - Flash loans can temporarily grant >50% votes to queue actions
//     (snapshot is taken at queue time, not execution time)
//   - Once queued, ANY address can execute — not just the proposer
//   - Queued calldata executes with this contract's context/authority
// ================================================================

contract SimpleGovernance is ISimpleGovernance {
    using Address for address; // enables functionCallWithValue() on addresses

    // 2-day mandatory waiting period between queueAction and executeAction
    uint256 private constant ACTION_DELAY_IN_SECONDS = 2 days;

    // ERC20Votes token — voting power is derived from delegate balances
    DamnValuableVotes private _votingToken;

    // Auto-incrementing ID for each queued governance action (starts at 1)
    uint256 private _actionCounter;

    // Storage of all queued actions keyed by their actionId
    mapping(uint256 => GovernanceAction) private _actions;

    // ----------------------------------------------------------------
    // Constructor: bind the governance contract to a specific vote token
    // ----------------------------------------------------------------
    constructor(DamnValuableVotes votingToken) {
        _votingToken = votingToken;
        _actionCounter = 1; // actionId 0 is reserved/invalid
    }

    // ================================================================
    // queueAction()
    // ================================================================
    // Allows any address with >50% of total voting supply to schedule
    // an arbitrary low-level call to be executed after ACTION_DELAY.
    //
    // PARAMETERS:
    //   target  — contract address the call will be made to
    //   value   — ETH (in wei) to forward with the call
    //   data    — ABI-encoded calldata (function selector + args)
    //
    // RETURNS: actionId — numeric ID to reference this queued action
    //
    // VULNERABILITY: Voting power is checked HERE (queue time).
    //   An attacker can flash-borrow tokens, delegate votes to self,
    //   queue a malicious action, then return the tokens — all in one tx.
    //   The queued action remains valid even after votes are returned.
    // ================================================================
    function queueAction(address target, uint128 value, bytes calldata data)
        external
        returns (uint256 actionId)
    {
        // Guard: caller must currently hold >50% of total voting supply
        // ⚠️ Flash loan attack vector: borrow tokens → delegate → queue → return
        if (!_hasEnoughVotes(msg.sender)) {
            revert NotEnoughVotes(msg.sender);
        }

        // Guard: governance cannot queue actions targeting itself
        // (prevents governance from overwriting its own logic/state)
        if (target == address(this)) {
            revert InvalidTarget();
        }

        // Guard: if calldata is provided, target must be a contract
        // (prevents accidentally sending data to an EOA)
        if (data.length > 0 && target.code.length == 0) {
            revert TargetMustHaveCode();
        }

        // Assign the next actionId and store the full action struct
        actionId = _actionCounter;
        _actions[actionId] = GovernanceAction({
            target:     target,
            value:      value,
            proposedAt: uint64(block.timestamp), // time-lock starts now
            executedAt: 0,                        // 0 = not yet executed
            data:       data
        });

        // Increment counter (unchecked: overflow after 2^256 actions is impossible)
        unchecked {
            _actionCounter++;
        }

        emit ActionQueued(actionId, msg.sender);
    }

    // ================================================================
    // executeAction()
    // ================================================================
    // Executes a previously queued governance action after the time-lock
    // delay has elapsed. Can be called by ANYONE — not just the proposer.
    //
    // ⚠️ The call runs with this contract as msg.sender, so it can
    //    invoke privileged functions on contracts that trust governance.
    // ================================================================
    function executeAction(uint256 actionId) external payable returns (bytes memory) {
        // Guard: action must exist, be unexecuted, and past the 2-day delay
        if (!_canBeExecuted(actionId)) {
            revert CannotExecute(actionId);
        }

        GovernanceAction storage actionToExecute = _actions[actionId];

        // Mark as executed BEFORE the external call (follows checks-effects-interactions)
        actionToExecute.executedAt = uint64(block.timestamp);

        emit ActionExecuted(actionId, msg.sender);

        // Execute the stored calldata against the target with optional ETH value
        // functionCallWithValue reverts if the call fails, propagating the error
        return actionToExecute.target.functionCallWithValue(
            actionToExecute.data,
            actionToExecute.value
        );
    }

    // ----------------------------------------------------------------
    // View / Pure Getters
    // ----------------------------------------------------------------

    // Returns the hardcoded 2-day delay constant
    function getActionDelay() external pure returns (uint256) {
        return ACTION_DELAY_IN_SECONDS;
    }

    // Returns the address of the bound voting token
    function getVotingToken() external view returns (address) {
        return address(_votingToken);
    }

    // Returns the full GovernanceAction struct for a given actionId
    function getAction(uint256 actionId) external view returns (GovernanceAction memory) {
        return _actions[actionId];
    }

    // Returns the next actionId that will be assigned (current counter value)
    function getActionCounter() external view returns (uint256) {
        return _actionCounter;
    }

    // ================================================================
    // _canBeExecuted() — internal time-lock + duplicate guard
    // ================================================================
    // An action is executable if ALL of the following are true:
    //   1. It was actually queued (proposedAt != 0)
    //   2. It has never been executed (executedAt == 0)
    //   3. At least ACTION_DELAY_IN_SECONDS have elapsed since queuing
    //
    // NOTE: unchecked subtraction is safe here — block.timestamp is always
    // >= proposedAt since proposedAt was set in a prior block.
    // ================================================================
    function _canBeExecuted(uint256 actionId) private view returns (bool) {
        GovernanceAction memory actionToExecute = _actions[actionId];

        // Action must exist (uninitialized structs have proposedAt == 0)
        if (actionToExecute.proposedAt == 0) return false;

        uint64 timeDelta;
        unchecked {
            // Safe: current timestamp always >= proposedAt
            timeDelta = uint64(block.timestamp) - actionToExecute.proposedAt;
        }

        // Must be unexecuted AND past the mandatory delay
        return actionToExecute.executedAt == 0 && timeDelta >= ACTION_DELAY_IN_SECONDS;
    }

    // ================================================================
    // _hasEnoughVotes() — >50% majority check
    // ================================================================
    // Uses ERC20Votes.getVotes() which returns the CURRENT delegated
    // voting power — not a historical snapshot.
    //
    // ⚠️ This is the flash loan vulnerability entry point:
    //   getVotes() reflects balances RIGHT NOW, so a flash-borrowed
    //   and self-delegated position satisfies this check instantly.
    // ================================================================
    function _hasEnoughVotes(address who) private view returns (bool) {
        uint256 balance        = _votingToken.getVotes(who);       // current delegated votes
        uint256 halfTotalSupply = _votingToken.totalSupply() / 2;  // 50% threshold
        return balance > halfTotalSupply;                           // strict majority required
    }
}
