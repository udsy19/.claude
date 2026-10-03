# `evidence/` — captures of record

One directory per line or mission, holding the screenshots, logs and JSON a claim was proven with.
A session note or report without an evidence path proved nothing (`vault/CLAUDE.md`). Evidence lives
OUTSIDE the vault so a vault reorganisation never breaks a link a gate reads.

**Every NEW `evidence/<dir>/` carries a `README.md`** that names the script or gate that produced or
reads it — a path that exists, which mentions `evidence/<dir>` on a non-comment line. A landing that
adds files must say why in an `EVIDENCE-GROWTH:` paragraph of its commit message. Both are graded by
`scripts/gates/sprawl.mjs`.

Captures a gate publishes as a side effect go to a gitignored scratch directory; publishing to
`evidence/` is a deliberate act (gate-independence law 10: a check must not rewrite the record).
