"use client";

import { useEffect, useState } from "react";
import { APP_URL } from "@/config/contracts";
import { useI18n } from "@/components/LocaleProvider";

/*
 * IPFS mirror only (mounted by the root layout on that target). A PATH gateway
 * (https://ipfs.io/ipfs/<cid>/...) serves every IPFS site from ONE origin:
 * localStorage -- the terms acceptance, the language, wagmi's connection
 * state, a WalletConnect session -- is readable and writable by any other
 * site opened through the same gateway. A SUBDOMAIN gateway
 * (https://<cid>.ipfs.dweb.link), Brave's ipfs:// handling and a resolved
 * daimon.blockchain give the site an origin of its own, so nothing is shown.
 * docs/IPFS_MIRROR.md, "What a server used to do".
 */
export function GatewayNotice() {
  const { t } = useI18n();
  const [sharedOrigin, setSharedOrigin] = useState(false);

  useEffect(() => {
    setSharedOrigin(/^\/ip[fn]s\//.test(window.location.pathname));
  }, []);

  if (!sharedOrigin) return null;
  return (
    <div
      role="status"
      className="border-b border-oro/40 bg-oro/10 px-4 py-2 text-center text-xs leading-snug text-testo"
    >
      {t("mirror.sharedOrigin")}{" "}
      <a href={APP_URL} className="whitespace-nowrap font-medium text-oro underline underline-offset-2">
        {t("mirror.official")}
      </a>
    </div>
  );
}
