#!/usr/bin/env python3
"""promote — the org's ONE trusted promotion coordinator. Lane loops REQUEST; only this decides and executes.

  promote.py <ORG_ROOT> request merge <LANE_ROOT> <agent-branch> [--consult N]   into the lane's integration branch
  promote.py <ORG_ROOT> request land  <LANE_ROOT> <lane>/integration [--consult N]   into main
  promote.py <ORG_ROOT> done    <LANE_ROOT> [--consult N]       is the mission DONE? (derived, never asserted)
  promote.py <ORG_ROOT> dispatch <LANE_ROOT> <agent> <branch> <base> [--consult N]   the loop records a dispatch
  promote.py <ORG_ROOT> accept <AC-key> --note <text>          the OWNER accepts a manual criterion at main's tip
  promote.py <ORG_ROOT> reconcile                               finish/abort promotions a crash interrupted
  promote.py <ORG_ROOT> sync-main                               git-sync's main fast-forward/push, under the lock
Prints one JSON object: {"decision": promoted|nothing|refused|verified|not-verified|ok, "reason", "prom", "sha",
"notices": [...], "report": "<markdown>"}. Exit 0 = promoted/nothing/verified/ok, 3 = refused/not-verified, 2 = usage.

Every promotion, under one exclusive lock (ORG_ROOT/locks/promote):
  scope   merge: only a branch this lane's loop dispatched; land: only this lane's own integration branch. Never
          another lane's ref, origin/*, recovered/* or quarantine/*, nor a tip whose head is a safety-net commit.
  fresh   land: refused while main is behind or diverged from origin (fetched first); merge: the candidate also
          merges main, so integration never lags main
  build   candidate = current target + request, in a throw-away worktree (never the shared checkout); the vault
          hubs and Index are regenerated INSIDE the candidate, before anything moves
  verify  the landing gates — their CODE from main, never the candidate's — and every org.json `verify` command,
          on that exact merged tree; each result is an immutable verification record with its log stored
          content-addressed. No `verify` configured = refused: independent verification is mandatory.
  move    compare-and-swap: the target ref moves only if it still points where the candidate was built from
  record  promotion.requested → verifying → promoted | refused | aborted, in the org's canonical state (orgstate.py);
          a promotion a crash interrupted is reconciled against the ref on the next start, never replayed blind.
DONE: every acceptance criterion of the mission (the owner's table on main) has a passing acceptance verification
of main's current tree. Workers and supervisors cannot mark anything verified: only this process writes the state.
"""
import fcntl
import json
import os
import pwd
import re
import shlex
import socket
import subprocess
import sys
import tempfile
import time
from datetime import datetime, timezone

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import orgstate as S  # noqa: E402

NAME_RE = re.compile(r"^[a-z0-9][a-z0-9-]{0,40}$")
HUB_RE = re.compile(r"^vault/(.+/)?(README|Map|Index)\.md$")     # generated files: a conflict here is regenerated
SAFETY_NET = "(safety net)"                                      # subject marker of the loop's leftover commits
FORBIDDEN_PREFIXES = ("origin/", "refs/", "recovered/", "quarantine/")
GATES = (("plan-ownership", ["node", "scripts/gates/plan-ownership.mjs", "--since", "{base}", "{lane}"]),
         ("sprawl", ["node", "scripts/gates/sprawl.mjs", "--base", "{base}", "--tip", "HEAD"]),
         ("protected-paths", ["node", "scripts/gates/protected-paths.mjs"]))
ME = pwd.getpwuid(os.getuid()).pw_name
AUTH = f"proc:coordinator@{ME}"


def now():
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def run(cmd, cwd, env=None, timeout=None):
    return subprocess.run(cmd, cwd=cwd, env=env, text=True, capture_output=True, timeout=timeout)


def git(cwd, *args, check=False):
    r = run(["git", *args], cwd)
    if check and r.returncode:
        raise RuntimeError(f"git {' '.join(args)}: {(r.stderr or r.stdout).strip()[:300]}")
    return r


