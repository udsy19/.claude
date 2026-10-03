#!/usr/bin/env node
/**
 * `scripts/where.mjs` must answer "is this on MAIN?" about MAIN — and its branch census
 * must list only work that is really unlanded.
 *
 * THE DEFECTS THIS EXISTS FOR.
 *  1. where.mjs once greped the revision `HEAD` and printed the result under `ON MAIN`. From
 *     a branch worktree — the one situation an agent is routed to it for — a symbol that
 *     existed ONLY on that branch was reported as ALREADY ON MAIN.
 *  2. `--branches` once listed every file a branch merely CARRIED, under "This work EXISTS.
 *     Do not write a second one." Measured: 97.5% of those hits were main's own bytes
 *     (byte-identical, or main's OLDER bytes on a branch cut before main moved).
 *
 * WHAT IS GRADED, and how it stays independent of the thing it grades. Every ground truth
 * here is re-derived with the test's OWN `git grep` / `git diff`, never read out of
 * where.mjs's output, and every fixture premise is asserted BEFORE where.mjs runs (a
 * missing input is a FAILURE, never a skip). Every arm runs in a HERMETIC scratch repo with
 * this tree's where.mjs copied in, so the suite never touches the repo running it and works
 * on any project from its first commit.
 *
 * Takes no arguments.
 */
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { execFileSync } from 'node:child_process'
import { noGitEnv } from './lib/git-env.mjs'
import { fileURLToPath } from 'node:url'

if (process.argv.length > 2) {
  console.log(`where.test: unrecognised argument '${process.argv[2]}' — accepts: (none)`)
  process.exit(2)
}

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
const WHERE = path.join(ROOT, 'scripts', 'where.mjs')
const ENV = noGitEnv()
for (const k of ['ORG_MAIN_BRANCH', 'ORG_BRANCH_GLOBS', 'ORG_SEARCH_PATHS']) delete ENV[k]
const GIT_ID = { GIT_AUTHOR_NAME: 'where.test', GIT_AUTHOR_EMAIL: 'w@t', GIT_COMMITTER_NAME: 'where.test', GIT_COMMITTER_EMAIL: 'w@t' }

let failed = 0
let checksRun = 0
const check = (name, cond, detail = '') => {
  checksRun++
  if (cond) console.log(`  ok   ${name}`)
  else { failed++; console.log(`  FAIL ${name}${detail ? ' — ' + detail : ''}`) }
}

/** git, in a named repo, with a status of 1 (grep: no match) treated as a real empty. */
const git = (args, opts = {}) => {
  try {
    return execFileSync('git', args, {
      cwd: opts.cwd, env: { ...ENV, ...GIT_ID, ...(opts.env || {}) }, input: opts.input,
      encoding: 'utf8', maxBuffer: 32 * 1024 * 1024, stdio: ['pipe', 'pipe', 'pipe'],
    }).trim()
  } catch (e) {
    if (e.status === 1) return ''
    throw new Error(`git ${args.slice(0, 3).join(' ')} failed (${e.status}): ${String(e.stderr || e.message).split('\n')[0]}`)
  }
}

/** THE TEST'S OWN GROUND TRUTH — the files a revision really carries this symbol in. */
const filesWith = (rev, sym, opts, paths = []) =>
  git(['grep', '-l', '-w', '--', sym, rev, '--', ...paths], opts)
    .split('\n').filter(Boolean).map((l) => l.slice(rev.length + 1))

/** The paths whose CONTENT differs between two revs. */
const changedPaths = (a, b, opts) =>
  git(['diff', '--name-only', '--no-renames', a, b], opts).split('\n').filter(Boolean)

/**
 * Classify one branch's hits PER FILE, with one diff per path (the tool does one tree diff
 * per branch), so agreement is evidence and not transcription.
 *   identical — the branch's blob equals main's
 *   stale     — differs from main only because MAIN moved after the branch point
 *   kept      — differs from main AND from the merge-base: the branch really holds a change
 */
