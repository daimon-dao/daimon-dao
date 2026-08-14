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
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

interface IDaimonV2Token {
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    // Needed by the #32-bis structural guard in stake(): the deposit
    // accounting is only sound while this contract is fee-exempt.
    function isExcludedFromFee(address account) external view returns (bool);
}

contract DaimonStaking is ReentrancyGuard {
    // ---- Governance (bespoke mapping: multiple addresses can be enabled,
    // managed by the DAO Timelock; semantics differ from OZ AccessControl) ----
    mapping(address => bool) private _governance;

    error NotGovernance();

    /// Emitted on every effective change of governance privilege, including
    /// the one granted in the constructor. Indexed on the account so a
    /// monitor can subscribe per address, and the full set of current holders
    /// can be reconstructed from the log history — the private mapping is not
    /// enumerable.
    event GovernanceSet(address indexed account, bool enabled);

    modifier onlyGovernance() {
        if (!_governance[msg.sender]) revert NotGovernance();
        _;
    }

    function _setGovernance(address account, bool enabled) internal {
        // No-op writes emit nothing: an observer must be able to treat every
        // GovernanceSet as a real transition, without filtering duplicates.
        if (_governance[account] == enabled) return;
        _governance[account] = enabled;
        emit GovernanceSet(account, enabled);
    }

    function isGovernance(address account) public view returns (bool) {
        return _governance[account];
    }

    IDaimonV2Token public immutable daimonToken;

    // Only used to refuse it as a recovery destination: sending recovered
    // value there would destroy it a second time.
    address private constant DEAD_ADDRESS = 0x000000000000000000000000000000000000dEaD;

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
    // At each stake/withdraw a (blockNumber, votingPower) pair is recorded,
    // for the account AND for the aggregate total: the Governor reads both
    // at the proposal snapshot (the block BEFORE the proposal's own block),
    // so voting power moved in the proposal's block or later can influence
    // neither the votes nor the quorum denominator (#12).
    //
    // Keyed by block.number, NOT block.timestamp: BSC seals two blocks per
    // second, so two different blocks share one timestamp and a timestamp
    // key cannot tell "before the proposal" from "same block, reacting to
    // it". Lock durations and reward accounting stay on wall-clock time;
    // only the snapshot history is block-based.
    struct Checkpoint {
        uint256 blockNumber;
        uint256 votingPower;
    }

    mapping(address => Checkpoint[]) private _vpCheckpoints;
    Checkpoint[] private _totalVpCheckpoints;

    // ---- Reward pool (funded in BNB by the token's marketing fee) ----
    // Scale 1e27: with voting power up to ~4e30 (4x on a supply of 1e12
    // tokens at 18 decimals), a 1e18 scale would truncate small notifies to
    // zero.
    uint256 private constant REWARD_PRECISION = 1e27;

    uint256 public rewardPerVotingPowerStored; // MasterChef-style accumulator, scaled by REWARD_PRECISION
    // BNB received while totalVotingPower == 0. It NEVER merges into later
    // distributions (#35): folding it into the next notify let the first
    // staker to arrive - even with 1 wei - capture the whole backlog accrued
    // before it existed. Recovery is an explicit governance decision
    // (transferZeroStakerReserve), and the public getter doubles as the
    // DAO's visibility that there is something to recover.
    uint256 public zeroStakerReserve;
    mapping(address => uint256) private _userRewardDebt;
    mapping(address => uint256) private _userPendingReward;

    event Staked(address indexed user, uint256 indexed lockId, uint256 amount, uint256 duration, uint256 votingPowerGranted);
    event Withdrawn(address indexed user, uint256 indexed lockId, uint256 amount);
    event RewardClaimed(address indexed user, uint256 amount);
    event RewardNotified(uint256 amount);
    // Distinct from RewardNotified on purpose: reserved funds are NOT queued
    // for distribution, they wait for an explicit governance decision (#35).
    event RewardReserved(uint256 amount);
    // The deltas are MEASURED before/after the transfer, never assumed: with
    // a reflection token the debited and received amounts need not equal the
    // requested one.
    event SurplusTransferred(address indexed to, uint256 debited, uint256 received);
    event ZeroStakerReserveTransferred(address indexed to, uint256 debited, uint256 received);
    event LockOptionAdded(uint256 duration, uint256 multiplierX1000);
    event LockOptionDisabled(uint256 index);

    error InvalidLockOption();
    error LockStillActive();
    error AlreadyWithdrawn();
    error NotLockOwner();
    error ZeroAmount();
    error StakingNotFeeExempt();
    error InvalidRecipient();
    error AmountExceedsSurplus();
    error AmountExceedsReserve();

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
    /// @notice Locks `amount` for the chosen option and credits the weighted
    /// voting power.
    /// @dev ACCOUNTING INVARIANT (Zenith #10): this function records `amount`
    /// as staked without re-reading the balance actually received. That is
    /// correct ONLY because this contract is exempt from the token's transfer
    /// fee, so the amount received equals the amount requested. The exemption
    /// is therefore not a convenience — it is what makes the recorded
    /// principal true, and what lets withdraw() return it 1:1.
    /// Any upgrade or configuration change MUST preserve it. Since the fix for
    /// Zenith #32 the token enforces this on-chain as well: the exemption
    /// cannot be revoked while totalStakedAmount() > 0.
    function stake(uint256 amount, uint256 lockOptionIndex) external nonReentrant returns (uint256 lockId) {
        if (amount == 0) revert ZeroAmount();
        if (lockOptionIndex >= lockOptions.length || !lockOptions[lockOptionIndex].active) revert InvalidLockOption();
        // Structural guard (#32-bis): the accounting below records `amount`
        // as received, with no balance-delta check - that is only sound
        // while this contract is fee-exempt on the token. The token-side
        // #32 fix prevents revoking the exemption while stake is
        // outstanding, but releases it once totalStakedAmount reaches zero:
        // nothing stopped a NEW deposit while the exemption was off. This
        // refuses the deposit, closing the hole from this side too.
        if (!daimonToken.isExcludedFromFee(address(this))) revert StakingNotFeeExempt();

        _settleReward(msg.sender);

        LockOption memory opt = lockOptions[lockOptionIndex];

        bool ok = daimonToken.transferFrom(msg.sender, address(this), amount);
        require(ok, "DaimonStaking: transferFrom failed");

        // No mulDiv needed here (verified for #31): amount is bounded by the
        // 1e30 total supply and multiplierX1000 by 10_000 (addLockOption), so
        // the product tops out near 1e34 - forty-three orders of magnitude
        // below uint256 overflow.
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

        _writeCheckpoints(msg.sender);

        _userRewardDebt[msg.sender] = Math.mulDiv(votingPower[msg.sender], rewardPerVotingPowerStored, REWARD_PRECISION);

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

        _writeCheckpoints(msg.sender);

        _userRewardDebt[msg.sender] = Math.mulDiv(votingPower[msg.sender], rewardPerVotingPowerStored, REWARD_PRECISION);

        bool ok = daimonToken.transfer(msg.sender, amount);
        require(ok, "DaimonStaking: transfer failed");

        emit Withdrawn(msg.sender, lockId, amount);
    }

    // ============================================================
    // Checkpoint del voting power
    // ============================================================
    function _writeCheckpoints(address account) private {
        _writeCheckpoint(_vpCheckpoints[account], votingPower[account]);
        _writeCheckpoint(_totalVpCheckpoints, totalVotingPower);
    }

    // A same-block update overwrites the last entry. This is safe with the
    // Governor's block-1 snapshot: by the time a snapshot can reference
    // block N, block N is sealed and its checkpoint can no longer be
    // rewritten. (The overwrite WAS finding #12 when the snapshot could
    // point at the still-open key.)
    function _writeCheckpoint(Checkpoint[] storage cps, uint256 value) private {
        uint256 len = cps.length;
        if (len > 0 && cps[len - 1].blockNumber == block.number) {
            cps[len - 1].votingPower = value;
        } else {
            cps.push(Checkpoint({blockNumber: block.number, votingPower: value}));
        }
    }

    // Last checkpoint with blockNumber <= requested; 0 if none. Binary
    // search: O(log n) even with many stake/withdraw.
    function _checkpointLookup(Checkpoint[] storage cps, uint256 blockNumber) private view returns (uint256) {
        uint256 len = cps.length;
        if (len == 0 || cps[0].blockNumber > blockNumber) return 0;
        uint256 lo = 0;
        uint256 hi = len - 1;
        while (lo < hi) {
            uint256 mid = (lo + hi + 1) / 2;
            if (cps[mid].blockNumber <= blockNumber) {
                lo = mid;
            } else {
                hi = mid - 1;
            }
        }
        return cps[lo].votingPower;
    }

    /// @notice Voting power of `account` at block `blockNumber`.
    function votingPowerAt(address account, uint256 blockNumber) external view returns (uint256) {
        return _checkpointLookup(_vpCheckpoints[account], blockNumber);
    }

    /// @notice Aggregate voting power at block `blockNumber`: the quorum
    /// denominator the Governor uses for proposals snapshotted at that block.
    function totalVotingPowerAt(uint256 blockNumber) external view returns (uint256) {
        return _checkpointLookup(_totalVpCheckpoints, blockNumber);
    }

    function checkpointCount(address account) external view returns (uint256) {
        return _vpCheckpoints[account].length;
    }

    function totalCheckpointCount() external view returns (uint256) {
        return _totalVpCheckpoints.length;
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
            // Nobody staked: the funds are set aside and NEVER merged into a
            // later distribution (#35). See the note on zeroStakerReserve.
            zeroStakerReserve += amount;
            emit RewardReserved(amount);
            return;
        }
        // Distribute exactly what this notification carries: nothing is ever
        // distributed retroactively any more. mulDiv for #31 (see
        // _settleReward), and for symmetry with every other accumulator
        // expression.
        rewardPerVotingPowerStored += Math.mulDiv(amount, REWARD_PRECISION, totalVotingPower);
        emit RewardNotified(amount);
    }

    // mulDiv (512-bit intermediate) in every reward expression (#31): voting
    // power can reach ~4e30 and the accumulator grows without bound - one
    // low-power epoch receiving a large notify is enough to push it past the
    // point where vp * accumulator overflows uint256. The naive product then
    // reverts (panic 0x11) inside stake() and withdraw(), permanently
    // locking large stakers out of a NON-UPGRADEABLE contract. mulDiv
    // computes the full 512-bit product before dividing, and floors exactly
    // like the plain expression in every non-overflowing case.
    function _settleReward(address user) private {
        uint256 vp = votingPower[user];
        if (vp > 0) {
            uint256 accumulated = Math.mulDiv(vp, rewardPerVotingPowerStored, REWARD_PRECISION);
            uint256 pending = accumulated - _userRewardDebt[user];
            if (pending > 0) {
                _userPendingReward[user] += pending;
            }
        }
        _userRewardDebt[user] = Math.mulDiv(vp, rewardPerVotingPowerStored, REWARD_PRECISION);
    }

    function pendingReward(address user) external view returns (uint256) {
        uint256 vp = votingPower[user];
        uint256 accumulated = Math.mulDiv(vp, rewardPerVotingPowerStored, REWARD_PRECISION);
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

    /// @notice Moves DMN held ABOVE the staked principal out of the contract
    /// (#33). Surplus accrues from reflection on the staked balance and from
    /// direct transfers; no other function can touch it, so without this it
    /// would be stuck forever.
    /// @dev The recipient is a PARAMETER, not a stored address: this
    /// contract is not upgradeable, so a fixed destination that proved wrong
    /// or obsolete would be irrecoverable. Every call arrives through a
    /// public proposal and the 7-day Timelock, so the destination is visible
    /// long before it can execute. The principal is protected twice: the
    /// amount is checked against the measured surplus before the transfer,
    /// and the remaining balance is re-checked after it.
    function transferSurplus(address to, uint256 amount) external onlyGovernance nonReentrant {
        if (amount == 0) revert ZeroAmount();
        if (to == address(0) || to == address(this) || to == DEAD_ADDRESS) revert InvalidRecipient();

        uint256 balBefore = daimonToken.balanceOf(address(this));
        if (balBefore < totalStakedAmount + amount) revert AmountExceedsSurplus();

        uint256 toBefore = daimonToken.balanceOf(to);
        bool ok = daimonToken.transfer(to, amount);
        require(ok, "DaimonStaking: transfer failed");

        uint256 balAfter = daimonToken.balanceOf(address(this));
        if (balAfter < totalStakedAmount) revert AmountExceedsSurplus();

        emit SurplusTransferred(to, balBefore - balAfter, daimonToken.balanceOf(to) - toBefore);
    }

    /// @notice Recovers the BNB reserved while nobody was staked (#35). Same
    /// shape and same reasoning as transferSurplus: parameterized recipient,
    /// public route through governance and the Timelock, measured deltas.
    function transferZeroStakerReserve(address to, uint256 amount) external onlyGovernance nonReentrant {
        if (amount == 0) revert ZeroAmount();
        if (to == address(0) || to == address(this) || to == DEAD_ADDRESS) revert InvalidRecipient();
        if (amount > zeroStakerReserve) revert AmountExceedsReserve();

        zeroStakerReserve -= amount;

        uint256 selfBefore = address(this).balance;
        uint256 toBefore = to.balance;
        (bool ok, ) = to.call{value: amount}("");
        require(ok, "DaimonStaking: BNB transfer failed");

        emit ZeroStakerReserveTransferred(to, selfBefore - address(this).balance, to.balance - toBefore);
    }

    function lockOptionsLength() external view returns (uint256) {
        return lockOptions.length;
    }

    // NO receive(): BNB must arrive ONLY through notifyRewardAmount(), which
    // is payable and books what it receives into rewardPerVotingPowerStored.
    // A bare receiver accepted BNB that no accounting ever saw: the balance
    // grew while the accumulator did not, breaking the invariant that this
    // contract holds exactly (funded - claimed), and stranding those funds —
    // nothing here can move BNB except claimReward(), which pays out only
    // what the accumulator attributes.
    //
    // Verified before removing: DaimonV2 funds the pool exclusively via
    // notifyRewardAmount{value: ...} in _swapAccumulatedFees, never with a
    // bare transfer, so no legitimate path depended on this function.
    // Accidental sends now bounce back to the sender instead of being trapped.
}
