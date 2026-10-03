#!/usr/bin/env python3
"""Generate vault/Map-code.md from the graphify code graph.

WHY THIS IS GENERATED. vault/Map.md maps the notes; nothing mapped the code, so
"which code is where" was answered by prose and then grep. A hand-written code map
drifts the first time a file moves. So, once a knowledge graph exists (`/graphify`,
written to graphify-out/graph.json), this page is derived from the AST graph and is
re-runnable. Until then vault/Map-code.md is the hand-kept skeleton the kit ships, and
the rule is: update its row in the same change that adds, moves or retires an area.

  python3 scripts/gen-code-map.py            # write vault/Map-code.md (needs the graph)
  python3 scripts/gen-code-map.py --check     # 0 current · 1 stale · 77 cannot measure

Area one-liners ("what lives here") are the one part no generator can derive; they live
in BLURB below, one line per area, hand-written.

REFUSES an unrecognised argument by name (exit 2), like every other entry point here.
"""
import json, sys, os, re
import os as _os, time as _time, datetime as _dt, subprocess as _sp
import signal
# `| head` closes stdout early; the default SIGPIPE handling turns that into a traceback
# and a non-zero exit, so a tool that worked perfectly reports failure.
try: signal.signal(signal.SIGPIPE, signal.SIG_DFL)
except Exception: pass
import collections, datetime

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GRAPH = os.path.join(ROOT, "graphify-out", "graph.json")
OUT = os.path.join(ROOT, "vault", "Map-code.md")

ACCEPTS = {"--check"}
argv = sys.argv[1:]
bad = [a for a in argv if a not in ACCEPTS]
if bad:
    print(f"gen-code-map: unrecognised argument {bad[0]!r} — accepts: {' '.join(sorted(ACCEPTS))}")
    raise SystemExit(2)
CHECK = "--check" in argv

if not os.path.exists(GRAPH):
    # No graph on this machine is "cannot measure", not a red: graphify-out/ is a local
    # cache, and the hand-kept Map-code.md is the committed fallback. 77 is the skip
    # channel — named by the board, never tallied as a pass.
    print("gen-code-map: SKIP (77) — no graphify-out/graph.json on this machine, so the code map "
          "cannot be derived. Run /graphify to build it; until then vault/Map-code.md is hand-kept.")
    raise SystemExit(77)

# INDEPENDENCE. An earlier `--check` regenerated the page from graph.json and diffed
# the strings — and graph.json is gitignored, machine-local, and the very artifact the
# page was produced from. A stale cache certified a stale map. That is the canonical failure this
# repo has a rule about: the check's ground truth was the producer's own output.
#
# So the freshness of the CACHE is now judged against the SOURCE TREE, which git
# tracks and the cache does not come from.
import subprocess
CODE_EXT = ("rs", "ts", "tsx", "js", "jsx", "mjs", "cjs", "py", "go", "rb", "java", "kt", "swift", "c", "cc", "cpp", "h", "hpp", "cs", "sql", "sh")
def _newest_tracked_source():
    # A FAILURE HERE IS "CANNOT MEASURE", NOT "NOTHING IS NEWER".
    #
    # This returned (None, None) on any git failure, which made STALE False, which sent
    # the check on to GRADE THE PAGE against a cache it could not prove was fresh. Found
    # by sabotage: git off PATH produced `STALE`, exit 1, a confident red from a check
    # that had established nothing.
    #
    # `False` is the third answer, distinct from a real (None, None) "git answered and
    # nothing matched", and the caller REFUSES on it.
    try:
        r = subprocess.run(["git", "ls-files"],
                           cwd=ROOT, capture_output=True, text=True, timeout=30)
        if r.returncode != 0:
            return False, False
        files = r.stdout.split("\n")
    except Exception:
        return False, False
    newest, when = None, 0
    for f in files:
        if not f or f.startswith(("vault/", "evidence/")) or not f.split(".")[-1] in CODE_EXT:
            continue
        fp = os.path.join(ROOT, f)
        try:
            m = os.path.getmtime(fp)
        except OSError:
            continue
        if m > when:
            newest, when = f, m
    return newest, when

GRAPH_MTIME = os.path.getmtime(GRAPH)
_newest_file, _newest_when = _newest_tracked_source()
if _newest_file is False:
    print("gen-code-map: REFUSED — `git ls-files` did not answer, so the freshness of "
          "graphify-out/graph.json cannot be established. Grading the page against a cache "
          "that cannot be dated would certify it on no evidence. Not a red: nothing was "
          "measured.", file=sys.stderr)
    raise SystemExit(2)
