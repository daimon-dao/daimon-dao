// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {StackDeployer} from "./base/StackDeployer.sol";
import {DaimonV2} from "../src/DaimonV2.sol";
import {DaimonGovernor} from "../src/DaimonGovernor.sol";
import {DaimonTimelock} from "../src/DaimonTimelock.sol";
import {DaimonMigration} from "../src/DaimonMigration.sol";

/*
 * Findings #36 and #26 (points 1-3).
 *
 * Before the fix the same guardian address held three authorities of which
 * only ONE expired, and only half-way: pausing stopped at guardianExpiry but
 * an armed pause persisted forever, and both cancellation paths (Governor,
 * Timelock CANCELLER) never expired at all — a compromised guardian could
 * censor its own replacement indefinitely and preserve a global pause.
 *
 * After the fix:
 *  - a pause is a self-terminating WINDOW (max 14 days, clamped to
 *    guardianExpiry) that requires active renewal and lapses with no call;
 *  - one single expiry, replicated as an immutable in Governor and Timelock
 *    and asserted equal to the token's, kills BOTH cancellation paths;
 *  - after the expiry the governance pipeline is uncancellable by any single
 *    authority — the only remaining cancel is the Timelock's own self-call,
 *    i.e. an executed (majority, 13-day) governance proposal;
 *  - Governor.cancel() atomically cancels the queued Timelock operation
 *    (#26), reconciling with operations already canceled or executed
 *    directly;
 *  - pause seconds are credited to the migration deadline: censorship can
 *    no longer consume the immutable claim window.
 */
