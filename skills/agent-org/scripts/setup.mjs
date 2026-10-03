#!/usr/bin/env node
/**
 * setup — the engine behind /setup (commands/setup.md). The command interviews; this installs.
 *
 *   node <KIT>/scripts/setup.mjs --scope base|vault|org [--install global|project] [--project <dir>]
 *                                [--answers <file.json>] [--change] [--bootstrap]
 *   node <KIT>/scripts/setup.mjs --show [--project <dir>]      (remembered answers, as JSON)
 *
 * Tiers (each includes the ones before it):
 *   base   copy this config (skills agents commands hooks rules references + settings.json) into ~/.claude
 *          (--install global) or <project>/.claude (--install project). Never overwrites a file; settings.json
 *          is MERGED (missing permissions and hook commands added, everything of yours kept).
 *   vault  the agent-org repo layer in <project>, via init-repo.mjs. Per project: --install global is refused.
 *   org    the vault with the full interview's vars, plus <ORG_ROOT>/org.json; --bootstrap then runs
 *          bootstrap-host.sh when the org runs on this box (org.host empty), else prints the remote steps.
 *
 * Answers (all optional; a missing one is inferred or defaulted, and remembered):
 *   { "permissions": "default"|"none", "base_install": "global"|"project",
 *     "project": "...", "vision": "...", "main_branch": "...",
 *     "vars": { <init-repo UPPER_SNAKE keys> }, "org_root": "...", "org": { <org.json keys> } }
 * Memory: ~/.claude/setup.json (tiers 1–2) and <ORG_ROOT>/org.json (tier 3). A re-run with the same answers
 * changes nothing. A different answer needs --change; one that cannot be migrated (where the base config
 * lives, a project's name or vision, an org's repo/runtime/worker user/host) is refused with what to do by
 * hand. --change with a new main branch updates org.json, .claude/settings.json and the PR-gate workflow only.
 * It never commits, never pushes, and asks nothing: the /setup command asks, and passes the answers.
 */
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { spawnSync } from 'node:child_process'
import { fileURLToPath } from 'node:url'

const KIT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
const SRC = path.resolve(KIT, '..', '..')                     // the config: skills/agent-org is two levels down
const BASE = ['skills', 'agents', 'commands', 'hooks', 'rules', 'references']
const HOME = os.homedir()
const MEMO = path.join(HOME, '.claude', 'setup.json')
const HAS_PH = /\{\{[A-Z][A-Z0-9_]*\}\}/
const ORG_FIXED = ['repo', 'runtime', 'worker_user', 'host']   // an org already running cannot move these

const die = (m, code = 2) => { console.error(`setup: ${m}`); process.exit(code) }
const say = (m) => console.log(`setup: ${m}`)
const readJSON = (f, dflt) => { try { return JSON.parse(fs.readFileSync(f, 'utf8')) } catch { return dflt } }
const writeJSON = (f, o) => { fs.mkdirSync(path.dirname(f), { recursive: true }); fs.writeFileSync(f, JSON.stringify(o, null, 2) + '\n') }
const git = (dir, ...a) => { const r = spawnSync('git', ['-C', dir, ...a], { encoding: 'utf8' }); return r.status === 0 ? r.stdout.trim() : null }
const tilde = (p) => (p.startsWith('~/') ? path.join(HOME, p.slice(2)) : p)
const same = (a, b) => { try { return fs.realpathSync(a) === fs.realpathSync(b) } catch { return false } }

// ---- arguments ----------------------------------------------------------------------------------
const argv = process.argv.slice(2)
let scope = 'base', install = null, projectArg = process.cwd(), answersFile = null, change = false, bootstrap = false, show = false
for (let i = 0; i < argv.length; i++) {
  const a = argv[i]
  if (a === '--scope') scope = argv[++i]
  else if (a === '--install') install = argv[++i]
  else if (a === '--project') projectArg = argv[++i]
  else if (a === '--answers') answersFile = argv[++i]
  else if (a === '--change') change = true
  else if (a === '--bootstrap') bootstrap = true
  else if (a === '--show') show = true
  else die(`unrecognised argument: ${a}\nsetup: accepts: --scope base|vault|org --install global|project --project <dir> --answers <file.json> --change --bootstrap --show`)
}
if (!['base', 'vault', 'org'].includes(scope)) die(`--scope must be base, vault or org, not '${scope}'`)
if (install && !['global', 'project'].includes(install)) die(`--install must be global or project, not '${install}'`)
const answers = answersFile ? readJSON(answersFile, null) : {}
if (answers === null) die(`--answers ${answersFile}: not readable JSON`)
const memo = readJSON(MEMO, { version: 1, projects: {} })
memo.projects ??= {}
const top = git(path.resolve(projectArg), 'rev-parse', '--show-toplevel')
const project = top ? fs.realpathSync(top) : path.resolve(projectArg)
const remembered = memo.projects[project] ?? {}
const orgRoot = path.resolve(tilde(answers.org_root || remembered.org_root || '~/agent-org'))
const orgFile = path.join(orgRoot, 'org.json')

