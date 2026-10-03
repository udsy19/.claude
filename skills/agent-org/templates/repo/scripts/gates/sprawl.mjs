#!/usr/bin/env node
// scripts/gates/sprawl.mjs — A LANDING MAY NOT GROW THE TRACKED TREE IN SILENCE.
//
//   node scripts/gates/sprawl.mjs                       # grade the default range (see below)
//   node scripts/gates/sprawl.mjs --base <rev> --tip <rev>
//   node scripts/gates/sprawl.mjs --census              # + the full per-directory evidence census
//   node scripts/gates/sprawl.mjs --selftest            # replay the built-in cases, touch no git
//
// THE DEFECT THIS EXISTS FOR, measured in the project this kit came from: the repository
// went 4,804 → 5,352 tracked files overnight, and nothing anywhere noticed, because nothing
// anywhere counted. Agents produce evidence faster than cleanup removes it, and every one
// of those landings was green on its board.
//
// THE PROPERTY (not a fix): *the tracked-file count may not grow unless a commit in the
// range SAYS WHY, in words the gate could not have written itself.* Growth is legitimate —
// a gate needs its fixtures — so this is not a ban. It is a requirement that growth be a
// decision somebody took on the record, and the record is the commit message: the one
// artifact a lander cannot produce after the fact without rewriting history.
//
// INDEPENDENCE (.claude/rules/gate-independence.md). BOTH counts are re-derived from GIT
// OBJECTS — `git ls-tree -r --name-only <rev>` — never from anything the producer wrote
// down. ADDED/REMOVED are a set difference of the two listings, not `git diff
// --diff-filter=A`, so no rename heuristic sits between the objects and the verdict. The
// one thing it consumes from the producer is the justification itself — graded as a
// STATEMENT, never trusted as a MEASUREMENT.
//
// THE VACUITY BAR. `EVIDENCE-GROWTH: yes` must be RED, or the rule is a formality. A
// justification clears the bar only when ALL of these hold:
//   V1  NON-EMPTY.  There is text after the colon.
//   V2  IT NAMES THE GROWTH.  At least one path-like token (two or more segments) is equal
//       to, or a directory prefix of, a file the range ADDED.
//   V3  IT NAMES EVERY NEW EVIDENCE DIRECTORY.  For each new top-level `evidence/<dir>/`,
//       `evidence/<dir>` appears in the reason as a path (boundary-matched: a filename that
//       merely CONTAINS the directory name does not count).
//   V4  IT SAYS SOMETHING THE GATE COULD NOT HAVE COMPUTED.  Strip every path-like token and
//       every new-directory name — the gate derived those itself — and what remains must be
//       at least RESIDUE_MIN_WORDS words and RESIDUE_MIN_CHARS characters.
// V4 is the conjunct that makes the other three mean anything: without it,
// `EVIDENCE-GROWTH: evidence/x` clears V1–V3 while restating the gate's own output back at
// it. Every justification paragraph must clear V1 and V4 individually; V2 and V3 are graded
// over their UNION, because two commits may legitimately split one landing's account.
//
// THE SECOND STANDING RULE — a new evidence directory explains itself. Every NEW top-level
// `evidence/<dir>/` must carry a README.md that names a path which EXISTS in the tip tree,
// and that path's source must mention the directory ON A NON-COMMENT LINE (a reader whose
// only connection is a sentence ABOUT the directory reads nothing). STATED CEILING: a
// non-comment mention is still not a proof of a READ. PRE-EXISTING directories are counted
// and printed by the census, never graded — retro-grading would make the row permanently
// red and therefore permanently ignored.
//
// THE GUARDS, in the units of the band they defend (the assertion grades a difference of
// ONE file):
//   · either revision failing to resolve            → REFUSED, exit 2
//   · base not an ancestor of tip                   → REFUSED, exit 2
//   · the TIP count below MIN_TRACKED_FILES         → REFUSED, exit 2 ("0 → 0, PASS" is
//     the degenerate case; the floor must exceed the one-file band by enough that clearing
//     it means "this is the repository"). The BASE is not floored: the first landing of a
//     young repository (the agent-org install itself) grows a two-file tree, and that growth
//     is exactly what this gate must grade, not refuse.
//   · the commit range is EMPTY                     → SKIP, exit 77 — never a pass
//
// The trailer is paragraph-aware (scripts/lib/commit-trailers.mjs) and the range is the
// shared landing range (scripts/lib/landing-range.mjs).