def out(cwd, *args):
    r = git(cwd, *args)
    return r.stdout.strip() if r.returncode == 0 else ""


def crash_point(name):
    """Fault injection for the adversarial tests: PROMOTE_CRASH_AT=<name> kills the process here, like a power cut."""
    if os.environ.get("PROMOTE_CRASH_AT") == name:
        os._exit(137)


class Org:
    def __init__(self, org_root):
        self.root = os.path.abspath(org_root)
        self.cfg = json.load(open(os.path.join(self.root, "org.json")))
        self.repo = self.cfg["repo"]
        self.main = self.cfg.get("main_branch", "main")
        self.commit_env = {**os.environ, **self.cfg.get("commit_env", {})}
        os.makedirs(os.path.join(self.root, "locks"), exist_ok=True)
        self.conn = S.open_db(self.root)

    def lock(self):
        f = open(os.path.join(self.root, "locks", "promote"), "a")
        fcntl.flock(f, fcntl.LOCK_EX)
        return f

    def ev(self, type_, entity, payload, actor="coordinator", auth=AUTH, correlation=None):
        with S.tx(self.conn):
            return S.append(self.conn, type_, entity, actor, auth, payload, correlation=correlation)


def lane_of(lane_root):
    lane = json.load(open(os.path.join(lane_root, "lane.json")))
    prefix = lane.get("branch_prefix", f"lane/{lane['name']}")
    return lane, prefix, f"{prefix}/integration"


# ── evidence ────────────────────────────────────────────────────────────────────────────────────────────────
def verification(org, prom, kind, name, cmd, cwd, tree, commit, timeout, env=None, ac=None, actor="coordinator", auth=AUTH):
    """Run one check on the exact tree and record it (with its log, content-addressed). -> (VER id, exit, tail)."""
    started = now()
    try:
        r = run(cmd if isinstance(cmd, list) else ["bash", "-c", cmd], cwd, env=env, timeout=timeout)
        code, text = r.returncode, (r.stdout or "") + (r.stderr or "")
    except subprocess.TimeoutExpired as e:
        code, text = 124, f"{e.stdout or ''}{e.stderr or ''}\n[timed out after {timeout}s]"
    ended = now()
    with tempfile.NamedTemporaryFile("w", delete=False, suffix=".log") as f:
        f.write(f"$ {cmd if isinstance(cmd, str) else shlex.join(cmd)}\n# tree {tree} commit {commit}\n# exit {code}\n{text}")
    with S.tx(org.conn):
        ver = S.next_id(org.conn, "VER")
        evd, _ = S.put_artifact(org.conn, org.root, f.name, actor, auth, produced_by=ver, correlation=prom)
        S.append(org.conn, "verification.recorded", ver, actor, auth,
                 {"promotion": prom, "kind": kind, "name": name, "cmd": cmd if isinstance(cmd, str) else shlex.join(cmd),
                  "tree_sha": tree, "commit_sha": commit, "started": started, "ended": ended, "exit": code, "log": evd,
                  "ac": ac, "env": {"host": socket.gethostname(), "os": os.uname().sysname, "user": ME}},
                 correlation=prom)
    os.unlink(f.name)
    return ver, code, "\n".join(text.strip().splitlines()[-12:])


def verify_commands(org):
    """org.json "verify": a list of shell commands (strings) or {"name", "run", "timeout_s"}; run in the candidate's root."""
    out_ = []
    for i, v in enumerate(org.cfg.get("verify") or []):
        if isinstance(v, str):
            v = {"name": f"verify-{i + 1}", "run": v}
        out_.append((v.get("name") or f"verify-{i + 1}", v["run"], int(v.get("timeout_s", 1800))))
    return out_


# ── the candidate ───────────────────────────────────────────────────────────────────────────────────────────
def worktree(org, prom, at):
    wt = os.path.join(org.root, "state", "tmp", prom)
    git(org.repo, "worktree", "remove", "--force", wt)
    git(org.repo, "worktree", "prune")
    git(org.repo, "worktree", "add", "-q", "--detach", wt, at, check=True)
    return wt


