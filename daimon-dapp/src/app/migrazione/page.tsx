"use client";

import { useMemo, useState } from "react";
import { useAccount, useReadContract, useReadContracts } from "wagmi";
import { parseUnits, type Abi } from "viem";
import {
  ADDRESSES,
  OLD_DAIMON_FEE_EXEMPT,
  OLD_DAIMON_HAS_MAX_TX,
  OLD_DAIMON_MAX_TX_ABI,
  explorerTx,
} from "@/config/contracts";
import { mockOldDaimonAbi } from "@/config/abis/mockOldDaimon";
import { daimonMigrationAbi } from "@/config/abis/daimonMigration";
import { ConnectButton } from "@/components/ConnectButton";
import { DataOwner } from "@/components/DataOwner";
import { Skeleton } from "@/components/Skeleton";
import { TxStatus } from "@/components/TxStatus";
import { useI18n } from "@/components/LocaleProvider";
import { useTx } from "@/hooks/useTx";
import { useNow } from "@/hooks/useNow";
import { usePaused } from "@/components/PausedBanner";
import { formatCompact, formatCountdown, formatDate, formatExact } from "@/lib/format";

const oldToken = { address: ADDRESSES.oldDaimon, abi: mockOldDaimonAbi } as const;
const migration = { address: ADDRESSES.daimonMigration, abi: daimonMigrationAbi } as const;

function Step({
  n,
  title,
  active,
  done,
  children,
}: {
  n: number;
  title: string;
  active: boolean;
  done: boolean;
  children: React.ReactNode;
}) {
  return (
    <div className={`card ${active ? "border-oro/60" : done ? "border-verde/40" : "opacity-70"}`}>
      <div className="flex items-center gap-3">
        <span
          className={`flex h-8 w-8 items-center justify-center rounded-full text-sm font-semibold ${
            done ? "bg-verde/20 text-verde" : active ? "bg-oro text-[#0a1128]" : "bg-bg text-secondario"
          }`}
        >
          {done ? "✓" : n}
        </span>
        <h2 className="font-medium text-orochiaro">{title}</h2>
      </div>
      <div className="mt-4">{children}</div>
    </div>
  );
}

