"use client";

import { useMemo, useState } from "react";
import { useAccount, useReadContract, useReadContracts } from "wagmi";
import { parseUnits } from "viem";
import { ADDRESSES } from "@/config/contracts";
import { daimonV2Abi } from "@/config/abis/daimonV2";
import { daimonStakingAbi } from "@/config/abis/daimonStaking";
import { ConnectButton } from "@/components/ConnectButton";
import { DataOwner } from "@/components/DataOwner";
import { TxStatus } from "@/components/TxStatus";
import { useI18n } from "@/components/LocaleProvider";
import { useTx } from "@/hooks/useTx";
import { useNow } from "@/hooks/useNow";
import { usePrice } from "@/hooks/usePrice";
import { usePaused } from "@/components/PausedBanner";
import {
  formatCompact,
  formatCountdown,
  formatDate,
  formatExact,
  formatUnitsNumber,
  formatUsd,
} from "@/lib/format";

const token = { address: ADDRESSES.daimonV2, abi: daimonV2Abi } as const;
const staking = { address: ADDRESSES.daimonStaking, abi: daimonStakingAbi } as const;

// Limite di scansione dei lock su RPC pubblico; oltre, servira' un indexer.
const MAX_LOCK_SCAN = 400;

type LockOption = { index: number; duration: bigint; multiplierX1000: bigint; active: boolean };
type Lock = {
  id: number;
  owner: `0x${string}`;
  amount: bigint;
  unlockTime: bigint;
  multiplierX1000: bigint;
  votingPowerGranted: bigint;
  withdrawn: boolean;
};

