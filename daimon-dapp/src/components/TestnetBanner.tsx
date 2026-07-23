"use client";

import { IS_TESTNET } from "@/config/contracts";
import { useI18n } from "@/components/LocaleProvider";

// Fixed informational strip at the top: whoever lands on staging must grasp
// at a glance that this is not the launched product. It disappears on its own
// on mainnet (NEXT_PUBLIC_CHAIN_ID=56), like the noindex in the layout.
export function TestnetBanner() {
  const { t } = useI18n();
  if (!IS_TESTNET) return null;
  // Short version below sm: on mobile the full strip wrapped onto two lines,
  // eating vertical space.
  return (
    <div className="border-b border-oro/40 bg-oro/15 px-4 py-1.5 text-center text-xs font-semibold uppercase tracking-widest text-oro">
      <span className="sm:hidden">{t("banner.testnetShort")}</span>
      <span className="hidden sm:inline">{t("banner.testnet")}</span>
    </div>
  );
}
