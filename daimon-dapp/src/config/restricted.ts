/*
 * Jurisdictions from which this interface is not served, as ISO 3166-1
 * alpha-2 codes (the form Vercel reports in the x-vercel-ip-country header).
 *
 * EMPTY BY DECISION (2026-09-29): the interface blocks no one, and
 * DISCLAIMER_TERMS v0.3 §5 says so -- each user is responsible for lawful use
 * where they are. src/middleware.ts stays in place: listing codes here (e.g.
 * "CU", "IR", "KP", "SY") switches the edge restriction on, with no other code
 * change -- but §5 must then be amended in the same release, since it states
 * that access is not restricted by location.
 *
 * THE list: change it here and nowhere else. Kept free of imports: it runs at
 * the edge.
 */
export const RESTRICTED_COUNTRIES: readonly string[] = [];
