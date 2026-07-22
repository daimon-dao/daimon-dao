import { BaseError, ContractFunctionRevertedError, UserRejectedRequestError } from "viem";
import { translate, type Locale } from "@/lib/i18n";

/*
 * Mappa errori contratto -> messaggi comprensibili nella lingua della UI
 * (DAPP_SPEC.md §8.3: mai mostrare stringhe raw di revert). I testi vivono
 * in messages/{en,it}.json sotto "errors.<NomeErrore>": la mappatura esiste
 * per costruzione in entrambe le lingue (stesse chiavi, fallback inglese).
 */
const ERROR_NAMES = [
  // DaimonStaking
  "LockStillActive",
  "AlreadyWithdrawn",
  "NotLockOwner",
  "InvalidLockOption",
  "ZeroAmount",
  "NotGovernance",
  // DaimonGovernor
  "VotingClosed",
  "VotingNotEnded",
  "AlreadyVoted",
  "InsufficientVotingPower",
  "ProposalNotSucceeded",
  "ProposalNotQueued",
  "InvalidSupport",
  "NotGuardian",
  "AlreadyExecuted",
  // DaimonTimelock
  "TooEarly",
  "OperationNotReady",
  "OperationAlreadyExecuted",
  "OperationAlreadyScheduled",
  "DelayTooShort",
  "ExecutionFailed",
  // DaimonMigration
  "AmountMismatch",
  "MigrationEnded",
  "MigrationStillOpen",
  "OnlyGovernance",
  "AlreadySwept",
  // DaimonV2
  "ContractIsPaused",
  "GuardianExpired",
  "TransferAmountExceedsMaxTx",
  "BelowMinSupply",
  "FeeTooHigh",
  "ZeroAddress",
  "AccessControlUnauthorizedAccount",
] as const;

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

/*
 * Il rifiuto della firma nel wallet (EIP-1193 code 4001) e' un'azione
 * NORMALE dell'utente, non un errore: va distinta da revert e guasti.
 */
export function isUserRejection(err: unknown): boolean {
  if (err instanceof BaseError && err.walk((e) => e instanceof UserRejectedRequestError)) {
    return true;
  }
  const e = err as { code?: number; message?: string; shortMessage?: string } | null;
  if (e?.code === 4001) return true;
  const text = `${e?.shortMessage ?? ""} ${e?.message ?? ""}`;
  return /user rejected|user denied|rejected the request/i.test(text);
}

export function mapTxError(err: unknown, locale: Locale = "en"): string {
  const t = (key: string, vars?: Record<string, string | number>) =>
    translate(locale, key, vars);

  if (err instanceof BaseError) {
    const rejected = err.walk((e) => e instanceof UserRejectedRequestError);
    if (rejected) return t("errors.rejected");

    const revert = err.walk((e) => e instanceof ContractFunctionRevertedError);
    if (revert instanceof ContractFunctionRevertedError) {
      const name = revert.data?.errorName ?? revert.reason;
      if (name && (ERROR_NAMES as readonly string[]).includes(name)) {
        return t(`errors.${name}`);
      }
      if (revert.reason) return t("errors.contractRefusedReason", { reason: revert.reason });
    }
    if (err.shortMessage?.includes("User rejected")) return t("errors.rejected");
    // Selector noto dentro il messaggio (alcuni nodi non decodificano)
    for (const name of ERROR_NAMES) {
      if (err.message.includes(name)) return t(`errors.${name}`);
    }
    return t("errors.contractRefused");
  }
  return t("errors.unexpected");
}
