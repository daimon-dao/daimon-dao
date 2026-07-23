# Social assets — Daimon DAO

Social graphics generated from the dApp visual identity (logo, Inter font,
night-blue `#0a1128` · gold `#c9a227` · cream `#f5e9c8` palette). Sober,
"institutional crypto" style: no pump effects, no third-party logos, no price
charts. Inter font (the same as the dApp), at most 3 colors.

Regenerable with the Node script in `scripts/` (uses `@resvg/resvg-js` +
Inter's static TTFs; see the comment at the top of the script).

| File | Size | Use |
|---|---|---|
| **`banner-profilo-A-en.png`** | 1500×500 | ⭐ **OFFICIAL BANNER.** X profile header — variant A (no logo), English. The text is the protagonist, centered, with the left and bottom kept clear for the avatar. |
| `banner-profilo-A-it.png` | 1500×500 | Alternative — variant A (no logo), Italian. |
| `banner-profilo-B-en/it.png` | 1500×500 | Alternative — variant B (watermark): text on the left, the logo symbol as a light tone-on-tone watermark in the right corner (not a second full logo). Useful for contexts other than the X profile. |
| `stat-fee.png` | 1600×900 | X post — "11% → 4%", "decided by the DAO, not by a boss". |
| `stat-timelock.png` | 1600×900 | X post — "604,800" seconds of timelock. |
| `stat-owner-mint.png` | 1600×900 | X post — "0 owner · 0 mint". |
| `stat-supply.png` | 1600×900 | X post — "1000B → 21B" with deflation bar. |
| `quote-codice.png` | 1600×900 | X post — "Humans make mistakes. Code doesn't." |
| `quote-verificate.png` | 1600×900 | X post — "Don't trust us. Verify." |
| `github-preview.png` | 1280×640 | Repository social preview (Settings → Social preview). |
| `logo-512.png` | 512×512 | Square logo (disc + gold ring, transparent corners): root README header and the GitHub organization avatar. |

The social cards (stat/quote) and the GitHub preview are in **English**,
consistent with the official banner and the root README. The banners keep the
IT/EN variants.

## Notes

- **X banner**: the profile avatar (which already shows the Daimon logo)
  overlaps the bottom-left and X crops the edges on mobile. No full logo in
  the banner (it would be a second circle identical to the avatar): variant A
  without logo, variant B with a light watermark on the right. Text kept in
  the safe band, away from the bottom-left corner. Adopted banner: **variant A
  English** (`banner-profilo-A-en.png`). The other three (A-it, B-en, B-it)
  remain as alternatives for other contexts.
- **GitHub social preview**: to be uploaded in *Settings → General → Social
  preview* of the repo (it is not applied automatically from the files in the
  repo).
- The stat/quote templates are reusable: for new data/phrases just change the
  text in the script and regenerate.
