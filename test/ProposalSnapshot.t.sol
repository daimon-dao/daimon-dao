// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {StackDeployer} from "./base/StackDeployer.sol";
import {DaimonGovernor} from "../src/DaimonGovernor.sol";

/*
 * Findings #12 (Critical) and #37.
 *
 * #12 - the proposal snapshot moves to BLOCK NUMBERS, taken at
 * block.number - 1: a sealed block whose checkpoints can never be rewritten.
 * Voting power staked in the proposal's own block (or later) counts for
 * nothing - not as voter weight, not in the quorum denominator. The
 * end-to-end attack reproduction lives in AuditFindings.t.sol
 * (test_Finding12_sameBlockStakeMustNotCountAtSnapshot); here we pin down
 * the mechanics it relies on.
 *
 * #37 - the quorum bps is captured per proposal at creation: a quorum
 * change enacted while a proposal is in flight does not retroactively move
 * the bar that proposal is judged against.
 *
 * Block numbers are LITERALS throughout: the same via-ir caution documented
 * for timestamps applies - never derive from block.number a value that is
 * reused after a vm.roll.
 */
contract ProposalSnapshotTest is StackDeployer {
    address internal ally = address(0xA11);
    address internal attacker = address(0xBAD);

    function setUp() public {
        deployStack();
    }

    function _stake(address who, uint256 amount, uint256 opt) internal returns (uint256 lockId) {
        fundWithDmn(who, amount);
        vm.startPrank(who);
        token.approve(address(staking), amount);
        lockId = staking.stake(amount, opt);
        vm.stopPrank();
    }

    // ---- Aggregate checkpoint history (the piece #12's fix rests on) ----

    function test_TotalVotingPowerHistoryIsQueryable() public {
        vm.roll(10);
        vm.warp(1_000_000);
        uint256 firstLock = _stake(ally, 1000 ether, 0); // total 1000, cp @ block 10

        vm.roll(20);
        _stake(attacker, 3000 ether, 0); // total 4000, cp @ block 20

        vm.roll(30);
        _stake(ally, 500 ether, 0); // total 4500, cp @ block 30
        // Same-block update: overwrites the last entry instead of growing
        // the array. Safe now - block 30 can only become a snapshot once it
        // is sealed, and then nothing writes to it anymore.
        assertEq(staking.totalCheckpointCount(), 3, "checkpoint array grew on same-block update?");
        _stake(attacker, 500 ether, 0); // still block 30, total 5000
        assertEq(staking.totalCheckpointCount(), 3, "same-block update must overwrite");

        vm.roll(40);
        vm.warp(1_000_000 + 31 days); // lock expiry stays on wall-clock time
        vm.prank(ally);
        staking.withdraw(firstLock); // total 4000, cp @ block 40

        // Binary search across the whole history, boundaries included.
        assertEq(staking.totalVotingPowerAt(9), 0, "before any checkpoint");
        assertEq(staking.totalVotingPowerAt(10), 1000 ether, "at first checkpoint");
        assertEq(staking.totalVotingPowerAt(15), 1000 ether, "between 10 and 20");
        assertEq(staking.totalVotingPowerAt(20), 4000 ether, "at second checkpoint");
        assertEq(staking.totalVotingPowerAt(29), 4000 ether, "just before 30");
        assertEq(staking.totalVotingPowerAt(30), 5000 ether, "overwritten same-block value");
        assertEq(staking.totalVotingPowerAt(40), 4000 ether, "after withdraw");

        // Per-account history stays coherent with the aggregate.
        assertEq(staking.votingPowerAt(ally, 29), 1000 ether);
        assertEq(staking.votingPowerAt(ally, 30), 1500 ether);
        assertEq(staking.votingPowerAt(ally, 40), 500 ether);
    }

    // ---- #12: the quorum DENOMINATOR is immune to same-block stakes ----

    /// A stake landing in the proposal's own block, even BEFORE the propose
    /// call, must not inflate the electorate the quorum is computed on.
    /// Live total here is 100_000; the snapshot total must be 5_000.
    function test_QuorumDenominatorExcludesSameBlockStake() public {
        vm.roll(100);
        _stake(ally, 5_000 ether, 0); // the only voting power in a sealed block

        fundWithDmn(attacker, 95_000 ether);
        vm.roll(101);
        vm.startPrank(attacker);
        token.approve(address(staking), 95_000 ether);
        staking.stake(95_000 ether, 0); // same block as the propose below
        uint256 id = governor.propose(address(token), 0, "", "p");
        vm.stopPrank();

        (,,,,, uint256 snapBlock, uint256 snapTotal,,,,,,,,,,) = governor.proposals(id);
        assertEq(snapBlock, 100, "snapshot must be the previous block");
        assertEq(snapTotal, 5_000 ether, "same-block stake leaked into the quorum denominator");

        // The attacker holds 95% of the LIVE power and still cannot vote.
        vm.warp(block.timestamp + governor.VOTING_DELAY() + 1);
        vm.prank(attacker);
        vm.expectRevert(DaimonGovernor.InsufficientVotingPower.selector);
        governor.castVote(id, 1);

        // The pre-existing electorate alone decides: 5_000 for, quorum
        // needed 10% of 5_000 = 500. Had the denominator used the live
        // 100_000, the bar would be 10_000 and this proposal Defeated.
        vm.prank(ally);
        governor.castVote(id, 1);
        vm.warp(block.timestamp + governor.VOTING_PERIOD() + 1);
        assertEq(
            uint8(governor.state(id)),
            uint8(DaimonGovernor.ProposalState.Succeeded),
            "#12: quorum denominator counted power staked in the proposal's block"
        );
    }

    // ---- #37: quorum bps snapshotted per proposal ----

    /// 15% of the electorate votes for. Under the 10% quorum at creation the
    /// proposal passes; under the 30% enacted mid-flight it would not. The
    /// in-flight proposal must be judged by the bar it was created under,
    /// and only the later proposal by the new one.
    function test_QuorumBpsChangeDoesNotMoveInFlightBar() public {
        vm.roll(100);
        _stake(ally, 15_000 ether, 0);     // will vote
        _stake(attacker, 85_000 ether, 0); // never votes
        vm.roll(101);

        vm.prank(ally);
        uint256 p0 = governor.propose(address(token), 0, "", "before the change");
        (,,,,,,,,,,,,,,,, uint256 p0Bps) = governor.proposals(p0);
        assertEq(p0Bps, 1000, "bps at creation not captured");

        // Governance raises the quorum while p0 is in flight.
        vm.prank(address(timelock));
        governor.setQuorumBps(3000);

        vm.warp(block.timestamp + governor.VOTING_DELAY() + 1);
        vm.prank(ally);
        governor.castVote(p0, 1); // 15_000 of 100_000 = 15%

        vm.prank(ally);
        uint256 p1 = governor.propose(address(token), 0, "", "after the change");
        (,,,,,,,,,,,,,,,, uint256 p1Bps) = governor.proposals(p1);
        assertEq(p1Bps, 3000, "new proposal must take the new bps");

        vm.warp(block.timestamp + governor.VOTING_DELAY() + 1);
        vm.prank(ally);
        governor.castVote(p1, 1); // same 15%

        vm.warp(block.timestamp + governor.VOTING_PERIOD() + 1);
        assertEq(
            uint8(governor.state(p0)),
            uint8(DaimonGovernor.ProposalState.Succeeded),
            "#37: the mid-flight quorum change moved p0's bar"
        );
        assertEq(
            uint8(governor.state(p1)),
            uint8(DaimonGovernor.ProposalState.Defeated),
            "p1 must be judged by the new quorum"
        );
    }

    // ---- Edge: proposal born before any sealed voting power ----

    /// Live threshold lets "stake then propose in one block" through, but
    /// the snapshot electorate is empty: nobody can vote (every weight is 0
    /// at the snapshot) and forVotes <= againstVotes defeats it. A proposal
    /// created from nothing can never pass.
    function test_EmptyElectorateProposalIsDefeated() public {
        address u = address(0xC0);
        fundWithDmn(u, 1000 ether);
        vm.startPrank(u);
        token.approve(address(staking), 1000 ether);
        staking.stake(1000 ether, 0); // meets the live threshold...
        uint256 id = governor.propose(address(token), 0, "", "from nothing"); // ...in the same block
        vm.stopPrank();

        vm.warp(block.timestamp + governor.VOTING_DELAY() + 1);
        vm.prank(u);
        vm.expectRevert(DaimonGovernor.InsufficientVotingPower.selector);
        governor.castVote(id, 1);

        vm.warp(block.timestamp + governor.VOTING_PERIOD() + 1);
        assertEq(
            uint8(governor.state(id)),
            uint8(DaimonGovernor.ProposalState.Defeated),
            "a proposal with an empty snapshot electorate must be Defeated"
        );
    }
}
