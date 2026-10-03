#!/usr/bin/env node
// A closed pipe is not an error: `node scripts/x.mjs | head` must not report failure.
process.stdout.on('error', (e) => { if (e && e.code === 'EPIPE') process.exit(0) })
/**
 * "Who already implements this?" — the question .claude/rules/no-bloat.md opens with, and
 * the one vault/Map-code.md cannot answer.
 *
 * Map-code is a STRUCTURE map. An agent asked for a check found all three existing
 * implementations by grepping, and a plan row named a symbol that existed only on an
 * unlanded branch, so an agent trusting main would have written a second one. Both are the
 * fifth-rediscovery failure. This answers the question directly.
 *
 *   node scripts/where.mjs parseConfig           # defined where, referenced by what
 *   node scripts/where.mjs --loose config        # substring, for when you half-remember it
 *   node scripts/where.mjs --branches parseConfig  # ALSO search unlanded work branches
 *
 * Three sources, in order, and it says which answered:
 *   1. the AST graph (graphify-out/graph.json, when present) — exact symbols with their file
 *   2. `git grep` on MAIN — the ref `main`, or `origin/main` when there is no local main,
 *      NAMED in the heading with its commit; and, separately, on HEAD when HEAD is not main
 *   3. `git grep` across unlanded work branches (`lane/*` by default)
 *
 * WHY THE MAIN SECTION NAMES ITS REF. An earlier version greped `HEAD` and printed the
 * result under `ON MAIN`. From a branch worktree — the one situation an agent is routed
 * here for — a symbol that existed ONLY on that branch was reported as already on main.
 * A tool built to prevent a rediscovery was causing one. scripts/where.test.mjs holds the
 * two refs apart.
 *
 * `--branches` lists a file only when its CONTENT differs both from main and from the
 * branch's merge-base with main — anything else is main's bytes, old or new. It used to
 * list every file a branch merely CARRIED: 97.5% of its hits were not unlanded work.
 *
 * Configuration (environment):
 *   ORG_MAIN_BRANCH   the integration branch                       (default: main)
 *   ORG_BRANCH_GLOBS  unlanded-work branch globs, space-separated  (default: lane/*)
 *   ORG_SEARCH_PATHS  paths the ON MAIN / HEAD greps cover, space-separated
 *                     (default: the whole tree)
 *
 * Exits 1 when NOTHING matches anywhere, because "no result" must be distinguishable from
 * "the tool did not look" — an agent reading a silent 0 as "does not exist" is the defect.
 * Exits 2 when a git call failed: no negative conclusion is available from that run.
 */
import fs from 'node:fs'
import path from 'node:path'
import { execFileSync } from 'node:child_process'
import { fileURLToPath } from 'node:url'

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
const GRAPH = path.join(ROOT, 'graphify-out', 'graph.json')
const MAIN_BRANCH = process.env.ORG_MAIN_BRANCH || 'main'
const BRANCH_GLOBS = (process.env.ORG_BRANCH_GLOBS || 'lane/*').split(/[\s,]+/).filter(Boolean)
const SEARCH_PATHS = (process.env.ORG_SEARCH_PATHS || '').split(/[\s,]+/).filter(Boolean)
const FLAGS = new Set(['--loose', '--branches'])
const argv = process.argv.slice(2)
let LOOSE = false, BRANCHES = false, name = null
for (const a of argv) {
  if (a.startsWith('--')) {
    if (!FLAGS.has(a)) { console.log(`where: unrecognised argument '${a}' — accepts: --loose, --branches, and one name`); process.exit(2) }
    if (a === '--loose') LOOSE = true
    if (a === '--branches') BRANCHES = true
  } else if (name === null) name = a
  else { console.log(`where: one name at a time (got '${name}' and '${a}')`); process.exit(2) }
}
if (!name) { console.log('where: give a symbol name. e.g. node scripts/where.mjs parseConfig'); process.exit(2) }
if (name.length < 3) { console.log(`where: '${name}' is too short to search usefully — 3 characters minimum`); process.exit(2) }

// A FAILED git call and an EMPTY result are different facts. git grep exits 1 on "no
// match" — a real empty — and 128 on a bad revision, which is a broken search. Only the
// first may be reported as a negative.
const searchBroke = []
const git = (...a) => {
  try { return execFileSync('git', a, { cwd: ROOT, encoding: 'utf8', maxBuffer: 32 * 1024 * 1024, stdio: ['ignore', 'pipe', 'pipe'] }) }
  catch (e) {
    if (e.status === 1) return ''            // grep: no match. A genuine empty.
    searchBroke.push(`${a.slice(0, 3).join(' ')} → ${String(e.stderr || e.message).split('\n')[0].slice(0, 90)}`)
    return null                               // anything else: the search did not happen.
  }
}
const text = (v) => (v === null ? '' : v)
let found = 0
console.log(`WHERE — "${name}"${LOOSE ? ' (loose)' : ''}\n`)

