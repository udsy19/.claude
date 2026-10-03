#!/usr/bin/env node
/**
 * The proposal channel under concurrency.
 *
 * WHY THIS EXISTS. Measured: eight supervisor `--resolve` calls interleaved
 * with eight subagent filings LOST FOUR PROPOSALS AND THREE VERDICTS, silently and with no
 * corruption to notice. `--resolve` rewrites the whole file, so any append between its read
 * and its write is erased — and what is erased is a subagent's finding, which is the only
 * thing this channel carries. A second, smaller loss (1 of 28) survived locking the rewrite
 * alone, because an append can still land between the locked read and the rename.
 *
 * Both are now standing cases. A race that is fixed but untested is a race.
 */
import { execFileSync } from 'node:child_process'
import { noGitEnv } from './lib/git-env.mjs'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')

// This suite takes no arguments, and refuses one by name like every entry point here.
if (process.argv.length > 2) {
  console.log(`propose.test: unrecognised argument '${process.argv[2]}' — accepts: (none)`)
  process.exit(2)
}
const CLI = path.join(ROOT, 'scripts/propose.mjs')
let failed = 0
let checksRun = 0
const check = (name, cond, detail = '') => { checksRun++;
  if (cond) console.log(`  ok   ${name}`)
  else { failed++; console.log(`  FAIL ${name}${detail ? ' — ' + detail : ''}`) }
}
const dir = () => fs.mkdtempSync(path.join(os.tmpdir(), 'org-propose-'))
// The suite runs as a SUBAGENT unless a case says otherwise: an operator's own ORG_ROLE
// must not turn "a subagent may not rule" green for the wrong reason.
const BASE_ENV = { ...process.env }
delete BASE_ENV.ORG_ROLE
const runSync = (args, d, env = {}) => {
  try { return { code: 0, out: execFileSync('node', [CLI, ...args], { env: { ...BASE_ENV, ORG_PROPOSALS_DIR: d, ...env }, encoding: 'utf8', stdio: ['ignore','pipe','pipe'] }) } }
  catch (e) { return { code: e.status ?? 1, out: (e.stdout || '').toString() } }
}
const rowsOf = (d) => {
  const p = path.join(d, 'proposals.jsonl')
  if (!fs.existsSync(p)) return { rows: [], corrupt: 0 }
  let corrupt = 0
  const rows = fs.readFileSync(p, 'utf8').split('\n').filter(Boolean).flatMap((l) => {
    try { return [JSON.parse(l)] } catch { corrupt++; return [] }
  })
  return { rows, corrupt }
}

// ---- (a) the contract ------------------------------------------------------
{
  const d = dir()
  check('(a) a challenge with no number is refused',
    runSync(['--row','1','--kind','challenge','--why','the approach here is simply wrong and I am sure of it'], d).code === 2)
  check('(a) a challenge WITH a number is accepted',
    runSync(['--row','1','--kind','challenge','--why','packing yields 57 desks against 72 promised'], d).code === 0)
  check('(a) a subagent may not rule',
    runSync(['--resolve','1','--verdict','accept','--because','because I am confident about this'], d).code === 2)
  check('(a) a verdict with no reason is refused',
    runSync(['--resolve','1','--verdict','accept','--because','ok'], d, { ORG_ROLE: 'supervisor' }).code === 2)
  check('(a) the supervisor may rule',
    runSync(['--resolve','1','--verdict','accept','--because','measured: the count is 57 not 72'], d, { ORG_ROLE: 'supervisor' }).code === 0)
  check('(a) an unknown flag is refused by name', runSync(['--bogus'], d).code === 2)
}

// ---- (b) THE RACE, run several times because a race that passes once proves nothing ----
{
  const SEED = 20, PAIRS = 8, ROUNDS = 3
  let worst = null
  for (let r = 0; r < ROUNDS; r++) {
    const d = dir()
    for (let i = 1; i <= SEED; i++) runSync(['--row', String(i), '--kind', 'add', '--why', `seed ${i} with sufficient characters here`], d)
    // spawn both families truly concurrently
    const { spawn } = await import('node:child_process')
    const procs = []
    for (let i = 1; i <= PAIRS; i++) {
      procs.push(new Promise((res) => spawn('node', [CLI, '--resolve', String(i), '--verdict', 'accept', '--because', `verdict ${i} long enough to clear the floor`],
        { env: { ...BASE_ENV, ORG_PROPOSALS_DIR: d, ORG_ROLE: 'supervisor' }, stdio: 'ignore' }).on('exit', res)))
      procs.push(new Promise((res) => spawn('node', [CLI, '--row', `9${i}`, '--kind', 'add', '--why', `a subagent files while the supervisor resolves, run ${i}`],
        { env: { ...BASE_ENV, ORG_PROPOSALS_DIR: d }, stdio: 'ignore' }).on('exit', res)))
    }
    await Promise.all(procs)
    const { rows, corrupt } = rowsOf(d)
    const verdicts = rows.filter((x) => x.verdict).length
    const bad = rows.length !== SEED + PAIRS || corrupt !== 0 || verdicts !== PAIRS
    if (bad) worst = `round ${r + 1}: ${rows.length}/${SEED + PAIRS} rows, ${corrupt} corrupt, ${verdicts}/${PAIRS} verdicts`
  }
  check(`(b) ${ROUNDS} rounds of ${PAIRS} resolves interleaved with ${PAIRS} filings lose NOTHING`, worst === null, worst || '')
}