if (show) {
  console.log(JSON.stringify({ setup: memo, project, remembered, org: readJSON(orgFile, null), org_json: orgFile }, null, 2))
  process.exit(0)
}

// ---- refusals that need no write --------------------------------------------------------------------
if (scope !== 'base') {
  if ((install ?? 'project') === 'global') die('the vault is per project; run `/setup` inside the project')
  if (!top || same(project, HOME)) die(`not a git repository: ${path.resolve(projectArg)} — the vault is per project; run \`git init\` there (or cd into the project), then run \`/setup\` inside the project`)
}
const baseInstall = scope === 'base' ? (install ?? memo.install ?? 'global') : (answers.base_install ?? memo.install ?? 'global')
if (memo.install && memo.install !== baseInstall) {
  const from = memo.install === 'global' ? '~/.claude' : 'each project\'s .claude/'
  die(`refused: the base config is installed ${memo.install} (${from}); moving it to ${baseInstall} cannot be done automatically.\n` +
    `  By hand: remove it from ${from} (the copied folders, and its hook commands from settings.json), delete "install" from ${MEMO},\n` +
    `  then run: node ${path.join(KIT, 'scripts', 'setup.mjs')} --scope base --install ${baseInstall}${baseInstall === 'project' ? ' --project <dir>' : ''}`)
}
if (baseInstall === 'project' && !top) die(`--install project needs a git repository: ${path.resolve(projectArg)}`)

// ---- tiers 2–3: every answer is checked before anything is written ------------------------------------
const branchExists = (b) => b && git(project, 'rev-parse', '--verify', '--quiet', `refs/heads/${b}`) !== null
const inferMain = () => ['main', 'master', git(project, 'config', 'init.defaultBranch')].find(branchExists)
  ?? git(project, 'symbolic-ref', '--short', 'HEAD') ?? 'main'
const asked = { project: answers.project, vision: answers.vision, main_branch: answers.main_branch }
const want = scope === 'base' ? {} : {
  project: asked.project ?? remembered.project ?? path.basename(project),
  vision: asked.vision ?? remembered.vision ?? 'TODO: one line on what this is and who it is for (inferred at setup; edit vault/Vision.md)',
  main_branch: asked.main_branch ?? remembered.main_branch ?? inferMain(),
}
const inferred = !remembered.project && (asked.project === undefined || asked.vision === undefined)
const diff = scope === 'base' ? [] : Object.keys(asked).filter((k) => asked[k] !== undefined && remembered[k] !== undefined && asked[k] !== remembered[k])
if (diff.length && !change) die(`these answers differ from the remembered ones: ${diff.join(', ')} — re-run with --change to apply them`)
const blocked = diff.filter((k) => k !== 'main_branch')
if (blocked.length) die(`refused: ${blocked.join(', ')} cannot be changed by re-running setup — the vault was written with them.\n` +
  '  By hand: edit vault/Vision.md, vault/Home.md and vault/Plan.md (Authority: owner), then update the entry for this project in ' + MEMO)
const haveOrg = scope === 'org' ? readJSON(orgFile, null) : null
const asOrg = { ...(answers.org ?? {}) }
const orgChanged = haveOrg ? Object.keys(asOrg).filter((k) => JSON.stringify(asOrg[k]) !== JSON.stringify(haveOrg[k])) : []
if (orgChanged.length && !change) die(`org.json answers differ from ${orgFile}: ${orgChanged.join(', ')} — re-run with --change to apply them`)
const fixed = orgChanged.filter((k) => ORG_FIXED.includes(k))
if (fixed.length) die(`refused: ${fixed.join(', ')} cannot change under a running org. By hand: lanes.sh ${orgRoot} stop (every lane), then edit ${orgFile} and re-run bootstrap-host.sh`)