def drop_worktree(org, wt):
    git(org.repo, "worktree", "remove", "--force", wt)
    git(org.repo, "worktree", "prune")


def merge_into(org, wt, ref, msg):
    """Merge ref into the candidate. A conflict only in generated hub files is resolved by regenerating them.
    -> None on success, else the conflicting paths (the merge is aborted)."""
    r = run(["git", "merge", "--no-ff", "--no-verify", "-m", msg, ref], wt, env=org.commit_env)
    if r.returncode == 0:
        return None
    unmerged = out(wt, "diff", "--name-only", "--diff-filter=U").splitlines()
    if unmerged and all(HUB_RE.match(f) for f in unmerged):
        git(wt, "checkout", "--ours", "--", *unmerged)
        git(wt, "add", "--", *unmerged)
        if run(["git", "commit", "--no-verify", "-q", "--no-edit"], wt, env=org.commit_env).returncode == 0:
            return None
    git(wt, "merge", "--abort")
    return unmerged or [(r.stderr or r.stdout).strip()[:300]]


def regenerate(org, wt, why):
    """The vault's generated pages (hubs, Map, Index) are rebuilt inside the candidate, so what moves is complete."""
    ran = False
    if os.path.exists(os.path.join(wt, "scripts", "vault-hubs.mjs")):
        run(["node", "scripts/vault-hubs.mjs"], wt)
        ran = True
    if os.path.exists(os.path.join(wt, "scripts", "gen-subject-index.py")):
        run(["python3", "scripts/gen-subject-index.py"], wt)
        ran = True
    if ran and out(wt, "status", "--porcelain", "--", "vault"):
        git(wt, "add", "-A", "--", "vault")
        run(["git", "commit", "--no-verify", "-q", "-m", f"vault: regenerate hubs and index (coordinator)\n\n{why}"],
            wt, env=org.commit_env)


def gate_env(org):
    return {**os.environ, "ORG_MAIN_BRANCH": org.main}


# ── one promotion ───────────────────────────────────────────────────────────────────────────────────────────
def result(decision, reason="", prom=None, sha=None, notices=(), report=""):
    return {"decision": decision, "reason": reason, "prom": prom, "sha": sha, "notices": list(notices), "report": report}


def scope_refusal(org, op, lane_root, ref):
    lane, prefix, int_br = lane_of(lane_root)
    if ref.startswith(FORBIDDEN_PREFIXES) or ref.startswith("-") or "@{" in ref or ".." in ref:
        return f"{ref} is not a local work branch this lane may promote"
    if op == "land":
        if not lane.get("may_land"):
            return "this lane may not land on main (lane.json may_land is false)"
        if ref != int_br:
            return f"a lane lands only its own integration branch {int_br}: MERGE {ref} into it first"
    else:
        name = ref[len(prefix) + 1:] if ref.startswith(prefix + "/") else ""
        if not NAME_RE.match(name) or ref == int_br:
            return f"a lane merges only its own agents' branches ({prefix}/<agent>), not {ref}"
        if not org.conn.execute("SELECT 1 FROM dispatches WHERE lane=? AND branch=?", (lane["name"], ref)).fetchone():
            return f"{ref} was never dispatched by this lane's loop"
    if git(org.repo, "rev-parse", "-q", "--verify", f"refs/heads/{ref}^{{commit}}").returncode:
        return f"{ref} does not exist"
    subject = out(org.repo, "log", "-1", "--format=%s", ref)
    if SAFETY_NET in subject:
        return f"{ref}'s tip is a safety-net commit (unverified leftovers of an interrupted agent)"
    return None


