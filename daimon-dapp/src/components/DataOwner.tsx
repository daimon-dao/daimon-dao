"use client";

import { shortAddress } from "@/lib/format";
import { useI18n } from "@/components/LocaleProvider";

/*
 * "data for 0x1234…abcd" label for the personal cards: when MetaMask is on an
 * account not connected to the dApp, the data shown legitimately remains that
 * of the connected account — this line makes explicit WHOSE data it is,
 * avoiding the confusion.
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
