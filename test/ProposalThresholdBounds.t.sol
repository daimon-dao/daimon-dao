// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {StackDeployer} from "./base/StackDeployer.sol";
import {DaimonGovernor} from "../src/DaimonGovernor.sol";

/*
 * Finding #19: setProposalThreshold() accepted up to type(uint256).max, while
 * the voting power any account can ever hold is bounded. A threshold above
 * that ceiling would make it impossible to create the very proposal needed to
 * lower it: governance frozen permanently, with no recovery path.
 */
contract ProposalThresholdBoundsTest is StackDeployer {
    address internal alice = address(0xA11CE);

    function setUp() public {
        deployStack();
    }

    function test_SetterRejectsAboveMax() public {
        uint256 max = governor.MAX_PROPOSAL_THRESHOLD();

        vm.prank(address(timelock));
        vm.expectRevert("DaimonGovernor: threshold too high");
        governor.setProposalThreshold(max + 1);

        // The extreme the finding is really about.
        vm.prank(address(timelock));
        vm.expectRevert("DaimonGovernor: threshold too high");
        governor.setProposalThreshold(type(uint256).max);

        // Unchanged by the rejected calls.
        assertEq(governor.proposalThreshold(), 1000 ether, "threshold moved on a rejected set");
    }

    function test_SetterAcceptsUpToMax() public {
        uint256 max = governor.MAX_PROPOSAL_THRESHOLD();

        vm.prank(address(timelock));
        governor.setProposalThreshold(max);
        assertEq(governor.proposalThreshold(), max, "max threshold not applied");

        // And ordinary values keep working.
        vm.prank(address(timelock));
        governor.setProposalThreshold(5_000 ether);
        assertEq(governor.proposalThreshold(), 5_000 ether);
    }

    function test_ConstructorRejectsAboveMax() public {
        uint256 max = governor.MAX_PROPOSAL_THRESHOLD();

        vm.expectRevert("DaimonGovernor: threshold too high");
        new DaimonGovernor(address(staking), address(timelock), guardian, 1000, max + 1);
    }

    function test_ConstructorAcceptsUpToMax() public {
        uint256 max = governor.MAX_PROPOSAL_THRESHOLD();

        DaimonGovernor g = new DaimonGovernor(address(staking), address(timelock), guardian, 1000, max);
        assertEq(g.proposalThreshold(), max, "constructor did not apply the max");
    }

    /// The bound is the documented policy: one percent of the supply floor.
    function test_MaxIsOnePercentOfTheSupplyFloor() public view {
        assertEq(
            governor.MAX_PROPOSAL_THRESHOLD(),
            token.MIN_SUPPLY() / 100,
            "#19: the cap drifted from MIN_SUPPLY / 100"
        );
    }
}
