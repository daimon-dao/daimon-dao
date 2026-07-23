// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {StackDeployer} from "../base/StackDeployer.sol";
import {DaimonV2} from "../../src/DaimonV2.sol";
import {DaimonGovernor} from "../../src/DaimonGovernor.sol";

/*
 * Verifies that NO shortcut sequence takes a proposal to execution while
 * skipping quorum, queue or the timelock delay. Every "out of order" attempt
 * must revert; only the complete path actually executes.
 */
contract GovernanceSequence is StackDeployer {
    address internal whale = address(0xA11CE);

    function setUp() public {
        deployStack();
        // whale: high but not total voting power, to be able to distinguish quorum
        fundWithDmn(whale, 3_000_000 ether);
        vm.startPrank(whale);
        token.approve(address(staking), 3_000_000 ether);
        staking.stake(3_000_000 ether, 3);
        vm.stopPrank();
    }

    function _propose() internal returns (uint256 id, bytes memory data) {
        data = abi.encodeWithSelector(DaimonV2.setFees.selector, uint256(10), uint256(10), uint256(20));
        vm.prank(whale);
        id = governor.propose(address(token), 0, data, "Fee reduction");
    }

    function test_CannotExecuteBeforeVoting() public {
        (uint256 id,) = _propose();
        vm.expectRevert(DaimonGovernor.ProposalNotSucceeded.selector);
        governor.execute(id);
    }

    function test_CannotQueueBeforeSucceeded() public {
        (uint256 id,) = _propose();
        vm.warp(block.timestamp + governor.VOTING_DELAY() + 1);
        vm.prank(whale);
        governor.castVote(id, 1);
        // still voting: queue must fail
        vm.expectRevert(DaimonGovernor.ProposalNotSucceeded.selector);
        governor.queue(id);
    }

    function test_CannotExecuteWithoutQueue() public {
        (uint256 id,) = _propose();
        vm.warp(block.timestamp + governor.VOTING_DELAY() + 1);
        vm.prank(whale);
        governor.castVote(id, 1);
        vm.warp(block.timestamp + governor.VOTING_PERIOD() + 1);
        assertEq(uint8(governor.state(id)), uint8(DaimonGovernor.ProposalState.Succeeded));
        // Succeeded but not queued.
        vm.expectRevert(DaimonGovernor.ProposalNotQueued.selector);
        governor.execute(id);
    }

    function test_CannotExecuteDuringTimelock() public {
        (uint256 id,) = _propose();
        vm.warp(block.timestamp + governor.VOTING_DELAY() + 1);
        vm.prank(whale);
        governor.castVote(id, 1);
        vm.warp(block.timestamp + governor.VOTING_PERIOD() + 1);
        governor.queue(id);
        // Timelock delay not yet elapsed.
        vm.expectRevert();
        governor.execute(id);
    }

    function test_DefeatedProposalCannotBeQueuedOrExecuted() public {
        // whale votes AGAINST: the proposal is defeated, never executable.
        (uint256 id,) = _propose();
        vm.warp(block.timestamp + governor.VOTING_DELAY() + 1);
        vm.prank(whale);
        governor.castVote(id, 0);
        vm.warp(block.timestamp + governor.VOTING_PERIOD() + 1);
        assertEq(uint8(governor.state(id)), uint8(DaimonGovernor.ProposalState.Defeated));
        vm.expectRevert(DaimonGovernor.ProposalNotSucceeded.selector);
        governor.queue(id);
        vm.expectRevert(DaimonGovernor.ProposalNotSucceeded.selector);
        governor.execute(id);
    }

    function test_HappyPathExecutesAndAppliesEffect() public {
        (uint256 id,) = _propose();
        vm.warp(block.timestamp + governor.VOTING_DELAY() + 1);
        vm.prank(whale);
        governor.castVote(id, 1);
        vm.warp(block.timestamp + governor.VOTING_PERIOD() + 1);
        governor.queue(id);
        vm.warp(block.timestamp + timelock.getMinDelay() + 1);
        governor.execute(id);
        assertEq(token.taxFee(), 10);
        assertEq(token.buybackFee(), 10);
        assertEq(token.marketingFee(), 20);
    }
}
