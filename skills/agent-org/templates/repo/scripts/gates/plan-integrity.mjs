#!/usr/bin/env node
/**
 * plan-integrity — the gate for vault/Plan.md, the ordered plan of record.
 *
 * WHY IT EXISTS. An adversarial review once reported: "the status column has no closed
 * vocabulary — I set a status to `banana` on a disposable copy and it lands in the roll-up
 * as its own bucket, and nothing refuses it." A column whose values are free text cannot be
 * aggregated, and a citation nobody re-resolves rots the moment the file it points at
 * moves. Both are the same defect: a check that cannot go red.
 *
 * INDEPENDENCE (.claude/rules/gate-independence.md). This gate consumes NOTHING the plan
 * says about itself: not its Status roll-up, not any "verification" prose. It re-derives
 * every number from the table's own bytes, and resolves every citation against the cited
 * FILE (vault/Roadmap.md) — by the row's own QUOTED WORDS, because a line number is the
 * producer's coordinate and the words are the artifact's.
 *
 * A Roadmap citation is graded TWICE: its quoted words must exist in the Roadmap (the
 * stable key), AND the line number it gives must point at those words. A key that is
 * checked and a coordinate that is not is half a citation.
 *
 *   node scripts/gates/plan-integrity.mjs            grade vault/Plan.md
 *   node scripts/gates/plan-integrity.mjs <file>     grade another copy (sabotage)
 *   node scripts/gates/plan-integrity.mjs --relocate rewrite every citation's LINE
 *                                                    NUMBER from its quoted words
 *
 * FOR A LANDER: run `--relocate` INSIDE the merge, in the same change as the vault edit
 * that moved a line, and then the plain gate. Landing ticks live at the END of the Roadmap
 * precisely so a tick moves nothing; --relocate exists for every other edit, which can.
 *
 * THE ROADMAP IS RESOLVED BESIDE THE PLAN: hand this gate `<dir>/Plan.md` and it grades
 * against `<dir>/Roadmap.md`. That is what lets the self-check below sabotage a COPY of the
 * pair rather than the real vault (gate-independence law 10).
 *
 * EXIT: 0 all checks green (or a relocation completed) · 1 at least one check red · 2
 * refused (bad argv, a file it cannot read, or a citation --relocate will not guess at —
 * in which case NOTHING is written).
 */
