// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/*
 * DaimonStaking
 * -------------
 * Stake DaimonV2 with a lock time of your choice: the longer the lock, the
 * more voting power you get (vote-escrow / veCRV style), plus a proportional
 * ETH reward (funded by the token's marketing fee).
 *
 * Voting power does NOT derive from the generic ERC20 balance (incompatible
 * with the token's reflection, see the explanation elsewhere in the
 * conversation), but exclusively from how much and for how long you have
 * locked here.
 *
 * Security:
 *  - ReentrancyGuard on every function that moves funds
 *  - Checks-effects-interactions everywhere
 *  - No loop over user-controlled-length arrays in public functions (each
 *    lock is a record indexed by id, not in an array)
 *  - Unstake cooldown proportional to the chosen lock: whoever picks a long
 *    lock cannot exit before expiry; at the end of the lock, withdraw is
 *    immediate (no extra cooldown, the lock itself IS the cooldown)
 */

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

interface IDaimonV2Token {
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

contract DaimonStaking is ReentrancyGuard {
    // ---- Governance (bespoke mapping: multiple addresses can be enabled,
    // managed by the DAO Timelock; semantics differ from OZ AccessControl) ----
    mapping(address => bool) private _governance;

    error NotGovernance();

    modifier onlyGovernance() {
        if (!_governance[msg.sender]) revert NotGovernance();
        _;
    }

    function _setGovernance(address account, bool enabled) internal {
        _governance[account] = enabled;
    }

    function isGovernance(address account) public view returns (bool) {
        return _governance[account];
    }

    IDaimonV2Token public immutable daimonToken;

    // Lock options: duration in seconds => voting power multiplier (x1000)
    // Example: 30 days = 1.0x weight, 365 days = 4.0x weight
    struct LockOption {
        uint256 duration;
        uint256 multiplierX1000; // 1000 = 1x
        bool active;
    }

    LockOption[] public lockOptions;

    struct Lock {
        address owner;
        uint256 amount;
        uint256 start;
        uint256 unlockTime;
        uint256 multiplierX1000;
        // Voting power credited at stake time: withdraw subtracts EXACTLY
        // this value, never a recomputation (if the vp formula changed in an
        // upgrade, a recomputation would diverge and corrupt the totals).
        uint256 votingPowerGranted;
        bool withdrawn;
    }

    mapping(uint256 => Lock) public locks;
    uint256 public nextLockId;

    mapping(address => uint256) public votingPower;     // weighted sum of all the user's active locks
    mapping(address => uint256) public totalStaked;     // (unweighted) capital sum of the user

    uint256 public totalVotingPower;
    uint256 public totalStakedAmount;

    // ---- Voting power checkpoints (OZ Votes style) ----
    // At each stake/withdraw a (timestamp, votingPower) pair is recorded:
    // the Governor reads the voting power at the proposal snapshot via
    // votingPowerAt(), so tokens staked AFTER a proposal's creation cannot
    // vote on it.
    struct Checkpoint {
        uint256 timestamp;
        uint256 votingPower;
    }

    mapping(address => Checkpoint[]) private _vpCheckpoints;

    // ---- Reward pool (funded in BNB by the token's marketing fee) ----
    // Scale 1e27: with voting power up to ~4e30 (4x on a supply of 1e12
    // tokens at 18 decimals), a 1e18 scale would truncate small notifies to
    // zero.
    uint256 private constant REWARD_PRECISION = 1e27;

    uint256 public rewardPerVotingPowerStored; // MasterChef-style accumulator, scaled by REWARD_PRECISION
    // BNB received when totalVotingPower == 0: queued and distributed at the
    // first notify with stakers present.
    uint256 public undistributedRewards;
    mapping(address => uint256) private _userRewardDebt;
    mapping(address => uint256) private _userPendingReward;

    event Staked(address indexed user, uint256 indexed lockId, uint256 amount, uint256 duration, uint256 votingPowerGranted);
    event Withdrawn(address indexed user, uint256 indexed lockId, uint256 amount);
    event RewardClaimed(address indexed user, uint256 amount);
    event RewardNotified(uint256 amount);
    event LockOptionAdded(uint256 duration, uint256 multiplierX1000);
    event LockOptionDisabled(uint256 index);

    error InvalidLockOption();
    error LockStillActive();
    error AlreadyWithdrawn();
    error NotLockOwner();
    error ZeroAmount();

    // The parameter is named initialGovernance (not _governance) so it does
    // not shadow the state mapping of the same name.
    constructor(address _daimonToken, address initialGovernance) {
        daimonToken = IDaimonV2Token(_daimonToken);
        _setGovernance(initialGovernance, true);

        // Opzioni di default: 30gg / 90gg / 180gg / 365gg
        lockOptions.push(LockOption(30 days, 1000, true));
        lockOptions.push(LockOption(90 days, 1500, true));
        lockOptions.push(LockOption(180 days, 2200, true));
        lockOptions.push(LockOption(365 days, 4000, true));
    }

    // ============================================================
    // Staking
    // ============================================================
    function stake(uint256 amount, uint256 lockOptionIndex) external nonReentrant returns (uint256 lockId) {
        if (amount == 0) revert ZeroAmount();
        if (lockOptionIndex >= lockOptions.length || !lockOptions[lockOptionIndex].active) revert InvalidLockOption();

        _settleReward(msg.sender);

        LockOption memory opt = lockOptions[lockOptionIndex];

        bool ok = daimonToken.transferFrom(msg.sender, address(this), amount);
        require(ok, "DaimonStaking: transferFrom failed");

        uint256 vp = (amount * opt.multiplierX1000) / 1000;

        lockId = nextLockId++;
        locks[lockId] = Lock({
            owner: msg.sender,
            amount: amount,
            start: block.timestamp,
            unlockTime: block.timestamp + opt.duration,
            multiplierX1000: opt.multiplierX1000,
            votingPowerGranted: vp,
            withdrawn: false
        });

        votingPower[msg.sender] += vp;
        totalStaked[msg.sender] += amount;
        totalVotingPower += vp;
        totalStakedAmount += amount;

        _writeCheckpoint(msg.sender);

        _userRewardDebt[msg.sender] = (votingPower[msg.sender] * rewardPerVotingPowerStored) / REWARD_PRECISION;

        emit Staked(msg.sender, lockId, amount, opt.duration, vp);
    }

    function withdraw(uint256 lockId) external nonReentrant {
        Lock storage lockData = locks[lockId];
        if (lockData.owner != msg.sender) revert NotLockOwner();
        if (lockData.withdrawn) revert AlreadyWithdrawn();
        if (block.timestamp < lockData.unlockTime) revert LockStillActive();

        _settleReward(msg.sender);

        uint256 amount = lockData.amount;
        uint256 vp = lockData.votingPowerGranted;

        lockData.withdrawn = true;
        votingPower[msg.sender] -= vp;
        totalStaked[msg.sender] -= amount;
        totalVotingPower -= vp;
        totalStakedAmount -= amount;

        _writeCheckpoint(msg.sender);

        _userRewardDebt[msg.sender] = (votingPower[msg.sender] * rewardPerVotingPowerStored) / REWARD_PRECISION;

        bool ok = daimonToken.transfer(msg.sender, amount);
        require(ok, "DaimonStaking: transfer failed");

        emit Withdrawn(msg.sender, lockId, amount);
    }

    // ============================================================
    // Checkpoint del voting power
    // ============================================================
    function _writeCheckpoint(address account) private {
        uint256 vp = votingPower[account];
        Checkpoint[] storage cps = _vpCheckpoints[account];
        uint256 len = cps.length;
        if (len > 0 && cps[len - 1].timestamp == block.timestamp) {
            cps[len - 1].votingPower = vp;
        } else {
            cps.push(Checkpoint({timestamp: block.timestamp, votingPower: vp}));
        }
    }

    /// @notice Voting power of `account` at instant `timestamp` (last
    /// checkpoint with timestamp <= requested; 0 if none). Binary search:
    /// O(log n) even with many stake/withdraw.
    function votingPowerAt(address account, uint256 timestamp) external view returns (uint256) {
        Checkpoint[] storage cps = _vpCheckpoints[account];
        uint256 len = cps.length;
        if (len == 0 || cps[0].timestamp > timestamp) return 0;
        uint256 lo = 0;
        uint256 hi = len - 1;
        while (lo < hi) {
            uint256 mid = (lo + hi + 1) / 2;
            if (cps[mid].timestamp <= timestamp) {
                lo = mid;
            } else {
                hi = mid - 1;
            }
        }
        return cps[lo].votingPower;
    }

    function checkpointCount(address account) external view returns (uint256) {
        return _vpCheckpoints[account].length;
    }

    // ============================================================
    // Reward (in BNB, finanziato dal token tramite notifyRewardAmount)
    // ============================================================
    function notifyRewardAmount(uint256 amount) external payable {
        // Anyone can fund the pool (in particular the DaimonV2 token), but
        // the accounted value is always the msg.value actually received, not
        // the amount argument (avoids mismatch/manipulation).
        require(msg.value == amount, "DaimonStaking: value mismatch");
        if (totalVotingPower == 0) {
            // Nobody staked: the funds are queued and distributed at the
            // first notify with voting power > 0 (without this accrual they
            // would stay forever unattributed in the contract).
            undistributedRewards += amount;
            emit RewardNotified(amount);
            return;
        }
        uint256 toDistribute = amount + undistributedRewards;
        undistributedRewards = 0;
        rewardPerVotingPowerStored += (toDistribute * REWARD_PRECISION) / totalVotingPower;
        emit RewardNotified(toDistribute);
    }

    function _settleReward(address user) private {
        uint256 vp = votingPower[user];
        if (vp > 0) {
            uint256 accumulated = (vp * rewardPerVotingPowerStored) / REWARD_PRECISION;
            uint256 pending = accumulated - _userRewardDebt[user];
            if (pending > 0) {
                _userPendingReward[user] += pending;
            }
        }
        _userRewardDebt[user] = (vp * rewardPerVotingPowerStored) / REWARD_PRECISION;
    }

    function pendingReward(address user) external view returns (uint256) {
        uint256 vp = votingPower[user];
        uint256 accumulated = (vp * rewardPerVotingPowerStored) / REWARD_PRECISION;
        uint256 newlyAccrued = accumulated >= _userRewardDebt[user] ? accumulated - _userRewardDebt[user] : 0;
        return _userPendingReward[user] + newlyAccrued;
    }

    function claimReward() external nonReentrant {
        _settleReward(msg.sender);
        uint256 reward = _userPendingReward[msg.sender];
        if (reward == 0) return;
        _userPendingReward[msg.sender] = 0;

        (bool ok, ) = msg.sender.call{value: reward}("");
        require(ok, "DaimonStaking: BNB transfer failed");

        emit RewardClaimed(msg.sender, reward);
    }

    // ============================================================
    // Governance: lock option management (DAO Timelock only)
    // ============================================================
    function addLockOption(uint256 duration, uint256 multiplierX1000) external onlyGovernance {
        require(duration > 0 && multiplierX1000 >= 1000 && multiplierX1000 <= 10000, "DaimonStaking: invalid params");
        lockOptions.push(LockOption(duration, multiplierX1000, true));
        emit LockOptionAdded(duration, multiplierX1000);
    }

    function disableLockOption(uint256 index) external onlyGovernance {
        require(index < lockOptions.length, "DaimonStaking: bad index");
        lockOptions[index].active = false;
        emit LockOptionDisabled(index);
    }

    function setGovernance(address account, bool enabled) external onlyGovernance {
        _setGovernance(account, enabled);
    }

    function lockOptionsLength() external view returns (uint256) {
        return lockOptions.length;
    }

    receive() external payable {}
}
