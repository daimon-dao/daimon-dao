"use client";

import { useMemo } from "react";
import { useI18n } from "@/components/LocaleProvider";
import { formattersFor, type Formatters } from "@/lib/format";

/** The number formatters in the current language (src/lib/format.ts). */
export function useFormat(): Formatters {
  const { locale } = useI18n();
  return useMemo(() => formattersFor(locale), [locale]);
}