import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { refuseUnknownArgv } from '../lib/argv.mjs'
import { chooseBaseRev, gitText, isRepo, rangeCommits, rangeMessages, resolveRevs } from '../lib/landing-range.mjs'
import { tokens, trailerParagraphs } from '../lib/commit-trailers.mjs'

const GID = 'SPRAWL'
const REPO = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..')

// The bar's numbers, hoisted so a reader can argue with them. Four words is the shortest
// clause that carries a subject and a purpose ("fixtures for the sabotage round").
export const RESIDUE_MIN_WORDS = 4
export const RESIDUE_MIN_CHARS = 16
// Twenty, not one hundred: a freshly bootstrapped repository is ~80 files, and the floor
// must refuse an empty or mis-addressed tree, not a young one.
export const MIN_TRACKED_FILES = 20
export const TRAILER = 'EVIDENCE-GROWTH:'

function refuse(msg) {
  console.log(`${GID} REFUSED — ${msg}`)
  console.log('  Nothing was graded: a count this gate cannot trust is not a count.')
  process.exit(2)
}

/** Every tracked path at <rev>, from the git objects. No working tree is read. */
function treeFiles(rev, repo) {
  const out = gitText(repo, ['ls-tree', '-r', '--name-only', '-z', rev], { allowFail: true })
  return out === null ? null : out.split('\0').filter(Boolean)
}

// ---------------------------------------------------------------------------
// THE PURE DECISION. `--selftest` drives exactly this function, so the thing replayed is
// the thing that grades.
// ---------------------------------------------------------------------------

const PATH_TOKEN = /^[A-Za-z0-9._@+-]+(?:\/[A-Za-z0-9._@+-]+)+\/?$/
export function pathTokens(text) {
  return tokens(text).filter((t) => PATH_TOKEN.test(t)).map((t) => t.replace(/\/+$/, ''))
}
/** Does `tok` name `file`, either exactly or as one of its directory prefixes? */
function namesFile(tok, file) { return file === tok || file.startsWith(tok + '/') }

