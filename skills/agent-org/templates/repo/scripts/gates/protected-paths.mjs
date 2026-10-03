#!/usr/bin/env node
// A closed pipe is not an error: `node scripts/x.mjs | head` must not report failure.
process.stdout.on('error', (e) => { if (e && e.code === 'EPIPE') process.exit(0) })
/**
 * The protected list has ONE declaration (scripts/lib/protected-paths.mjs). This holds
 * every document that states the contract to it.
 *
 * Two properties, and the second is the one that catches the next drift:
 *   1. every document NAMES every protected path;
 *   2. no document GRANTS one away — a sentence that permits writing a protected path is a
 *      contradiction even when the path is also named correctly elsewhere on the page.
 * Plus: the enforcers import the declaration rather than restating it, and the supervisor
 * contract names the roles that may write.
 *
 *   node scripts/gates/protected-paths.mjs
 */
import fs from 'node:fs'
import path from 'node:path'
import { PROTECTED, AUTHORS } from '../lib/protected-paths.mjs'
import { fileURLToPath } from 'node:url'

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..')
if (process.argv.length > 2) {
  console.log(`protected-paths: unrecognised argument '${process.argv[2]}' — accepts: (none)`)
  process.exit(2)
}

// Every document that states who may write what. The rules file is auto-loaded into every
// agent, so it is the one copy an agent reads without being sent to it — which is exactly
// why it is held to the declaration here rather than trusted.
const DOCS = ['vault/AGENTS.md', 'vault/SUPERVISOR.md', 'vault/CLAUDE.md', '.claude/rules/protected-paths.md']
const ENFORCERS = ['scripts/hooks/agent-contract.mjs', 'scripts/gates/plan-ownership.mjs']

let failed = 0
// Returns the condition, so `if (!ok(...)) continue` guards really guard.
const ok = (cond, msg) => { if (cond) console.log(`  ok   ${msg}`); else { failed++; console.log(`  FAIL ${msg}`) }; return !!cond }
const read = (f) => { try { return fs.readFileSync(path.join(ROOT, f), 'utf8') } catch { return null } }

// NON-VACUITY, BEFORE ANYTHING IS GRADED. Every row below filters one of these lists, and
// an empty one makes each vacuously true ("3 documents agreeing about NOTHING"). REFUSES
// (exit 2): an empty declaration is a tree this gate cannot grade, not one that fails it.
if (!PROTECTED.length || !DOCS.length || !ENFORCERS.length) {
  console.log(`PROTECTED-PATHS REFUSED — nothing to grade: ${PROTECTED.length} protected path(s), ` +
    `${DOCS.length} document(s), ${ENFORCERS.length} enforcer(s).`)
  process.exit(2)
}
console.log(`PROTECTED-PATHS — ${PROTECTED.length} paths, ${DOCS.length} documents, ${ENFORCERS.length} enforcers`)

// 1. the enforcers must IMPORT the declaration, never restate it
for (const f of ENFORCERS) {
  const src = read(f)
  if (!ok(src !== null, `${f} exists`)) continue
  ok(/protected-paths\.mjs/.test(src), `${f} imports the shared declaration`)
  ok(!/const PROTECTED\s*=\s*\[/.test(src), `${f} does NOT carry its own copy of the list`)
}

// 2. every document names every path
for (const f of DOCS) {
  const src = read(f)
  if (!ok(src !== null, `${f} exists`)) continue
  const missing = PROTECTED.filter((e) => !src.includes(e.path))
  ok(missing.length === 0,
    missing.length ? `${f} names every protected path — MISSING ${missing.map((m) => m.path).join(', ')}`
                   : `${f} names every protected path`)
}

// 3. NO DOCUMENT GRANTS ONE AWAY. The wording that actually shipped once is the seed:
//    "may write ... status fields in existing notes' frontmatter" and "a Decisions/ draft".
const GRANTS = [
  [/an agent may write[^.]*\bDecisions\//i, 'permits writing under Decisions/'],
  [/may write[^.]*`?Decisions\/`?[^.]*draft/i, 'permits a Decisions/ draft'],
  [/may (?:write|edit)[^.]*\bvault\/Plan\.md/i, 'permits writing vault/Plan.md'],
  [/may (?:write|edit)[^.]*\bvault\/Roadmap\.md/i, 'permits writing vault/Roadmap.md'],
  [/may (?:write|edit)[^.]*\.claude\/rules\//i, 'permits writing .claude/rules/'],
]
// A document that EXPLAINS an old contradiction quotes its wording, and a detector that
// cannot tell a quotation from a claim reports the explanation as the defect. Historical
// paragraphs are excluded; a real grant is not written in the past tense. By PARAGRAPH,
// because a disclaimer and its quotation can sit lines apart and a paragraph is the unit a
// reader judges. (Keep this list narrow: every word added here is a way to hide a grant.)
const HISTORICAL = /used to|previously|no longer|contradict|refuses outright/i
const graded = (src) => src.split(/\n\s*\n/).filter((para) => !HISTORICAL.test(para)).join('\n\n')
for (const f of DOCS) {
  const src = read(f)
  if (src === null) continue
  const hits = GRANTS.filter(([re]) => re.test(graded(src))).map(([, what]) => what)
  ok(hits.length === 0, hits.length ? `${f} grants NO protected path away — it ${hits.join('; it ')}` : `${f} grants no protected path away`)
}

// 4. the roles that may write are stated, not folk knowledge
{
  const src = read('vault/SUPERVISOR.md')
  if (src !== null) ok(AUTHORS.every((r) => src.toLowerCase().includes(r)), `vault/SUPERVISOR.md names the roles that may write (${AUTHORS.join(', ')})`)
}

console.log(failed === 0 ? `\nPROTECTED-PATHS PASS  (one declaration, ${DOCS.length} documents agreeing with it)`
                         : `\nPROTECTED-PATHS FAIL (${failed} failing)`)
process.exit(failed === 0 ? 0 : 1)
