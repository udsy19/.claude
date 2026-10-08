# Agent isolation

Workers run with permissions skipped (`--dangerously-skip-permissions`) and can run any command. So the loop
doesn't rely on what an agent chooses to do. It relies on what the operating system lets it do. Every worker, and
a Claude supervisor, runs as a **whole process inside the sandbox runtime**:
[`@anthropic-ai/sandbox-runtime`](https://github.com/anthropics/sandbox-runtime) (`srt`), which uses Seatbelt on
macOS and bubblewrap on Linux.

## Why this mechanism

- **The built-in Bash sandbox isn't enough on its own.** It confines shell commands only. Claude Code's Read,
  Edit and Write tools, its hooks and MCP servers run outside it
  ([sandboxing](https://code.claude.com/docs/en/sandboxing#what-runs-outside-the-sandbox)), and by default it can
  read "most of the machine, including credential files such as `~/.ssh`".
- **The docs prescribe this for unattended runs:** "Always run `--dangerously-skip-permissions` sessions inside a
  container, a VM, or the sandbox runtime, so that file tools, MCP servers, and hooks are also inside the
  boundary" ([sandbox environments](https://code.claude.com/docs/en/sandbox-environments#how-isolation-relates-to-permission-modes)).
- **A container would need Docker on every host.** The sandbox runtime needs no daemon. It runs as the org's own
  unprivileged user, which `claude` requires: it refuses bypass mode as root.
- **Hooks and a separate HOME aren't boundaries.** The audit beat both (findings A5, A6, A8).

## The layers, and what each one stops

| Layer | What it does | Stops (audit 2026-10) |
|---|---|---|
| **Identity** | The org runs as one unprivileged user: the owner locally, `worker_user` on a VPS. Never root. | Running as root; access to other users' files |
| **Filesystem** | Reads of the loop user's HOME, `ORG_ROOT` and the main repo are denied. Reads come back only for the agent's own workspace, outbox, home, renders and build dirs, the repo's object store (read-only, through git alternates), Claude Code's binary, main's trusted `scripts/`, and `isolation.allow_read`. Writes go only to the workspace, outbox, home, renders, build dir and the build-queue locks. Inside the workspace, `.claude/` and `.mcp.json` stay unwritable. | Reading `~/.ssh` (A6); reading or forging `rulings.md`, `org.json` or `ORG_ROOT/state/` (A5); reading other agents' prompts; rewriting its own settings, hooks or MCP config (W1) |
| **Own clone** | The workspace is the agent's own `git clone --shared`, not a `git worktree`: it has no write path to the main repo's refs. `finish()` fetches the agent's `HEAD` into `lane/<lane>/<name>`. | Moving `main` or another lane's branch from inside a workspace |
| **Trusted hooks** | `.claude/settings.json` runs the hooks from `$AGENT_ORG_SCRIPTS`, main's `scripts/` extracted per commit into `ORG_ROOT/trusted/<sha>/` (readable, not writable). | A worker neutering its own contract hook by editing its workspace (A8) |
| **Network** | No direct route out. The runtime's proxy admits only `api.anthropic.com`, `claude.ai`, `platform.claude.com` and `isolation.allowed_domains` (`supervisor.web_domains` for the supervisor). | Exfiltrating what an agent can read (A10, and every A6 path) |
| **Environment** | Rebuilt from an allowlist: PATH, LANG, a per-agent HOME and TMPDIR, the org's own variables, `worker_env`. It's passed as the process environment, never in an argv. No `LANE_ROOT`/`ORG_ROOT`. | The loop's secrets reaching an agent (A6) |
| **Supervisor** | Same runtime, read-only profile: it reads the integration checkout and the lane's renders, writes only its own HOME. `--tools Read,Grep,Glob,WebSearch,WebFetch`. | A Claude supervisor reading the owner's files and fetching them out (A10) |
| **Leftovers** | A finished, killed or timed-out agent's uncommitted files are never committed, merged or pushed. They become a local patch in `<lane>/recovered/`, which no agent can read. | Half-done work and untracked secrets reaching a branch or origin (A7, F4c) |
| **Untrusted text** | Worker reports reach the supervisor fenced as `UNTRUSTED WORKER REPORT`, with `===` block markers neutralised. LEARN entries are marked unverified. | Report text posing as supervisor blocks or owner instructions (C4, A12) |
| **Process identity** | Each launch carries a token in the launcher's command line. Adoption and deadline kills check it. Pid files are written atomically; an unreadable one is quarantined to `pids/bad/`. `gc` keeps any workspace a live process uses. | A reused pid being adopted or killed (F5); a lost pid file orphaning a live agent into `gc` (F4a) |

`test-adv-isolation.sh` runs the real loop with a hostile worker and a hostile supervisor inside the runtime, and
checks every row above against real state afterwards. On `main@e318f8b` it fails 28 of 28.

## Setting it up

1. Install the runtime: `npm i -g @anthropic-ai/sandbox-runtime`. On Linux, also `apt-get install bubblewrap socat ripgrep`.
2. **Ubuntu 24.04+** blocks the user namespaces bubblewrap needs
   (`sysctl kernel.apparmor_restrict_unprivileged_userns` prints `1`). As root, add the profile the docs give
   ([sandboxing: Set up Linux](https://code.claude.com/docs/en/sandboxing#set-up-linux-and-wsl2)), then `systemctl reload apparmor`:
   ```
   abi <abi/4.0>,
   include <tunables/global>
   profile bwrap /usr/bin/bwrap flags=(unconfined) {
     userns,
     include if exists <local/bwrap>
   }
   ```
3. **Worker auth.** Agents get their own HOME, so they don't see the user's Claude login. Run `claude setup-token`
   and save the token to `isolation.auth_token_file` (default `<ORG_ROOT>/secrets/claude-oauth-token`, mode 600).
   The loop passes it to each agent as `CLAUDE_CODE_OAUTH_TOKEN`, in the environment, never in an argv.
4. **Builds:** toolchains under HOME (`~/.cargo`, `~/.rustup`, `~/.nvm`) are denied by default. List them in
   `isolation.allow_read`, and package registries in `isolation.allowed_domains`.

`bootstrap-host.sh` checks steps 1–3 and prints the exact fix. `supervise.py` refuses to start a lane while
`isolation.mode` is `srt` and the runtime is missing.

`isolation.mode: "none"` turns all of this off. Agents then run with everything the org user can read and write.
It exists for test fixtures; every unisolated dispatch is logged as `UNISOLATED`.

## What remains

- **The agent's own token.** A worker can read the token it authenticates with. The network allowlist limits
  where it could send it.
- **Allowed domains.** The proxy decides on the hostname without inspecting TLS, so a broad allowed domain can be
  used for domain fronting (docs: [security limitations](https://code.claude.com/docs/en/sandboxing#security-limitations)).
  Keep `allowed_domains` narrow.
- **`worktree_links`** (for example a shared `.env.local`) are readable by agents by design. Don't link secrets an
  agent shouldn't hold.
- **One uid.** Workers and the loop share a uid. The boundary between them is the runtime, not file ownership, so
  a sandbox escape is an escape into the org user. A second OS user per worker would add depth, at the cost of
  privileged launching.
- **Linux deny lists.** The runtime builds them once, at launch. It doesn't cover files a session creates later,
  such as a nested `git clone` ([sandbox runtime](https://code.claude.com/docs/en/sandbox-environments#what-the-runtime-blocks-on-its-own)).
- **The runtime is a beta research preview.** Its configuration format may change.