/** Top-level `evidence/<dir>` names present in a file list. */
export function evidenceDirs(files) {
  const s = new Set()
  for (const f of files) { const m = /^evidence\/([^/]+)\//.exec(f); if (m) s.add(m[1]) }
  return s
}
export function growthParagraphs(message) { return trailerParagraphs(message, TRAILER) }

/** A line that mentions one of `needles` outside a single-line comment, or null. */
export function nonCommentMention(source, needles) {
  const lines = String(source ?? '').split('\n')
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i]
    if (!needles.some((n) => line.includes(n))) continue
    const t = line.trim()
    if (/^(\/\/|#|\*|\/\*|<!--|--\s|;)/.test(t)) continue
    return { lineNo: i + 1, text: t.slice(0, 160) }
  }
  return null
}

export function evaluate({ baseFiles, tipFiles, growth, readTip }) {
  const rows = []
  const ok = (cond, msg) => { rows.push({ ok: !!cond, msg }); return !!cond }
  const baseSet = new Set(baseFiles)
  const tipSet = new Set(tipFiles)
  const added = tipFiles.filter((f) => !baseSet.has(f))
  const removed = baseFiles.filter((f) => !tipSet.has(f))
  const delta = tipFiles.length - baseFiles.length
  const byDir = new Map()
  const bump = (f, n) => { const d = f.includes('/') ? f.slice(0, f.indexOf('/')) : '(root)'; byDir.set(d, (byDir.get(d) ?? 0) + n) }
  for (const f of added) bump(f, +1)
  for (const f of removed) bump(f, -1)
  const baseDirs = evidenceDirs(baseFiles)
  const newDirs = [...evidenceDirs(tipFiles)].filter((d) => !baseDirs.has(d)).sort()
  const report = { baseCount: baseFiles.length, tipCount: tipFiles.length, delta, added, removed, byDir, newDirs, growth }

  // ---- rule one: the delta, and its justification -------------------------
  if (delta > 0) {
    const has = ok(growth.length > 0,
      `the tracked tree grew by ${delta} file(s) and NO commit in the range carries a \`${TRAILER} <reason>\` line`)
    if (has) {
      for (const g of growth) {
        const reason = g.line.slice(g.line.indexOf(TRAILER) + TRAILER.length).trim()
        ok(reason.length > 0, `V1 ${g.sha}: \`${TRAILER}\` carries no reason at all`)
        const strip = new Set([...pathTokens(reason), ...newDirs])
        const residue = tokens(reason).filter((t) => !strip.has(t.replace(/\/+$/, '')))
        const words = residue.filter((t) => /[A-Za-z]/.test(t))
        const chars = residue.join(' ').length
        ok(words.length >= RESIDUE_MIN_WORDS && chars >= RESIDUE_MIN_CHARS,
          `V4 ${g.sha}: VACUOUS — strip the paths and directory names this gate derived itself and ` +
          `${words.length} word(s) / ${chars} char(s) remain, under the ${RESIDUE_MIN_WORDS}/${RESIDUE_MIN_CHARS} floor. ` +
          `Residue: "${residue.join(' ').slice(0, 80)}"`)
      }
      const toks = pathTokens(growth.map((g) => g.line).join('\n'))
      const naming = toks.filter((t) => added.some((f) => namesFile(t, f)))
      ok(naming.length > 0,
        `V2: no path in the justification names anything the range ADDED — ` +
        `${toks.length} path-like token(s) (${toks.slice(0, 4).join(' ') || 'none'}), 0 of them inside the ${added.length} added file(s)`)
      const unnamed = newDirs.filter((d) => !toks.some((t) => namesFile(`evidence/${d}`, t)))
      ok(unnamed.length === 0,
        `V3: ${unnamed.length} new evidence directory/ies are created and never named in the justification: ${unnamed.join(' ')}`)
    }
  } else {
    rows.push({ ok: true, msg: `delta ${delta} — the tracked tree did not grow, so no justification is owed` })
  }

  // ---- rule two: a new evidence directory explains itself -----------------
  for (const d of newDirs) {
    const readmePath = `evidence/${d}/README.md`
    if (!ok(tipSet.has(readmePath), `README: the new directory evidence/${d}/ has no README.md`)) continue
    const readme = readTip(readmePath)
    if (!ok(readme !== null && readme.trim().length > 0, `README: ${readmePath} is unreadable or empty`)) continue
    const cands = [...new Set(pathTokens(readme))].filter((t) => tipSet.has(t))
    if (!ok(cands.length > 0,
      `README: ${readmePath} names no path that EXISTS in the tip tree ` +
      `(path-like tokens: ${[...new Set(pathTokens(readme))].slice(0, 5).join(' ') || 'none'})`)) continue
    let hit = null
    for (const c of cands) {
      const src = readTip(c)
      const m = src === null ? null : nonCommentMention(src, [`evidence/${d}`])
      if (m) { hit = { file: c, ...m }; break }
    }
    ok(hit !== null,
      `README: ${readmePath} names ${cands.length} existing path(s) (${cands.slice(0, 3).join(' ')}) but NONE of them ` +
      `mentions evidence/${d} on a non-comment line — a README naming a reader that never reads the directory`)
    if (hit) report[`reader:${d}`] = `${hit.file}:${hit.lineNo}`
  }
  return { rows, report }
}

// ---------------------------------------------------------------------------
// printing
// ---------------------------------------------------------------------------
function printReport(r, base, tip, baseRev, tipRev) {
  console.log(`${GID} — tracked-file sprawl, ${baseRev} (${base}) .. ${tipRev} (${tip})`)
  console.log(`  base ${String(r.baseCount).padStart(6)} tracked files`)
  console.log(`  tip  ${String(r.tipCount).padStart(6)} tracked files`)
  console.log(`  delta ${r.delta > 0 ? '+' : ''}${r.delta}   (+${r.added.length} added, -${r.removed.length} removed, a set difference of two \`git ls-tree -r\` listings)`)
  const dirs = [...r.byDir.entries()].sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0]))
  if (dirs.length) {
    console.log('  growth by top-level directory:')
    for (const [d, n] of dirs) console.log(`    ${n > 0 ? '+' : ''}${String(n).padStart(5)}  ${d}`)
  }
  if (r.newDirs.length) console.log(`  new top-level evidence directories (${r.newDirs.length}): ${r.newDirs.join(' ')}`)
  if (r.growth.length === 0) console.log(`  justification: NONE — no \`${TRAILER}\` line in the range`)
  for (const g of r.growth) {
    const para = g.line.trim().split('\n')
    console.log(`  justification @ ${g.sha}: ${para[0]}`)
    for (const l of para.slice(1)) console.log(`      ${l.trim()}`)
  }
  for (const k of Object.keys(r)) if (k.startsWith('reader:')) console.log(`  reader of evidence/${k.slice(7)}/: ${r[k]}`)
}

