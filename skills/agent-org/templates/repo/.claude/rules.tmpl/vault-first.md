# Vault first

Before designing or building anything, read what the project already knows. `vault/AGENTS.md` is
the routing table; open `vault/Home.md`, the newest `vault/Sessions/` note and the mission being
served, then the notes they route you to. The vault's own contract is `vault/CLAUDE.md`.

- **Every report opens with a Vault check:** notes read (paths), what was already known, what you
  reused, and what is wrong or stale.
- **Durable findings go back into the vault** — measured findings to `vault/Reports/`, findings about
  the outside world (with sources) to `vault/Research/` — linked from the folder's hub in the same
  change (`node scripts/vault-hubs.mjs`). A finding that lives only in a context window is lost.
- **Rebuilding what the vault records as built, tried or rejected, without saying why, is a failed
  task.** Searching before writing is `no-bloat.md`.
- **A stale note is marked, not silently rewritten:** `status: outdated` with a one-line reason.
