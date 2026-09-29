import Link from "next/link";
import { TERMS, type TermsRun } from "@/content/terms";

/*
 * The full legal text, rendered from src/content/terms.ts (generated from the
 * repository's docs/DISCLAIMER_TERMS_*.md by `npm run terms`). Readable
 * without accepting: TermsGate leaves /terms and /terms/it uncovered.
 */
const REPO_BLOB = "https://github.com/daimon-dao/daimon-dao/blob/master";

function Runs({ runs }: { runs: TermsRun[] }) {
  return (
    <>
      {runs.map((r, i) =>
        r.b ? <b key={i}>{r.text}</b> : r.i ? <i key={i}>{r.text}</i> : <span key={i}>{r.text}</span>
      )}
    </>
  );
}

export function TermsDocument({ lang }: { lang: "en" | "it" }) {
  const { source, blocks } = TERMS[lang];
  const other = lang === "en" ? { href: "/terms/it", label: "Italiano" } : { href: "/terms", label: "English" };
  return (
    <article className="mx-auto max-w-2xl" lang={lang}>
      <div className="mb-6 flex flex-wrap items-center justify-between gap-3 text-sm">
        <Link href="/" className="text-secondario hover:text-oro">
          {lang === "en" ? "← Back to the dApp" : "← Torna alla dApp"}
        </Link>
        <Link href={other.href} className="text-oro underline underline-offset-2">
          {other.label}
        </Link>
      </div>
      <div className="space-y-4 text-sm leading-relaxed text-testo">
        {blocks.map((b, i) => {
          switch (b.type) {
            case "h1":
              return (
                <h1 key={i} className="text-2xl font-semibold text-orochiaro">
                  <Runs runs={b.text} />
                </h1>
              );
            case "h2":
              return (
                <h2 key={i} className="pt-2 text-lg font-medium text-orochiaro">
                  <Runs runs={b.text} />
                </h2>
              );
            case "p":
              return (
                <p key={i}>
                  <Runs runs={b.text} />
                </p>
              );
            case "quote":
              return (
                <blockquote key={i} className="border-l-2 border-oro/50 pl-4 text-secondario">
                  <Runs runs={b.text} />
                </blockquote>
              );
            case "ul":
              return (
                <ul key={i} className="list-disc space-y-2 pl-5">
                  {b.items.map((item, j) => (
                    <li key={j}>
                      <Runs runs={item} />
                    </li>
                  ))}
                </ul>
              );
            case "hr":
              return <hr key={i} className="border-bordi" />;
          }
        })}
      </div>
      <p className="mt-8 text-xs text-secondario">
        {lang === "en" ? "Source in the repository: " : "Sorgente nel repository: "}
        <a
          href={`${REPO_BLOB}/${source}`}
          target="_blank"
          rel="noopener noreferrer"
          className="underline underline-offset-2 hover:text-oro"
        >
          {source}
        </a>
      </p>
    </article>
  );
}
