// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Vm} from "forge-std/Vm.sol";
import {StackDeployer} from "./base/StackDeployer.sol";
import {DaimonV2} from "../src/DaimonV2.sol";

/*
 * Finding #21: deviations from ERC-20/BEP-20 observable behaviour.
 * Zero-value transfers must succeed and emit; every real balance movement
 * must be reported as a Transfer; reflection — which is not a movement
 * between accounts — gets its own event; the burn uses the conventional
 * transfer-to-zero signature.
 */
contract Erc20ComplianceTest is StackDeployer {
    address internal alice = address(0xA11CE);
    address internal bob = address(0xB0B);

    function setUp() public {
        deployStack();
    }

    // ---- 1. Zero-value transfers ----

    function test_ZeroValueTransferSucceedsAndEmits() public {
        fundWithDmn(alice, 1_000 ether);
        uint256 balBefore = token.balanceOf(alice);

        vm.expectEmit(true, true, false, true, address(token));
        emit DaimonV2.Transfer(alice, bob, 0);
        vm.prank(alice);
        bool ok = token.transfer(bob, 0);

        assertTrue(ok, "zero transfer returned false");
        assertEq(token.balanceOf(alice), balBefore, "zero transfer moved balance");
        assertEq(token.balanceOf(bob), 0, "recipient credited on a zero transfer");
    }

    function test_ZeroValueTransferFromSucceeds() public {
        fundWithDmn(alice, 1_000 ether);
        vm.prank(alice);
        token.approve(bob, 100 ether);

        vm.prank(bob);
        bool ok = token.transferFrom(alice, bob, 0);
        assertTrue(ok, "zero transferFrom returned false");
        assertEq(token.allowance(alice, bob), 100 ether, "zero transferFrom consumed allowance");
    }

    /// The early return sits BEFORE the swap/buyback automation, so a
    /// zero-amount transfer cannot be used as a free trigger for it.
    function test_ZeroValueTransferDoesNotTriggerAutomation() public {
        vm.prank(address(timelock));
        token.setMinimumTokensBeforeSwap(1_000_000 ether);
        vm.deal(address(router), 5_000 ether);

        fundWithDmn(alice, 100_000_000 ether);
        vm.prank(alice);
        token.transfer(bob, 50_000_000 ether); // arm the fee inventory

        uint256 inventoryBefore = token.balanceOf(address(token));
        assertGe(inventoryBefore, 1_000_000 ether, "fee inventory not armed");

        // A zero transfer to the pair: the swap must NOT run.
        address pair = token.uniswapV2Pair(); // read before the prank
        vm.prank(alice);
        token.transfer(pair, 0);

        assertEq(
            token.balanceOf(address(token)),
            inventoryBefore,
            "#21: zero-value transfer triggered the fee swap"
        );
    }

    /// A paused token transfers nothing, not even zero.
    function test_ZeroValueTransferStillBlockedWhilePaused() public {
        fundWithDmn(alice, 1_000 ether);
        vm.prank(guardian);
        token.setPaused(true);

        vm.prank(alice);
        vm.expectRevert(DaimonV2.ContractIsPaused.selector);
        token.transfer(bob, 0);
    }

    // ---- 2 & 3. Fee and reflection events ----

    /// The liquidity fee credited to the contract is a real balance movement
    /// and must be visible as a Transfer; the reflection share gets its own
    /// event, because no account receives it.
    function test_FeeAndReflectionAreObservable() public {
        fundWithDmn(alice, 10_000_000 ether);

        uint256 amount = 1_000_000 ether;
        // Fees are per-mille: tax 1%, liquidity 3% at the deployed defaults.
        uint256 expectedTax = (amount * token.taxFee()) / 1000;
        uint256 expectedLiquidity = (amount * token.liquidityFee()) / 1000;
        assertGt(expectedTax, 0, "no tax configured");
        assertGt(expectedLiquidity, 0, "no liquidity fee configured");

        vm.expectEmit(true, true, false, true, address(token));
        emit DaimonV2.Transfer(alice, address(token), expectedLiquidity);
        vm.expectEmit(true, false, false, true, address(token));
        emit DaimonV2.ReflectionFeeApplied(alice, expectedTax);

        vm.prank(alice);
        token.transfer(bob, amount);
    }

    /// A fee-exempt sender moves the full amount: no fee events at all.
    function test_NoFeeEventsWhenExempt() public {
        fundWithDmn(alice, 1_000 ether);
        vm.prank(address(timelock));
        token.setExcludedFromFee(alice, true);

        vm.recordLogs();
        vm.prank(alice);
        token.transfer(bob, 1_000 ether);

        // Exactly one Transfer, no ReflectionFeeApplied.
        uint256 transfers;
        uint256 reflections;
        bytes32 transferTopic = keccak256("Transfer(address,address,uint256)");
        bytes32 reflectionTopic = keccak256("ReflectionFeeApplied(address,uint256)");
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == transferTopic) transfers++;
            if (logs[i].topics[0] == reflectionTopic) reflections++;
        }
        assertEq(transfers, 1, "fee-exempt transfer emitted extra Transfer events");
        assertEq(reflections, 0, "fee-exempt transfer emitted a reflection event");
    }

    // ---- 4. Burn signature ----

    function test_BurnEmitsTransferToZeroAddress() public {
        // Read the address BEFORE the prank: a staticcall used as an argument
        // would consume it and send the transfer from the test contract.
        address dead = token.deadAddress();

        vm.prank(address(migration));
        token.transfer(dead, 5_000_000 ether);
        uint256 deadBal = token.balanceOf(dead);
        assertGt(deadBal, 0, "nothing to burn");

        vm.expectEmit(true, true, false, true, address(token));
        emit DaimonV2.Transfer(dead, address(0), deadBal);
        token.burnDeadBalanceToFloor();

        assertEq(token.balanceOf(dead), 0, "dead balance not burned");
    }

    // ---- 5. getOwner() is deliberately absent ----

    /// The BEP-2 binding is not supported: this token has no owner, and
    /// returning a placeholder would misrepresent the trust model.
    function test_GetOwnerIsNotImplemented() public {
        (bool ok,) = address(token).call(abi.encodeWithSignature("getOwner()"));
        assertFalse(ok, "#21: getOwner() should not exist on an ownerless token");
    }
}
