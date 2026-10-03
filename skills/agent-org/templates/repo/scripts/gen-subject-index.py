#!/usr/bin/env python3
"""Generate vault/Index.md — "has this been done before?", answered without grep.

WHAT IT FIXES. vault/Map.md says WHERE every note is. It does not say WHAT WAS DECIDED, so
an agent asking "did we already settle this?" greps every report and session. This indexes
the answers: every decision, report and session by subject, with its date and status, so
the question costs one page instead of a search. It is the first stop of the search order
in vault/AGENTS.md (Index → where.mjs → git grep → branches).

WHY A SECOND GENERATOR. scripts/vault-hubs.mjs lists where notes ARE (Map, folder hubs);
this lists what they ANSWERED. They share no logic, so folding them together would couple
two unrelated derivations behind one flag.

  python3 scripts/gen-subject-index.py           # write vault/Index.md
  python3 scripts/gen-subject-index.py --check   # exit 1 if stale
"""
import os, re, sys
import signal
# `| head` closes stdout early; the default SIGPIPE handling turns that into a traceback
# and a non-zero exit, so a tool that worked perfectly reports failure.
try: signal.signal(signal.SIGPIPE, signal.SIG_DFL)
except Exception: pass
import collections, datetime

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
VAULT = os.path.join(ROOT, "vault")
OUT = os.path.join(VAULT, "Index.md")

ACCEPTS = {"--check"}
argv = sys.argv[1:]
bad = [a for a in argv if a not in ACCEPTS]
if bad:
    print(f"gen-subject-index: unrecognised argument {bad[0]!r} — accepts: {' '.join(sorted(ACCEPTS))}")
    raise SystemExit(2)
CHECK = "--check" in argv

DATE_TOKEN = "@@INDEX-DATE@@"
DATE_RE = re.compile(r"\d{4}-\d{2}-\d{2}")
VOLATILE_BEGIN = "<!-- INDEX:VOLATILE-BEGIN — git branch state; not graded by --check -->"
VOLATILE_END = "<!-- INDEX:VOLATILE-END -->"

SKIP_DIRS = (".obsidian", "_log")
notes = []
for r, d, fs in os.walk(VAULT):
    if any(x in r for x in SKIP_DIRS):
        continue
    for f in sorted(fs):
        if not f.endswith(".md"):
            continue
        p = os.path.join(r, f)
        rel = os.path.relpath(p, VAULT)[:-3]
        if rel in ("Index", "Map", "Map-code") or rel.endswith("README") or rel == "CLAUDE":
            continue
        try:
            t = open(p, encoding="utf-8").read()
        except Exception:
            continue
        fm = {}
        m = re.match(r"^---\n(.*?)\n---\n", t, re.S)
        if m:
            for line in m.group(1).split("\n"):
                if ":" in line:
                    k, v = line.split(":", 1)
                    fm[k.strip()] = v.strip().strip('"')
        body = t[m.end():] if m else t
        h1 = re.search(r"^#\s+(.+)$", body, re.M)
        title = h1.group(1).strip() if h1 else rel.split("/")[-1]
        # the first sentence that is prose, not a heading, quote, table or list
        gist = ""
        for para in body.split("\n\n"):
            s = para.strip()
            if not s or s[0] in "#>|-*!" or s.startswith("```"):
                continue
            s = re.sub(r"\s+", " ", s)
            # The gist is the note's own first sentence, quoted. If that sentence contains
            # a link, copying it verbatim RELOCATES the link into this page, where its
            # relative target no longer resolves — one such line was the last broken link
            # this page introduced. Keep the words, drop the linkage.
            s = re.sub(r"\[\[([^\]|]+)\|([^\]]+)\]\]", r"\2", s)   # [[a|b]] -> b
            s = re.sub(r"\[\[([^\]]+)\]\]", r"\1", s)               # [[a]]   -> a
            s = re.sub(r"\[([^\]]*)\]\([^)]*\)", r"\1", s)          # [t](u)  -> t
            s = re.sub(r"\s+", " ", s).strip()
            if not s:
                continue
            gist = s[:190] + ("…" if len(s) > 190 else "")
            break
        notes.append({"rel": rel, "title": title, "gist": gist,
                      "type": fm.get("type", "?"), "status": fm.get("status", "?"),
                      "date": fm.get("date", ""), "updated": fm.get("updated", "")})


