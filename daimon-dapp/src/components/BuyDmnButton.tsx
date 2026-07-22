"use client";

import { useState } from "react";
import { ADDRESSES, IS_TESTNET } from "@/config/contracts";
import { shortAddress } from "@/lib/format";
import { useI18n } from "@/components/LocaleProvider";

/*
 * "Compra DMN": SOLO un link diretto a PancakeSwap con la pair giusta
 * preselezionata (outputCurrency dall'unica fonte di verita',
 * contracts.ts) — nessuno swap integrato (fase 2 DeFi, via proposta DAO).
 * Protegge l'utente dai token fake con nomi simili portandolo sulla pool
 * ufficiale in un click. Nessun parametro referral/tracking nell'URL.
 *
 * Su testnet (97) PancakeSwap non offre un'interfaccia di swap
 * affidabile: il bottone e' disabilitato con tooltip, ma il comportamento
 * e' gia' pronto per mainnet (56) — cambiando chain in contracts.ts
 * l'URL segue automaticamente il nuovo indirizzo.
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
        <button
          className={`btn-oro ${width} cursor-not-allowed opacity-60`}
          disabled
          title={t("buy.testnetTitle")}
        >
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
