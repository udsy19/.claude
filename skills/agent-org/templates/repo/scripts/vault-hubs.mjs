#!/usr/bin/env node
// A closed pipe is not an error: `node scripts/x.mjs | head` must not report failure.
process.stdout.on('error', (e) => { if (e && e.code === 'EPIPE') process.exit(0) })
/**
 * vault-hubs — generate vault/Map.md and one README.md per vault directory.
 *
 * WHY A GENERATOR AND NOT HAND-WRITTEN HUBS. The index has to list every note in the
 * vault, and a hand-maintained list is wrong the day after it is written. This script is
 * re-runnable: `--check` re-derives what the files SHOULD contain and diffs it against
 * what they DO contain, so a note added without a hub link is caught by
 * scripts/gates/vault-reachability.mjs and repaired by one command.
 *
 * THE PURPOSE LINES ARE HAND-WRITTEN, ON PURPOSE. A directory's one-line "what it is for,
 * who reads it" is the only part a generator cannot derive, and the only part with any
 * value. They live in DIRS below. A directory with no entry is REFUSED rather than given a
 * generic line — a generated sentence that says nothing is worse than no sentence, because
 * it reads like somebody decided. Add a folder → add its purpose line here, same change.
 *
 * IT WRITES NOTHING BUT README.md AND Map.md, and never edits any other note. A signpost
 * carries no vision, decision or scope, and every file this writes says so in its own body.
 *
 * THE DATE IS NOT A CHANGE. A hub's `date:`/`updated:` and Map's "Measured" stamp record
 * when the CONTENT last changed: a hub whose content is unchanged keeps its old date, so
 * `--check` does not go stale at midnight with not one vault byte moved.
 *
 *   node scripts/vault-hubs.mjs            write Map.md + every README.md
 *   node scripts/vault-hubs.mjs --check    exit 1 if any is stale, write nothing
 *
 * EXIT: 0 written / already current · 1 --check found drift · 2 refused.
 */
import { readdirSync, readFileSync, writeFileSync, existsSync } from 'node:fs'
import { join, resolve, dirname, basename } from 'node:path'
import { refuseUnknownArgv } from './lib/argv.mjs'
import { fileURLToPath } from 'node:url'

const argv = process.argv.slice(2)
refuseUnknownArgv(argv, { script: 'vault-hubs', accepts: ['--check'] })
const CHECK = argv.includes('--check')

const REPO = resolve(fileURLToPath(new URL('..', import.meta.url)))
const VAULT = join(REPO, 'vault')
const TODAY = new Date().toISOString().slice(0, 10)

// The one thing no generator can derive: what a folder is FOR, and who reads it.
// An entry for a folder that does not exist yet is harmless; a folder with no entry is refused.
const DIRS = {
  '.': 'The vault root: the notes every session starts from. [[Home]] owns NOW, [[Vision]] the goal, [[Roadmap]] the delivery tracker, [[Plan]] the ordered plan of record, [[AGENTS]] and [[SUPERVISOR]] the two contracts, and [[CLAUDE]] the rules for what an agent may write here.',
  'Archive': 'Notes kept for the record only. A note arrives here by being SUPERSEDED, never by being wrong, and only once nothing current links to it (vault/CLAUDE.md). Read one when you need to know what a current decision replaced.',
  'Decisions': 'Decision records, one decision per numbered note. Read before changing anything a decision governs. A decision is law until superseded; only the owner or the supervisor writes here — everyone else files a proposal (scripts/propose.mjs).',
  'Design': 'Design specs — how a thing should behave, written before it is built. Read by whoever implements the subsystem the note names.',
  'Missions': 'One note per mission: scope, the lanes serving it, and a definition of done that is OWNER-EDITED. Its `## NOW` block is printed into every session. Read the mission you are serving at session open, after Home and the newest session note.',
  'Reports': 'Mission reports, audits and post-mortems — what a lane measured and what it delivered, written after the work. A number in one of these names the gate or session that produced it, or it is a claim.',
  'Reports/audits': 'Standing registers rather than one-off reports. `SESSION-REGISTRY.md` declares which lines are live: read it before taking a branch, write your declaration into it.',
  'Research': 'What exists outside this repo — competitor teardowns, library evaluations and captures. Read before building something that may already exist.',
  'Research/captures': 'One note per link, video or screenshot the owner sent in, filed by the capture skill from `Templates/capture.md`: what it shows and what we take from it.',
  'Research/oss': 'Evaluations of open-source libraries, each written BEFORE adopting or rejecting one, so a rejection is recoverable reasoning rather than a lost afternoon.',
  'Sessions': 'One note per work session, from `Templates/session.md`: what changed, with commits and evidence paths. The NEWEST note here is read at every session open (vault/CLAUDE.md).',
  'Templates': 'The note shapes an agent fills in. Wikilinks in these files carry deliberate blanks (`D-XXXX-...`, `Design/...`) — they are the form, not broken links, and scripts/gates/vault-reachability.mjs classifies them as TEMPLATE_PLACEHOLDER.',
}

