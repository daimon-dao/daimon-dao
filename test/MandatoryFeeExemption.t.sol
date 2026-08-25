// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {StackDeployer} from "./base/StackDeployer.sol";
import {DaimonV2} from "../src/DaimonV2.sol";

/*
 * Finding #32: setExcludedFromFee() treated every exemption as a policy
 * choice. Two of them are not: removing Staking's would leave withdraw()
 * short of the principal it must return 1:1, and removing Migration's would
 * make claim() revert with AmountMismatch — freezing every migration while
 * the immutable deadline keeps running.
 */
contract MandatoryFeeExemptionTest is StackDeployer {
    address internal alice = address(0xA11CE);
    address internal bob = address(0xB0B);

    function setUp() public {
        deployStack();
    }

    function test_MandatoryFlagsAreSet() public view {
        assertTrue(token.mandatoryFeeExempt(address(migration)), "migration not flagged");
        assertTrue(token.mandatoryFeeExempt(address(staking)), "staking not flagged");
        assertEq(token.migrationContract(), address(migration), "migration address not recorded");

        // An ordinary exemption stays a free policy choice.
        assertFalse(token.mandatoryFeeExempt(alice), "an ordinary account is flagged");
    }

    // ---- Staking: locked while it holds principal ----

    function test_CannotRemoveStakingExemptionWhileStaked() public {
        fundWithDmn(alice, 1_000_000 ether);
        vm.startPrank(alice);
        token.approve(address(staking), 1_000_000 ether);
        uint256 lockId = staking.stake(1_000_000 ether, 0);
        vm.stopPrank();
        assertGt(staking.totalStakedAmount(), 0, "nothing staked");

        vm.prank(address(timelock));
        vm.expectRevert(DaimonV2.MandatoryFeeExemption.selector);
        token.setExcludedFromFee(address(staking), false);

        assertTrue(token.isExcludedFromFee(address(staking)), "exemption was removed anyway");

        // Once every stake is withdrawn the exemption becomes releasable.
        vm.warp(block.timestamp + 31 days);
        vm.prank(alice);
        staking.withdraw(lockId);
        assertEq(staking.totalStakedAmount(), 0, "stake not fully withdrawn");

        vm.prank(address(timelock));
        token.setExcludedFromFee(address(staking), false);
        assertFalse(token.isExcludedFromFee(address(staking)), "exemption not releasable when empty");
    }

    // ---- Migration: locked until the window closed AND the sweep ran ----

    function test_CannotRemoveMigrationExemptionBeforeDeadline() public {
        vm.prank(address(timelock));
        vm.expectRevert(DaimonV2.MandatoryFeeExemption.selector);
        token.setExcludedFromFee(address(migration), false);

        assertTrue(token.isExcludedFromFee(address(migration)), "exemption was removed anyway");
    }

    function test_CannotRemoveMigrationExemptionAfterDeadlineWithoutSweep() public {
        // Window closed, but the unclaimed DMN are still sitting there.
        vm.warp(migration.migrationDeadline() + 1);
        assertFalse(migration.sweepExecuted(), "sweep already done");

        vm.prank(address(timelock));
        vm.expectRevert(DaimonV2.MandatoryFeeExemption.selector);
        token.setExcludedFromFee(address(migration), false);
    }

    function test_MigrationExemptionReleasableAfterSweep() public {
        vm.warp(migration.migrationDeadline() + 1);
        vm.prank(address(timelock));
        migration.sweepUnclaimed();
        assertTrue(migration.sweepExecuted(), "sweep did not run");

        vm.prank(address(timelock));
        token.setExcludedFromFee(address(migration), false);
        assertFalse(token.isExcludedFromFee(address(migration)), "exemption not releasable after sweep");
    }

    // ---- Granting is never restricted ----

    function test_GrantingIsAlwaysAllowed() public {
        // Ordinary account: free both ways.
        vm.prank(address(timelock));
        token.setExcludedFromFee(alice, true);
        assertTrue(token.isExcludedFromFee(alice));

        vm.prank(address(timelock));
        token.setExcludedFromFee(alice, false);
        assertFalse(token.isExcludedFromFee(alice));

        // Re-granting a mandatory one is allowed even while it is locked.
        vm.prank(address(timelock));
        token.setExcludedFromFee(address(migration), true);
        assertTrue(token.isExcludedFromFee(address(migration)));
    }

    /// The guard is on the exemption, not on the caller: a non-governance
    /// account still cannot touch it at all.
    function test_StillGovernanceOnly() public {
        vm.prank(alice);
        vm.expectRevert();
        token.setExcludedFromFee(alice, true);
    }
}