export default function Staking() {
  const { t, locale } = useI18n();
  const now = useNow();
  const paused = usePaused();
  const price = usePrice();
  const { address, isConnected } = useAccount();

  const [amountInput, setAmountInput] = useState("1000000");
  const [optionIndex, setOptionIndex] = useState(0);

  const approveTx = useTx();
  const stakeTx = useTx();
  const withdrawTx = useTx();
  const claimTx = useTx();

  // --- Opzioni di lock on-chain ---
  const { data: optionsLength } = useReadContract({
    ...staking,
    functionName: "lockOptionsLength",
  });
  const nOptions = Number(optionsLength ?? 0n);
  const { data: optionsData } = useReadContracts({
    contracts: Array.from({ length: nOptions }, (_, i) => ({
      ...staking,
      functionName: "lockOptions" as const,
      args: [BigInt(i)] as const,
    })),
    query: { enabled: nOptions > 0 },
  });
  const options: LockOption[] = useMemo(
    () =>
      (optionsData ?? [])
        .map((r, i) => {
          const t = r.result as readonly [bigint, bigint, boolean] | undefined;
          return t
            ? { index: i, duration: t[0], multiplierX1000: t[1], active: t[2] }
            : null;
        })
        .filter((o): o is LockOption => o !== null && o.active),
    [optionsData]
  );
  const selected = options.find((o) => o.index === optionIndex) ?? options[0];

  // --- Dati utente ---
  const { data: userData } = useReadContracts({
    contracts: address
      ? [
          { ...token, functionName: "balanceOf", args: [address] },
          { ...token, functionName: "allowance", args: [address, ADDRESSES.daimonStaking] },
          { ...staking, functionName: "votingPower", args: [address] },
          { ...staking, functionName: "pendingReward", args: [address] },
        ]
      : [],
    query: { enabled: Boolean(address), refetchInterval: 30_000 },
  });
  const balance = userData?.[0]?.result as bigint | undefined;
  const allowance = userData?.[1]?.result as bigint | undefined;
  const myVotingPower = userData?.[2]?.result as bigint | undefined;
  const myReward = userData?.[3]?.result as bigint | undefined;

  // --- Posizioni: scansione dei lock per id (numero piccolo su testnet) ---
  const { data: nextLockId } = useReadContract({ ...staking, functionName: "nextLockId" });
  const nLocks = Math.min(Number(nextLockId ?? 0n), MAX_LOCK_SCAN);
  const { data: locksData } = useReadContracts({
    contracts: Array.from({ length: nLocks }, (_, i) => ({
      ...staking,
      functionName: "locks" as const,
      args: [BigInt(i)] as const,
    })),
    query: { enabled: nLocks > 0 && Boolean(address) },
  });
  const myLocks: Lock[] = useMemo(() => {
    if (!address || !locksData) return [];
    return locksData
      .map((r, id) => {
        const t = r.result as
          | readonly [`0x${string}`, bigint, bigint, bigint, bigint, bigint, boolean]
          | undefined;
        if (!t) return null;
        return {
          id,
          owner: t[0],
          amount: t[1],
          unlockTime: t[3],
          multiplierX1000: t[4],
          votingPowerGranted: t[5],
          withdrawn: t[6],
        };
      })
      .filter(
        (l): l is Lock =>
          l !== null && l.owner.toLowerCase() === address.toLowerCase() && !l.withdrawn
      );
  }, [locksData, address]);

  // --- Simulatore (funziona anche senza wallet, spec §6) ---
  const amount = useMemo(() => {
    try {
      return parseUnits((amountInput || "0").replace(",", "."), 18);
    } catch {
      return 0n;
    }
  }, [amountInput]);
  const previewVp = selected ? (amount * selected.multiplierX1000) / 1000n : 0n;
  const unlockDate = selected ? now + Number(selected.duration) : now;
  const usdValue = price.usd !== null ? price.usd * formatUnitsNumber(amount) : null;
  const sliderMax = balance !== undefined ? formatUnitsNumber(balance) : 100_000_000;

  const approved = allowance !== undefined && amount > 0n && allowance >= amount;
  // Il contratto rifiuterebbe uno stake oltre il saldo: blocchiamo prima.
  const insufficientBalance = isConnected && balance !== undefined && amount > balance;

  // Il refetch post-conferma e' automatico (invalidazione in useTx).
  async function doApprove() {
    await approveTx.send({
      ...token,
      functionName: "approve",
      args: [ADDRESSES.daimonStaking, amount],
    });
  }
  async function doStake() {
    if (!selected) return;
    await stakeTx.send({
      ...staking,
      functionName: "stake",
      args: [amount, BigInt(selected.index)],
    });
  }
  async function doWithdraw(id: number) {
    await withdrawTx.send({ ...staking, functionName: "withdraw", args: [BigInt(id)] });
  }
  async function doClaim() {
    await claimTx.send({ ...staking, functionName: "claimReward", args: [] });
  }

  return (
    <div className="space-y-8">
      <div>
        <h1 className="text-2xl font-semibold text-orochiaro">{t("staking.title")}</h1>
        <p className="mt-1 text-sm text-secondario">{t("staking.subtitle")}</p>
      </div>

      {/* Simulatore */}
      <div className="card">
        <h2 className="font-medium text-orochiaro">{t("staking.simulator")}</h2>
        <div className="mt-4 grid gap-6 md:grid-cols-2">
          <div>
            <label className="mb-1 block text-xs text-secondario">{t("staking.amountLabel")}</label>
            <input
              className="input"
              inputMode="decimal"
              value={amountInput}
              onChange={(e) => setAmountInput(e.target.value)}
            />
            <input
              type="range"
              min={0}
              max={sliderMax}
              step={sliderMax / 1000}
              value={Math.min(formatUnitsNumber(amount), sliderMax)}
              onChange={(e) => setAmountInput(String(Math.round(Number(e.target.value))))}
              className="mt-3 w-full accent-[#c9a227]"
            />
            <label className="mb-1 mt-4 block text-xs text-secondario">
              {t("staking.durationLabel")}
            </label>
            <div className="flex flex-wrap gap-2">
              {options.map((o) => (
                <button
                  key={o.index}
                  onClick={() => setOptionIndex(o.index)}
                  className={`rounded-lg border px-3 py-2 text-sm ${
                    selected?.index === o.index
                      ? "border-oro bg-oro/15 font-medium text-oro"
                      : "border-bordi text-secondario hover:text-testo"
                  }`}
                >
                  {t("staking.days", { n: Math.round(Number(o.duration) / 86400) })} ·{" "}
                  {Number(o.multiplierX1000) / 1000}x
                </button>
              ))}
              {options.length === 0 && (
                <span className="text-sm text-secondario">{t("staking.loadingOptions")}</span>
              )}
            </div>
          </div>
          <div className="rounded-xl border border-bordi bg-bg/50 p-4">
            <p className="text-sm text-secondario">{t("staking.youGet")}</p>
            <p className="mt-1 text-2xl font-medium text-orochiaro" title={formatExact(previewVp)}>
              {formatCompact(previewVp)} {t("staking.votingPower")}
            </p>
            <p className="mt-2 text-sm text-secondario">
              {t("staking.usdValue")}
              {usdValue !== null ? formatUsd(usdValue) : t("staking.naTestnet")}
            </p>
            <p className="mt-2 text-sm">
              <span className="text-secondario">{t("staking.unlockOn")}</span>
              {/* Gated sulle opzioni on-chain: una data derivata
                  dall'orologio al primo paint non coincide mai tra l'HTML
                  prerenderizzato e il client (hydration mismatch). */}
              <b>{selected ? formatDate(unlockDate, locale) : "…"}</b>
            </p>
          </div>
        </div>

        {/* Azione stake */}
        <div className="mt-5 flex flex-wrap items-center gap-3">
          {!isConnected ? (
            <ConnectButton />
          ) : (
            <>
              {!approved && (
                <button
                  className="btn-outline"
                  onClick={doApprove}
                  disabled={amount === 0n || insufficientBalance || paused || approveTx.phase === "signing" || approveTx.phase === "pending"}
                  title={insufficientBalance ? t("staking.insufficientTitle") : undefined}
                >
                  {t("staking.approve")}
                </button>
              )}
              <button
                className="btn-oro"
                onClick={doStake}
                disabled={!approved || amount === 0n || insufficientBalance || paused || stakeTx.phase === "signing" || stakeTx.phase === "pending"}
                title={
                  insufficientBalance
                    ? t("staking.insufficientTitle")
                    : !approved
                      ? t("staking.approveFirst")
                      : undefined
                }
              >
                {approved ? t("staking.stake") : t("staking.stakeNumbered")}
              </button>
              {balance !== undefined && (
                <span className="text-xs text-secondario">
                  {t("staking.available", { amount: formatCompact(balance) })}
                </span>
              )}
            </>
          )}
        </div>
        {insufficientBalance && (
          <p className="mt-2 text-xs text-rosso">
            {t("staking.insufficientMsg", {
              balance: balance !== undefined ? ` (${formatCompact(balance)} DMN)` : "",
            })}
          </p>
        )}
        <TxStatus phase={approveTx.phase} hash={approveTx.hash} errorMessage={approveTx.errorMessage} notice={approveTx.notice} />
        <TxStatus phase={stakeTx.phase} hash={stakeTx.hash} errorMessage={stakeTx.errorMessage} notice={stakeTx.notice} />
      </div>

      {/* Posizioni + reward */}
      <div className="grid gap-4 lg:grid-cols-3">
        <div className="card lg:col-span-2">
          <h2 className="font-medium text-orochiaro">{t("staking.positions")}</h2>
          {isConnected && <DataOwner address={address} />}
          {!isConnected ? (
            <p className="mt-3 text-sm text-secondario">{t("staking.connectPositions")}</p>
          ) : myLocks.length === 0 ? (
            <p className="mt-3 text-sm text-secondario">{t("staking.noPositions")}</p>
          ) : (
            <div className="mt-3 divide-y divide-bordi">
              {myLocks.map((l) => {
                const unlocked = now >= Number(l.unlockTime);
                return (
                  <div key={l.id} className="flex flex-wrap items-center gap-3 py-3">
                    <div className="min-w-0 flex-1">
                      <p className="text-sm font-medium" title={formatExact(l.amount)}>
                        {formatCompact(l.amount)} DMN ·{" "}
                        <span className="text-oro">{Number(l.multiplierX1000) / 1000}x</span>
                      </p>
                      <p className="text-xs text-secondario" title={formatExact(l.votingPowerGranted)}>
                        {t("staking.positionVp", {
                          vp: formatCompact(l.votingPowerGranted),
                          date: formatDate(l.unlockTime, locale),
                        })}
                        {!unlocked &&
                          t("staking.inTime", {
                            countdown: formatCountdown(Number(l.unlockTime) - now, locale),
                          })}
                      </p>
                    </div>
                    <button
                      className="btn-outline"
                      disabled={!unlocked || paused || withdrawTx.phase === "signing" || withdrawTx.phase === "pending"}
                      title={
                        !unlocked
                          ? t("staking.unlockableOn", { date: formatDate(l.unlockTime, locale) })
                          : undefined
                      }
                      onClick={() => doWithdraw(l.id)}
                    >
                      {t("staking.withdraw")}
                    </button>
                  </div>
                );
              })}
            </div>
          )}
          <TxStatus phase={withdrawTx.phase} hash={withdrawTx.hash} errorMessage={withdrawTx.errorMessage} notice={withdrawTx.notice} />
          {Number(nextLockId ?? 0n) > MAX_LOCK_SCAN && (
            <p className="mt-2 text-xs text-secondario">
              {t("staking.scanNote", { n: MAX_LOCK_SCAN })}
            </p>
          )}
        </div>

        <div className="card">
          <h2 className="font-medium text-orochiaro">{t("staking.rewardsTitle")}</h2>
          {isConnected && <DataOwner address={address} />}
          {!isConnected ? (
            <p className="mt-3 text-sm text-secondario">{t("staking.connectRewards")}</p>
          ) : (
            <>
              <p className="mt-3 text-2xl font-medium text-orochiaro" title={myReward !== undefined ? formatExact(myReward) : ""}>
                {myReward !== undefined ? `${formatCompact(myReward)} BNB` : "…"}
              </p>
              <p className="mt-1 text-sm text-secondario">
                ≈{" "}
                {myReward !== undefined && price.bnbUsd !== null
                  ? formatUsd(price.bnbUsd * formatUnitsNumber(myReward))
                  : t("staking.na")}
              </p>
              <button
                className="btn-oro mt-4"
                onClick={doClaim}
                disabled={!myReward || myReward === 0n || paused || claimTx.phase === "signing" || claimTx.phase === "pending"}
                title={!myReward || myReward === 0n ? t("staking.noRewards") : undefined}
              >
                {t("staking.claim")}
              </button>
              <TxStatus phase={claimTx.phase} hash={claimTx.hash} errorMessage={claimTx.errorMessage} notice={claimTx.notice} />
              {myVotingPower !== undefined && (
                <p className="mt-4 text-xs text-secondario">
                  {t("staking.totalVp", { vp: formatCompact(myVotingPower) })}
                </p>
              )}
            </>
          )}
        </div>
      </div>
    </div>
  );
}
