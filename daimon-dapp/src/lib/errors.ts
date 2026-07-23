import { BaseError, ContractFunctionRevertedError, UserRejectedRequestError } from "viem";
import { translate, type Locale } from "@/lib/i18n";

/*
 * Maps contract errors -> human-readable messages in the UI language
 * (DAPP_SPEC.md §8.3: never show raw revert strings). The texts live in
 * messages/{en,it}.json under "errors.<ErrorName>": the mapping exists by
 * construction in both languages (same keys, English fallback).
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
 * The wallet is on a chain different from the transaction's: this is not a
 * contract error but a network issue, to be handled with a neutral prompt to
 * switch (never a red error).
 */
export function isChainMismatch(err: unknown): boolean {
  const e = err as { name?: string; message?: string; shortMessage?: string } | null;
  const text = `${e?.name ?? ""} ${e?.shortMessage ?? ""} ${e?.message ?? ""}`;
  return /ChainMismatch|does not match the target chain|chain of the wallet/i.test(text);
}

/*
 * Rejecting the signature in the wallet (EIP-1193 code 4001) is a NORMAL user
 * action, not an error: it must be distinguished from reverts and failures.
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
    // Known selector inside the message (some nodes don't decode)
    for (const name of ERROR_NAMES) {
      if (err.message.includes(name)) return t(`errors.${name}`);
    }
    return t("errors.contractRefused");
  }
  return t("errors.unexpected");
}
