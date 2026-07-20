"use client";

import { useMemo, useState } from "react";
import { useAccount, useReadContract, useReadContracts } from "wagmi";
import { parseUnits } from "viem";
import { ADDRESSES, explorerTx } from "@/config/contracts";
import { mockOldDaimonAbi } from "@/config/abis/mockOldDaimon";
import { daimonMigrationAbi } from "@/config/abis/daimonMigration";
import { ConnectButton } from "@/components/ConnectButton";
import { DataOwner } from "@/components/DataOwner";
import { TxStatus } from "@/components/TxStatus";
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
  const now = useNow();
  const paused = usePaused();
  const { address, isConnected } = useAccount();
  const [amountInput, setAmountInput] = useState<string>("");
  const [claimed, setClaimed] = useState<{ amount: bigint; hash: `0x${string}` } | null>(null);

  const approveTx = useTx();
  const claimTx = useTx();

  const { data: deadline } = useReadContract({
    ...migration,
    functionName: "migrationDeadline",
  });

  const { data: treasuryAddr } = useReadContract({
    ...migration,
    functionName: "treasury",
  });
  // La treasury e' la DESTINAZIONE dei vecchi token: se migrasse se stessa
  // il suo saldo non cambierebbe e il contratto reverterebbe con
  // AmountMismatch. Meglio spiegarlo prima che l'utente firmi.
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

  // Importo: default = balance rilevato, modificabile (spec §5)
  const amount = useMemo(() => {
    try {
      if (amountInput.trim() !== "") return parseUnits(amountInput.replace(",", "."), 18);
    } catch {}
    return oldBalance ?? 0n;
  }, [amountInput, oldBalance]);

  const approved = allowance !== undefined && amount > 0n && allowance >= amount;
  const step1Done = isConnected;
  const step2Done = step1Done && approved;
  // Il contratto rifiuterebbe una migrazione oltre il saldo: blocchiamo prima.
  const insufficientBalance =
    isConnected && oldBalance !== undefined && amount > oldBalance;
  const disabled = paused || deadlineExpired || isTreasury || insufficientBalance;

  // Il refetch post-conferma (balance, allowance) e' automatico: useTx
  // invalida le query wagmi quando la transazione risulta confermata.
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
    // null = transazione non inviata (es. firma rifiutata): niente schermata di successo.
    if (hash) setClaimed({ amount, hash });
  }

  return (
    <div className="mx-auto max-w-2xl space-y-6">
      <div>
        <h1 className="text-2xl font-semibold text-orochiaro">Migrazione 1:1</h1>
        <p className="mt-1 text-sm text-secondario">
          Converti i vecchi Daimon in DMN nuovi, uno a uno. I vecchi token vanno
          alla tesoreria della DAO.
        </p>
      </div>

      {deadline !== undefined && (
        <div
          className={`rounded-xl border px-4 py-3 text-sm ${
            deadlineExpired
              ? "border-rosso/50 bg-rosso/10 text-rosso"
              : "border-bordi bg-card text-secondario"
          }`}
        >
          {deadlineExpired ? (
            <>
              La finestra di migrazione si è chiusa il {formatDate(deadline)}. Non è
              più possibile migrare da questa pagina: contatta la community della
              DAO per le opzioni disponibili.
            </>
          ) : (
            <>
              La migrazione chiude il <b className="text-testo">{formatDate(deadline)}</b>{" "}
              — mancano {formatCountdown(Number(deadline) - now)}.
            </>
          )}
        </div>
      )}

      {isTreasury && (
        <div className="rounded-xl border border-oro/50 bg-oro/10 px-4 py-3 text-sm text-oro">
          ⚠ Il wallet connesso è la <b>tesoreria della DAO</b>, cioè la
          destinazione dei vecchi token: non può migrare se stesso (il
          contratto rifiuterebbe l&apos;operazione). Connetti un altro wallet
          per provare la migrazione.
        </div>
      )}

      {claimed && claimTx.phase === "success" ? (
        <div className="card border-verde/50 text-center">
          <p className="text-3xl">🎉</p>
          <h2 className="mt-2 text-xl font-semibold text-verde">Migrazione completata</h2>
          <p className="mt-2 text-sm">
            Hai ricevuto{" "}
            <b title={formatExact(claimed.amount)}>{formatCompact(claimed.amount)} DMN</b>{" "}
            (rapporto 1:1 esatto).
          </p>
          <a
            className="mt-3 inline-block text-sm text-oro underline underline-offset-2"
            href={explorerTx(claimed.hash)}
            target="_blank"
            rel="noreferrer"
          >
            Vedi la transazione su BscScan ↗
          </a>
          <div className="mt-4">
            <button className="btn-outline" onClick={() => setClaimed(null)}>
              Migra altri token
            </button>
          </div>
        </div>
      ) : (
        <div className="space-y-4">
          <Step n={1} title="Connetti" active={!step1Done} done={step1Done}>
            {isConnected ? (
              <>
                <p className="text-sm">
                  Vecchi Daimon rilevati nel wallet:{" "}
                  <b title={oldBalance !== undefined ? formatExact(oldBalance) : ""}>
                    {oldBalance !== undefined ? `${formatCompact(oldBalance)}` : "…"}
                  </b>
                </p>
                <DataOwner address={address} />
              </>
            ) : (
              <div className="flex items-center gap-3">
                <p className="text-sm text-secondario">
                  Connetti il wallet per rilevare i tuoi vecchi Daimon.
                </p>
                <ConnectButton />
              </div>
            )}
          </Step>

          <Step n={2} title="Approva" active={step1Done && !step2Done} done={step2Done}>
            <label className="mb-1 block text-xs text-secondario">
              Importo da migrare (default: tutto il saldo)
            </label>
            <input
              className="input"
              inputMode="decimal"
              placeholder={
                oldBalance !== undefined ? formatExact(oldBalance) : "importo in Daimon"
              }
              value={amountInput}
              onChange={(e) => setAmountInput(e.target.value)}
              disabled={!step1Done || paused || deadlineExpired || isTreasury}
            />
            {insufficientBalance && (
              <p className="mt-1 text-xs text-rosso">
                L&apos;importo supera i vecchi Daimon disponibili
                {oldBalance !== undefined ? ` (${formatCompact(oldBalance)})` : ""}:
                riducilo per procedere.
              </p>
            )}
            <button
              className="btn-oro mt-3"
              onClick={doApprove}
              disabled={!step1Done || approved || amount === 0n || disabled || approveTx.phase === "signing" || approveTx.phase === "pending"}
            >
              {approved ? "Approvazione già concessa ✓" : "Approva la migrazione"}
            </button>
            <TxStatus phase={approveTx.phase} hash={approveTx.hash} errorMessage={approveTx.errorMessage} notice={approveTx.notice} />
          </Step>

          <Step n={3} title="Ricevi DMN" active={step2Done} done={false}>
            <p className="text-sm text-secondario">
              Riceverai{" "}
              <b className="text-testo" title={formatExact(amount)}>
                {formatCompact(amount)} DMN
              </b>{" "}
              — esattamente 1:1, senza fee.
            </p>
            <button
              className="btn-oro mt-3"
              onClick={doClaim}
              disabled={!step2Done || amount === 0n || disabled || claimTx.phase === "signing" || claimTx.phase === "pending"}
            >
              Migra ora
            </button>
            <TxStatus phase={claimTx.phase} hash={claimTx.hash} errorMessage={claimTx.errorMessage} notice={claimTx.notice} />
          </Step>
        </div>
      )}
    </div>
  );
}