function classify(opts, mainRef, branch, sym) {
  const files = git(['grep', '-l', '-w', '--', sym, branch], opts)
    .split('\n').filter(Boolean).map((l) => l.slice(branch.length + 1))
  const mb = git(['merge-base', mainRef, branch], opts)
  const out = { kept: [], identical: [], stale: [] }
  for (const p of files) {
    const vsMain = git(['diff', '--name-only', '--no-renames', mainRef, branch, '--', p], opts) !== ''
    const vsBase = git(['diff', '--name-only', '--no-renames', mb, branch, '--', p], opts) !== ''
    if (!vsMain) out.identical.push(p)
    else if (!vsBase) out.stale.push(p)
    else out.kept.push(p)
  }
  return out
}
const expectCounts = (opts, mainRef, branches, sym) => {
  const per = new Map(branches.map((b) => [b, classify(opts, mainRef, b, sym)]))
  const sum = (k) => [...per.values()].reduce((a, c) => a + c[k].length, 0)
  return { per, kept: sum('kept'), identical: sum('identical'), stale: sum('stale') }
}

/** Run the tool under test from a given directory's copy of it. */
const runWhere = (dir, args, env = {}) => {
  try {
    return { code: 0, out: execFileSync('node', [path.join(dir, 'scripts', 'where.mjs'), ...args], { cwd: dir, env: { ...ENV, ...env }, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] }) }
  } catch (e) { return { code: e.status ?? 1, out: String(e.stdout || '') + String(e.stderr || '') } }
}

/** One top-level section: the heading line plus every indented line under it. */
const section = (out, heading) => {
  const lines = out.split('\n')
  const i = lines.findIndex((l) => l.startsWith(heading))
  if (i < 0) return null
  const body = []
  for (let j = i + 1; j < lines.length; j++) {
    if (lines[j].trim() && /^\S/.test(lines[j])) break
    body.push(lines[j])
  }
  return { head: lines[i], body: body.join('\n'), all: [lines[i], ...body].join('\n') }
}

const tmpRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'org-where-'))

/** A hermetic one-off repository with this tree's where.mjs in it. */
function scratchRepo(name, initialBranch) {
  const dir = path.join(tmpRoot, name)
  fs.mkdirSync(path.join(dir, 'scripts'), { recursive: true })
  fs.copyFileSync(WHERE, path.join(dir, 'scripts', 'where.mjs'))
  const opts = { cwd: dir }
  const g = (...a) => git(a, opts)
  g('init', '-q', '-b', initialBranch, '.')
  const put = (rel, body) => {
    fs.mkdirSync(path.dirname(path.join(dir, rel)), { recursive: true })
    fs.writeFileSync(path.join(dir, rel), body)
  }
  return { dir, g, put, opts }
}