// ---- tier 1: the base config --------------------------------------------------------------------------
let failed = false
function copyTree(from, to, rel = '') {
  let n = 0
  for (const e of fs.readdirSync(path.join(from, rel), { withFileTypes: true })) {
    if (e.name === '.DS_Store' || e.name === '__pycache__' || e.name.endsWith('.pyc')) continue
    const r = path.join(rel, e.name)
    if (e.isDirectory()) { n += copyTree(from, to, r); continue }
    const dst = path.join(to, r)
    if (fs.existsSync(dst)) continue
    fs.mkdirSync(path.dirname(dst), { recursive: true })
    fs.copyFileSync(path.join(from, r), dst)
    fs.chmodSync(dst, fs.statSync(path.join(from, r)).mode & 0o777)
    n++
  }
  return n
}
function mergeSettings(want, file, permissions) {
  if (!fs.existsSync(file)) { if (permissions === 'none') delete want.permissions; writeJSON(file, want); return 'written' }
  const raw = fs.readFileSync(file, 'utf8')
  const ph = raw.match(HAS_PH)
  if (ph) { console.error(`setup: ${file} carries an unfilled ${ph[0]}; NOT merged. Fill or remove it, then re-run.`); failed = true; return 'NOT merged' }
  let have
  try { have = JSON.parse(raw) } catch (e) { console.error(`setup: ${file} is not plain JSON (${e.message}); NOT merged.`); failed = true; return 'NOT merged' }
  let n = 0
  if (permissions !== 'none') {
    have.permissions ??= {}
    for (const k of ['allow', 'ask', 'deny']) for (const rule of want.permissions?.[k] ?? []) {
      have.permissions[k] ??= []
      if (!have.permissions[k].includes(rule)) { have.permissions[k].push(rule); n++ }
    }
  }
  have.hooks ??= {}
  for (const [ev, entries] of Object.entries(want.hooks ?? {})) {
    have.hooks[ev] ??= []
    const cmds = new Set(have.hooks[ev].flatMap((e) => (e.hooks ?? []).map((h) => h.command)))
    for (const e of entries) {
      const missing = (e.hooks ?? []).filter((h) => !cmds.has(h.command))
      if (missing.length) { have.hooks[ev].push({ ...e, hooks: missing }); n += missing.length }
    }
  }
  if (n) writeJSON(file, have)
  return n ? `merged (+${n})` : 'kept'
}
const permissions = answers.permissions ?? memo.permissions ?? 'default'
const baseDir = baseInstall === 'global' ? path.join(HOME, '.claude') : path.join(project, '.claude')
if (same(SRC, baseDir)) say(`base config: already here (${baseDir})`)
else {
  if (baseInstall === 'project' && same(SRC, path.join(HOME, '.claude'))) say('WARN: copying from your global ~/.claude, which may hold skills of your own beyond this config; run setup.mjs from a clone of the config to install exactly it')
  let n = 0
  // In a vault repo the vault's role cards ARE the agents (the contract test requires its rules in every
  // card); the base personas (code-reviewer, …) would run there without them, so they stay out.
  const orgRepo = baseInstall === 'project' && (scope !== 'base' || fs.existsSync(path.join(project, 'vault', 'AGENTS.md')))
  for (const d of BASE) if (fs.existsSync(path.join(SRC, d)) && !(orgRepo && d === 'agents')) n += copyTree(path.join(SRC, d), path.join(baseDir, d))
  if (orgRepo) {   // personas an earlier base-only run copied here, still unmodified, are ours to take back
    const gone = fs.readdirSync(path.join(SRC, 'agents')).filter((f) => {
      const mine = path.join(baseDir, 'agents', f)
      return fs.existsSync(mine) && fs.readFileSync(mine).equals(fs.readFileSync(path.join(SRC, 'agents', f))) && (fs.rmSync(mine), true)
    })
    say(`base agents/ not installed here: this is a vault repo, its role cards are the agents${gone.length ? ` (removed unmodified copies: ${gone.join(', ')})` : ''}`)
  }
  const s = mergeSettings(readJSON(path.join(SRC, 'settings.json'), {}), path.join(baseDir, 'settings.json'), permissions)
  if (baseInstall === 'project' && !fs.existsSync(path.join(project, '.mcp.json')) && fs.existsSync(path.join(SRC, '.mcp.json'))) {
    fs.copyFileSync(path.join(SRC, '.mcp.json'), path.join(project, '.mcp.json')); n++   // MCP config lives at the project root
  }
  say(`base config → ${baseDir}: ${n} file(s) written, settings.json ${s}`)
}
memo.install = baseInstall
memo.permissions = permissions
writeJSON(MEMO, memo)