# A wikilink with an alias cannot live in a Markdown TABLE cell: the pipe splits the
# cell, and escaping it as `\|` makes the resolver read the backslash as part of the
# target — which silently broke all 129 links the first version of this page emitted,
# caught by scripts/gates/vault-reachability.mjs. So links here carry NO alias, and the
# title gets its own column. A bare basename is used when it is unique vault-wide
# (Obsidian resolves those), and the full path when it is not.
_basenames = collections.Counter(n["rel"].split("/")[-1] for n in notes)
def link(rel):
    base = rel.split("/")[-1]
    return f"[[{base}]]" if _basenames[base] == 1 else f"[[{rel}]]"

by_type = collections.defaultdict(list)
for n in notes:
    by_type[n["type"]].append(n)

L = []
w = L.append
w("---"); w("type: dashboard"); w("status: current")
w(f"date: {DATE_TOKEN}"); w(f"updated: {DATE_TOKEN}"); w("---"); w("")
w("# Index — what has already been decided, measured or tried")
w("")
w("[[Map]] says where every note IS. This says what each note ANSWERED, so "
  "*\"have we done this before?\"* costs one page instead of a grep over every report and "
  "session. Generated by `python3 scripts/gen-subject-index.py`; `--check` fails "
  "when it has drifted.")
w("")
w("> [!note] Signpost only.")
w("> Every line is the note's own first sentence, unedited. Nothing here is a new claim; "
  "if a line reads oddly, the note says it oddly.")
w("")
w(f"Measured {DATE_TOKEN}: **{len(notes)} notes** carrying an answer.")
w("")
# ---- THE PROMOTED-LESSONS BLOCK: hand-kept, carried verbatim ------------------
# The overseer promotes lane-local lessons that hold beyond the lane (tried and rejected,
# measured, decided) from lanes/*/lane-memory.md into this page, one line each. This page is
# otherwise generated, so those lines live between two markers and are CARRIED VERBATIM from
# the page on disk on every regeneration — never derived, never dropped. --check compares the
# carried block with itself, so a promotion never reads as staleness; and the generated half
# around it is still graded in full.
PROMOTED_BEGIN = "<!-- INDEX:PROMOTED-BEGIN — hand-kept by the overseer; carried verbatim -->"
PROMOTED_END = "<!-- INDEX:PROMOTED-END -->"
_existing = open(OUT, encoding="utf-8").read() if os.path.exists(OUT) else ""
_pa, _pb = _existing.find(PROMOTED_BEGIN), _existing.find(PROMOTED_END)
if _pa != -1 and _pb > _pa:
    _promoted = _existing[_pa + len(PROMOTED_BEGIN):_pb].strip("\n")
else:
    _promoted = ("*One line per lesson, newest last: `- YYYY-MM-DD · <lane> · <what was tried, measured or "
                 "rejected> — evidence: <path>`. Promoted by the overseer from `lanes/*/lane-memory.md`.*")
w("## Promoted lessons — from the lanes")
w("")
w(PROMOTED_BEGIN)
w(_promoted)
w(PROMOTED_END)
w("")
w("## Read these first — they bind")
w("")
w("Decisions are law until superseded. Everything else describes; these DECIDE.")
w("")
w("| decision | title | status | what it settles |")
w("|---|---|---|---|")
for n in sorted(by_type.get("decision", []), key=lambda n: n["rel"]):
    w(f"| {link(n['rel'])} | {n['title'][:70].replace('|','/')} | {n['status']} | {n['gist'][:140].replace('|','/')} |")
