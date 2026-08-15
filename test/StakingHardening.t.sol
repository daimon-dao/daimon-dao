// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {StackDeployer} from "./base/StackDeployer.sol";
import {DaimonStaking} from "../src/DaimonStaking.sol";

/*
 * Zenith #31, #33, #35 and the #32-bis structural guard, fixed in one pass
 * because DaimonStaking is NOT upgradeable: any later correction would mean
 * redeploying both the staking contract and the Governor that stores its
 * address immutably.
 *
 * #31  - reward math on naive uint256 products overflowed once a low-power
 *        epoch poisoned the accumulator, bricking stake/withdraw for large
 *        stakers. Math.mulDiv everywhere.
 * #33  - DMN above the staked principal (reflection accrual, donations) was
 *        stuck forever. transferSurplus, governance-only.
 * #35  - rewards received with zero stakers were captured wholesale by the
 *        first (even 1 wei) staker. Separate zeroStakerReserve, never
 *        merged, recoverable only by governance.
 * #32b - stake() now refuses deposits while the contract is not fee-exempt
 *        on the token: the amount-based accounting is only sound untaxed.
 */
contract StakingHardeningTest is StackDeployer {
    address internal alice = address(0xA11CE);
    address internal whale = address(0x3A1E);
    address internal recipient = address(0xDEC1);

    function setUp() public {
        deployStack();
    }

    function _stake(address who, uint256 amount, uint256 opt) internal returns (uint256 lockId) {
        fundWithDmn(who, amount);
        vm.startPrank(who);
        token.approve(address(staking), amount);
        lockId = staking.stake(amount, opt);
        vm.stopPrank();
    }

    // ------------------------------------------------------------------
    // #31 - overflow in the reward math
    // ------------------------------------------------------------------

    /// The bricking scenario: a 1 wei staker receives a large notify, the
    /// accumulator reaches 1e47, and a whale with ~2.4e30 voting power used
    /// to overflow vp * accumulator (2.4e77 > 2^256) inside stake() - in a
    /// non-upgradeable contract, permanently.
    function test_31_PoisonedAccumulatorNoLongerBricksLargeStakers() public {
        _stake(alice, 1, 0); // vp = 1 wei
        vm.deal(address(this), 100 ether);
        staking.notifyRewardAmount{value: 100 ether}(100 ether); // acc = 1e47

        vm.prank(address(timelock));
        token.setMaxTxAmount(1_000_000_000_000 ether); // lift maxTx for the whale deposit

        uint256 whaleAmount = 600_000_000_000 ether; // 6e29 DMN, 4x lock -> vp 2.4e30
        uint256 lockId = _stake(whale, whaleAmount, 3); // used to revert with panic 0x11

        // The whale's rewards stay sane: a fresh notify is split pro-rata.
        vm.deal(address(this), 12 ether);
        staking.notifyRewardAmount{value: 12 ether}(12 ether);
        assertApproxEqAbs(staking.pendingReward(whale), 12 ether, 1e9, "whale reward distorted");
        // Alice keeps the 100 ether she was legitimately the sole staker for.
        assertApproxEqAbs(staking.pendingReward(alice), 100 ether, 1e9, "sole-staker backlog lost");

        // And the principal comes back exactly, through the same math.
        vm.warp(block.timestamp + 366 days);
        uint256 balBefore = token.balanceOf(whale);
        vm.prank(whale);
        staking.withdraw(lockId);
        assertEq(token.balanceOf(whale) - balBefore, whaleAmount, "principal not returned 1:1");
    }

    /// mulDiv floors exactly like the plain expression when nothing
    /// overflows: small-scale accounting is bit-for-bit unchanged.
    function test_31_RewardMathUnchangedAtSmallScale() public {
        _stake(alice, 600 ether, 0); // vp 600
        _stake(whale, 400 ether, 0); // vp 400

        vm.deal(address(this), 10 ether);
        staking.notifyRewardAmount{value: 10 ether}(10 ether);

        assertEq(staking.pendingReward(alice), 6 ether, "60% share inexact");
        assertEq(staking.pendingReward(whale), 4 ether, "40% share inexact");
    }

    // ------------------------------------------------------------------
    // #33 - surplus DMN recovery
    // ------------------------------------------------------------------

    function test_33_SurplusTransferMovesOnlySurplus() public {
        _stake(alice, 1_000 ether, 0);

        // Deterministic surplus: an exempt sender donates untaxed.
        vm.prank(address(migration));
        token.transfer(address(staking), 50 ether);

        uint256 stakingBal = token.balanceOf(address(staking));
        assertGe(stakingBal, 1_050 ether, "setup: surplus missing");

        // More than the surplus is refused, wherever the principal sits.
        vm.prank(address(timelock));
        vm.expectRevert(DaimonStaking.AmountExceedsSurplus.selector);
        staking.transferSurplus(recipient, stakingBal - 1_000 ether + 1);

        // The exact surplus moves, with measured deltas in the event.
        uint256 surplus = stakingBal - 1_000 ether;
        vm.expectEmit(true, false, false, true);
        emit DaimonStaking.SurplusTransferred(recipient, surplus, surplus);
        vm.prank(address(timelock));
        staking.transferSurplus(recipient, surplus);

        assertEq(token.balanceOf(recipient), surplus, "recipient did not receive the surplus");
        assertEq(token.balanceOf(address(staking)), 1_000 ether, "principal touched");

        // Alice's principal is intact and withdrawable in full.
        vm.warp(block.timestamp + 31 days);
        uint256 balBefore = token.balanceOf(alice);
        vm.prank(alice);
        staking.withdraw(0);
        assertEq(token.balanceOf(alice) - balBefore, 1_000 ether, "withdraw shorted after surplus transfer");
    }

    function test_33_SurplusGuards() public {
        vm.prank(address(migration));
        token.transfer(address(staking), 10 ether);

        // Only governance.
        vm.expectRevert(DaimonStaking.NotGovernance.selector);
        staking.transferSurplus(recipient, 1 ether);

        // Destinations that would destroy or strand the value.
        vm.startPrank(address(timelock));
        vm.expectRevert(DaimonStaking.InvalidRecipient.selector);
        staking.transferSurplus(address(0), 1 ether);
        vm.expectRevert(DaimonStaking.InvalidRecipient.selector);
        staking.transferSurplus(address(staking), 1 ether);
        vm.expectRevert(DaimonStaking.InvalidRecipient.selector);
        staking.transferSurplus(0x000000000000000000000000000000000000dEaD, 1 ether);
        vm.expectRevert(DaimonStaking.ZeroAmount.selector);
        staking.transferSurplus(recipient, 0);
        vm.stopPrank();
    }

    // ------------------------------------------------------------------
    // #35 - zero-staker reserve
    // ------------------------------------------------------------------

    function test_35_ZeroStakerRewardsAreReserved() public {
        vm.deal(address(this), 15 ether);

        vm.expectEmit(false, false, false, true);
        emit DaimonStaking.RewardReserved(10 ether);
        staking.notifyRewardAmount{value: 10 ether}(10 ether);
        assertEq(staking.zeroStakerReserve(), 10 ether);

        staking.notifyRewardAmount{value: 5 ether}(5 ether);
        assertEq(staking.zeroStakerReserve(), 15 ether);
        assertEq(staking.rewardPerVotingPowerStored(), 0, "reserve leaked into the accumulator");
    }

    /// The repro shape: reserve accrued before the dust staker existed must
    /// stay out of its reach, through notify, claim and time.
    function test_35_DustStakeCannotCaptureReserve() public {
        vm.deal(address(this), 11 ether);
        staking.notifyRewardAmount{value: 10 ether}(10 ether); // backlog, nobody staked

        _stake(alice, 1, 0); // the 1 wei "captor"
        staking.notifyRewardAmount{value: 0.01 ether}(0.01 ether);

        // Alice gets the new notify (she is the sole staker) - and nothing else.
        assertEq(staking.pendingReward(alice), 0.01 ether, "dust staker reward wrong");

        vm.prank(alice);
        staking.claimReward();
        assertEq(alice.balance, 0.01 ether, "dust staker balance wrong");
        assertEq(staking.zeroStakerReserve(), 10 ether, "reserve eroded");
        assertGe(address(staking).balance, 10 ether, "reserve not backed by balance");
    }

    function test_35_ReserveRecoverableByGovernanceOnly() public {
        vm.deal(address(this), 10 ether);
        staking.notifyRewardAmount{value: 10 ether}(10 ether);

        vm.expectRevert(DaimonStaking.NotGovernance.selector);
        staking.transferZeroStakerReserve(recipient, 1 ether);

        vm.startPrank(address(timelock));
        vm.expectRevert(DaimonStaking.InvalidRecipient.selector);
        staking.transferZeroStakerReserve(address(0), 1 ether);
        vm.expectRevert(DaimonStaking.InvalidRecipient.selector);
        staking.transferZeroStakerReserve(address(staking), 1 ether);
        vm.expectRevert(DaimonStaking.InvalidRecipient.selector);
        staking.transferZeroStakerReserve(0x000000000000000000000000000000000000dEaD, 1 ether);
        vm.expectRevert(DaimonStaking.AmountExceedsReserve.selector);
        staking.transferZeroStakerReserve(recipient, 10 ether + 1);

        // Partial recovery, measured deltas.
        vm.expectEmit(true, false, false, true);
        emit DaimonStaking.ZeroStakerReserveTransferred(recipient, 4 ether, 4 ether);
        staking.transferZeroStakerReserve(recipient, 4 ether);
        vm.stopPrank();

        assertEq(recipient.balance, 4 ether);
        assertEq(staking.zeroStakerReserve(), 6 ether);

        // The remainder stays recoverable.
        vm.prank(address(timelock));
        staking.transferZeroStakerReserve(recipient, 6 ether);
        assertEq(recipient.balance, 10 ether);
        assertEq(staking.zeroStakerReserve(), 0);
    }

    // ------------------------------------------------------------------
    // #32-bis - structural fee-exemption guard
    // ------------------------------------------------------------------

    /// Constructed with NO stake outstanding, so it stays valid once the
    /// token-side #32 fix (mandatory exemption while staked) is merged.
    function test_32bis_StakeRefusedWithoutFeeExemption() public {
        fundWithDmn(alice, 100 ether);

        vm.prank(address(timelock));
        token.setExcludedFromFee(address(staking), false);

        vm.startPrank(alice);
        token.approve(address(staking), 100 ether);
        vm.expectRevert(DaimonStaking.StakingNotFeeExempt.selector);
        staking.stake(100 ether, 0);
        vm.stopPrank();

        // Exemption restored: the same deposit goes through.
        vm.prank(address(timelock));
        token.setExcludedFromFee(address(staking), true);
        vm.prank(alice);
        staking.stake(100 ether, 0);
        assertEq(staking.totalStakedAmount(), 100 ether);
    }
}
