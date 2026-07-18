"use client";

import { useState } from "react";
import { ADDRESSES, IS_TESTNET } from "@/config/contracts";
import { shortAddress } from "@/lib/format";

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
          title="Disponibile al lancio su mainnet: PancakeSwap non offre un'interfaccia di swap per la testnet."
        >
          Compra DMN
        </button>
      ) : (
        <a
          href={SWAP_URL}
          target="_blank"
          rel="noopener noreferrer"
          className={`btn-oro ${width}`}
          title="Si apre su PancakeSwap — verifica sempre che l'indirizzo del token corrisponda a quello mostrato qui."
        >
          Compra DMN ↗
        </a>
      )}
      <p className="mt-1.5 text-[11px] leading-snug text-secondario">
        {IS_TESTNET ? "Disponibile al lancio su mainnet. " : "Si apre su PancakeSwap. "}
        Verifica l&apos;indirizzo del token:{" "}
        <button
          onClick={copyAddress}
          className="font-mono underline decoration-dotted underline-offset-2 hover:text-oro"
          title={`Copia l'indirizzo completo: ${ADDRESSES.daimonV2}`}
        >
          {copied ? "copiato ✓" : shortAddress(ADDRESSES.daimonV2)}
        </button>
      </p>
    </div>
  );
}
