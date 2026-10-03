#!/usr/bin/env node
// Falsification suite for the contract hook. It gates every write the fleet makes, so
// each branch is exercised — including the ones that must FAIL OPEN, because a hook that
// wedges on its own bug is worse than the rule it enforces.
import { execFileSync } from 'node:child_process'
import path from 'node:path'
import fs from 'node:fs'
import os from 'node:os'
import { fileURLToPath } from 'node:url'

if (process.argv.length > 2) {
  console.log(`agent-contract.test: unrecognised argument '${process.argv[2]}' — accepts: (none)`)
  process.exit(2)
}

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..')
const HOOK = path.join(ROOT, 'scripts/hooks/agent-contract.mjs')
let failed = 0
let checksRun = 0
const check = (name, cond, detail = '') => { checksRun++
  if (cond) console.log(`  ok   ${name}`)
  else { failed++; console.log(`  FAIL ${name}${detail ? ' — ' + detail : ''}`) }
}
// ISOLATE the marker store. A suite that deletes the SHARED marker directory interrupts
// every live agent session on its next write. A test must not mutate the thing it shares
// with production (.claude/rules/gate-independence.md, "falsify against a disposable
// copy"), so every run() points the hook at a private TMPDIR.
const MARKERS = fs.mkdtempSync(path.join(os.tmpdir(), 'org-contract-test-'))
process.on('exit', () => { try { fs.rmSync(MARKERS, { recursive: true, force: true }) } catch {} })
const BASE_ENV = { ...process.env }
delete BASE_ENV.ORG_ROLE   // the suite runs as a subagent unless a case says otherwise
delete BASE_ENV.AGENT_NAME; delete BASE_ENV.AGENT_ORG_HEADLESS   // ...and as an interactive one
function run(payload, env = {}) {
  try {
    const out = execFileSync('node', [HOOK], {
      input: typeof payload === 'string' ? payload : JSON.stringify(payload),
      env: { ...BASE_ENV, CLAUDE_PROJECT_DIR: ROOT, TMPDIR: MARKERS, ...env }, encoding: 'utf8', stdio: ['pipe', 'pipe', 'pipe'],
    })
    return { code: 0, out, err: '' }
  } catch (e) { return { code: e.status ?? 1, out: (e.stdout || '').toString(), err: (e.stderr || '').toString() } }
}
const sid = () => 's' + Math.random().toString(36).slice(2)
const edit = (f, s) => ({ session_id: s, tool_name: 'Edit', tool_input: { file_path: path.join(ROOT, f) } })
const ORDINARY = 'src/zz-ordinary-file.js'

// (a) ownership
for (const p of ['vault/Plan.md', 'vault/Roadmap.md', 'vault/Decisions/0001-any.md', '.claude/rules/gate-independence.md',
  '.claude/settings.json']) {
  const r = run(edit(p, sid()))
  check(`(a) a subagent editing ${p} is REFUSED`, r.code === 2 && /REFUSED/.test(r.err), `exit ${r.code}`)
  check('(a) ... and is told how to propose instead', /propose\.mjs/.test(r.err))
}
const sup = run(edit('vault/Plan.md', sid()), { ORG_ROLE: 'supervisor' })
check('(a) the SUPERVISOR may edit the plan (contract still delivered once)', sup.code === 2 && !/REFUSED/.test(sup.err), `exit ${sup.code}`)
run(edit('vault/Plan.md', 'supersession'), { ORG_ROLE: 'supervisor' })
const sup3 = run(edit('vault/Plan.md', 'supersession'), { ORG_ROLE: 'supervisor' })
check('(a) ... and after that is not blocked at all', sup3.code === 0, `exit ${sup3.code}`)
const own = sid(); run(edit(ORDINARY, own), { ORG_ROLE: 'owner' })
check('(a) settings.local.json is NOT protected (it is per-machine, untracked)', (() => {
  const s = sid(); run(edit(ORDINARY, s)); return run(edit('.claude/settings.local.json', s)).code === 0
})())
check('(a) the OWNER may edit a decision', run(edit('vault/Decisions/0001-any.md', own), { ORG_ROLE: 'owner' }).code === 0)
check('(a) a subagent writing vault/Reports/ is ALLOWED (after delivery)', (() => {
  const s = sid(); run(edit(ORDINARY, s)); return run(edit('vault/Reports/some-report.md', s)).code === 0
})())

// (b) the contract is delivered exactly once per session
const s = sid()
const first = run(edit(ORDINARY, s))
check('(b) the FIRST write is interrupted', first.code === 2, `exit ${first.code}`)
check('(b) ... and the refusal carries the contract itself', /AGENTS — read this before you touch anything/.test(first.err))
check('(b) ... including the routing table', /Map-code/.test(first.err) && /Index/.test(first.err))
const second = run(edit(ORDINARY, s))
check('(b) the SECOND write in the same session passes', second.code === 0, `exit ${second.code}`)
check('(b) a DIFFERENT session is interrupted again', run(edit(ORDINARY, sid())).code === 2)

