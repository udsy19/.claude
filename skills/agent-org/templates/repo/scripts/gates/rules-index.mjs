#!/usr/bin/env node
// A closed pipe is not an error: `node scripts/x.mjs | head` must not report failure.
process.stdout.on('error', (e) => { if (e && e.code === 'EPIPE') process.exit(0) })
// The laws and their worked cases live in TWO files, so they can drift apart in a way one
// file could not. This checks the join — the rules file's own law applied to itself: an
// index that drifts into a summary of a document it no longer describes.
//
//   node scripts/gates/rules-index.mjs
//
// Every numbered law in .claude/rules/gate-independence.md must appear as a `## ` heading
// in vault/Design/gate-independence-cases.md, matched as a LITERAL string — because the
// defect this catches is a heading reworded by one word, and anything looser would not see
// it. Sub-laws (4a, 13a, 14a) are indented in the index and `###` in the cases file.
import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..')
const RULES = path.join(ROOT, '.claude/rules/gate-independence.md')
const CASES = path.join(ROOT, 'vault/Design/gate-independence-cases.md')
const MIN_LAWS = 17   // the laws this kit ships; a project adds, it does not silently lose

const argv = process.argv.slice(2)
if (argv.length) {
  console.log(`rules-index: unrecognised argument '${argv[0]}' — accepts: (none)`)
  process.exit(2)
}

let failed = 0
let checks = 0
const ok = (cond, msg) => { checks++; if (cond) console.log(`  ok   ${msg}`); else { failed++; console.log(`  FAIL ${msg}`) } }

for (const f of [RULES, CASES]) {
  if (!fs.existsSync(f)) { console.log(`RULES-INDEX REFUSED: missing ${path.relative(ROOT, f)}`); process.exit(2) }
}
const rules = fs.readFileSync(RULES, 'utf8')
const cases = fs.readFileSync(CASES, 'utf8')

// the index entries: `N. **<heading>** — gloss`
const laws = [...rules.matchAll(/^\d+\.\s+\*\*(.+?)\*\*\s+—/gm)].map((m) => m[1])
const heads = [...cases.matchAll(/^## (.+)$/gm)].map((m) => m[1].trim())

ok(laws.length >= MIN_LAWS, `the index declares ${laws.length} laws (expected at least ${MIN_LAWS})`)
ok(heads.length >= MIN_LAWS, `the cases file carries ${heads.length} top-level headings`)

const missing = laws.filter((l) => !heads.some((h) => h === l))
ok(missing.length === 0,
  missing.length ? `every indexed law has a case with that EXACT heading — missing: ${missing.map((m) => JSON.stringify(m.slice(0, 48))).join(', ')}`
                 : 'every indexed law has a case with that EXACT heading')

const orphan = heads.filter((h) => !laws.some((l) => l === h))
ok(orphan.length === 0,
  orphan.length ? `every case is indexed — unindexed: ${orphan.map((o) => JSON.stringify(o.slice(0, 48))).join(', ')}`
                : 'every case heading appears in the index')

// the rules file must still POINT at the cases, or the split silently orphans them
ok(/gate-independence-cases/.test(rules), 'the rules file names the cases file')

// THE COUNT IS COUNTED, NOT TYPED, and zero checks is a refusal, not a pass.
if (checks === 0) {
  console.log('\nRULES-INDEX REFUSED — zero checks ran, so `failed === 0` means nothing here.')
  process.exit(2)
}
console.log(failed === 0 ? `\nRULES-INDEX PASS  (${checks} checks)` : `\nRULES-INDEX FAIL (${failed} of ${checks} failing)`)
process.exit(failed === 0 ? 0 : 1)
