#!/usr/bin/env node
// A closed pipe is not an error: `node scripts/x.mjs | head` must not report failure.
process.stdout.on('error', (e) => { if (e && e.code === 'EPIPE') process.exit(0) })
/**
 * The channel a subagent uses to ask for the plan or the roadmap to change.
 *
 * A subagent cannot edit vault/Plan.md (scripts/hooks/agent-contract.mjs refuses it), so
 * this is how a real finding reaches the plan instead of dying in a session note nobody
 * re-reads. It appends to vault/_log/proposals.jsonl and nothing else: the supervisor
 * decides, and a decision that needed research is written to vault/Decisions/.
 *
 *   node scripts/propose.mjs --row 15 --kind split --why "..."      # subagent files one
 *   node scripts/propose.mjs --list                                  # supervisor reads open ones
 *   node scripts/propose.mjs --resolve 3 --verdict accept --because "..."
 *
 * KINDS
 *   split      this row is many rows; here is the decomposition
 *   reorder    this row blocks/unblocks another
 *   add        work exists that the plan does not name
 *   done       this row is already satisfied — with the evidence that shows it
 *   challenge  the APPROACH is wrong. Requires --why to contain a measurement.
 *
 * Refuses an unrecognised argument by name (exit 2), like every entry point here.
 */
import fs from 'node:fs'
import path from 'node:path'
import { execFileSync } from 'node:child_process'
import { fileURLToPath } from 'node:url'

