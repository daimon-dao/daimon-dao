"use client";

import { useReadContract } from "wagmi";
import { ADDRESSES } from "@/config/contracts";
import { daimonV2Abi } from "@/config/abis/daimonV2";
import { useI18n } from "@/components/LocaleProvider";

/** true se il token e' in pausa di emergenza (poll ogni 30s). */
export function usePaused(): boolean {
  const { data } = useReadContract({
    address: ADDRESSES.daimonV2,
    abi: daimonV2Abi,
    functionName: "paused",
    query: { refetchInterval: 30_000 },
  });
  return data === true;
}

export function PausedBanner() {
  const { t } = useI18n();
  const paused = usePaused();
  if (!paused) return null;
  return (
    <div className="border-b border-rosso/40 bg-rosso/15 px-4 py-2.5 text-center text-sm text-rosso">
      {t("paused.message")}
    </div>
  );
}