import { readFileSync, writeFileSync, existsSync, mkdtempSync, rmSync } from 'node:fs'
import { spawnSync } from 'node:child_process'
import { createHash } from 'node:crypto'
import { tmpdir } from 'node:os'
import { resolve, dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const HERE = dirname(fileURLToPath(import.meta.url))
const ROOT = resolve(HERE, '..', '..')

// Acceptance cells normally name a gate FILE that exists. A project whose standing gate is
// a command rather than a file (e.g. `cargo test -p core`, `npm test`) lists the command's
// pattern here — once, so the exception is visible and arguable.
const COMMAND_GATES = []

// ---- argv: refuse what we do not understand, BY NAME, before any work -------
const argv = process.argv.slice(2)
let RELOCATE = false
const positional = []
for (const a of argv) {
  if (a === '--relocate') { RELOCATE = true; continue }
  if (a.startsWith('-')) {
    process.stderr.write(`plan-integrity: unrecognised argument ${JSON.stringify(a)}\n`)
    process.stderr.write('plan-integrity: accepts: at most one positional (a plan file); the flag --relocate\n')
    process.exit(2)
  }
  positional.push(a)
}
if (positional.length > 1) {
  process.stderr.write('plan-integrity: expected at most one positional (a plan file)\n')
  process.exit(2)
}
const PLAN = resolve(ROOT, positional[0] ?? 'vault/Plan.md')

const read = (p) => {
  try { return readFileSync(p, 'utf8') } catch (e) {
    process.stderr.write(`plan-integrity REFUSED — cannot read ${p}: ${e.code ?? e.message}\n`)
    process.exit(2)
  }
}

// ---- the citation vocabulary, declared ONCE ---------------------------------
// A citation is `` `Roadmap.md:<n>` ("its own quoted words"…) ``. The quote is the key,
// the number is a coordinate. The checks and --relocate both read citations through these
// constants, so the mode can never resolve a citation the gate does not grade.
const CITATION = /`Roadmap\.md:(\d+)`\s*(\(([^)]*)\))?/g
const QUOTED = /["“]([^"”]{6,})["”]/g
const norm = (x) => x.replace(/\s+/g, ' ').trim()
// A citation is correct when its quote appears within LINE_SLACK lines FORWARD of the
// number (a wrapped roadmap item wraps downward, so the cited line must be its first).
const LINE_SLACK = 4
const ROADMAP = resolve(dirname(PLAN), 'Roadmap.md')

// The lines a quote STARTS on: the window opening there carries it and the window one line
// later does not. One hit is a coordinate; two is ambiguity. Shared by --relocate and its
// self-check so the two cannot disagree about where a quote starts.
const quoteStarts = (rmLines) => {
  const windowAt = (i) => norm(rmLines.slice(i, i + LINE_SLACK).join(' '))
  return (q) => {
    const out = []
    for (let i = 0; i < rmLines.length; i++) if (windowAt(i).includes(q) && !windowAt(i + 1).includes(q)) out.push(i + 1)
    return out
  }
}

const whereOf = (line) => {
  const row = /^\|\s*(\d+)\s*\|/.exec(line)
  if (row) return `row ${row[1]}`
  const owner = /^\|\s*(O\d+)\s*\|/.exec(line)
  return owner ? `owner row ${owner[1]}` : 'a non-table citation'
}

// ---- --relocate: rewrite every citation's NUMBER from its quoted words -------
// It refuses rather than guesses: a quote that matches no line, or more than one, is
// printed BY NAME and NOTHING is written. All-or-nothing, so a refusal can never leave the
// plan half-rewritten.
if (RELOCATE) {
  const planText = read(PLAN)
  const rmLines = read(ROADMAP).split('\n')
  const startsOf = quoteStarts(rmLines)
  const refusals = []
  const moves = []
  const next = planText.split('\n').map((line) => line.replace(CITATION, (whole, num, _paren, inner) => {
    const quotes = [...(inner ?? '').matchAll(QUOTED)].map(q => norm(q[1]))
    if (quotes.length === 0) { refusals.push(`${whereOf(line)}: \`Roadmap.md:${num}\` carries NO quoted words — nothing to re-derive from`); return whole }
    const targets = new Set()
    for (const q of quotes) {
      const hits = startsOf(q)
      if (hits.length !== 1) { refusals.push(`${whereOf(line)}: ${JSON.stringify(q.slice(0, 60))} matches ${hits.length} lines${hits.length ? ` (${hits.join(', ')})` : ''} in ${ROADMAP} — refusing to guess`); continue }
      targets.add(hits[0])
    }
    if (targets.size !== 1) {
      if (targets.size > 1) refusals.push(`${whereOf(line)}: \`Roadmap.md:${num}\`'s quotes disagree — they start on ${[...targets].join(' and ')}`)
      return whole
    }
    const to = [...targets][0]
    if (Number(num) !== to) moves.push(`${whereOf(line)}: ${num} → ${to}  ${JSON.stringify(quotes[0].slice(0, 46))}`)
    return whole.replace(`\`Roadmap.md:${num}\``, `\`Roadmap.md:${to}\``)
  })).join('\n')

  if (refusals.length) {
    process.stderr.write(`plan-integrity --relocate REFUSED — ${refusals.length} citation(s) could not be re-derived; NOTHING was written to ${PLAN}\n`)
    for (const r of refusals) process.stderr.write(`  ${r}\n`)
    process.exit(2)
  }
  if (next !== planText) writeFileSync(PLAN, next)
  process.stdout.write(`PLAN-RELOCATE ${moves.length === 0 ? 'no change' : `${moves.length} citation(s) moved`} — ${PLAN} against ${ROADMAP} (${rmLines.length} lines)\n`)
  for (const m of moves) process.stdout.write(`  ${m}\n`)
  process.exit(0)
}

// ---- split a GFM table row on UNESCAPED pipes -------------------------------
function cells (line) {
  const body = line.trim().replace(/^\|/, '').replace(/\|$/, '')
  const out = []; let cur = ''
  for (let i = 0; i < body.length; i++) {
    if (body[i] === '\\' && body[i + 1] === '|') { cur += '|'; i++; continue }
    if (body[i] === '|') { out.push(cur.trim()); cur = ''; continue }
    cur += body[i]
  }
  out.push(cur.trim())
  return out
}

const text = read(PLAN)
const rows = []
text.split('\n').forEach((l, i) => {
  const m = /^\|\s*(\d+)\s*\|/.exec(l)
  if (m) rows.push({ n: Number(m[1]), line: i + 1, c: cells(l) })
})

let failing = 0, checks = 0
const results = []
const check = (name, ok, detail) => {
  checks++; if (!ok) failing++
  results.push(`  ${ok ? 'ok  ' : 'FAIL'}  ${name}${detail ? `\n          ${detail}` : ''}`)
}

// ---- 0. the population is not empty ----------------------------------------
check('the plan carries a numbered task table at all', rows.length > 0,
  rows.length === 0 ? `no row matching /^\\|\\s*\\d+\\s*\\|/ in ${PLAN} — an empty population is not a pass` : `${rows.length} rows parsed`)
if (rows.length === 0) { process.stdout.write(results.join('\n') + '\nPLAN-INTEGRITY FAIL (1 checks, 1 failing)\n'); process.exit(1) }

// ---- 1. six cells, none empty (# · task · serves · owner line · acceptance gate · status)
// Every cell access below is `?? ''`-guarded: a malformed row must be REPORTED, not throw —
// a stack trace is not a red (gate-independence law 7).
const wrongWidth = rows.filter(r => r.c.length !== 6)
check('every row has exactly six cells', wrongWidth.length === 0,
  wrongWidth.map(r => `row ${r.n} (line ${r.line}) has ${r.c.length}`).join(' · '))
const emptyCells = []
for (const r of rows) r.c.forEach((v, k) => { if (!v) emptyCells.push(`row ${r.n} cell ${k + 1}`) })
check('no cell is empty', emptyCells.length === 0, emptyCells.join(' · '))

// ---- 2. contiguous numbering ------------------------------------------------
const nums = rows.map(r => r.n)
const want = Array.from({ length: rows.length }, (_, i) => i + 1)
check(`numbering is contiguous 1..${rows.length}`, nums.join(',') === want.join(','),
  nums.join(',') === want.join(',') ? '' : `first divergence at index ${nums.findIndex((v, i) => v !== want[i])}`)

// ---- 3. CLOSED status vocabulary -------------------------------------------
const STATUS = [
  /^open$/,
  /^in-flight:[A-Za-z0-9._\/-]+$/,
  /^blocked-on-owner:O\d+$/,
  /^done:[0-9a-f]{7,40}$/,
]
const badStatus = rows.filter(r => !STATUS.some(re => re.test(r.c[5] ?? '')))
check('every status is one of {open, in-flight:<branch>, blocked-on-owner:<Oid>, done:<sha>}',
  badStatus.length === 0, badStatus.map(r => `row ${r.n}: ${JSON.stringify(r.c[5])}`).join(' · '))

const declaredO = new Set([...text.matchAll(/^\|\s*(O\d+)\s*\|/gm)].map(m => m[1]))
const undeclared = rows
  .filter(r => (r.c[5] ?? '').startsWith('blocked-on-owner:'))
  .map(r => [r.n, (r.c[5] ?? '').split(':')[1]])
  .filter(([, o]) => !declaredO.has(o))
check('every blocked-on-owner O-id is declared in the owner table', undeclared.length === 0,
  undeclared.map(([n, o]) => `row ${n} → ${o}`).join(' · ') || `${declaredO.size} O-ids declared`)

// ---- 4. every roadmap citation's QUOTED WORDS are findable in Roadmap.md ----
const rm = existsSync(ROADMAP) ? readFileSync(ROADMAP, 'utf8') : null
check('the Roadmap BESIDE the plan is present', rm !== null, rm === null ? `${ROADMAP} absent` : `${ROADMAP} — ${rm.split('\n').length} lines`)

const rmFlat = rm ? norm(rm) : ''
const noWords = [], notFound = []
for (const r of rows) {
  const s = r.c[2] ?? ''
  for (const m of s.matchAll(CITATION)) {
    const quoted = [...(m[3] ?? '').matchAll(QUOTED)].map(q => norm(q[1]))
    if (quoted.length === 0) { noWords.push(`row ${r.n} → Roadmap.md:${m[1]}`); continue }
    for (const q of quoted) if (rm && !rmFlat.includes(q)) notFound.push(`row ${r.n}: ${JSON.stringify(q)}`)
  }
}
check('every Roadmap citation carries quoted words from the item it names', noWords.length === 0, noWords.join(' · '))
check('every quoted Roadmap phrase is found in vault/Roadmap.md', notFound.length === 0, notFound.join(' · '))

const rmLines = rm ? rm.split('\n') : []
const stale = []
for (const r of rows) {
  const s = r.c[2] ?? ''
  for (const m of s.matchAll(CITATION)) {
    const n = Number(m[1])
    const quoted = [...(m[3] ?? '').matchAll(QUOTED)].map(q => norm(q[1]))
    if (quoted.length === 0 || !rm) continue                 // already failed above
    const window = norm(rmLines.slice(Math.max(0, n - 1), n - 1 + LINE_SLACK).join(' '))
    for (const q of quoted) {
      if (!rmFlat.includes(q)) continue                      // already failed above
      if (!window.includes(q)) stale.push(`row ${r.n}: Roadmap.md:${n} does not carry ${JSON.stringify(q.slice(0, 40))}`)
    }
  }
}
check(`every Roadmap line number points at its own quoted words (line N..N+${LINE_SLACK - 1})`,
  stale.length === 0, stale.join(' · '))

// ---- 4b. the landing ticks live at the END of the Roadmap, and nowhere else --
// A tick inserted near the TOP pushes every line below it down and ages every citation.
// The rule used to be prose only — and the gate's own printed remedy ("run --relocate")
// repaired the coordinates while leaving the tick at the top, so the churn restarted.
// A rule with no row is a rule nothing guards (gate-independence law 15).
const TICK_HEADING = '## Plan of record — the landing ticks'
const TICK_LINE = /^- \[x\] .*\(landed[^)]*\)\s*$/
// The population guard (law 12): the absence-shaped row below is vacuous if no line
// matches TICK_LINE at all. A RATCHET: raise it as landings accrue, never lower it.
const TICKS_AT_LANDING = 1
const headings = []
rmLines.forEach((l, i) => { if (/^#{1,6}\s+\S/.test(l)) headings.push({ line: i + 1, text: l.trim() }) })
const tickHeading = headings.filter(h => h.text === TICK_HEADING)
const lastHeading = headings[headings.length - 1]
check(`"${TICK_HEADING}" is the LAST heading of vault/Roadmap.md`,
  rm !== null && tickHeading.length === 1 && lastHeading?.text === TICK_HEADING,
  rm === null ? 'the Roadmap beside the plan is absent — already failed above'
    : tickHeading.length !== 1 ? `the heading occurs ${tickHeading.length} times — expected exactly 1`
      : lastHeading?.text === TICK_HEADING ? `line ${tickHeading[0].line} of ${rmLines.length}, last of ${headings.length} headings`
        : `it is on line ${tickHeading[0].line}, but the LAST heading is line ${lastHeading.line} ${JSON.stringify(lastHeading.text.slice(0, 60))}`)

const tickAt = tickHeading.length === 1 ? tickHeading[0].line : Infinity
const ticks = []
rmLines.forEach((l, i) => { if (TICK_LINE.test(l)) ticks.push(i + 1) })
const ticksUnder = ticks.filter(n => n > tickAt)
check(`the landing-tick population is REACHABLE — at least ${TICKS_AT_LANDING} tick(s) live under that heading`,
  ticksUnder.length >= TICKS_AT_LANDING,
  `${ticksUnder.length} line(s) match /- [x] … (landed …)/ below line ${tickAt === Infinity ? '(no heading)' : tickAt}`)
const ticksAbove = ticks.filter(n => n <= tickAt)
check('every landing tick lives UNDER that heading — none above it',
  ticksAbove.length === 0,
  ticksAbove.map(n => `Roadmap.md:${n} ${JSON.stringify((rmLines[n - 1] ?? '').trim().slice(0, 60))}`).join(' · ')
    + (ticksAbove.length ? ` — move it to the "${TICK_HEADING}" subsection at the END of the file, THEN run --relocate` : ''))

// ---- 5. every acceptance cell names an existing file, or says gate-to-write --
const noAcceptance = []
for (const r of rows) {
  const a = r.c[4] ?? ''
  if (/gate to write/i.test(a)) continue
  if (COMMAND_GATES.some((re) => re.test(a))) continue
  const cands = [...a.matchAll(/[\w./-]+\.(?:mjs|cjs|js|py|sh|ts|tsx|rs|go|rb|json|md|txt|fixture)/g)].map(m => m[0])
  if (!cands.some(p => existsSync(resolve(ROOT, p)))) noAcceptance.push(`row ${r.n}: ${cands.join(', ') || '(no path at all)'}`)
}
check('every acceptance cell names a gate/test that exists, or says "gate to write:"',
  noAcceptance.length === 0, noAcceptance.join(' · '))

// ---- 6. the --relocate mode, proven on a DISPOSABLE COPY --------------------
// Graded on a temp copy of the file under grade, NEVER on the file itself (law 10). The
// copy is perturbed by +9 on EVERY citation — more than the window tolerates — and the
// rows assert in order: the perturbation is reachable · it reddens the stale row
// DIFFERENTIALLY · relocate restores the bytes exactly · relocate is idempotent · the
// relocated copy grades exactly as the pristine copy · an ambiguous quote is refused.
//
// RECURSION GUARD (law 7 — a hang is not a red): children run with
// ORG_PLAN_INTEGRITY_CHILD=1 and skip this section.
const SELF = fileURLToPath(import.meta.url)
const verdictOf = (r) => {
  if (r.error?.code === 'ETIMEDOUT' || r.signal) return `NO VERDICT (${r.signal ?? r.error?.code}) — a hang is its own outcome`
  const m = /PLAN-INTEGRITY (PASS|FAIL) \((\d+) checks, (\d+) failing\)/.exec(r.stdout ?? '')
  return m ? `exit=${r.status} ${m[1]} (${m[2]} checks, ${m[3]} failing)` : `exit=${r.status} NO VERDICT LINE`
}
if (process.env.ORG_PLAN_INTEGRITY_CHILD === '1') {
  results.push('  --    --relocate self-check SKIPPED — child invocation (recursion guard ORG_PLAN_INTEGRITY_CHILD=1)')
} else {
  const dir = mkdtempSync(join(tmpdir(), 'plan-integrity-'))
  const pristine = join(dir, 'pristine.md')
  const work = join(dir, 'work.md')
  const perturbed = text.replace(/`Roadmap\.md:(\d+)`/g, (_, d) => `\`Roadmap.md:${Number(d) + 9}\``)
  writeFileSync(join(dir, 'Roadmap.md'), rm ?? '')
  writeFileSync(pristine, text)
  writeFileSync(work, perturbed)
  const run = (args) => spawnSync(process.execPath, [SELF, ...args], {
    encoding: 'utf8', timeout: 120_000,
    env: { ...process.env, ORG_PLAN_INTEGRITY_CHILD: '1' },
  })

  check('the +9 citation perturbation is REACHABLE on the file under grade', perturbed !== text,
    perturbed === text ? `no \`Roadmap.md:<n>\` citation in ${PLAN} — this self-check would be vacuous; cite at least one Roadmap item` : `${[...text.matchAll(/`Roadmap\.md:\d+`/g)].length} citations shifted by +9 on ${work}`)

  const baseline = run([pristine])
  const before = run([work])
  const staleRow = /FAIL {2}every Roadmap line number points at its own quoted words/
  const reddened = staleRow.test(before.stdout ?? '')
  const differential = !staleRow.test(baseline.stdout ?? '')
  check('a +9 shift of every citation REDDENS the stale-citation row on the copy — DIFFERENTIALLY',
    reddened && differential,
    `perturbed copy: ${verdictOf(before)} · pristine copy: ${verdictOf(baseline)} · the control is ${differential ? 'differential' : 'NOT DIFFERENTIAL — the pristine copy ALREADY fails that row; fix the stale citation(s) named above first'}`)

  const rel = run(['--relocate', work])
  const relocated = readFileSync(work, 'utf8')
  check('--relocate restores every perturbed citation BYTE-FOR-BYTE',
    rel.status === 0 && relocated === text,
    relocated === text ? `exit ${rel.status} · ${(rel.stdout ?? '').trim().split('\n')[0]}`
      : `exit=${rel.status} · ${relocated === perturbed ? 'the file is UNCHANGED — the mode did nothing' : `the restored copy DIFFERS from the plan under grade — ${PLAN} is not itself relocated. If a line was INSERTED ABOVE the cited words and it is a landing tick, move it to the end of the Roadmap first; then run \`node scripts/gates/plan-integrity.mjs --relocate\``} · ${(rel.stderr ?? '').trim().split('\n').slice(0, 3).join(' | ')}`)

  const rel2 = run(['--relocate', work])
  const twice = readFileSync(work, 'utf8')
  check('--relocate is IDEMPOTENT — a second run changes nothing',
    rel2.status === 0 && twice === relocated, `exit=${rel2.status} · ${twice === relocated ? 'byte-identical' : 'the second run moved bytes'}`)

  const after = run([work])
  check('the relocated copy grades EXACTLY as the pristine copy',
    after.status === baseline.status && verdictOf(after) === verdictOf(baseline),
    `relocated ${verdictOf(after)} · pristine ${verdictOf(baseline)}`)

  // ---- the AMBIGUITY REFUSAL: a quote matching two lines must be refused, not guessed.
  const dupDir = mkdtempSync(join(tmpdir(), 'plan-integrity-dup-'))
  const dupPlan = join(dupDir, 'Plan.md')
  const dupRoadmap = join(dupDir, 'Roadmap.md')
  const md5 = (f) => createHash('md5').update(readFileSync(f)).digest('hex')
  const head = (r) => `${(r.stdout ?? '').trim().split('\n')[0] || ''} ${(r.stderr ?? '').trim().split('\n').slice(0, 2).join(' | ')}`.trim()
  const startsIn = quoteStarts(rmLines)
  let dup = null
  for (const r of rows) {
    for (const m of (r.c[2] ?? '').matchAll(CITATION)) {
      for (const q of [...(m[3] ?? '').matchAll(QUOTED)].map(x => norm(x[1]))) {
        if (dup) break
        const hits = startsIn(q)
        if (hits.length === 1) dup = { q, at: hits[0], row: `row ${r.n}` }
      }
      if (dup) break
    }
    if (dup) break
  }
  check('a citation whose quote resolves to EXACTLY ONE Roadmap line exists to duplicate',
    dup !== null && rm !== null,
    dup ? `${dup.row}: ${JSON.stringify(dup.q.slice(0, 40))} starts on Roadmap line ${dup.at}` : 'no citation resolves to exactly one line — the rows below would be VACUOUS, which is not a pass')

  if (dup && rm !== null) {
    // arm A — the CONTROL: same scratch plan, an UNDUPLICATED Roadmap copy.
    writeFileSync(dupRoadmap, rm)
    writeFileSync(dupPlan, text)
    const clean = run(['--relocate', dupPlan])
    check('the ambiguity arm is DIFFERENTIAL — with no duplicate, --relocate ACCEPTS that same scratch plan',
      clean.status === 0, `exit=${clean.status} · ${head(clean)}`)
    // arm B — one quote's window copied to the TOP of the scratch Roadmap (BEFORE the real
    // one, so a guess would move bytes and the "nothing written" row is differential).
    const dupLines = rmLines.slice()
    dupLines.splice(1, 0, ...rmLines.slice(dup.at - 1, dup.at - 1 + LINE_SLACK))
    writeFileSync(dupRoadmap, dupLines.join('\n'))
    writeFileSync(dupPlan, text)
    const beforeHash = md5(dupPlan)
    const amb = run(['--relocate', dupPlan])
    const said = `${amb.stdout ?? ''}${amb.stderr ?? ''}`
    check('--relocate REFUSES an AMBIGUOUS quote rather than guessing (exit 2)',
      amb.status === 2 && /refusing to guess/.test(said), `exit=${amb.status} · ${head(amb)}`)
    check('…and the refusal NAMES the row and both lines the quote matched',
      said.includes(dup.row) && /matches 2 lines \(\d+, \d+\)/.test(said), head(amb))
    check('…and NOTHING was written — the scratch plan is md5-identical',
      md5(dupPlan) === beforeHash, `${beforeHash} → ${md5(dupPlan)}`)
  }
  rmSync(dupDir, { recursive: true, force: true })
  rmSync(dir, { recursive: true, force: true })
}

// ---- report -----------------------------------------------------------------
process.stdout.write(results.join('\n') + '\n')
process.stdout.write(`\nPLAN-INTEGRITY ${failing ? 'FAIL' : 'PASS'} (${checks} checks, ${failing} failing) — ${PLAN}\n`)
process.exit(failing ? 1 : 0)