// ---- 1. the AST graph -------------------------------------------------------
let graphAnswered = 0
if (fs.existsSync(GRAPH)) {
  const g = JSON.parse(fs.readFileSync(GRAPH, 'utf8'))
  const byId = new Map(g.nodes.map((n) => [n.id, n]))
  const hit = (l) => LOOSE ? String(l || '').toLowerCase().includes(name.toLowerCase()) : String(l || '') === name || String(l || '').startsWith(name + '(')
  const defs = g.nodes.filter((n) => hit(n.label) && (n.source_file || '').trim())
  if (defs.length) {
    console.log(`DEFINED  (AST graph, ${defs.length})`)
    for (const d of defs.slice(0, 20)) console.log(`  ${(d.label || '').slice(0, 44).padEnd(46)} ${d.source_file}`)
    if (defs.length > 20) console.log(`  … and ${defs.length - 20} more`)
    const ids = new Set(defs.map((d) => d.id))
    const refs = new Set()
    for (const e of (g.edges || g.links || [])) {
      const s = typeof e.source === 'object' ? e.source.id : e.source
      const t = typeof e.target === 'object' ? e.target.id : e.target
      if (ids.has(t) && byId.get(s)?.source_file) refs.add(byId.get(s).source_file)
      if (ids.has(s) && byId.get(t)?.source_file) refs.add(byId.get(t).source_file)
    }
    const others = [...refs].filter((f) => !defs.some((d) => d.source_file === f))
    if (others.length) {
      console.log(`\nREACHES  (${others.length} other file(s))`)
      for (const f of others.slice(0, 12)) console.log(`  ${f}`)
      if (others.length > 12) console.log(`  … and ${others.length - 12} more`)
    }
    graphAnswered = defs.length; found += defs.length
    console.log()
  }
} else {
  console.log('(no graphify-out/graph.json — skipping the AST source; run /graphify to add it)\n')
}

// ---- 2. git grep, on MAIN and (separately) on HEAD --------------------------
const commitOf = (ref) => text(git('rev-parse', '--verify', '--quiet', `${ref}^{commit}`)).trim() || null

// WHICH REF IS MAIN, decided once and printed. A repo with neither is one where this
// question has no answer, and the tool REFUSES by name rather than silently answering a
// different question.
const MAIN_REF = [MAIN_BRANCH, `origin/${MAIN_BRANCH}`].find((r) => commitOf(r)) || null
if (!MAIN_REF) {
  console.log(`where: REFUSED — neither '${MAIN_BRANCH}' nor 'origin/${MAIN_BRANCH}' resolves in this repository,`)
  console.log(`  so "is it on main?" has no answer here (${ROOT}).`)
  console.log('  Fetch the remote, or set ORG_MAIN_BRANCH, and re-run. A tool that answers about')
  console.log('  HEAD under the heading ON MAIN is worse than no tool.')
  process.exit(2)
}
const MAIN_SHA = commitOf(MAIN_REF)
const HEAD_SHA = commitOf('HEAD')
const HEAD_NAME = text(git('rev-parse', '--abbrev-ref', 'HEAD')).trim() || 'HEAD'
const HEAD_IS_MAIN = !!HEAD_SHA && HEAD_SHA === MAIN_SHA

/** grep ONE named revision, grouped by file. The rev is a literal prefix on every line. */
const grepRev = (rev) => {
  const lines = text(git('grep', '-n', '-I', LOOSE ? '-i' : '-w', '--', name, rev, '--', ...SEARCH_PATHS))
    .split('\n').filter(Boolean)
  const byFile = new Map()
  for (const l of lines) {
    if (!l.startsWith(`${rev}:`)) continue
    const m = /^([^:]+):(\d+):(.*)$/.exec(l.slice(rev.length + 1))
    if (!m) continue
    if (!byFile.has(m[1])) byFile.set(m[1], [])
    byFile.get(m[1]).push([m[2], m[3].trim().slice(0, 96)])
  }
  return { lines, byFile }
}
const listHits = (byFile) => {
  for (const [f, hits] of [...byFile].slice(0, 14)) {
    console.log(`  ${f}`)
    for (const [ln, txt] of hits.slice(0, 2)) console.log(`      :${ln}  ${txt}`)
    if (hits.length > 2) console.log(`      … ${hits.length - 2} more in this file`)
  }
  if (byFile.size > 14) console.log(`  … and ${byFile.size - 14} more files`)
}

