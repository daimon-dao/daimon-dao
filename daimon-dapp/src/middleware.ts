import { NextResponse, type NextRequest } from "next/server";
import { RESTRICTED_COUNTRIES } from "@/config/restricted";

/*
 * Country restriction at the edge -- DORMANT: RESTRICTED_COUNTRIES is empty by
 * decision (src/config/restricted.ts, DAPP_SPEC.md §8 point 10), so every
 * request passes untouched. Kept so that it can be switched on by editing that
 * one constant.
 *
 * When the list is not empty, a visitor whose connection Vercel locates in a
 * listed jurisdiction gets a plain notice (HTTP 451) INSTEAD of the app: no app
 * code, no wallet connector, no RPC call reaches their browser. The full terms
 * at /terms and /terms/it stay readable from everywhere.
 *
 * The country comes from the x-vercel-ip-country header, which Vercel sets on
 * every request at its edge. Without it (local dev, `next start`) nothing is
 * restricted. The smart contracts are permissionless and untouched by this:
 * any restriction applies to this interface only.
 */
export function middleware(req: NextRequest) {
  // Empty list: nothing is restricted, whatever the request carries.
  if (RESTRICTED_COUNTRIES.length === 0) return NextResponse.next();

  const { pathname } = req.nextUrl;
  if (pathname === "/terms" || pathname.startsWith("/terms/")) return NextResponse.next();

  const country = req.headers.get("x-vercel-ip-country")?.toUpperCase();
  if (!country || !RESTRICTED_COUNTRIES.includes(country)) return NextResponse.next();

  // Both languages on one page, the visitor's own first (same rule as the app:
  // the language cookie, else Italian only if it is the browser's primary).
  const cookieLocale = req.cookies.get("daimon-locale")?.value;
  const italianFirst =
    cookieLocale === "it" ||
    (cookieLocale !== "en" &&
      (req.headers.get("accept-language") ?? "").trim().toLowerCase().startsWith("it"));

  return new NextResponse(noticeHtml(italianFirst), {
    status: 451, // Unavailable For Legal Reasons
    headers: {
      "content-type": "text/html; charset=utf-8",
      "cache-control": "private, no-store",
      "x-robots-tag": "noindex",
    },
  });
}

// Everything except the build's static files and the icons: the /terms pages
// need their scripts and styles, and those carry no app behaviour by
// themselves.
export const config = {
  matcher: ["/((?!_next/static|_next/image|favicon\\.ico|icon\\.svg|apple-icon\\.png|logo\\.svg).*)"],
};

// Deliberately neutral: it quotes no terms clause. Whoever switches the
// restriction on amends the terms' §5 in the same release and can extend this.
const EN = `
<section lang="en">
  <h1>Not available in your region</h1>
  <p>This interface is not available from your location.</p>
  <p><a href="/terms">Read the terms of use</a></p>
</section>`;

const IT = `
<section lang="it">
  <h1>Non disponibile nella tua area</h1>
  <p>Questa interfaccia non è disponibile dalla tua posizione.</p>
  <p><a href="/terms/it">Leggi le condizioni d'uso</a></p>
</section>`;

function noticeHtml(italianFirst: boolean): string {
  return `<!doctype html>
<html lang="${italianFirst ? "it" : "en"}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex">
<title>Daimon DAO</title>
<style>
  body { margin: 0; background: #0a1128; color: #e8ebf4;
    font: 15px/1.6 Inter, system-ui, -apple-system, "Segoe UI", sans-serif; }
  main { max-width: 36rem; margin: 0 auto; padding: 4rem 1rem; }
  section { background: #111b3a; border: 1px solid #2a3655; border-radius: 0.75rem;
    padding: 1.25rem 1.5rem; margin-bottom: 1rem; }
  h1 { color: #f5e9c8; font-size: 1.2rem; font-weight: 600; margin: 0 0 0.5rem; }
  p { margin: 0.5rem 0; }
  a { color: #c9a227; }
</style>
</head>
<body><main>${italianFirst ? IT + EN : EN + IT}</main></body>
</html>`;
}
