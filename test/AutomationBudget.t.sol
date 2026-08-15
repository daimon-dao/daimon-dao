// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {StackDeployer} from "./base/StackDeployer.sol";
import {DaimonV2} from "../src/DaimonV2.sol";

/*
 * Finding #28.
 *
 * A 1-wei transfer to the pair triggers the automation (amount > 0 is the
 * only requirement, and at 1 wei every fee rounds to zero), and lockSwap /
 * nonReentrant only prevent nesting: they reset between calls. A loop of
 * dust transfers therefore ran another fee-swap chunk and another buyback
 * slice per iteration - the limits bounded the single execution, not the
 * aggregate. The fix introduces per-block budgets, independent of the
 * caller: attempts consumed before the router interaction, amounts counted
 * only on success.
 */

contract DustTrigger {
    DaimonV2 private immutable token;
    address private immutable pair;

    constructor(DaimonV2 _token, address _pair) {
        token = _token;
        pair = _pair;
    }

    function spam(uint256 n) external {
        for (uint256 i = 0; i < n; i++) {
            token.transfer(pair, 1);
        }
    }
}

contract AutomationBudgetTest is StackDeployer {
    address internal alice = address(0xA11CE);
    address internal bob = address(0xB0B);

    uint256 internal minSwap;
    address internal pair;

    function setUp() public {
        deployStack();
        pair = token.uniswapV2Pair();
    }

    /// Same arming as the reproduction suite: lower the threshold, then bank
    /// `chunks` chunks of fee inventory in the contract.
    function _armFeeInventory(uint256 chunks) internal {
        uint256 floorAmount = token.totalSupply() / 1_000_000;
        vm.prank(address(timelock));
        token.setMinimumTokensBeforeSwap(floorAmount);
        minSwap = token.minimumTokensBeforeSwap();

        uint256 gross = (minSwap * chunks * 1000) / token.liquidityFee() + 1 ether;
        fundWithDmn(alice, gross + 10 ether);
        vm.prank(alice);
        token.transfer(bob, gross);

        assertGe(token.balanceOf(address(token)), minSwap * chunks, "setup: inventory not armed");
    }

    function _newDustTrigger() internal returns (DustTrigger d) {
        d = new DustTrigger(token, pair);
        fundWithDmn(address(this), 10 ether);
        token.transfer(address(d), 5 ether);
    }

    // ------------------------------------------------------------------
    // The two per-block caps
    // ------------------------------------------------------------------

    function test_FeeSwapCappedAtOneChunkPerBlock() public {
        _armFeeInventory(5);
        vm.prank(address(timelock));
        token.setBuyBackEnabled(false);

        DustTrigger d = _newDustTrigger();

        uint256 invBefore = token.balanceOf(address(token));
        d.spam(5);
        assertEq(invBefore - token.balanceOf(address(token)), minSwap, "not exactly one chunk");

        // The budget is caller-independent: a DIFFERENT sender in the same
        // block gets nothing either. Dust again, so the sender's own 4%
        // liquidity fee (inbound to the contract) does not pollute the delta.
        uint256 invMid = token.balanceOf(address(token));
        vm.prank(alice);
        token.transfer(pair, 1);
        assertEq(token.balanceOf(address(token)) - invMid, 0, "second caller got another chunk");
    }

    function test_BuybackCappedAtOneSlicePerBlock() public {
        _armFeeInventory(1);
        vm.prank(address(timelock));
        token.setSwapAndLiquifyEnabled(false);

        vm.deal(address(token), 10 ether);
        vm.prank(address(migration));
        token.transfer(address(router), 100_000 ether);

        DustTrigger d = _newDustTrigger();

        uint256 ethBefore = address(token).balance;
        d.spam(5);
        // Exactly one 5% slice: the geometric drain (~2.26 ETH over 5 calls)
        // collapses to the single slice the parameters always intended.
        assertEq(ethBefore - address(token).balance, ethBefore / 20, "not exactly one slice");
    }

    // ------------------------------------------------------------------
    // Reset: pacing, not prohibition
    // ------------------------------------------------------------------

    function test_BudgetResetsOnNextBlock() public {
        _armFeeInventory(5);
        vm.prank(address(timelock));
        token.setBuyBackEnabled(false);

        DustTrigger d = _newDustTrigger();

        uint256 invBefore = token.balanceOf(address(token));
        d.spam(2);
        assertEq(invBefore - token.balanceOf(address(token)), minSwap, "block 1: one chunk");

        vm.roll(block.number + 1);
        d.spam(2);
        assertEq(invBefore - token.balanceOf(address(token)), 2 * minSwap, "block 2: second chunk");
    }

    // ------------------------------------------------------------------
    // Attempts are consumed BEFORE the router interaction
    // ------------------------------------------------------------------

    function test_FailedFeeSwapConsumesTheBlockAttempt() public {
        _armFeeInventory(2);
        vm.prank(address(timelock));
        token.setBuyBackEnabled(false);

        // Insolvent router: the swap leg reverts, the try/catch absorbs it.
        vm.deal(address(router), 0);

        DustTrigger d = _newDustTrigger();
        uint256 invBefore = token.balanceOf(address(token));

        d.spam(1);
        assertEq(invBefore - token.balanceOf(address(token)), 0, "failed swap moved inventory");

        // Solvent again, SAME block: the attempt is spent, no retry.
        vm.deal(address(router), 100_000 ether);
        d.spam(1);
        assertEq(invBefore - token.balanceOf(address(token)), 0, "caught failure was retried in-block");

        // Next block: the budget rolls and the chunk goes through.
        vm.roll(block.number + 1);
        d.spam(1);
        assertEq(invBefore - token.balanceOf(address(token)), minSwap, "next block did not recover");
    }

    function test_FailedBuybackConsumesTheBlockAttempt() public {
        _armFeeInventory(1);
        vm.prank(address(timelock));
        token.setSwapAndLiquifyEnabled(false);

        vm.deal(address(token), 10 ether);
        // Router NOT funded with DMN: the buyback's swap leg fails, caught.

        DustTrigger d = _newDustTrigger();
        uint256 ethBefore = address(token).balance;

        d.spam(1);
        assertEq(ethBefore - address(token).balance, 0, "failed buyback spent ETH");

        // Fund the router, SAME block: the attempt is spent, no retry.
        vm.prank(address(migration));
        token.transfer(address(router), 100_000 ether);
        d.spam(1);
        assertEq(ethBefore - address(token).balance, 0, "caught failure was retried in-block");

        // Next block: nothing was spent so far, so the slice is still
        // computed on the full balance.
        vm.roll(block.number + 1);
        d.spam(1);
        assertEq(ethBefore - address(token).balance, ethBefore / 20, "next block did not recover");
    }
}