def diverged(org):
    """None if main is current with origin (or there is no origin), else why not. Fetches first."""
    if git(org.repo, "remote", "get-url", "origin").returncode:
        return None
    if git(org.repo, "fetch", "-q", "origin", org.main).returncode:
        return f"could not fetch origin/{org.main} to confirm main is current"
    behind = out(org.repo, "rev-list", "--count", f"{org.main}..origin/{org.main}")
    if behind and behind != "0":
        ahead = out(org.repo, "rev-list", "--count", f"origin/{org.main}..{org.main}")
        return (f"{org.main} is DIVERGED from origin (+{ahead}/-{behind})" if ahead != "0"
                else f"{org.main} is {behind} commit(s) behind origin") + ": reconcile main before landing"
    return None


def checkout_conflict(org, target, before, after):
    """If the shared checkout has the target out, the files the promotion changes must be clean there."""
    if out(org.repo, "symbolic-ref", "-q", "--short", "HEAD") != target:
        return None
    changed = set(out(org.repo, "diff", "--name-only", before, after).splitlines())
    local = {l[3:].split(" -> ")[-1] for l in out(org.repo, "status", "--porcelain").splitlines()}
    both = sorted(changed & local)
    return f"the checkout at {org.repo} has local changes to {', '.join(both[:5])}" if both else None


def sync_checkout(org, target, before, after):
    """Every worktree that has target checked out (the shared checkout, a lane's int/) follows the ref from before
    to after — only where its index still matches before; read-tree -m -u never overwrites local edits."""
    path = None
    for line in out(org.repo, "worktree", "list", "--porcelain").splitlines() + [""]:
        if line.startswith("worktree "):
            path = line[9:]
        elif line == f"branch refs/heads/{target}" and path and os.path.isdir(path):
            if git(path, "diff-index", "--cached", "--quiet", before).returncode == 0:
                git(path, "read-tree", "-m", "-u", before, after)


