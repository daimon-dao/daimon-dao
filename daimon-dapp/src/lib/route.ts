"use client";

import { createContext, createElement, useContext, type ReactNode } from "react";
import { usePathname, useSelectedLayoutSegments } from "next/navigation";
import { IS_IPFS_BUILD } from "@/config/target";

/*
 * The route of the current page ("/", "/staking", "/terms/it") and, on the
 * IPFS mirror, how deep it sits below the site root.
 *
 * On the Vercel app the route is the pathname, as always. On the IPFS mirror
 * the pathname is the GATEWAY's path (https://<gw>/ipfs/<cid>/staking/), so
 * it never equals a route: there the route is rebuilt from the router tree,
 * which is the same in the prerendered HTML and after hydration, whatever
 * URL the page is served from. useSelectedLayoutSegments() gives the
 * segments BELOW the layout that calls it, so RouteProvider, mounted by the
 * root layout, is the one place that reads them from the root; everything
 * else, pages included, takes them from its context.
 *
 * Every link and asset the mirror renders is made relative WITH the depth
 * prefix ("" on /, "../" on /staking/, "../../" on /terms/it/), so it is
 * right at any URL a gateway serves the page from and depends on no <base>
 * element -- which React drops, together with everything else it did not
 * render, when it has to re-render the document after a hydration mismatch.
 * The not-found page is served by gateways for any missing path, at any
 * depth: it counts as depth 0 and relies on the <base> the build script
 * computes at load time in ipfs-404.html.
 */
const Ctx = createContext<string[] | null>(null);

export function RouteProvider({ children }: { children: ReactNode }) {
  // Next's internal segments ("/_not-found") are not path segments.
  const segments = useSelectedLayoutSegments().filter((s) => !s.startsWith("/") && !s.startsWith("_"));
  return createElement(Ctx.Provider, { value: segments }, children);
}

function useRouteSegments(): string[] {
  const segments = useContext(Ctx);
  if (!segments) throw new Error("useRouteSegments requires RouteProvider in the tree (root layout)");
  return segments;
}

export function useRoutePath(): string {
  const pathname = usePathname();
  const segments = useRouteSegments();
  if (!IS_IPFS_BUILD) return pathname;
  return "/" + segments.join("/");
}

export function useRelativePrefix(): string {
  return "../".repeat(useRouteSegments().length);
}