export default function Migrazione() {
  const { t, locale } = useI18n();
  const now = useNow();
  const paused = usePaused();
  const { address, isConnected } = useAccount();
  const [amountInput, setAmountInput] = useState<string>("");
  const [claimed, setClaimed] = useState<{ amount: bigint; hash: `0x${string}` } | null>(null);

  const approveTx = useTx();
  const claimTx = useTx();

  // The deadline claim() actually enforces: the immutable base plus any pause
  // credit (#36). Read live, never hard-coded. The base getter is only the
  // fallback for the older testnet Migration, which predates the credit.
  const { data: deadlines } = useReadContracts({
    contracts: [
      { ...migration, functionName: "effectiveMigrationDeadline" },
      { ...migration, functionName: "migrationDeadline" },
    ],
    query: { refetchInterval: 60_000 },
  });
  const deadline = (deadlines?.[0]?.result ?? deadlines?.[1]?.result) as bigint | undefined;

  const { data: treasuryAddr } = useReadContract({
    ...migration,
    functionName: "treasury",
  });

  // OPEN = the Migration's treasury, where the old tokens land, is fee-exempt
  // on the old token. On mainnet the treasury IS the Timelock (checked on
  // chain) and the exemption is launch step 11b: DMX
  // isExcludedFromFee(Timelock). Before it every claim reverts with
  // AmountMismatch (the fee shrinks what the treasury receives), so the page
  // refuses to send one. Polled: the page opens by itself. (The testnet
  // deploy has a separate treasury, hence treasury() and not the Timelock.)
  const { data: feeExempt } = useReadContract({
    address: ADDRESSES.oldDaimon,
    abi: OLD_DAIMON_FEE_EXEMPT.abi as Abi,
    functionName: OLD_DAIMON_FEE_EXEMPT.functionName,
    args: treasuryAddr ? [treasuryAddr] : undefined,
    query: { enabled: Boolean(treasuryAddr), refetchInterval: 15_000 },
  });
  const migrationOpen = feeExempt === true;

  // The real DMX caps every transfer (mainnet only): a claim above the cap
  // would revert inside transferFrom.
  const { data: maxTx } = useReadContract({
    address: ADDRESSES.oldDaimon,
    abi: OLD_DAIMON_MAX_TX_ABI,
    functionName: "_maxTxAmount",
    query: { enabled: OLD_DAIMON_HAS_MAX_TX, refetchInterval: 60_000 },
  });

  // The treasury is the DESTINATION of the old tokens: if it migrated itself
  // its balance would not change and the contract would revert with
  // AmountMismatch. Better to explain it before the user signs.
  const isTreasury = Boolean(
    address && treasuryAddr && address.toLowerCase() === (treasuryAddr as string).toLowerCase()
  );

  const { data } = useReadContracts({
    contracts: address
      ? [
          { ...oldToken, functionName: "balanceOf", args: [address] },
          { ...oldToken, functionName: "allowance", args: [address, ADDRESSES.daimonMigration] },
        ]
      : [],
    query: { enabled: Boolean(address), refetchInterval: 20_000 },
  });

  const oldBalance = data?.[0]?.result as bigint | undefined;
  const allowance = data?.[1]?.result as bigint | undefined;

  const deadlineExpired = deadline !== undefined && BigInt(now) > deadline;

  // Amount: default = detected balance, editable (spec §5)
  const amount = useMemo(() => {
    try {
      if (amountInput.trim() !== "") return parseUnits(amountInput.replace(",", "."), 18);
    } catch {}
    return oldBalance ?? 0n;
  }, [amountInput, oldBalance]);

  const approved = allowance !== undefined && amount > 0n && allowance >= amount;
  const step1Done = isConnected;
  const step2Done = step1Done && approved;
  // The contract would reject a migration beyond the balance: block it first.
  const insufficientBalance =
    isConnected && oldBalance !== undefined && amount > oldBalance;
  const capExceeded = maxTx !== undefined && amount > maxTx;
  const disabled =
    !migrationOpen || paused || deadlineExpired || isTreasury || insufficientBalance || capExceeded;

  // The post-confirmation refetch (balance, allowance) is automatic: useTx
  // invalidates the wagmi queries when the transaction is confirmed.
  async function doApprove() {
    await approveTx.send({
      ...oldToken,
      functionName: "approve",
      args: [ADDRESSES.daimonMigration, amount],
    });
  }

  async function doClaim() {
    const hash = await claimTx.send({
      ...migration,
      functionName: "claim",
      args: [amount],
    });
    // null = transaction not sent (e.g. rejected signature): no success screen.
    if (hash) setClaimed({ amount, hash });
  }

  return (
    <div className="mx-auto max-w-2xl space-y-6">
      <div>
        <h1 className="text-2xl font-semibold text-orochiaro">{t("migration.title")}</h1>
        <p className="mt-1 text-sm text-secondario">{t("migration.subtitle")}</p>
      </div>

      {deadline !== undefined && (
        <div
          className={`rounded-xl border px-4 py-3 text-sm ${
            deadlineExpired
              ? "border-rosso/50 bg-rosso/10 text-rosso"
              : "border-bordi bg-card text-secondario"
          }`}
        >
          {deadlineExpired
            ? t("migration.closed", { date: formatDate(deadline, locale) })
            : t("migration.closesOn", {
                date: formatDate(deadline, locale),
                countdown: formatCountdown(Number(deadline) - now, locale),
              })}
        </div>
      )}

      {!deadlineExpired && !migrationOpen && (
        <div
          className="rounded-xl border border-oro/50 bg-oro/10 px-4 py-3 text-sm text-oro"
          role="status"
        >
          {feeExempt === false ? (
            <>
              <b>{t("migration.opensShortlyTitle")}</b> {t("migration.opensShortly")}
            </>
          ) : (
            t("migration.checkingOpen")
          )}
        </div>
      )}

      {isTreasury && (
        <div className="rounded-xl border border-oro/50 bg-oro/10 px-4 py-3 text-sm text-oro">
          {t("migration.treasuryWarning")}
        </div>
      )}

      {claimed && claimTx.phase === "success" ? (
        <div className="card border-verde/50 text-center">
          <p className="text-3xl">🎉</p>
          <h2 className="mt-2 text-xl font-semibold text-verde">{t("migration.success")}</h2>
          <p className="mt-2 text-sm">
            {t("migration.successPrefix")}
            <b title={formatExact(claimed.amount)}>{formatCompact(claimed.amount)} DMN</b>
            {t("migration.successSuffix")}
          </p>
          <a
            className="mt-3 inline-block text-sm text-oro underline underline-offset-2"
            href={explorerTx(claimed.hash)}
            target="_blank"
            rel="noreferrer"
          >
            {t("migration.viewTx")}
          </a>
          <div className="mt-4">
            <button className="btn-outline" onClick={() => setClaimed(null)}>
              {t("migration.migrateMore")}
            </button>
          </div>
        </div>
      ) : (
        <div className="space-y-4">
          <Step n={1} title={t("migration.step1")} active={!step1Done} done={step1Done}>
            {isConnected ? (
              <>
                <p className="text-sm">
                  {t("migration.detected")}{" "}
                  <b title={oldBalance !== undefined ? formatExact(oldBalance) : ""}>
                    {oldBalance !== undefined ? (
                      `${formatCompact(oldBalance)}`
                    ) : (
                      <Skeleton className="h-4 w-20" />
                    )}
                  </b>
                </p>
                <DataOwner address={address} />
              </>
            ) : (
              <div className="flex items-center gap-3">
                <p className="text-sm text-secondario">{t("migration.connectPrompt")}</p>
                <ConnectButton />
              </div>
            )}
          </Step>

          <Step n={2} title={t("migration.step2")} active={step1Done && !step2Done} done={step2Done}>
            <label className="mb-1 block text-xs text-secondario">
              {t("migration.amountLabel")}
            </label>
            <input
              className="input"
              inputMode="decimal"
              placeholder={
                oldBalance !== undefined ? formatExact(oldBalance) : t("migration.amountPlaceholder")
              }
              value={amountInput}
              onChange={(e) => setAmountInput(e.target.value)}
              disabled={!step1Done || paused || deadlineExpired || isTreasury}
            />
            {insufficientBalance && (
              <p className="mt-1 text-xs text-rosso">
                {t("migration.insufficient", {
                  balance: oldBalance !== undefined ? ` (${formatCompact(oldBalance)})` : "",
                })}
              </p>
            )}
            {capExceeded && maxTx !== undefined && (
              <p className="mt-1 text-xs text-rosso">
                {t("migration.capExceeded", { cap: formatCompact(maxTx) })}
              </p>
            )}
            <button
              className="btn-oro mt-3"
              onClick={doApprove}
              disabled={!step1Done || approved || amount === 0n || disabled || approveTx.phase === "signing" || approveTx.phase === "pending"}
            >
              {approved ? t("migration.approveDone") : t("migration.approveBtn")}
            </button>
            <TxStatus phase={approveTx.phase} hash={approveTx.hash} errorMessage={approveTx.errorMessage} notice={approveTx.notice} />
          </Step>

          <Step n={3} title={t("migration.step3")} active={step2Done} done={false}>
            <p className="text-sm text-secondario">
              {t("migration.receivePrefix")}
              <b className="text-testo" title={formatExact(amount)}>
                {formatCompact(amount)} DMN
              </b>
              {t("migration.receiveSuffix")}
            </p>
            <button
              className="btn-oro mt-3"
              onClick={doClaim}
              disabled={!step2Done || amount === 0n || disabled || claimTx.phase === "signing" || claimTx.phase === "pending"}
            >
              {t("migration.migrateBtn")}
            </button>
            <TxStatus phase={claimTx.phase} hash={claimTx.hash} errorMessage={claimTx.errorMessage} notice={claimTx.notice} />
          </Step>
        </div>
      )}
    </div>
  );
}