try {
  // ---- (a) THE ROW: from a branch, a branch-only symbol is NOT on main -------------
  const SYM = `zzWhereBranchOnly${process.pid}`
  const MAINSYM = `zzWhereOnMain${process.pid}`
  const { dir: arepo, g: ag, put: aput, opts: aOpts } = scratchRepo('branch-repo', 'main')
  aput('src/base.js', `export const ${MAINSYM} = 1\n`)
  ag('add', '-A'); ag('commit', '-q', '-m', 'base')
  ag('checkout', '-q', '-b', 'lane/zz-feature')
  aput('src/feature.js', `export const ${SYM} = 1\n`)
  ag('add', '-A'); ag('commit', '-q', '-m', 'feature')
  const FIXTURE = 'src/feature.js'

  check("(a) fixture: the symbol is on the branch (test's own git grep)",
    filesWith('HEAD', SYM, aOpts).includes(FIXTURE), JSON.stringify(filesWith('HEAD', SYM, aOpts)))
  check("(a) fixture: the symbol is NOT on main (test's own git grep)",
    filesWith('main', SYM, aOpts).length === 0, JSON.stringify(filesWith('main', SYM, aOpts)))

  const r = runWhere(arepo, [SYM])
  const onMain = section(r.out, 'ON MAIN')
  const onHead = section(r.out, 'ON THIS BRANCH (HEAD)')
  check('(a) an ON MAIN section is printed even when main has no hit',
    !!onMain, r.out.split('\n').filter(Boolean).slice(0, 6).join(' / '))
  check('(a) ON MAIN does NOT name the branch-only file',
    !!onMain && !onMain.all.includes(FIXTURE), onMain ? onMain.all.trim().slice(0, 200) : '(no section)')
  check('(a) ON MAIN reports zero hits',
    !!onMain && /\bnone\b|\b0 line\(s\)/.test(onMain.head), onMain ? onMain.head : '(no section)')
  check('(a) ON MAIN names the ref it actually greped',
    !!onMain && /\b(origin\/)?main\b/.test(onMain.head), onMain ? onMain.head : '(no section)')
  check('(a) a separate ON THIS BRANCH (HEAD) section names the branch-only file',
    !!onHead && onHead.all.includes(FIXTURE), onHead ? onHead.all.trim().slice(0, 200) : '(no section)')
  check('(a) the run still exits 0 — the symbol WAS found, just not on main', r.code === 0, `exit ${r.code}`)

  // ---- (b) ANTI-VACUITY: a symbol that IS on main must be reported there -----------
  const mainTruth = filesWith('main', MAINSYM, aOpts)
  check(`(b) input: '${MAINSYM}' is on main (a missing input is a FAILURE, never a skip)`, mainTruth.length > 0)
  const rb = runWhere(arepo, [MAINSYM])
  const bMain = section(rb.out, 'ON MAIN')
  const mainSha = ag('rev-parse', 'main')
  check('(b) ON MAIN reports a symbol that really is on main',
    !!bMain && /[1-9]\d* line\(s\)/.test(bMain.head), bMain ? bMain.head : '(no section)')
  check('(b) the populated ON MAIN heading names the ref AND the commit it greped',
    !!bMain && /\bmain\b/.test(bMain.head) && bMain.head.includes(mainSha.slice(0, 9)),
    `${bMain ? bMain.head : '(no section)'} (main is ${mainSha.slice(0, 9)})`)
  check("(b) and names a file the test's own grep of main also names",
    !!bMain && mainTruth.some((f) => bMain.all.includes(f)), bMain ? bMain.all.trim().slice(0, 200) : '(no section)')

  // ---- (c) FROM THE MAIN CHECKOUT: HEAD is main, so do not print the list twice ----
  ag('checkout', '-q', 'main')
  const rc = runWhere(arepo, [MAINSYM])
  const cMain = section(rc.out, 'ON MAIN')
  const cHead = section(rc.out, 'ON THIS BRANCH (HEAD)')
  check('(c) HEAD == main: ON MAIN still reports the hits',
    !!cMain && /[1-9]\d* line\(s\)/.test(cMain.head), cMain ? cMain.head : '(no section)')
  check('(c) HEAD == main: the HEAD section says so instead of repeating the file list',
    !!cHead && /\bmain\b/.test(cHead.head) && !mainTruth.some((f) => cHead.all.includes(f)),
    cHead ? cHead.all.trim().slice(0, 200) : '(no section)')

  // ---- (d) NO `main` AT ALL: origin/main, said out loud — or a refusal by name -----
  const { dir: scratch, g: sgit, put: sput } = scratchRepo('scratch-repo', 'master')
  sput('scripts/base.mjs', 'export const zzScratchBaseSymbol = 1\n')
  sgit('add', '-A'); sgit('commit', '-q', '-m', 'base')
  const baseSha = sgit('rev-parse', 'HEAD')
  sput('scripts/tip.mjs', 'export const zzScratchTipSymbol = 1\n')
  sgit('add', '-A'); sgit('commit', '-q', '-m', 'tip')

  const rd0 = runWhere(scratch, ['zzScratchTipSymbol'])
  check('(d) neither main nor origin/main resolves: REFUSED by name, exit 2',
    rd0.code === 2 && /\bmain\b/.test(rd0.out) && /origin\/main/.test(rd0.out),
    `exit ${rd0.code}: ${rd0.out.split('\n').filter(Boolean).slice(-2).join(' / ')}`)
  sgit('update-ref', 'refs/remotes/origin/main', baseSha)
  const rd1 = runWhere(scratch, ['zzScratchTipSymbol'])
  const dMain = section(rd1.out, 'ON MAIN')
  const dHead = section(rd1.out, 'ON THIS BRANCH (HEAD)')
  check('(d) with only origin/main, the ON MAIN section says WHICH ref it used',
    !!dMain && dMain.head.includes('origin/main'), dMain ? dMain.head : `exit ${rd1.code}: ${rd1.out.slice(0, 200)}`)
  check('(d) a tip-only symbol is 0 on origin/main and present under HEAD',
    !!dMain && /\bnone\b|\b0 line\(s\)/.test(dMain.head) && !!dHead && dHead.all.includes('scripts/tip.mjs'),
    `${dMain ? dMain.head : '(no ON MAIN)'} || ${dHead ? dHead.all.trim().slice(0, 120) : '(no HEAD section)'}`)

  // ---- (e) WHICH ref wins when BOTH exist and they DISAGREE ----------------------
  // Local `main` is one commit ahead of origin/main and that commit carries the probe, so
  // the preference order decides the ANSWER: a just-landed-not-yet-pushed symbol.
  sgit('branch', 'main', 'HEAD')
  const tipSha = sgit('rev-parse', 'main')
  check('(e) fixture: local main and origin/main differ by exactly one commit',
    sgit('rev-list', '--count', 'origin/main..main') === '1' && tipSha !== baseSha)
  const re = runWhere(scratch, ['zzScratchTipSymbol'])
  const eMain = section(re.out, 'ON MAIN')
  check('(e) with BOTH refs present, ON MAIN reads local `main`, not `origin/main`',
    !!eMain && !/origin\/main/.test(eMain.head) && eMain.head.includes(tipSha.slice(0, 9)) && !eMain.head.includes(baseSha.slice(0, 9)),
    `${eMain ? eMain.head : '(no section)'} (main ${tipSha.slice(0, 9)}, origin/main ${baseSha.slice(0, 9)})`)
  check('(e) and therefore reports the symbol that landed on main but is not yet pushed',
    !!eMain && /[1-9]\d* line\(s\)/.test(eMain.head) && eMain.all.includes('scripts/tip.mjs'),
    eMain ? eMain.all.trim().slice(0, 200) : '(no section)')

  // ---- (f) THE CENSUS GRADES CONTENT, NOT BRANCHES -------------------------------
  const PROBE = `zzCensusProbe${process.pid}`
  const { dir: crepo, g: cg, put: cput, opts: cOpts } = scratchRepo('census-repo', 'main')
  cput('scripts/reverted.mjs', `export const ${PROBE} = 1\n`)
  cput('scripts/untouched.mjs', `export const ${PROBE} = 2\n`)
  cput('scripts/carrier.mjs', 'export const zzCensusCarrier = 1\n')
  cg('add', '-A'); cg('commit', '-q', '-m', 'base')
  cg('update-ref', 'refs/remotes/origin/main', 'HEAD')

  const REVERTED = 'lane/zz-where-reverted'
  cg('checkout', '-q', '-b', REVERTED)
  cput('scripts/reverted.mjs', `export const ${PROBE} = 1\nexport const zzCensusEdit = 1\n`)
  cg('add', '-A'); cg('commit', '-q', '-m', 'touch the file')
  cput('scripts/reverted.mjs', `export const ${PROBE} = 1\n`)          // main's bytes, exactly
  cg('add', '-A'); cg('commit', '-q', '-m', "put main's bytes back")

  const GENUINE = 'lane/zz-where-genuine'
  cg('checkout', '-q', 'main'); cg('checkout', '-q', '-b', GENUINE)
  cput('scripts/carrier.mjs', `export const zzCensusCarrier = 1\nexport const ${PROBE} = 3\n`)
  cput('scripts/added.mjs', `export const ${PROBE} = 4\n`)
  cg('add', '-A'); cg('commit', '-q', '-m', 'genuinely add the symbol')
  cg('checkout', '-q', 'main')

  check('(f) fixture: main itself carries the probe in two files',
    filesWith('main', PROBE, cOpts).slice().sort().join(',') === 'scripts/reverted.mjs,scripts/untouched.mjs')
  check('(f) fixture: the revert branch is 2 commits ahead of origin/main (the census counts it LIVE)',
    cg('rev-list', '--count', `origin/main..${REVERTED}`) === '2')
  check("(f) fixture: and its tree is byte-identical to main (the test's own diff)",
    changedPaths('main', REVERTED, cOpts).length === 0)
  check('(f) fixture: a plain grep of that branch DOES hit the file, so the census sees it',
    filesWith(REVERTED, PROBE, cOpts).includes('scripts/reverted.mjs'))
  check('(f) fixture: the other branch genuinely changes content',
    changedPaths('main', GENUINE, cOpts).slice().sort().join(',') === 'scripts/added.mjs,scripts/carrier.mjs')

  const rf = runWhere(crepo, [PROBE, '--branches'])
  const fNot = section(rf.out, 'NOT ON MAIN')
  const fAll = fNot ? fNot.all : ''
  check('(f) a NOT ON MAIN section is printed', !!fNot, rf.out.split('\n').filter(Boolean).slice(-6).join(' / '))
  check("(f) a file the branch reverted to main's bytes is NOT listed as unlanded", !!fNot && !fAll.includes('scripts/reverted.mjs'), fAll.slice(0, 300))
  check('(f) a file no branch ever touched is NOT listed as unlanded', !!fNot && !fAll.includes('scripts/untouched.mjs'), fAll.slice(0, 300))
  check('(f) a genuinely CHANGED file is still listed (the fix must not empty the census)', fAll.includes('scripts/carrier.mjs'), fAll.slice(0, 300))
  check('(f) a file the branch ADDED is still listed', fAll.includes('scripts/added.mjs'), fAll.slice(0, 300))
  check('(f) the drop is REPORTED — a count, the branch, and why',
    /\b[1-9]\d* file\(s\) on \S+ are byte-identical to main and were not listed\b/.test(fAll) && fAll.includes(REVERTED), fAll.slice(0, 300))
  check('(f) the run exits 0 — the symbol was found', rf.code === 0, `exit ${rf.code}`)

  // (f2) THE PRINTED COUNTS ARE GRADED BY VALUE: a number nobody grades is ink.
  const fExp = expectCounts(cOpts, 'main', [REVERTED, GENUINE], PROBE)
  check('(f2) fixture: the test itself expects 2 kept, 4 identical, 0 stale here',
    fExp.kept === 2 && fExp.identical === 4 && fExp.stale === 0, `kept ${fExp.kept} identical ${fExp.identical} stale ${fExp.stale}`)
  check('(f2) the NOT ON MAIN heading prints the kept count the test derived',
    !!fNot && new RegExp(`\\(${fExp.kept} hit\\(s\\)`).test(fNot.head), `${fNot ? fNot.head : '(none)'} (expected ${fExp.kept})`)
  for (const [b, c] of fExp.per) {
    if (!c.identical.length) continue
    check(`(f2) the per-branch drop count for ${b} is ${c.identical.length}, by value`,
      fAll.includes(`  ${c.identical.length} file(s) on ${b} are byte-identical to main and were not listed`), fAll.slice(0, 300))
  }
  check("(f2) and the total dropped equals the test's own total", fAll.includes(`(${fExp.identical} in all:`), fAll.slice(0, 300))

  // ---- (g) DROPPED IS NOT "DOES NOT EXIST" ------------------------------------------
  // With ORG_SEARCH_PATHS narrowed, a name living only outside those paths is seen by the
  // census alone; dropping its hits must not print "this does not exist yet".
  const VPROBE = `zzVaultOnlyProbe${process.pid}`
  const { dir: vrepo, g: vg, put: vput, opts: vOpts } = scratchRepo('vault-repo', 'main')
  vput('vault/Note.md', `a note naming ${VPROBE} and nothing else\n`)
  vput('scripts/unrelated.mjs', 'export const zzVaultUnrelated = 1\n')
  vg('add', '-A'); vg('commit', '-q', '-m', 'base')
  vg('update-ref', 'refs/remotes/origin/main', 'HEAD')
  const VBRANCH = 'lane/zz-where-vault'
  vg('checkout', '-q', '-b', VBRANCH)
  vput('vault/Note.md', `a note naming ${VPROBE} and an edit\n`)
  vg('add', '-A'); vg('commit', '-q', '-m', 'touch the note')
  vput('vault/Note.md', `a note naming ${VPROBE} and nothing else\n`)
  vg('add', '-A'); vg('commit', '-q', '-m', "put main's bytes back")
  vg('checkout', '-q', 'main')
  check('(g) fixture: the probe is on main, OUTSIDE the searched path (scripts)',
    filesWith('main', VPROBE, vOpts).includes('vault/Note.md') && filesWith('main', VPROBE, vOpts, ['scripts']).length === 0)
  const rg = runWhere(vrepo, [VPROBE, '--branches'], { ORG_SEARCH_PATHS: 'scripts' })
  check('(g) dropping every hit must NOT become "this does not exist yet" — exit 0, no such claim',
    rg.code === 0 && !/does not exist yet/.test(rg.out), `exit ${rg.code}: ${rg.out.split('\n').filter(Boolean).slice(-4).join(' / ')}`)
  check('(g) and the run SAYS the matches are byte-identical to main', /byte-identical to main/.test(rg.out))
  check('(g) and tells the reader WHERE it is — outside the searched paths, named',
    /outside the searched paths \(scripts\)/.test(rg.out), rg.out.split('\n').filter(Boolean).slice(-6).join(' / '))

  // ---- (h) WHICH REF THE FILTER DIFFS AGAINST, AND THE MERGE-BASE ---------------------
  // main, origin/main and HEAD are three DIFFERENT commits and the answer depends on each:
  //   main        = base + one commit main made after the branches were cut
  //   origin/main = the branch point
  //   HEAD        = lane/zz-baseref-b1, one of the two live branches
  const HPROBE = `zzBaseRefProbe${process.pid}`
  const { dir: hrepo, g: hg, put: hput, opts: hOpts } = scratchRepo('baseref-repo', 'main')
  hput('scripts/landed.mjs', `export const ${HPROBE} = 'v1'\n`)
  hput('scripts/twin.mjs', `export const ${HPROBE} = 'v1'\n`)
  hput('scripts/mainmoved.mjs', `export const ${HPROBE} = 'v1'\n`)
  hput('scripts/quiet.mjs', `export const ${HPROBE} = 'v1'\n`)
  hg('add', '-A'); hg('commit', '-q', '-m', 'base — the branch point')
  const HBASE = hg('rev-parse', 'HEAD')
  hg('update-ref', 'refs/remotes/origin/main', HBASE)
  hput('scripts/landed.mjs', `export const ${HPROBE} = 'v2'\n`)
  hput('scripts/mainmoved.mjs', `export const ${HPROBE} = 'v2-main-only'\n`)
  hg('add', '-A'); hg('commit', '-q', '-m', 'main moves: takes the landed work, and edits a file alone')
  const B1 = 'lane/zz-baseref-b1', B2 = 'lane/zz-baseref-b2'
  hg('checkout', '-q', '-b', B1, HBASE)
  hput('scripts/landed.mjs', `export const ${HPROBE} = 'v2'\n`)
  hput('scripts/twin.mjs', `export const ${HPROBE} = 'v9'\n`)
  hg('add', '-A'); hg('commit', '-q', '-m', 'b1: the landed edit, and the twin edit')
  hg('checkout', '-q', '-b', B2, HBASE)
  hput('scripts/twin.mjs', `export const ${HPROBE} = 'v9'\n`)
  hput('scripts/own.mjs', `export const ${HPROBE} = 'b2 only'\n`)
  hg('add', '-A'); hg('commit', '-q', '-m', 'b2: the same twin edit, and a file of its own')
  hg('checkout', '-q', B1)

  check('(h) fixture: main, origin/main and HEAD are THREE different commits',
    new Set([hg('rev-parse', 'main'), hg('rev-parse', 'origin/main'), hg('rev-parse', 'HEAD')]).size === 3)
  check("(h) fixture: b1's landed.mjs is byte-identical to MAIN's (the work landed)",
    hg('rev-parse', `${B1}:scripts/landed.mjs`) === hg('rev-parse', 'main:scripts/landed.mjs'))
  check('(h) fixture: mainmoved.mjs differs from main ONLY because main moved',
    hg('rev-parse', `${B1}:scripts/mainmoved.mjs`) === hg('rev-parse', `${HBASE}:scripts/mainmoved.mjs`) &&
      hg('rev-parse', `${B1}:scripts/mainmoved.mjs`) !== hg('rev-parse', 'main:scripts/mainmoved.mjs'))

  const rh = runWhere(hrepo, [HPROBE, '--branches'])
  const hNot = section(rh.out, 'NOT ON MAIN')
  const hAll = hNot ? hNot.all : ''
  check('(h) a file whose change ALREADY LANDED on main is not listed as unlanded work', !!hNot && !hAll.includes(`${B1}:scripts/landed.mjs`), hAll.slice(0, 400))
  check('(h) a genuinely changed file is listed for BOTH branches — the base is main, not HEAD',
    hAll.includes(`${B1}:scripts/twin.mjs`) && hAll.includes(`${B2}:scripts/twin.mjs`), hAll.slice(0, 400))
  check('(h) a file that differs from main only because MAIN MOVED is not listed', !!hNot && !hAll.includes('scripts/mainmoved.mjs'), hAll.slice(0, 400))
  check('(h) anti-vacuity: a file the branch itself added IS still listed', hAll.includes(`${B2}:scripts/own.mjs`), hAll.slice(0, 400))
  const hExp = expectCounts(hOpts, 'main', [B1, B2], HPROBE)
  check('(h) fixture: the test itself expects 3 kept, 3 identical, 3 stale',
    hExp.kept === 3 && hExp.identical === 3 && hExp.stale === 3, `kept ${hExp.kept} identical ${hExp.identical} stale ${hExp.stale}`)
  check("(h) the kept count printed equals the test's own", !!hNot && new RegExp(`\\(${hExp.kept} hit\\(s\\)`).test(hNot.head), hNot ? hNot.head : '(none)')
  check("(h) the BYTE-IDENTICAL total printed equals the test's own", hAll.includes(`(${hExp.identical} in all:`), hAll.slice(0, 400))
  check("(h) the STALE-MAIN-BYTES total printed equals the test's own, reported separately",
    new RegExp(`\\b${hExp.stale} file\\(s\\) in all .*main moved`).test(hAll), hAll.slice(0, 400))
  check('(h) the run exits 0', rh.code === 0, `exit ${rh.code}`)
} finally {
  try { fs.rmSync(tmpRoot, { recursive: true, force: true }) } catch (e) { console.log(`  (cleanup) ${e.message}`) }
}

if (checksRun === 0) {
  console.log('\nREFUSED  where.test — zero checks ran, so `failed === 0` proves nothing.')
  process.exit(2)
}
console.log(failed === 0 ? `\nPASS  where — ${checksRun} checks, all green` : `\nFAIL  where — ${failed} of ${checksRun} failing`)
process.exit(failed === 0 ? 0 : 1)
