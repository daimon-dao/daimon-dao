# Social assets — Daimon DAO

Grafiche social generate dall'identità visiva della dApp (logo, font Inter,
palette blu notte `#0a1128` · oro `#c9a227` · crema `#f5e9c8`). Stile sobrio,
"istituzionale crypto": nessun effetto pump, nessun logo di terze parti,
nessun grafico di prezzo. Font Inter (lo stesso della dApp), max 3 colori.

Rigenerabili con lo script Node in `scripts/` (usa `@resvg/resvg-js` +
i TTF statici di Inter; vedi commento in testa allo script).

| File | Dimensioni | Uso |
|---|---|---|
| `banner-profilo-A-it/en.png` | 1500×500 | Header profilo X — **variante A** (senza logo). L'avatar mostra già il logo Daimon: qui il testo è protagonista, centrato, con sinistra e basso liberi per l'avatar. |
| `banner-profilo-B-it/en.png` | 1500×500 | Header profilo X — **variante B** (filigrana). Testo a sinistra, simbolo del logo come filigrana chiara tono-su-tono nell'angolo destro (non un secondo logo pieno). |
| `stat-fee.png` | 1600×900 | Post X — "11% → 4%", fee decise dalla DAO. |
| `stat-timelock.png` | 1600×900 | Post X — "604.800" secondi di timelock. |
| `stat-owner-mint.png` | 1600×900 | Post X — "0 owner · 0 mint". |
| `stat-supply.png` | 1600×900 | Post X — "1000B → 21B" con barra di deflazione. |
| `quote-codice.png` | 1600×900 | Post X — "Gli umani sbagliano. Il codice no." |
| `quote-verificate.png` | 1600×900 | Post X — "Non chiedeteci fiducia. Verificate." |
| `github-preview.png` | 1280×640 | Social preview del repository (Settings → Social preview). |

## Note

- **Banner X**: l'avatar del profilo (che mostra già il logo Daimon) si
  sovrappone in basso a sinistra e X ritaglia i bordi su mobile. Nessun
  logo pieno nel banner (sarebbe un secondo cerchio identico all'avatar):
  variante A senza logo, variante B con filigrana chiara a destra. Testo
  tenuto nella fascia sicura, lontano dall'angolo in basso a sinistra.
  Le due varianti sono alternative da scegliere: adottata una, l'altra
  (e la lingua non usata) si possono rimuovere.
- **Social preview GitHub**: da caricare in *Settings → General → Social
  preview* del repo (non viene applicata automaticamente dai file nel repo).
- I template stat/quote sono riutilizzabili: per nuovi dati/frasi basta
  cambiare il testo nello script e rigenerare.