/**
 * THE NON-GRADING CENSUS. Its scope is printed on every run, because a census whose
 * population is unstated is a claim. Scope: every tracked top-level entry except `vault/`
 * and `evidence/` (a report that DESCRIBES a directory is not a reader of it).
 */
function census(tipFiles, tipRev, repo, full) {
  const dirs = [...evidenceDirs(tipFiles)].sort()
  const scope = [...new Set(tipFiles.map((f) => f.split('/')[0]))].filter((t) => t !== 'vault' && t !== 'evidence').sort()
  const readme = new Set(dirs.filter((d) => tipFiles.includes(`evidence/${d}/README.md`)))
  const cited = new Set()
  if (dirs.length && scope.length) {
    const args = ['grep', '-l', '-I', '-F']
    for (const d of dirs) args.push('-e', `evidence/${d}`)
    args.push(tipRev, '--', ...scope)
    const files = (gitText(repo, args, { allowFail: true }) ?? '').split('\n').filter(Boolean).map((l) => l.replace(/^[^:]*:/, ''))
    for (const f of files) {
      const src = gitText(repo, ['show', `${tipRev}:${f}`], { allowFail: true }) ?? ''
      for (const d of dirs) if (src.includes(`evidence/${d}`)) cited.add(d)
    }
  }
  const noReadme = dirs.filter((d) => !readme.has(d))
  const noCite = dirs.filter((d) => !cited.has(d))
  console.log(`  note[census, NON-GRADING] ${dirs.length} top-level evidence directories at ${tipRev.slice(0, 9)}: ` +
    `${noReadme.length} have no README.md, ${noCite.length} are named by no tracked file outside vault/ and evidence/.`)
  console.log(`  note[census, NON-GRADING] scope of "named": tracked files under ${scope.join(' ') || '(nothing)'}. ` +
    'Ceiling: a MENTION is not a READ. Pre-existing directories are counted here and graded nowhere.')
  if (full) {
    console.log('  dir                                        README  cited')
    for (const d of dirs) console.log(`    ${d.padEnd(42)} ${readme.has(d) ? '  yes ' : '  NO  '}  ${cited.has(d) ? 'yes' : 'NO'}`)
  }
}

