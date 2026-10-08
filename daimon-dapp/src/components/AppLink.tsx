"use client";

import Link from "next/link";
import type { AnchorHTMLAttributes, ReactNode } from "react";
import { IS_IPFS_BUILD } from "@/config/target";
import { useRelativePrefix } from "@/lib/route";

/*
 * Internal links. On the Vercel app: next/link, exactly as before (client-side
 * navigation, prefetch). On the IPFS mirror: a plain anchor with a RELATIVE
 * href computed from this page's depth (src/lib/route.ts), so the same HTML
 * works at https://<cid>.ipfs.<gw>/staking/ and at
 * https://<gw>/ipfs/<cid>/staking/, and a full page load per click: Next's
 * client router would fetch its payloads from the origin root, which on a
 * path gateway is not the site.
 */

/** "/staking" from "/" -> "staking/"; from "/terms/it" -> "../../staking/"; "/" from "/staking" -> "../". */
export function relativeRoute(route: string, prefix: string): string {
  const inner = route.replace(/^\/+/, "").replace(/\/+$/, "");
  return inner ? `${prefix}${inner}/` : prefix || "./";
}

/** "/logo-ring.svg" (a file of public/) from "/staking" -> "../logo-ring.svg". */
export function relativeAsset(path: string, prefix: string): string {
  return prefix + path.replace(/^\/+/, "");
}

type Props = Omit<AnchorHTMLAttributes<HTMLAnchorElement>, "href"> & {
  href: string;
  children: ReactNode;
};

export function AppLink({ href, children, ...rest }: Props) {
  const prefix = useRelativePrefix();
  if (!IS_IPFS_BUILD) {
    return (
      <Link href={href} {...rest}>
        {children}
      </Link>
    );
  }
  return (
    <a href={relativeRoute(href, prefix)} {...rest}>
      {children}
    </a>
  );
}