// (c) scope — it gates writes, nothing else
check('(c) Read is never gated', run({ session_id: sid(), tool_name: 'Read', tool_input: { file_path: path.join(ROOT, 'vault/Plan.md') } }).code === 0)
check('(c) Bash is never gated', run({ session_id: sid(), tool_name: 'Bash', tool_input: { command: 'echo hi' } }).code === 0)

// (e) ADVERSARIAL — every one of these reached the plan in the project this came from.
// They are standing cases because each was found by attacking the hook, not reading it.
{
  const prot = path.join(ROOT, 'vault/Plan.md')
  const wt = '/tmp/org-other-checkout'
  const served = (id) => { run(edit(ORDINARY, id)); return id }   // consume the contract
  const owned = (target, env) => {
    const id = served(sid())
    const r = run({ session_id: id, tool_name: 'Edit', tool_input: { file_path: target } }, env)
    return r.code === 2 && /REFUSED/.test(r.err)
  }
  check('(e) vault/plan.md is refused (case-insensitive bypass)', owned(path.join(ROOT, 'vault/plan.md')))
  check('(e) vault/PLAN.md is refused', owned(path.join(ROOT, 'vault/PLAN.md')))
  check('(e) vault/Decisions/ matches case-insensitively', owned(path.join(ROOT, 'VAULT/decisions/x.md')))
  check("(e) another checkout's plan is refused (cross-tree)", owned(`${wt}/vault/Plan.md`))
  check("(e) another checkout's rules file is refused", owned(`${wt}/.claude/rules/gate-independence.md`))
  check('(e) a/../a is refused', owned(path.join(ROOT, 'vault/../vault/Plan.md')))
  check('(e) a//b is refused', owned(ROOT + '/vault//Plan.md'))
  check('(e) a relative path is refused', owned('vault/Plan.md'))
  check('(e) an ordinary source file is still allowed', !owned(path.join(ROOT, ORDINARY)))
  check('(e) an unrelated /tmp file is still allowed', !owned('/tmp/org-scratch-xyz.txt'))
  // MALFORMED PAYLOADS must not crash the hook — an uncaught throw exits 1, which a
  // PreToolUse hook treats as non-blocking, i.e. the write PROCEEDS.
  for (const [name, fp] of [['array', [prot]], ['number', 42], ['object', { p: prot }], ['null', null]]) {
    const r = run({ session_id: sid(), tool_name: 'Edit', tool_input: { file_path: fp } })
    check(`(e) file_path=${name} does not crash the hook`, r.code === 0 || r.code === 2, `exit ${r.code}`)
  }
  check('(e) ORG_ROLE=" supervisor " is honoured', !owned(prot, { ORG_ROLE: ' supervisor ' }))
  check('(e) ORG_ROLE="superviso" does NOT grant authority', owned(prot, { ORG_ROLE: 'superviso' }))
  check('(e) ORG_ROLE="" does NOT grant authority', owned(prot, { ORG_ROLE: '' }))
}

// (d) FAIL OPEN — a broken hook must not wedge the fleet
check('(d) malformed JSON fails OPEN', run('not json at all').code === 0)
check('(d) empty stdin fails OPEN', run('').code === 0)
check('(d) a payload with no tool_name fails OPEN', run({ session_id: sid() }).code === 0)
// An UNWRITABLE marker directory: a delivery that cannot be recorded must not be repeated
// forever. (chmod cannot deny root, so as root this row cannot construct its subject.)
{
  const RO = fs.mkdtempSync(path.join(os.tmpdir(), 'org-contract-ro-'))
  const DENIED = path.join(RO, `org-agent-contract-${process.getuid ? process.getuid() : 'u'}`)
  fs.mkdirSync(DENIED)
  fs.chmodSync(DENIED, 0o555)
  const w = { session_id: sid(), tool_name: 'Write', tool_input: { file_path: path.join(ROOT, ORDINARY) } }
  if (process.getuid && process.getuid() === 0) check('(d) an unwritable marker dir — UNMEASURABLE as root', false, 'run as a non-root user')
  else {
    const a = run(w, { TMPDIR: RO }), b = run(w, { TMPDIR: RO }), c = run(w, { TMPDIR: RO })
    check('(d) an unwritable marker dir never blocks the same session three times running', [a, b, c].filter((r) => r.code === 2).length === 0, `exits ${a.code},${b.code},${c.code}`)
  }
  fs.chmodSync(DENIED, 0o755); fs.rmSync(RO, { recursive: true, force: true })
}

