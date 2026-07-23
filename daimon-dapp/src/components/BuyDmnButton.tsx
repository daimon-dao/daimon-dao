"use client";

import { useState } from "react";
import { ADDRESSES, IS_TESTNET } from "@/config/contracts";
import { shortAddress } from "@/lib/format";
import { useI18n } from "@/components/LocaleProvider";

/*
 * "Buy DMN": ONLY a direct link to PancakeSwap with the right pair preselected
 * (outputCurrency from the single source of truth, contracts.ts) — no
 * integrated swap (DeFi phase 2, via DAO proposal). It protects the user from
 * fake tokens with similar names by taking them to the official pool in one
 * click. No referral/tracking parameter in the URL.
 *
 * On testnet (97) PancakeSwap does not offer a reliable swap interface: the
 * button is disabled with a tooltip, but the behavior is already ready for
 * mainnet (56) — changing the chain in contracts.ts makes the URL follow the
 * new address automatically.
 */
const SWAP_URL = `https://pancakeswap.finance/swap?outputCurrency=${ADDRESSES.daimonV2}`;

export function BuyDmnButton({ block = true }: { block?: boolean }) {
  const { t } = useI18n();
  const [copied, setCopied] = useState(false);

  async function copyAddress() {
    try {
      await navigator.clipboard.writeText(ADDRESSES.daimonV2);
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    } catch {}
  }

  const width = block ? "block w-full text-center" : "inline-block";

  return (
    <div className="mt-3">
      {IS_TESTNET ? (
        <button className={`btn-oro ${width}`} disabled title={t("buy.testnetTitle")}>
          {t("buy.button")}
        </button>
      ) : (
        <a
          href={SWAP_URL}
          target="_blank"
          rel="noopener noreferrer"
          className={`btn-oro ${width}`}
          title={t("buy.mainnetTitle")}
        >
          {t("buy.buttonLink")}
        </a>
      )}
      <p className="mt-1.5 text-[11px] leading-snug text-secondario">
        {IS_TESTNET ? t("buy.testnetNote") : t("buy.mainnetNote")}
        {t("buy.verifyAddress")}{" "}
        <button
          onClick={copyAddress}
          className="font-mono underline decoration-dotted underline-offset-2 hover:text-oro"
          title={t("buy.copyFull", { address: ADDRESSES.daimonV2 })}
        >
          {copied ? t("buy.copied") : shortAddress(ADDRESSES.daimonV2)}
        </button>
      </p>
    </div>
  );
}
