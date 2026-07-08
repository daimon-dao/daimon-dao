"use client";

import { useEffect, useState } from "react";
import { useReadContracts } from "wagmi";
import { formatUnits } from "viem";
import { ADDRESSES, IS_TESTNET } from "@/config/contracts";
import { pancakePairAbi } from "@/config/abis/pancakePair";

/*
 * Prezzo DMN (DAPP_SPEC.md §4): fonte primaria le reserve on-chain della
 * pair PancakeSwap (prezzo in BNB) x prezzo BNB/USD da API pubblica;
 * fallback DexScreener. Su testnet, se la pool non ha liquidita' sensata
 * (>= 0.1 BNB), si mostra "n/d (testnet)".
 */
const MIN_SANE_BNB_RESERVE = 0.1;

export type PriceData = {
  usd: number | null; // prezzo DMN in USD, null = non disponibile
  bnbUsd: number | null; // prezzo BNB in USD (per i controvalori dei reward)
  loading: boolean;
};

export function usePrice(): PriceData {
  const [bnbUsd, setBnbUsd] = useState<number | null>(null);
  const [fallbackUsd, setFallbackUsd] = useState<number | null>(null);
  const [loading, setLoading] = useState(true);

  const { data, isLoading } = useReadContracts({
    contracts: [
      {
        address: ADDRESSES.pancakePair,
        abi: pancakePairAbi,
        functionName: "getReserves",
      },
      {
        address: ADDRESSES.pancakePair,
        abi: pancakePairAbi,
        functionName: "token0",
      },
    ],
    query: { refetchInterval: 60_000 },
  });

  // Prezzo BNB/USD da API pubblica (Binance), senza chiavi.
  useEffect(() => {
    let alive = true;
    fetch("https://api.binance.com/api/v3/ticker/price?symbol=BNBUSDT")
      .then((r) => r.json())
      .then((j) => {
        if (alive && j?.price) setBnbUsd(Number(j.price));
      })
      .catch(() => {})
      .finally(() => alive && setLoading(false));
    return () => {
      alive = false;
    };
  }, []);

  const reserves = data?.[0]?.result as
    | readonly [bigint, bigint, number]
    | undefined;
  const token0 = data?.[1]?.result as `0x${string}` | undefined;

  let priceBnb: number | null = null;
  if (reserves && token0) {
    const dmnIsToken0 = token0.toLowerCase() === ADDRESSES.daimonV2.toLowerCase();
    const reserveDmn = Number(formatUnits(dmnIsToken0 ? reserves[0] : reserves[1], 18));
    const reserveBnb = Number(formatUnits(dmnIsToken0 ? reserves[1] : reserves[0], 18));
    if (reserveBnb >= MIN_SANE_BNB_RESERVE && reserveDmn > 0) {
      priceBnb = reserveBnb / reserveDmn;
    }
  }

  // Fallback DexScreener solo se la fonte primaria non e' utilizzabile.
  const primaryUnavailable = !isLoading && (priceBnb === null || bnbUsd === null);
  useEffect(() => {
    if (!primaryUnavailable || IS_TESTNET) return; // su testnet: n/d, niente fallback
    let alive = true;
    fetch(`https://api.dexscreener.com/latest/dex/pairs/bsc/${ADDRESSES.pancakePair}`)
      .then((r) => r.json())
      .then((j) => {
        const p = j?.pairs?.[0]?.priceUsd;
        if (alive && p) setFallbackUsd(Number(p));
      })
      .catch(() => {});
    return () => {
      alive = false;
    };
  }, [primaryUnavailable]);

  const usd =
    priceBnb !== null && bnbUsd !== null ? priceBnb * bnbUsd : fallbackUsd;

  return { usd, bnbUsd, loading: isLoading || loading };
}