STALE = bool(_newest_when and _newest_when > GRAPH_MTIME)

g = json.load(open(GRAPH, encoding="utf-8"))
nodes = g["nodes"]
byid = {n["id"]: n for n in nodes}
edges = g.get("edges") or g.get("links") or []

deg = collections.Counter()
for e in edges:
    for k in ("source", "target"):
        v = e.get(k)
        if isinstance(v, dict): v = v.get("id")
        if v: deg[v] += 1

# ---- area = the first two path components, which is how people talk about it ----
def area(sf):
    """Two components, unless the second IS a file — `bench/assert-build.mjs` is a
    file in `bench`, not an area of its own, and listing it as one produced a table
    where eight of sixteen rows were single files."""
    if not sf: return "(unknown)"
    p = sf.split("/")
    if len(p) == 1: return "(root)"
    if "." in p[1]: return p[0]
    return "/".join(p[:2])

areas = collections.defaultdict(lambda: {"files": set(), "nodes": 0})
for n in nodes:
    sf = n.get("source_file") or ""
    a = area(sf)
    areas[a]["nodes"] += 1
    if sf: areas[a]["files"].add(sf)

comm = collections.defaultdict(list)
for n in nodes:
    c = n.get("community")
    if c is not None: comm[str(c)].append(n)

L = []
w = L.append
w("---"); w("type: dashboard"); w("status: current")
w("date: @@MAP-DATE@@"); w("updated: @@MAP-DATE@@"); w("---"); w("")
w("# Map of this codebase"); w("")
w("Which code is where, derived from the AST graph rather than written by hand — "
  "[[Map]] does this for the vault's notes, this does it for the source. Regenerate with "
  "`python3 scripts/gen-code-map.py`; `--check` fails if it has drifted.")
w("")
w("> [!note] Signpost only.")
w("> Adds no decision or scope. It says where things are so the next reader — human or "
  "agent — does not re-derive it by grepping. It is a STRUCTURE map: \"who already "
  "implements X?\" is `node scripts/where.mjs <name> --branches` ([[AGENTS]] §1).")
w("")
w(f"Graph built {datetime.date.fromtimestamp(GRAPH_MTIME)}"
  + (f" — **STALE**: `{_newest_file}` is newer, so re-run `/graphify`." if STALE else "")
  + f". **{len(nodes):,} symbols** over "
  f"**{len({n.get('source_file') for n in nodes if n.get('source_file')}):,} files**, "
  f"{len(edges):,} edges, {len(comm)} clusters.")
w("")
w("## Areas — the top level")
w("")
w("| area | files | symbols | what lives here |")
w("|---|---|---|---|")
BLURB = {
 # "<area>": "<one line: what lives here, and why it matters>",
 "scripts": "The org's tooling: propose, plan-row, where, vault-hubs, loop-state, the index generators.",
 "scripts/gates": "The org's board — vault, plan, ownership and anti-sprawl gates; `org-board.sh` runs them all.",
 "scripts/lib": "One owner per shared derivation: protected paths, landing range, commit trailers, argv, git env.",
 "scripts/hooks": "The PreToolUse contract hook and its falsification suite.",
}
for a, d in sorted(areas.items(), key=lambda kv: -len(kv[1]["files"]))[:16]:
    if not d["files"]: continue
    w(f"| `{a}` | {len(d['files'])} | {d['nodes']} | {BLURB.get(a,'')} |")
w("")
# A node whose label IS the basename of its own source file is the FILE, not a symbol
# in it. Ranking the two together put `tests.rs` at number one under a heading that
# says "symbols", and counted `Editor` and `Editor.ts` as two things.
def is_file_node(n):
    """A node standing for a FILE, not a symbol in one.

    Three shapes, all seen on this tree: the bare basename (`tests.rs`), the full
    source path, and a PARTIAL path (`core/src/lib.rs` for
    `pkg/core/src/lib.rs`). Matching only the first two left two file rows in a
    table headed 'symbols'."""
    sf = (n.get("source_file") or "").strip()
    lab = (n.get("label") or "").strip()
    if not sf or not lab:
        return False
    return lab == sf or lab == os.path.basename(sf) or sf.endswith("/" + lab)

