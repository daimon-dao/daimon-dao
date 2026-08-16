// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {StackDeployer} from "./base/StackDeployer.sol";
import {DaimonTimelock} from "../src/DaimonTimelock.sol";

/*
 * Finding #23: the timelock enforced a 7-day floor but no ceiling. A delay
 * past the overflow threshold would make every future schedule() revert —
 * including the proposal needed to correct it. Short of overflow, a delay of
 * years would render governance unusable while looking perfectly valid.
 *
 * The bound applies at all three doors: constructor, updateDelay(), and the
 * caller-supplied delay of schedule().
 */
contract TimelockDelayBoundsTest is StackDeployer {
    function setUp() public {
        deployStack();
    }

    // ---- Door 1: constructor ----

    function test_ConstructorRejectsAboveMax() public {
        vm.expectRevert("DaimonTimelock: above MAX_DELAY");
        new DaimonTimelock(90 days + 1, deployer, deployer, guardian, deployer);
    }

    function test_ConstructorAcceptsTheBounds() public {
        DaimonTimelock atMin = new DaimonTimelock(7 days, deployer, deployer, guardian, deployer);
        assertEq(atMin.getMinDelay(), 7 days, "min not applied");

        DaimonTimelock atMax = new DaimonTimelock(90 days, deployer, deployer, guardian, deployer);
        assertEq(atMax.getMinDelay(), 90 days, "max not applied");
        assertEq(atMax.MAX_DELAY(), 90 days);
    }

    // ---- Door 2: updateDelay() (self-call only) ----

    function test_UpdateDelayRejectsAboveMax() public {
        vm.prank(address(timelock));
        vm.expectRevert("DaimonTimelock: above MAX_DELAY");
        timelock.updateDelay(90 days + 1);

        // The overflow-class value the finding is really about.
        vm.prank(address(timelock));
        vm.expectRevert("DaimonTimelock: above MAX_DELAY");
        timelock.updateDelay(type(uint256).max);

        assertEq(timelock.getMinDelay(), 7 days, "delay moved on a rejected update");
    }

    function test_UpdateDelayAcceptsUpToMax() public {
        vm.prank(address(timelock));
        timelock.updateDelay(90 days);
        assertEq(timelock.getMinDelay(), 90 days, "max not applied");
    }

    // ---- Door 3: the delay argument of schedule() ----

    function test_ScheduleRejectsDelayAboveMax() public {
        bytes memory data = abi.encodeWithSignature("noop()");

        // The Governor holds PROPOSER_ROLE in this stack.
        vm.prank(address(governor));
        vm.expectRevert(DaimonTimelock.DelayTooLong.selector);
        timelock.schedule(address(token), 0, data, bytes32(0), keccak256("s1"), 90 days + 1);
    }

    function test_ScheduleAcceptsDelayUpToMax() public {
        bytes memory data = abi.encodeWithSignature("noop()");

        vm.prank(address(governor));
        timelock.schedule(address(token), 0, data, bytes32(0), keccak256("s2"), 90 days);

        bytes32 id = timelock.hashOperation(address(token), 0, data, bytes32(0), keccak256("s2"));
        (uint256 ready,,) = timelock.operations(id);
        assertEq(ready, block.timestamp + 90 days, "operation not scheduled at the max delay");
    }

    /// The floor still applies — the ceiling did not replace it.
    function test_ScheduleStillRejectsDelayBelowMin() public {
        bytes memory data = abi.encodeWithSignature("noop()");

        vm.prank(address(governor));
        vm.expectRevert(DaimonTimelock.DelayTooShort.selector);
        timelock.schedule(address(token), 0, data, bytes32(0), keccak256("s3"), 7 days - 1);
    }
}
