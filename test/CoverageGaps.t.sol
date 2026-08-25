// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {StackDeployer} from "./base/StackDeployer.sol";
import {DaimonV2} from "../src/DaimonV2.sol";
import {DaimonStaking} from "../src/DaimonStaking.sol";
import {DaimonGovernor} from "../src/DaimonGovernor.sol";
import {DaimonTimelock} from "../src/DaimonTimelock.sol";

/*
 * Tests for critical paths not covered by the main suite, identified by the
 * coverage review: UUPS upgrade, allowance/transferFrom, the administrative
 * setters of Governor/Timelock and lock-option management.
 */
contract CoverageGaps is StackDeployer {
    address internal alice = address(0xA11CE);
    address internal bob = address(0xB0B);

    function setUp() public {
        deployStack();
    }

    // ============================================================
    // UUPS upgrade â€” the most sensitive path (upgradeability)
    // ============================================================
    function test_UpgradeOnlyByGovernance() public {
        DaimonV2 newImpl = new DaimonV2();

        // A random address cannot upgrade.
        vm.prank(alice);
        vm.expectRevert();
        token.upgradeToAndCall(address(newImpl), "");

        // Not even the guardian (it only has the pause).
        vm.prank(guardian);
        vm.expectRevert();
        token.upgradeToAndCall(address(newImpl), "");
    }

    function test_UpgradeViaGovernancePreservesState() public {
        // Pre-upgrade state
        uint256 supplyBefore = token.totalSupply();
        uint256 migBal = token.balanceOf(address(migration));

        DaimonV2 newImpl = new DaimonV2();

        // Only governance (Timelock) can authorize the upgrade.
        vm.prank(address(timelock));
        token.upgradeToAndCall(address(newImpl), "");

        // State preserved: supply, balances and roles unchanged.
        assertEq(token.totalSupply(), supplyBefore, "supply changed by the upgrade");
        assertEq(token.balanceOf(address(migration)), migBal, "balance changed by the upgrade");
        assertTrue(token.hasRole(token.GOVERNANCE_ROLE(), address(timelock)), "governance lost");
    }

    function test_UpgradeRejectsZeroImplementation() public {
        vm.prank(address(timelock));
        vm.expectRevert();
        token.upgradeToAndCall(address(0), "");
    }

    // ============================================================
    // ERC20 allowance / transferFrom
    // ============================================================
    function test_TransferFromConsumesAllowance() public {
        fundWithDmn(alice, 1_000_000 ether);

        vm.prank(alice);
        token.approve(bob, 100_000 ether);
        assertEq(token.allowance(alice, bob), 100_000 ether);

        vm.prank(bob);
        token.transferFrom(alice, bob, 40_000 ether);

        // The finite allowance drops by the amount spent.
        assertEq(token.allowance(alice, bob), 60_000 ether, "allowance not decremented");
    }

    function test_InfiniteAllowanceNotDecremented() public {
        fundWithDmn(alice, 1_000_000 ether);

        vm.prank(alice);
        token.approve(bob, type(uint256).max);

        vm.prank(bob);
        token.transferFrom(alice, bob, 50_000 ether);

        assertEq(token.allowance(alice, bob), type(uint256).max, "infinite allowance decremented");
    }

    function test_IncreaseAndDecreaseAllowance() public {
        vm.startPrank(alice);
        token.approve(bob, 100 ether);
        token.increaseAllowance(bob, 50 ether);
        assertEq(token.allowance(alice, bob), 150 ether);
        token.decreaseAllowance(bob, 120 ether);
        assertEq(token.allowance(alice, bob), 30 ether);
        vm.expectRevert("DaimonV2: allowance below zero");
        token.decreaseAllowance(bob, 100 ether);
        vm.stopPrank();
    }

    // ============================================================
    // Governor: timelock-only setters and guardian cancel
    // ============================================================
    function test_GovernorSettersOnlyTimelock() public {
        vm.prank(alice);
        vm.expectRevert("DaimonGovernor: only via timelock");
        governor.setQuorumBps(2000);

        vm.prank(address(timelock));
        governor.setQuorumBps(2000);
        assertEq(governor.quorumBps(), 2000);

        vm.prank(address(timelock));
        governor.setProposalThreshold(5000 ether);
        assertEq(governor.proposalThreshold(), 5000 ether);

        vm.prank(address(timelock));
        governor.setGuardian(bob);
        assertEq(governor.guardian(), bob);
    }

    function test_GovernorQuorumFloorEnforced() public {
        vm.prank(address(timelock));
        vm.expectRevert("DaimonGovernor: below MIN_QUORUM_BPS");
        governor.setQuorumBps(999); // below the 10% minimum
    }

    function test_GuardianCanCancelProposal() public {
        fundWithDmn(alice, 3_000_000 ether);
        vm.startPrank(alice);
        token.approve(address(staking), 3_000_000 ether);
        staking.stake(3_000_000 ether, 3);
        vm.stopPrank();

        bytes memory data = abi.encodeWithSelector(DaimonV2.setFees.selector, uint256(10), uint256(10), uint256(20));
        vm.prank(alice);
        uint256 id = governor.propose(address(token), 0, data, "x");

        vm.prank(guardian);
        governor.cancel(id);
        assertEq(uint8(governor.state(id)), uint8(DaimonGovernor.ProposalState.Canceled));

        // A non-guardian cannot cancel.
        vm.prank(alice);
        vm.expectRevert(DaimonGovernor.NotGuardian.selector);
        governor.cancel(id);
    }

    /// Finding #8: cancel() did not check that the proposal exists. The
    /// guardian could cancel an id not yet allocated; propose() never resets
    /// p.canceled, so that proposal would have been born already canceled â€”
    /// and the flag outlives the guardian that set it, since nothing clears
    /// it when the guardian is rotated or expires.
    function test_GuardianCannotPreCancelFutureProposal() public {
        uint256 futureId = governor.proposalCount(); // not allocated yet

        vm.prank(guardian);
        vm.expectRevert(DaimonGovernor.ProposalDoesNotExist.selector);
        governor.cancel(futureId);

        // That id can still be allocated normally, and is NOT born canceled.
        fundWithDmn(alice, 3_000_000 ether);
        vm.startPrank(alice);
        token.approve(address(staking), 3_000_000 ether);
        staking.stake(3_000_000 ether, 3);
        vm.stopPrank();

        bytes memory data = abi.encodeWithSelector(DaimonV2.setFees.selector, uint256(10), uint256(10), uint256(20));
        vm.prank(alice);
        uint256 id = governor.propose(address(token), 0, data, "not pre-canceled");
        assertEq(id, futureId, "unexpected proposal id");
        assertEq(
            uint8(governor.state(id)),
            uint8(DaimonGovernor.ProposalState.Pending),
            "proposal born canceled"
        );

        // A genuine cancel still works, and only once.
        vm.prank(guardian);
        governor.cancel(id);
        assertEq(uint8(governor.state(id)), uint8(DaimonGovernor.ProposalState.Canceled));

        vm.prank(guardian);
        vm.expectRevert(DaimonGovernor.ProposalAlreadyCanceled.selector);
        governor.cancel(id);
    }

    // ============================================================
    // Timelock: cancel del canceller (guardian) â€” finding #2
    // ============================================================

    /// Legitimate path: an operation actually scheduled through governance can
    /// be canceled by the CANCELLER, and only once.
    function test_TimelockCancellerCanCancelScheduledOperation() public {
        fundWithDmn(alice, 3_000_000 ether);
        vm.startPrank(alice);
        token.approve(address(staking), 3_000_000 ether);
        staking.stake(3_000_000 ether, 3);
        vm.stopPrank();
        // #12 snapshots at block.number - 1: the stake must sit in a sealed
        // block before the proposal (same adjustment as the rest of the
        // governance suite).
        vm.roll(block.number + 1);

        bytes memory data = abi.encodeWithSelector(DaimonV2.setFees.selector, uint256(10), uint256(10), uint256(20));

        // Literal timestamps: with via-ir, block.timestamp must not be
        // re-read after a vm.warp (same caution as in DaimonDAO.t.sol).
        uint256 tPropose = 1_000_000;
        vm.warp(tPropose);
        vm.prank(alice);
        uint256 id = governor.propose(address(token), 0, data, "cancellable");

        vm.warp(tPropose + governor.VOTING_DELAY() + 1);
        vm.prank(alice);
        governor.castVote(id, 1);

        vm.warp(tPropose + governor.VOTING_DELAY() + governor.VOTING_PERIOD() + 2);
        governor.queue(id);

        // Same salt the Governor derives in propose().
        bytes32 salt = keccak256(abi.encode(id, tPropose));
        bytes32 opId = timelock.hashOperation(address(token), 0, data, bytes32(0), salt);

        (uint256 readyBefore,,) = timelock.operations(opId);
        assertGt(readyBefore, 0, "operation was not scheduled");

        vm.prank(guardian);
        timelock.cancel(opId);
        (,, bool canceled) = timelock.operations(opId);
        assertTrue(canceled, "scheduled operation not canceled");

        // Canceling twice must revert: no duplicate Cancelled events.
        vm.prank(guardian);
        vm.expectRevert(DaimonTimelock.OperationAlreadyCanceled.selector);
        timelock.cancel(opId);
    }

    /// Finding #2: an unknown id resolves to an empty Operation. Before the
    /// fix it passed the executed check, was marked canceled and emitted
    /// Cancelled(id) for something that was never scheduled â€” and the stale
    /// canceled flag would have survived into a later schedule() of the same
    /// id, which does not reset it. It must revert and write nothing.
    function test_TimelockCancelRevertsOnUnknownId() public {
        bytes32 unknownId = keccak256("never-scheduled");

        // The role check still comes first.
        vm.prank(alice);
        vm.expectRevert();
        timelock.cancel(unknownId);

        vm.prank(guardian);
        vm.expectRevert(DaimonTimelock.OperationNotScheduled.selector);
        timelock.cancel(unknownId);

        (uint256 ready, bool executed, bool canceled) = timelock.operations(unknownId);
        assertEq(ready, 0, "phantom readyTimestamp");
        assertFalse(executed, "phantom executed flag");
        assertFalse(canceled, "phantom canceled flag");
    }

    /// Finding #18: governance privilege changes on the staking contract were
    /// silent. The mapping is private and not enumerable, so without an event
    /// a monitor can neither subscribe to changes nor reconstruct the current
    /// set of holders.
    function test_GovernanceChangesEmitEvent() public {
        // Granting emits.
        vm.expectEmit(true, false, false, true, address(staking));
        emit DaimonStaking.GovernanceSet(bob, true);
        vm.prank(address(timelock));
        staking.setGovernance(bob, true);
        assertTrue(staking.isGovernance(bob));

        // Revoking emits.
        vm.expectEmit(true, false, false, true, address(staking));
        emit DaimonStaking.GovernanceSet(bob, false);
        vm.prank(address(timelock));
        staking.setGovernance(bob, false);
        assertFalse(staking.isGovernance(bob));
    }

    /// A write that does not change the value must stay silent, so every
    /// emitted event is a real transition.
    function test_GovernanceNoOpEmitsNothing() public {
        // bob is not governance: setting false again changes nothing.
        vm.recordLogs();
        vm.prank(address(timelock));
        staking.setGovernance(bob, false);
        assertEq(vm.getRecordedLogs().length, 0, "no-op revoke emitted an event");

        // timelock is already governance: setting true again changes nothing.
        assertTrue(staking.isGovernance(address(timelock)));
        vm.recordLogs();
        vm.prank(address(timelock));
        staking.setGovernance(address(timelock), true);
        assertEq(vm.getRecordedLogs().length, 0, "no-op grant emitted an event");
    }

    // ============================================================
    // Staking: lock-option management (governance)
    // ============================================================
    function test_AddAndDisableLockOption() public {
        uint256 nBefore = staking.lockOptionsLength();

        vm.prank(address(timelock));
        staking.addLockOption(730 days, 8000); // 2 years, 8x
        assertEq(staking.lockOptionsLength(), nBefore + 1);

        (uint256 dur, uint256 mult, bool active) = staking.lockOptions(nBefore);
        assertEq(dur, 730 days);
        assertEq(mult, 8000);
        assertTrue(active);

        vm.prank(address(timelock));
        staking.disableLockOption(nBefore);
        (,, bool activeAfter) = staking.lockOptions(nBefore);
        assertFalse(activeAfter);

        // A non-governance address cannot add options.
        vm.prank(alice);
        vm.expectRevert(DaimonStaking.NotGovernance.selector);
        staking.addLockOption(1 days, 1000);
    }

    // ============================================================
    // Token: parametric setters with bounds
    // ============================================================
    function test_ParametricSettersBounds() public {
        vm.startPrank(address(timelock));

        staking; // silence
        token.setStakingRewardShareBps(1000);
        assertEq(token.stakingRewardShareBps(), 1000);
        vm.expectRevert("DaimonV2: bps > 100%");
        token.setStakingRewardShareBps(1001);

        vm.expectRevert("DaimonV2: maxTx too low");
        token.setMaxTxAmount(1); // below 0.01% of the supply

        token.setBuyBackUpperLimit(10 ether);
        assertEq(token.buyBackUpperLimit(), 10 ether);

        vm.stopPrank();
    }

    // ============================================================
    // Migration: post-deadline sweep to the treasury
    // ============================================================
    function test_SweepSendsRemainderToTreasury() public {
        vm.warp(block.timestamp + 366 days); // oltre la deadline (365 giorni)
        uint256 remaining = token.balanceOf(address(migration));
        uint256 treasuryBefore = token.balanceOf(treasury);

        vm.prank(address(timelock));
        migration.sweepUnclaimed();

        assertEq(token.balanceOf(address(migration)), 0, "migration not emptied");
        assertEq(token.balanceOf(treasury), treasuryBefore + remaining, "treasury did not receive the remainder");
    }
}
