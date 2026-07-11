// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {StackDeployer} from "../base/StackDeployer.sol";
import {DaimonV2} from "../../src/DaimonV2.sol";
import {DaimonGovernor} from "../../src/DaimonGovernor.sol";

/*
 * Verifica che NESSUNA sequenza scorciatoia porti una proposta all'esecuzione
 * saltando quorum, queue o il delay del timelock. Ogni tentativo "fuori
 * ordine" deve revertire; solo il percorso completo esegue davvero.
 */
contract GovernanceSequence is StackDeployer {
    address internal whale = address(0xA11CE);

    function setUp() public {
        deployStack();
        // whale: voting power alto ma non totale, per poter distinguere quorum
        fundWithDmn(whale, 3_000_000 ether);
        vm.startPrank(whale);
        token.approve(address(staking), 3_000_000 ether);
        staking.stake(3_000_000 ether, 3);
        vm.stopPrank();
    }

    function _propose() internal returns (uint256 id, bytes memory data) {
        data = abi.encodeWithSelector(DaimonV2.setFees.selector, uint256(10), uint256(10), uint256(20));
        vm.prank(whale);
        id = governor.propose(address(token), 0, data, "Riduzione fee");
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
        // ancora in votazione: queue deve fallire
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
        // Approvata ma non messa in coda.
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
        // Delay del timelock non ancora trascorso.
        vm.expectRevert();
        governor.execute(id);
    }

    function test_DefeatedProposalCannotBeQueuedOrExecuted() public {
        // whale vota CONTRO: la proposta e' bocciata, mai eseguibile.
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
