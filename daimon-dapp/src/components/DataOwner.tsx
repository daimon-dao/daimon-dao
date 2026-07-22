"use client";

import { shortAddress } from "@/lib/format";
import { useI18n } from "@/components/LocaleProvider";

/*
 * Etichetta "dati di 0x1234…abcd" per le card personali: quando MetaMask
 * e' su un account non connesso alla dApp, i dati mostrati restano
 * legittimamente quelli dell'account connesso — questa riga rende
 * esplicito DI CHI sono i dati, evitando la confusione.
 */
export function DataOwner({ address }: { address?: `0x${string}` }) {
  const { t } = useI18n();
  if (!address) return null;
  return (
    <p className="mt-0.5 text-[11px] text-secondario">
      {t("dataOwner.label")}{" "}
      <span className="font-mono" title={address}>{shortAddress(address)}</span>
    </p>
  );
}