contract GuardianAuthorityExpiryTest is StackDeployer {
    address internal whale = address(0xA11CE);
    address internal alice = address(0xA1);
    address internal bob = address(0xB0B);
    address internal eve = address(0xE7E);
    address internal newGuardian = address(0x9E9);

    function setUp() public {
        deployStack();
        fundWithDmn(whale, 3_000_000 ether);
        vm.startPrank(whale);
        token.approve(address(staking), 3_000_000 ether);
        staking.stake(3_000_000 ether, 3);
        vm.stopPrank();
    }

    // ------------------------------------------------------------------
    // Governance-cycle helpers
    // ------------------------------------------------------------------

    function _propose(address target, bytes memory data, string memory desc) internal returns (uint256 id, bytes32 salt) {
        // The snapshot is block.number - 1 (#12): the setUp stake must sit
        // in a sealed block before the proposal for the whale to vote.
        vm.roll(block.number + 1);
        vm.prank(whale);
        id = governor.propose(target, 0, data, desc);
        // Mirrors propose(): the salt binds the id and the creation instant.
        salt = keccak256(abi.encode(id, block.timestamp));
    }

    function _passAndQueue(uint256 id) internal {
        vm.warp(block.timestamp + governor.VOTING_DELAY() + 1);
        vm.prank(whale);
        governor.castVote(id, 1);
        vm.warp(block.timestamp + governor.VOTING_PERIOD() + 1);
        governor.queue(id);
    }

    function _opId(address target, bytes memory data, bytes32 salt) internal view returns (bytes32) {
        return timelock.hashOperation(target, 0, data, bytes32(0), salt);
    }

    // ------------------------------------------------------------------
    // One expiry, three contracts
    // ------------------------------------------------------------------

    function test_ExpiryIsSingleAcrossAllThreeContracts() public view {
        assertEq(timelock.guardianAuthorityExpiry(), token.guardianExpiry(), "timelock expiry drifted");
        assertEq(governor.guardianAuthorityExpiry(), token.guardianExpiry(), "governor expiry drifted");
    }

    function test_ConstructorsRejectPastExpiry() public {
        vm.expectRevert("DaimonTimelock: expiry in the past");
        new DaimonTimelock(7 days, deployer, deployer, guardian, deployer, block.timestamp);
        vm.expectRevert("DaimonGovernor: expiry in the past");
        new DaimonGovernor(address(staking), address(timelock), guardian, 1000, 1000 ether, block.timestamp);
    }

    // ------------------------------------------------------------------
    // The pause is a window, not a latch
    // ------------------------------------------------------------------

    function test_PauseIsAFourteenDayWindow() public {
        fundWithDmn(alice, 10 ether);

        vm.prank(guardian);
        token.setPaused(true);
        assertTrue(token.isPaused());
        assertEq(token.pauseUntil(), block.timestamp + token.MAX_PAUSE_DURATION());

        vm.prank(alice);
        vm.expectRevert(DaimonV2.ContractIsPaused.selector);
        token.transfer(bob, 1 ether);

        // The window lapses ON ITS OWN: no unpause, no poke, and transfers
        // work again. The raw flag stays armed — interfaces read isPaused().
        vm.warp(block.timestamp + token.MAX_PAUSE_DURATION());
        assertFalse(token.isPaused());
        assertTrue(token.paused());
        vm.prank(alice);
        token.transfer(bob, 1 ether);
    }

    function test_RenewalExtendsWindowWithoutDoubleCredit() public {
        // Absolute literal anchors throughout: under via-ir the compiler may
        // legally re-read TIMESTAMP at each use site (it cannot change
        // intra-transaction in a real EVM), so a local captured before a
        // vm.warp silently observes the post-warp clock. Literals are immune.
        vm.warp(1000);
        vm.prank(guardian);
        token.setPaused(true);
        assertEq(token.pauseUntil(), 1000 + 14 days);
        assertEq(token.cumulativePauseSeconds(), 14 days);

        // Renewing half-way extends the window from NOW, and only the seconds
        // beyond the already-credited horizon are added to the counter.
        vm.warp(1000 + 7 days);
        vm.prank(guardian);
        token.setPaused(true);
        assertEq(token.pauseUntil(), 1000 + 21 days, "renewal did not extend");
        assertEq(token.cumulativePauseSeconds(), 21 days, "overlap was double-credited");
    }

    function test_EarlyUnpauseDoesNotClawBackCredit() public {
        vm.prank(guardian);
        token.setPaused(true);
        vm.warp(block.timestamp + 1 days);
        vm.prank(guardian);
        token.setPaused(false);

        assertFalse(token.isPaused());
        assertEq(token.pauseUntil(), 0);
        // The full scheduled window stays credited: the accounting error is
        // deliberately in the holders' favour.
        assertEq(token.cumulativePauseSeconds(), 14 days);
    }

    function test_PauseClampsToGuardianExpiry() public {
        uint256 expiry = token.guardianExpiry();
        vm.warp(expiry - 3 days);

        vm.prank(guardian);
        token.setPaused(true);
        assertEq(token.pauseUntil(), expiry, "window outlived the mandate");
        assertEq(token.cumulativePauseSeconds(), 3 days);

        vm.warp(expiry);
        assertFalse(token.isPaused(), "pause survived the expiry");
    }

    // ------------------------------------------------------------------
    // Atomic cross-cancel (#26 points 1-3)
    // ------------------------------------------------------------------

    function test_AtomicCancelAlsoCancelsTheQueuedOperation() public {
        bytes memory data = abi.encodeWithSelector(DaimonV2.setFees.selector, uint256(10), uint256(10), uint256(20));
        (uint256 id, bytes32 salt) = _propose(address(token), data, "fees");
        _passAndQueue(id);
        bytes32 opId = _opId(address(token), data, salt);

        vm.prank(guardian);
        governor.cancel(id);

        (, , bool opCanceled) = timelock.operations(opId);
        assertTrue(opCanceled, "timelock operation left scheduled");
        assertEq(uint8(governor.state(id)), uint8(DaimonGovernor.ProposalState.Canceled));
        vm.expectRevert(DaimonGovernor.ProposalNotSucceeded.selector);
        governor.execute(id);
    }

    function test_CancelConvergesWhenOperationAlreadyCanceledDirectly() public {
        bytes memory data = abi.encodeWithSelector(DaimonV2.setFees.selector, uint256(10), uint256(10), uint256(20));
        (uint256 id, bytes32 salt) = _propose(address(token), data, "fees");
        _passAndQueue(id);
        bytes32 opId = _opId(address(token), data, salt);

        // The guardian's kept independent path: cancel directly at the
        // Timelock first...
        vm.prank(guardian);
        timelock.cancel(opId);

        // ...then the Governor-side cancel must CONVERGE, not revert on the
        // Timelock's double-cancel guard.
        vm.prank(guardian);
        governor.cancel(id);
        assertEq(uint8(governor.state(id)), uint8(DaimonGovernor.ProposalState.Canceled));
    }

    function test_CancelRefusesWhenOperationExecutedDirectly() public {
        bytes memory data = abi.encodeWithSelector(DaimonV2.setFees.selector, uint256(10), uint256(10), uint256(20));
        (uint256 id, bytes32 salt) = _propose(address(token), data, "fees");
        _passAndQueue(id);
        bytes32 opId = _opId(address(token), data, salt);

        // The #26 scenario: governance later grants an ADDITIONAL executor,
        // which executes at the Timelock directly (the Governor's proposal
        // flags never learn about it). The role id is cached first: reading
        // it via an external call would consume the prank.
        bytes32 execRole = timelock.EXECUTOR_ROLE();
        vm.prank(address(timelock));
        timelock.grantRole(execRole, eve);
        vm.warp(block.timestamp + timelock.getMinDelay() + 1);
        vm.prank(eve);
        timelock.execute(address(token), 0, data, bytes32(0), salt);

        // The action already happened on-chain: reporting it canceled would
        // be the exact divergence the fix removes.
        vm.prank(guardian);
        vm.expectRevert(DaimonGovernor.AlreadyExecuted.selector);
        governor.cancel(id);
        (, bool opExecuted, ) = timelock.operations(opId);
        assertTrue(opExecuted);
    }

    // ------------------------------------------------------------------
    // The mandate really ends (#36)
    // ------------------------------------------------------------------

    function test_CompromisedGuardianCannotOutliveMandate() public {
        bytes memory data = abi.encodeWithSelector(DaimonGovernor.setGuardian.selector, newGuardian);

        // Within the mandate the guardian CAN censor its own replacement —
        // bounded, visible, and about to end.
        (uint256 id1, ) = _propose(address(governor), data, "replace guardian");
        vm.prank(guardian);
        governor.cancel(id1);
        assertEq(uint8(governor.state(id1)), uint8(DaimonGovernor.ProposalState.Canceled));

        // Last-second pause: the window clamps to the expiry...
        uint256 expiry = token.guardianExpiry();
        vm.warp(expiry - 1 days);
        vm.prank(guardian);
        token.setPaused(true);
        assertEq(token.pauseUntil(), expiry);

        // ...and past it the pause has lapsed with no cooperation needed.
        vm.warp(expiry + 1);
        assertFalse(token.isPaused());

        // The replacement pipeline is now uncancellable on BOTH contracts.
        (uint256 id2, bytes32 salt2) = _propose(address(governor), data, "replace guardian, take two");
        _passAndQueue(id2);
        bytes32 op2 = _opId(address(governor), data, salt2);

        vm.prank(guardian);
        vm.expectRevert(DaimonGovernor.GuardianAuthorityExpired.selector);
        governor.cancel(id2);

        vm.prank(guardian);
        vm.expectRevert(DaimonTimelock.GuardianAuthorityExpired.selector);
        timelock.cancel(op2);

        vm.warp(block.timestamp + timelock.getMinDelay() + 1);
        governor.execute(id2);
        assertEq(governor.guardian(), newGuardian, "recovery proposal did not land");
    }

    function test_GovernanceSelfCancelSurvivesExpiry() public {
        // Scheduled operations never expire (#24): after the guardian
        // mandate, the ONLY way to remove a queued-but-wrong operation is a
        // governance-voted cancel — a Timelock self-call, like updateDelay().
        vm.warp(token.guardianExpiry() + 1);

        bytes memory dataA = abi.encodeWithSelector(DaimonV2.setFees.selector, uint256(10), uint256(10), uint256(20));
        (uint256 idA, bytes32 saltA) = _propose(address(token), dataA, "target operation");
        _passAndQueue(idA);
        bytes32 opA = _opId(address(token), dataA, saltA);

        bytes memory dataB = abi.encodeWithSelector(DaimonTimelock.cancel.selector, opA);
        (uint256 idB, ) = _propose(address(timelock), dataB, "governance-voted cancel of A");
        _passAndQueue(idB);

        vm.warp(block.timestamp + timelock.getMinDelay() + 1);
        governor.execute(idB);

        (, , bool canceledA) = timelock.operations(opA);
        assertTrue(canceledA, "self-call cancel did not land");
        // The Governor reflects the Timelock-side cancellation (#26 pt.4-6)
        // and refuses execution at its own level.
        assertEq(uint8(governor.state(idA)), uint8(DaimonGovernor.ProposalState.Canceled));
        vm.expectRevert(DaimonGovernor.ProposalNotSucceeded.selector);
        governor.execute(idA);
    }

    // ------------------------------------------------------------------
    // Migration credit: censorship cannot consume the claim window
    // ------------------------------------------------------------------

    function test_PauseCreditExtendsMigrationWindow() public {
        // A dedicated short-window migration wired to the same token: the
        // stack's own migration has a 10-year window, far past the guardian
        // mandate, so the interplay needs a window inside it.
        DaimonMigration shortMigration =
            new DaimonMigration(address(oldToken), address(token), treasury, address(timelock), 40 days);
        vm.prank(address(timelock));
        token.setExcludedFromFee(address(shortMigration), true);
        fundWithDmn(address(this), 100 ether);
        token.transfer(address(shortMigration), 60 ether);
        vm.prank(deployer);
        oldToken.transfer(alice, 30 ether);

        uint256 deadline = shortMigration.migrationDeadline();

        // Sanity: an ordinary claim works.
        vm.startPrank(alice);
        oldToken.approve(address(shortMigration), 30 ether);
        shortMigration.claim(10 ether);
        vm.stopPrank();

        // The guardian pauses one day before the deadline: claims are
        // blocked (the outgoing DaimonV2 transfer reverts)...
        vm.warp(deadline - 1 days);
        vm.prank(guardian);
        token.setPaused(true);
        assertEq(shortMigration.effectiveMigrationDeadline(), deadline + 14 days);

        vm.prank(alice);
        vm.expectRevert(DaimonV2.ContractIsPaused.selector);
        shortMigration.claim(10 ether);

        // ...and once the window lapses, the blocked time has been credited:
        // this claim lands AFTER the immutable base deadline, and would have
        // been MigrationEnded before the fix.
        vm.warp(deadline + 13 days + 1 hours);
        assertFalse(token.isPaused());
        vm.prank(alice);
        shortMigration.claim(10 ether);

        // The sweep respects the SAME effective deadline...
        vm.prank(address(timelock));
        vm.expectRevert(DaimonMigration.MigrationStillOpen.selector);
        shortMigration.sweepUnclaimed();

        // ...and past it, the window truly closes and the sweep runs.
        vm.warp(deadline + 14 days + 1);
        vm.prank(alice);
        vm.expectRevert(DaimonMigration.MigrationEnded.selector);
        shortMigration.claim(10 ether);
        vm.prank(address(timelock));
        shortMigration.sweepUnclaimed();
    }
}
