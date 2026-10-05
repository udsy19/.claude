#!/usr/bin/env node
/**
 * PreToolUse hook: the subagent contract, ENFORCED BY DELIVERY.
 *
 * Two jobs, both on Edit/Write:
 *
 *   1. OWNERSHIP. vault/Plan.md, vault/Roadmap.md, vault/Decisions/, .claude/rules/ and
 *      .claude/settings.json belong to the supervisor and the owner (scripts/lib/protected-paths.mjs). A subagent
 *      editing them is refused and told to use scripts/propose.mjs instead.
 *      `ORG_ROLE=supervisor` (or `owner`) lifts it.
 *
 *   2. THE CONTRACT. The first Edit/Write of a session is refused ONCE, and the refusal
 *      carries vault/AGENTS.md in full. This is deliberately not "check whether the agent
 *      read it": a check like that trusts the agent to have chosen to read, and can be
 *      satisfied by a Read the agent never looked at. Delivering the text in the block
 *      message puts it in the model's context as a fact, then gets out of the way.
 *
 * CEILING, stated rather than discovered later. This gates the Edit/Write TOOLS. An agent
 * can still write a protected file through Bash (`sed -i`, a heredoc), and no PreToolUse
 * matcher on Bash can reliably tell a write from a read. That hole is closed at the LANDING
 * boundary instead, by scripts/gates/plan-ownership.mjs, which re-derives from git which
 * commits touched a protected path and what authority they claimed. Two checks at two
 * layers, neither trusting the other — which is the point.
 *
 * Exit 2 blocks the tool call and returns stderr to the model. Exit 0 allows.
 * ANY internal error exits 0 — a broken hook must not wedge the fleet, and a hook that
 * fails closed on its own bug is worse than the rule it enforces.
 */
import fs from 'node:fs'
import path from 'node:path'
import os from 'node:os'
// ONE declaration of the protected list, shared with scripts/gates/plan-ownership.mjs.
import { AUTHORS, protectedHit, workerOffLimitsHit } from '../lib/protected-paths.mjs'
import { fileURLToPath } from 'node:url'

const ROOT = process.env.CLAUDE_PROJECT_DIR ||
  path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..')

function read(p) { try { return fs.readFileSync(p, 'utf8') } catch { return null } }

let raw = ''
try { raw = fs.readFileSync(0, 'utf8') } catch { process.exit(0) }
let ev = {}
try { ev = JSON.parse(raw || '{}') } catch { process.exit(0) }

const tool = ev.tool_name || ''
if (!/^(Edit|Write|NotebookEdit|MultiEdit)$/.test(tool)) process.exit(0)

// A non-string file_path must not be a bypass. Substituting '' for it (the obvious
// "coercion") matches no protected path, so every non-string shape was silently
// unprotected — measured: ["vault/Plan.md"] and {"0":"vault/Plan.md"} both got through.
// Refusing every unrecognised shape is not available either (the hook fails OPEN), so the
// payload is SCANNED: every string anywhere in `tool_input` is checked against the same
// declaration. A normal write's path is a string and is checked alone, so an ordinary edit
// whose CONTENT mentions a protected path is never refused.
const rawTarget = ev.tool_input && (ev.tool_input.file_path ?? ev.tool_input.notebook_path)
const target = typeof rawTarget === 'string' ? rawTarget : ''
function stringsIn(v, depth = 0, out = []) {
  if (depth > 6 || out.length > 200) return out
  if (typeof v === 'string') out.push(v)
  else if (Array.isArray(v)) for (const x of v) stringsIn(x, depth + 1, out)
  else if (v && typeof v === 'object') for (const k of Object.keys(v)) stringsIn(v[k], depth + 1, out)
  return out
}
const payloadStrings = target ? [target] : stringsIn(ev.tool_input)
const role = String(process.env.ORG_ROLE || 'subagent').trim().toLowerCase()

