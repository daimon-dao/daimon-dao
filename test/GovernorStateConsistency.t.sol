// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {StackDeployer} from "./base/StackDeployer.sol";
import {DaimonV2} from "../src/DaimonV2.sol";
import {DaimonGovernor} from "../src/DaimonGovernor.sol";
import {DaimonTimelock} from "../src/DaimonTimelock.sol";

/*
 * Finding #26 (points 5 and 6) and #22.
 *
 * The Governor and the Timelock kept independent cancellation state and never
 * reconciled it: the Timelock could cancel an operation while the Governor
 * kept reporting the proposal as alive. state() also never returned Queued,
 * and an id that was never allocated resolved to an empty struct that read as
 * a perfectly normal Pending proposal (#22).
 */
contract GovernorStateConsistencyTest is StackDeployer {
    address internal whale = address(0xA11CE);

    function setUp() public {
        deployStack();
        fundWithDmn(whale, 3_000_000 ether);
        vm.startPrank(whale);
        token.approve(address(staking), 3_000_000 ether);
        staking.stake(3_000_000 ether, 3);
        vm.stopPrank();
        // #12 snapshots at block.number - 1: the stake must sit in a sealed
        // block before any proposal (same adjustment as the rest of the
        // governance suite).
        vm.roll(block.number + 1);
    }

    function _proposeAndPass() internal returns (uint256 id, bytes memory data) {
        data = abi.encodeWithSelector(DaimonV2.setFees.selector, uint256(10), uint256(10), uint256(20));
        vm.prank(whale);
        id = governor.propose(address(token), 0, data, "consistency");

        vm.warp(block.timestamp + governor.VOTING_DELAY() + 1);
        vm.prank(whale);
        governor.castVote(id, 1);
        vm.warp(block.timestamp + governor.VOTING_PERIOD() + 1);
    }

    // ---- #22: ids that were never allocated ----

    function test_StateRejectsNonExistentId() public {
        uint256 unallocated = governor.proposalCount();

        vm.expectRevert(DaimonGovernor.ProposalDoesNotExist.selector);
        governor.state(unallocated);

        vm.expectRevert(DaimonGovernor.ProposalDoesNotExist.selector);
        governor.state(type(uint256).max);
    }

    // ---- #26 point 5: Queued is actually reported ----

    function test_StateReportsQueued() public {
        (uint256 id,) = _proposeAndPass();
        assertEq(uint8(governor.state(id)), uint8(DaimonGovernor.ProposalState.Succeeded), "not Succeeded");

        governor.queue(id);
        assertEq(
            uint8(governor.state(id)),
            uint8(DaimonGovernor.ProposalState.Queued),
            "#26: a queued proposal still reads as Succeeded"
        );

        // And it is still executable once the delay has passed.
        vm.warp(block.timestamp + timelock.getMinDelay() + 1);
        governor.execute(id);
        assertEq(uint8(governor.state(id)), uint8(DaimonGovernor.ProposalState.Executed));
    }

    /// Succeeded-but-not-queued must still be refused with the precise error.
    function test_ExecuteBeforeQueueStillRejected() public {
        (uint256 id,) = _proposeAndPass();
        vm.expectRevert(DaimonGovernor.ProposalNotQueued.selector);
        governor.execute(id);
    }

    // ---- #26 point 5: the two contracts can no longer disagree ----

    function test_TimelockCancellationIsReflected() public {
        (uint256 id, bytes memory data) = _proposeAndPass();
        governor.queue(id);

        // Recompute the operation id the way the Governor schedules it.
        // 17 components since #37 appended quorumBpsSnapshot to the struct.
        (,,,,, uint256 snapshotBlock,,,,,,,,,, bytes32 salt,) = governor.proposals(id);
        snapshotBlock; // silence: only the salt is needed here
        bytes32 opId = timelock.hashOperation(address(token), 0, data, bytes32(0), salt);

        // The CANCELLER cancels directly on the Timelock, bypassing the Governor.
        vm.prank(guardian);
        timelock.cancel(opId);

        assertEq(
            uint8(governor.state(id)),
            uint8(DaimonGovernor.ProposalState.Canceled),
            "#26: the Governor kept reporting a live proposal for a cancelled operation"
        );

        // And it is no longer executable, with a coherent error.
        vm.warp(block.timestamp + timelock.getMinDelay() + 1);
        vm.expectRevert(DaimonGovernor.ProposalNotSucceeded.selector);
        governor.execute(id);
    }

    // ---- #26 point 6: no votes on a cancelled proposal ----

    function test_CannotVoteOnCancelledProposal() public {
        bytes memory data = abi.encodeWithSelector(DaimonV2.setFees.selector, uint256(10), uint256(10), uint256(20));
        vm.prank(whale);
        uint256 id = governor.propose(address(token), 0, data, "to be cancelled");

        vm.prank(guardian);
        governor.cancel(id);

        vm.warp(block.timestamp + governor.VOTING_DELAY() + 1);
        vm.prank(whale);
        vm.expectRevert(DaimonGovernor.ProposalIsCanceled.selector);
        governor.castVote(id, 1);

        // The tally stayed empty: nothing was counted for a dead proposal.
        (,,,,,,,,, uint256 forVotes, uint256 againstVotes, uint256 abstainVotes,,,,,) = governor.proposals(id);
        assertEq(forVotes + againstVotes + abstainVotes, 0, "votes counted on a cancelled proposal");
    }
}
