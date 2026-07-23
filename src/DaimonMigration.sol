// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/*
 * DaimonMigration
 * ---------------
 * Lets holders of the old Daimon claim new DaimonV2 tokens 1:1, sending the
 * old tokens to a DAO treasury address (not a dead address: what to do with
 * them stays a future DAO decision, see the explanation given in chat).
 *
 * Operational precondition (one-time action required from the owner of the
 * OLD Daimon contract, BEFORE opening the migration):
 *   oldDaimon.excludeFromFee(address(thisMigrationContract))
 * Without this step, the incoming transferFrom would incur the old
 * contract's tax fee and the net migrated amount would be lower than what
 * the user declared, causing a protective revert (see below) rather than a
 * silent loss of funds.
 *
 * Security:
 *  - Pull, not push: the user initiates their own claim, no "mass" action
 *    that could be hijacked.
 *  - Reentrancy guard.
 *  - EXPLICIT check that the treasury received exactly the declared amount
 *    (balance before/after) before crediting the new tokens: protects both
 *    against unexpected fee-on-transfer and against any inconsistency in the
 *    old contract's reflection.
 *  - Total cap: it cannot distribute more than the supply assigned to it at
 *    deploy (minted only once in the token's constructor), so there is no
 *    risk of "creating" new supply from the migration contract.
 *  - finalize/sweep: at the end of the migration period, the DAO (via
 *    Timelock) can recover any unclaimed DaimonV2, but ONLY after the
 *    deadline and ONLY to the DAO treasury (never to a private wallet).
 */

interface IOldDaimon {
    function balanceOf(address account) external view returns (uint256);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
}

interface INewDaimon {
    function transfer(address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract DaimonMigration is ReentrancyGuard {
    IOldDaimon public immutable oldDaimon;
    INewDaimon public immutable newDaimon;
    address public immutable treasury;     // DAO treasury, destination of the old tokens
    address public immutable governance;   // Timelock, the only one allowed to sweep post-deadline

    uint256 public immutable migrationDeadline;
    uint256 public totalMigrated;

    mapping(address => uint256) public migratedAmount; // how much each user has already migrated (informational)

    bool public sweepExecuted;

    event Claimed(address indexed user, uint256 amount);
    event Swept(address indexed to, uint256 amount);

    error ZeroAmount();
    error ZeroAddress();
    error AmountMismatch();
    error MigrationEnded();
    error MigrationStillOpen();
    error OnlyGovernance();
    error AlreadySwept();

    modifier onlyGovernance() {
        if (msg.sender != governance) revert OnlyGovernance();
        _;
    }

    constructor(address _oldDaimon, address _newDaimon, address _treasury, address _governance, uint256 _migrationDurationSeconds) {
        // All immutable: a zero here would make the contract unusable
        // (or burn the old tokens to address(0)) with no remedy.
        if (_oldDaimon == address(0) || _newDaimon == address(0) || _treasury == address(0) || _governance == address(0)) {
            revert ZeroAddress();
        }
        oldDaimon = IOldDaimon(_oldDaimon);
        newDaimon = INewDaimon(_newDaimon);
        treasury = _treasury;
        governance = _governance;
        migrationDeadline = block.timestamp + _migrationDurationSeconds;
    }

    /// @param amount how many old Daimon you want to migrate. You must first
    /// call oldDaimon.approve(migrationContractAddress, amount).
    function claim(uint256 amount) external nonReentrant {
        if (block.timestamp > migrationDeadline) revert MigrationEnded();
        if (amount == 0) revert ZeroAmount();

        uint256 treasuryBalanceBefore = oldDaimon.balanceOf(treasury);

        bool ok = oldDaimon.transferFrom(msg.sender, treasury, amount);
        require(ok, "DaimonMigration: old token transferFrom failed");

        uint256 treasuryBalanceAfter = oldDaimon.balanceOf(treasury);
        uint256 actuallyReceived = treasuryBalanceAfter - treasuryBalanceBefore;

        // If the old contract applies a non-zeroed fee (because the
        // preparatory excludeFromFee step was not done, or for any other
        // reason), the net amount received would be lower than "amount":
        // instead of silently crediting less, we block the transaction to
        // protect the user, who can retry once the problem is fixed.
        if (actuallyReceived != amount) revert AmountMismatch();

        migratedAmount[msg.sender] += actuallyReceived;
        totalMigrated += actuallyReceived;

        // Same balance-before/after check on the NEW token: if this contract
        // were not excluded from DaimonV2's fees (a deploy wiring error), the
        // user would silently receive less than the promised 1:1 ratio.
        // Better to revert and fix the setup.
        uint256 userNewBalanceBefore = newDaimon.balanceOf(msg.sender);
        bool ok2 = newDaimon.transfer(msg.sender, actuallyReceived);
        require(ok2, "DaimonMigration: new token transfer failed");
        uint256 newReceived = newDaimon.balanceOf(msg.sender) - userNewBalanceBefore;
        if (newReceived != actuallyReceived) revert AmountMismatch();

        emit Claimed(msg.sender, actuallyReceived);
    }

    /// @notice After the deadline, the DAO (via Timelock) can recover the
    /// unclaimed DaimonV2 and route them ONLY to the DAO treasury, for later
    /// decisions (e.g. a new migration round, a voted burn, etc). Executable
    /// only once.
    function sweepUnclaimed() external onlyGovernance nonReentrant {
        if (block.timestamp <= migrationDeadline) revert MigrationStillOpen();
        if (sweepExecuted) revert AlreadySwept();

        sweepExecuted = true;
        uint256 remaining = newDaimon.balanceOf(address(this));
        if (remaining > 0) {
            bool ok = newDaimon.transfer(treasury, remaining);
            require(ok, "DaimonMigration: sweep transfer failed");
        }

        emit Swept(treasury, remaining);
    }
}
