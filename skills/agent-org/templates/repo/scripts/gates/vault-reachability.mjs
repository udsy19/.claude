#!/usr/bin/env node
/**
 * vault-reachability — the gate for vault/, the Obsidian vault.
 *
 * WHY IT EXISTS. "We have so many redundancies and we build the same thing over
 * and over." A note nobody can reach from Home is a note the next agent will not
 * find, and a thing nobody can find is a thing somebody rebuilds. In the project
 * this kit was distilled from, 120 of 195 notes were once unreachable from
 * vault/Home.md by any number of hops — not stale, not wrong, simply invisible.
 *
 * WHAT IT ASSERTS. Every `vault/**./*.md` is reachable from vault/Home.md within
 * MAX_HOPS (2) link hops, and every link resolves. Two hops rather than "any
 * number" because reachability alone is satisfied by a chain, and a chain is not
 * navigation: Home -> hub -> note is the shape a human can hold.
 *
 * INDEPENDENCE (.claude/rules/gate-independence.md). This gate consumes NOTHING
 * the vault says about itself. It does not read `Home.md`'s "Where things are"
 * section, any README's claim about what it links, or any note's frontmatter.
 * It re-derives the node set from the FILESYSTEM (every .md under vault/) and the
 * edge set from the BYTES of each note (wikilinks and markdown links, after code
 * is stripped). A note that claims to be linked and is not is red; a hub that
 * claims to link everything and does not is red.
 *
 * THE PARSER IS THE WEAK POINT, so it is calibrated on links THIS AUTHOR DID NOT
 * WRITE (gate-independence §4a — never calibrate a detector on the fix's own
 * vocabulary). A vault mixes these conventions in the same tree:
 *   [[Vision]]                      bare basename
 *   [[Design/ui-system]]            vault-root-relative path, no extension
 *   [[Reports/audits/SESSION-REGISTRY]]  deep path
 *   [[Sessions.base#Recent]]        a NON-md target (an Obsidian Base) + a view
 *   [[Decisions/0005-x#Rule]]       heading fragment
 *   [[Missions/first-mission|the loop]]  alias
 *   ![[Sessions.base#Recent]]       embed
 * A resolver that understands only one of these disagrees with Obsidian, and a
 * gate that disagrees with the tool the humans use is measuring its own opinion.
 * `--selftest` hands the parser one of each, plus the two NON-links below.
 *
 * TWO THINGS LOOK EXACTLY LIKE WIKILINKS AND ARE NOT:
 *   `api/share/[[...path]].ts`   a catch-all ROUTE name inside an inline code span
 *   supersedes: "[[...]]"        a YAML frontmatter EXAMPLE inside a fenced block
 * Both are stripped before any link is matched. A parser that reported them would
 * file dangling links against notes that have none, and the fix for a phantom is
 * to delete a real line.
 *
 *   node scripts/gates/vault-reachability.mjs            grade vault/
 *   node scripts/gates/vault-reachability.mjs <dir>      grade another copy (sabotage)
 *   node scripts/gates/vault-reachability.mjs --selftest parser + depth positive controls
 *   node scripts/gates/vault-reachability.mjs --max-hops N   (sabotage only; N != 2 is
 *                                                    reported as a WEAKENED BOUND)
 *
 * WHY --max-hops IS A DECLARED KNOB AND NOT A CONSTANT. The two-hop bound is the
 * only part of this gate that can be true because nothing happened: once every
 * note is within two hops, raising the bound to 99 changes no verdict, so the
 * bound would be unguarded by the live vault ("a policy nothing sabotages is a
 * policy nothing guards"). `--selftest` therefore builds a fixture
 * whose only defect is DEPTH — Home -> hub -> mid -> deep, every link resolving —
 * and asserts this gate reds on it and names `deep.md`. That fixture is the
 * positive control for MAX_HOPS; the live vault is not and cannot be.
 *
 * EXIT: 0 every note reachable within the bound and every link resolving · 1 at
 * least one check red · 2 refused (bad argv, a vault it cannot read, or a run
 * that found nothing to grade). A refusal grades nothing and says so — an absent
 * verdict is its own outcome, never folded into the passes (gate-independence §7).
 */