def promote(org, op, lane_root, ref, consult):
    lane, prefix, int_br = lane_of(lane_root)
    target = org.main if op == "land" else int_br
    why = scope_refusal(org, op, lane_root, ref)
    with S.tx(org.conn):
        prom = S.next_id(org.conn, "PROM")
        S.append(org.conn, "promotion.requested", prom, f"supervisor:{lane['name']}", f"proc:loop@{ME}",
                 {"lane": lane["name"], "op": op, "ref": ref, "target": target, "consult": consult}, correlation=prom)
    def refuse(reason, failed=(), report=""):
        org.ev("promotion.refused", prom, {"reason": reason, "failed": list(failed)}, correlation=prom)
        return result("refused", reason, prom, report=report)
    if why:
        return refuse(why)
    if op == "land":
        d = diverged(org)
        if d:
            return refuse(d)
    if git(org.repo, "merge-base", "--is-ancestor", ref, target).returncode == 0:
        org.ev("promotion.aborted", prom, {"reason": f"nothing to promote: {ref} is already in {target}"}, correlation=prom)
        return result("nothing", f"{ref} is already in {target}", prom)
    missing = [g for g, a in GATES if git(org.repo, "cat-file", "-e", f"{org.main}:{a[1]}").returncode]
    if missing:
        return refuse(f"the landing gates are not on {org.main} ({', '.join(missing)}): install the agent-org repo layer first")
    checks = verify_commands(org)
    if not checks:
        return refuse("no verification configured (org.json \"verify\"): independent verification is mandatory")
    for attempt in (1, 2):
        before = out(org.repo, "rev-parse", f"refs/heads/{target}")
        trusted = out(org.repo, "rev-parse", f"refs/heads/{org.main}")
        wt = worktree(org, prom, before)
        try:
            what = f"{op.upper()} {ref} into {target} (consult {consult}, {prom})"
            if op == "merge" and git(wt, "merge-base", "--is-ancestor", org.main, "HEAD").returncode:
                bad = merge_into(org, wt, org.main, f"{prefix}: refresh {target} from {org.main} ({prom})")
                if bad:
                    return refuse(f"{target} is behind {org.main} and refreshing it conflicts: {', '.join(bad[:5])}")
            bad = merge_into(org, wt, ref, f"{prefix}: {op} {ref} into {target} (consult {consult})\n\nAuthority: supervisor")
            if bad:
                return refuse(f"CONFLICT merging {ref} into {target}: {', '.join(bad[:5])}")
            # Grade the lane's range — every commit not on trusted main yet — at the merged candidate, BEFORE the
            # coordinator's own regeneration commit (generated and protected files are the coordinator's to write).
            graded = out(wt, "rev-parse", "HEAD")
            since = out(wt, "merge-base", trusted, "HEAD")
            regenerate(org, wt, what)
            cand, tree = out(wt, "rev-parse", "HEAD"), out(wt, "rev-parse", "HEAD^{tree}")
            org.ev("promotion.verifying", prom, {"base_sha": before, "candidate_sha": cand, "merged_tree_sha": tree,
                                                 "graded_sha": graded, "graded_since": since,
                                                 "target_before": before, "trusted_gates_from": trusted}, correlation=prom)
            crash_point("verifying")
            # the gates' CODE is main's (trusted), the history and content are the candidate's
            git(wt, "checkout", "-q", graded, check=True)
            git(wt, "checkout", "-q", trusted, "--", "scripts/gates", "scripts/lib", check=True)
            lane_mode = "--lane" in (out(wt, "show", f"{trusted}:scripts/gates/plan-ownership.mjs") or "")
            failed, parts = [], []
            for g, args in GATES:
                argv = [a.format(base=since, lane="--lane" if lane_mode else "") for a in args]
                ver, code, tail = verification(org, prom, "gate", g, [a for a in argv if a], wt, out(wt, "rev-parse", "HEAD^{tree}"),
                                               graded, 600, env=gate_env(org))
                ok = code in (0, 77)
                parts.append(f"### gate {g}: exit {code} ({'pass' if ok else 'FAIL'}) — {ver}\n```\n{tail}\n```")
                failed += [] if ok else [ver]
            git(wt, "checkout", "-q", "-f", cand)
            for name, cmd, tmo in checks:
                ver, code, tail = verification(org, prom, "check", name, cmd, wt, tree, cand, tmo)
                parts.append(f"### check {name}: exit {code} ({'pass' if code == 0 else 'FAIL'}) — {ver}\n`{cmd}`\n```\n{tail}\n```")
                failed += [] if code == 0 else [ver]
            report = "\n\n".join(parts)
            if failed:
                return refuse(f"verification failed on the merged candidate {cand[:9]} ({len(failed)} of "
                              f"{len(GATES) + len(checks)} failed)", failed, report)
            busy = checkout_conflict(org, target, before, cand)
            if busy:
                return refuse(busy, report=report)
            if git(org.repo, "update-ref", f"refs/heads/{target}", cand, before).returncode:
                if attempt == 1:
                    continue           # the target moved while we verified: rebuild on the new tip, once
                return refuse(f"{target} kept moving during verification; request again", report=report)
            crash_point("after-cas")
            sync_checkout(org, target, before, cand)
            org.ev("promotion.promoted", prom, {"target_before": before, "target_after": cand}, correlation=prom)
            if op == "merge":
                git(org.repo, "push", "-q", "origin", target)
            publish(org)
            return result("promoted", "", prom, cand, report=report)
        finally:
            drop_worktree(org, wt)
    return refuse("unreachable")


