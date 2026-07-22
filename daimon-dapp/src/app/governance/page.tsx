"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import { useAccount, useReadContract, useReadContracts } from "wagmi";
import { isAddress, isHex, parseEther } from "viem";
import { ADDRESSES } from "@/config/contracts";
import { daimonGovernorAbi } from "@/config/abis/daimonGovernor";
import { daimonTimelockAbi } from "@/config/abis/daimonTimelock";
import { daimonStakingAbi } from "@/config/abis/daimonStaking";
import { ConnectButton } from "@/components/ConnectButton";
import { TxStatus } from "@/components/TxStatus";
import { useI18n } from "@/components/LocaleProvider";
import { useTx } from "@/hooks/useTx";
import { useNow } from "@/hooks/useNow";
import { usePaused } from "@/components/PausedBanner";
import { formatCompact, formatCountdown, formatDate, formatExact, shortAddress } from "@/lib/format";
import {
  PROPOSAL_PHASE,
  phaseOf,
  timelockOperationId,
  type ProposalTuple,
} from "@/lib/governance";

const governor = { address: ADDRESSES.daimonGovernor, abi: daimonGovernorAbi } as const;
const timelock = { address: ADDRESSES.daimonTimelock, abi: daimonTimelockAbi } as const;
const staking = { address: ADDRESSES.daimonStaking, abi: daimonStakingAbi } as const;

export default function Governance() {
  const { t } = useI18n();
  const { isConnected } = useAccount();
  const [showAdvanced, setShowAdvanced] = useState(false);
  // true per qualche secondo dopo che proposalCount CRESCE: chiude il form,
  // mostra il banner ed evidenzia la card appena nata. Guidato dal conteggio
  // (non dal componente form) cosi' funziona anche se l'utente ha chiuso il
  // form prima della conferma — lo scenario del bug della proposta #1.
  const [justCreated, setJustCreated] = useState(false);

  const { data: countData, isLoading: countLoading } = useReadContracts({
    contracts: [
      { ...governor, functionName: "proposalCount" },
      { ...governor, functionName: "quorumBps" },
      { ...governor, functionName: "proposalThreshold" },
    ],
  });
  const proposalCount = Number((countData?.[0]?.result as bigint | undefined) ?? 0n);

  const prevCount = useRef<number | null>(null);
  useEffect(() => {
    if (countData?.[0]?.result === undefined) return; // conteggio non ancora letto
    if (prevCount.current === null) {
      prevCount.current = proposalCount;
      return;
    }
    if (proposalCount > prevCount.current) {
      prevCount.current = proposalCount;
      setShowAdvanced(false);
      setJustCreated(true);
      const t = window.setTimeout(() => setJustCreated(false), 8000);
      return () => window.clearTimeout(t);
    }
    prevCount.current = proposalCount;
  }, [proposalCount, countData]);
  const quorumBps = (countData?.[1]?.result as bigint | undefined) ?? 1000n;
  const threshold = countData?.[2]?.result as bigint | undefined;

  // Ordina dalla piu' recente
  const ids = useMemo(
    () => Array.from({ length: proposalCount }, (_, i) => BigInt(proposalCount - 1 - i)),
    [proposalCount]
  );

  return (
    <div className="space-y-8">
      <div className="flex flex-wrap items-end justify-between gap-3">
        <div>
          <h1 className="text-2xl font-semibold text-orochiaro">{t("governance.title")}</h1>
          <p className="mt-1 text-sm text-secondario">{t("governance.subtitle")}</p>
        </div>
        <button className="btn-outline" onClick={() => setShowAdvanced((v) => !v)}>
          {showAdvanced ? t("governance.advancedClose") : t("governance.advancedOpen")}
        </button>
      </div>

      {showAdvanced && <CreateProposal threshold={threshold} />}

      {justCreated && (
        <div className="card border-verde/50 text-sm text-verde">
          {t("governance.created")}
        </div>
      )}

      {countLoading ? (
        <div className="card text-sm text-secondario">{t("governance.loading")}</div>
      ) : proposalCount === 0 ? (
        <div className="card text-sm text-secondario">{t("governance.none")}</div>
      ) : (
        <div className="space-y-4">
          {ids.map((id, i) => (
            <ProposalCard
              key={id.toString()}
              id={id}
              quorumBps={quorumBps}
              highlight={justCreated && i === 0}
            />
          ))}
        </div>
      )}

      {!isConnected && (
        <div className="card flex flex-wrap items-center justify-between gap-3">
          <p className="text-sm text-secondario">{t("governance.connectToVote")}</p>
          <ConnectButton />
        </div>
      )}
    </div>
  );
}