// ---- tier 2/3: remembered project answers -------------------------------------------------------------
function finish(code = failed ? 1 : 0) {
  writeJSON(MEMO, memo)
  process.exit(code)
}
if (scope === 'base') finish()

// A changed main branch: org.json, the settings env and the PR-gate workflow — nothing else.
function renameMain(from, to) {
  const touched = []
  const org = readJSON(orgFile, null)
  if (org && org.main_branch !== to) { org.main_branch = to; writeJSON(orgFile, org); touched.push(orgFile) }
  const sf = path.join(project, '.claude', 'settings.json'), s = readJSON(sf, null)
  if (s?.env?.ORG_MAIN_BRANCH !== undefined && s.env.ORG_MAIN_BRANCH !== to) { s.env.ORG_MAIN_BRANCH = to; writeJSON(sf, s); touched.push('.claude/settings.json') }
  const wf = path.join(project, '.github', 'workflows', 'org-gates.yml')
  if (fs.existsSync(wf)) {
    const esc = from.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
    const before = fs.readFileSync(wf, 'utf8')
    const after = before.replace(new RegExp(`(branches: \\[)${esc}(\\])`, 'g'), `$1${to}$2`).replace(new RegExp(`(ORG_MAIN_BRANCH: )${esc}\\b`, 'g'), `$1${to}`)
    if (after !== before) { fs.writeFileSync(wf, after); touched.push('.github/workflows/org-gates.yml') }
  }
  say(`main branch ${from} → ${to}: updated ${touched.join(', ') || 'nothing (already current)'}`)
  if (touched.includes('.claude/settings.json')) say('.claude/settings.json is a protected path: commit this change with `Authority: owner`.')
}
if (diff.includes('main_branch')) {
  renameMain(remembered.main_branch, want.main_branch)
  memo.projects[project] = { ...remembered, main_branch: want.main_branch }
  finish()
}

// ---- the vault (init-repo), with the interview's vars over inferred ones ----------------------------------
const areas = fs.readdirSync(project, { withFileTypes: true })
  .filter((e) => e.isDirectory() && !e.name.startsWith('.') && !['vault', 'scripts', 'evidence', 'node_modules'].includes(e.name))
  .map((e) => `| \`${e.name}/\` | TODO: what lives here | |`)
