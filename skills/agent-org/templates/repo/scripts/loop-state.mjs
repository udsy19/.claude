#!/usr/bin/env node
process.stdout.on('error', (e) => { if (e && e.code === 'EPIPE') process.exit(0) })
/**
 * LOOP STATE — the supervisor's running summary, re-derived instead of remembered.
 *
 * WHY THIS EXISTS. Over one session in the project this kit came from, four running
 * summaries drifted from the artefacts they described, and every artefact was right each
 * time: reds called NEW that open plan rows already owned; "six reds fixed" when four went
 * green; "twelve open proposals" when the log held eleven. None of those was a gate failing.
 * They were prose about gates, carried forward by hand from pass to pass, softening a little
 * each time. A number is only true at the instant it is derived.
 *
 *   node scripts/loop-state.mjs           # print the state, derived from the repo
 *   node scripts/loop-state.mjs --check   # assert the artefacts agree with themselves
 *
 * INDEPENDENCE (.claude/rules/gate-independence.md). Every number below is read out of a
 * file's bytes — vault/Plan.md's table, vault/_log/proposals.jsonl, the mission file, the
 * vault folders — never out of a summary any agent wrote about them. It does not run the
 * gates: a script the board runs must not re-enter the board.
 *
 * WHAT --check ASSERTS, and why:
 *   C1  Non-vacuity: the plan parses to at least one row, and proposals.jsonl parses as
 *       JSONL. A census over nothing agrees with everything.
 *   C2  Every proposal names a plan row that EXISTS. A proposal against a row that was
 *       renumbered or deleted is a finding addressed to nobody.
 *   C3  The mission in force (ORG_MISSION) exists, carries a `state:` from the declared
 *       vocabulary, and carries the `## NOW` … `## ---END-NOW` block the SessionStart hook
 *       prints — an absent block briefs every agent with nothing, silently.
 *   C4  At most one mission declares `state: running`: two running missions is two sets of
 *       instructions with nothing to say which one binds.
 */
import fs from 'node:fs'
import path from 'node:path'
import { refuseUnknownArgv } from './lib/argv.mjs'
import { fileURLToPath } from 'node:url'

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
const argv = process.argv.slice(2)
refuseUnknownArgv(argv, { script: 'loop-state', accepts: ['--check'] })
const CHECK = argv.includes('--check')

const read = (p) => fs.readFileSync(path.join(ROOT, p), 'utf8')
const has = (p) => fs.existsSync(path.join(ROOT, p))
let checks = 0
let failures = 0
const ok = (m) => { checks++; if (CHECK) console.log(`  ok    ${m}`) }
const fail = (m, d) => { checks++; failures++; console.log(`  FAIL  ${m}${d ? `\n          ${d}` : ''}`) }
const refuse = (m) => { console.log(`\nLOOP-STATE REFUSED: ${m}`); process.exit(2) }
const fmOf = (src) => {
  const m = /^---\n([\s\S]*?)\n---\n/.exec(src)
  const out = {}
  if (m) for (const l of m[1].split('\n')) { const i = l.indexOf(':'); if (i > 0) out[l.slice(0, i).trim()] = l.slice(i + 1).trim() }
  return out
}

// ── the plan ───────────────────────────────────────────────────────────────
const PLAN = 'vault/Plan.md'
if (!has(PLAN)) refuse(`${PLAN} does not exist`)
const planRows = []
for (const line of read(PLAN).split('\n')) {
  const m = /^\|\s*(\d+(?:\.\d+)?)\s*\|/.exec(line)
  if (!m) continue
  const cells = line.split(/(?<!\\)\|/).slice(1, -1).map((c) => c.trim())
  planRows.push({ id: m[1], status: cells[cells.length - 1] || '' })
}
const byStatus = {}
for (const r of planRows) {
  const k = r.status.split(':')[0] || '(empty)'
  byStatus[k] = (byStatus[k] ?? 0) + 1
}

// ── proposals ──────────────────────────────────────────────────────────────
const PROPS = 'vault/_log/proposals.jsonl'
if (!has(PROPS)) refuse(`${PROPS} does not exist`)
let props = []
try { props = read(PROPS).split('\n').filter((l) => l.trim()).map((l) => JSON.parse(l)) }
catch (e) { refuse(`${PROPS} does not parse as JSONL: ${e.message}`) }
const unresolved = props.filter((r) => !r.verdict)

