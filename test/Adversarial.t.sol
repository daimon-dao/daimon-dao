// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {StackDeployer} from "./base/StackDeployer.sol";
import {DaimonV2} from "../src/DaimonV2.sol";
import {DaimonGovernor} from "../src/DaimonGovernor.sol";

/*
 * Targeted pre-freeze adversarial round (what adds value beyond the audit):
 *  1. snapshot/whale: vp acquired after the snapshot does not count
 *  2. boundary values
 *  3. perverse incentives (game theory on the tokenomics)
 *  4. reflection edge cases + wei-level accounting coherence
 */
contract AdversarialTest is StackDeployer {
    // enum ProposalState { Pending, Active, Defeated, Succeeded, Queued, Executed, Canceled }
    uint8 constant DEFEATED = 2;
    uint8 constant SUCCEEDED = 3;
    uint8 constant EXECUTED = 5;

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

    function _state(uint256 id) internal view returns (uint8) {
        return uint8(governor.state(id));
    }

    // ============================================================
    // AREA 1 — SNAPSHOT / WHALE
    // ============================================================

    /// vp acquired at a timestamp STRICTLY after the snapshot
    /// does not count for that proposal.
    function test_A1_vpAfterSnapshotDoesNotCount() public {
        address ally = address(0xA11);
        address whale = address(0xBAD);

        vm.warp(1_000_000);
        _stake(ally, 1_000_000 ether, 0); // vp before the proposal, cp @1_000_000

        uint256 tSnap = 2_000_000;
        vm.warp(tSnap);
        vm.prank(ally);
        uint256 id = governor.propose(address(token), 0, "", "p"); // snapshot @2_000_000

        // the whale stakes LATER, at a strictly subsequent timestamp
        vm.warp(tSnap + 100);
        _stake(whale, 500_000_000 ether, 3); // huge 4x vp, but late, cp @2_000_100

        assertEq(staking.votingPowerAt(whale, tSnap), 0, "whale vp leaked into the snapshot");
        assertGt(staking.votingPowerAt(ally, tSnap), 0, "ally vp missing");

        // voting open: the whale cannot vote, the ally can
        vm.warp(tSnap + governor.VOTING_DELAY());
        vm.prank(whale);
        vm.expectRevert(DaimonGovernor.InsufficientVotingPower.selector);
        governor.castVote(id, 1);

        vm.prank(ally);
        governor.castVote(id, 1); // ok
    }

    /// Documented nuance: staking at the SAME timestamp as the snapshot counts.
    /// It requires the same block as the creation, though (block timestamps on
    /// BSC/EVM are strictly increasing): anyone REACTING to an already-mined
    /// proposal is always in a later block → excluded. Not exploitable.
    function test_A1_sameTimestampStakeCounts_sameBlockOnly() public {
        address u = address(0xC0);
        _stake(u, 1000 ether, 0);
        vm.warp(block.timestamp + 1 days);
        uint256 tSnap = block.timestamp;
        vm.prank(u); // vp needed to propose
        governor.propose(address(token), 0, "", "p");
        // same timestamp, "after" within the same transaction-block
        _stake(u, 1000 ether, 0);
        assertGt(staking.votingPowerAt(u, tSnap), 1000 ether, "same-ts stake should count");
    }

    // ============================================================
    // AREA 2 — BOUNDARY VALUES
    // ============================================================

    function test_A2_stakeOneWei() public {
        address u = address(0x11);
        _stake(u, 1, 0); // opt 0 = 1.0x
        assertEq(staking.votingPower(u), 1, "wrong 1-wei vp");
    }

    /// maxTx boundary: the per-transaction cap is maxTxAmount (0.5% of the
    /// initial supply = 5B DMN). Staking exactly maxTxAmount passes;
    /// maxTxAmount+1 in one shot reverts. "Staking the whole supply" is not
    /// possible in a single tx (by anti-dump design), it must be split.
    function test_A2_stakeMaxTxBoundary() public {
        uint256 mtx = token.maxTxAmount();
        address u = address(0x12);
        fundWithDmn(u, mtx + 1000); // the migration is exempt from maxTx: the user can hold > maxTx
        vm.startPrank(u);
        token.approve(address(staking), type(uint256).max);
        staking.stake(mtx, 3); // amount == maxTx → ok
        assertEq(staking.votingPower(u), mtx * 4000 / 1000, "wrong vp at the maxTx cap");
        vm.expectRevert(DaimonV2.TransferAmountExceedsMaxTx.selector);
        staking.stake(mtx + 1, 3); // amount > maxTx → reverts
        vm.stopPrank();
    }

    function test_A2_migrationClaimZeroReverts() public {
        vm.prank(address(0x13));
        vm.expectRevert(); // ZeroAmount
        migration.claim(0);
    }

    function test_A2_migrationClaimOneWei() public {
        address u = address(0x14);
        fundWithDmn(u, 1); // 1-wei claim through the helper
        assertEq(token.balanceOf(u), 1, "1-wei claim not 1:1");
    }

    function test_A2_burnToExactFloor_neverBelow() public {
        // Make the dead address hold enough to cover the whole burnable amount,
        // then verify that _tTotal lands EXACTLY on MIN_SUPPLY.
        uint256 burnable = token.INITIAL_SUPPLY() - token.MIN_SUPPLY();
        // send 'burnable' to the dead address (the deployer is not excluded from
        // reward but received the whole supply in the migration; we use the migration).
        vm.prank(address(migration));
        token.transfer(address(0xdEaD), burnable); // dead is excluded: receives net? migration is fee-exempt → no fee
        // dead now holds ~burnable; burn down to the floor
        token.burnDeadBalanceToFloor();
        assertEq(token.totalSupply(), token.MIN_SUPPLY(), "supply did not land on the exact floor");
        // further burn: no-op, never below the floor
        token.burnDeadBalanceToFloor();
        assertEq(token.totalSupply(), token.MIN_SUPPLY(), "supply dropped below the floor");
    }

    function test_A2_timelockExecute_readyMinusOne_vs_exact() public {
        // proposal that passes on its own, then the timelock boundary at execute
        address p = address(0x15);
        _stake(p, 2_000_000 ether, 0);
        vm.warp(block.timestamp + 1 days);

        bytes memory data = abi.encodeCall(DaimonV2.setFees, (10, 10, 20));
        vm.prank(p);
        uint256 id = governor.propose(address(token), 0, data, "setFees");

        vm.warp(block.timestamp + governor.VOTING_DELAY());
        vm.prank(p);
        governor.castVote(id, 1);
        vm.warp(block.timestamp + governor.VOTING_PERIOD() + 1);
        assertEq(_state(id), SUCCEEDED, "not Succeeded");

        governor.queue(id);
        uint256 ready = block.timestamp + timelock.getMinDelay();

        // ready - 1: TooEarly (reverts)
        vm.warp(ready - 1);
        vm.expectRevert();
        governor.execute(id);

        // exact ready: passes
        vm.warp(ready);
        governor.execute(id);
        assertEq(_state(id), EXECUTED, "not Executed at exact ready");
    }

    // ============================================================
    // AREA 3 — PERVERSE INCENTIVES (game theory)
    // ============================================================

    // Shared scenario: proposer 8, opponent 4, non-voting crowd 88.
    // Total vp = 100, quorum 10%. The proposer's for (8) alone does NOT
    // reach quorum (10).
    function _quorumScenario() internal returns (uint256 id, address opp) {
        address proposer = address(0x100);
        opp = address(0x200);
        address crowd = address(0x300);
        _stake(proposer, 8_000_000 ether, 0);
        _stake(opp, 4_000_000 ether, 0);
        _stake(crowd, 88_000_000 ether, 0); // will never vote
        vm.warp(block.timestamp + 1 days);
        vm.prank(proposer);
        id = governor.propose(address(token), 0, "", "quorum-game");
        vm.warp(block.timestamp + governor.VOTING_DELAY());
        vm.prank(proposer);
        governor.castVote(id, 1); // for = 8 < quorum 10
    }

    /// FIX Finding 1: against votes NO LONGER count toward quorum (for+abstain,
    /// like OZ). Same scenario (for 8% < quorum 10%, against 4%): now voting
    /// against does NOT push the proposal to quorum → Defeated. This is the
    /// CORRECT behavior — the perverse asymmetry is eliminated.
    function test_A3_againstVoteDoesNotSatisfyQuorum() public {
        (uint256 id, address opp) = _quorumScenario();
        vm.prank(opp);
        governor.castVote(id, 0); // against = 4, EXCLUDED from quorum
        vm.warp(block.timestamp + governor.VOTING_PERIOD() + 1);
        assertEq(_state(id), DEFEATED, "against must no longer reach quorum");
    }

    /// Counterpoint: staying silent → identical outcome (Defeated). After the
    /// fix, voting against and not voting give the SAME result: no perverse
    /// incentive to stay silent instead of opposing.
    function test_A3_silenceDeniesQuorumDefeats() public {
        (uint256 id, ) = _quorumScenario();
        vm.warp(block.timestamp + governor.VOTING_PERIOD() + 1);
        assertEq(_state(id), DEFEATED, "silence must defeat");
    }

    /// Abstain, however, still counts toward quorum (like OZ): the fix excludes
    /// ONLY against. for 8% + abstain 4% = 12% >= 10% → Succeeded.
    function test_A3_abstainCountsTowardQuorum() public {
        (uint256 id, address opp) = _quorumScenario();
        vm.prank(opp);
        governor.castVote(id, 2); // abstain = 4 → for+abstain = 12 >= 10
        vm.warp(block.timestamp + governor.VOTING_PERIOD() + 1);
        assertEq(_state(id), SUCCEEDED, "abstain must count toward quorum");
    }

    /// Voting power does NOT decay: after the lock expires it stays full
    /// (with multiplier) until withdraw. Rational strategy: never withdraw →
    /// keep voting weight + reward share without a lock.
    function test_A3_votingPowerDoesNotDecayAfterUnlock() public {
        address u = address(0x400);
        uint256 lockId = _stake(u, 1_000_000 ether, 3); // 4x, 365 days
        uint256 vpBefore = staking.votingPower(u);
        assertEq(vpBefore, 1_000_000 ether * 4, "initial vp");
        // well past the lock expiry
        vm.warp(block.timestamp + 400 days);
        assertEq(staking.votingPower(u), vpBefore, "vp decayed after unlock (it should stay full)");
        // and it stays full until withdraw
        vm.prank(u);
        staking.withdraw(lockId);
        assertEq(staking.votingPower(u), 0, "vp not zeroed after withdraw");
    }

    // ============================================================
    // AREA 4 — REFLECTION EDGE + WEI-LEVEL COHERENCE
    // ============================================================

    /// Conservation: the sum of all holder balances stays <= totalSupply and
    /// matches it up to dust (integer truncation), even after a taxed transfer.
    function test_A4_reflectionConservation() public {
        address a = address(0x51);
        address b = address(0x52);
        fundWithDmn(a, 10_000_000 ether);

        uint256 sumBefore = _sumKnown(a, b);
        assertLe(sumBefore, token.totalSupply(), "sum > supply (before)");
        assertLt(token.totalSupply() - sumBefore, 1000, "excessive dust (before)");

        // taxed transfer a→b (neither one is fee-excluded)
        vm.prank(a);
        token.transfer(b, 1_000_000 ether);

        uint256 sumAfter = _sumKnown(a, b);
        assertLe(sumAfter, token.totalSupply(), "sum > supply (after)");
        assertLt(token.totalSupply() - sumAfter, 1000, "excessive dust (after)");

        // the net to the recipient is <= 96% (4% fee), and a passive holder
        // (the migration) has earned reflection from the 1% tax.
        assertGt(token.balanceOf(b), 0, "b received nothing");
    }

    /// The dead address (the only one excluded from reward) uses the _tOwned
    /// path and the accounting stays coherent after a burn down to the floor.
    function test_A4_deadExcludedAccountingCoherent() public {
        vm.prank(address(migration));
        token.transfer(address(0xdEaD), 5_000_000 ether);
        uint256 deadBal = token.balanceOf(address(0xdEaD));
        assertEq(deadBal, 5_000_000 ether, "dead does not reflect the net sent (excluded from reward)");

        uint256 supplyBefore = token.totalSupply();
        token.burnDeadBalanceToFloor();
        // burned exactly the dead balance (< burnable), supply drops by the same
        assertEq(token.totalSupply(), supplyBefore - 5_000_000 ether, "dead burn != dead balance");
        assertEq(token.balanceOf(address(0xdEaD)), 0, "dead not zeroed");
    }

    function _sumKnown(address a, address b) internal view returns (uint256) {
        return token.balanceOf(address(migration)) +
            token.balanceOf(address(token)) +
            token.balanceOf(address(staking)) +
            token.balanceOf(address(0xdEaD)) +
            token.balanceOf(marketingWallet) +
            token.balanceOf(a) +
            token.balanceOf(b);
    }
}
