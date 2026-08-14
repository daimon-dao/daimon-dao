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
 * style): at proposal creation, snapshotTimestamp and snapshotTotalVotingPower
 * are stored; castVote() reads the voter's voting power at that instant via
 * staking.votingPowerAt(voter, snapshotTimestamp), and the quorum in state()
 * uses the total at the snapshot. It follows that to vote on a proposal you
 * must have locked the tokens BEFORE (or in the same block as) its creation:
 * later stakes do not count, neither for votes nor for quorum — resistant
 * both to flash-loans and to late purchases aimed at an already-visible
 * proposal.
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
    function votingPowerAt(address account, uint256 timestamp) external view returns (uint256);
    function totalVotingPower() external view returns (uint256);
}

interface ITimelockControllerMinimal {
    function schedule(address target, uint256 value, bytes calldata data, bytes32 predecessor, bytes32 salt, uint256 delay) external;
    function execute(address target, uint256 value, bytes calldata data, bytes32 predecessor, bytes32 salt) external payable;
    function getMinDelay() external view returns (uint256);
    // Needed to reflect a cancellation performed directly on the Timelock
    // (#26). hashOperation is used rather than recomputing the hash here, so
    // the Timelock stays the single source of truth for the id formula.
    function hashOperation(address target, uint256 value, bytes calldata data, bytes32 predecessor, bytes32 salt) external pure returns (bytes32);
    function operations(bytes32 id) external view returns (uint256 readyTimestamp, bool executed, bool canceled);
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

    enum ProposalState { Pending, Active, Defeated, Succeeded, Queued, Executed, Canceled }

    struct Proposal {
        address proposer;
        address target;
        uint256 value;
        bytes data;
        string description;
        uint256 snapshotTimestamp; // voters must have acquired voting power before this conceptual moment (here simplified: creation block)
        // totalVotingPower at creation time: quorum is computed on this
        // snapshot, not on the live value, so stake/unstake after the
        // proposal cannot alter the threshold.
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
    error NotGuardian();
    error AlreadyExecuted();
    error InvalidSupport();
    error ProposalDoesNotExist();
    error ProposalIsCanceled();

    modifier onlyGuardian() {
        if (msg.sender != guardian) revert NotGuardian();
        _;
    }

    constructor(address _staking, address _timelock, address _guardian, uint256 _quorumBps, uint256 _proposalThreshold) {
        require(_quorumBps >= MIN_QUORUM_BPS && _quorumBps <= 5000, "DaimonGovernor: invalid quorum");
        require(
            _staking != address(0) && _timelock != address(0) && _guardian != address(0),
            "DaimonGovernor: zero address"
        );
        staking = IDaimonStakingVotes(_staking);
        timelock = ITimelockControllerMinimal(_timelock);
        guardian = _guardian;
        quorumBps = _quorumBps;               // 1000 = 10%
        proposalThreshold = _proposalThreshold;
    }

    function propose(address target, uint256 value, bytes calldata data, string calldata description) external returns (uint256 id) {
        if (staking.votingPower(msg.sender) < proposalThreshold) revert InsufficientVotingPower();

        id = proposalCount++;
        Proposal storage p = proposals[id];
        p.proposer = msg.sender;
        p.target = target;
        p.value = value;
        p.data = data;
        p.description = description;
        p.snapshotTimestamp = block.timestamp;
        p.snapshotTotalVotingPower = staking.totalVotingPower();
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

        // Weight at the proposal SNAPSHOT, not live: whoever stakes after
        // creation cannot vote on this proposal.
        uint256 weight = staking.votingPowerAt(msg.sender, p.snapshotTimestamp);
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
        uint256 quorumNeeded = (p.snapshotTotalVotingPower * quorumBps) / 10000;

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

    function queue(uint256 id) external {
        if (state(id) != ProposalState.Succeeded) revert ProposalNotSucceeded();
        Proposal storage p = proposals[id];

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
        Proposal storage p = proposals[id];
        if (p.executed) revert AlreadyExecuted();
        p.canceled = true;
        emit ProposalCanceled(id);
    }

    function setGuardian(address newGuardian) external {
        require(msg.sender == address(timelock), "DaimonGovernor: only via timelock");
        require(newGuardian != address(0), "DaimonGovernor: zero address");
        guardian = newGuardian;
        emit GuardianSet(newGuardian);
    }

    function setQuorumBps(uint256 bps) external {
        require(msg.sender == address(timelock), "DaimonGovernor: only via timelock");
        require(bps >= MIN_QUORUM_BPS, "DaimonGovernor: below MIN_QUORUM_BPS");
        require(bps <= 5000, "DaimonGovernor: quorum too high");
        quorumBps = bps;
        emit QuorumBpsSet(bps);
    }

    function setProposalThreshold(uint256 threshold) external {
        require(msg.sender == address(timelock), "DaimonGovernor: only via timelock");
        proposalThreshold = threshold;
        emit ProposalThresholdSet(threshold);
    }
}
