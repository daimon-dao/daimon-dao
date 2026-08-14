// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {StackDeployer} from "./base/StackDeployer.sol";
import {DaimonV2} from "../src/DaimonV2.sol";

/*
 * Finding #14: at MIN_SUPPLY, _buyBackAndBurn() returns immediately, so the
 * BNB accumulated for the buyback has no spending path left and would sit in
 * the token forever.
 *
 * settleTerminalBuyback(to) is the only way out, and it opens ONLY in that
 * terminal state.
 */
contract TerminalBuybackSettlementTest is StackDeployer {
    address internal alice = address(0xA11CE);
    address internal recipient = address(0xBEEF);

    function setUp() public {
        deployStack();
    }

    /// Drives the supply down to exactly MIN_SUPPLY.
    function _reachFloor() internal {
        address dead = token.deadAddress();
        uint256 burnable = token.INITIAL_SUPPLY() - token.MIN_SUPPLY();

        vm.prank(address(migration));
        token.transfer(dead, burnable);
        token.burnDeadBalanceToFloor();

        assertEq(token.totalSupply(), token.MIN_SUPPLY(), "floor not reached");
    }

    function test_RevertsBeforeTheFloor() public {
        vm.deal(address(token), 10 ether);
        assertGt(token.totalSupply(), token.MIN_SUPPLY(), "already at the floor");

        vm.prank(address(timelock));
        vm.expectRevert(DaimonV2.FloorNotReached.selector);
        token.settleTerminalBuyback(recipient);

        assertEq(address(token).balance, 10 ether, "BNB moved before the floor");
    }

    function test_SettlesAtTheFloor() public {
        _reachFloor();
        vm.deal(address(token), 10 ether);
        uint256 before = recipient.balance;

        vm.expectEmit(true, false, false, true, address(token));
        emit DaimonV2.TerminalBuybackSettled(recipient, 10 ether);

        vm.prank(address(timelock));
        token.settleTerminalBuyback(recipient);

        assertEq(recipient.balance - before, 10 ether, "recipient did not receive the residue");
        assertEq(address(token).balance, 0, "BNB left stranded in the token");
    }

    function test_RejectsDestructiveRecipients() public {
        _reachFloor();
        vm.deal(address(token), 10 ether);
        address dead = token.deadAddress();

        vm.prank(address(timelock));
        vm.expectRevert(DaimonV2.InvalidRecipient.selector);
        token.settleTerminalBuyback(address(0));

        vm.prank(address(timelock));
        vm.expectRevert(DaimonV2.InvalidRecipient.selector);
        token.settleTerminalBuyback(address(token));

        vm.prank(address(timelock));
        vm.expectRevert(DaimonV2.InvalidRecipient.selector);
        token.settleTerminalBuyback(dead);

        assertEq(address(token).balance, 10 ether, "BNB moved on a rejected recipient");
    }

    function test_RevertsWithNothingToSettle() public {
        _reachFloor();
        assertEq(address(token).balance, 0, "unexpected balance");

        vm.prank(address(timelock));
        vm.expectRevert(DaimonV2.NothingToSettle.selector);
        token.settleTerminalBuyback(recipient);
    }

    /// Governance only: it can only arrive through propose -> vote -> timelock.
    function test_GovernanceOnly() public {
        _reachFloor();
        vm.deal(address(token), 10 ether);

        vm.prank(alice);
        vm.expectRevert();
        token.settleTerminalBuyback(recipient);

        vm.prank(guardian);
        vm.expectRevert();
        token.settleTerminalBuyback(recipient);

        assertEq(address(token).balance, 10 ether, "BNB moved for a non-governance caller");
    }
}
