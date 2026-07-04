// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/*
 * DaimonTimelock
 * --------------
 * Versione minimale di OpenZeppelin TimelockController: ogni azione
 * proveniente dal Governor deve essere schedulata e puo' essere eseguita
 * solo dopo minDelay secondi. Questo da' alla community una finestra
 * pubblica e garantita per accorgersi di azioni malevole/errate prima che
 * abbiano effetto, anche se la governance fosse compromessa.
 *
 * Il controllo dei ruoli usa l'AccessControl ufficiale OpenZeppelin;
 * la logica di scheduling con MIN_DELAY hardcodato resta bespoke, motivo
 * per cui il contratto non e' stato sostituito integralmente con
 * TimelockController (che permetterebbe minDelay = 0 via governance).
 */

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

contract DaimonTimelock is AccessControl {
    bytes32 public constant PROPOSER_ROLE = keccak256("PROPOSER_ROLE"); // il Governor
    bytes32 public constant EXECUTOR_ROLE = keccak256("EXECUTOR_ROLE"); // chi puo' eseguire (puo' essere address(0)-equivalente "chiunque" se aperto)
    bytes32 public constant CANCELLER_ROLE = keccak256("CANCELLER_ROLE"); // guardian, solo cancel
    // Gestisce i ruoli stessi, idealmente il Timelock stesso dopo il setup
    // iniziale. Coincide con DEFAULT_ADMIN_ROLE di OZ AccessControl, che e'
    // gia' l'admin di default di tutti gli altri ruoli.
    bytes32 public constant ADMIN_ROLE = DEFAULT_ADMIN_ROLE;

    uint256 public minDelay;

    enum OpState { Unset, Scheduled, Ready, Executed, Canceled }

    struct Operation {
        uint256 readyTimestamp;
        bool executed;
        bool canceled;
    }

    mapping(bytes32 => Operation) public operations;

    event CallScheduled(bytes32 indexed id, address target, uint256 value, bytes data, uint256 delay);
    event CallExecuted(bytes32 indexed id, address target, uint256 value, bytes data);
    event Cancelled(bytes32 indexed id);
    event MinDelayChanged(uint256 oldDelay, uint256 newDelay);

    error TooEarly();
    error OperationNotReady();
    error OperationAlreadyExecuted();
    error OperationAlreadyScheduled();
    error DelayTooShort();
    error ExecutionFailed();

    constructor(uint256 _minDelay, address proposer, address executor, address canceller, address admin) {
        require(_minDelay >= MIN_DELAY, "DaimonTimelock: below MIN_DELAY");
        minDelay = _minDelay;
        _grantRole(PROPOSER_ROLE, proposer);
        _grantRole(EXECUTOR_ROLE, executor);
        _grantRole(CANCELLER_ROLE, canceller);
        // Il timelock amministra se stesso: le rotazioni di ruolo passano
        // da una proposta di governance che target-a il timelock stesso
        // (msg.sender = timelock in execute()).
        _grantRole(ADMIN_ROLE, address(this));
        // Bootstrap TEMPORANEO per il wiring iniziale: l'admin di deploy
        // DEVE chiamare renounceRole(ADMIN_ROLE) a fine setup, altrimenti
        // resta un owner nascosto in grado di auto-assegnarsi
        // PROPOSER/EXECUTOR e bypassare la governance. Verificato nei test.
        _grantRole(ADMIN_ROLE, admin);
    }

    function getMinDelay() external view returns (uint256) {
        return minDelay;
    }

    function hashOperation(address target, uint256 value, bytes calldata data, bytes32 predecessor, bytes32 salt) public pure returns (bytes32) {
        return keccak256(abi.encode(target, value, data, predecessor, salt));
    }

    // Delay minimo assoluto hardcodato: nessuna governance puo' scendere sotto 7 giorni.
    // updateDelay() puo' solo aumentare il delay (o abbassarlo fino a questo floor),
    // mai azzerarlo o renderlo inferiore a MIN_DELAY.
    uint256 public constant MIN_DELAY = 7 days;

    function schedule(address target, uint256 value, bytes calldata data, bytes32 predecessor, bytes32 salt, uint256 delay) external onlyRole(PROPOSER_ROLE) {
        if (delay < minDelay || delay < MIN_DELAY) revert DelayTooShort();
        bytes32 id = hashOperation(target, value, data, predecessor, salt);
        if (operations[id].readyTimestamp != 0) revert OperationAlreadyScheduled();

        operations[id] = Operation({ readyTimestamp: block.timestamp + delay, executed: false, canceled: false });
        emit CallScheduled(id, target, value, data, delay);
    }

    function execute(address target, uint256 value, bytes calldata data, bytes32 predecessor, bytes32 salt) external payable onlyRole(EXECUTOR_ROLE) {
        bytes32 id = hashOperation(target, value, data, predecessor, salt);
        Operation storage op = operations[id];

        if (op.executed) revert OperationAlreadyExecuted();
        if (op.readyTimestamp == 0 || op.canceled) revert OperationNotReady();
        if (block.timestamp < op.readyTimestamp) revert TooEarly();

        if (predecessor != bytes32(0)) {
            if (!operations[predecessor].executed) revert OperationNotReady();
        }

        op.executed = true;

        (bool success, ) = target.call{value: value}(data);
        if (!success) revert ExecutionFailed();

        emit CallExecuted(id, target, value, data);
    }

    function cancel(bytes32 id) external onlyRole(CANCELLER_ROLE) {
        Operation storage op = operations[id];
        require(!op.executed, "DaimonTimelock: already executed");
        op.canceled = true;
        emit Cancelled(id);
    }

    function updateDelay(uint256 newDelay) external {
        require(msg.sender == address(this), "DaimonTimelock: only via self-call (governance proposal)");
        require(newDelay >= MIN_DELAY, "DaimonTimelock: below MIN_DELAY");
        emit MinDelayChanged(minDelay, newDelay);
        minDelay = newDelay;
    }

    // grantRole/revokeRole sono ereditati da OZ AccessControl e richiedono
    // l'admin del ruolo (= ADMIN_ROLE/DEFAULT_ADMIN_ROLE per tutti i ruoli).

    receive() external payable {}
}