// ---- (c) the lock does not wedge -------------------------------------------
{
  const d = dir()
  runSync(['--row','1','--kind','add','--why','a seed row with sufficient characters here'], d)
  fs.writeFileSync(path.join(d, 'proposals.jsonl.lock'), '999999')
  const old = Date.now() - 60_000
  fs.utimesSync(path.join(d, 'proposals.jsonl.lock'), old / 1000, old / 1000)
  const r = runSync(['--row','2','--kind','add','--why','a stale lock must be broken, not waited on forever'], d)
  check('(c) a STALE lock is broken rather than wedging the channel', r.code === 0, `exit ${r.code}`)
  check('(c) and it is cleaned up', !fs.existsSync(path.join(d, 'proposals.jsonl.lock')))
}

// ---- (d) THE CHANNEL MUST CROSS A WORKTREE -------------------------------
// Every subagent works in a linked worktree, so this is not an edge case, it is the ONLY
// case that matters for the population this channel serves. An earlier propose.mjs
// resolved its log to `CLAUDE_PROJECT_DIR || <its own ../>`, both of which are the WORKTREE
// under a subagent, and the main checkout's `--list` read "0 open" while three proposals
// sat unread. Silence on this channel is indistinguishable from nothing-filed.
//
// NOTE WHAT THIS CASE DELIBERATELY DOES NOT DO: it does not set ORG_PROPOSALS_DIR. Every
// other case above does, which is right for testing the LOCK and the VERDICTS and is
// exactly why none of them could ever have caught this — the override bypasses the
// resolution under test. A test that isolates the subject can isolate away the defect.
{
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'org-propose-wt-'))
  const main = path.join(root, 'main')
  // GIT WITH THE REPO YOU NAMED. `cwd` does NOT override GIT_DIR / GIT_INDEX_FILE /
  // GIT_WORK_TREE, and git exports all three into every hook — so run from a pre-commit hook
  // these calls would operate on the COMMITTING repo's index. scripts/lib/git-env.mjs is the
  // single owner of the scrub.
  const NO_GIT_ENV = noGitEnv()
  const git = (cwd, ...a) => execFileSync('git', a, { cwd, env: NO_GIT_ENV, encoding: 'utf8', stdio: ['ignore','pipe','pipe'] })
  fs.mkdirSync(path.join(main, 'scripts'), { recursive: true })
  fs.copyFileSync(CLI, path.join(main, 'scripts', 'propose.mjs'))
  git(main, 'init', '-q', '-b', 'main')
  git(main, 'config', 'user.email', 't@t'); git(main, 'config', 'user.name', 't')
  git(main, 'add', '-A'); git(main, 'commit', '-qm', 'seed')
  const wt = path.join(root, 'wt')
  git(main, 'worktree', 'add', '-q', '--detach', wt, 'HEAD')

  // File from INSIDE the worktree, with CLAUDE_PROJECT_DIR pointing at the worktree —
  // which is what a subagent's environment actually looks like.
  const env = { ...NO_GIT_ENV, CLAUDE_PROJECT_DIR: wt }
  delete env.ORG_PROPOSALS_DIR
  let code = 0
  try {
    execFileSync('node', [path.join(wt, 'scripts', 'propose.mjs'), '--row', '9', '--kind', 'add',
      '--why', 'filed from a linked worktree and it must reach the main checkout'],
      { cwd: wt, env, encoding: 'utf8', stdio: ['ignore','pipe','pipe'] })
  } catch (e) { code = e.status ?? 1 }

  const mainLog = path.join(main, 'vault/_log/proposals.jsonl')
  const wtLog = path.join(wt, 'vault/_log/proposals.jsonl')
  check('(d) filing from a linked worktree SUCCEEDS', code === 0, `exit ${code}`)
  check('(d) and the entry lands in the MAIN checkout', fs.existsSync(mainLog) &&
    fs.readFileSync(mainLog, 'utf8').includes('filed from a linked worktree'),
    fs.existsSync(mainLog) ? 'main log exists but lacks the entry' : 'no main log at all')
  check('(d) and NOT in the worktree, where nobody reads it', !fs.existsSync(wtLog),
    fs.existsSync(wtLog) ? 'a log was written inside the worktree' : '')

  // THE POSITIVE CONTROL. The two assertions above are about WHERE a file went, and a
  // resolution bug that wrote nowhere at all would satisfy the third one for free. Read it
  // back the way the supervisor does — through --list, from the MAIN checkout — because
  // that is the act the channel exists to make work.
  let listed = ''
  try {
    listed = execFileSync('node', [path.join(main, 'scripts', 'propose.mjs'), '--list'],
      { cwd: main, env: { ...env, CLAUDE_PROJECT_DIR: main }, encoding: 'utf8', stdio: ['ignore','pipe','pipe'] })
  } catch (e) { listed = String(e.stdout || '') }
  check('(d) and the supervisor SEES it from the main checkout',
    listed.includes('filed from a linked worktree'), listed.split('\n')[0] || '(no output)')

  fs.rmSync(root, { recursive: true, force: true })
}

// A COUNT, NOT JUST AN ABSENCE OF FAILURES. This printed "all checks green" off
// `failed === 0` alone, so a run in which NO check executed read as success — the F73/F74
// class in this suite's own verdict line. The count is now reported and zero REFUSES.
if (checksRun === 0) {
  console.log('\\nREFUSED  propose — zero checks ran, so `failed === 0` proves nothing.')
  process.exit(2)
}
console.log(failed === 0 ? `\nPASS  propose — ${checksRun} checks, all green` : `\nFAIL  propose — ${failed} failing`)
process.exit(failed === 0 ? 0 : 1)
