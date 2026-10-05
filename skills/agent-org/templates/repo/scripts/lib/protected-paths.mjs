/**
 * THE protected paths — declared ONCE, here.
 *
 * In the project this kit was distilled from, this list once lived in five places — the
 * hook, the landing gate, and three prose documents — and one of the documents granted away
 * what the other four forbade ("an agent may write status fields in existing notes'
 * frontmatter", and Plan.md has frontmatter). A probe agent hit that contradiction, reported
 * that three sources disagreed about what it was allowed to do, and stopped.
 *
 * One quantity, one owner (.claude/rules/no-bloat.md). The two enforcers import this; the
 * prose documents are held to it by scripts/gates/protected-paths.mjs, which fails when a
 * document stops naming an entry or starts granting one away.
 */
export const PROTECTED = [
  { path: 'vault/Plan.md', what: 'the ordered work queue' },
  { path: 'vault/Roadmap.md', what: 'the track-level delivery checklist' },
  { path: 'vault/Decisions/', what: 'rulings that are law until superseded' },
  { path: '.claude/rules/', what: 'the laws every gate obeys' },
  { path: '.claude/settings.json', what: 'the hooks that enforce these laws' },
]

/** The roles (ORG_ROLE) that may write them. Everything else proposes. */
export const AUTHORS = ['supervisor', 'owner']

/** What a LANE WORKER (and its sub-agents) may not write, though an interactive agent may:
 *  the session trail and memory are the overseer's (templates/lane/agent-rules.md). Parallel
 *  workers writing them on separate branches conflict at MERGE, and a worker's memory would load
 *  into every later session. Same matching as PROTECTED; `memory` also catches Claude Code's
 *  native auto-memory directory (~/.claude/projects/<p>/memory/). */
export const WORKER_OFF_LIMITS = [
  { path: 'vault/Sessions/', what: 'the session notes (the overseer\'s handoff trail)' },
  { path: 'vault/Home.md', what: 'the current-state page the overseer keeps' },
  { path: 'vault/Reports/audits/SESSION-REGISTRY.md', what: 'the session registry' },
  { path: '.claude/agent-memory/', what: 'sub-agent memory' },
  { memory: /\/\.claude\/projects\/[^/]+\/memory\//, path: '~/.claude/projects/<p>/memory/', what: 'Claude Code auto-memory' },
]

/** Path -> {path, what} when it names a protected file in ANY checkout, else null.
 *  Case-insensitive and suffix-matched: `vault/plan.md` reaches the plan on a
 *  case-insensitive filesystem, and an agent in a worktree can reach the main checkout's
 *  plan by absolute path. Both were measured; both are closed here. */
export function protectedHit(p) { return hitIn(PROTECTED, p) }

/** Path -> entry when a lane worker may not write it, else null. */
export function workerOffLimitsHit(p) { return hitIn(WORKER_OFF_LIMITS, p) }

function hitIn(list, p) {
  const norm = String(p || '').replace(/\\/g, '/').replace(/\/+/g, '/')
  // resolve . and .. without needing node:path, so this stays importable anywhere
  const parts = []
  for (const seg of norm.split('/')) {
    if (seg === '.' || seg === '') { if (parts.length === 0 && seg === '') parts.push(''); continue }
    if (seg === '..') { if (parts.length && parts[parts.length - 1] !== '..') parts.pop(); continue }
    parts.push(seg)
  }
  const clean = parts.join('/').toLowerCase()
  for (const entry of list) {
    if (entry.memory) { if (entry.memory.test('/' + clean)) return entry; continue }
    const needle = entry.path.toLowerCase()
    if (needle.endsWith('/')) {
      if (clean.includes('/' + needle) || clean.startsWith(needle)) return entry
    } else if (clean === needle || clean.endsWith('/' + needle)) {
      return entry
    }
  }
  return null
}