w("")
ORDER = [("report", "Reports — what was measured"),
         ("design", "Design — how it should work"),
         ("mission", "Missions — what a push was for"),
         ("research", "Research — what exists outside this repo"),
         ("session", "Sessions — what a day did"),
         ("capture", "Captures — what the owner sent in")]
for t, heading in ORDER:
    rows = by_type.get(t, [])
    if not rows:
        continue
    w(f"## {heading}  ({len(rows)})")
    w("")
    w("| note | title | status | date | gist |")
    w("|---|---|---|---|---|")
    for n in sorted(rows, key=lambda n: (n["date"] or "0000", n["rel"]), reverse=True):
        g = n["gist"][:120].replace("|", "/")
        w(f"| {link(n['rel'])} | {n['title'][:58].replace('|','/')} | {n['status']} | {n['date']} | {g} |")
    w("")
# The vault's navigation notes (Home, AGENTS, Plan, Roadmap, Vision, Architecture …) carry
# declared types that answer no question by themselves — they ARE the routing. They are not
# contract violations, so they are not listed as uncategorised.
NAVIGATION = {"dashboard", "plan", "roadmap", "vision", "spec"}
other = [t for t in by_type if t not in dict(ORDER) and t != "decision" and t not in NAVIGATION]
if other:
    w("## Uncategorised — a note whose `type:` is missing or unknown")
    w("")
    w("Each of these is a vault-contract violation: `type:` is required frontmatter. "
      "Listed so they are visible rather than silently unindexed.")
    w("")
    for t in sorted(other):
        for n in sorted(by_type[t], key=lambda n: n["rel"]):
            w(f"- {link(n['rel'])} {n['title'][:70].replace('|','/')} — `type: {t}`")
    w("")
# ---- the two places prior art actually lives that vault notes do NOT cover -------
# A probe agent asked for prior work found it in .claude/rules/gate-independence.md and on
# an unlanded branch, and this index gave it NOTHING while claiming to answer "has this been
# done before".
import subprocess

def _sh(args, timeout=30):
    try:
        return subprocess.run(args, cwd=ROOT, capture_output=True, text=True, timeout=timeout).stdout
    except Exception:
        return ""

w("## The laws — binding, and NOT vault notes")
w("")
w("`.claude/rules/*.md` is auto-loaded (gate-independence when a gate, hook, test or evidence file is "
  "touched), so it is the one place prior art is read without being looked for. Its worked cases live in "
  "[[Design/gate-independence-cases]].")
w("")
rules_dir = os.path.join(ROOT, ".claude", "rules")
laws = []
if os.path.isdir(rules_dir):
    for f in sorted(os.listdir(rules_dir)):
        if not f.endswith(".md"):
            continue
        t = open(os.path.join(rules_dir, f), encoding="utf-8").read()
        for m in re.finditer(r"^\d+\.\s+\*\*(.+?)\*\*\s+—\s*(.+)$", t, re.M):
            laws.append((f, m.group(1).strip(), m.group(2).strip()))
if laws:
    w("| law | what it says |")
    w("|---|---|")
    for _f, title, gist in laws:
        w(f"| {title[:80].replace('|', '/')} | {gist[:120].replace('|', '/')} |")
else:
    w("*(no numbered laws parsed — check `.claude/rules/`)*")
w("")

