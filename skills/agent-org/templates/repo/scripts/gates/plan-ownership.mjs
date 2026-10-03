#!/usr/bin/env node
// A closed pipe is not an error: `node scripts/x.mjs | head` must not report failure.
process.stdout.on('error', (e) => { if (e && e.code === 'EPIPE') process.exit(0) })
/**
 * Who changed the plan, and by what authority — re-derived from git.
 *
 * scripts/hooks/agent-contract.mjs refuses a subagent's Edit to vault/Plan.md,
 * vault/Roadmap.md, vault/Decisions/ or .claude/rules/. It cannot refuse a Bash write,
 * because no PreToolUse matcher on Bash can tell a write from a read. So the same rule is
 * checked again HERE, at the landing boundary, from a source the hook does not produce:
 * the commits themselves.
 *
 * A commit touching a protected path must SAY so, in its message, one of:
 *     Authority: supervisor          — the supervisor made this call
 *     Authority: owner               — the owner ruled
 *     Proposal: #<n>                 — it carries out an accepted proposal
 * A commit that changes the plan while claiming nothing is the defect: not because it is
 * malicious, but because nobody can later tell whether it was decided or drifted.
 *
 *   node scripts/gates/plan-ownership.mjs           # grade HEAD's landing range
 *   node scripts/gates/plan-ownership.mjs --since <rev>
 *
 * EXIT: 0 pass · 1 a commit claimed no authority · 2 refused · 77 empty range (a skip,
 * never a pass).
 */
import { execFileSync } from 'node:child_process'
import path from 'node:path'
// Imported, not restated: one declaration shared with the hook.
import { protectedHit } from '../lib/protected-paths.mjs'
// And one owner for "which commits did this landing bring in".
import { chooseBaseRev, resolveRevs } from '../lib/landing-range.mjs'
import { noGitEnv } from '../lib/git-env.mjs'
import { fileURLToPath } from 'node:url'

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..')
const CLAIM = /^\s*(Authority:\s*(supervisor|owner)|Proposal:\s*#\d+)\s*$/mi

const argv = process.argv.slice(2)
let since = null
for (let i = 0; i < argv.length; i++) {
  if (argv[i] === '--since') {
    since = argv[++i]
    // A flag that is ignored is worse than one that is rejected: the caller believes it
    // was honoured.
    if (!since) { console.log('plan-ownership: --since needs a rev'); process.exit(2) }
    continue
  }
  console.log(`plan-ownership: unrecognised argument '${argv[i]}' — accepts: --since <rev>`)
  process.exit(2)
}
const git = (...a) => execFileSync('git', a, { cwd: ROOT, encoding: 'utf8', env: noGitEnv() }).trim()
const refuse = (msg) => { console.log(`PLAN-OWNERSHIP REFUSED: ${msg}`); process.exit(2) }

let baseRev
try { baseRev = since || chooseBaseRev({ repo: ROOT, tipRev: 'HEAD', refuse }) }
catch (e) { refuse(`cannot resolve a range — ${e.message}`) }
const range = `${baseRev}..HEAD`

// An UNRESOLVABLE rev must REFUSE, not skip: `--since not-a-rev` once printed "nothing
// landed" and exited 77 — a typo grading nothing while reporting a clean skip.
const { base, tip, anc } = resolveRevs({ repo: ROOT, baseRev, tipRev: 'HEAD' })
if (!base) refuse(`'${baseRev}' does not resolve to a commit`)
if (!tip) refuse(`'HEAD' does not resolve to a commit`)
if (anc.status !== 0) {
  refuse(`base ${base.slice(0, 9)} is not an ancestor of HEAD (${tip.slice(0, 9)}), so \`${range}\` is not the set of commits this landing brought in`)
}
let shas = []
try { shas = git('rev-list', range).split('\n').filter(Boolean) }
catch (e) { refuse(`cannot list ${range} — ${e.message.split('\n')[0]}`) }
if (!shas.length) {
  console.log(`PLAN-OWNERSHIP SKIP (77): ${range} is empty — nothing landed, so nothing to grade.`)
  process.exit(77)
}

let failed = 0, touched = 0
console.log(`PLAN-OWNERSHIP — ${shas.length} commit(s) in ${range}`)
for (const sha of shas) {
  // --root so a repository's FIRST commit lists its files too (it has no parent to diff).
  const files = git('show', '--root', '--name-only', '--format=', sha).split('\n').filter(Boolean)
  const hits = files.filter((f) => protectedHit(f))
  if (!hits.length) continue
  touched++
  const msg = git('log', '-1', '--format=%B', sha)
  const claim = msg.match(CLAIM)
  if (claim) {
    console.log(`  ok   ${sha.slice(0, 9)} ${hits.length} protected file(s) — ${claim[0].trim()}`)
  } else {
    failed++
    console.log(`  FAIL ${sha.slice(0, 9)} changed ${hits.join(', ')} claiming no authority`)
  }
}
if (!touched) {
  console.log('  no commit in this range touched a protected path')
  console.log('\nPLAN-OWNERSHIP PASS  (nothing to grade, and it says so)')
  process.exit(0)
}
console.log(failed === 0
  ? `\nPLAN-OWNERSHIP PASS  (${touched} commit(s) touched a protected path, every one claimed authority)`
  : `\nPLAN-OWNERSHIP FAIL: ${failed} commit(s) changed the plan, roadmap, decisions or rules claiming no authority.\nAdd 'Authority: supervisor' or 'Proposal: #<n>' to the commit message.`)
process.exit(failed === 0 ? 0 : 1)
