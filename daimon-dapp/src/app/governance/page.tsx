"use client";

import { useMemo, useState } from "react";
import { useAccount, useReadContract, useReadContracts } from "wagmi";
import { isAddress, isHex, parseEther } from "viem";
import { ADDRESSES } from "@/config/contracts";
import { daimonGovernorAbi } from "@/config/abis/daimonGovernor";
import { daimonTimelockAbi } from "@/config/abis/daimonTimelock";
import { daimonStakingAbi } from "@/config/abis/daimonStaking";
import { ConnectButton } from "@/components/ConnectButton";
import { TxStatus } from "@/components/TxStatus";
import { useTx } from "@/hooks/useTx";
import { useNow } from "@/hooks/useNow";
import { usePaused } from "@/components/PausedBanner";
import { formatCompact, formatCountdown, formatExact, shortAddress } from "@/lib/format";
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
  const { isConnected } = useAccount();
  const [showAdvanced, setShowAdvanced] = useState(false);

  const { data: countData, isLoading: countLoading, refetch } = useReadContracts({
    contracts: [
      { ...governor, functionName: "proposalCount" },
      { ...governor, functionName: "quorumBps" },
      { ...governor, functionName: "proposalThreshold" },
    ],
  });
  const proposalCount = Number((countData?.[0]?.result as bigint | undefined) ?? 0n);
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
          <h1 className="text-2xl font-semibold text-orochiaro">Governance</h1>
          <p className="mt-1 text-sm text-secondario">
            Le decisioni passano da voto on-chain e da un timelock pubblico di 7 giorni.
          </p>
        </div>
        <button className="btn-outline" onClick={() => setShowAdvanced((v) => !v)}>
          {showAdvanced ? "Chiudi modalità avanzata" : "Modalità avanzata (nuova proposta)"}
        </button>
      </div>

      {showAdvanced && <CreateProposal threshold={threshold} onCreated={refetch} />}

      {countLoading ? (
        <div className="card text-sm text-secondario">Caricamento proposte…</div>
      ) : proposalCount === 0 ? (
        <div className="card text-sm text-secondario">Nessuna proposta ancora creata.</div>
      ) : (
        <div className="space-y-4">
          {ids.map((id) => (
            <ProposalCard key={id.toString()} id={id} quorumBps={quorumBps} />
          ))}
        </div>
      )}

      {!isConnected && (
        <div className="card flex flex-wrap items-center justify-between gap-3">
          <p className="text-sm text-secondario">
            Connetti il wallet per votare o eseguire le proposte.
          </p>
          <ConnectButton />
        </div>
      )}
    </div>
  );
}

