// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {StackDeployer} from "../base/StackDeployer.sol";
import {DaimonV2} from "../../src/DaimonV2.sol";
import {DaimonStaking} from "../../src/DaimonStaking.sol";
import {DaimonGovernor} from "../../src/DaimonGovernor.sol";

/*
 * Fuzz tests (parameters sampled by Foundry) on the critical functions.
 * Each test checks a local invariant downstream of a fuzzed action.
 */
contract FuzzDaimon is StackDeployer {
    address internal alice = address(0xA11CE);
    address internal bob = address(0xB0B);

    function setUp() public {
        deployStack();
    }

    // --- Transfer / reflection ---
    // No mint (totalSupply constant) and the sum of the known holders'
    // balances never exceeds the supply (reflection redistributes, it does
    // not create; integer rounding can only lose dust).
    function testFuzz_TransferNeverMintsAndConservesSupply(uint256 fund, uint256 amount) public {
        fund = bound(fund, 1 ether, 10_000_000 ether);
        fundWithDmn(alice, fund);

        uint256 supply = token.totalSupply();
        uint256 aBal = token.balanceOf(alice);
        amount = bound(amount, 1, _min(aBal, token.maxTxAmount()));

        vm.prank(alice);
        token.transfer(bob, amount);

        // No mint.
        assertEq(token.totalSupply(), supply, "supply changed by a transfer");
        // Sum of known holders <= supply.
        uint256 sum = token.balanceOf(alice) + token.balanceOf(bob) + token.balanceOf(address(token))
            + token.balanceOf(address(migration)) + token.balanceOf(token.deadAddress());
        assertLe(sum, supply, "sum of balances > supply (broken accounting)");
        // Bob receives a positive net and never more than the gross sent.
        assertGt(token.balanceOf(bob), 0, "bob received nothing");
        assertLe(token.balanceOf(bob), amount, "bob received more than the gross");
    }

    // --- Staking: coherent weighted voting power ---
    function testFuzz_StakeGrantsExactWeightedPower(uint256 amount, uint256 optRaw) public {
        uint256 nOpt = staking.lockOptionsLength();
        uint256 idx = bound(optRaw, 0, nOpt - 1);
        (, uint256 mult,) = staking.lockOptions(idx);

        fundWithDmn(alice, 20_000_000 ether);
        amount = bound(amount, 1 ether, token.balanceOf(alice));

        uint256 vpBefore = staking.totalVotingPower();

        vm.startPrank(alice);
        token.approve(address(staking), amount);
        uint256 lockId = staking.stake(amount, idx);
        vm.stopPrank();

        uint256 expectedVp = (amount * mult) / 1000;
        assertEq(staking.votingPower(alice), expectedVp, "wrong user vp");
        assertEq(staking.totalVotingPower(), vpBefore + expectedVp, "incoherent totalVotingPower");

        (, uint256 lockedAmount,,,, uint256 vpGranted,) = staking.locks(lockId);
        assertEq(lockedAmount, amount, "wrong lock amount");
        assertEq(vpGranted, expectedVp, "wrong stored vpGranted");
    }

    // --- Staking: withdraw at expiry returns exactly the principal ---
    function testFuzz_WithdrawReturnsPrincipal(uint256 amount, uint256 optRaw) public {
        uint256 nOpt = staking.lockOptionsLength();
        uint256 idx = bound(optRaw, 0, nOpt - 1);
        (uint256 duration,,) = staking.lockOptions(idx);

        fundWithDmn(alice, 20_000_000 ether);
        amount = bound(amount, 1 ether, token.balanceOf(alice));

        vm.startPrank(alice);
        token.approve(address(staking), amount);
        uint256 lockId = staking.stake(amount, idx);
        vm.stopPrank();

        uint256 balBefore = token.balanceOf(alice);
        vm.warp(block.timestamp + duration + 1);
        vm.prank(alice);
        staking.withdraw(lockId);

        // Staking is excluded from fees: exact net return.
        assertEq(token.balanceOf(alice), balBefore + amount, "principal not returned 1:1");
        assertEq(staking.votingPower(alice), 0, "vp not zeroed after withdraw");
        assertEq(staking.totalVotingPower(), 0, "totalVotingPower not zeroed");
    }

    // --- Exact 1:1 migration ---
    function testFuzz_MigrationIsOneToOne(uint256 amount) public {
        amount = bound(amount, 1, 500_000_000 ether);
        vm.prank(deployer);
        oldToken.transfer(alice, amount);

        uint256 treasuryBefore = oldToken.balanceOf(treasury);
        uint256 migBefore = token.balanceOf(address(migration));
        uint256 migratedBefore = migration.totalMigrated();

        vm.startPrank(alice);
        oldToken.approve(address(migration), amount);
        migration.claim(amount);
        vm.stopPrank();

        assertEq(token.balanceOf(alice), amount, "DMN received != old tokens");
        assertEq(oldToken.balanceOf(treasury), treasuryBefore + amount, "treasury did not receive the old tokens");
        assertEq(migration.totalMigrated(), migratedBefore + amount, "incoherent totalMigrated");
        assertEq(token.balanceOf(address(migration)), migBefore - amount, "DMN distributed != migrated");
    }

    // --- Reward: never more BNB than received ---
    function testFuzz_RewardsNeverExceedFunded(uint256 stakeAmt, uint256 reward) public {
        fundWithDmn(alice, 20_000_000 ether);
        stakeAmt = bound(stakeAmt, 1 ether, token.balanceOf(alice));
        reward = bound(reward, 1, 1000 ether);

        vm.startPrank(alice);
        token.approve(address(staking), stakeAmt);
        staking.stake(stakeAmt, 0);
        vm.stopPrank();

        vm.deal(address(this), reward);
        staking.notifyRewardAmount{value: reward}(reward);

        // A single staker: the pending cannot exceed the BNB paid in.
        assertLe(staking.pendingReward(alice), reward, "pending reward > funds paid in");
    }

    // --- Governance: setFees never exceeds the 10% cap ---
    function testFuzz_SetFeesRespectsCap(uint256 tax, uint256 buy, uint256 mkt) public {
        tax = bound(tax, 0, 200);
        buy = bound(buy, 0, 200);
        mkt = bound(mkt, 0, 200);

        vm.prank(address(timelock));
        if (tax + buy + mkt > 100) {
            vm.expectRevert(DaimonV2.FeeTooHigh.selector);
            token.setFees(tax, buy, mkt);
        } else {
            token.setFees(tax, buy, mkt);
            assertLe(token.taxFee() + token.buybackFee() + token.marketingFee(), 100, "total fee > cap");
        }
    }

    function _min(uint256 a, uint256 b) private pure returns (uint256) {
        return a < b ? a : b;
    }
}
