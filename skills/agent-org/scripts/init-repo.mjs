#!/usr/bin/env node
/**
 * init-repo — install the agent-org repo layer (templates/repo/) into a project, 1:1.
 *
 *   node <KIT>/scripts/init-repo.mjs --repo <path> --set KEY=VALUE [--set …] [--vars <file.json>]
 *                                    [--allow-unfilled] [--install-global-skills]
 *
 * WHAT IT DOES, in order:
 *   1. Copies every file under templates/repo/ to the same path in <repo>, with two path rules:
 *      - a path segment ending in `.tmpl` loses the suffix. The kit stores the four PROTECTED
 *        entries this way (`vault/Plan.md.tmpl`, `vault/Roadmap.md.tmpl`, `vault/Decisions.tmpl/`,
 *        `.claude/rules.tmpl/`), because the contract hook protects those paths in ANY checkout —
 *        including the kit's own template tree — and an agent editing the kit must not be refused.
 *      - `{{KEY}}` in a path is substituted (e.g. `vault/Missions/{{MISSION}}.md`).
 *   2. Substitutes `{{KEY}}` (UPPER_SNAKE only) in every copied text file. Lower-case `{{date}}`
 *      is Obsidian's template syntax and is left alone.
 *   3. MERGES, never overwrites: an existing file is kept as is, except `.gitignore` (missing lines
 *      appended) and `.claude/settings.json` (missing env keys and hook commands added).
 *   4. Regenerates the vault's hubs, Map and Index in <repo> (and the code map if a graph exists).
 *   0. FIRST, before writing anything: refuses (exit 2) when any `{{KEY}}` the templates use has
 *      no value, unless --allow-unfilled. A partial install is worse than none.
 *   5. Reports every `{{KEY}}` still unfilled in what it wrote, by file, and exits 1 if any remain
 *      (only reachable with --allow-unfilled): an unfilled placeholder is a defect the next agent
 *      reads as content.
 *
 * It never commits, never pushes, and never writes outside <repo> (except, with
 * --install-global-skills, missing skills into ~/.claude/skills/ — never overwriting one).
 */
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { spawnSync } from 'node:child_process'
import { fileURLToPath } from 'node:url'

const KIT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
const SRC = path.join(KIT, 'templates', 'repo')
// The rules depend on these two; they live beside the kit in the same skills/ folder, not in it.
const GLOBAL_SKILLS = ['pre-edit-scan', 'memory-discipline']
const SKILLS_DIR = path.dirname(KIT)
const argv = process.argv.slice(2)
const vars = {}
let repo = null, allowUnfilled = false, globalSkills = false
const die = (m, code = 2) => { console.error(`init-repo: ${m}`); process.exit(code) }
for (let i = 0; i < argv.length; i++) {
  const a = argv[i]
  if (a === '--repo') repo = argv[++i]
  else if (a === '--set') {
    const kv = argv[++i] ?? ''
    const eq = kv.indexOf('=')
    if (eq < 1 || !/^[A-Z][A-Z0-9_]*$/.test(kv.slice(0, eq))) die(`--set expects KEY=VALUE with an UPPER_SNAKE key, got '${kv}'`)
    vars[kv.slice(0, eq)] = kv.slice(eq + 1)
  } else if (a === '--vars') {
    const f = argv[++i]
    let o
    try { o = JSON.parse(fs.readFileSync(f, 'utf8')) } catch (e) { die(`--vars ${f}: ${e.message}`) }
    for (const [k, v] of Object.entries(o)) vars[k] = String(v)
  } else if (a === '--allow-unfilled') allowUnfilled = true
  else if (a === '--install-global-skills') globalSkills = true
  else die(`unrecognised argument: ${a}\ninit-repo: accepts: --repo <path> --set KEY=VALUE --vars <file.json> --allow-unfilled --install-global-skills`)
}
if (!repo) die('--repo <path> is required')
repo = path.resolve(repo)
if (!fs.existsSync(repo) || !fs.statSync(repo).isDirectory()) die(`not a directory: ${repo}`)
if (globalSkills) {
  const missing = GLOBAL_SKILLS.filter((s) => !fs.existsSync(path.join(SKILLS_DIR, s, 'SKILL.md')))
  if (missing.length) die(`--install-global-skills: ${missing.join(', ')} not found beside the kit in ${SKILLS_DIR}`)
}
if (!vars.DATE) vars.DATE = new Date().toISOString().slice(0, 10)
if (!vars.MAIN_BRANCH) vars.MAIN_BRANCH = 'main'