// (f) IS THE GUARD ACTUALLY INSTALLED? Every case above tests the SCRIPT; none notices if it
// is no longer WIRED. A deleted or broken hook exits 1, which is non-blocking, so the write
// proceeds and enforcement vanishes with no symptom. Its presence is checked, not assumed.
{
  const settingsPath = path.join(ROOT, '.claude/settings.json')
  check('(f) .claude/settings.json exists', fs.existsSync(settingsPath))
  let cfg = {}
  try { cfg = JSON.parse(fs.readFileSync(settingsPath, 'utf8')) } catch { /* stays empty */ }
  let wired = false, matcher = ''
  for (const e of (cfg.hooks?.PreToolUse ?? [])) {
    for (const h of (e.hooks ?? [])) {
      if (String(h.command || '').includes('agent-contract.mjs')) { wired = true; matcher = e.matcher || '' }
    }
  }
  check('(f) the hook is WIRED as a PreToolUse hook', wired)
  for (const t of ['Edit', 'Write', 'MultiEdit', 'NotebookEdit']) {
    check(`(f) ... and its matcher covers ${t}`, new RegExp(`\\b${t}\\b`).test(matcher), matcher)
  }
  check('(f) the hook FILE exists at the wired path', fs.existsSync(HOOK))
  const s2 = sid(); run(edit(ORDINARY, s2))
  const live = run(edit('vault/Plan.md', s2))
  check('(f) the installed hook REFUSES a protected path right now', live.code === 2 && /REFUSED/.test(live.err), `exit ${live.code}`)
  const ssWired = (cfg.hooks?.SessionStart ?? []).some((e) => (e.hooks ?? []).some((h) => String(h.command || '').includes('AGENTS.md')))
  check('(f) SessionStart also delivers vault/AGENTS.md', ssWired)
  check('(f) vault/AGENTS.md exists to be delivered', fs.existsSync(path.join(ROOT, 'vault/AGENTS.md')))
}

// (g) THE CONTRACT MUST REACH A SUBAGENT THAT NEVER WRITES. SessionStart does not fire for
// a subagent, and a read-only role has no Edit tool at all — so BOTH delivery paths miss
// it. A pointer is not a delivery: the load-bearing lines are inlined in every role card,
// which IS in the subagent's prompt, and this holds them there.
{
  const dir = path.join(ROOT, '.claude/agents')
  const cards = fs.existsSync(dir) ? fs.readdirSync(dir).filter((f) => f.endsWith('.md')) : []
  check('(g) role cards exist to carry the contract', cards.length > 0)
  const need = [
    ['the proposal channel', /scripts\/propose\.mjs/],
    ['the write ban', /vault\/Plan\.md/],
    ['where the code is', /vault\/Map-code\.md/],
    ['what was already tried', /vault\/Index\.md/],
    ['the one-row reader', /scripts\/plan-row\.mjs/],
    ['who already implements X', /scripts\/where\.mjs/],
  ]
  for (const card of cards) {
    const txt = fs.readFileSync(path.join(dir, card), 'utf8')
    for (const [what, re] of need) check(`(g) ${card} names ${what}`, re.test(txt))
  }
}

// (h) A NON-STRING file_path IS NOT A BYPASS — measured with the delivery marker already
// spent, because the FIRST write of a session is refused anyway and that exit 2 is easily
// mistaken for protection. The last row is the guard that matters: the scan must not
// wedge an ordinary edit whose CONTENT names a protected path.
{
  const secondWrite = (payload) => { const s2 = sid(); run({ ...payload, session_id: s2 }); return run({ ...payload, session_id: s2 }) }
  const shaped = (fp) => ({ session_id: sid(), tool_name: 'Edit', tool_input: { file_path: fp } })
  const PLAN = path.join(ROOT, 'vault/Plan.md')
  check('(h) CONTROL — a plain string protected path is refused on the second write', secondWrite(shaped(PLAN)).code === 2)
  check('(h) file_path as an ARRAY is still refused', secondWrite(shaped([PLAN])).code === 2)
  check('(h) file_path as an OBJECT is still refused', secondWrite(shaped({ 0: PLAN })).code === 2)
  check('(h) ...and an ORDINARY edit whose CONTENT names a protected path is ALLOWED',
    secondWrite({ session_id: sid(), tool_name: 'Edit',
      tool_input: { file_path: path.join(ROOT, ORDINARY), new_string: `// see ${PLAN} for the queue` } }).code === 0,
    'the scan must not wedge ordinary work')
}