const onMain = grepRev(MAIN_REF)
if (onMain.lines.length) {
  console.log(`ON MAIN  (git grep ${MAIN_REF} ${String(MAIN_SHA).slice(0, 9)}, ${onMain.lines.length} line(s) in ${onMain.byFile.size} file(s))`)
  listHits(onMain.byFile)
  found += onMain.lines.length
} else {
  // PRINTED EVEN WHEN EMPTY: a silent absence is indistinguishable from a search that never ran.
  console.log(`ON MAIN  none — git grep ${MAIN_REF} (${String(MAIN_SHA).slice(0, 9)}) matched 0 line(s)`)
}
console.log()

if (HEAD_IS_MAIN) {
  console.log(`ON THIS BRANCH (HEAD)  HEAD IS ${MAIN_REF} (${String(HEAD_SHA).slice(0, 9)}) — the section above is this checkout`)
} else {
  const onHead = grepRev('HEAD')
  if (onHead.lines.length) {
    console.log(`ON THIS BRANCH (HEAD)  (git grep HEAD = ${HEAD_NAME} ${String(HEAD_SHA).slice(0, 9)}, ${onHead.lines.length} line(s) in ${onHead.byFile.size} file(s))`)
    listHits(onHead.byFile)
    const newHere = [...onHead.byFile.keys()].filter((f) => !onMain.byFile.has(f))
    if (newHere.length) console.log(`\n  ^ ${newHere.length} of these file(s) carry it on HEAD and NOT on ${MAIN_REF} — unlanded work, yours or someone's.`)
    found += onHead.lines.length
  } else {
    console.log(`ON THIS BRANCH (HEAD)  none — git grep HEAD = ${HEAD_NAME} (${String(HEAD_SHA).slice(0, 9)}) matched 0 line(s)`)
  }
}
console.log()

// ---- 3. unlanded branches ---------------------------------------------------
// TWO QUESTIONS, BOTH REQUIRED. A hit is listed only when (1) its CONTENT differs from
// MAIN_REF and (2) its content ALSO differs from the same path at merge-base(MAIN_REF,
// branch) — i.e. the branch's bytes there are not simply the bytes it was cut from.
// Condition (1) alone still over-reports: a branch cut weeks ago holds MAIN'S OLDER BYTES at
// every path main has changed since. Both are CONTENT tests, not commit-touch tests: a
// merge of main, or a touch-then-revert, leaves the blob equal and carries no work.
// `--no-renames` only ever WIDENS the kept set, which is the safe direction.
// BOTH drops are PRINTED, per branch and in total: a filter that hides its own work is the
// next defect of this kind, and where.test.mjs grades every printed count BY VALUE.
const identicalHits = []
const identicalBy = new Map()
const staleHits = []
const staleBy = new Map()
if (BRANCHES) {
  const branches = text(git('branch', '--list', ...BRANCH_GLOBS)).split('\n').map((b) => b.replace(/^[*+]/, '').trim()).filter(Boolean)
  // Liveness is measured against the PUBLISHED main when there is one (a branch whose work
  // landed locally but is not pushed is still live), else against MAIN_REF.
  const LIVE_BASE = commitOf(`origin/${MAIN_BRANCH}`) ? `origin/${MAIN_BRANCH}` : MAIN_REF
  const live = branches.filter((b) => (text(git('rev-list', '--count', `${LIVE_BASE}..${b}`)).trim() || '0') !== '0')
  /** The paths two revisions disagree about. null = the diff FAILED and we know nothing. */
  const diffNames = (a, b, paths = []) => {
    const o = git('diff', '--name-only', '--no-renames', a, b, '--', ...paths)
    return o === null ? null : new Set(o.split('\n').filter(Boolean))
  }
  const hits = []
  for (const b of live) {
    const files = text(git('grep', '-l', '-I', LOOSE ? '-i' : '-w', '--', name, b)).split('\n').filter(Boolean)
    if (!files.length) continue
    const changed = diffNames(MAIN_REF, b)      // null when the diff did not run: keep the
    const candidates = []                       // hit, and `searchBroke` already refuses.
    for (const l of files) {
      const rel = l.slice(b.length + 1)
      if (changed && !changed.has(rel)) { identicalHits.push(l); identicalBy.set(b, (identicalBy.get(b) || 0) + 1) }
      else candidates.push([l, rel])
    }
    if (!candidates.length) continue
    const mb = text(git('merge-base', MAIN_REF, b)).trim() || null
    const contributed = mb ? diffNames(mb, b, candidates.map(([, rel]) => rel)) : null
    for (const [l, rel] of candidates) {
      if (contributed && !contributed.has(rel)) { staleHits.push(l); staleBy.set(b, (staleBy.get(b) || 0) + 1) }
      else hits.push(l)
    }
  }
  if (hits.length) {
    console.log(`NOT ON MAIN  (${hits.length} hit(s) across ${live.length} unlanded branch(es), changed BY the branch and different from ${MAIN_REF})`)
    for (const h of hits.slice(0, 14)) console.log(`  ${h}`)
    if (hits.length > 14) console.log(`  … and ${hits.length - 14} more`)
    console.log('\n  ^ This work EXISTS. Do not write a second one — read it, or ask the supervisor to land it.')
    found += hits.length
  } else {
    console.log(`NOT ON MAIN  none — checked ${live.length} unlanded branch(es) matching ${BRANCH_GLOBS.join(' ')}`)
  }
  if (identicalHits.length) {
    console.log()
    for (const [b, n] of [...identicalBy].slice(0, 8)) console.log(`  ${n} file(s) on ${b} are byte-identical to ${MAIN_REF} and were not listed`)
    if (identicalBy.size > 8) console.log(`  … and ${identicalBy.size - 8} more branch(es), ${identicalHits.length - [...identicalBy.values()].slice(0, 8).reduce((a, n) => a + n, 0)} file(s)`)
    console.log(`  (${identicalHits.length} in all: a branch that merely touched a file — or never touched it — holds no unlanded work in it)`)
  }
  if (staleHits.length) {
    console.log()
    for (const [b, n] of [...staleBy].slice(0, 8)) console.log(`  ${n} file(s) on ${b} differ only because ${MAIN_REF} moved after the branch point — the branch's bytes there are still its merge-base's — and were not listed`)
    if (staleBy.size > 8) console.log(`  … and ${staleBy.size - 8} more branch(es), ${staleHits.length - [...staleBy.values()].slice(0, 8).reduce((a, n) => a + n, 0)} file(s)`)
    console.log(`  ${staleHits.length} file(s) in all differ only because ${MAIN_REF} moved after the branch point: that is ${MAIN_REF}'s OLDER bytes sitting on a branch, not unlanded work`)
  }
  console.log()
}

