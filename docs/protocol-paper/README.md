# Daimon DAO — Protocol paper

**Current version: v0.2** (post-audit release, 2026-09-11). Up to v0.1 the
document was published as the *whitepaper*; the name changed, the document
and its history did not. The **English edition is the primary document**;
the Italian edition is a translation. If the two ever diverge, the English
text prevails.

- [Daimon_Protocol_Paper_EN_v0.2.pdf](Daimon_Protocol_Paper_EN_v0.2.pdf) — English (primary)
- [Daimon_Protocol_Paper_IT_v0.2.pdf](Daimon_Protocol_Paper_IT_v0.2.pdf) — Italiano

Previous versions, kept exactly as released:

- v0.1 (2026-07-27, draft pending the external audit, tag `whitepaper-v0.1`):
  [Daimon_Whitepaper_EN_v0.1.pdf](Daimon_Whitepaper_EN_v0.1.pdf) ·
  [Daimon_Whitepaper_IT_v0.1.pdf](Daimon_Whitepaper_IT_v0.1.pdf)

## Versioning policy

- **Previous versions are never removed.** Each release adds new files next to
  the old ones, so any two versions can be compared side by side and old
  citations keep resolving. The v0.1 files keep their original names.
- Every release is marked with an **annotated git tag** (`protocol-paper-vX.Y`;
  the first release carries the old name, `whitepaper-v0.1`), the same method
  used to freeze the audited contracts (`audit-final`). A tag makes the cited
  version immutable: check out the tag and you get exactly the files that
  were released.
- The **Markdown sources** (`protocol_paper_EN.md`, `protocol_paper_IT.md`)
  are versioned in git alongside the PDFs. Any change between releases is
  therefore mechanically verifiable:

  ```sh
  git diff -M whitepaper-v0.1 protocol-paper-v0.2 -- docs/whitepaper/whitepaper_EN.md docs/protocol-paper/protocol_paper_EN.md
  ```

  (the `-M` and the two paths are needed across the v0.1 → v0.2 rename;
  `git log --follow -- docs/protocol-paper/protocol_paper_EN.md` walks the
  whole history of the file.)

## Building the PDFs

The PDFs are generated from the sources by [`build_pdf.py`](build_pdf.py)
(Python 3, `reportlab`, `pikepdf`, and the DejaVu font family):

```sh
python build_pdf.py --fonts /path/to/dejavu-fonts-ttf/ttf
```

The script writes both editions, sets the document metadata, and linearizes
the files for web preview. Rebuilding an existing release from its tag must
reproduce the released content page for page; a change in wording is a new
version, never a silent rebuild.

See [CHANGELOG.md](CHANGELOG.md) for the release history and what changed in
each version.