function ProposalCard({
  id,
  quorumBps,
  highlight = false,
}: {
  id: bigint;
  quorumBps: bigint;
  highlight?: boolean;
}) {
  const { t, locale } = useI18n();
  const now = useNow();
  const paused = usePaused();
  const { address, isConnected } = useAccount();
  const voteTx = useTx();
  const queueTx = useTx();
  const executeTx = useTx();
  // Scelta espressa in QUESTA sessione (il contratto salva solo hasVoted,
  // non il verso del voto: per i voti passati mostriamo il badge generico).
  const [castChoice, setCastChoice] = useState<number | null>(null);

  const { data: proposal } = useReadContract({
    ...governor,
    functionName: "proposals",
    args: [id],
    query: { refetchInterval: 30_000 },
  });
  const { data: stateData } = useReadContract({
    ...governor,
    functionName: "state",
    args: [id],
    query: { refetchInterval: 30_000 },
  });

  const p = proposal as unknown as ProposalTuple | undefined;

  // eta del timelock (solo se la proposta e' stata messa in coda)
  const opId = p && p[14] ? timelockOperationId(p) : undefined;
  const { data: operation } = useReadContract({
    ...timelock,
    functionName: "operations",
    args: opId ? [opId] : undefined,
    query: { enabled: Boolean(opId), refetchInterval: 30_000 },
  });
  const readyTs = operation ? (operation as readonly [bigint, boolean, boolean])[0] : undefined;

  // voting power dell'utente ALLO SNAPSHOT + hasVoted (spec §7)
  const { data: voterData } = useReadContracts({
    contracts:
      address && p
        ? [
            { ...staking, functionName: "votingPowerAt", args: [address, p[5]] },
            { ...governor, functionName: "hasVoted", args: [id, address] },
          ]
        : [],
    query: { enabled: Boolean(address && p) },
  });
  const snapshotVp = voterData?.[0]?.result as bigint | undefined;
  const hasVoted = voterData?.[1]?.result as boolean | undefined;

  if (!p)
    return (
      <div className="card text-sm text-secondario">
        {t("governance.loadingProposal", { id: id.toString() })}
      </div>
    );

  // (evidenziazione post-creazione: anello oro per qualche secondo)

  const phase = phaseOf(stateData as number | undefined, p, now, readyTs);
  const info = PROPOSAL_PHASE[phase.key];

  const forVotes = p[9];
  const againstVotes = p[10];
  const abstainVotes = p[11];
  const totalVotes = forVotes + againstVotes + abstainVotes; // solo per le % delle barre
  // Quorum: for + abstain, ESCLUDENDO against (coerente col Governor —
  // i voti contrari non concorrono al quorum).
  const quorumVotes = forVotes + abstainVotes;
  const quorumNeeded = (p[6] * quorumBps) / 10000n;
  const quorumPct =
    quorumNeeded > 0n ? Math.min(Number((quorumVotes * 10000n) / quorumNeeded) / 100, 100) : 0;

  const canVote =
    phase.key === "active" &&
    isConnected &&
    snapshotVp !== undefined &&
    snapshotVp > 0n &&
    hasVoted === false;

  function bar(v: bigint): number {
    return totalVotes > 0n ? Number((v * 10000n) / totalVotes) / 100 : 0;
  }

  // Il refetch post-conferma e' automatico (invalidazione in useTx).
  // send() non rigetta mai: null = non inviata (es. firma rifiutata).
  async function vote(support: number) {
    const h = await voteTx.send({ ...governor, functionName: "castVote", args: [id, support] });
    if (h) setCastChoice(support);
  }
  async function doQueue() {
    await queueTx.send({ ...governor, functionName: "queue", args: [id] });
  }
  async function doExecute() {
    await executeTx.send({ ...governor, functionName: "execute", args: [id] });
  }

  const alreadyVoted = hasVoted === true || voteTx.phase === "success";
  const choiceLabel =
    castChoice === 1
      ? t("governance.choiceYes")
      : castChoice === 0
        ? t("governance.choiceNo")
        : castChoice === 2
          ? t("governance.choiceAbstain")
          : "";
  const noSnapshotPower =
    isConnected && snapshotVp !== undefined && snapshotVp === 0n;

  return (
    <div className={`card ${highlight ? "border-oro/70 ring-1 ring-oro/50" : ""}`}>
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div className="min-w-0">
          <p className="font-medium text-orochiaro">
            {/* La descrizione e' contenuto on-chain del proposer: NON si traduce. */}
            #{id.toString()} — {p[4] || t("governance.noDescription")}
          </p>
          <p className="mt-1 text-xs text-secondario">
            {t("governance.proposedBy", {
              proposer: shortAddress(p[0]),
              target: shortAddress(p[1]),
            })}
          </p>
        </div>
        <div className="text-right">
          <span className={`rounded-full px-2.5 py-1 text-xs font-medium ${info.badgeClass}`}>
            {t(info.labelKey)}
          </span>
          {phase.countdownTo && phase.countdownTo > now && (
            <p className="mt-1 text-xs text-secondario">
              {phase.countdownLabelKey ? t(phase.countdownLabelKey) : ""}{" "}
              {formatCountdown(phase.countdownTo - now, locale)}
            </p>
          )}
        </div>
      </div>

      {/* Barre voto */}
      {(phase.key === "active" || totalVotes > 0n) && (
        <div className="mt-4 space-y-2 text-xs">
          <VoteBar label={t("governance.yes")} value={forVotes} pct={bar(forVotes)} color="bg-verde" />
          <VoteBar label={t("governance.no")} value={againstVotes} pct={bar(againstVotes)} color="bg-rosso" />
          <VoteBar label={t("governance.abstained")} value={abstainVotes} pct={bar(abstainVotes)} color="bg-secondario" />
          <div className="pt-1">
            <div className="mb-1 flex justify-between text-secondario">
              <span>
                {t("governance.quorum", {
                  votes: formatCompact(quorumVotes),
                  needed: formatCompact(quorumNeeded),
                  pct: (Number(quorumBps) / 100).toFixed(0),
                })}
              </span>
              <span>{quorumPct.toFixed(0)}%</span>
            </div>
            <div className="h-1.5 overflow-hidden rounded-full bg-bg">
              <div className="h-full rounded-full bg-oro" style={{ width: `${quorumPct}%` }} />
            </div>
          </div>
        </div>
      )}

      {/* Voting power allo snapshot */}
      {isConnected && phase.key === "active" && (
        <p className="mt-3 text-xs text-secondario">
          {t("governance.yourVp")}{" "}
          <b className="text-testo" title={t("governance.vpTooltip")}>
            {snapshotVp !== undefined ? formatCompact(snapshotVp) : "…"} ⓘ
          </b>
        </p>
      )}
      {noSnapshotPower && phase.key === "active" && (
        <p className="mt-1 text-xs text-secondario">{t("governance.cantVote")}</p>
      )}

      {/* Azioni per fase */}
      <div className="mt-4 flex flex-wrap gap-2">
        {phase.key === "active" && alreadyVoted && (
          <span className="rounded-full bg-verde/20 px-3 py-1.5 text-sm font-medium text-verde">
            {t("governance.voted", { choice: choiceLabel })}
          </span>
        )}
        {phase.key === "active" && !alreadyVoted && (
          <>
            <button className="btn-oro" disabled={!canVote || paused} onClick={() => vote(1)}
              title={!canVote ? t("governance.needVpTooltip") : undefined}>
              {t("governance.voteYes")}
            </button>
            <button className="btn-outline" disabled={!canVote || paused} onClick={() => vote(0)}
              title={!canVote ? t("governance.needVpTooltip") : undefined}>
              {t("governance.voteNo")}
            </button>
            <button className="btn-outline" disabled={!canVote || paused} onClick={() => vote(2)}
              title={!canVote ? t("governance.needVpTooltip") : undefined}>
              {t("governance.voteAbstain")}
            </button>
          </>
        )}
        {phase.key === "succeeded" && (
          <button className="btn-oro" disabled={!isConnected || paused || queueTx.phase === "pending"} onClick={doQueue}>
            {t("governance.queueBtn")}
          </button>
        )}
        {phase.key === "timelock" && (
          <button
            className="btn-outline"
            disabled
            title={
              readyTs
                ? t("governance.executableFrom", { date: formatDate(readyTs, locale) })
                : undefined
            }
          >
            {t("governance.executeLocked")}
          </button>
        )}
        {phase.key === "ready" && (
          <button className="btn-oro" disabled={!isConnected || paused || executeTx.phase === "pending"} onClick={doExecute}>
            {t("governance.executeBtn")}
          </button>
        )}
      </div>
      <TxStatus phase={voteTx.phase} hash={voteTx.hash} errorMessage={voteTx.errorMessage} notice={voteTx.notice} />
      <TxStatus phase={queueTx.phase} hash={queueTx.hash} errorMessage={queueTx.errorMessage} notice={queueTx.notice} />
      <TxStatus phase={executeTx.phase} hash={executeTx.hash} errorMessage={executeTx.errorMessage} notice={executeTx.notice} />
    </div>
  );
}

