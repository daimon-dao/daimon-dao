"use client";

import Link from "next/link";
import { useAccount, useReadContract, useReadContracts } from "wagmi";
import { ADDRESSES, explorerAddress, IS_TESTNET } from "@/config/contracts";
import { daimonV2Abi } from "@/config/abis/daimonV2";
import { daimonStakingAbi } from "@/config/abis/daimonStaking";
import { daimonGovernorAbi } from "@/config/abis/daimonGovernor";
import { formatCompact, formatExact, formatUsd, formatUnitsNumber, formatCountdown } from "@/lib/format";
import { usePrice } from "@/hooks/usePrice";
import { useNow } from "@/hooks/useNow";
import { PROPOSAL_PHASE, phaseOf, type ProposalTuple } from "@/lib/governance";

const token = { address: ADDRESSES.daimonV2, abi: daimonV2Abi } as const;
const staking = { address: ADDRESSES.daimonStaking, abi: daimonStakingAbi } as const;
const governor = { address: ADDRESSES.daimonGovernor, abi: daimonGovernorAbi } as const;

function MetricCard({
  title,
  value,
  sub,
  exact,
  contract,
}: {
  title: string;
  value: string;
  sub?: string;
  exact?: string;
  contract: string;
}) {
  return (
    <div className="card relative">
      <p className="text-xs uppercase tracking-wider text-secondario">{title}</p>
      <p className="mt-2 text-2xl font-medium text-orochiaro" title={exact}>
        {value}
      </p>
      {sub && <p className="mt-1 text-xs text-secondario">{sub}</p>}
      <a
        href={explorerAddress(contract)}
        target="_blank"
        rel="noreferrer"
        title="Verifica il contratto su BscScan"
        className="absolute right-4 top-4 text-secondario hover:text-oro"
      >
        ⛓
      </a>
    </div>
  );
}

