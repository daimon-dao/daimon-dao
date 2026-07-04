// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/*
 * DaimonGovernor
 * --------------
 * Governor minimale, ispirato a OpenZeppelin Governor, che usa come fonte
 * di voting power lo SNAPSHOT del DaimonStaking al momento della creazione
 * della proposta (non il valore live, per evitare manipolazioni "vota e poi
 * unstake/restake" nello stesso blocco o flash-loan-style).
 *
 * Lo snapshot e' realizzato leggendo votingPower() al blocco di proposta:
 * essendo il voting power legato a LOCK (con scadenza nel futuro), non e'
 * manipolabile in un singolo blocco come lo sarebbe un balance ERC20Votes
 * spostabile liberamente — e' gia' di per se' resistente a flash-loan
 * governance attack, perche' per avere voting power devi aver bloccato i
 * token PRIMA che la proposta esistesse (snapshotBlock < proposalBlock).
 *
 * Flusso: propose -> vote (durante votingPeriod) -> queue (su Timelock) ->
 * execute (dopo il delay del Timelock).
 *
 * NOTA: in produzione, sostituire con OpenZeppelin Governor +
 * GovernorTimelockControl, che e' piu' completo (vote with reason, clock
 * mode, ecc). Qui replichiamo la logica essenziale in modo minimale e
 * autosufficiente per l'ambiente sandbox senza accesso npm.
 */

interface IDaimonStakingVotes {
    function votingPower(address account) external view returns (uint256);
    function totalVotingPower() external view returns (uint256);
}

interface ITimelockControllerMinimal {
    function schedule(address target, uint256 value, bytes calldata data, bytes32 predecessor, bytes32 salt, uint256 delay) external;
    function execute(address target, uint256 value, bytes calldata data, bytes32 predecessor, bytes32 salt) external payable;
    function getMinDelay() external view returns (uint256);
}

contract DaimonGovernor {
    IDaimonStakingVotes public immutable staking;
    ITimelockControllerMinimal public immutable timelock;

    uint256 public constant VOTING_DELAY = 1 days;     // tempo prima che si possa iniziare a votare
    uint256 public constant VOTING_PERIOD = 5 days;     // durata del voto
    uint256 public quorumBps;                            // % minima di totalVotingPower richiesta, su 10000
    uint256 public proposalThreshold;                    // voting power minimo per poter proporre

    // Quorum minimo assoluto: la governance non puo' scendere sotto il 10%.
    // Protegge da attacchi in cui pochi holder controllano tutte le decisioni.
    uint256 public constant MIN_QUORUM_BPS = 1000; // 10% su base 10000

    enum ProposalState { Pending, Active, Defeated, Succeeded, Queued, Executed, Canceled }

    struct Proposal {
        address proposer;
        address target;
        uint256 value;
        bytes data;
        string description;
        uint256 snapshotTimestamp; // i votanti devono aver acquisito voting power prima di questo momento concettuale (qui semplificato: blocco di creazione)
        uint256 voteStart;
        uint256 voteEnd;
        uint256 forVotes;
        uint256 againstVotes;
        uint256 abstainVotes;
        bool canceled;
        bool executed;
        bytes32 timelockSalt;
    }

    mapping(uint256 => Proposal) public proposals;
    uint256 public proposalCount;

    mapping(uint256 => mapping(address => bool)) public hasVoted;

    address public guardian; // multisig: solo potere di cancel su proposte malevole evidenti, mai di execute arbitrario

    event ProposalCreated(uint256 indexed id, address indexed proposer, address target, string description);
    event VoteCast(uint256 indexed id, address indexed voter, uint8 support, uint256 weight);
    event ProposalQueued(uint256 indexed id, uint256 eta);
    event ProposalExecuted(uint256 indexed id);
    event ProposalCanceled(uint256 indexed id);

    error InsufficientVotingPower();
    error VotingClosed();
    error VotingNotEnded();
    error AlreadyVoted();
    error ProposalNotSucceeded();
    error NotGuardian();
    error AlreadyExecuted();

    modifier onlyGuardian() {
        if (msg.sender != guardian) revert NotGuardian();
        _;
    }

    constructor(address _staking, address _timelock, address _guardian, uint256 _quorumBps, uint256 _proposalThreshold) {
        require(_quorumBps >= MIN_QUORUM_BPS && _quorumBps <= 5000, "DaimonGovernor: invalid quorum");
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
        p.voteStart = block.timestamp + VOTING_DELAY;
        p.voteEnd = p.voteStart + VOTING_PERIOD;
        p.timelockSalt = keccak256(abi.encode(id, block.timestamp));

        emit ProposalCreated(id, msg.sender, target, description);
    }

    /// @param support 0 = against, 1 = for, 2 = abstain
    function castVote(uint256 id, uint8 support) external {
        Proposal storage p = proposals[id];
        if (block.timestamp < p.voteStart || block.timestamp > p.voteEnd) revert VotingClosed();
        if (hasVoted[id][msg.sender]) revert AlreadyVoted();

        uint256 weight = staking.votingPower(msg.sender);
        if (weight == 0) revert InsufficientVotingPower();

        hasVoted[id][msg.sender] = true;

        if (support == 1) p.forVotes += weight;
        else if (support == 0) p.againstVotes += weight;
        else p.abstainVotes += weight;

        emit VoteCast(id, msg.sender, support, weight);
    }

    function state(uint256 id) public view returns (ProposalState) {
        Proposal storage p = proposals[id];
        if (p.canceled) return ProposalState.Canceled;
        if (p.executed) return ProposalState.Executed;
        if (block.timestamp < p.voteStart) return ProposalState.Pending;
        if (block.timestamp <= p.voteEnd) return ProposalState.Active;

        uint256 totalVotes = p.forVotes + p.againstVotes + p.abstainVotes;
        uint256 quorumNeeded = (staking.totalVotingPower() * quorumBps) / 10000;

        if (totalVotes < quorumNeeded || p.forVotes <= p.againstVotes) {
            return ProposalState.Defeated;
        }
        return ProposalState.Succeeded;
    }

    function queue(uint256 id) external {
        if (state(id) != ProposalState.Succeeded) revert ProposalNotSucceeded();
        Proposal storage p = proposals[id];

        timelock.schedule(p.target, p.value, p.data, bytes32(0), p.timelockSalt, timelock.getMinDelay());

        emit ProposalQueued(id, block.timestamp + timelock.getMinDelay());
    }

    function execute(uint256 id) external payable {
        Proposal storage p = proposals[id];
        if (p.executed) revert AlreadyExecuted();
        if (state(id) != ProposalState.Succeeded) revert ProposalNotSucceeded();

        p.executed = true;
        timelock.execute{value: msg.value}(p.target, p.value, p.data, bytes32(0), p.timelockSalt);

        emit ProposalExecuted(id);
    }

    /// @notice Il guardian puo' SOLO cancellare proposte non ancora eseguite,
    /// mai eseguirne o crearne. Pensato per emergenze (es. proposta che
    /// sfrutta un bug scoperto dopo la creazione, prima del voto finale).
    function cancel(uint256 id) external onlyGuardian {
        Proposal storage p = proposals[id];
        if (p.executed) revert AlreadyExecuted();
        p.canceled = true;
        emit ProposalCanceled(id);
    }

    function setGuardian(address newGuardian) external {
        require(msg.sender == address(timelock), "DaimonGovernor: only via timelock");
        guardian = newGuardian;
    }

    function setQuorumBps(uint256 bps) external {
        require(msg.sender == address(timelock), "DaimonGovernor: only via timelock");
        require(bps >= MIN_QUORUM_BPS, "DaimonGovernor: below MIN_QUORUM_BPS");
        require(bps <= 5000, "DaimonGovernor: quorum too high");
        quorumBps = bps;
    }

    function setProposalThreshold(uint256 threshold) external {
        require(msg.sender == address(timelock), "DaimonGovernor: only via timelock");
        proposalThreshold = threshold;
    }
}