function VoteBar({
  label,
  value,
  pct,
  color,
}: {
  label: string;
  value: bigint;
  pct: number;
  color: string;
}) {
  return (
    <div>
      <div className="mb-0.5 flex justify-between">
        <span>{label}</span>
        <span title={formatExact(value)}>
          {formatCompact(value)} ({pct.toFixed(1)}%)
        </span>
      </div>
      <div className="h-1.5 overflow-hidden rounded-full bg-bg">
        <div className={`h-full rounded-full ${color}`} style={{ width: `${pct}%` }} />
      </div>
    </div>
  );
}

function CreateProposal({ threshold }: { threshold?: bigint }) {
  const { t } = useI18n();
  const { address, isConnected } = useAccount();
  const paused = usePaused();
  const tx = useTx();
  const [target, setTarget] = useState("");
  const [value, setValue] = useState("0");
  const [calldata, setCalldata] = useState("0x");
  const [description, setDescription] = useState("");

  const { data: myVp } = useReadContract({
    ...staking,
    functionName: "votingPower",
    args: address ? [address] : undefined,
    query: { enabled: Boolean(address) },
  });

  const valid =
    isAddress(target) && isHex(calldata) && description.trim().length > 0;
  const enoughVp =
    myVp !== undefined && threshold !== undefined && (myVp as bigint) >= threshold;

  // Nessun callback di conferma qui: la chiusura del form, il banner e
  // l'evidenziazione sono guidati dall'aumento di proposalCount nel parent,
  // cosi' funzionano anche se questo componente viene smontato prima della
  // conferma on-chain.
  async function submit() {
    let wei = 0n;
    try {
      wei = parseEther(value || "0");
    } catch {}
    await tx.send({
      ...governor,
      functionName: "propose",
      args: [target as `0x${string}`, wei, calldata as `0x${string}`, description],
    });
  }

  return (
    <div className="card border-oro/40">
      <h2 className="font-medium text-orochiaro">{t("governance.newProposal")}</h2>
      <p className="mt-1 text-xs text-secondario">
        {t("governance.thresholdInfo", {
          threshold: threshold !== undefined ? formatCompact(threshold) : "…",
        })}
        {myVp !== undefined && (
          <>
            {" "}
            {t("governance.yourVpShort", { vp: formatCompact(myVp as bigint) })}
            {enoughVp ? t("governance.enough") : t("governance.insufficient")}.
          </>
        )}
      </p>
      <div className="mt-4 grid gap-3 md:grid-cols-2">
        <div>
          <label className="mb-1 block text-xs text-secondario">{t("governance.targetLabel")}</label>
          <input className="input" placeholder="0x…" value={target} onChange={(e) => setTarget(e.target.value.trim())} />
        </div>
        <div>
          <label className="mb-1 block text-xs text-secondario">{t("governance.valueLabel")}</label>
          <input className="input" value={value} onChange={(e) => setValue(e.target.value)} />
        </div>
        <div className="md:col-span-2">
          <label className="mb-1 block text-xs text-secondario">{t("governance.calldataLabel")}</label>
          <input className="input font-mono" placeholder="0x…" value={calldata} onChange={(e) => setCalldata(e.target.value.trim())} />
        </div>
        <div className="md:col-span-2">
          <label className="mb-1 block text-xs text-secondario">{t("governance.descriptionLabel")}</label>
          <textarea className="input" rows={2} value={description} onChange={(e) => setDescription(e.target.value)} />
        </div>
      </div>
      <button
        className="btn-oro mt-4"
        onClick={submit}
        disabled={!isConnected || !valid || !enoughVp || paused || tx.phase === "signing" || tx.phase === "pending"}
      >
        {t("governance.createBtn")}
      </button>
      <TxStatus phase={tx.phase} hash={tx.hash} errorMessage={tx.errorMessage} notice={tx.notice} />
    </div>
  );
}
