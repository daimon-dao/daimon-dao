"use client";

import Link from "next/link";
import { useAccount, useReadContract, useReadContracts } from "wagmi";
import { ADDRESSES, INITIAL_SUPPLY, SUPPLY_FLOOR, explorerAddress, IS_TESTNET } from "@/config/contracts";
import { daimonV2Abi } from "@/config/abis/daimonV2";
import { daimonStakingAbi } from "@/config/abis/daimonStaking";
import { daimonGovernorAbi } from "@/config/abis/daimonGovernor";
import { daimonMigrationAbi } from "@/config/abis/daimonMigration";
import { useFormat } from "@/hooks/useFormat";
import { BuyDmnButton } from "@/components/BuyDmnButton";
import { DataOwner } from "@/components/DataOwner";
import { Skeleton } from "@/components/Skeleton";
import { useI18n } from "@/components/LocaleProvider";
import { usePrice } from "@/hooks/usePrice";
import { useNow } from "@/hooks/useNow";
import { PROPOSAL_PHASE, phaseOf, type ProposalTuple } from "@/lib/governance";

const token = { address: ADDRESSES.daimonV2, abi: daimonV2Abi } as const;
const staking = { address: ADDRESSES.daimonStaking, abi: daimonStakingAbi } as const;
const governor = { address: ADDRESSES.daimonGovernor, abi: daimonGovernorAbi } as const;
const migration = { address: ADDRESSES.daimonMigration, abi: daimonMigrationAbi } as const;
// The price headline is per this many DMN.
const ONE_MILLION_DMN = 1_000_000n * 10n ** 18n;

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
  value?: React.ReactNode;
  sub?: React.ReactNode;
  exact?: string;
  contract: string;
  linkTitle: string;
  children?: React.ReactNode;
}) {
  return (
    <div className="card relative">
      <p className="text-xs uppercase tracking-wider text-secondario">{title}</p>
      <p className="mt-2 text-2xl font-medium text-orochiaro" title={exact}>
        {value ?? <Skeleton className="h-7 w-32" />}
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
  const f = useFormat();
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
      // DMN handed to holders so far: of the 1,000B supply, the rest still
      // waits in the Migration contract.
      { ...migration, functionName: "totalMigrated" },
    ],
    query: { refetchInterval: 30_000 },
  });

  const totalSupply = data?.[0]?.result as bigint | undefined;
  const initialSupply = data?.[1]?.result as bigint | undefined;
  const minSupply = data?.[2]?.result as bigint | undefined;
  const totalStaked = data?.[3]?.result as bigint | undefined;
  const proposalCount = data?.[4]?.result as bigint | undefined;
  const totalMigrated = data?.[5]?.result as bigint | undefined;

  const burned =
    totalSupply !== undefined && initialSupply !== undefined
      ? initialSupply - totalSupply
      : undefined;

  const stakedPct =
    totalStaked !== undefined && totalSupply !== undefined && totalSupply > 0n
      ? Number((totalStaked * 100000000n) / totalSupply) / 1000000
      : undefined;

  // Deflation progress: from INITIAL_SUPPLY (1000B) toward MIN_SUPPLY (21B)
  const burnTarget =
    initialSupply !== undefined && minSupply !== undefined
      ? initialSupply - minSupply
      : undefined;
  const progressPct =
    burned !== undefined && burnTarget !== undefined && burnTarget > 0n
      ? Number((burned * 100000n) / burnTarget) / 1000
      : 0;

  // Latest governance proposal
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

  // "Your staking" — NEVER fake zeros without a wallet (spec §8.1)
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
          value={
            totalSupply !== undefined ? (
              <>
                {f.token(totalSupply, "DMN", 3)}{" "}
                <span className="whitespace-nowrap text-sm font-normal text-secondario">
                  — {t("dashboard.totalSupply")}
                </span>
              </>
            ) : undefined
          }
          sub={
            totalMigrated !== undefined
              ? t("dashboard.migratedOf", { amount: f.token(totalMigrated, "DMN", 3) })
              : undefined
          }
          exact={totalSupply !== undefined ? f.tokenExact(totalSupply, "DMN") : undefined}
          contract={ADDRESSES.daimonV2}
          linkTitle={t("dashboard.verifyContract")}
        />
        <MetricCard
          title={t("dashboard.burnedTitle")}
          value={burned !== undefined ? f.token(burned, "DMN") : undefined}
          sub={t("dashboard.burnedSub", { floor: f.compact(minSupply ?? SUPPLY_FLOOR) })}
          exact={burned !== undefined ? f.tokenExact(burned, "DMN") : undefined}
          contract={ADDRESSES.daimonV2}
          linkTitle={t("dashboard.verifyContract")}
        />
        <MetricCard
          title={t("dashboard.stakedTitle")}
          value={totalStaked !== undefined ? f.token(totalStaked, "DMN") : undefined}
          sub={
            stakedPct !== undefined
              ? t("dashboard.stakedPct", { pct: f.percent(stakedPct, stakedPct < 0.01 ? 4 : 2) })
              : undefined
          }
          exact={totalStaked !== undefined ? f.tokenExact(totalStaked, "DMN") : undefined}
          contract={ADDRESSES.daimonStaking}
          linkTitle={t("dashboard.verifyContract")}
        />
        <MetricCard
          title={t("dashboard.priceTitle")}
          // Per MILLION as the headline: a per-token price has six zeros after
          // the point and reads as noise. The exact per-token price follows,
          // in plain decimals (never exponent notation).
          value={
            price.usd !== null ? (
              <>
                {f.usd(price.usd * 1e6)}{" "}
                <span className="whitespace-nowrap text-sm font-normal text-secondario">
                  {t("dashboard.perMillion", { amount: f.token(ONE_MILLION_DMN, "DMN") })}
                </span>
              </>
            ) : IS_TESTNET ? (
              t("dashboard.priceNaTestnet")
            ) : (
              t("dashboard.priceNa")
            )
          }
          exact={price.usd !== null ? `${f.usd(price.usd, 6)} ${t("dashboard.perToken")}` : undefined}
          sub={
            price.usd !== null ? (
              <>
                <span className="block">
                  {f.usd(price.usd)} {t("dashboard.perToken")}
                </span>
                <span className="block">{t("dashboard.priceSource")}</span>
              </>
            ) : (
              t("dashboard.priceSource")
            )
          }
          contract={ADDRESSES.pancakePair}
          linkTitle={t("dashboard.verifyContract")}
        >
          <BuyDmnButton />
        </MetricCard>
      </div>

      {/* Deflation bar */}
      <div className="card">
        <div className="mb-2 flex items-baseline justify-between text-sm">
          <span className="font-medium text-orochiaro">{t("dashboard.deflationTitle")}</span>
          <span className="text-secondario">
            {t("dashboard.deflationRange", {
              from: f.compact(initialSupply ?? INITIAL_SUPPLY),
              to: f.compact(minSupply ?? SUPPLY_FLOOR),
            })}
          </span>
        </div>
        <div className="h-4 overflow-hidden rounded-full border border-bordi bg-bg">
          <div
            className="h-full rounded-full bg-oro transition-all"
            style={{ width: `${Math.max(progressPct, 0.4)}%` }}
            title={
              burned !== undefined
                ? t("dashboard.burnedAmount", { amount: f.tokenExact(burned, "DMN") })
                : undefined
            }
          />
        </div>
        <div className="mt-2 flex justify-between text-xs text-secondario">
          <span>
            {burned !== undefined ? (
              t("dashboard.burnedAmount", { amount: f.token(burned, "DMN") })
            ) : (
              <Skeleton className="h-3 w-24" />
            )}{" "}
            ({f.percent(progressPct, 3)})
          </span>
          <span>{t("dashboard.floorLabel", { floor: f.compact(minSupply ?? SUPPLY_FLOOR) })}</span>
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
                <span title={mine?.[1]?.result !== undefined ? f.tokenExact(mine[1].result as bigint, "DMN") : ""}>
                  {mine?.[1]?.result !== undefined ? (
                    f.token(mine[1].result as bigint, "DMN")
                  ) : (
                    <Skeleton className="h-4 w-16" />
                  )}
                </span>
              </p>
              <p>
                <span className="text-secondario">{t("dashboard.votingPower")}</span>
                {mine?.[0]?.result !== undefined ? (
                  <span title={f.exact(mine[0].result as bigint)}>{f.compact(mine[0].result as bigint)}</span>
                ) : (
                  <Skeleton className="h-4 w-16" />
                )}
              </p>
              <p>
                <span className="text-secondario">{t("dashboard.rewards")}</span>
                {mine?.[2]?.result !== undefined ? (
                  <span title={f.tokenExact(mine[2].result as bigint, "BNB")}>{f.token(mine[2].result as bigint, "BNB")}</span>
                ) : (
                  <Skeleton className="h-4 w-16" />
                )}
              </p>
            </div>
          )}
          <Link href="/staking" className="btn-outline mt-4 inline-block">
            {t("dashboard.goStaking")}
          </Link>
        </div>

        <div className="card">
          <h2 className="font-medium text-orochiaro">{t("dashboard.governanceTitle")}</h2>
          {/* Three distinct states: count not yet read (skeleton, NOT the
              false "no proposals" — with a slow or down RPC it would stay on
              screen as wrong information), zero real proposals, or the latest
              proposal. */}
          {proposalCount === undefined || (lastId !== undefined && !lastProposal) ? (
            <div className="mt-3 space-y-2">
              <Skeleton className="h-4 w-3/4" />
              <Skeleton className="h-4 w-24" />
            </div>
          ) : lastId === undefined ? (
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
  const { t } = useI18n();
  const f = useFormat();
  const phase = phaseOf(state, proposal, now);
  const info = PROPOSAL_PHASE[phase.key];
  return (
    <div className="mt-3 text-sm">
      <p className="font-medium">
        {/* The description is the proposer's on-chain content: NOT translated. */}
        #{id.toString()} — {proposal[4] || t("dashboard.noDescription")}
      </p>
      <p className="mt-1.5">
        <span
          className={`rounded-full px-2.5 py-0.5 text-xs font-medium ${info.badgeClass}`}
        >
          {t(info.labelKey)}
        </span>
        {phase.countdownTo && phase.countdownTo > now && (
          <span className="ml-2 text-secondario">
            {phase.countdownLabelKey ? t(phase.countdownLabelKey) : ""}{" "}
            {f.countdown(phase.countdownTo - now)}
          </span>
        )}
      </p>
    </div>
  );
}