import { readFileSync, readdirSync, statSync, existsSync, mkdtempSync, mkdirSync, writeFileSync, rmSync } from 'node:fs'
import { join, relative, dirname, basename, resolve, sep } from 'node:path'
import { tmpdir } from 'node:os'
import { refuseUnknownArgv } from '../lib/argv.mjs'
import { fileURLToPath } from 'node:url'

// ---- argv: refuse what we do not understand, BY NAME, before any work -------
// Walk argv ONCE, consuming a valued flag's value as part of the flag, so the
// positionals are what is left. (Filtering flags and values separately once handed
// the helper a `--max-hops` with its value removed, so `--max-hops 99` refused
// itself and the knob had never worked.)
const argv = process.argv.slice(2)
const VALUED = ['--max-hops']
const ACCEPTS = ['--selftest', '--max-hops']
const positionals = []
const flagTokens = []
for (let i = 0; i < argv.length; i++) {
  const a = argv[i]
  if (!a.startsWith('-')) { positionals.push(a); continue }
  flagTokens.push(a)
  if (VALUED.includes(a) && argv[i + 1] !== undefined && !argv[i + 1].startsWith('-')) { flagTokens.push(argv[i + 1]); i++ }
}
const hopIdx = flagTokens.indexOf('--max-hops')
const hopValue = hopIdx >= 0 ? flagTokens[hopIdx + 1] : undefined
refuseUnknownArgv(flagTokens, { script: 'vault-reachability', accepts: ACCEPTS, valued: VALUED })
const flags = flagTokens
if (positionals.length > 1) {
  console.error(`vault-reachability: unrecognised argument: ${positionals[1]}`)
  console.error('vault-reachability: accepts: at most one vault directory')
  process.exit(2)
}

const DEFAULT_MAX_HOPS = 2
let MAX_HOPS = DEFAULT_MAX_HOPS
if (hopIdx >= 0) {
  const n = Number(hopValue)
  if (!Number.isInteger(n) || n < 0) {
    console.error(`vault-reachability: --max-hops expects a non-negative integer, got ${JSON.stringify(hopValue)}`)
    process.exit(2)
  }
  MAX_HOPS = n
}

const SELFTEST = flags.includes('--selftest')
const REPO = resolve(fileURLToPath(new URL('../..', import.meta.url)))
const VAULT = resolve(positionals[0] ?? join(REPO, 'vault'))

// ---- the parser -------------------------------------------------------------
// Order matters: fenced blocks first (they can contain backticks), then inline
// spans. Replacing with spaces rather than '' keeps byte offsets, so a line
// number reported for a link is the line the link is really on.
const blank = (s) => s.replace(/[^\n]/g, ' ')

export function stripCode(src) {
  let out = src.replace(/^([ \t]*)(```|~~~)[^\n]*\n[\s\S]*?^[ \t]*\2[^\n]*$/gm, (m) => blank(m))
  // An unterminated fence runs to EOF — Obsidian renders the rest as code too.
  out = out.replace(/^([ \t]*)(```|~~~)[^\n]*\n[\s\S]*$/m, (m) => blank(m))
  // CommonMark code spans: a run of N backticks is closed by a run of EXACTLY N.
  // The naive /`+[^`\n]*`+/ is wrong: in
  //     so `` `[[Design/x]]` `` renders as text
  // that pattern pairs the opening ``  with the following single ` , leaving
  // [[Design/x]] outside code and reporting a phantom link. vault/CLAUDE.md
  // carries that very sentence, so the live vault exercises this every run.
  out = out.replace(/(`+)((?:[^`]|(?!\1)`)*?)\1(?!`)/g, (m) => blank(m))
  return out
}