function ProposalCard({ id, quorumBps }: { id: bigint; quorumBps: bigint }) {
  const now = useNow();
  const paused = usePaused();
  const { address, isConnected } = useAccount();
  const voteTx = useTx();
  const queueTx = useTx();
  const executeTx = useTx();

  const { data: proposal, refetch: refetchProposal } = useReadContract({
    ...governor,
    functionName: "proposals",
    args: [id],
    query: { refetchInterval: 30_000 },
  });
  const { data: stateData, refetch: refetchState } = useReadContract({
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
  const { data: voterData, refetch: refetchVoter } = useReadContracts({
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

  if (!p) return <div className="card text-sm text-secondario">Caricamento proposta #{id.toString()}…</div>;

  const phase = phaseOf(stateData as number | undefined, p, now, readyTs);
  const info = PROPOSAL_PHASE[phase.key];

  const forVotes = p[9];
  const againstVotes = p[10];
  const abstainVotes = p[11];
  const totalVotes = forVotes + againstVotes + abstainVotes;
  const quorumNeeded = (p[6] * quorumBps) / 10000n;
  const quorumPct =
    quorumNeeded > 0n ? Math.min(Number((totalVotes * 10000n) / quorumNeeded) / 100, 100) : 0;

  const canVote =
    phase.key === "active" &&
    isConnected &&
    snapshotVp !== undefined &&
    snapshotVp > 0n &&
    hasVoted === false;

  function bar(v: bigint): number {
    return totalVotes > 0n ? Number((v * 10000n) / totalVotes) / 100 : 0;
  }

  async function vote(support: number) {
    await voteTx.send({ ...governor, functionName: "castVote", args: [id, support] });
    refetchProposal();
    refetchVoter();
  }
  async function doQueue() {
    await queueTx.send({ ...governor, functionName: "queue", args: [id] });
    refetchProposal();
    refetchState();
  }
  async function doExecute() {
    await executeTx.send({ ...governor, functionName: "execute", args: [id] });
    refetchProposal();
    refetchState();
  }

  return (
    <div className="card">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div className="min-w-0">
          <p className="font-medium text-orochiaro">
            #{id.toString()} — {p[4] || "(senza descrizione)"}
          </p>
          <p className="mt-1 text-xs text-secondario">
            proposta da {shortAddress(p[0])} · target {shortAddress(p[1])}
          </p>
        </div>
        <div className="text-right">
          <span className={`rounded-full px-2.5 py-1 text-xs font-medium ${info.badgeClass}`}>
            {info.label}
          </span>
          {phase.countdownTo && phase.countdownTo > now && (
            <p className="mt-1 text-xs text-secondario">
              {phase.countdownLabel} {formatCountdown(phase.countdownTo - now)}
            </p>
          )}
        </div>
      </div>

      {/* Barre voto */}
      {(phase.key === "active" || totalVotes > 0n) && (
        <div className="mt-4 space-y-2 text-xs">
          <VoteBar label="Sì" value={forVotes} pct={bar(forVotes)} color="bg-verde" />
          <VoteBar label="No" value={againstVotes} pct={bar(againstVotes)} color="bg-rosso" />
          <VoteBar label="Astenuti" value={abstainVotes} pct={bar(abstainVotes)} color="bg-secondario" />
          <div className="pt-1">
            <div className="mb-1 flex justify-between text-secondario">
              <span>
                Quorum: {formatCompact(totalVotes)} / {formatCompact(quorumNeeded)} richiesto (
                {(Number(quorumBps) / 100).toFixed(0)}%)
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
          Il tuo voting power su questa proposta:{" "}
          <b
            className="text-testo"
            title="Il potere di voto è fotografato alla creazione della proposta per impedire manipolazioni: stake successivi non contano."
          >
            {snapshotVp !== undefined ? formatCompact(snapshotVp) : "…"} ⓘ
          </b>
          {hasVoted && <span className="ml-2 text-verde">Hai già votato ✓</span>}
        </p>
      )}

      {/* Azioni per fase */}
      <div className="mt-4 flex flex-wrap gap-2">
        {phase.key === "active" && (
          <>
            <button className="btn-oro" disabled={!canVote || paused} onClick={() => vote(1)}
              title={!canVote ? "Serve voting power allo snapshot della proposta" : undefined}>
              Vota Sì
            </button>
            <button className="btn-outline" disabled={!canVote || paused} onClick={() => vote(0)}>
              Vota No
            </button>
            <button className="btn-outline" disabled={!canVote || paused} onClick={() => vote(2)}>
              Astieniti
            </button>
          </>
        )}
        {phase.key === "succeeded" && (
          <button className="btn-oro" disabled={!isConnected || paused || queueTx.phase === "pending"} onClick={doQueue}>
            Metti in coda (timelock 7 giorni)
          </button>
        )}
        {phase.key === "timelock" && (
          <button className="btn-outline" disabled title={readyTs ? `Eseguibile dal ${new Date(Number(readyTs) * 1000).toLocaleString("it-IT")}` : undefined}>
            Esegui (in timelock)
          </button>
        )}
        {phase.key === "ready" && (
          <button className="btn-oro" disabled={!isConnected || paused || executeTx.phase === "pending"} onClick={doExecute}>
            Esegui
          </button>
        )}
      </div>
      <TxStatus phase={voteTx.phase} hash={voteTx.hash} errorMessage={voteTx.errorMessage} />
      <TxStatus phase={queueTx.phase} hash={queueTx.hash} errorMessage={queueTx.errorMessage} />
      <TxStatus phase={executeTx.phase} hash={executeTx.hash} errorMessage={executeTx.errorMessage} />
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

function CreateProposal({
  threshold,
  onCreated,
}: {
  threshold?: bigint;
  onCreated: () => void;
}) {
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
    onCreated();
  }

  return (
    <div className="card border-oro/40">
      <h2 className="font-medium text-orochiaro">Nuova proposta (modalità avanzata)</h2>
      <p className="mt-1 text-xs text-secondario">
        Per proporre servono almeno{" "}
        {threshold !== undefined ? formatCompact(threshold) : "…"} di voting power.
        {myVp !== undefined && (
          <> Il tuo: {formatCompact(myVp as bigint)}{enoughVp ? " ✓" : " — insufficiente"}.</>
        )}
      </p>
      <div className="mt-4 grid gap-3 md:grid-cols-2">
        <div>
          <label className="mb-1 block text-xs text-secondario">Contratto target</label>
          <input className="input" placeholder="0x…" value={target} onChange={(e) => setTarget(e.target.value.trim())} />
        </div>
        <div>
          <label className="mb-1 block text-xs text-secondario">Value (BNB)</label>
          <input className="input" value={value} onChange={(e) => setValue(e.target.value)} />
        </div>
        <div className="md:col-span-2">
          <label className="mb-1 block text-xs text-secondario">Calldata (hex)</label>
          <input className="input font-mono" placeholder="0x…" value={calldata} onChange={(e) => setCalldata(e.target.value.trim())} />
        </div>
        <div className="md:col-span-2">
          <label className="mb-1 block text-xs text-secondario">Descrizione</label>
          <textarea className="input" rows={2} value={description} onChange={(e) => setDescription(e.target.value)} />
        </div>
      </div>
      <button
        className="btn-oro mt-4"
        onClick={submit}
        disabled={!isConnected || !valid || !enoughVp || paused || tx.phase === "signing" || tx.phase === "pending"}
      >
        Crea proposta
      </button>
      <TxStatus phase={tx.phase} hash={tx.hash} errorMessage={tx.errorMessage} />
    </div>
  );
}