// THE LOG LIVES IN THE MAIN CHECKOUT, NEVER IN A LINKED WORKTREE.
//
// Every subagent works in a worktree — that is the dispatch rule — and an earlier version
// resolved to the WORKTREE's vault/_log, so a proposal filed by the one population this
// channel exists for was written where the supervisor's `--list` cannot see it. Measured:
// an agent filed a `challenge` and two `add`s from its worktree; the main checkout's
// `--list` read "0 open of 1 filed" while three sat unseen. Silence here is
// indistinguishable from "nothing was filed", which is the verdict a broken channel invites.
//
// `--git-common-dir` is the main checkout's .git from ANY worktree. CLAUDE_PROJECT_DIR is
// itself the worktree under a subagent, so it is NOT trusted for this path when git can
// answer. `ORG_PROPOSALS_DIR` overrides both (tests use it).
function mainCheckout() {
  try {
    const g = execFileSync('git', ['rev-parse', '--path-format=absolute', '--git-common-dir'],
      { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim()
    if (g) return g.replace(/\/\.git\/?$/, '')
  } catch { /* not a repo, or no git — fall through to the source-relative root */ }
  return null
}
const SELF_ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
const ROOT = mainCheckout() || process.env.CLAUDE_PROJECT_DIR || SELF_ROOT
const LOG = path.join(process.env.ORG_PROPOSALS_DIR || path.join(ROOT, 'vault/_log'), 'proposals.jsonl')
const KINDS = new Set(['split', 'reorder', 'add', 'done', 'challenge'])
const FLAGS = new Set(['--row', '--kind', '--why', '--list', '--resolve', '--verdict', '--because', '--json'])

const argv = process.argv.slice(2)
const opt = {}
for (let i = 0; i < argv.length; i++) {
  const a = argv[i]
  if (!FLAGS.has(a)) {
    console.log(`propose: unrecognised argument '${a}' — accepts: ${[...FLAGS].sort().join(' ')}`)
    process.exit(2)
  }
  if (a === '--list' || a === '--json') { opt[a.slice(2)] = true; continue }
  const v = argv[++i]
  if (v === undefined) { console.log(`propose: ${a} needs a value`); process.exit(2) }
  opt[a.slice(2)] = v
}

/**
 * An exclusive lock around the read-modify-write in --resolve.
 *
 * MEASURED: eight supervisor `--resolve` calls interleaved with eight subagent
 * filings LOST FOUR PROPOSALS AND THREE VERDICTS. `--resolve` rewrites the whole file, so
 * any append landing between its read and its write is erased — and the thing erased is a
 * subagent's finding, which is precisely what this channel exists to carry. Filing is a
 * single O_APPEND write and is safe on its own; only the rewrite needs the lock.
 *
 * `wx` fails if the lock exists, which is the atomic test-and-set. A lock older than
 * STALE_MS is broken on the assumption its holder died, because a channel that can wedge
 * permanently is worse than one that can race.
 */
const LOCK = LOG + '.lock'
const STALE_MS = 30_000
function withLock(fn) {
  const deadline = Date.now() + 20_000
  for (;;) {
    try {
      const fd = fs.openSync(LOCK, 'wx')
      fs.writeSync(fd, String(process.pid)); fs.closeSync(fd)
      try { return fn() } finally { try { fs.unlinkSync(LOCK) } catch { /* already gone */ } }
    } catch (e) {
      if (e.code !== 'EEXIST') throw e
      try {
        if (Date.now() - fs.statSync(LOCK).mtimeMs > STALE_MS) { fs.unlinkSync(LOCK); continue }
      } catch { continue }
      if (Date.now() > deadline) {
        console.log('propose: could not take the proposals lock in 20s — another process is holding it.')
        console.log(`If nothing else is running, remove ${LOCK} and retry.`)
        process.exit(2)
      }
      Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, 25 + Math.random() * 50)
    }
  }
}

function readAll() {
  if (!fs.existsSync(LOG)) return []
  return fs.readFileSync(LOG, 'utf8').split('\n').filter(Boolean).map((l, i) => {
    try { const o = JSON.parse(l); o.n = i + 1; return o } catch { return null }
  }).filter(Boolean)
}

if (opt.list) {
  const rows = readAll()
  const open = rows.filter((r) => !r.verdict)
  if (opt.json) { console.log(JSON.stringify({ open, total: rows.length }, null, 2)); process.exit(0) }
  console.log(`PROPOSALS — ${open.length} open of ${rows.length} filed`)
  for (const r of open) {
    console.log(`  #${r.n}  row ${r.row}  [${r.kind}]  by ${r.by}  ${r.at}`)
    console.log(`        ${String(r.why).slice(0, 200)}`)
  }
  if (!open.length) console.log('  (none — every proposal has a recorded verdict)')
  console.log('\nThe supervisor must answer each with EITHER a measurement that rejects it,')
  console.log('OR research plus a ruling written to vault/Decisions/. Silence is not a verdict.')
  process.exit(0)
}

if (opt.resolve) {
  const n = Number(opt.resolve)
  const rows = readAll()
  const row = rows.find((r) => r.n === n)
  if (!row) { console.log(`propose: no proposal #${opt.resolve}`); process.exit(2) }
  if (!['accept', 'reject'].includes(String(opt.verdict))) { console.log('propose: --verdict must be accept or reject'); process.exit(2) }
  if (!opt.because || String(opt.because).trim().length < 20) {
    console.log('propose: --because must say WHY, in at least 20 characters.')
    console.log('A verdict with no reason is how the same proposal gets filed again next week.')
    process.exit(2)
  }
  const role = (process.env.ORG_ROLE || 'subagent').toLowerCase()
  if (role !== 'supervisor' && role !== 'owner') {
    console.log(`propose: --resolve is the supervisor's, and ORG_ROLE is '${role}'. A subagent may file, never rule.`)
    process.exit(2)
  }
  // Re-read INSIDE the lock: the rows loaded above were read before it was taken, so a
  // filing may have landed since. Rewriting from the stale copy is exactly the lost update.
  withLock(() => {
    const fresh = readAll()
    const target = fresh.find((r) => r.n === n)
    if (!target) { console.log(`propose: #${n} vanished while taking the lock`); process.exit(2) }
    target.verdict = opt.verdict
    target.because = opt.because
    target.resolved_at = new Date().toISOString()
    const all = fresh.map((r) => { const { n: _n, ...rest } = r; return rest })
    const tmp = LOG + '.tmp'
    fs.writeFileSync(tmp, all.map((r) => JSON.stringify(r)).join('\n') + '\n')
    fs.renameSync(tmp, LOG)   // atomic swap: a reader never sees a half-written ledger
  })
  console.log(`propose: #${n} ${opt.verdict.toUpperCase()} — ${opt.because}`)
  if (opt.verdict === 'accept') console.log('Now make the plan edit yourself, and cite this proposal number in the commit.')
  process.exit(0)
}

// ---- filing one ----
if (!opt.row || !/^\d+(\.\d+)*$/.test(String(opt.row))) { console.log('propose: --row <n> is required (e.g. 15 or 15.2)'); process.exit(2) }
if (!KINDS.has(String(opt.kind))) { console.log(`propose: --kind must be one of ${[...KINDS].join(' ')}`); process.exit(2) }
const why = String(opt.why || '').trim()
if (why.length < 30) {
  console.log('propose: --why must be at least 30 characters.')
  console.log('Name what you FOUND and how you know. "this row is wrong" is not a proposal.')
  process.exit(2)
}
if (opt.kind === 'challenge' && !/\d/.test(why)) {
  console.log('propose: a --kind challenge must contain a MEASUREMENT — a count, a time, a size, a sha.')
  console.log('vault/AGENTS.md §5: a disagreement with no number attached is noise here.')
  process.exit(2)
}
fs.mkdirSync(path.dirname(LOG), { recursive: true })
const rec = {
  at: new Date().toISOString(),
  by: process.env.ORG_AGENT || process.env.ORG_ROLE || 'subagent',
  row: String(opt.row), kind: String(opt.kind), why,
}
// The append takes the lock too. An O_APPEND write is atomic against other appends, but
// NOT against --resolve's rewrite: measured, an append landing between the resolve's
// (locked) read and its rename was still lost — 1 of 28 after the first fix, 4 of 28
// before it. Filing is rare and cheap; correctness beats the lock-free write.
withLock(() => { fs.appendFileSync(LOG, JSON.stringify(rec) + '\n') })
console.log(`propose: filed against row ${rec.row} [${rec.kind}]. The supervisor sees it with:`)
console.log('  node scripts/propose.mjs --list')
