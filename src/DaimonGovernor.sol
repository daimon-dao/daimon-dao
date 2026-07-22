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
 * Lo snapshot e' realizzato con i CHECKPOINT del DaimonStaking (stile OZ
 * Votes): alla creazione della proposta vengono salvati snapshotTimestamp
 * e snapshotTotalVotingPower; castVote() legge il voting power del votante
 * a quell'istante via staking.votingPowerAt(voter, snapshotTimestamp), e
 * il quorum in state() usa il totale allo snapshot. Ne segue che per
 * votare una proposta devi aver bloccato i token PRIMA (o nello stesso
 * blocco) della sua creazione: stake successivi non contano, ne' per i
 * voti ne' per il quorum — resistente sia a flash-loan sia ad acquisti
 * tardivi mirati a una proposta gia' visibile.
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
    function votingPowerAt(address account, uint256 timestamp) external view returns (uint256);
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
        // totalVotingPower al momento della creazione: il quorum si calcola
        // su questo snapshot, non sul valore live, cosi' stake/unstake
        // successivi alla proposta non possono alterare la soglia.
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

    address public guardian; // multisig: solo potere di cancel su proposte malevole evidenti, mai di execute arbitrario

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
        if (block.timestamp < p.voteStart || block.timestamp > p.voteEnd) revert VotingClosed();
        if (hasVoted[id][msg.sender]) revert AlreadyVoted();

        // Peso allo SNAPSHOT della proposta, non live: chi staka dopo la
        // creazione non puo' votare questa proposta.
        uint256 weight = staking.votingPowerAt(msg.sender, p.snapshotTimestamp);
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

        // Quorum su for + abstain, ESCLUDENDO against (allineato a
        // OpenZeppelin GovernorCountingSimple). Contare i voti contrari nel
        // quorum creerebbe un incentivo perverso: opporsi potrebbe far
        // raggiungere il quorum e passare la proposta, mentre tacere lo
        // negherebbe. Escludendo against, votare contro non aiuta mai a
        // superare la soglia.
        uint256 quorumVotes = p.forVotes + p.abstainVotes;
        uint256 quorumNeeded = (p.snapshotTotalVotingPower * quorumBps) / 10000;

        if (quorumVotes < quorumNeeded || p.forVotes <= p.againstVotes) {
            return ProposalState.Defeated;
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
        if (state(id) != ProposalState.Succeeded) revert ProposalNotSucceeded();
        // execute() deve passare dal percorso queue() -> delay del Timelock:
        // senza questo check una proposta mai schedulata arriverebbe a
        // timelock.execute() saltando la finestra pubblica di reazione.
        if (!p.queued) revert ProposalNotQueued();

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