// What only the full interview knows is a token in a vault-only install, `none yet [setup:KEY]`. A later
// scope=org run replaces exactly those tokens in place (the owner's other edits stay), then init-repo adds
// whatever is missing: an upgrade that a re-run leaves alone.
const tok = (k) => (k === 'LANE_TABLE' ? '| none yet [setup:LANE_TABLE] | | | | | |' : k === 'EXTRA_RULINGS' ? '- none yet [setup:EXTRA_RULINGS]' : `none yet [setup:${k}]`)
const LATER = ['USERS', 'ACCEPTANCE_BAR', 'OWNER_WORDS', 'NOT_WORKED', 'SUPERVISOR_DESC', 'WORKER_DESC', 'RUNTIME', 'HOST', 'ORG_ROOT', 'LANE_TABLE', 'EXTRA_RULINGS']
const hadVault = fs.existsSync(path.join(project, 'vault', 'AGENTS.md'))
const mission = remembered.mission ?? (scope === 'org' && !hadVault ? answers.vars?.MISSION : null) ?? 'first-mission'
const vars = {
  PROJECT: want.project, MAIN_BRANCH: want.main_branch, VISION_ONE_LINER: want.vision,
  MISSION_TITLE: 'First mission', MISSION_GOAL: want.vision,
  NEXT_MOVE: 'confirm the vision in vault/Vision.md', FIRST_TRACK: 'setup', FIRST_TRACK_ITEM: 'confirm the vision and the source areas',
  SOURCE_AREAS: areas.join('\n') || '| `./` | TODO: what lives here | |', STATE_BRANCH: 'backup/lane-state',
  ...Object.fromEntries(LATER.map((k) => [k, tok(k)])),
  ...(scope === 'org' ? { ORG_ROOT: orgRoot, ...(answers.vars ?? {}) } : {}),
  MISSION: mission,   // the mission file already exists under this name; never start a second one
}
if (scope === 'org' && hadVault) {
  const swap = LATER.filter((k) => vars[k] !== tok(k))
  const walkText = (d) => fs.readdirSync(d, { withFileTypes: true }).flatMap((e) =>
    e.name === '.git' || e.name === 'node_modules' ? [] : e.isDirectory() ? walkText(path.join(d, e.name)) : [path.join(d, e.name)])
  let n = 0
  // only where the templates put tokens: the vault and the rules (never the copied config under .claude/skills)
  for (const f of ['vault', path.join('.claude', 'rules')].filter((d) => fs.existsSync(path.join(project, d))).flatMap((d) => walkText(path.join(project, d)))) {
    const t = fs.readFileSync(f, 'utf8')
    if (!t.includes('[setup:')) continue
    const u = swap.reduce((s, k) => s.split(tok(k)).join(vars[k]), t)
    if (u !== t) { fs.writeFileSync(f, u); n++ }
  }
  say(`vault upgraded to the org: ${n} file(s) had their [setup:…] tokens filled (${swap.join(' ') || 'none answered'})`)
}
const vf = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'setup-')), 'vars.json')
writeJSON(vf, vars)
const r = spawnSync('node', [path.join(KIT, 'scripts', 'init-repo.mjs'), '--repo', project, '--vars', vf], { encoding: 'utf8' })
fs.rmSync(path.dirname(vf), { recursive: true, force: true })
process.stdout.write(r.stdout); process.stderr.write(r.stderr)
if (r.status !== 0) failed = true
if (r.status === 2) die('the vault was not installed (init-repo refused, above)')

// An inferred name or vision is a TODO the owner should see first: the Index's hand-kept block.
const idx = path.join(project, 'vault', 'Index.md'), TODO = '- TODO (setup): the project name and vision were inferred — confirm them in [[Vision]].'
if (inferred && fs.existsSync(idx)) {
  const t = fs.readFileSync(idx, 'utf8')
  if (!t.includes(TODO)) fs.writeFileSync(idx, t.replace(/(<!-- INDEX:PROMOTED-BEGIN[^\n]*\n)/, `$1${TODO}\n`))
}
memo.projects[project] = { ...remembered, project: want.project, vision: want.vision, main_branch: want.main_branch, mission, ...(scope === 'org' ? { org_root: orgRoot } : {}) }
if (scope === 'vault') finish()

// ---- tier 3: org.json, then (optionally) this box's bootstrap ----------------------------------------------
const example = readJSON(path.join(KIT, 'scripts', 'org.example.json'), {})
for (const k of Object.keys(example)) if (k.startsWith('_')) delete example[k]
if (haveOrg) {
  if (orgChanged.length) { writeJSON(orgFile, { ...haveOrg, ...asOrg }); say(`org.json updated: ${orgChanged.join(', ')}`) }
  else say(`org.json kept (${orgFile})`)
} else {
  // The example shows a VPS; a new org starts local and opt-in (no worker user, no wrapped builds, no links).
  const local = { runtime: 'local', host: '', worker_user: '', claude_bin: 'claude', worktree_links: [], build_queue: { slots: 2, wrap: [] } }
  writeJSON(orgFile, { ...example, ...local, ...asOrg, project: want.project, repo: project, main_branch: want.main_branch })
  say(`org.json written (${orgFile})`)
}
if (bootstrap) {
  const org = readJSON(orgFile, {})
  if (org.host && !['local', 'localhost'].includes(org.host)) {
    say(`the org runs on ${org.host}: copy ${KIT}/scripts and ${KIT}/templates/lane there with ${orgFile}, then run bootstrap-host.sh on it (SKILL.md §4)`)
  } else {
    const b = spawnSync('bash', [path.join(KIT, 'scripts', 'bootstrap-host.sh'), orgRoot], { encoding: 'utf8' })
    process.stdout.write(b.stdout); process.stderr.write(b.stderr)
    if (b.status !== 0) { say(`bootstrap-host.sh stopped (exit ${b.status}) — fix what it names above, then re-run /setup`); memo.projects[project].bootstrap = 'failed'; finish(b.status) }
    memo.projects[project].bootstrap = 'ok'
  }
}
finish()
