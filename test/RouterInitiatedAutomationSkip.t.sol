// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {StackDeployer} from "./base/StackDeployer.sol";

/*
 * Finding #1.
 *
 * PancakeSwap's addLiquidityETH() reads the pair reserves, fixes the token
 * and BNB contributions from that snapshot, and only then transfers the
 * tokens to the pair. That transfer used to trigger the fee swap and the
 * buyback, which change the very reserves the router just read: the outer
 * mint() then prices the contribution on a stale ratio and part of the
 * deposit becomes pool backing that mints no LP shares (under-mint).
 *
 * The fix skips the automation whenever the configured router is the
 * immediate caller — the only way the canonical periphery ever moves tokens
 * into the pair mid-operation. The automation stays reachable through any
 * direct transfer to the pair, which carries no outer reserve snapshot.
 */
contract RouterInitiatedAutomationSkipTest is StackDeployer {
    address internal alice = address(0xA11CE);
    address internal bob = address(0xB0B);

    uint256 internal minSwap;
    address internal pair;

    function setUp() public {
        deployStack();
        pair = token.uniswapV2Pair();
    }

    /// Lowers the swap threshold to its floor, then banks one chunk of fee
    /// inventory in the contract by routing a taxed transfer through alice.
    function _armFeeInventory() internal {
        uint256 floorAmount = token.totalSupply() / 1_000_000;
        vm.prank(address(timelock));
        token.setMinimumTokensBeforeSwap(floorAmount);
        minSwap = token.minimumTokensBeforeSwap();

        uint256 gross = (minSwap * 1000) / token.liquidityFee() + 1 ether;
        fundWithDmn(alice, gross + 10 ether);
        vm.prank(alice);
        token.transfer(bob, gross);

        assertGe(token.balanceOf(address(token)), minSwap, "setup: inventory not armed");
    }

    /// The exact call shape of the router's token leg: the router is the
    /// approved spender and the tokens move holder -> pair via transferFrom.
    function _routerPullsToPair(address holder, uint256 amount) internal {
        vm.prank(holder);
        token.approve(address(router), amount);
        vm.prank(address(router));
        token.transferFrom(holder, pair, amount);
    }

    // ------------------------------------------------------------------
    // Router-initiated transfers must not run the automation
    // ------------------------------------------------------------------

    function test_RouterInitiatedTransferSkipsFeeSwap() public {
        _armFeeInventory();
        vm.prank(address(timelock));
        token.setBuyBackEnabled(false);

        // 1 wei: every fee rounds to zero, so the only possible balance
        // movement on the contract is the fee swap itself.
        uint256 invBefore = token.balanceOf(address(token));
        _routerPullsToPair(alice, 1);
        assertEq(token.balanceOf(address(token)), invBefore, "router-initiated transfer ran the fee swap");
    }

    function test_RouterInitiatedTransferSkipsBuyback() public {
        _armFeeInventory();
        vm.prank(address(timelock));
        token.setSwapAndLiquifyEnabled(false);

        // A buyback WOULD succeed here (ETH armed, router solvent in DMN):
        // an unchanged balance therefore proves the skip, not a failure.
        vm.deal(address(token), 10 ether);
        vm.prank(address(migration));
        token.transfer(address(router), 100_000 ether);

        uint256 ethBefore = address(token).balance;
        _routerPullsToPair(alice, 1);
        assertEq(address(token).balance, ethBefore, "router-initiated transfer ran the buyback");
    }

    // ------------------------------------------------------------------
    // The permissionless trigger survives: direct transfers to the pair
    // ------------------------------------------------------------------

    function test_DirectTransferToPairStillRunsFeeSwap() public {
        _armFeeInventory();
        vm.prank(address(timelock));
        token.setBuyBackEnabled(false);

        uint256 invBefore = token.balanceOf(address(token));
        vm.prank(alice);
        token.transfer(pair, 1);
        assertEq(invBefore - token.balanceOf(address(token)), minSwap, "direct trigger no longer swaps");
    }

    function test_DirectTransferToPairStillRunsBuyback() public {
        vm.prank(address(timelock));
        token.setSwapAndLiquifyEnabled(false);

        vm.deal(address(token), 10 ether);
        vm.prank(address(migration));
        token.transfer(address(router), 100_000 ether);
        fundWithDmn(alice, 1 ether);

        uint256 ethBefore = address(token).balance;
        vm.prank(alice);
        token.transfer(pair, 1);
        assertEq(ethBefore - address(token).balance, ethBefore / 20, "direct trigger no longer buys back");
    }

    // ------------------------------------------------------------------
    // Scope boundary: only the configured router is skipped
    // ------------------------------------------------------------------

    /// A third-party operator (aggregator, zap, another router) pulling
    /// tokens to the pair is OUTSIDE the skip: the fix protects the
    /// canonical router's mid-operation window, it does not try to guess
    /// which other contracts might be mid-computation.
    function test_ThirdPartyOperatorStillTriggersAutomation() public {
        _armFeeInventory();
        vm.prank(address(timelock));
        token.setBuyBackEnabled(false);

        address aggregator = address(0xA66);
        vm.prank(alice);
        token.approve(aggregator, 1);

        uint256 invBefore = token.balanceOf(address(token));
        vm.prank(aggregator);
        token.transferFrom(alice, pair, 1);
        assertEq(invBefore - token.balanceOf(address(token)), minSwap, "non-router operator was skipped too");
    }
}