# ── crash recovery ──────────────────────────────────────────────────────────────────────────────────────────
def reconcile(org):
    """Each promotion left requested/verifying by a crash: if its target ref is at the recorded candidate, it
    happened (promoted, reconciled) — else it did not (aborted). Never replays an operation blind."""
    notes = []
    rows = org.conn.execute("SELECT id, op, requested_ref, target, state, candidate_sha, target_before FROM promotions "
                            "WHERE state IN ('requested', 'verifying')").fetchall()
    for prom, op, ref, target, state, cand, before in rows:
        tip = out(org.repo, "rev-parse", f"refs/heads/{target}")
        if state == "verifying" and cand and tip == cand:
            sync_checkout(org, target, before, cand)
            org.ev("promotion.promoted", prom, {"target_before": before, "target_after": cand, "reconciled": True}, correlation=prom)
            notes.append(f"{prom} ({op.upper()} {ref} into {target}) was interrupted after it moved {target}: recorded as promoted.")
        else:
            org.ev("promotion.aborted", prom, {"reason": "interrupted before the target moved", "reconciled": True}, correlation=prom)
            notes.append(f"{prom} ({op.upper()} {ref} into {target}) was interrupted before {target} moved: aborted; request it again.")
    tmp = os.path.join(org.root, "state", "tmp")
    for d in (os.listdir(tmp) if os.path.isdir(tmp) else []):
        drop_worktree(org, os.path.join(tmp, d))
    if rows:
        publish(org)
    return notes


# ── the mission's acceptance ────────────────────────────────────────────────────────────────────────────────
def mission_slug(org):
    s = out(org.repo, "show", f"{org.main}:.claude/settings.json")
    try:
        slug = json.loads(s).get("env", {}).get("ORG_MISSION") if s else None
    except ValueError:
        slug = None
    return slug or org.cfg.get("mission")


def criteria_from_main(org, slug):
    """The owner's "Definition of done" table in main's mission file (a protected path): `| key | property | check |…`.
    A check in backticks is a command run at the repo root; anything else is a manual criterion the owner accepts."""
    path = f"vault/Missions/{slug}.md"
    text = out(org.repo, "show", f"{org.main}:{path}")
    sec = re.search(r"^## Definition of done\s*$(.*?)(?=^## |\Z)", text, re.M | re.S)
    rows = []
    for line in (sec.group(1) if sec else "").splitlines():
        cells = [c.strip() for c in line.strip().strip("|").split("|")] if line.strip().startswith("|") else []
        if len(cells) < 3 or not cells[0] or cells[0] in ("#", "key") or set(cells[0]) <= set("-: "):
            continue
        m = re.search(r"`([^`]+)`", cells[2])
        rows.append({"key": cells[0], "text": cells[1], "check": {"cmd": m.group(1), "cwd": "repo"} if m else "manual"})
    return path, rows


def sync_mission(org, slug):
    """Mirror main's mission criteria into the canonical state (only changes become events). -> (MIS id, [AC rows])."""
    path, rows = criteria_from_main(org, slug)
    src = f"{org.main}:{path}@{out(org.repo, 'rev-parse', org.main)[:12]}"
    with S.tx(org.conn):
        m = org.conn.execute("SELECT id FROM missions WHERE slug=?", (slug,)).fetchone()
        mis = m[0] if m else S.next_id(org.conn, "MIS")
        if not m:
            S.append(org.conn, "mission.defined", mis, "coordinator", AUTH,
                     {"slug": slug, "title": slug, "source": src, "authored_by": "owner"})
        for r in rows:
            have = org.conn.execute("SELECT id, text, check_json FROM acceptance_criteria WHERE mission=? AND key=?",
                                    (mis, r["key"])).fetchone()
            if have and have[1] == r["text"] and have[2] == S.canon(r["check"]):
                continue
            ac = have[0] if have else S.next_id(org.conn, "AC")
            S.append(org.conn, "acceptance.defined", ac, "coordinator", AUTH,
                     {"mission": mis, "key": r["key"], "text": r["text"], "check": r["check"], "source": src,
                      "authored_by": "owner"})
    acs = org.conn.execute("SELECT id, key, text, check_json FROM acceptance_criteria WHERE mission=? ORDER BY key",
                           (mis,)).fetchall()
    keys = {r["key"] for r in rows}
    return mis, [a for a in acs if a[1] in keys]