// ---------------------------------------------------------------------------
// --selftest: built-in decision-level cases, replayed through evaluate(). No git, no tree.
// Each FAIL case must fail for its RECORDED reason — a red is not a diagnosis.
// ---------------------------------------------------------------------------
function selftestCases() {
  const filler = Array.from({ length: 40 }, (_, i) => `src/filler/f${i}.js`)
  const base = [...filler, 'scripts/gates/unrelated-gate.mjs', 'README.md']
  const P = 'evidence/zz-sprawl-probe'
  const unrelated = '// a real gate that reads nothing under evidence/\nexport const ok = true\n'
  const readmeFor = (reader) => `# probe\n\nRead by \`${reader}\`.\n`
  const realReader = `// A probe reader.\nimport fs from 'node:fs'\nconst DIR = '${P}'\nexport const notes = () => fs.readdirSync(DIR)\n`
  const commentReader = `// A probe reader whose ONLY mention of ${P} is this comment.\nimport fs from 'node:fs'\nexport const notes = () => fs.readdirSync(process.argv[2])\n`
  const good = `${TRAILER} the probe fixtures the sabotage round builds and replays, under ${P}`
  const withDir = (extra) => [...base, `${P}/README.md`, `${P}/note.txt`, ...extra]
  const files = (o) => ({ 'scripts/gates/unrelated-gate.mjs': unrelated, [`${P}/note.txt`]: 'a probe note\n', ...o })
  const g = (line) => [{ sha: 'c0ffee000', line }]
  return [
    { name: 'A1 growth with NO justification', expect: 'FAIL', because: 'NO commit in the range carries',
      baseFiles: base, tipFiles: [...base, 'src/zz-probe-a.js', 'src/zz-probe-b.js'], growth: [], files: files({}) },
    { name: 'A2 the same growth, justified', expect: 'PASS',
      baseFiles: base, tipFiles: [...base, 'src/zz-probe-a.js', 'src/zz-probe-b.js'],
      growth: g(`${TRAILER} two probe modules added so the round has something to grade, src/zz-probe-a.js`), files: files({}) },
    { name: 'A3 vacuous justification — `EVIDENCE-GROWTH: yes`', expect: 'FAIL', because: 'VACUOUS',
      baseFiles: base, tipFiles: [...base, 'src/zz-probe-a.js'], growth: g(`${TRAILER} yes`), files: files({}) },
    { name: "A3b vacuous the SUBTLE way — the reason restates the gate's own output", expect: 'FAIL', because: 'VACUOUS',
      baseFiles: base, tipFiles: withDir(['scripts/zz-probe-reader.mjs']), growth: g(`${TRAILER} ${P}`),
      files: files({ [`${P}/README.md`]: readmeFor('scripts/zz-probe-reader.mjs'), 'scripts/zz-probe-reader.mjs': realReader }) },
    { name: 'A4 a NEW evidence directory with no README', expect: 'FAIL', because: 'has no README.md',
      baseFiles: base, tipFiles: [...base, `${P}/note.txt`], growth: g(good), files: files({}) },
    { name: 'A5 README names a gate that does not EXIST', expect: 'FAIL', because: 'names no path that EXISTS',
      baseFiles: base, tipFiles: withDir([]), growth: g(good), files: files({ [`${P}/README.md`]: readmeFor('scripts/gates/zz-no-such-gate.mjs') }) },
    { name: 'A6 README names a REAL gate that never reads the directory', expect: 'FAIL', because: 'on a non-comment line',
      baseFiles: base, tipFiles: withDir([]), growth: g(good), files: files({ [`${P}/README.md`]: readmeFor('scripts/gates/unrelated-gate.mjs') }) },
    { name: 'A6b README names a reader whose ONLY mention is a comment', expect: 'FAIL', because: 'on a non-comment line',
      baseFiles: base, tipFiles: withDir(['scripts/zz-probe-reader.mjs']), growth: g(good),
      files: files({ [`${P}/README.md`]: readmeFor('scripts/zz-probe-reader.mjs'), 'scripts/zz-probe-reader.mjs': commentReader }) },
    { name: 'A7 a pure DELETION', expect: 'PASS',
      baseFiles: [...base, 'src/old-1.js', 'src/old-2.js'], tipFiles: base, growth: [], files: files({}) },
    { name: 'A8 the whole legal shape — justified growth, a dir, a README, a real reader', expect: 'PASS',
      baseFiles: base, tipFiles: withDir(['scripts/zz-probe-reader.mjs']), growth: g(good),
      files: files({ [`${P}/README.md`]: readmeFor('scripts/zz-probe-reader.mjs'), 'scripts/zz-probe-reader.mjs': realReader }) },
    { name: 'A9 a fluent reason that names nothing the range added', expect: 'FAIL', because: 'V2: no path in the justification names anything the range ADDED',
      baseFiles: base, tipFiles: [...base, 'src/zz-probe-a.js'],
      growth: g(`${TRAILER} these probe modules were added so that the round has something to grade against`), files: files({}) },
    { name: 'A10 a justification that runs onto CONTINUATION lines', expect: 'PASS',
      baseFiles: base, tipFiles: withDir(['scripts/zz-probe-reader.mjs']),
      growth: g(`${TRAILER} tracked files +3. All three are the round's own capture —\nthe red-first log and the fixtures it replays, under ${P}, read by\nscripts/zz-probe-reader.mjs.`),
      files: files({ [`${P}/README.md`]: readmeFor('scripts/zz-probe-reader.mjs'), 'scripts/zz-probe-reader.mjs': realReader }) },
    { name: 'A11 V3 SUBSTRING false-PASS — a reader FILENAME contains the bare directory name', expect: 'FAIL', because: 'V3:',
      baseFiles: base, tipFiles: [...base, 'evidence/zz-v3probe/README.md', 'evidence/zz-v3probe/note.txt', 'scripts/zz-v3probe-reader.mjs'],
      growth: g(`${TRAILER} added scripts/zz-v3probe-reader.mjs, a reader module for the new probe fixtures, wired the usual way`),
      files: { 'evidence/zz-v3probe/README.md': readmeFor('scripts/zz-v3probe-reader.mjs'), 'evidence/zz-v3probe/note.txt': 'a note\n',
        'scripts/zz-v3probe-reader.mjs': "import fs from 'node:fs'\nconst DIR = 'evidence/zz-v3probe'\nexport const notes = () => fs.readdirSync(DIR)\n" } },
  ]
}

