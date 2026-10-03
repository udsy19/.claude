#!/usr/bin/env node
// A closed pipe is not an error: `node scripts/x.mjs | head` must not report failure.
process.stdout.on('error', (e) => { if (e && e.code === 'EPIPE') process.exit(0) })
/**
 * Nested plan rows: a parent and its subtasks, held to each other.
 *
 * A row that is really ten tasks sits at "in-flight" for a fortnight while nobody can say
 * which part is done. So a parent row N may carry children N.1, N.2 … and this gate holds
 * the three properties that make the nesting mean anything:
 *
 *   1. every child has a parent row that exists;
 *   2. children are numbered contiguously from 1 — a gap means a row was deleted rather
 *      than resolved, and the reader cannot tell which;
 *   3. A PARENT IS NOT DONE WHILE A CHILD IS OPEN. This is the one that earns the gate.
 *      Ticking a parent whose subtasks are open is how a plan reports progress it has not
 *      made, and it is invisible to any check that reads rows independently.
 *
 * plan-integrity.mjs matches `^| <digits> |` only, so it cannot see a child row at all;
 * this is the other half, not a second copy of it.
 *
 *   node scripts/gates/plan-hierarchy.mjs [path/to/Plan.md]
 *
 * EXIT: 0 pass · 1 fail · 2 refused (bad argv, no plan, a row nested too deep, or no child
 * rows at all — every property here is computed over the children, so with none the plan
 * is ungradeable, not green).
 */
import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..')
const argv = process.argv.slice(2)
const positional = []
for (const a of argv) {
  if (a.startsWith('--')) { console.log(`plan-hierarchy: unrecognised argument '${a}' — accepts: (a path only)`); process.exit(2) }
  positional.push(a)
}
if (positional.length > 1) { console.log('plan-hierarchy: at most one path'); process.exit(2) }
const PLAN = path.resolve(ROOT, positional[0] ?? 'vault/Plan.md')
if (!fs.existsSync(PLAN)) { console.log(`PLAN-HIERARCHY REFUSED: no such file ${PLAN}`); process.exit(2) }

const DONE = /^(done|done:|shipped|landed)/i
const text = fs.readFileSync(PLAN, 'utf8')

// A row id with TWO dots (2.1.1) does not match the row regex below, so it would be
// silently DROPPED — present in the plan, invisible to every check here. Dropping a row is
// worse than misreading one, so depth beyond one level is REFUSED by name.
const tooDeep = []
for (const [i, line] of text.split('\n').entries()) {
  const m = /^\|\s*(\d+(?:\.\d+){2,})\s*\|/.exec(line)
  if (m) tooDeep.push(`${m[1]} (line ${i + 1})`)
}
if (tooDeep.length) {
  console.log(`PLAN-HIERARCHY REFUSED: ${tooDeep.length} row(s) nested more than one level deep: ${tooDeep.join(', ')}`)
  console.log('This gate models ONE level (N.1 … N.k). Flatten it, or extend this gate first.')
  process.exit(2)
}

const rows = []
for (const [i, line] of text.split('\n').entries()) {
  const m = /^\|\s*(\d+(?:\.\d+)?)\s*\|/.exec(line)
  if (!m) continue
  // Escape-aware: a cell may legally contain `\|`, and a naive split breaks it into extra
  // cells. The status is the second-to-last cell of an escape-aware split.
  const cells = line.split(/(?<!\\)\|/).map((c) => c.trim())
  rows.push({ id: m[1], lineNo: i + 1, status: (cells[cells.length - 2] || '').trim(), task: (cells[2] || '').slice(0, 70) })
}
if (rows.length === 0) { console.log(`PLAN-HIERARCHY REFUSED: parsed 0 rows from ${PLAN} — the parser, not the plan, is the finding`); process.exit(2) }

const byId = new Map(rows.map((r) => [r.id, r]))
const children = new Map()
for (const r of rows) {
  if (!r.id.includes('.')) continue
  const parent = r.id.split('.')[0]
  if (!children.has(parent)) children.set(parent, [])
  children.get(parent).push(r)
}

// NON-VACUITY: all three properties are computed over the CHILD rows; with none they are
// vacuously true. Measured once: removing every `| N.N |` row left this gate PASS.
if (children.size === 0) {
  console.log(`PLAN-HIERARCHY REFUSED — ${PLAN} declares no child rows (\`| N.N |\`), and all ` +
    'three properties here are computed over that population, so each is vacuously true. ' +
    'Not a failing plan, an ungradeable one. Decompose at least one row into N.1 … N.k.')
  process.exit(2)
}

let failed = 0
const ok = (cond, msg) => { if (cond) console.log(`  ok   ${msg}`); else { failed++; console.log(`  FAIL ${msg}`) } }
console.log(`PLAN-HIERARCHY — ${rows.length} rows, ${children.size} parent(s) with children`)

const orphans = [...children.keys()].filter((p) => !byId.has(p))
ok(orphans.length === 0, orphans.length ? `every child row has a parent — ORPHANED: ${orphans.map((o) => o + '.x').join(', ')}` : 'every child row has a parent row that exists')

const gaps = []
for (const [p, kids] of children) {
  const nums = kids.map((k) => Number(k.id.split('.')[1])).sort((a, b) => a - b)
  for (let i = 0; i < nums.length; i++) if (nums[i] !== i + 1) { gaps.push(`${p}.${i + 1} missing (saw ${nums.join(',')})`); break }
}
ok(gaps.length === 0, gaps.length ? `children are numbered contiguously from 1 — ${gaps.join('; ')}` : 'children are numbered contiguously from 1')

const premature = []
for (const [p, kids] of children) {
  const parent = byId.get(p)
  if (!parent || !DONE.test(parent.status)) continue
  const open = kids.filter((k) => !DONE.test(k.status))
  if (open.length) premature.push(`row ${p} is '${parent.status}' with ${open.length} open child: ${open.map((o) => o.id).join(', ')}`)
}
ok(premature.length === 0, premature.length ? `no parent is done while a child is open — ${premature.join(' | ')}` : 'no parent is marked done while one of its children is open')

console.log('\n  decomposed rows:')
for (const [p, kids] of [...children].sort((a, b) => Number(a[0]) - Number(b[0]))) {
  const done = kids.filter((k) => DONE.test(k.status)).length
  console.log(`    row ${p}: ${done}/${kids.length} subtasks done — ${(byId.get(p)?.task || '').slice(0, 60)}`)
}
console.log(failed === 0 ? '\nPLAN-HIERARCHY PASS  (3 checks)' : `\nPLAN-HIERARCHY FAIL (${failed} failing)`)
process.exit(failed === 0 ? 0 : 1)
