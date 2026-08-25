// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {StackDeployer} from "./base/StackDeployer.sol";
import {DaimonMigration} from "../src/DaimonMigration.sol";

/*
 * Finding #13: the migration duration had no bounds. The deadline is
 * immutable AND it arms the sweep, so a zero duration made the migration
 * impossible and a huge one made the sweep unreachable — with no remedy
 * after deploy in either case.
 */
contract MigrationDurationBoundsTest is StackDeployer {
    function setUp() public {
        deployStack();
    }

    function _construct(uint256 duration) internal returns (DaimonMigration) {
        return new DaimonMigration(
            address(oldToken), address(token), treasury, address(timelock), duration
        );
    }

    function test_DurationBelowMinReverts() public {
        vm.expectRevert(DaimonMigration.InvalidMigrationDuration.selector);
        _construct(30 days - 1);

        // Zero — the case that makes the migration impossible outright.
        vm.expectRevert(DaimonMigration.InvalidMigrationDuration.selector);
        _construct(0);
    }

    function test_DurationAboveMaxReverts() public {
        vm.expectRevert(DaimonMigration.InvalidMigrationDuration.selector);
        _construct(365 days + 1);

        // The old testnet-fixture value: exactly the typo class the bound is for.
        vm.expectRevert(DaimonMigration.InvalidMigrationDuration.selector);
        _construct(3650 days);
    }

    function test_BoundsAreInclusive() public {
        // Both extremes are valid values, and the deadline lands where expected.
        DaimonMigration atMin = _construct(30 days);
        assertEq(atMin.migrationDeadline(), block.timestamp + 30 days, "min deadline wrong");

        DaimonMigration atMax = _construct(365 days);
        assertEq(atMax.migrationDeadline(), block.timestamp + 365 days, "max deadline wrong");

        assertEq(atMin.MIN_MIGRATION_DURATION(), 30 days);
        assertEq(atMax.MAX_MIGRATION_DURATION(), 365 days);
    }
}