const PH = /\{\{([A-Z][A-Z0-9_]*)\}\}/g
const HAS_PH = /\{\{[A-Z][A-Z0-9_]*\}\}/
const fill = (s) => s.replace(PH, (m, k) => (k in vars ? vars[k] : m))
const destOf = (rel) => fill(rel.split('/').map((seg) => seg.replace(/\.tmpl$/, '')).join('/'))
const isText = (buf) => !buf.includes(0)

function walk(dir, rel = '') {
  const out = []
  for (const e of fs.readdirSync(path.join(dir, rel), { withFileTypes: true }).sort((a, b) => a.name.localeCompare(b.name))) {
    if (e.name === '.DS_Store' || e.name === '__pycache__') continue
    const r = rel ? `${rel}/${e.name}` : e.name
    if (e.isDirectory()) out.push(...walk(dir, r))
    else out.push(r)
  }
  return out
}

// FAIL FAST, BEFORE ANY WRITE: every key the templates use must be supplied. A partial
// install with literal `{{KEY}}` in file names and hook commands is worse than none.
const used = new Set()
for (const rel of walk(SRC)) {
  for (const m of rel.matchAll(PH)) used.add(m[1])
  const buf = fs.readFileSync(path.join(SRC, rel))
  if (isText(buf)) for (const m of buf.toString('utf8').matchAll(PH)) used.add(m[1])
}
const missingKeys = [...used].filter((k) => !(k in vars)).sort()
if (missingKeys.length && !allowUnfilled) {
  die(`REFUSED before writing anything — no value for: ${missingKeys.join(' ')}\n` +
    'init-repo: pass them with --set KEY=VALUE or --vars <file.json> (or --allow-unfilled to fill them by hand later)')
}

