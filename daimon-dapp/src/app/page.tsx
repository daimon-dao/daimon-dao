"use client";

import Link from "next/link";
import { useAccount, useReadContract, useReadContracts } from "wagmi";
import { ADDRESSES, explorerAddress, IS_TESTNET } from "@/config/contracts";
import { daimonV2Abi } from "@/config/abis/daimonV2";
import { daimonStakingAbi } from "@/config/abis/daimonStaking";
import { daimonGovernorAbi } from "@/config/abis/daimonGovernor";
import { formatCompact, formatExact, formatUsd, formatUnitsNumber, formatCountdown, truncFixed } from "@/lib/format";
import { BuyDmnButton } from "@/components/BuyDmnButton";
import { DataOwner } from "@/components/DataOwner";
import { useI18n } from "@/components/LocaleProvider";
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
  linkTitle,
  children,
}: {
  title: string;
  value: string;
  sub?: string;
  exact?: string;
  contract: string;
  linkTitle: string;
  children?: React.ReactNode;
}) {
  return (
    <div className="card relative">
      <p className="text-xs uppercase tracking-wider text-secondario">{title}</p>
      <p className="mt-2 text-2xl font-medium text-orochiaro" title={exact}>
        {value}
      </p>
      {sub && <p className="mt-1 text-xs text-secondario">{sub}</p>}
      {children}
      <a
        href={explorerAddress(contract)}
        target="_blank"
        rel="noreferrer"
        title={linkTitle}
        className="absolute right-4 top-4 text-secondario hover:text-oro"
      >
        ⛓
      </a>
    </div>
  );
}

