"use client";

import { IS_TESTNET } from "@/config/contracts";
import { useI18n } from "@/components/LocaleProvider";

// Striscia informativa fissa in cima: chi arriva sullo staging deve capire
// al primo sguardo che non e' il prodotto lanciato. Sparisce da sola su
// mainnet (NEXT_PUBLIC_CHAIN_ID=56), come il noindex nel layout.
export function TestnetBanner() {
  const { t } = useI18n();
  if (!IS_TESTNET) return null;
  // Versione corta sotto sm: su mobile la striscia intera andava su due
  // righe mangiando spazio verticale.
  return (
    <div className="border-b border-oro/40 bg-oro/15 px-4 py-1.5 text-center text-xs font-semibold uppercase tracking-widest text-oro">
      <span className="sm:hidden">{t("banner.testnetShort")}</span>
      <span className="hidden sm:inline">{t("banner.testnet")}</span>
    </div>
  );
}