function selftest() {
  const cases = selftestCases()
  let failing = 0, checks = 0
  console.log(`${GID} selftest — replaying ${cases.length} built-in cases through evaluate()`)
  for (const c of cases) {
    const { rows } = evaluate({
      baseFiles: c.baseFiles, tipFiles: c.tipFiles, growth: c.growth,
      readTip: (p) => (Object.prototype.hasOwnProperty.call(c.files, p) ? c.files[p] : null),
    })
    const failed = rows.filter((r) => !r.ok)
    const got = failed.length === 0 ? 'PASS' : 'FAIL'
    checks++
    if (got !== c.expect) {
      failing++
      console.log(`  FAIL ${c.name} — expected ${c.expect}, got ${got}${failed.length ? ': ' + failed[0].msg : ''}`)
    } else {
      console.log(`  ok   ${c.name} → ${got}${failed.length ? ` (${failed[0].msg.slice(0, 96)})` : ''}`)
    }
    if (c.expect === 'FAIL') {
      checks++
      if (!failed.some((r) => r.msg.includes(c.because))) {
        failing++
        console.log(`  FAIL ${c.name} — red, but for the wrong reason: expected "${c.because}", got: ${failed.map((r) => r.msg).join(' | ').slice(0, 200)}`)
      }
    }
  }
  console.log(failing ? `${GID}-SELFTEST FAIL (${checks} checks, ${failing} failing)` : `${GID}-SELFTEST PASS (${checks} checks)`)
  process.exit(failing ? 1 : 0)
}

