import { BaseError, ContractFunctionRevertedError, UserRejectedRequestError } from "viem";

/*
 * Mappa errori contratto -> messaggi italiani comprensibili
 * (DAPP_SPEC.md §8.3: mai mostrare stringhe raw di revert).
 */
const ERROR_MESSAGES: Record<string, string> = {
  // DaimonStaking
  LockStillActive:
    "Il lock è ancora attivo: potrai ritirare i token solo alla data di sblocco.",
  AlreadyWithdrawn: "Questa posizione è già stata ritirata.",
  NotLockOwner: "Questa posizione appartiene a un altro wallet.",
  InvalidLockOption: "L'opzione di lock selezionata non è disponibile.",
  ZeroAmount: "L'importo deve essere maggiore di zero.",
  NotGovernance: "Azione riservata alla governance della DAO.",
  // DaimonGovernor
  VotingClosed: "La votazione non è aperta in questo momento.",
  VotingNotEnded: "La votazione non è ancora terminata.",
  AlreadyVoted: "Hai già votato su questa proposta.",
  InsufficientVotingPower:
    "Non hai voting power allo snapshot di questa proposta. Il potere di voto è fotografato alla creazione della proposta.",
  ProposalNotSucceeded: "La proposta non è stata approvata (o non è ancora conclusa).",
  ProposalNotQueued: "La proposta va prima messa in coda nel timelock.",
  InvalidSupport: "Opzione di voto non valida.",
  NotGuardian: "Azione riservata al guardian.",
  AlreadyExecuted: "La proposta è già stata eseguita.",
  // DaimonTimelock
  TooEarly: "Il periodo di timelock non è ancora trascorso.",
  OperationNotReady: "L'operazione non è pronta per l'esecuzione.",
  OperationAlreadyExecuted: "L'operazione è già stata eseguita.",
  OperationAlreadyScheduled: "L'operazione è già in coda.",
  DelayTooShort: "Il ritardo indicato è inferiore al minimo consentito.",
  ExecutionFailed: "L'esecuzione della proposta è fallita nel contratto di destinazione.",
  // DaimonMigration
  AmountMismatch:
    "Il contratto ha rilevato una discrepanza negli importi. Riprova o contatta il supporto — i tuoi fondi non sono stati toccati.",
  MigrationEnded: "La finestra di migrazione è chiusa.",
  MigrationStillOpen: "La migrazione è ancora aperta.",
  OnlyGovernance: "Azione riservata alla governance della DAO.",
  AlreadySwept: "I token residui sono già stati recuperati dalla DAO.",
  // DaimonV2
  ContractIsPaused: "Il contratto è temporaneamente in pausa di emergenza.",
  GuardianExpired: "Il ruolo guardian è scaduto: la pausa non è più attivabile.",
  TransferAmountExceedsMaxTx: "L'importo supera il limite massimo per transazione.",
  BelowMinSupply: "L'operazione porterebbe la supply sotto il floor di 21B.",
  FeeTooHigh: "Le fee proposte superano il tetto massimo del 10%.",
  ZeroAddress: "Indirizzo non valido (zero address).",
  AccessControlUnauthorizedAccount: "Il wallet connesso non ha i permessi per questa azione.",
};

/*
 * Il rifiuto della firma nel wallet (EIP-1193 code 4001) e' un'azione
 * NORMALE dell'utente, non un errore: va distinta da revert e guasti.
 */
/*
 * Il wallet e' su una chain diversa da quella della transazione: non e' un
 * errore del contratto ma un problema di rete, da trattare con un invito
 * neutro allo switch (mai un errore rosso).
 */
export function isChainMismatch(err: unknown): boolean {
  const e = err as { name?: string; message?: string; shortMessage?: string } | null;
  const text = `${e?.name ?? ""} ${e?.shortMessage ?? ""} ${e?.message ?? ""}`;
  return /ChainMismatch|does not match the target chain|chain of the wallet/i.test(text);
}

export function isUserRejection(err: unknown): boolean {
  if (err instanceof BaseError && err.walk((e) => e instanceof UserRejectedRequestError)) {
    return true;
  }
  const e = err as { code?: number; message?: string; shortMessage?: string } | null;
  if (e?.code === 4001) return true;
  const text = `${e?.shortMessage ?? ""} ${e?.message ?? ""}`;
  return /user rejected|user denied|rejected the request/i.test(text);
}

export function mapTxError(err: unknown): string {
  if (err instanceof BaseError) {
    const rejected = err.walk((e) => e instanceof UserRejectedRequestError);
    if (rejected) return "Firma rifiutata nel wallet.";

    const revert = err.walk((e) => e instanceof ContractFunctionRevertedError);
    if (revert instanceof ContractFunctionRevertedError) {
      const name = revert.data?.errorName ?? revert.reason;
      if (name && ERROR_MESSAGES[name]) return ERROR_MESSAGES[name];
      if (revert.reason) return `Operazione rifiutata dal contratto (${revert.reason}).`;
    }
    if (err.shortMessage?.includes("User rejected")) return "Firma rifiutata nel wallet.";
    // Selector noto dentro il messaggio (alcuni nodi non decodificano)
    for (const [name, msg] of Object.entries(ERROR_MESSAGES)) {
      if (err.message.includes(name)) return msg;
    }
    return "La transazione è stata rifiutata dal contratto. Nessun fondo è stato spostato.";
  }
  return "Errore imprevisto durante l'invio della transazione.";
}
