# Social assets — Daimon DAO

Grafiche social generate dall'identità visiva della dApp (logo, font Inter,
palette blu notte `#0a1128` · oro `#c9a227` · crema `#f5e9c8`). Stile sobrio,
"istituzionale crypto": nessun effetto pump, nessun logo di terze parti,
nessun grafico di prezzo. Font Inter (lo stesso della dApp), max 3 colori.

Rigenerabili con lo script Node in `scripts/` (usa `@resvg/resvg-js` +
i TTF statici di Inter; vedi commento in testa allo script).

| File | Dimensioni | Uso |
|---|---|---|
| **`banner-profilo-A-en.png`** | 1500×500 | ⭐ **BANNER UFFICIALE.** Header profilo X — variante A (senza logo), inglese. Il testo è protagonista, centrato, con sinistra e basso liberi per l'avatar. |
| `banner-profilo-A-it.png` | 1500×500 | Alternativa — variante A (senza logo), italiano. |
| `banner-profilo-B-en/it.png` | 1500×500 | Alternativa — variante B (filigrana): testo a sinistra, simbolo del logo come filigrana chiara tono-su-tono nell'angolo destro (non un secondo logo pieno). Utile per contesti diversi dal profilo X. |
| `stat-fee.png` | 1600×900 | Post X — "11% → 4%", "decided by the DAO, not by a boss". |
| `stat-timelock.png` | 1600×900 | Post X — "604,800" seconds of timelock. |
| `stat-owner-mint.png` | 1600×900 | Post X — "0 owner · 0 mint". |
| `stat-supply.png` | 1600×900 | Post X — "1000B → 21B" with deflation bar. |
| `quote-codice.png` | 1600×900 | Post X — "Humans make mistakes. Code doesn't." |
| `quote-verificate.png` | 1600×900 | Post X — "Don't trust us. Verify." |
| `github-preview.png` | 1280×640 | Social preview del repository (Settings → Social preview). |
| `logo-512.png` | 512×512 | Logo quadrato (disco + anello oro, angoli trasparenti): header del README root e avatar dell'organization GitHub. |

Le card social (stat/quote) e la GitHub preview sono in **inglese**, coerenti
col banner ufficiale e col README root. I banner mantengono le varianti IT/EN.

## Note

- **Banner X**: l'avatar del profilo (che mostra già il logo Daimon) si
  sovrappone in basso a sinistra e X ritaglia i bordi su mobile. Nessun
  logo pieno nel banner (sarebbe un secondo cerchio identico all'avatar):
  variante A senza logo, variante B con filigrana chiara a destra. Testo
  tenuto nella fascia sicura, lontano dall'angolo in basso a sinistra.
  Banner adottato: **variante A inglese** (`banner-profilo-A-en.png`).
  Le altre tre (A-it, B-en, B-it) restano come alternative per contesti
  diversi (profilo in italiano, header di altre piattaforme, ecc.).
- **Social preview GitHub**: da caricare in *Settings → General → Social
  preview* del repo (non viene applicata automaticamente dai file nel repo).
- I template stat/quote sono riutilizzabili: per nuovi dati/frasi basta
  cambiare il testo nello script e rigenerare.