/** Every link a note emits, as {raw, target, frag, alias, embed, line}. */
export function parseLinks(src) {
  const clean = stripCode(src)
  const links = []
  const lineOf = (idx) => clean.slice(0, idx).split('\n').length
  for (const m of clean.matchAll(/(!?)\[\[([^\]\n|#]*)(#[^\]\n|]*)?(\|[^\]\n]*)?\]\]/g)) {
    const target = m[2].trim()
    if (!target && !m[3]) continue // [[]] or [[|x]] — not a link to anything
    links.push({
      raw: m[0], target, frag: (m[3] ?? '').replace(/^#/, ''),
      alias: (m[4] ?? '').replace(/^\|/, ''), embed: m[1] === '!', line: lineOf(m.index), kind: 'wiki',
    })
  }
  for (const m of clean.matchAll(/(!?)\[[^\]\n]*\]\(([^)\s]+)(?:\s+"[^"]*")?\)/g)) {
    let t = m[2]
    if (/^(https?|mailto|obsidian):/i.test(t)) continue
    t = decodeURIComponent(t)
    const hash = t.indexOf('#')
    const frag = hash >= 0 ? t.slice(hash + 1) : ''
    if (hash === 0) continue // same-note anchor
    if (hash > 0) t = t.slice(0, hash)
    links.push({ raw: m[0], target: t, frag, alias: '', embed: m[1] === '!', line: lineOf(m.index), kind: 'md' })
  }
  return links
}

// ---- resolution, Obsidian's order -------------------------------------------
// Obsidian resolves a bare name against the whole vault, and a path against the
// vault root, then against the linking note's folder. It appends `.md` only when
// the target has no extension. `Sessions.base` therefore resolves to a FILE that
// is not a note, and that is a resolved link, not a dangling one.
export function buildIndex(files) {
  const byPath = new Set(files)
  const byName = new Map()
  for (const f of files) {
    for (const key of [basename(f), basename(f).replace(/\.md$/, '')]) {
      if (!byName.has(key)) byName.set(key, [])
      byName.get(key).push(f)
    }
  }
  return { byPath, byName }
}

export function resolveTarget(target, fromFile, index) {
  const t = target.replace(/\\/g, '/').replace(/^\.\//, '')
  if (!t) return null
  const hasExt = /\.[A-Za-z0-9]+$/.test(basename(t))
  const cands = []
  const push = (p) => { const n = p.replace(/^\/+/, ''); if (n) cands.push(n) }
  push(t); if (!hasExt) push(`${t}.md`)
  const dir = dirname(fromFile)
  if (dir !== '.') { push(`${dir}/${t}`); if (!hasExt) push(`${dir}/${t}.md`) }
  for (const c of cands) {
    const norm = c.split('/').filter((s) => s && s !== '.').reduce((acc, s) => {
      if (s === '..') { acc.pop(); return acc } acc.push(s); return acc
    }, []).join('/')
    if (index.byPath.has(norm)) return norm
  }
  // bare-name fallback, vault-wide (Obsidian's "shortest path when not ambiguous")
  if (!t.includes('/')) {
    const hits = index.byName.get(t)
    if (hits && hits.length) return hits.slice().sort((a, b) => a.split('/').length - b.split('/').length || a.localeCompare(b))[0]
  }
  return null
}

// ---- classifying a link that resolved to nothing IN the vault ---------------
// Four outcomes, and only two of them are the vault's fault. Lumping them would
// excuse a real one: of three `../../../evidence/...` citations in one research
// note, TWO resolved to files that existed and ONE did not. A blanket
// "out-of-vault links are fine" rule passes a citation to a file that was never
// written; a blanket "all dangling is red" demands the good ones be deleted.
// Neither is a measurement.
//
// TEMPLATE_PLACEHOLDER is deliberately NARROW: only inside Templates/, and only
// when the target carries an explicit ellipsis or an XXXX stand-in. A template is
// a form to be filled, and `[[Decisions/D-XXXX-...]]` is the blank, not a break.
// Widening this predicate is how a real broken link gets excused.
function classify(link, fromNote, vaultDir) {
  const t = link.target
  if (fromNote.startsWith('Templates/') && /(\.\.\.|XXXX)/.test(t)) return 'TEMPLATE_PLACEHOLDER'
  if (link.kind === 'md' && (t.startsWith('../') || t.startsWith('/'))) {
    const abs = resolve(dirname(join(vaultDir, fromNote)), t)
    return existsSync(abs) ? 'OUT_OF_VAULT_RESOLVED' : 'OUT_OF_VAULT_MISSING'
  }
  // A wikilink can only ever mean "a note in this vault" — Obsidian has no other
  // referent — so one that resolves to nothing is broken even when a file of that
  // name exists elsewhere in the repo. vault/CLAUDE.md: paths outside the vault
  // are backticked code paths, never wikilinks.
  return 'BROKEN'
}

// The named ratchet. A COUNT would let one broken link be traded for another; the
// set is pinned by `<note>|<raw link>` so a new break is red and an old one cannot
// hide behind it. An entry here is DECLARED DEBT with a named repair, never a
// tolerance; repairing one is expected and the gate stays green. A fresh vault
// starts with none.
const KNOWN_BROKEN = new Set([])

// ---- walk -------------------------------------------------------------------
function walk(root, rel = '') {
  const out = []
  let entries
  try { entries = readdirSync(join(root, rel), { withFileTypes: true }) } catch { return out }
  for (const e of entries.sort((a, b) => a.name.localeCompare(b.name))) {
    if (e.name === '.obsidian' || e.name === '.git') continue
    const r = rel ? `${rel}/${e.name}` : e.name
    if (e.isDirectory()) out.push(...walk(root, r))
    else out.push(r)
  }
  return out
}

// ---- the graded run ---------------------------------------------------------
const results = []
let checks = 0, failing = 0
const check = (name, ok, detail) => {
  checks++; if (!ok) failing++
  results.push(`  ${ok ? 'ok  ' : 'FAIL'}  ${name}${detail ? `\n          ${detail}` : ''}`)
}

function grade(vaultDir, { quiet = false, maxHops = MAX_HOPS } = {}) {
  const allFiles = walk(vaultDir)
  const notes = allFiles.filter((f) => f.endsWith('.md'))
  const index = buildIndex(allFiles)
  const ROOT = 'Home.md'

  const edges = new Map()   // note -> Set(note)
  const dangling = []
  const linkCount = { wiki: 0, md: 0, embed: 0 }
  for (const n of notes) {
    const src = readFileSync(join(vaultDir, n), 'utf8')
    const outs = new Set()
    for (const l of parseLinks(src)) {
      linkCount[l.kind]++; if (l.embed) linkCount.embed++
      const hit = resolveTarget(l.target, n, index)
      if (!hit) { dangling.push({ from: n, line: l.line, raw: l.raw, target: l.target, klass: classify(l, n, vaultDir) }); continue }
      if (hit.endsWith('.md') && hit !== n) outs.add(hit)
    }
    edges.set(n, outs)
  }

  // BFS from Home
  const depth = new Map()
  if (notes.includes(ROOT)) {
    depth.set(ROOT, 0)
    let frontier = [ROOT]
    while (frontier.length) {
      const next = []
      for (const n of frontier) for (const m of edges.get(n) ?? []) {
        if (!depth.has(m)) { depth.set(m, depth.get(n) + 1); next.push(m) }
      }
      frontier = next
    }
  }

  const unreachable = notes.filter((n) => !depth.has(n))
  const tooDeep = notes.filter((n) => depth.has(n) && depth.get(n) > maxHops)

  if (!quiet) {
    const hist = new Map()
    for (const n of notes) { const d = depth.has(n) ? depth.get(n) : Infinity; hist.set(d, (hist.get(d) ?? 0) + 1) }
    const perDir = new Map()
    for (const n of notes) {
      const d = n.includes('/') ? n.split('/')[0] : '(root)'
      if (!perDir.has(d)) perDir.set(d, { total: 0, unreach: 0, deep: 0 })
      const e = perDir.get(d); e.total++
      if (!depth.has(n)) e.unreach++; else if (depth.get(n) > maxHops) e.deep++
    }
    const out = []
    out.push(`VAULT ${vaultDir}`)
    out.push(`  notes ${notes.length} · non-note files ${allFiles.length - notes.length} · links ${linkCount.wiki} wiki + ${linkCount.md} md (${linkCount.embed} embeds) · bound ${maxHops} hop(s)`)
    if (maxHops !== DEFAULT_MAX_HOPS) out.push(`  !! WEAKENED BOUND — this run graded at ${maxHops} hops, not the declared ${DEFAULT_MAX_HOPS}`)
    out.push('')
    out.push('  hop distance from Home.md')
    for (const d of [...hist.keys()].sort((a, b) => a - b)) {
      out.push(`    ${d === Infinity ? 'unreachable' : `${d} hop${d === 1 ? ' ' : 's'}`.padStart(11)}  ${String(hist.get(d)).padStart(4)}  ${'#'.repeat(Math.min(60, hist.get(d)))}`)
    }
    out.push('')
    out.push('  by directory                 notes  unreachable  >bound')
    for (const [d, e] of [...perDir.entries()].sort((a, b) => b[1].total - a[1].total)) {
      out.push(`    ${d.padEnd(26)} ${String(e.total).padStart(5)} ${String(e.unreach).padStart(12)} ${String(e.deep).padStart(7)}`)
    }
    if (unreachable.length) {
      out.push('')
      out.push(`  UNREACHABLE from Home.md (${unreachable.length})`)
      for (const n of unreachable) out.push(`    ${n}`)
    }
    if (tooDeep.length) {
      out.push('')
      out.push(`  REACHABLE BUT DEEPER THAN ${maxHops} HOP(S) (${tooDeep.length})`)
      for (const n of tooDeep) out.push(`    ${String(depth.get(n)).padStart(2)}  ${n}`)
    }
    if (dangling.length) {
      out.push('')
      out.push(`  LINKS THAT RESOLVE TO NO NOTE IN THIS VAULT (${dangling.length}), by class`)
      for (const k of ['BROKEN', 'OUT_OF_VAULT_MISSING', 'OUT_OF_VAULT_RESOLVED', 'TEMPLATE_PLACEHOLDER']) {
        const rows = dangling.filter((d) => d.klass === k)
        if (!rows.length) continue
        out.push(`    ${k} (${rows.length})`)
        for (const d of rows) {
          const known = KNOWN_BROKEN.has(`${d.from}|${d.raw}`)
          out.push(`      ${known ? 'declared' : 'NEW     '}  ${d.from}:${d.line}  ${d.raw}`)
        }
      }
    }
    process.stdout.write(out.join('\n') + '\n\n')
  }

  return { notes, allFiles, edges, depth, unreachable, tooDeep, dangling, linkCount, hasRoot: notes.includes(ROOT) }
}

// ---- selftest: the positive controls ----------------------------------------
// Two of them, because this gate has two ways to be vacuous: a parser that finds
// no links (everything unreachable — loud), and a parser or bound that finds
// everything fine when it is not (silent). The fixtures are written here, graded
// here, and deleted here; nothing under vault/ is touched (gate-independence §10).
function selftest() {
  // --- 1. the parser, on conventions THIS AUTHOR DID NOT INVENT --------------
  const sample = [
    'bare [[Vision]] and path [[Design/ui-system]] and deep [[Reports/audits/SESSION-REGISTRY]]',
    'base [[Sessions.base#Recent]] embed ![[Design.base#By status]] alias [[Missions/first-mission|the loop]]',
    'heading [[Decisions/0005-generator-search#Rule]] and md [](Reports/F-1.md) and [x](https://e.com)',
    'NOT a link: `api/share/[[...path]].ts`',
    '```yaml',
    'supersedes: "[[...]]"',
    '```',
  ].join('\n')
  const parsed = parseLinks(sample)
  const targets = parsed.map((l) => l.target)
  check('parser: the six wikilink conventions in this vault all parse',
    ['Vision', 'Design/ui-system', 'Reports/audits/SESSION-REGISTRY', 'Sessions.base', 'Design.base', 'Missions/first-mission', 'Decisions/0005-generator-search'].every((t) => targets.includes(t)),
    targets.join(' · '))
  check('parser: an ALIAS is stripped from the target and kept',
    parsed.find((l) => l.target === 'Missions/first-mission')?.alias === 'the loop')
  check('parser: a HEADING fragment is stripped from the target and kept',
    parsed.find((l) => l.target === 'Decisions/0005-generator-search')?.frag === 'Rule')
  check('parser: an EMBED is flagged and its target is the file',
    parsed.find((l) => l.target === 'Design.base')?.embed === true)
  check('parser: a markdown link is an edge, an http link is not',
    targets.includes('Reports/F-1.md') && !targets.some((t) => t.includes('e.com')))
  check('parser: `api/share/[[...path]].ts` in a CODE SPAN is NOT a link',
    !targets.some((t) => t.includes('...path')), `saw: ${targets.filter((t) => t.includes('.')).join(' ')}`)
  check('parser: supersedes: "[[...]]" inside a YAML FENCE is NOT a link',
    !targets.includes('...'), targets.join(' · '))
  // A DOUBLE-backtick span, which is how you quote a code span containing a
  // backtick. The naive /`+[^`\n]*`+/ pairs the opening `` with the inner ` and
  // leaves the wikilink exposed; vault/CLAUDE.md contains that exact sentence.
  const dbl = parseLinks('so `` `[[Design/x]]` `` renders as text, and [[Vision]] does not')
  check('parser: a DOUBLE-backtick code span hides its wikilink, and the one after it still parses',
    dbl.length === 1 && dbl[0].target === 'Vision', dbl.map((l) => l.target).join(' · ') || '(none)')

  // --- 2. the DEPTH bound, which the live vault cannot guard -----------------
  const dir = mkdtempSync(join(tmpdir(), 'vault-reach-'))
  const w = (p, s) => { mkdirSync(dirname(join(dir, p)), { recursive: true }); writeFileSync(join(dir, p), s) }
  w('Home.md', 'hub: [[Hub]]\n')
  w('Hub.md', 'mid: [[Sub/mid]]\n')
  w('Sub/mid.md', 'deep: [[Sub/deep]]\n')
  w('Sub/deep.md', 'nothing\n')
  const g3 = grade(dir, { quiet: true, maxHops: 2 })
  check('depth: a fixture whose ONLY defect is depth (every link resolves) is caught',
    g3.dangling.length === 0 && g3.unreachable.length === 0 && g3.tooDeep.length === 1,
    `dangling ${g3.dangling.length} · unreachable ${g3.unreachable.length} · tooDeep ${g3.tooDeep.length}`)
  check('depth: …and it is named — the gate says WHICH note is too deep',
    g3.tooDeep[0] === 'Sub/deep.md', String(g3.tooDeep[0]))
  const g99 = grade(dir, { quiet: true, maxHops: 99 })
  check('depth: …and raising the bound to 99 CLEARS it — the bound is what red it',
    g99.tooDeep.length === 0, `tooDeep at 99 hops: ${g99.tooDeep.length}`)

  // --- 3. the non-vacuity guard itself --------------------------------------
  const empty = mkdtempSync(join(tmpdir(), 'vault-reach-empty-'))
  const ge = grade(empty, { quiet: true })
  check('vacuity: a vault with NO notes is not graded green — it has no Home.md',
    ge.notes.length === 0 && ge.hasRoot === false)
  rmSync(dir, { recursive: true, force: true })
  rmSync(empty, { recursive: true, force: true })
}

// ---- run --------------------------------------------------------------------
if (!existsSync(VAULT) || !statSync(VAULT).isDirectory()) {
  console.error(`vault-reachability: not a directory: ${VAULT}`)
  process.exit(2)
}

if (SELFTEST) {
  selftest()
  process.stdout.write(results.join('\n') + '\n')
  process.stdout.write(`\nVAULT-REACHABILITY SELFTEST ${failing ? 'FAIL' : 'PASS'} (${checks} checks, ${failing} failing)\n`)
  process.exit(failing ? 1 : 0)
}

const g = grade(VAULT)

// The guard, in the assertion's own units. "Every note is reachable" is satisfied
// by a vault with one note, or by a parser that found no notes at all; both would
// be green and neither would have measured anything.
if (g.notes.length < 2 || !g.hasRoot) {
  console.error(`vault-reachability: REFUSED — ${g.notes.length} note(s), Home.md ${g.hasRoot ? 'present' : 'ABSENT'}. Nothing to grade.`)
  process.exit(2)
}
if (g.linkCount.wiki + g.linkCount.md === 0) {
  console.error('vault-reachability: REFUSED — parsed 0 links across every note. The parser, not the vault, is the finding.')
  process.exit(2)
}

check(`the vault has notes to grade and a Home.md to start from`,
  g.notes.length >= 2 && g.hasRoot, `${g.notes.length} notes · ${g.linkCount.wiki + g.linkCount.md} links`)
check(`every note is REACHABLE from Home.md`,
  g.unreachable.length === 0, `${g.unreachable.length} unreachable of ${g.notes.length}`)
check(`every note is within ${MAX_HOPS} hop(s) of Home.md`,
  g.tooDeep.length === 0, `${g.tooDeep.length} deeper than ${MAX_HOPS} of ${g.notes.length}`)
// Two rows, because "dangling" was never one quantity. The first is the tooth:
// a break nobody declared. The second is the ratchet's own honesty — it names
// what is owed rather than tolerating a number.
const undeclared = g.dangling.filter((d) => (d.klass === 'BROKEN' || d.klass === 'OUT_OF_VAULT_MISSING') && !KNOWN_BROKEN.has(`${d.from}|${d.raw}`))
check(`no UNDECLARED broken link — every unresolved target is known debt or out-of-vault-and-present`,
  undeclared.length === 0,
  undeclared.length ? undeclared.map((d) => `${d.from}:${d.line} ${d.raw}`).join('\n          ') : `${g.dangling.length} unresolved, all classified`)
const declaredSeen = g.dangling.filter((d) => KNOWN_BROKEN.has(`${d.from}|${d.raw}`)).length
results.push(`  NOTE  DECLARED DEBT: ${declaredSeen} link(s) matching ${KNOWN_BROKEN.size} pinned break(s) are still open — each is owed a repair, not a tolerance`)
if (MAX_HOPS !== DEFAULT_MAX_HOPS) {
  check(`the declared bound is ${DEFAULT_MAX_HOPS} hops — this run WEAKENED it to ${MAX_HOPS}`, false,
    'a run at a bound other than the declared one is not a verdict on this vault')
}

process.stdout.write(results.join('\n') + '\n')
process.stdout.write(`\nVAULT-REACHABILITY ${failing ? 'FAIL' : 'PASS'} (${checks} checks, ${failing} failing) — ${relative(REPO, VAULT) || VAULT}\n`)
process.exit(failing ? 1 : 0)
