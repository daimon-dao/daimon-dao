# Daimon DAO — Whitepaper

**Current version: v0.1** (draft, pending external security audit).
The **English edition is the primary document**; the Italian edition is a
translation. If the two ever diverge, the English text prevails.

- [Daimon_Whitepaper_EN_v0.1.pdf](Daimon_Whitepaper_EN_v0.1.pdf) — English (primary)
- [Daimon_Whitepaper_IT_v0.1.pdf](Daimon_Whitepaper_IT_v0.1.pdf) — Italiano

## Versioning policy

- **Previous versions are never removed.** Each release adds new files next to
  the old ones, so any two versions can be compared side by side and old
  citations keep resolving.
- Every release is marked with an **annotated git tag** (`whitepaper-vX.Y`),
  the same method used to freeze the audit scope of the contracts
  (`audit-scope-v2`). A tag makes the cited version immutable: check out the
  tag and you get exactly the files that were released.
- The **Markdown sources** (`whitepaper_EN.md`, `whitepaper_IT.md`) are
  versioned in git alongside the PDFs. Any change between releases is
  therefore mechanically verifiable:

  ```sh
  git diff whitepaper-v0.1 whitepaper-v1.0 -- docs/whitepaper/whitepaper_EN.md
  ```

See [CHANGELOG.md](CHANGELOG.md) for the release history and what changed in
each version.
