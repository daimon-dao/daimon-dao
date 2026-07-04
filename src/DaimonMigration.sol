// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/*
 * DaimonMigration
 * ---------------
 * Permette ai holder del vecchio Daimon di fare claim 1:1 dei nuovi
 * DaimonV2, inviando i vecchi token a un indirizzo di tesoreria della DAO
 * (non un dead address: resta una decisione futura della DAO cosa farne,
 * vedi spiegazione fornita in chat).
 *
 * Precondizione operativa (azione one-time richiesta all'owner del VECCHIO
 * contratto Daimon, PRIMA di aprire la migrazione):
 *   oldDaimon.excludeFromFee(address(thisMigrationContract))
 * Senza questo passaggio, il transferFrom in entrata subirebbe la tax fee
 * del vecchio contratto e l'importo netto migrato sarebbe inferiore a
 * quanto dichiarato dall'utente, causando un revert protettivo (vedi sotto)
 * piuttosto che una perdita silenziosa di fondi.
 *
 * Sicurezza:
 *  - Pull, non push: l'utente avvia la propria claim, nessuna azione "di
 *    massa" che possa essere dirottata.
 *  - Reentrancy guard.
 *  - Verifica ESPLICITA che il treasury abbia ricevuto esattamente
 *    l'importo dichiarato (balance prima/dopo) prima di accreditare i
 *    nuovi token: protegge sia da fee-on-transfer inattese sia da eventuali
 *    incongruenze nella reflection del vecchio contratto.
 *  - Cap totale: non puo' distribuire piu' della supply che gli e' stata
 *    assegnata al deploy (mintata una sola volta nel costruttore del
 *    token), quindi nessun rischio di "creare" nuova supply dal contratto
 *    di migrazione.
 *  - finalize/sweep: a fine periodo di migrazione, la DAO (via Timelock)
 *    puo' recuperare gli eventuali DaimonV2 non riscattati, ma SOLO dopo
 *    la deadline e SOLO verso la tesoreria della DAO (mai a un wallet
 *    privato).
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
    address public immutable treasury;     // tesoreria DAO, destinazione dei vecchi token
    address public immutable governance;   // Timelock, unico abilitato a fare sweep post-deadline

    uint256 public immutable migrationDeadline;
    uint256 public totalMigrated;

    mapping(address => uint256) public migratedAmount; // quanto ogni utente ha gia' migrato (informativo)

    bool public sweepExecuted;

    event Claimed(address indexed user, uint256 amount);
    event Swept(address indexed to, uint256 amount);

    error ZeroAmount();
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
        oldDaimon = IOldDaimon(_oldDaimon);
        newDaimon = INewDaimon(_newDaimon);
        treasury = _treasury;
        governance = _governance;
        migrationDeadline = block.timestamp + _migrationDurationSeconds;
    }

    /// @param amount quanti vecchi Daimon vuoi migrare. Devi prima fare
    /// oldDaimon.approve(migrationContractAddress, amount).
    function claim(uint256 amount) external nonReentrant {
        if (block.timestamp > migrationDeadline) revert MigrationEnded();
        if (amount == 0) revert ZeroAmount();

        uint256 treasuryBalanceBefore = oldDaimon.balanceOf(treasury);

        bool ok = oldDaimon.transferFrom(msg.sender, treasury, amount);
        require(ok, "DaimonMigration: old token transferFrom failed");

        uint256 treasuryBalanceAfter = oldDaimon.balanceOf(treasury);
        uint256 actuallyReceived = treasuryBalanceAfter - treasuryBalanceBefore;

        // Se il vecchio contratto applica una fee non azzerata (perche' il
        // passaggio preparatorio excludeFromFee non e' stato fatto, o per
        // qualunque altra causa), l'importo netto ricevuto sarebbe inferiore
        // a "amount": invece di accreditare meno silenziosamente, blocchiamo
        // la transazione a protezione dell'utente, che puo' riprovare dopo
        // che il problema e' risolto.
        if (actuallyReceived != amount) revert AmountMismatch();

        migratedAmount[msg.sender] += actuallyReceived;
        totalMigrated += actuallyReceived;

        // Stesso controllo balance-before/after anche sul NUOVO token: se
        // questo contratto non fosse escluso dalle fee di DaimonV2 (errore
        // di wiring al deploy), l'utente riceverebbe silenziosamente meno
        // del rapporto 1:1 promesso. Meglio revertire e correggere il setup.
        uint256 userNewBalanceBefore = newDaimon.balanceOf(msg.sender);
        bool ok2 = newDaimon.transfer(msg.sender, actuallyReceived);
        require(ok2, "DaimonMigration: new token transfer failed");
        uint256 newReceived = newDaimon.balanceOf(msg.sender) - userNewBalanceBefore;
        if (newReceived != actuallyReceived) revert AmountMismatch();

        emit Claimed(msg.sender, actuallyReceived);
    }

    /// @notice Dopo la deadline, la DAO (via Timelock) puo' recuperare i
    /// DaimonV2 non riscattati e SOLO indirizzarli alla treasury della DAO,
    /// per decisioni successive (es. nuovo round di migrazione, burn votato,
    /// ecc). Eseguibile una sola volta.
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
