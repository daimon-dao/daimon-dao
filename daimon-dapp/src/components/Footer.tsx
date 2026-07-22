"use client";

import { ADDRESSES, explorerAddress, IS_TESTNET } from "@/config/contracts";
import { useI18n } from "@/components/LocaleProvider";

const LINKS: Array<[string, string]> = [
  ["footer.token", ADDRESSES.daimonV2],
  ["footer.staking", ADDRESSES.daimonStaking],
  ["footer.governor", ADDRESSES.daimonGovernor],
  ["footer.timelock", ADDRESSES.daimonTimelock],
  ["footer.migration", ADDRESSES.daimonMigration],
];

export function Footer() {
  const { t } = useI18n();
  return (
    <footer className="mt-16 border-t border-bordi py-8">
      <div className="mx-auto max-w-6xl px-4">
        <p className="mb-3 text-xs uppercase tracking-widest text-secondario">
          {IS_TESTNET ? t("footer.verifiedTestnet") : t("footer.verified")}
        </p>
        <div className="flex flex-wrap gap-x-6 gap-y-2 text-sm">
          {LINKS.map(([labelKey, addr]) => (
            <a
              key={labelKey}
              href={explorerAddress(addr)}
              target="_blank"
              rel="noreferrer"
              className="text-secondario underline-offset-2 hover:text-oro hover:underline"
            >
              {t(labelKey)} ↗
            </a>
          ))}
          {/* Link discreto alla pool ufficiale: solo su mainnet (su testnet
              PancakeSwap non ha una UI di swap). */}
          {!IS_TESTNET && (
            <a
              href={`https://pancakeswap.finance/swap?outputCurrency=${ADDRESSES.daimonV2}`}
              target="_blank"
              rel="noopener noreferrer"
              className="text-oro underline-offset-2 hover:underline"
            >
              {t("footer.buyOnPancake")}
            </a>
          )}
        </div>
        <p className="mt-6 text-xs text-secondario">{t("footer.tagline")}</p>
      </div>
    </footer>
  );
}
