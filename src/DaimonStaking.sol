// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/*
 * DaimonStaking
 * -------------
 * Stake-i DaimonV2 con un lock-time a scelta: piu' lungo il lock, piu'
 * voting power ottieni (stile vote-escrow / veCRV), oltre a un reward in
 * ETH proporzionale (finanziato dalla marketing fee del token).
 *
 * Il voting power NON deriva dal balance ERC20 generico (incompatibile con
 * la reflection del token, vedi spiegazione nel resto della conversazione),
 * ma esclusivamente da quanto e per quanto tempo hai bloccato qui.
 *
 * Sicurezza:
 *  - ReentrancyGuard su tutte le funzioni che muovono fondi
 *  - Checks-effects-interactions ovunque
 *  - Nessun loop su array di lunghezza utente-controllata in funzioni
 *    pubbliche (ogni lock e' un record indicizzato per id, non in array)
 *  - Cooldown per l'unstake proporzionale al lock scelto: chi sceglie lock
 *    lungo non puo' uscire prima della scadenza; al termine del lock,
 *    withdraw immediato (nessun cooldown aggiuntivo, il lock stesso E' il
 *    cooldown)
 */

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

interface IDaimonV2Token {
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

contract DaimonStaking is ReentrancyGuard {
    // ---- Governance (mapping bespoke: piu' indirizzi abilitabili, gestito
    // dal Timelock della DAO; semantica diversa da OZ AccessControl) ----
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

    // Lock options: durata in secondi => moltiplicatore voting power (x1000)
    // Esempio: 30 giorni = peso 1.0x, 365 giorni = peso 4.0x
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
        // Voting power accreditato allo stake: withdraw sottrae ESATTAMENTE
        // questo valore, mai un ricalcolo (se la formula del vp cambiasse in
        // un upgrade, un ricalcolo divergerebbe e corromperebbe i totali).
        uint256 votingPowerGranted;
        bool withdrawn;
    }

    mapping(uint256 => Lock) public locks;
    uint256 public nextLockId;

    mapping(address => uint256) public votingPower;     // somma pesata di tutti i lock attivi dell'utente
    mapping(address => uint256) public totalStaked;     // somma capitale (non pesata) dell'utente

    uint256 public totalVotingPower;
    uint256 public totalStakedAmount;

    // ---- Checkpoint del voting power (stile OZ Votes) ----
    // Ad ogni stake/withdraw viene registrato (timestamp, votingPower):
    // il Governor legge il voting power allo snapshot della proposta via
    // votingPowerAt(), cosi' token stakati DOPO la creazione di una
    // proposta non possono votarla.
    struct Checkpoint {
        uint256 timestamp;
        uint256 votingPower;
    }

    mapping(address => Checkpoint[]) private _vpCheckpoints;

    // ---- Reward pool (finanziato in BNB dalla marketing fee del token) ----
    // Scala 1e27: con voting power fino a ~4e30 (4x su supply da 1e12 token
    // a 18 decimali) la scala 1e18 troncherebbe a zero i notify piccoli.
    uint256 private constant REWARD_PRECISION = 1e27;

    uint256 public rewardPerVotingPowerStored; // accumulatore stile MasterChef, scalato per REWARD_PRECISION
    // BNB ricevuti quando totalVotingPower == 0: vengono accodati e
    // distribuiti al primo notify con staker presenti.
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

    constructor(address _daimonToken, address _governance) {
        daimonToken = IDaimonV2Token(_daimonToken);
        _setGovernance(_governance, true);

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

    /// @notice Voting power di `account` all'istante `timestamp` (ultimo
    /// checkpoint con timestamp <= richiesto; 0 se nessuno). Ricerca binaria:
    /// O(log n) anche con molti stake/withdraw.
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
        // Chiunque puo' finanziare il pool (in particolare il token DaimonV2),
        // ma il valore contabilizzato e' sempre msg.value effettivamente
        // ricevuto, non l'argomento amount (evita mismatch/manipolazione).
        require(msg.value == amount, "DaimonStaking: value mismatch");
        if (totalVotingPower == 0) {
            // Nessuno stakato: i fondi vengono accodati e distribuiti al
            // primo notify con voting power > 0 (senza questo accumulo
            // resterebbero per sempre non attribuiti nel contratto).
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
    // Governance: gestione lock options (solo Timelock DAO)
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