export default function Dashboard() {
  const { t } = useI18n();
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
        <h1 className="text-2xl font-semibold text-orochiaro">{t("dashboard.title")}</h1>
        <p className="mt-1 text-sm text-secondario">
          {t("dashboard.subtitle")}
          {IS_TESTNET ? t("dashboard.testnetSuffix") : ""}.
        </p>
      </div>

      {/* Metric cards */}
      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <MetricCard
          title={t("dashboard.supplyTitle")}
          value={totalSupply !== undefined ? `${formatCompact(totalSupply, 18, 3)} DMN` : "…"}
          exact={totalSupply !== undefined ? `${formatExact(totalSupply)} DMN` : undefined}
          contract={ADDRESSES.daimonV2}
          linkTitle={t("dashboard.verifyContract")}
        />
        <MetricCard
          title={t("dashboard.burnedTitle")}
          value={burned !== undefined ? `${formatCompact(burned)} DMN` : "…"}
          sub={t("dashboard.burnedSub")}
          exact={burned !== undefined ? `${formatExact(burned)} DMN` : undefined}
          contract={ADDRESSES.daimonV2}
          linkTitle={t("dashboard.verifyContract")}
        />
        <MetricCard
          title={t("dashboard.stakedTitle")}
          value={totalStaked !== undefined ? `${formatCompact(totalStaked)} DMN` : "…"}
          sub={
            stakedPct !== undefined
              ? t("dashboard.stakedPct", {
                  pct: stakedPct < 0.01 ? stakedPct.toFixed(4) : stakedPct.toFixed(2),
                })
              : undefined
          }
          exact={totalStaked !== undefined ? `${formatExact(totalStaked)} DMN` : undefined}
          contract={ADDRESSES.daimonStaking}
          linkTitle={t("dashboard.verifyContract")}
        />
        <MetricCard
          title={t("dashboard.priceTitle")}
          value={
            price.usd !== null
              ? formatUsd(price.usd)
              : IS_TESTNET
                ? t("dashboard.priceNaTestnet")
                : t("dashboard.priceNa")
          }
          sub={
            marketCap !== null
              ? t("dashboard.marketCap", { value: formatUsd(marketCap) })
              : t("dashboard.priceSource")
          }
          contract={ADDRESSES.pancakePair}
          linkTitle={t("dashboard.verifyContract")}
        >
          <BuyDmnButton />
        </MetricCard>
      </div>

      {/* Barra di deflazione */}
      <div className="card">
        <div className="mb-2 flex items-baseline justify-between text-sm">
          <span className="font-medium text-orochiaro">{t("dashboard.deflationTitle")}</span>
          <span className="text-secondario">{t("dashboard.deflationRange")}</span>
        </div>
        <div className="h-4 overflow-hidden rounded-full border border-bordi bg-bg">
          <div
            className="h-full rounded-full bg-oro transition-all"
            style={{ width: `${Math.max(progressPct, 0.4)}%` }}
            title={
              burned !== undefined
                ? t("dashboard.burnedAmount", { amount: formatExact(burned) })
                : undefined
            }
          />
        </div>
        <div className="mt-2 flex justify-between text-xs text-secondario">
          <span>
            {burned !== undefined
              ? t("dashboard.burnedAmount", { amount: formatCompact(burned) })
              : "…"}{" "}
            ({truncFixed(progressPct, 3)}%)
          </span>
          <span>{t("dashboard.floorLabel")}</span>
        </div>
        <p className="mt-4 rounded-lg bg-oro/10 px-4 py-3 text-center text-sm font-medium text-oro">
          {t("dashboard.floorPromise")}
        </p>
      </div>

      {/* Card di accesso rapido */}
      <div className="grid gap-4 md:grid-cols-2">
        <div className="card">
          <h2 className="font-medium text-orochiaro">{t("dashboard.yourStaking")}</h2>
          {isConnected && <DataOwner address={address} />}
          {!isConnected ? (
            <p className="mt-3 text-sm text-secondario">{t("dashboard.connectForStaking")}</p>
          ) : (
            <div className="mt-3 space-y-1.5 text-sm">
              <p>
                <span className="text-secondario">{t("dashboard.inStake")}</span>
                <span title={mine?.[1]?.result !== undefined ? formatExact(mine[1].result as bigint) : ""}>
                  {mine?.[1]?.result !== undefined
                    ? `${formatCompact(mine[1].result as bigint)} DMN`
                    : "…"}
                </span>
              </p>
              <p>
                <span className="text-secondario">{t("dashboard.votingPower")}</span>
                {mine?.[0]?.result !== undefined
                  ? formatCompact(mine[0].result as bigint)
                  : "…"}
              </p>
              <p>
                <span className="text-secondario">{t("dashboard.rewards")}</span>
                {mine?.[2]?.result !== undefined
                  ? `${formatCompact(mine[2].result as bigint)} BNB`
                  : "…"}
              </p>
            </div>
          )}
          <Link href="/staking" className="btn-outline mt-4 inline-block">
            {t("dashboard.goStaking")}
          </Link>
        </div>

        <div className="card">
          <h2 className="font-medium text-orochiaro">{t("dashboard.governanceTitle")}</h2>
          {lastId === undefined || !lastProposal ? (
            <p className="mt-3 text-sm text-secondario">{t("dashboard.noProposals")}</p>
          ) : (
            <LatestProposal
              id={lastId}
              proposal={lastProposal as unknown as ProposalTuple}
              state={lastState as number | undefined}
              now={now}
            />
          )}
          <Link href="/governance" className="btn-outline mt-4 inline-block">
            {t("dashboard.goGovernance")}
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
  const { t, locale } = useI18n();
  const phase = phaseOf(state, proposal, now);
  const info = PROPOSAL_PHASE[phase.key];
  return (
    <div className="mt-3 text-sm">
      <p className="font-medium">
        {/* La descrizione e' contenuto on-chain del proposer: NON si traduce. */}
        #{id.toString()} — {proposal[4] || t("dashboard.noDescription")}
      </p>
      <p className="mt-1.5">
        <span
          className={`rounded-full px-2.5 py-0.5 text-xs font-medium ${info.badgeClass}`}
        >
          {t(info.labelKey)}
        </span>
        {phase.countdownTo && (
          <span className="ml-2 text-secondario">
            {phase.countdownLabelKey ? t(phase.countdownLabelKey) : ""}{" "}
            {formatCountdown(phase.countdownTo - now, locale)}
          </span>
        )}
      </p>
    </div>
  );
}