const written = [], kept = [], merged = []
for (const rel of walk(SRC)) {
  const dest = destOf(rel)
  const to = path.join(repo, dest)
  const buf = fs.readFileSync(path.join(SRC, rel))
  const body = isText(buf) ? Buffer.from(fill(buf.toString('utf8'))) : buf
  fs.mkdirSync(path.dirname(to), { recursive: true })
  if (!fs.existsSync(to)) {
    fs.writeFileSync(to, body)
    if (/\.(sh|mjs|py)$/.test(dest) && body.toString().startsWith('#!')) fs.chmodSync(to, 0o755)
    written.push(dest)
    continue
  }
  if (dest === '.gitignore') {
    const have = fs.readFileSync(to, 'utf8')
    const lines = have.split('\n')
    const add = body.toString().split('\n').filter((l) => l.trim() && !lines.includes(l))
    if (add.length) { fs.appendFileSync(to, (have.endsWith('\n') ? '' : '\n') + add.join('\n') + '\n'); merged.push(`${dest} (+${add.length} lines)`) }
    else kept.push(dest)
    continue
  }
  if (dest === '.claude/settings.json') {
    const raw = fs.readFileSync(to, 'utf8')
    if (HAS_PH.test(raw)) {   // a half-filled template: merging into it would hide the placeholder under working hooks
      console.error(`init-repo: ${dest} carries an unfilled ${raw.match(HAS_PH)[0]}; its hooks and env were NOT merged. Fill or remove it, then re-run.`)
      process.exitCode = 1
      kept.push(`${dest} (NOT merged)`)
      continue
    }
    let have, want
    try { have = JSON.parse(raw); want = JSON.parse(body.toString()) }
    catch (e) {
      // Without these hooks the contract, loop guard and dispatch log are silently absent, and the
      // board does not test hooks, so it would still go green. Fail the install instead.
      console.error(`init-repo: ${dest} could not be parsed (${e.message}); its hooks and env were NOT merged. ` +
        `Make it plain JSON (no comments) and re-run, or merge them by hand from ${path.join(SRC, rel)}.`)
      process.exitCode = 1
      kept.push(`${dest} (NOT merged)`)
      continue
    }
    let n = 0
    have.env ??= {}
    for (const [k, v] of Object.entries(want.env ?? {})) {
      if (!(k in have.env)) { have.env[k] = v; n++ }
      else if (have.env[k] !== v) console.warn(`init-repo: WARNING ${dest} keeps env ${k}=${JSON.stringify(have.env[k])}; the vars file says ${JSON.stringify(v)}. The gates read the settings value — change one so they agree.`)
    }
    have.hooks ??= {}
    // A hook counts as present when it targets the same project file, so a re-run after the kit
    // rewords a command does not install a second copy of it.
    const target = (c) => (String(c).match(/\$\{?CLAUDE_PROJECT_DIR\}?\/([^"'\s]+)/) || [])[1] || c
    for (const [ev, entries] of Object.entries(want.hooks ?? {})) {
      have.hooks[ev] ??= []
      const cmds = new Set(have.hooks[ev].flatMap((e) => (e.hooks ?? []).map((h) => target(h.command))))
      for (const e of entries) {
        // never merge a hook whose command still carries an unfilled placeholder
        const missing = (e.hooks ?? []).filter((h) => !cmds.has(target(h.command)) && !HAS_PH.test(h.command))
        if (missing.length) { have.hooks[ev].push({ ...e, hooks: missing }); n += missing.length }
      }
    }
    if (n) { fs.writeFileSync(to, JSON.stringify(have, null, 2) + '\n'); merged.push(`${dest} (+${n} env keys / hook commands)`) }
    else kept.push(dest)
    continue
  }
  kept.push(dest)
}

if (globalSkills) {
  const home = path.join(os.homedir(), '.claude', 'skills')
  for (const s of GLOBAL_SKILLS) {
    const to = path.join(home, s)
    if (fs.existsSync(to)) { kept.push(`~/.claude/skills/${s}`); continue }
    fs.mkdirSync(to, { recursive: true })
    fs.copyFileSync(path.join(SKILLS_DIR, s, 'SKILL.md'), path.join(to, 'SKILL.md'))
    written.push(`~/.claude/skills/${s}/SKILL.md`)
  }
}

console.log(`init-repo: ${written.length} written, ${merged.length} merged, ${kept.length} kept (already present) — ${repo}`)
for (const m of merged) console.log(`  merged ${m}`)
if (kept.length) console.log(`  kept as is (merge by hand if the kit's version is needed): ${kept.slice(0, 12).join(', ')}${kept.length > 12 ? ` … +${kept.length - 12}` : ''}`)

// ---- regenerate the derived vault pages, in the target repo -----------------
const run = (cmd, args) => {
  const r = spawnSync(cmd, args, { cwd: repo, encoding: 'utf8' })
  const line = `${(r.stdout || '').trim().split('\n').pop() || ''} ${(r.stderr || '').trim().split('\n').pop() || ''}`.trim()
  console.log(`  ${[cmd, ...args].join(' ')} → exit ${r.status}${line ? ` · ${line.slice(0, 140)}` : ''}`)
  return r.status
}
console.log('init-repo: regenerating derived vault pages')
run('node', ['scripts/vault-hubs.mjs'])
run('python3', ['scripts/gen-subject-index.py'])
if (fs.existsSync(path.join(repo, 'graphify-out', 'graph.json'))) run('python3', ['scripts/gen-code-map.py'])
run('node', ['scripts/vault-hubs.mjs'])   // the Index is a note too: a second pass lists it — and must be a no-op after

// ---- unfilled placeholders --------------------------------------------------
const unfilled = new Map()
for (const rel of walk(repo).filter((r) => !r.startsWith('.git/') && !r.startsWith('node_modules/'))) {
  if (!written.includes(rel) && !merged.some((m) => m.startsWith(rel + ' '))) continue
  const buf = fs.readFileSync(path.join(repo, rel))
  if (!isText(buf)) continue
  const keys = [...new Set([...buf.toString('utf8').matchAll(PH)].map((m) => m[1]))]
  if (keys.length) unfilled.set(rel, keys)
}
if (unfilled.size) {
  console.log(`init-repo: ${unfilled.size} file(s) still carry UNFILLED placeholders:`)
  for (const [f, ks] of unfilled) console.log(`  ${f}: ${ks.map((k) => `{{${k}}}`).join(' ')}`)
  console.log('  Fill them (re-run with --set KEY=VALUE only fills files this run WROTE; edit the rest by hand).')
  if (!allowUnfilled) process.exit(1)
}
if (process.exitCode) console.log('init-repo: finished WITH ERRORS (above). Fix them before committing.')
else console.log('init-repo: done. Next: commit on a branch (Authority: owner — the owner said yes to the set-up, plus an EVIDENCE-GROWTH paragraph), then `bash scripts/gates/org-board.sh` must exit 0.')