def is_test(n):
    sf = (n.get("source_file") or "").lower()
    return ("test" in os.path.basename(sf)) or "/tests/" in sf or ".test." in sf

w("## Core abstractions — the most connected SYMBOLS")
w("")
w("A change to one of these reaches furthest. File nodes and test files are excluded: "
  "ranking them together put `tests.rs` first under a heading that says *symbols*, which "
  "pointed the reader at the one file where a change reaches nothing in the product.")
w("")
w("| symbol | edges | defined in |")
w("|---|---|---|")
shown = 0
for nid, dcount in deg.most_common(4000):
    n = byid.get(nid)
    # A node with NO source_file is external — `Result`, `JsValue`, stdlib types the
    # AST saw referenced but never saw defined. They are not this codebase's abstractions
    # and listing them as such is the same category error as listing filenames.
    if not n or not (n.get("source_file") or "").strip(): continue
    if is_file_node(n) or is_test(n): continue
    w(f"| `{n.get('label', nid)}` | {dcount} | `{n.get('source_file','?')}` |")
    shown += 1
    if shown >= 12: break
w("")
w("## Files by total reach")
w("")
w("The same degree, aggregated over every symbol a file defines — the file-level answer "
  "to the same question. Test files are marked rather than dropped, because a test file "
  "with enormous reach is a fact about the suite.")
w("")
w("| file | total edges | |")
w("|---|---|---|")
fdeg = collections.Counter()
ftest = {}
for nid, dcount in deg.items():
    n = byid.get(nid)
    if not n: continue
    sf = n.get("source_file")
    if not sf: continue
    fdeg[sf] += dcount
    ftest[sf] = is_test(n)
for sf, dcount in fdeg.most_common(12):
    w(f"| `{sf}` | {dcount} | {'*(tests)*' if ftest.get(sf) else ''} |")
w("")
w("## Clusters — what groups with what")
w("")
w("Named clusters only; the long tail of small ones is in `graphify-out/GRAPH_REPORT.md`.")
w("")
w("| cluster | symbols | area | start at |")
w("|---|---|---|---|")
# NAMES ARE DERIVED, NOT STORED. They used to come from a hand-written {cluster id: name}
# map in graphify-out/.graphify_labels.json. Cluster ids are NOT STABLE across clustering
# runs: refreshing the graph moved 385 clusters to 387 and every stored name slid onto a
# different cluster — "Rust Document Model" ended up pointing at circulation.rs and
# "Cloud Auth & Persistence" at layout/tests.rs. The page was wrong in a way no reader
# could detect, because the names still READ plausibly. A name computed from the cluster's
# own contents cannot slide off it.
def cluster_name(ns, top=None):
    """Named after the file the reader should OPEN — the same file the `start at`
    column gives, so a row cannot name one file and point at another."""
    if not top:
        files = collections.Counter((n.get("source_file") or "") for n in ns if n.get("source_file"))
        if not files: return "(unsourced)"
        top = files.most_common(1)[0][0]
    d = os.path.dirname(top)
    stem = os.path.splitext(os.path.basename(top))[0]
    return f"`{d or '.'}` — {stem}"
named = [(cid, ns) for cid, ns in comm.items() if len(ns) >= 40]
for cid, ns in sorted(named, key=lambda kv: -len(kv[1])):
    pass
    files = collections.Counter(area(n.get("source_file") or "") for n in ns)
    # the file to OPEN. A cluster row that names only an area sends the reader to grep;
    # this is the highest-degree member's file, which is where the cluster actually lives.
    sourced = [n for n in ns if (n.get("source_file") or "").strip()]
    best = max(sourced, key=lambda n: deg.get(n["id"], 0)) if sourced else None
    bf = best.get("source_file") if best else None
    where = f"`{bf}`" if bf else "—"
    w(f"| {cluster_name(ns, bf)} | {len(ns)} | `{files.most_common(1)[0][0]}` | {where} |")
w("")
w("## What this map cannot see")
w("")
w("It holds no lines-of-code, no entry points, and no constants, and it cannot see edges "
  "a language boundary hides (generated bindings, RPC, string-dispatched calls). For those, "
  "read the boundary module itself.")
w("")
w("## Asking it questions")
w("")
w("The graph answers more than this page holds:")
w("")
w("```bash")
w('graphify query "what depends on <Symbol>?"')
w('graphify path "<A>" "<B>"        # shortest path between two concepts')
w('graphify explain "<Symbol>"')
w("```")
w("")
w("`graphify-out/` is gitignored and local to each machine — it is a cache, not a record. "
  "This page is the committed part, which is why it is small.")