if (searchBroke.length) {
  console.log(`SEARCH INCOMPLETE — ${searchBroke.length} git call(s) failed:`)
  for (const b of searchBroke.slice(0, 6)) console.log(`  ${b}`)
  console.log('\nNo negative conclusion is available from this run. Fix the failure and re-run;')
  console.log('a tool that reports "not found" when its search did not happen is worse than no tool.')
  process.exit(2)
}
const droppedHits = [...identicalHits, ...staleHits]
if (!found && droppedHits.length) {
  // THE FILTER'S OWN FAILURE MODE, refused by name. The branch census greps the whole tree;
  // ON MAIN and HEAD grep ORG_SEARCH_PATHS when it is set. A name living only outside those
  // paths is seen by the census alone — dropping its hits must not become "does not exist".
  console.log(`NOTHING UNLANDED — all ${droppedHits.length} branch match(es) were dropped: ${identicalHits.length} byte-identical to ${MAIN_REF}, ${staleHits.length} differing only because ${MAIN_REF} moved after the branch point, across ${new Set([...identicalBy.keys(), ...staleBy.keys()]).size} branch(es):`)
  for (const h of droppedHits.slice(0, 4)) console.log(`  ${h}`)
  if (droppedHits.length > 4) console.log(`  … and ${droppedHits.length - 4} more`)
  console.log(`\nIt EXISTS — outside the searched paths (${SEARCH_PATHS.join(', ')}), which is why the`)
  console.log(`${MAIN_REF} and HEAD sections above are empty. It is not unlanded work; do not write a second one.`)
} else if (!found) {
  console.log(`NOTHING FOUND in the AST graph, on ${MAIN_REF}, on HEAD` + (BRANCHES ? ', or on any unlanded branch.' : '.'))
  console.log(BRANCHES ? 'Every source searched and answered empty, so this does not exist yet.'
    : 'Before concluding it does not exist, re-run with --branches: a plan row can name a symbol')
  if (!BRANCHES) console.log('that lives only on an unlanded work branch.')
  process.exit(1)
}
console.log(`sources that answered: ${graphAnswered ? 'AST graph · ' : ''}git grep (${MAIN_REF}${HEAD_IS_MAIN ? ' = HEAD' : ' + HEAD'})${BRANCHES ? ' · branches' : ''}`)