export default function Dashboard() {
  const now = useNow();
  const { isConnected, address } = useAccount();
  const price = usePrice();

  const { data } = useReadContracts({
    contracts: [
      { ...token, functionName: "totalSupply" },
      { ...token, functionName: "INITIAL_SUPPLY" },
      { ...token, functionName: "MIN_SUPPLY" },
      { ...staking, functionName: "totalStakedAmount" },
      { ...governor, functionName: "proposalCount" },
    ],
    query: { refetchInterval: 30_000 },
  });

  const totalSupply = data?.[0]?.result as bigint | undefined;
  const initialSupply = data?.[1]?.result as bigint | undefined;
  const minSupply = data?.[2]?.result as bigint | undefined;
  const totalStaked = data?.[3]?.result as bigint | undefined;
  const proposalCount = data?.[4]?.result as bigint | undefined;

  const burned =
    totalSupply !== undefined && initialSupply !== undefined
      ? initialSupply - totalSupply
      : undefined;

  const stakedPct =
    totalStaked !== undefined && totalSupply !== undefined && totalSupply > 0n
      ? Number((totalStaked * 100000000n) / totalSupply) / 1000000
      : undefined;

  // Progresso deflazione: da INITIAL_SUPPLY (1000B) verso MIN_SUPPLY (21B)
  const burnTarget =
    initialSupply !== undefined && minSupply !== undefined
      ? initialSupply - minSupply
      : undefined;
  const progressPct =
    burned !== undefined && burnTarget !== undefined && burnTarget > 0n
      ? Number((burned * 100000n) / burnTarget) / 1000
      : 0;

  const marketCap =
    price.usd !== null && totalSupply !== undefined
      ? price.usd * formatUnitsNumber(totalSupply)
      : null;

  // Ultima proposta di governance
  const lastId =
    proposalCount !== undefined && proposalCount > 0n ? proposalCount - 1n : undefined;
  const { data: lastProposal } = useReadContract({
    ...governor,
    functionName: "proposals",
    args: lastId !== undefined ? [lastId] : undefined,
    query: { enabled: lastId !== undefined },
  });
  const { data: lastState } = useReadContract({
    ...governor,
    functionName: "state",
    args: lastId !== undefined ? [lastId] : undefined,
    query: { enabled: lastId !== undefined, refetchInterval: 30_000 },
  });

  // "Il tuo staking" — MAI zeri finti senza wallet (spec §8.1)
  const { data: mine } = useReadContracts({
    contracts: address
      ? [
          { ...staking, functionName: "votingPower", args: [address] },
          { ...staking, functionName: "totalStaked", args: [address] },
          { ...staking, functionName: "pendingReward", args: [address] },
        ]
      : [],
    query: { enabled: Boolean(address) },
  });

  return (
    <div className="space-y-8">
      <div>
        <h1 className="text-2xl font-semibold text-orochiaro">Dashboard</h1>
        <p className="mt-1 text-sm text-secondario">
          Tutti i dati sono letti in tempo reale dai contratti su BNB Chain
          {IS_TESTNET ? " (testnet)" : ""}.
        </p>
      </div>

      {/* Metric cards */}
      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <MetricCard
          title="Supply attuale"
          value={totalSupply !== undefined ? `${formatCompact(totalSupply)} DMN` : "…"}
          exact={totalSupply !== undefined ? `${formatExact(totalSupply)} DMN` : undefined}
          contract={ADDRESSES.daimonV2}
        />
        <MetricCard
          title="Token bruciati"
          value={burned !== undefined ? `${formatCompact(burned)} DMN` : "…"}
          sub="verso il floor 21B"
          exact={burned !== undefined ? `${formatExact(burned)} DMN` : undefined}
          contract={ADDRESSES.daimonV2}
        />
        <MetricCard
          title="Totale stakato"
          value={totalStaked !== undefined ? `${formatCompact(totalStaked)} DMN` : "…"}
          sub={
            stakedPct !== undefined
              ? `${stakedPct < 0.01 ? stakedPct.toFixed(4) : stakedPct.toFixed(2)}% della supply`
              : undefined
          }
          exact={totalStaked !== undefined ? `${formatExact(totalStaked)} DMN` : undefined}
          contract={ADDRESSES.daimonStaking}
        />
        <MetricCard
          title="Prezzo DMN"
          value={price.usd !== null ? formatUsd(price.usd) : IS_TESTNET ? "n/d (testnet)" : "n/d"}
          sub={
            marketCap !== null
              ? `Market cap ≈ ${formatUsd(marketCap)}`
              : "prezzo dalla pool PancakeSwap"
          }
          contract={ADDRESSES.pancakePair}
        />
      </div>

      {/* Barra di deflazione */}
      <div className="card">
        <div className="mb-2 flex items-baseline justify-between text-sm">
          <span className="font-medium text-orochiaro">Deflazione verso il floor</span>
          <span className="text-secondario">1000B → 21B</span>
        </div>
        <div className="h-4 overflow-hidden rounded-full border border-bordi bg-bg">
          <div
            className="h-full rounded-full bg-oro transition-all"
            style={{ width: `${Math.max(progressPct, 0.4)}%` }}
            title={burned !== undefined ? `${formatExact(burned)} DMN bruciati` : undefined}
          />
        </div>
        <div className="mt-2 flex justify-between text-xs text-secondario">
          <span>
            {burned !== undefined ? `${formatCompact(burned)} DMN bruciati` : "…"} (
            {progressPct.toFixed(3)}%)
          </span>
          <span>floor: 21B</span>
        </div>
        <p className="mt-4 rounded-lg bg-oro/10 px-4 py-3 text-center text-sm font-medium text-oro">
          Quando il floor sarà raggiunto, il 100% della revenue andrà agli staker
        </p>
      </div>

      {/* Card di accesso rapido */}
      <div className="grid gap-4 md:grid-cols-2">
        <div className="card">
          <h2 className="font-medium text-orochiaro">Il tuo staking</h2>
          {!isConnected ? (
            <p className="mt-3 text-sm text-secondario">
              Connetti il wallet per vedere posizioni e reward.
            </p>
          ) : (
            <div className="mt-3 space-y-1.5 text-sm">
              <p>
                <span className="text-secondario">In stake: </span>
                <span title={mine?.[1]?.result !== undefined ? formatExact(mine[1].result as bigint) : ""}>
                  {mine?.[1]?.result !== undefined
                    ? `${formatCompact(mine[1].result as bigint)} DMN`
                    : "…"}
                </span>
              </p>
              <p>
                <span className="text-secondario">Voting power: </span>
                {mine?.[0]?.result !== undefined
                  ? formatCompact(mine[0].result as bigint)
                  : "…"}
              </p>
              <p>
                <span className="text-secondario">Reward maturati: </span>
                {mine?.[2]?.result !== undefined
                  ? `${formatCompact(mine[2].result as bigint)} BNB`
                  : "…"}
              </p>
            </div>
          )}
          <Link href="/staking" className="btn-outline mt-4 inline-block">
            Vai allo staking →
          </Link>
        </div>

        <div className="card">
          <h2 className="font-medium text-orochiaro">Governance</h2>
          {lastId === undefined || !lastProposal ? (
            <p className="mt-3 text-sm text-secondario">Nessuna proposta ancora creata.</p>
          ) : (
            <LatestProposal
              id={lastId}
              proposal={lastProposal as unknown as ProposalTuple}
              state={lastState as number | undefined}
              now={now}
            />
          )}
          <Link href="/governance" className="btn-outline mt-4 inline-block">
            Vai alla governance →
          </Link>
        </div>
      </div>
    </div>
  );
}

function LatestProposal({
  id,
  proposal,
  state,
  now,
}: {
  id: bigint;
  proposal: ProposalTuple;
  state?: number;
  now: number;
}) {
  const phase = phaseOf(state, proposal, now);
  const info = PROPOSAL_PHASE[phase.key];
  return (
    <div className="mt-3 text-sm">
      <p className="font-medium">
        #{id.toString()} — {proposal[4] || "(senza descrizione)"}
      </p>
      <p className="mt-1.5">
        <span
          className={`rounded-full px-2.5 py-0.5 text-xs font-medium ${info.badgeClass}`}
        >
          {info.label}
        </span>
        {phase.countdownTo && (
          <span className="ml-2 text-secondario">
            {phase.countdownLabel} {formatCountdown(phase.countdownTo - now)}
          </span>
        )}
      </p>
    </div>
  );
}