w("")
body = "\n".join(L) + "\n"
# THE DATE IS NOT A CHANGE: compare with the two frontmatter stamps normalised, and stamp
# today's date only when the content really changed.
_norm = lambda t: re.sub(r"(?m)^(date|updated): \d{4}-\d{2}-\d{2}$", r"\1: @@MAP-DATE@@", t).strip()
_cur_raw = open(OUT, encoding="utf-8").read() if os.path.exists(OUT) else ""
_same = bool(_cur_raw) and _norm(_cur_raw) == _norm(body)

if CHECK:
    # TWO different staleness questions, and conflating them made this check useless.
    #   page vs graph   -> the committed page is out of date. Actionable, and RED.
    #   graph vs source -> the local cache is older than the code, so this check CANNOT
    #                      MEASURE whether the page is current. That is not a red, it is
    #                      a step that could not run: exit 77, the repo's declared skip
    #                      channel (scripts/gates/org-board.sh), which the board counts and names but never
    #                      tallies as a pass.
    # Exiting 1 for both meant the check went red every time anyone edited any source
    # file — and a check that is red by default is a check nobody reads.
    if STALE:
        # A SKIP THAT CANNOT SAY HOW BAD IT IS INVITES INDEFINITE TOLERANCE: a board row
        # reading SKIP looks the same on its first day and its thirtieth. So the skip
        # quantifies itself.
        #
        # So the skip quantifies itself, and it does so from GIT rather than from the
        # graph — the artifact it is complaining about cannot also be the witness for how
        # stale it is. The drift is a differential (files ADDED since the graph's mtime),
        # not a comparison of two file counts, because `find` predicates are not
        # graphify's extraction rules and comparing them would be two populations wearing
        # one number.
        _age_h = max(0.0, (_time.time() - _os.path.getmtime(GRAPH)) / 3600.0) if _os.path.exists(GRAPH) else 0.0
        _added = []
        try:
            _since = _dt.datetime.fromtimestamp(_os.path.getmtime(GRAPH)).strftime("%Y-%m-%d %H:%M")
            _out = _sp.run(["git", "log", f"--since={_since}", "--diff-filter=A",
                            "--name-only", "--pretty=format:"],
                           cwd=ROOT, capture_output=True, text=True, timeout=30).stdout
            _added = sorted({l for l in _out.split("\n")
                             if l.strip() and not l.startswith(("vault/", "evidence/"))
                             and l.rsplit(".", 1)[-1] in CODE_EXT})
        except Exception:
            _added = []
        print(f"gen-code-map --check: SKIP (77) — cannot measure. graphify-out/graph.json is "
              f"{_age_h:.1f} h old and older than {_newest_file}, so a match against it would "
              f"prove nothing about today's source.")
        if _added:
            print(f"  DRIFT, re-derived from git and not from the graph: {len(_added)} source "
                  f"file(s) have been ADDED since the graph was built, so the map cannot "
                  f"mention any of them:")
            for f in _added[:12]:
                print(f"    {f}")
            if len(_added) > 12:
                print(f"    … and {len(_added) - 12} more")
        else:
            print("  DRIFT: no source file has been ADDED since the graph was built; the "
                  "staleness is edits to existing files only.")
        print("  The map is a NAVIGATION aid (areas, clusters, degree). It is NOT the answer "
              "to \"who already implements X\" — vault/AGENTS.md routes that to "
              "`node scripts/where.mjs <name>`, which answers from git grep and is unaffected "
              "by this cache. Re-run /graphify, then this script.")
        raise SystemExit(77)
    if _same:
        print("gen-code-map --check: vault/Map-code.md is current (and the graph is no older "
              "than the newest tracked source file)"); raise SystemExit(0)
    print("gen-code-map --check: vault/Map-code.md is STALE — re-run without --check"); raise SystemExit(1)

_prev = re.search(r"(?m)^date: (\d{4}-\d{2}-\d{2})$", _cur_raw) if _same else None
body = body.replace("@@MAP-DATE@@", _prev.group(1) if _prev else str(datetime.date.today()))
open(OUT, "w", encoding="utf-8").write(body)
print(f"wrote {OUT} ({len(body):,} bytes)")
