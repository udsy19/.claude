#!/usr/bin/env node
/**
 * Print ONE plan row, so an agent does not have to read the whole plan to see its task.
 *
 * WHY. A plan of record grows past what a Read tool returns in one call. Measured in the
 * project this kit came from (a 37,500-token Plan.md): an agent assigned row 2.1 graded the
 * row "from a partial view of the file". A task read partially is a task guessed at, and
 * the guess is invisible to everyone downstream.
 *
 *   node scripts/plan-row.mjs 2.1        # one row, all six columns, in full
 *   node scripts/plan-row.mjs 2          # a parent prints its children too
 *   node scripts/plan-row.mjs --open     # every row not yet done, id + task only
 *
 * Refuses an unrecognised argument by name (exit 2). Exits 1 when the row does not exist,
 * because an agent asking for a row that is not there must not read that as "nothing to do".
 */
import fs from 'node:fs'
import path from 'node:path'
import { refuseUnknownArgv } from './lib/argv.mjs'
import { fileURLToPath } from 'node:url'

// EVERY LINE THIS FILE PRINTS GOES OUT SYNCHRONOUSLY. When stdout is a PIPE, console.log is
// asynchronous and `process.exit()` does not wait for the queue — measured: 4 of 40 piped
// runs of `--open` delivered a PREFIX of the listing, exit 0, no error. `fs.writeSync`
// returns when the bytes are gone. A closed pipe (`| head`) arrives as EPIPE at the write
// site and is answered there.
const out = (s = '') => {
  try { fs.writeSync(1, `${s}\n`) } catch (e) { if (e?.code === 'EPIPE') process.exit(0); throw e }
}

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
const PLAN = path.join(ROOT, 'vault/Plan.md')
const argv = process.argv.slice(2)
// ONE REFUSAL, ON STDERR: a refusal on stdout is written into the tool's DATA channel.
refuseUnknownArgv(argv.filter((a) => a.startsWith('--')), {
  script: 'plan-row', accepts: ['--open'], takes: 'a row id',
})
const OPEN = argv.includes('--open')
const refuse = (m) => { try { fs.writeSync(2, `plan-row: ${m}\n`) } catch { /* the exit code still speaks */ } process.exit(2) }
let want = null
for (const a of argv) {
  if (a.startsWith('--')) continue
  if (want === null) want = a
  else refuse(`one row id at a time (got '${want}' and '${a}')`)
}
if (!OPEN && want === null) refuse('give a row id (e.g. 2.1) or --open')
if (want !== null && !/^\d+(\.\d+)?$/.test(want)) refuse(`'${want}' is not a row id`)
if (!fs.existsSync(PLAN)) refuse(`no ${path.relative(ROOT, PLAN)}`)

const HEAD = ['#', 'task', 'serves', 'owner line', 'acceptance gate', 'status']
const rows = []
for (const [i, line] of fs.readFileSync(PLAN, 'utf8').split('\n').entries()) {
  const m = /^\|\s*(\d+(?:\.\d+)?)\s*\|/.exec(line)
  if (!m) continue
  // Split on a pipe that is NOT escaped: a cell may legally contain `\|` (a quoted shell
  // pipe), and a naive split gives eight cells instead of six, printing acceptance prose
  // under the heading STATUS. The ends-anchored fallback is a net for a really malformed row.
  const raw = line.split(/(?<!\\)\|/).slice(1, -1).map((c) => c.trim())
  const malformed = raw.length !== 6
  const cells = malformed ? [raw[0], raw[1], '', '', '', raw[raw.length - 1]] : raw
  rows.push({ id: m[1], lineNo: i + 1, cells, malformed, rawCount: raw.length })
}
if (rows.length === 0) refuse(`parsed 0 rows from ${path.relative(ROOT, PLAN)} — the parser, not the plan, is the finding`)

const DONE = /^(done|done:|shipped|landed)/i
if (OPEN) {
  const open = rows.filter((r) => !DONE.test(r.cells[5] || ''))
  out(`${open.length} open of ${rows.length} rows in vault/Plan.md\n`)
  for (const r of open) out(`  ${r.id.padEnd(6)} ${(r.cells[5] || '').padEnd(28)} ${(r.cells[1] || '').slice(0, 96)}`)
  out('\nRead one in full with: node scripts/plan-row.mjs <id>')
  process.exit(0)
}

const hit = rows.filter((r) => r.id === want || r.id.startsWith(want + '.'))
if (!hit.length) {
  out(`plan-row: row ${want} does not exist in vault/Plan.md.`)
  out('A missing row is NOT an empty task list — check the id with --open before assuming there is nothing to do.')
  process.exit(1)
}
for (const r of hit) {
  const kids = rows.filter((x) => x.id.startsWith(r.id + '.'))
  if (r.malformed) {
    out(`NOTE  row ${r.id} is MALFORMED markdown: ${r.rawCount} cells, not 6 — an unescaped |`)
    out('      inside a cell. Id and status are read from the ENDS and are correct; the middle')
    out('      columns are SUPPRESSED rather than printed under the wrong headings.')
    out("      The fix is the supervisor's: escape the pipe in vault/Plan.md.\n")
  }
  out(`${'─'.repeat(78)}\nROW ${r.id}   (vault/Plan.md:${r.lineNo})` +
    (kids.length ? `   ${kids.filter((k) => DONE.test(k.cells[5] || '')).length}/${kids.length} subtasks done` : ''))
  out('─'.repeat(78))
  for (let c = 0; c < HEAD.length; c++) {
    const v = r.cells[c] || ''
    if (!v) continue
    out(`\n${HEAD[c].toUpperCase()}\n  ${v.replace(/\s*·\s*/g, '\n  · ').replace(/\\\|/g, '|')}`)
  }
  out()
}
out(`${'─'.repeat(78)}\nYou may NOT edit vault/Plan.md. To change a row: node scripts/propose.mjs --row ${want} --kind <split|reorder|add|done|challenge> --why "..."`)
