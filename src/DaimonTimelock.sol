// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/*
 * DaimonTimelock
 * --------------
 * Minimal version of OpenZeppelin's TimelockController: every action coming
 * from the Governor must be scheduled and can only be executed after
 * minDelay seconds. This gives the community a public, guaranteed window to
 * notice malicious or mistaken actions before they take effect, even if
 * governance were compromised.
 *
 * Role management uses OpenZeppelin's official AccessControl; the scheduling
 * logic with a hardcoded MIN_DELAY stays bespoke, which is why the contract
 * was not replaced outright with TimelockController (which would allow
 * minDelay = 0 via governance).
 */

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

contract DaimonTimelock is AccessControl {
    bytes32 public constant PROPOSER_ROLE = keccak256("PROPOSER_ROLE"); // the Governor
    bytes32 public constant EXECUTOR_ROLE = keccak256("EXECUTOR_ROLE"); // who can execute (can be an open "anyone" role if opened up)
    bytes32 public constant CANCELLER_ROLE = keccak256("CANCELLER_ROLE"); // guardian, cancel only
    // Manages the roles themselves, ideally the Timelock itself after the
    // initial setup. Coincides with OZ AccessControl's DEFAULT_ADMIN_ROLE,
    // which is already the default admin of every other role.
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
        // The timelock administers itself: role rotations go through a
        // governance proposal that targets the timelock itself
        // (msg.sender = timelock in execute()).
        _grantRole(ADMIN_ROLE, address(this));
        // TEMPORARY bootstrap for the initial wiring: the deploy admin MUST
        // call renounceRole(ADMIN_ROLE) at the end of setup, otherwise a
        // hidden owner remains, able to self-assign PROPOSER/EXECUTOR and
        // bypass governance. Verified in the tests.
        _grantRole(ADMIN_ROLE, admin);
    }

    function getMinDelay() external view returns (uint256) {
        return minDelay;
    }

    function hashOperation(address target, uint256 value, bytes calldata data, bytes32 predecessor, bytes32 salt) public pure returns (bytes32) {
        return keccak256(abi.encode(target, value, data, predecessor, salt));
    }

    // Hardcoded absolute minimum delay: no governance can go below 7 days.
    // updateDelay() can only raise the delay (or lower it down to this floor),
    // never zero it out or make it lower than MIN_DELAY.
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

    // grantRole/revokeRole are inherited from OZ AccessControl and require
    // the role's admin (= ADMIN_ROLE/DEFAULT_ADMIN_ROLE for every role).

    receive() external payable {}
}