// (i) THE GATE HOLDS THE DOCUMENTS TO THE DECLARATION. Run against this tree it passes;
// run against a scratch copy whose contract drops one protected path it must FAIL, or the
// gate would be passing because it checks nothing.
{
  const gate = (root) => { try { execFileSync('node', [path.join(root, 'scripts/gates/protected-paths.mjs')], { encoding: 'utf8', stdio: 'pipe' }); return 0 } catch (e) { return e.status ?? 1 } }
  // only an INSTALLED tree has .claude/rules/; the kit stores it as rules.tmpl/ (see init-repo.mjs)
  if (fs.existsSync(path.join(ROOT, '.claude/rules/protected-paths.md'))) check('(i) the protected-paths gate passes on this tree', gate(ROOT) === 0)
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'org-pp-gate-'))
  try {
    for (const rel of ['scripts/gates/protected-paths.mjs', 'scripts/lib/protected-paths.mjs', 'scripts/hooks/agent-contract.mjs',
      'scripts/gates/plan-ownership.mjs', 'vault/AGENTS.md', 'vault/SUPERVISOR.md', 'vault/CLAUDE.md']) {
      fs.mkdirSync(path.dirname(path.join(tmp, rel)), { recursive: true }); fs.copyFileSync(path.join(ROOT, rel), path.join(tmp, rel))
    }
    const rules = fs.existsSync(path.join(ROOT, '.claude/rules/protected-paths.md')) ? '.claude/rules' : '.claude/rules.tmpl'
    fs.mkdirSync(path.join(tmp, '.claude/rules'), { recursive: true })
    fs.copyFileSync(path.join(ROOT, rules, 'protected-paths.md'), path.join(tmp, '.claude/rules/protected-paths.md'))
    check('(i) CONTROL — the scratch copy passes before it is broken', gate(tmp) === 0)
    const agents = path.join(tmp, 'vault/AGENTS.md')
    fs.writeFileSync(agents, fs.readFileSync(agents, 'utf8').replaceAll('.claude/settings.json', '.claude/settings'))
    check('(i) a contract that stops naming .claude/settings.json FAILS the gate', gate(tmp) === 1)
  } finally { fs.rmSync(tmp, { recursive: true, force: true }) }
}

// (j) LANE PROCESSES. supervise.py starts every lane process with AGENT_ORG_HEADLESS=1; workers
// also carry AGENT_NAME. The lane supervisor may write nothing; a worker may not write the
// overseer's trail or any memory. Each refusal has a control: the same write, interactive.
{
  const W = { AGENT_ORG_HEADLESS: '1', AGENT_NAME: 'alpha', ORG_LANE: 'core' }
  const afterDelivery = (p, env) => { const s = sid(); run(edit(ORDINARY, s), env); return run(edit(p, s), env) }
  const LANE_SUP = { AGENT_ORG_HEADLESS: '1', ORG_ROLE: 'supervisor' }
  const supAny = afterDelivery(ORDINARY, LANE_SUP)
  check('(j) the LANE SUPERVISOR is refused even an ordinary file', supAny.code === 2 && /read-only/.test(supAny.err), `exit ${supAny.code}`)
  check('(j) ...and the plan, which ORG_ROLE=supervisor alone would allow', afterDelivery('vault/Plan.md', LANE_SUP).code === 2)
  check('(j) CONTROL — the OVERSEER (same role, interactive) may edit the plan', afterDelivery('vault/Plan.md', { ORG_ROLE: 'supervisor' }).code === 0)
  for (const p of ['vault/Sessions/2026-10-03-x.md', 'vault/Home.md', 'vault/Reports/audits/SESSION-REGISTRY.md',
    '.claude/agent-memory/builder/notes.md', path.join(os.homedir(), '.claude/projects/-srv-repo/memory/feedback.md')]) {
    const r = afterDelivery(p, W)
    check(`(j) a lane WORKER writing ${p.replace(os.homedir(), '~')} is REFUSED`, r.code === 2 && /lane worker does not write/.test(r.err), `exit ${r.code}`)
  }
  check('(j) ...a worker sub-agent (AGENT_NAME inherited, no HEADLESS) too', afterDelivery('vault/Home.md', { AGENT_NAME: 'alpha' }).code === 2)
  check('(j) CONTROL — an interactive session may write its session note', afterDelivery('vault/Sessions/2026-10-03-x.md', {}).code === 0)
  check('(j) CONTROL — a lane worker may write its code and its report', afterDelivery(ORDINARY, W).code === 0 &&
    afterDelivery('vault/Reports/some-report.md', W).code === 0)
  check('(j) CONTROL — a file merely NAMED memory is not memory', afterDelivery('src/memory/cache.js', W).code === 0)
}

// A COUNT, NOT JUST AN ABSENCE OF FAILURES: a run in which no check executed must not read
// as success.
if (checksRun === 0) {
  console.log('\nREFUSED  agent-contract — zero checks ran, so `failed === 0` proves nothing.')
  process.exit(2)
}
console.log(failed === 0 ? `\nPASS  agent-contract — ${checksRun} checks, all green` : `\nFAIL  agent-contract — ${failed} of ${checksRun} failing`)
process.exit(failed === 0 ? 0 : 1)
