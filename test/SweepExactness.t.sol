// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {StackDeployer} from "./base/StackDeployer.sol";
import {DaimonMigration} from "../src/DaimonMigration.sol";

/*
 * Finding #11: claim() protected the 1:1 ratio with balance-before/after
 * checks on both legs, but sweepUnclaimed() only read transfer()'s boolean.
 *
 * If the migration's fee exemption had been revoked, the sweep would have
 * SUCCEEDED while the treasury received less than the full remainder — and
 * sweepExecuted stays true, so the recovery could never be repeated after
 * fixing the configuration. A single silent shortfall would close the
 * recovery path for good.
 */
contract SweepExactnessTest is StackDeployer {
    function setUp() public {
        deployStack();
    }

    /// A taxed sweep must revert, not silently under-deliver and burn the
    /// one-shot flag.
    function test_TaxedSweepRevertsAndStaysRepeatable() public {
        // The fee exemption also grants the maxTx exemption, so revoking it
        // makes the sweep hit the per-transaction cap BEFORE any fee is
        // applied. Raise the cap first, to isolate the behaviour this test is
        // about: a transfer that goes through and is taxed.
        // Read before the prank: a staticcall used as an argument consumes it.
        uint256 wholeSupply = token.totalSupply();
        vm.prank(address(timelock));
        token.setMaxTxAmount(wholeSupply);

        // Break the configuration the way the finding describes.
        vm.prank(address(timelock));
        token.setExcludedFromFee(address(migration), false);

        vm.warp(migration.migrationDeadline() + 1);

        uint256 owed = token.balanceOf(address(migration));
        uint256 treasuryBefore = token.balanceOf(treasury);
        assertGt(owed, 0, "nothing to sweep");

        vm.prank(address(timelock));
        vm.expectRevert(DaimonMigration.AmountMismatch.selector);
        migration.sweepUnclaimed();

        // Nothing moved, and the one-shot flag was rolled back with the rest
        // of the transaction.
        assertEq(token.balanceOf(treasury), treasuryBefore, "treasury moved on a reverted sweep");
        assertEq(token.balanceOf(address(migration)), owed, "migration balance moved");
        assertFalse(migration.sweepExecuted(), "#11: the one-shot flag survived a failed sweep");

        // Restore the exemption: the recovery is still available and exact.
        vm.prank(address(timelock));
        token.setExcludedFromFee(address(migration), true);

        vm.prank(address(timelock));
        migration.sweepUnclaimed();

        assertTrue(migration.sweepExecuted(), "sweep did not run after the fix");
        assertEq(token.balanceOf(address(migration)), 0, "migration not emptied");
        assertEq(
            token.balanceOf(treasury) - treasuryBefore,
            owed,
            "treasury did not receive the exact remainder"
        );
    }

    /// The healthy path is unchanged: exact delivery, one shot only.
    function test_ExactSweepStillWorksAndIsOneShot() public {
        vm.warp(migration.migrationDeadline() + 1);

        uint256 owed = token.balanceOf(address(migration));
        uint256 treasuryBefore = token.balanceOf(treasury);

        vm.prank(address(timelock));
        migration.sweepUnclaimed();

        assertEq(token.balanceOf(treasury) - treasuryBefore, owed, "inexact sweep");
        assertEq(token.balanceOf(address(migration)), 0, "migration not emptied");

        vm.prank(address(timelock));
        vm.expectRevert(DaimonMigration.AlreadySwept.selector);
        migration.sweepUnclaimed();
    }
}
