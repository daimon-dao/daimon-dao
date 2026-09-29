/*
 * Jurisdictions from which this interface is not served (DISCLAIMER_TERMS
 * v0.2 §5: "any interface published by the contributors may restrict access
 * from sanctioned jurisdictions"). The terms name no list, so this is the
 * comprehensively sanctioned set: ISO 3166-1 alpha-2 codes, as Vercel reports
 * them in the x-vercel-ip-country header. THE list: change it here and nowhere
 * else (src/middleware.ts reads it). Kept free of imports: it runs at the edge.
 */
export const RESTRICTED_COUNTRIES: readonly string[] = [
  "CU", // Cuba
  "IR", // Iran
  "KP", // North Korea
  "SY", // Syria
];