def done(org, lane_root, consult):
    """DONE is derived: every acceptance criterion has a passing acceptance verification of main's current tree."""
    slug = mission_slug(org)
    reasons = []
    if not slug:
        return result("not-verified", "no mission is in force (ORG_MISSION)")
    mis, acs = sync_mission(org, slug)
    tip, tree = out(org.repo, "rev-parse", org.main), out(org.repo, "rev-parse", f"{org.main}^{{tree}}")
    if not acs:
        reasons.append(f"mission {slug} has no acceptance criteria in its Definition of done table")
    passed, wt = [], None
    try:
        for ac, key, text, check in acs:
            check = json.loads(check)
            hit = org.conn.execute("SELECT id FROM verifications WHERE ac=? AND kind='acceptance' AND tree_sha=? AND exit=0",
                                   (ac, tree)).fetchone()
            if hit:
                passed.append(hit[0])
                continue
            if check == "manual":
                reasons.append(f"{key} ({text}) needs the owner's acceptance of {tip[:9]}: promote.py <ORG_ROOT> accept {key} --note …")
                continue
            wt = wt or worktree(org, f"done-{mis}", tip)
            ver, code, tail = verification(org, None, "acceptance", key, check["cmd"], wt, tree, tip, 1800, ac=ac)
            if code == 0:
                passed.append(ver)
            else:
                reasons.append(f"{key} ({text}) fails on {tip[:9]}: `{check['cmd']}` exit {code}")
    finally:
        if wt:
            drop_worktree(org, wt)
    plan = os.path.join(lane_root, "plan.md")
    open_rows = [l.strip() for l in open(plan)] if os.path.exists(plan) else []
    open_rows = [l for l in open_rows if l.startswith("- [ ]")]
    if open_rows:
        reasons.append(f"the lane plan has {len(open_rows)} open row(s), e.g. {open_rows[0][:80]}")
    if reasons:
        org.ev("mission.done_refused", mis, {"main_sha": tip, "tree_sha": tree, "reasons": reasons, "consult": consult})
        publish(org)
        return result("not-verified", "; ".join(reasons), sha=tip)
    org.ev("mission.verified", mis, {"main_sha": tip, "tree_sha": tree, "verifications": passed, "consult": consult})
    publish(org)
    return result("verified", f"mission {slug}: {len(passed)} acceptance criteria verified on {tip[:9]}", sha=tip)


def accept(org, key, note):
    """The owner (whoever runs this as the org's user, by hand) accepts a manual criterion at main's current tree."""
    slug = mission_slug(org)
    mis, acs = sync_mission(org, slug)
    hit = [a for a in acs if a[1] == key]
    if not hit:
        return result("refused", f"no criterion {key} in mission {slug}")
    tip, tree = out(org.repo, "rev-parse", org.main), out(org.repo, "rev-parse", f"{org.main}^{{tree}}")
    ver, _, _ = verification(org, None, "acceptance", key, ["printf", "%s\\n", f"accepted by the owner: {note}"],
                             org.root, tree, tip, 10, ac=hit[0][0], actor="owner", auth=f"os-user:{ME}")
    publish(org)
    return result("ok", f"{key} accepted at {tip[:9]} ({ver})", sha=tip)


# ── git-sync's main branch, under the same lock ─────────────────────────────────────────────────────────────
def sync_main(org):
    log = os.path.join(org.root, "logs", "git-sync.log")
    os.makedirs(os.path.dirname(log), exist_ok=True)
    stamp = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M")
    def note(s):
        open(log, "a").write(f"{stamp} {s}\n")
    if git(org.repo, "fetch", "-q", "origin", org.main).returncode:
        note("fetch failed")
        return result("ok", "fetch failed")
    a = int(out(org.repo, "rev-list", "--count", f"origin/{org.main}..{org.main}") or 0)
    b = int(out(org.repo, "rev-list", "--count", f"{org.main}..origin/{org.main}") or 0)
    if b and not a:
        before = out(org.repo, "rev-parse", org.main)
        after = out(org.repo, "rev-parse", f"origin/{org.main}")
        busy = checkout_conflict(org, org.main, before, after)
        if busy or git(org.repo, "update-ref", f"refs/heads/{org.main}", after, before).returncode:
            note(f"{org.main} fast-forward FAILED ({busy or 'ref moved'})")
        else:
            sync_checkout(org, org.main, before, after)
            note(f"{org.main} fast-forwarded to {after[:7]}")
    elif a and not b and org.cfg.get("sync", {}).get("push_main", False):
        if git(org.repo, "push", "-q", "origin", org.main).returncode == 0:
            note(f"{org.main} pushed {out(org.repo, 'rev-parse', '--short', org.main)} (+{a})")
    elif a and b:
        note(f"DIVERGED {org.main} +{a}/-{b} vs origin: not touched")
    return result("ok")


