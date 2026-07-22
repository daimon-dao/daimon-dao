# Social assets — Daimon DAO

Grafiche social generate dall'identità visiva della dApp (logo, font Inter,
palette blu notte `#0a1128` · oro `#c9a227` · crema `#f5e9c8`). Stile sobrio,
"istituzionale crypto": nessun effetto pump, nessun logo di terze parti,
nessun grafico di prezzo. Font Inter (lo stesso della dApp), max 3 colori.

Rigenerabili con lo script Node in `scripts/` (usa `@resvg/resvg-js` +
i TTF statici di Inter; vedi commento in testa allo script).

| File | Dimensioni | Uso |
|---|---|---|
| `banner-profilo-it.png` | 1500×500 | Header profilo X/Twitter (IT). Logo alto-sinistra fuori dalla safe-zone dell'avatar. |
| `banner-profilo-en.png` | 1500×500 | Header profilo X/Twitter (EN). |
| `stat-fee.png` | 1600×900 | Post X — "11% → 4%", fee decise dalla DAO. |
| `stat-timelock.png` | 1600×900 | Post X — "604.800" secondi di timelock. |
| `stat-owner-mint.png` | 1600×900 | Post X — "0 owner · 0 mint". |
| `stat-supply.png` | 1600×900 | Post X — "1000B → 21B" con barra di deflazione. |
| `quote-codice.png` | 1600×900 | Post X — "Gli umani sbagliano. Il codice no." |
| `quote-verificate.png` | 1600×900 | Post X — "Non chiedeteci fiducia. Verificate." |
| `github-preview.png` | 1280×640 | Social preview del repository (Settings → Social preview). |

## Note

- **Banner X**: X sovrappone l'avatar nell'angolo in basso a sinistra e
  ritaglia i bordi su mobile. Logo e testo sono tenuti nella fascia centrale
  sicura; il logo è in alto a sinistra, sopra la zona dell'avatar.
- **Social preview GitHub**: da caricare in *Settings → General → Social
  preview* del repo (non viene applicata automaticamente dai file nel repo).
- I template stat/quote sono riutilizzabili: per nuovi dati/frasi basta
  cambiare il testo nello script e rigenerare.
