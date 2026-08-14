// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {StackDeployer} from "./base/StackDeployer.sol";

/*
 * Finding #9: DaimonStaking had a bare receive() that accepted BNB without
 * booking it. The contract balance grew while rewardPerVotingPowerStored did
 * not, breaking the invariant that it holds exactly (funded - claimed), and
 * stranding those funds — claimReward() only ever pays out what the
 * accumulator attributes, so nothing could move them again.
 *
 * Verified before removing it: DaimonV2 funds the pool exclusively through
 * notifyRewardAmount{value: ...} in _swapAccumulatedFees, never with a bare
 * transfer, so no legitimate path depended on receive().
 */
contract StakingNoBareReceiveTest is StackDeployer {
    address internal alice = address(0xA11CE);

    function setUp() public {
        deployStack();
    }

    /// A bare send now bounces instead of being trapped unaccounted.
    function test_BareBnbSendIsRejected() public {
        vm.deal(alice, 10 ether);
        uint256 senderBefore = alice.balance;
        uint256 stakingBefore = address(staking).balance;

        vm.prank(alice);
        (bool ok,) = address(staking).call{value: 1 ether}("");

        assertFalse(ok, "#9: the staking contract still accepts unaccounted BNB");
        assertEq(address(staking).balance, stakingBefore, "balance moved on a rejected send");
        assertEq(alice.balance, senderBefore, "sender lost BNB on a rejected send");
    }

    /// Calldata that matches no function is rejected as well: there is no
    /// fallback either.
    function test_UnknownCalldataWithValueIsRejected() public {
        vm.deal(alice, 10 ether);

        vm.prank(alice);
        (bool ok,) = address(staking).call{value: 1 ether}(abi.encodeWithSignature("nope()"));

        assertFalse(ok, "#9: an unknown selector with value was accepted");
        assertEq(address(staking).balance, 0, "balance moved on a rejected call");
    }

    /// The legitimate funding path is untouched, and stays fully accounted.
    function test_NotifyRewardAmountStillWorks() public {
        fundWithDmn(alice, 1_000_000 ether);
        vm.startPrank(alice);
        token.approve(address(staking), 1_000_000 ether);
        staking.stake(1_000_000 ether, 0);
        vm.stopPrank();

        vm.deal(address(this), 5 ether);
        staking.notifyRewardAmount{value: 5 ether}(5 ether);

        assertEq(address(staking).balance, 5 ether, "funding did not arrive");
        assertEq(staking.pendingReward(alice), 5 ether, "reward not accounted to the only staker");

        uint256 before = alice.balance;
        vm.prank(alice);
        staking.claimReward();
        assertEq(alice.balance - before, 5 ether, "claim did not pay the accounted amount");

        // Everything that came in went out: nothing stranded.
        assertEq(address(staking).balance, 0, "BNB left behind after a full claim");
    }

    /// The queued-rewards path (funding with no stakers yet) also relies on
    /// notifyRewardAmount, not on receive().
    function test_QueuedRewardsPathStillWorks() public {
        vm.deal(address(this), 3 ether);
        staking.notifyRewardAmount{value: 3 ether}(3 ether);

        assertEq(staking.undistributedRewards(), 3 ether, "queued rewards not recorded");
        assertEq(address(staking).balance, 3 ether, "queued BNB not held");
    }
}
