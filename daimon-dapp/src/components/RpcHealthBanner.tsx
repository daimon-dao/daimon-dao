"use client";

import { useEffect, useState } from "react";
import { onlineManager } from "@tanstack/react-query";
import { getBlockNumber } from "viem/actions";
import { useClient } from "wagmi";
import { useI18n } from "@/components/LocaleProvider";

/*
 * RPC health probe: every 15s it asks for the block number through the SAME
 * viem transport as the dApp. Two consecutive failures (~30s) → a discreet
 * banner: the data may be stale. It disappears on its own at the first
 * successful read (data recovery is automatic via react-query, no manual
 * refresh required).
 *
 * Deliberately does NOT use react-query: its wagmi queries run in networkMode
 * offlineFirst and go "paused" (never errored) when the onlineManager believes
 * the device is offline — which is exactly one of the cases to flag.
 * setInterval + try/catch has no intermediate states.
 */
export function RpcHealthBanner() {
  const { t } = useI18n();
  const client = useClient();
  const [failures, setFailures] = useState(0);

  useEffect(() => {
    if (!client) return;
    let alive = true;
    async function probe() {
      try {
        // Explicit action: the client from useClient() lacks the extended methods.
        await getBlockNumber(client!);
        if (!alive) return;
        setFailures(0);
        // The RPC responds: if react-query believes it is "offline" (an online
        // event that never arrived — happens in WebViews and on flaky networks),
        // the data queries would stay paused forever. A successful probe IS the
        // proof of connectivity: we unblock the onlineManager and the queries resume.
        if (!onlineManager.isOnline()) onlineManager.setOnline(true);
      } catch {
        if (alive) setFailures((f) => f + 1);
      }
    }
    probe();
    const iv = window.setInterval(probe, 15_000);
    return () => {
      alive = false;
      window.clearInterval(iv);
    };
  }, [client]);

  if (failures < 2) return null;
  return (
    <div className="border-b border-oro/40 bg-oro/10 px-4 py-1.5 text-center text-xs text-oro">
      {t("rpc.degraded")}
    </div>
  );
}