# ---- THE VOLATILE BLOCK, AND WHY `--check` DOES NOT GRADE IT ------------------
# Everything above is derived from the VAULT: note frontmatter, headings, the rules
# files. It changes when somebody writes a note, which is exactly what `--check`
# should catch. What follows is derived from GIT BRANCH STATE, which changes for
# reasons that have nothing to do with the vault — and when `--check` compared it too,
# creating one branch that touched nothing flipped the gate to STALE, and deleting it
# flipped it back. Not one vault byte moved in either direction.
#
# The cost is not the false red, it is what the false red TEACHES: a reader who
# meets this gate red for a reason the vault did not cause learns that the remedy
# is to re-run the generator without looking — which is precisely the reflex that
# makes a REAL staleness red invisible. A gate that cries wolf trains the wolf.
#
# So the block is kept (it prevents the fifth-rediscovery failure and that is worth
# more than its churn), regenerated on every write, and EXCLUDED from the equality
# `--check` performs. The page says so itself below, because a reader who assumes
# the whole page is graded is owed the truth about which half is.
w(VOLATILE_BEGIN)
w("## In flight — work that exists but is NOT on main")
w("")
w("A plan row can name a symbol that lives only on a branch. An agent that trusts `main` "
  "concludes it is missing and writes a second one — the fifth-rediscovery failure, caused "
  "by the index rather than prevented by it. Re-derived from git on every run.")
w("")
w("> [!warning] This section is NOT graded by `--check`, and everything above it is.")
w("> It is derived from git branch state, not from the vault, so it changes when a branch "
  "is created or deleted anywhere in the repo. Grading it made the gate report STALE for "
  "reasons the vault did not cause. Treat the numbers here as of the last regeneration, "
  "not as of now; treat a STALE verdict as a real claim about the vault.")
w("")
MAIN = os.environ.get("ORG_MAIN_BRANCH", "main")
GLOBS = (os.environ.get("ORG_BRANCH_GLOBS") or "lane/*").replace(",", " ").split()
def _ref_ok(ref):
    return _sh(["git", "rev-parse", "--verify", "--quiet", ref + "^{commit}"]).strip() != ""
BASE = next((r for r in ("origin/" + MAIN, MAIN) if _ref_ok(r)), None)
branches = [b.strip().lstrip("*+ ") for b in _sh(["git", "branch", "--list", *GLOBS]).splitlines() if b.strip()]
live = []
for b in branches if BASE else []:
    n = _sh(["git", "rev-list", "--count", f"{BASE}..{b}"]).strip()
    if n.isdigit() and int(n) > 0:
        files = _sh(["git", "diff", "--name-only", f"{BASE}...{b}"]).split()
        live.append((b, int(n), files))
live.sort(key=lambda x: -x[1])
glob_txt = " ".join(GLOBS)
if BASE is None:
    w(f"**No `{MAIN}` or `origin/{MAIN}` resolves**, so unlanded work cannot be measured here.")
elif live:
    w(f"**{len(live)} of {len(branches)} `{glob_txt}` branches carry commits {BASE} does not have.**")
    w("")
    w("| branch | commits | touches |")
    w("|---|---|---|")
    for b, n, files in live[:25]:
        areas = sorted({("/".join(f.split("/")[:2]) if "/" in f else f) for f in files})[:4]
        w(f"| `{b}` | {n} | {', '.join('`'+a+'`' for a in areas) or '—'} |")
    w("")
    w("Search them before you build: `node scripts/where.mjs <symbol> --branches`")
else:
    w(f"**No `{glob_txt}` branch carries a commit {BASE} lacks** (checked {len(branches)}). "
      "Everything in flight has landed.")
w("")

w(VOLATILE_END)

body = "\n".join(L) + "\n"

def _stable(t):
    """The page with its volatile block removed — what `--check` actually compares.

    Tolerant by design: a page written before the sentinels existed has neither marker
    and is compared whole, which is the correct answer for it."""
    a, b = t.find(VOLATILE_BEGIN), t.find(VOLATILE_END)
    if a == -1 or b == -1 or b < a:
        return t
    return t[:a] + t[b + len(VOLATILE_END):]

