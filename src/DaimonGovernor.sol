// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/*
 * DaimonGovernor
 * --------------
 * Minimal Governor, inspired by OpenZeppelin Governor, that uses as its
 * voting-power source the DaimonStaking SNAPSHOT at the time the proposal is
 * created (not the live value, to prevent "vote then unstake/restake"
 * manipulation in the same block or flash-loan-style attacks).
 *
 * The snapshot is realized with DaimonStaking's CHECKPOINTs (OZ Votes
 * style), keyed by BLOCK NUMBER: at proposal creation, snapshotBlock is set
 * to block.number - 1 and snapshotTotalVotingPower to the aggregate voting
 * power at that block; castVote() reads the voter's power at snapshotBlock
 * via staking.votingPowerAt(voter, snapshotBlock), and the quorum in state()
 * uses the total at the same block. It follows that to vote on a proposal
 * you must have locked the tokens in a block STRICTLY BEFORE its creation:
 * a stake in the proposal's own block or later counts for nothing, neither
 * votes nor quorum (#12).
 *
 * Why block.number - 1 and not the creation timestamp: BSC seals two blocks
 * per second, so a timestamp cannot separate "before the proposal" from
 * "same block, reacting to it"; and the previous block is already sealed
 * when the proposal lands, so its checkpoints can never be rewritten. The
 * only residual window is staking in a block strictly before a propose
 * still sitting in the mempool — economically identical to staking before
 * an announced proposal, and dwarfed by the 1-day VOTING_DELAY.
 *
 * The quorum bps is also captured per proposal at creation (#37): changing
 * quorumBps mid-flight does not retroactively change the threshold an
 * existing proposal is judged against.
 *
 * Flow: propose -> vote (during votingPeriod) -> queue (on Timelock) ->
 * execute (after the Timelock delay).
 *
 * NOTE: in production, replace with OpenZeppelin Governor +
 * GovernorTimelockControl, which is more complete (vote with reason, clock
 * mode, etc). Here we replicate the essential logic in a minimal,
 * self-contained way for the sandbox environment without npm access.
 */

interface IDaimonStakingVotes {
    function votingPower(address account) external view returns (uint256);
    function votingPowerAt(address account, uint256 blockNumber) external view returns (uint256);
    function totalVotingPowerAt(uint256 blockNumber) external view returns (uint256);
}

interface ITimelockControllerMinimal {
    function schedule(address target, uint256 value, bytes calldata data, bytes32 predecessor, bytes32 salt, uint256 delay) external;
    function execute(address target, uint256 value, bytes calldata data, bytes32 predecessor, bytes32 salt) external payable;
    function getMinDelay() external view returns (uint256);
    // Needed to reflect a cancellation performed directly on the Timelock,
    // and for the atomic cross-cancel (#26). hashOperation is used rather
    // than recomputing the hash here, so the Timelock stays the single
    // source of truth for the id formula; operations() lets both state()
    // and cancel() reconcile with an operation already canceled or executed
    // directly.
    function hashOperation(address target, uint256 value, bytes calldata data, bytes32 predecessor, bytes32 salt) external pure returns (bytes32);
    function operations(bytes32 id) external view returns (uint256 readyTimestamp, bool executed, bool canceled);
    function cancel(bytes32 id) external;
}

contract DaimonGovernor {
    IDaimonStakingVotes public immutable staking;
    ITimelockControllerMinimal public immutable timelock;

    uint256 public constant VOTING_DELAY = 1 days;     // time before voting can begin
    uint256 public constant VOTING_PERIOD = 5 days;     // voting duration
    uint256 public quorumBps;                            // minimum % of totalVotingPower required, out of 10000
    uint256 public proposalThreshold;                    // minimum voting power required to propose

    // Absolute minimum quorum: governance cannot go below 10%.
    // Protects against attacks where a few holders control every decision.
    uint256 public constant MIN_QUORUM_BPS = 1000; // 10% su base 10000

    // Absolute maximum proposal threshold. Without it, a threshold above the
    // voting power any account can ever hold would make it impossible to
    // create the very proposal needed to lower it again: governance
    // permanently frozen, with no recovery path.
    //
    // The bound is a policy on governance accessibility, not the theoretical
    // limit. It is DaimonV2.MIN_SUPPLY / 100 — one percent of the supply
    // floor, the only quantity in this system that can never change. Written
    // out here rather than imported, because this Governor deliberately
    // depends on no token contract; the derivation is kept explicit so the
    // policy stays readable:
    //   MIN_SUPPLY = 21_000_000_000e18  ->  MAX_PROPOSAL_THRESHOLD = 210_000_000e18
    //
    // At today's ~1000B supply that is 0.005% of it (52.5M tokens locked at
    // 4x); in the terminal scenario, with supply burnt down to the floor, it
    // is 1% at 1x — reachable by a coalition, never a gate. Against the
    // ~10T maximum attributable voting power it is 0.002%. The deployed
    // threshold is 1000e18, so governance keeps five orders of magnitude of
    // room: this excludes only the unrecoverable region.
    uint256 public constant MAX_PROPOSAL_THRESHOLD = (21_000_000_000 * 10 ** 18) / 100;

    enum ProposalState { Pending, Active, Defeated, Succeeded, Queued, Executed, Canceled }

    struct Proposal {
        address proposer;
        address target;
        uint256 value;
        bytes data;
        string description;
        // The block BEFORE the proposal's own: voters must have acquired
        // voting power in a block <= snapshotBlock. Stakes in the proposal's
        // block (even earlier in it) or later count for nothing (#12).
        uint256 snapshotBlock;
        // Aggregate voting power at snapshotBlock: the quorum denominator.
        // Computed on the same sealed block as the voter weights, so
        // stake/unstake after the proposal can alter neither side of the
        // quorum fraction.
        uint256 snapshotTotalVotingPower;
        uint256 voteStart;
        uint256 voteEnd;
        uint256 forVotes;
        uint256 againstVotes;
        uint256 abstainVotes;
        bool canceled;
        bool executed;
        bool queued;
        bytes32 timelockSalt;
        // Quorum bps captured at creation (#37). Appended last so the
        // proposals(id) tuple keeps its existing field order for consumers.
        uint256 quorumBpsSnapshot;
    }

    mapping(uint256 => Proposal) public proposals;
    uint256 public proposalCount;

    mapping(uint256 => mapping(address => bool)) public hasVoted;

    address public guardian; // multisig: only the power to cancel clearly malicious proposals, never arbitrary execute

    event ProposalCreated(uint256 indexed id, address indexed proposer, address target, string description);
    event VoteCast(uint256 indexed id, address indexed voter, uint8 support, uint256 weight);
    event ProposalQueued(uint256 indexed id, uint256 eta);
    event ProposalExecuted(uint256 indexed id);
    event ProposalCanceled(uint256 indexed id);
    event GuardianSet(address indexed newGuardian);
    event QuorumBpsSet(uint256 bps);
    event ProposalThresholdSet(uint256 threshold);

    error InsufficientVotingPower();
    error VotingClosed();
    error VotingNotEnded();
    error AlreadyVoted();
    error ProposalNotSucceeded();
    error ProposalNotQueued();
    error ProposalAlreadyQueued();
    error NotGuardian();
    error AlreadyExecuted();
    error InvalidSupport();
    error ProposalDoesNotExist();
    error ProposalAlreadyCanceled();
    error ProposalIsCanceled();
    error GuardianAuthorityExpired();

    // The single guardian-mandate deadline (#36): the same instant as the
    // token's guardianExpiry and the Timelock's guardianAuthorityExpiry,
    // passed in by the deploy script and asserted equal across the three.
    // Immutable so no path — upgrade, rotation, governance — can extend it.
    uint256 public immutable guardianAuthorityExpiry;

    modifier onlyGuardian() {
        if (msg.sender != guardian) revert NotGuardian();
        _;
    }

    constructor(address _staking, address _timelock, address _guardian, uint256 _quorumBps, uint256 _proposalThreshold, uint256 _guardianAuthorityExpiry) {
        require(_quorumBps >= MIN_QUORUM_BPS && _quorumBps <= 5000, "DaimonGovernor: invalid quorum");
        require(_proposalThreshold <= MAX_PROPOSAL_THRESHOLD, "DaimonGovernor: threshold too high");
        require(
            _staking != address(0) && _timelock != address(0) && _guardian != address(0),
            "DaimonGovernor: zero address"
        );
        require(_guardianAuthorityExpiry > block.timestamp, "DaimonGovernor: expiry in the past");
        staking = IDaimonStakingVotes(_staking);
        timelock = ITimelockControllerMinimal(_timelock);
        guardian = _guardian;
        quorumBps = _quorumBps;               // 1000 = 10%
        proposalThreshold = _proposalThreshold;
        guardianAuthorityExpiry = _guardianAuthorityExpiry;
    }

    function propose(address target, uint256 value, bytes calldata data, string calldata description) external returns (uint256 id) {
        // Deliberately the LIVE voting power, not the snapshot: stake()
        // locks for >= 30 days with no same-transaction exit, so this is
        // real locked capital (flash-loan-proof), and a same-block stake
        // buys nothing downstream — the block-1 snapshot excludes it from
        // votes and quorum alike. Snapshotting the threshold too would only
        // break "stake then propose" within one block, a pure UX loss.
        if (staking.votingPower(msg.sender) < proposalThreshold) revert InsufficientVotingPower();

        // Snapshot at the PREVIOUS block: already sealed when the proposal
        // lands, so its checkpoints are final and nothing that happens in
        // the proposal's own block (including earlier transactions in it)
        // can reach back into the snapshot (#12).
        uint256 snapshotBlock = block.number - 1;

        id = proposalCount++;
        Proposal storage p = proposals[id];
        p.proposer = msg.sender;
        p.target = target;
        p.value = value;
        p.data = data;
        p.description = description;
        p.snapshotBlock = snapshotBlock;
        p.snapshotTotalVotingPower = staking.totalVotingPowerAt(snapshotBlock);
        p.quorumBpsSnapshot = quorumBps;
        p.voteStart = block.timestamp + VOTING_DELAY;
        p.voteEnd = p.voteStart + VOTING_PERIOD;
        p.timelockSalt = keccak256(abi.encode(id, block.timestamp));

        emit ProposalCreated(id, msg.sender, target, description);
    }

    /// @param support 0 = against, 1 = for, 2 = abstain
    function castVote(uint256 id, uint8 support) external {
        if (support > 2) revert InvalidSupport();
        Proposal storage p = proposals[id];
        // A cancelled proposal takes no more votes: counting them would keep
        // producing tallies for something that can never execute, and would
        // let a cancelled proposal look alive in the interface.
        if (p.canceled) revert ProposalIsCanceled();
        if (block.timestamp < p.voteStart || block.timestamp > p.voteEnd) revert VotingClosed();
        if (hasVoted[id][msg.sender]) revert AlreadyVoted();

        // Weight at the proposal SNAPSHOT (the sealed block before the
        // proposal's), not live: whoever stakes in the proposal's block or
        // later cannot vote on this proposal (#12).
        uint256 weight = staking.votingPowerAt(msg.sender, p.snapshotBlock);
        if (weight == 0) revert InsufficientVotingPower();

        hasVoted[id][msg.sender] = true;

        if (support == 1) p.forVotes += weight;
        else if (support == 0) p.againstVotes += weight;
        else p.abstainVotes += weight;

        emit VoteCast(id, msg.sender, support, weight);
    }

    /// @dev Reports a single, consistent view of the proposal:
    ///  - an id that was never allocated is rejected instead of resolving to
    ///    an empty struct that reads as a real Pending proposal (#22);
    ///  - Queued is actually returned, instead of a queued proposal still
    ///    reading as Succeeded;
    ///  - a cancellation performed DIRECTLY on the Timelock is reflected here,
    ///    so the two contracts can no longer disagree about whether the
    ///    proposal is still alive (#26).
    function state(uint256 id) public view returns (ProposalState) {
        if (id >= proposalCount) revert ProposalDoesNotExist();
        Proposal storage p = proposals[id];
        if (p.canceled) return ProposalState.Canceled;
        if (p.executed) return ProposalState.Executed;
        if (block.timestamp < p.voteStart) return ProposalState.Pending;
        if (block.timestamp <= p.voteEnd) return ProposalState.Active;

        // Quorum on for + abstain, EXCLUDING against (aligned with
        // OpenZeppelin GovernorCountingSimple). Counting against-votes in the
        // quorum would create a perverse incentive: opposing could push a
        // proposal over quorum and pass it, while staying silent would deny
        // it. By excluding against, voting no never helps clear the threshold.
        uint256 quorumVotes = p.forVotes + p.abstainVotes;
        // Both sides of the fraction are snapshots taken at creation: the
        // denominator at snapshotBlock, the bps as it was then (#37). A
        // quorum change enacted while this proposal is in flight does not
        // retroactively move its bar.
        uint256 quorumNeeded = (p.snapshotTotalVotingPower * p.quorumBpsSnapshot) / 10000;

        if (quorumVotes < quorumNeeded || p.forVotes <= p.againstVotes) {
            return ProposalState.Defeated;
        }

        if (p.queued) {
            // A CANCELLER can cancel the scheduled operation directly on the
            // Timelock. Without reading that flag the Governor would keep
            // reporting a live proposal for an operation that can never
            // execute — the divergence this finding is about.
            bytes32 opId = timelock.hashOperation(p.target, p.value, p.data, bytes32(0), p.timelockSalt);
            (,, bool operationCanceled) = timelock.operations(opId);
            if (operationCanceled) return ProposalState.Canceled;
            return ProposalState.Queued;
        }

        return ProposalState.Succeeded;
    }

    /// @dev state() has no Queued branch: a queued proposal still reads as
    /// Succeeded, so without the p.queued guard a second queue() would reach
    /// the Timelock and only be stopped there by OperationAlreadyScheduled.
    /// The Governor must reject it itself, at its own level, rather than
    /// depending on an implementation detail of the contract it calls.
    function queue(uint256 id) external {
        Proposal storage p = proposals[id];
        // Checked BEFORE the state() gate: state() reports Queued for a
        // scheduled proposal (#26), so a second queue() would otherwise
        // surface as ProposalNotSucceeded and lose the precise error (#7).
        if (p.queued) revert ProposalAlreadyQueued();
        if (state(id) != ProposalState.Succeeded) revert ProposalNotSucceeded();

        p.queued = true;
        timelock.schedule(p.target, p.value, p.data, bytes32(0), p.timelockSalt, timelock.getMinDelay());

        emit ProposalQueued(id, block.timestamp + timelock.getMinDelay());
    }

    function execute(uint256 id) external payable {
        Proposal storage p = proposals[id];
        if (p.executed) revert AlreadyExecuted();
        // state() now reports Queued for a proposal that went through queue(),
        // so THAT is the executable state. Succeeded means it passed but was
        // never scheduled: it still owes the Timelock delay, which is the
        // public reaction window, hence the distinct error. Anything else is
        // not executable at all.
        ProposalState current = state(id);
        if (current == ProposalState.Succeeded) revert ProposalNotQueued();
        if (current != ProposalState.Queued) revert ProposalNotSucceeded();

        p.executed = true;
        timelock.execute{value: msg.value}(p.target, p.value, p.data, bytes32(0), p.timelockSalt);

        emit ProposalExecuted(id);
    }

    /// @notice The guardian can ONLY cancel proposals not yet executed, never
    /// execute or create them. Meant for emergencies (e.g. a proposal that
    /// exploits a bug discovered after creation, before the final vote).
    function cancel(uint256 id) external onlyGuardian {
        // The mandate ends at guardianAuthorityExpiry (#36): after it this
        // function is dead for whoever holds the guardian seat, and with the
        // Timelock's twin gate the governance pipeline becomes uncancellable
        // by any single authority — recovery proposals always execute.
        if (block.timestamp >= guardianAuthorityExpiry) revert GuardianAuthorityExpired();
        // An id not yet allocated must be rejected: propose() does not reset
        // p.canceled, so pre-canceling a future id would make that proposal
        // dead on arrival — and the flag would outlive the guardian that set
        // it, since nothing clears it when the guardian is replaced.
        if (id >= proposalCount) revert ProposalDoesNotExist();
        Proposal storage p = proposals[id];
        if (p.executed) revert AlreadyExecuted();
        if (p.canceled) revert ProposalAlreadyCanceled();

        // Atomic cross-cancel (#26): a queued proposal has a scheduled
        // Timelock operation, and the two flags must never disagree about
        // executability. Without this, the operation would stay scheduled and
        // a future additional EXECUTOR (a configuration governance may
        // legitimately adopt) could execute what the Governor reports as
        // canceled.
        if (p.queued) {
            bytes32 opId = timelock.hashOperation(p.target, p.value, p.data, bytes32(0), p.timelockSalt);
            (, bool opExecuted, bool opCanceled) = timelock.operations(opId);
            // Executed directly at the Timelock: the action already happened
            // on-chain — reporting it canceled here would create the very
            // divergence this fix removes.
            if (opExecuted) revert AlreadyExecuted();
            // Already canceled directly at the Timelock (the guardian's
            // independent path, kept by design): converge the flags without
            // re-canceling — the Timelock rejects a double cancel.
            if (!opCanceled) {
                timelock.cancel(opId);
            }
        }

        p.canceled = true;
        emit ProposalCanceled(id);
    }

    function setGuardian(address newGuardian) external {
        require(msg.sender == address(timelock), "DaimonGovernor: only via timelock");
        require(newGuardian != address(0), "DaimonGovernor: zero address");
        guardian = newGuardian;
        emit GuardianSet(newGuardian);
    }

    // #37: applies only to proposals created AFTER the change; proposals in
    // flight keep the bps captured at creation (quorumBpsSnapshot).
    function setQuorumBps(uint256 bps) external {
        require(msg.sender == address(timelock), "DaimonGovernor: only via timelock");
        require(bps >= MIN_QUORUM_BPS, "DaimonGovernor: below MIN_QUORUM_BPS");
        require(bps <= 5000, "DaimonGovernor: quorum too high");
        quorumBps = bps;
        emit QuorumBpsSet(bps);
    }

    function setProposalThreshold(uint256 threshold) external {
        require(msg.sender == address(timelock), "DaimonGovernor: only via timelock");
        require(threshold <= MAX_PROPOSAL_THRESHOLD, "DaimonGovernor: threshold too high");
        proposalThreshold = threshold;
        emit ProposalThresholdSet(threshold);
    }
}