// ---- 0. lane processes --------------------------------------------------------
// supervise.py starts every lane process with AGENT_ORG_HEADLESS=1; workers also carry
// AGENT_NAME, and their sub-agents inherit both. The LANE SUPERVISOR is read-only: its
// --tools allowlist gives it no write tool at all, and this refuses one anyway, so a changed
// allowlist cannot quietly hand the judge a pen. (The overseer also runs as ORG_ROLE=supervisor,
// but interactively, without AGENT_ORG_HEADLESS, so it is not caught here.)
const headless = !!process.env.AGENT_ORG_HEADLESS
if (headless && role === 'supervisor') {
  process.stderr.write(`REFUSED — the lane supervisor is read-only. It plans, briefs and judges; workers write.
Put what you wanted written into a worker's brief (=== AGENT ===) or ask the owner (=== ASK_OWNER ===).
`)
  process.exit(2)
}
if (headless || process.env.AGENT_NAME) {
  const off = payloadStrings.map((t) => workerOffLimitsHit(t)).find(Boolean)
  if (off) {
    process.stderr.write(`REFUSED — ${off.path} is ${off.what}, and a lane worker does not write it.
Your report is your trail: put what you learned there, and durable findings in vault/Reports/ or
vault/Research/. The overseer keeps the session notes, Home.md, the registry and memory.
`)
    process.exit(2)
  }
}

// ---- 1. ownership -----------------------------------------------------------
if (!AUTHORS.includes(role)) {
  const hit = payloadStrings.map((t) => protectedHit(t)).find(Boolean)
  if (hit) {
    process.stderr.write(
`REFUSED — ${hit.path} is ${hit.what}, and it is not yours to edit.

You are running as role "${role}". Only the supervisor and the owner write the plan, the
roadmap, the decisions, the rules and the hooks that enforce them; that is what stops five agents holding five different
ideas of what the work is.

PROPOSE it instead — this reaches the supervisor and is answered, not dropped:

  node scripts/propose.mjs --row <n> --kind <split|reorder|add|challenge|done> \\
    --why "<what you found, with the measurement that shows it>"

If you believe the APPROACH is wrong, use --kind challenge and bring a number. The
supervisor must then either reject it citing a measurement, or commission research and
record the ruling in vault/Decisions/ — see vault/AGENTS.md §4 and §5.
`)
    process.exit(2)
  }
}

// ---- 2. the contract, delivered once per session ----------------------------
const sid = (ev.session_id || 'nosession').replace(/[^A-Za-z0-9_-]/g, '')
// PER-USER: a shared directory created 0755 by one user locks every other user out of it,
// and /tmp is sticky so nobody but its owner can remove it. Measured: root made it, the
// fleet ran as a worker user, and every write of every agent was refused.
const markDir = path.join(os.tmpdir(), `org-agent-contract-${typeof process.getuid === 'function' ? process.getuid() : 'u'}`)
const mark = path.join(markDir, sid)
try {
  if (fs.existsSync(mark)) process.exit(0)
  fs.mkdirSync(markDir, { recursive: true })
  // One marker per session, forever, is thousands of files a year. Prune anything older
  // than a week; a session idle that long is simply handed the contract again.
  const weekAgo = Date.now() - 7 * 24 * 3600 * 1000
  for (const f of fs.readdirSync(markDir)) {
    try { if (fs.statSync(path.join(markDir, f)).mtimeMs < weekAgo) fs.unlinkSync(path.join(markDir, f)) } catch { /* best effort */ }
  }
} catch { process.exit(0) }

const contract = read(path.join(ROOT, 'vault/AGENTS.md'))
if (!contract) process.exit(0)   // no contract on this tree is not this hook's problem
// A delivery that cannot be RECORDED must not be made: it would be made again on every
// write, forever. That is how a hook that "fails OPEN on its own bugs" wedges a fleet.
try { fs.writeFileSync(mark, new Date().toISOString()) } catch { process.exit(0) }

process.stderr.write(
`STOP — read this once, then continue. This is your first write this session, so the
subagent contract is delivered here rather than left for you to find. Your next Edit
will not be interrupted.

${contract}
─────────────────────────────────────────────────────────────────────────────────
That was vault/AGENTS.md. Before you re-attempt this edit:
  • check [[Index]] that this was not already done, or already tried and rejected;
  • run \`node scripts/where.mjs <name> --branches\` before writing a new symbol;
  • use [[Map-code]] to find the file rather than grepping for it.
Now re-attempt the edit.
`)
process.exit(2)