// ── missions, sessions, decisions ──────────────────────────────────────────
const listMd = (dir) => (has(dir) ? fs.readdirSync(path.join(ROOT, dir)).filter((f) => f.endsWith('.md') && f !== 'README.md') : [])
const missions = listMd('vault/Missions').map((f) => ({ f, fm: fmOf(read(`vault/Missions/${f}`)) }))
const running = missions.filter((m) => m.fm.state === 'running')
const sessions = listMd('vault/Sessions').sort()
const decisions = listMd('vault/Decisions')
// ORG_MISSION from the environment, else from .claude/settings.json's `env` block — the
// one place it is declared — so a shell run and a session run grade the same mission.
const MISSION = process.env.ORG_MISSION || (() => {
  try { return JSON.parse(read('.claude/settings.json')).env?.ORG_MISSION || '' } catch { return '' }
})()

// ── print ──────────────────────────────────────────────────────────────────
console.log('loop state — every number below is read out of a file, not remembered\n')
console.log(`  plan (${PLAN}): ${planRows.length} rows — ${Object.entries(byStatus).map(([k, n]) => `${k} ${n}`).join(' · ') || 'none'}`)
console.log(`  proposals (${PROPS}): ${props.length} filed, ${unresolved.length} UNRESOLVED`)
for (const r of unresolved) console.log(`    #${props.indexOf(r) + 1}  row ${r.row} [${r.kind}] ${String(r.why).slice(0, 90)}`)
console.log(`  missions: ${missions.length} (${running.length} running: ${running.map((m) => m.f).join(', ') || 'none'}) · ORG_MISSION=${MISSION || '(unset)'}`)
console.log(`  sessions: ${sessions.length} · newest: ${sessions[sessions.length - 1] ?? '(none)'}`)
console.log(`  decisions: ${decisions.length}`)
if (!CHECK) { console.log('\n(run with --check to assert the artefacts agree with themselves)'); process.exit(0) }

console.log('\nchecking that the artefacts agree with themselves\n')
// C1
if (planRows.length >= 1) ok(`${PLAN} parses to ${planRows.length} row(s)`)
else fail(`${PLAN} parses to at least one row`, 'zero rows — this instrument is grading nothing')
ok(`${PROPS} parses as JSONL (${props.length} row(s))`)
// C2
const ids = new Set(planRows.map((r) => r.id))
const orphanProps = props.filter((p) => !ids.has(String(p.row)))
if (orphanProps.length === 0) ok(`every proposal names a plan row that exists (${props.length} checked)`)
else fail('every proposal names a plan row that exists', orphanProps.map((p) => `#${props.indexOf(p) + 1} → row ${p.row}`).join(' · '))
// C3
if (!MISSION) fail('ORG_MISSION names the mission in force', 'unset — the SessionStart hook and loop-guard.sh brief and guard nothing')
else if (!has(`vault/Missions/${MISSION}.md`)) fail(`vault/Missions/${MISSION}.md exists`, 'ORG_MISSION names a file that is not there')
else {
  const src = read(`vault/Missions/${MISSION}.md`)
  const state = fmOf(src).state
  if (['running', 'paused', 'blocked-on-human', 'done'].includes(state)) ok(`the mission's state is in the declared vocabulary (${state})`)
  else fail("the mission's state is in the declared vocabulary (running | paused | blocked-on-human | done)", `state: ${state ?? '(absent)'}`)
  if (/^## NOW\b/m.test(src) && /^## ---END-NOW\b/m.test(src)) ok('the mission carries the ## NOW … ## ---END-NOW block SessionStart prints')
  else fail('the mission carries the ## NOW … ## ---END-NOW block SessionStart prints', 'missing marker(s) — every agent is briefed with nothing')
}
// C4
if (running.length <= 1) ok(`at most one mission is running (${running.length})`)
else fail('at most one mission is running', running.map((m) => m.f).join(', '))

console.log(failures ? `\nLOOP-STATE FAIL (${checks} checks, ${failures} failing)` : `\nLOOP-STATE PASS (${checks} checks) — the artefacts agree with themselves`)
process.exit(failures ? 1 : 0)