// Hand-written READMEs that say more than a generated index could. They are listed in
// Map.md like any other hub and never rewritten. Add a folder path here to opt it out.
const HAND_WRITTEN = new Set([])

const SIGNPOST = '> [!note] Signpost only.\n> This file adds no vision, decision or scope — it lists what is already here so the\n> next reader can find it. Delete it and nothing but navigation is lost; regenerate it\n> with `node scripts/vault-hubs.mjs`.'

// Every FOLDER gets a hub, including one with no notes yet (an empty folder is still a place
// an agent will be sent) — except dot-folders and `_log/`, which hold machine state, not notes.
const FOLDERS = []
function walk(rel = '') {
  const out = []
  for (const e of readdirSync(join(VAULT, rel), { withFileTypes: true }).sort((a, b) => a.name.localeCompare(b.name))) {
    if (e.name.startsWith('.') || (rel === '' && e.name === '_log')) continue
    const r = rel ? `${rel}/${e.name}` : e.name
    if (e.isDirectory()) { FOLDERS.push(r); out.push(...walk(r)) }
    else if (e.name.endsWith('.md')) out.push(r)
  }
  return out
}

/** A note's display title: its H1 if it has one, else its filename. */
function titleOf(rel) {
  // A file this run is about to create has no H1 on disk yet; its title is known.
  if (!existsSync(join(VAULT, rel))) {
    if (rel === 'Map.md') return 'Map of this vault'
    if (rel.endsWith('/README.md')) return `${dirname(rel)}/`
  }
  const src = readFileSync(join(VAULT, rel), 'utf8')
  const body = src.replace(/^---\n[\s\S]*?\n---\n/, '')
  const h1 = /^#\s+(.+)$/m.exec(body)
  // A `|` in a title would end the wikilink alias early.
  return (h1 ? h1[1] : basename(rel, '.md')).replace(/[`*_]/g, '').replace(/\|/g, '/').trim()
}

// The generator must be a FIXED POINT: running it twice must produce the same bytes. The
// note set is the union of what is on disk and what this run WILL write, computed before
// anything is written, and every listing is derived from that one set.
const onDisk = walk()
const dirsOf = (list) => {
  const m = new Map()
  for (const d of FOLDERS) m.set(d, [])
  for (const n of list) {
    const d = n.includes('/') ? dirname(n) : '.'
    if (!m.has(d)) m.set(d, [])
    m.get(d).push(n)
  }
  for (const v of m.values()) v.sort()
  return m
}
const planned = ['Map.md', ...[...dirsOf(onDisk).keys()].filter((d) => d !== '.' && !HAND_WRITTEN.has(d)).map((d) => `${d}/README.md`)]
const notes = [...new Set([...onDisk, ...planned])].sort()
const byDir = dirsOf(notes)

const missing = [...byDir.keys()].filter((d) => !(d in DIRS))
if (missing.length) {
  console.error(`vault-hubs: REFUSED — no purpose line for: ${missing.join(', ')}`)
  console.error('vault-hubs: add one to DIRS in scripts/vault-hubs.mjs. A generated sentence that says nothing reads like a decision.')
  process.exit(2)
}

const STAMP = '@@HUB-DATE@@'
const fm = () => `---\ntype: dashboard\nstatus: current\ndate: ${STAMP}\nupdated: ${STAMP}\n---\n`

// ---- README.md, one per directory -------------------------------------------
const files = new Map()
for (const [d, list] of byDir) {
  if (d === '.' || HAND_WRITTEN.has(d)) continue
  const rel = `${d}/README.md`
  const kids = [...byDir.keys()].filter((k) => k !== d && dirname(k) === d).sort()
  const lines = [fm(), `# \`${d}/\``, '', DIRS[d], '', SIGNPOST, '']
  lines.push(`## Notes here (${list.filter((n) => n !== rel).length})`, '')
  for (const n of list.filter((n) => n !== rel)) lines.push(`- [[${n.replace(/\.md$/, '')}|${titleOf(n)}]]`)
  if (kids.length) {
    lines.push('', '## Below this folder', '')
    for (const k of kids) lines.push(`- [[${k}/README|\`${k}/\`]]`)
  }
  lines.push('', '---', '', 'Up: [[Map]] · [[Home]]', '')
  files.set(rel, lines.join('\n'))
}

// ---- Map.md — the index Home points at --------------------------------------
// Every note is listed HERE, one hop from Home, so no note is more than two hops from the
// front door. The per-directory READMEs give local navigation; this makes the bound true.
{
  const lines = [fm(), '# Map of this vault', '',
    'Every note in `vault/`, grouped by the folder it lives in. This file exists so that no',
    'note is more than **two hops** from [[Home]]: Home links here, and this links everything.',
    '`scripts/gates/vault-reachability.mjs` re-derives that claim from the filesystem and the',
    'bytes of each note, and fails if it stops being true.', '',
    SIGNPOST, '',
    `Measured ${STAMP}: **${notes.length} notes** over ${byDir.size} folders.`, '']
  const order = ['.', ...[...byDir.keys()].filter((d) => d !== '.').sort()]
  for (const d of order) {
    const list = byDir.get(d)
    lines.push('', d === '.' ? '## Start here — the vault root' : `## \`${d}/\``, '')
    if (d !== '.') lines.push(`${DIRS[d]}`, '', `Folder README: [[${d}/README]]`, '')
    for (const n of list) {
      if (n === 'Map.md') continue // this file does not list itself
      lines.push(`- [[${n.replace(/\.md$/, '')}|${titleOf(n)}]]`)
    }
  }
  lines.push('', '---', '', "Back to [[Home]]. The vault's own contract is [[CLAUDE]].", '')
  files.set('Map.md', lines.join('\n'))
}

// ---- write or check ---------------------------------------------------------
// Compare with the date stamps normalised (ONLY the three this file emits — never a date
// in the listed titles); write today's date only when the content really changed. The
// check re-READS what it wrote: a script that reports success from its own intention
// rather than the bytes on disk is the defect gate-independence law 13 names.
const normalise = (t) => t
  .replace(/^(date|updated): \d{4}-\d{2}-\d{2}$/gm, `$1: ${STAMP}`)
  .replace(/^Measured \d{4}-\d{2}-\d{2}:/m, `Measured ${STAMP}:`)
let drift = 0
for (const [rel, tmpl] of files) {
  const p = join(VAULT, rel)
  const have = existsSync(p) ? readFileSync(p, 'utf8') : null
  if (have !== null && normalise(have) === tmpl) continue
  drift++
  if (CHECK) { console.log(`STALE  vault/${rel}${have === null ? ' (missing)' : ''}`); continue }
  const want = tmpl.split(STAMP).join(TODAY)
  writeFileSync(p, want)
  if (readFileSync(p, 'utf8') !== want) { console.error(`vault-hubs: write did not take: vault/${rel}`); process.exit(2) }
  console.log(`${have === null ? 'wrote ' : 'update'} vault/${rel}  (${want.length} B)`)
}
if (CHECK) {
  console.log(drift ? `vault-hubs --check: ${drift} of ${files.size} hub file(s) STALE — run node scripts/vault-hubs.mjs` : `vault-hubs --check: all ${files.size} hub files current`)
  process.exit(drift ? 1 : 0)
}
console.log(`vault-hubs: ${files.size} hub file(s), ${drift} written/updated`)
process.exit(0)