def publish(org):
    """Export new events to ORG_ROOT/state/journal/ and commit them to the repo's `state/journal` branch (pushed
    best-effort): the durable copy a new machine rebuilds from. Plumbing only — no checkout is touched."""
    S.export_journal(org.root, org.conn)
    jdir = os.path.join(org.root, "state", "journal")
    env = {**os.environ, "GIT_INDEX_FILE": os.path.join(org.root, "state", "journal.index")}
    parent = out(org.repo, "rev-parse", "-q", "--verify", "refs/heads/state/journal")
    for f in sorted(os.listdir(jdir)):
        if f.endswith(".jsonl"):
            blob = run(["git", "hash-object", "-w", os.path.join(jdir, f)], org.repo).stdout.strip()
            run(["git", "update-index", "--add", "--cacheinfo", f"100644,{blob},journal/{f}"], org.repo, env=env)
    tree = run(["git", "write-tree"], org.repo, env=env).stdout.strip()
    if not tree or (parent and out(org.repo, "rev-parse", f"{parent}^{{tree}}") == tree):
        return
    cmd = ["git", "commit-tree", tree, "-m", f"state: journal to seq {S.head(org.conn)[0]}"] + (["-p", parent] if parent else [])
    c = run(cmd, org.repo, env={**org.commit_env, "GIT_INDEX_FILE": env["GIT_INDEX_FILE"]}).stdout.strip()
    if c:
        git(org.repo, "update-ref", "refs/heads/state/journal", c, *([parent] if parent else []))
        git(org.repo, "push", "-q", "origin", "refs/heads/state/journal")


# ── CLI ─────────────────────────────────────────────────────────────────────────────────────────────────────
def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 2
    org_root, cmd, rest = argv[0], argv[1], argv[2:]
    if cmd == "with-lock":       # run a command while holding the promotion lock (shell callers)
        org = Org(org_root)
        org.lock()
        return subprocess.call(rest[1:] if rest[:1] == ["--"] else rest)
    consult = 0
    if "--consult" in rest:
        i = rest.index("--consult")
        consult = int(rest[i + 1])
        rest = rest[:i] + rest[i + 2:]
    org = Org(org_root)
    held = org.lock()
    notices = reconcile(org)
    if cmd == "request" and len(rest) == 3 and rest[0] in ("merge", "land"):
        res = promote(org, rest[0], os.path.abspath(rest[1]), rest[2], consult)
    elif cmd == "done" and len(rest) == 1:
        res = done(org, os.path.abspath(rest[0]), consult)
    elif cmd == "dispatch" and len(rest) == 4:
        lane, _, _ = lane_of(rest[0])
        org.ev("dispatch.recorded", f"{lane['name']}/{rest[1]}", {"lane": lane["name"], "agent": rest[1], "branch": rest[2],
               "base": rest[3], "consult": consult}, actor=f"supervisor:{lane['name']}", auth=f"proc:loop@{ME}")
        res = result("ok")
    elif cmd == "accept" and len(rest) == 3 and rest[1] == "--note":
        res = accept(org, rest[0], rest[2])
    elif cmd == "reconcile":
        res = result("ok")
    elif cmd == "sync-main":
        res = sync_main(org)
    else:
        print(__doc__)
        return 2
    res["notices"] = notices + res["notices"]
    print(json.dumps(res))
    held.close()
    return 0 if res["decision"] in ("promoted", "nothing", "verified", "ok") else 3


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