# THE STRIP IS AN ENABLING TRANSFORM AND IT IS GUARDED HERE, because a comparison that
# compares nothing passes for ever. Sabotage: `_stable()` made to return ""
# left `--check` reporting "current" WITH A NEW VAULT NOTE ON DISK — the gate went vacuous
# and nothing anywhere noticed. A widened sentinel, a stray edit, or a marker that turns up
# in the stable half would all do the same thing silently.
#
# So the stable half must still contain the page's spine. `ANCHOR` is the one heading that
# is emitted unconditionally, sits ABOVE the volatile block, and would be the first thing
# an over-broad strip removes.
ANCHOR = "## Read these first — they bind"

# THE CLOCK IS A VOLATILE INPUT TOO, and missing it is the reason this comment exists.
# The first fix fenced GIT BRANCH STATE out of the comparison and stopped there —
# it enumerated the volatile input that had just bitten me instead of asking what ALL
# the non-vault inputs are. `datetime.date.today()` was stamped into three places, so
# the gate went STALE at the next midnight with 205 notes on both sides and not one
# vault byte changed. It fired the following morning. Fixing the instance and not the
# class buys you exactly one day.
#
# The date is NOT masked, which would make a genuinely stale page look current. It is
# made HONEST: it records when the CONTENT last changed, not when the generator last
# ran. A measurement taken on the 18th is still true on the 19th if nothing moved, so
# the old date is carried over; the moment the content differs, today's date is stamped.
def _nodate(t):
    """Normalise ONLY the three clock stamps this page emits — never a date in the data.

    The first attempt was `DATE_RE.sub(TOKEN, t)` over the whole page, and the spine
    guard below caught it on the first run: it rewrote **242** dates, not 3, because
    every row of every note table carries a `date` column. That version would have
    erased a whole class of real drift — a note's date changing is exactly the kind of
    thing this gate exists to see — while printing "current" for ever. Narrow, anchored
    patterns, and the guard stays to hold them to 3."""
    t = re.sub(r"(?m)^(date|updated): \d{4}-\d{2}-\d{2}\s*$", r"\1: " + DATE_TOKEN, t)
    return re.sub(r"Measured \d{4}-\d{2}-\d{2}:", "Measured " + DATE_TOKEN + ":", t)

def _graded(t):
    """What `--check` compares: the vault-derived half, with the clock normalised."""
    return _nodate(_stable(t)).strip()

_cur_raw = open(OUT, encoding="utf-8").read() if os.path.exists(OUT) else ""
_unchanged = bool(_cur_raw) and _graded(_cur_raw) == _graded(body)
if _unchanged:
    _prev = DATE_RE.search(_cur_raw)
    _date = _prev.group(0) if _prev else str(datetime.date.today())
else:
    _date = str(datetime.date.today())
body = body.replace(DATE_TOKEN, _date)

if CHECK:
    cur = _cur_raw
    if ANCHOR not in _stable(body):
        print("gen-subject-index --check: REFUSED — the volatile strip removed the page's "
              f"stable spine ({ANCHOR!r} is gone), so this comparison would compare nothing.")
        raise SystemExit(2)
    # A SECOND SPINE CHECK, for the clock normalisation rather than the strip. `_nodate`
    # rewrites every ISO date it finds, and a regex widened by accident would rewrite the
    # note table's `date` column into a constant — which would hide a whole class of real
    # drift while the gate went on printing "current". If normalising removed more than
    # the three stamps this page emits, refuse rather than grade.
    if _nodate(_stable(body)).count(DATE_TOKEN) > 3:
        print(f"gen-subject-index --check: REFUSED — clock normalisation rewrote "
              f"{_nodate(_stable(body)).count(DATE_TOKEN)} dates, not the 3 stamps this page emits; "
              "it is erasing content, not the clock.")
        raise SystemExit(2)
    if _graded(cur) == _graded(body):
        print("gen-subject-index --check: vault/Index.md is current"); raise SystemExit(0)
    print("gen-subject-index --check: vault/Index.md is STALE — re-run without --check"); raise SystemExit(1)

open(OUT, "w", encoding="utf-8").write(body)
print(f"wrote {OUT} ({len(body):,} bytes, {len(notes)} notes)")