// ---------------------------------------------------------------------------
// main — guarded so the module can be imported without running
// ---------------------------------------------------------------------------
const IS_ENTRY = process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)
if (IS_ENTRY) main()

function main() {
  const argv = process.argv.slice(2)
  refuseUnknownArgv(argv, {
    script: 'sprawl.mjs',
    accepts: ['--base', '--tip', '--repo', '--census', '--selftest', '--help'],
    valued: ['--base', '--tip', '--repo'],
  })
  if (argv.includes('--help')) {
    console.log('usage: node scripts/gates/sprawl.mjs [--base <rev>] [--tip <rev>] [--repo <dir>] [--census] [--selftest]')
    process.exit(0)
  }
  if (argv.includes('--selftest')) selftest()
  const flag = (name, def = null) => { const i = argv.indexOf(name); return i >= 0 && i + 1 < argv.length ? argv[i + 1] : def }
  const repo = path.resolve(flag('--repo', REPO))
  if (!isRepo(repo)) refuse(`${repo} is not a git repository`)

  const tipRev = flag('--tip', 'HEAD')
  const baseRev = flag('--base', null) || chooseBaseRev({ repo, tipRev, refuse })
  const { base, tip, anc } = resolveRevs({ repo, baseRev, tipRev })
  if (!base) refuse(`base revision "${baseRev}" does not resolve to a commit`)
  if (!tip) refuse(`tip revision "${tipRev}" does not resolve to a commit`)
  if (anc.status !== 0) refuse(`base ${base.slice(0, 9)} is not an ancestor of tip ${tip.slice(0, 9)}, so \`base..tip\` is not the set of commits that produced the difference`)

  const baseFiles = treeFiles(base, repo)
  const tipFiles = treeFiles(tip, repo)
  if (!baseFiles || !tipFiles) refuse('git ls-tree did not return a listing for one of the two revisions')
  if (tipFiles.length < MIN_TRACKED_FILES) {
    refuse(`the tip count is below the ${MIN_TRACKED_FILES}-file floor (base ${baseFiles.length}, tip ${tipFiles.length}). ` +
      'This row grades a difference of ONE file; a tree this small is not a repository it can grade')
  }
  const range = rangeCommits({ repo, base, tip })
  if (range.length === 0) {
    console.log(`SKIP: ${base.slice(0, 9)}..${tip.slice(0, 9)} is empty — no landing to grade.`)
    console.log(`  ${tipFiles.length} tracked files. A "delta 0, PASS" here would be a pass because nothing happened; 77 is the skip channel.`)
    process.exit(77)
  }
  // Every justification in the range, read out of the commit OBJECT, not a formatted log.
  const growth = []
  for (const { sha, message } of rangeMessages({ repo, shas: range })) {
    for (const line of growthParagraphs(message)) growth.push({ sha, line })
  }
  const readTip = (p) => gitText(repo, ['show', `${tip}:${p}`], { allowFail: true })
  const { rows, report } = evaluate({ baseFiles, tipFiles, growth, readTip })

  printReport(report, baseFiles.length, tipFiles.length, baseRev, tipRev)
  console.log(`  range: ${range.length} commit(s) in ${base.slice(0, 9)}..${tip.slice(0, 9)}`)
  census(tipFiles, tip, repo, argv.includes('--census'))

  const reasons = rows.filter((r) => !r.ok).map((r) => r.msg)
  if (reasons.length) {
    console.log(`${GID} FAIL: ${reasons.slice(0, 4).join('; ')}${reasons.length > 4 ? ` (+${reasons.length - 4} more)` : ''}`)
    process.exit(1)
  }
  console.log(`${GID} PASS  (${rows.length} checks)`)
  process.exit(0)
}
