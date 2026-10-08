#!/usr/bin/env python3
"""Lane supervisor loop: one SUPERVISOR model plans; WORKER agents (Claude Code) do the work.

One process per lane. Layout: <ORG_ROOT>/org.json (shared) and <ORG_ROOT>/lanes/<name>/lane.json (this lane).
  python3 supervise.py <LANE_ROOT> [start_round]

Each consult, the supervisor reads its brief + context + plan + owner rulings (and the newest raw owner answers)
+ a digest of the newest reports + the lane branch's code view + fresh images, and emits blocks this loop executes:
  === PLAN === … === END PLAN ===                         (rewritten whole every consult)
  === AGENT name=<slug> model=<key> [base=<ref>] === … === END AGENT ===
  === MERGE branch=<lane>/<agent> ===                      (request: into the lane integration branch, via promote.py)
  === LAND branch=<lane>/integration ===                   (request: into main, via promote.py; lane.json may_land)
  === KILL name=<slug> ===                                 (terminate a running agent; its work is committed)
  === ASK_OWNER === … === END ASK ===                      (appended to owner-questions.md)
  === LEARN === … === END LEARN ===                        (appended to lane-memory.md: the supervisor's persistent memory)
  === DONE ===                                             (a claim: promote.py derives whether the mission is done)
A consult with none of these is logged as NO ACTIONABLE BLOCK and quoted back in the next prompt.
ROLLING: the supervisor is re-consulted whenever ANY agent finishes (no round barrier). Each agent runs in its
own session (process group) with a deadline kept in <LANE_ROOT>/pids/<name>.json; a restarted loop ADOPTS the
agents still running from those files (no GNU `timeout`: macOS does not ship it).
Stop: touch <LANE_ROOT>/STOP.
"""
import datetime, glob, json, os, pwd, re, shlex, signal, subprocess, sys, time

LANE_ROOT = os.path.abspath(sys.argv[1]) if len(sys.argv) > 1 else os.getcwd()
START_ROUND = int(sys.argv[2]) if len(sys.argv) > 2 else 1
ORG_ROOT = os.environ.get("ORG_ROOT") or os.path.dirname(os.path.dirname(LANE_ROOT.rstrip("/")))   # <ORG_ROOT>/lanes/<name>
ORG = json.load(open(os.path.join(ORG_ROOT, "org.json")))
LANE = json.load(open(os.path.join(LANE_ROOT, "lane.json")))

R = LANE_ROOT
REPO = ORG["repo"]
MAIN_BR = ORG.get("main_branch", "main")
PREFIX = LANE.get("branch_prefix", f"lane/{LANE['name']}")
INT_BR = f"{PREFIX}/integration"
INT = f"{R}/int"
LOG = f"{R}/lane.log"
MAX_PAR = int(LANE.get("max_parallel", 2))
AGENT_TIMEOUT = int(ORG.get("agent_timeout_s", 8 * 3600))
CONSULT_TIMEOUT = int(ORG.get("consult_timeout_s", 5400))
SUPERVISOR_TOOLS = "Read,Grep,Glob,WebSearch,WebFetch"         # a Claude supervisor reads and researches, nothing else
REPORT_OVERDUE_S = int(ORG.get("report_overdue_s", 90 * 60))   # a running agent with no report file after this: warn once
POLL_S = int(ORG.get("poll_interval_s", 30))
IDLE_WAIT_S = int(ORG.get("idle_wait_s", 1200))              # nothing running: wait this long for owner answers / changes
USAGE_WAIT_S = int(ORG.get("usage_limit_wait_s", 1800))      # supervisor hit a usage limit: wait, then consult again
LIMIT_RE = re.compile(r"usage limit|rate limit|quota|credit balance", re.I)
# Spend guards, per lane per UTC day. On a breach the lane asks the owner and idles until midnight UTC or STOP.
BUDGET = {"consults": int(ORG.get("max_consults_per_day", 100)),
          "starts": int(ORG.get("max_agent_starts_per_day", 40)),
          "agent_hours": float(ORG.get("max_agent_hours_per_day", 48))}
WORKER_USER = ORG.get("worker_user") or ""                 # remote runtime: the ONE user that runs the whole org
SUP = ORG["supervisor"]                                     # {"backend": "codex"|"claude", "model": ..., ...}
MODELS = ORG["worker_models"]                               # {"opus": "claude-opus-5-5", "sonnet": "sonnet"}
DEFAULT_MODEL = ORG.get("default_worker_model", next(iter(MODELS)))
WORKER_ENV = dict(ORG.get("worker_env", {}))                # extra env for every worker (PATH, build profile, …)
_bq = ORG.get("build_queue") or {}
if _bq.get("wrap"):                                         # read by build-queue (installed by bootstrap-host.sh)
    WORKER_ENV.setdefault("BUILD_QUEUE_SLOTS", str(_bq.get("slots", 3)))
    WORKER_ENV.setdefault("BUILD_QUEUE_HEAVY", " ".join(dict.fromkeys(w.split()[1] for w in _bq["wrap"] if len(w.split()) > 1)))
COMMIT_ENV = ORG.get("commit_env", {})                      # env needed by the repo's commit hooks, if any
# Every org process: the global config's interactive hooks (standing procedure, skill router, session notes) stand down.
HEADLESS_ENV = {"AGENT_ORG_HEADLESS": "1"}
CLAUDE = ORG.get("claude_bin", "claude")
if not os.path.isabs(CLAUDE):                               # workers run with worker_env.PATH, which may not find a bare name
    CLAUDE = __import__("shutil").which(CLAUDE, path=WORKER_ENV.get("PATH") or os.environ.get("PATH")) or CLAUDE
if not (os.path.isfile(CLAUDE) and os.access(CLAUDE, os.X_OK)):
    sys.exit(f"supervise.py: claude_bin {CLAUDE!r} not found or not executable (set an absolute path in org.json)")
q = shlex.quote

# Prompt budget: what one consult may carry.
OWNER_ANSWERS_RECENT = int(ORG.get("owner_answers_recent", 10))   # raw `## …` entries shown beside rulings.md
REPORT_HEAD, REPORT_TAIL, TLDR_MAX = 2000, 3000, 2000              # chars per report: TL;DR + head + tail
CODE_VIEW_MAX = 6000                                               # chars of git log / diff --stat per consult
IMAGE_MAX = 12                                                     # pinned (renders/owner, renders/latest) + fresh
ACTION_RE = re.compile(r"^=== (PLAN|AGENT|MERGE|LAND|ASK_OWNER|LEARN|MEMORY_CONSOLIDATED|DONE|KILL)\b", re.M)
UNFILLED_RE = re.compile(r"\{\{[A-Z][A-Z0-9_]*\}\}")
NAME_RE = re.compile(r"^[a-z0-9][a-z0-9-]{0,40}$")                 # agent names: they become paths and branch names


def now():
    return datetime.datetime.now(datetime.timezone.utc)


def log(msg):
    line = f"{now():%Y-%m-%d %H:%M} {msg}"
    print(line, flush=True)
    with open(LOG, "a") as f:
        f.write(line + "\n")


def sh(cmd, **kw):
    return subprocess.run(cmd, shell=True, text=True, capture_output=True, **kw)


def run_bounded(args, timeout, input=None, **kw):
    """subprocess.run with a deadline that kills the WHOLE process group (a shell's children too), portably."""
    p = subprocess.Popen(args, stdin=subprocess.PIPE if input is not None else subprocess.DEVNULL,
                         stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, start_new_session=True, **kw)
    try:
        out, err = p.communicate(input, timeout=timeout)
    except subprocess.TimeoutExpired:
        killpg(p.pid)
        out, err = p.communicate()
        err += f"\n(killed after {timeout}s)"
        p.returncode = 124
    return subprocess.CompletedProcess(args, p.returncode, out, err)


def killpg(pid, grace=10):
    """TERM the process group, then KILL it if anything is left after `grace` seconds."""
    for sig in (signal.SIGTERM, signal.SIGKILL):
        try:
            os.killpg(pid, sig)
        except (ProcessLookupError, PermissionError):
            return
        for _ in range(grace * 10):
            try:
                os.killpg(pid, 0)
            except (ProcessLookupError, PermissionError):
                return
            time.sleep(0.1)


def git_out(cmd, cwd=REPO):
    return sh(f"cd {q(cwd)} && {cmd}").stdout.strip()


def rd(p, default=""):
    return open(p, errors="replace").read() if os.path.exists(p) else default


def stopped():
    return os.path.exists(f"{R}/STOP")


def env_str(extra):
    env = dict(WORKER_ENV)
    env.update({"BASH_DEFAULT_TIMEOUT_MS": "3600000", "BASH_MAX_TIMEOUT_MS": "3600000", **HEADLESS_ENV})
    env.update(extra)
    return " ".join(f"{k}={q(str(v))}" for k, v in env.items())


# ── loop state (survives restarts): last consult time, overdue warnings already given, notices for the next prompt
STATE = f"{R}/loop-state.json"
try:
    ST = json.load(open(STATE))
except (OSError, ValueError):
    ST = {}
ST.setdefault("last_consult", 0.0)
ST.setdefault("overdue", [])
ST.setdefault("notes", [])
FINISHED = []          # agent names finished since the last consult (their branches get a diff --stat)


def save_state():
    open(STATE + ".tmp", "w").write(json.dumps(ST, indent=1))
    os.replace(STATE + ".tmp", STATE)


def today():
    return f"{now():%Y-%m-%d}"


def spend(running=()):
    """Today's counters (reset at UTC midnight, logging the closing total), with running agents' time charged
    up to now."""
    b = ST.get("budget") or {}
    if b.get("day") != today():
        if b.get("day"):
            log_total(b, closing=True)
        b = ST["budget"] = {"day": today(), "consults": 0, "starts": 0, "agent_s": 0.0, "tick": time.time(),
                            "breached": [], "total_at": 0.0}
    t = time.time()
    # Agent-hours tick only when spend() runs (each poll, idle tick and consult), charging the agents alive NOW for
    # the whole interval: an agent that finished during a long consult is not charged for it. The figure
    # undercounts, never overcounts — a backstop against a runaway lane, not an exact meter.
    b["agent_s"] += (t - b.get("tick", t)) * sum(1 for x in running if x[0].poll() is None)
    b["tick"] = t
    return b


def log_total(b, closing=False):
    """D2: the running total for the day, in the lane log (lane-events.sh shows TOTAL lines)."""
    log(f"TOTAL {b['day']}{' (closing)' if closing else ''}: consults {b['consults']}/{BUDGET['consults']}, "
        f"agent starts {b['starts']}/{BUDGET['starts']}, agent hours {b['agent_s'] / 3600:.1f}/{BUDGET['agent_hours']:g}")
    b["total_at"] = time.time()


def over_budget(kind, running=()):
    """True when today's `kind` cap ("consults" | "starts") or the agent-hours cap is reached. The first breach of
    the day is logged and asked of the owner (owner-questions.md, like an ASK_OWNER block)."""
    b = spend(running)
    hit = [k for k, used in ((kind, b[kind]), ("agent_hours", b["agent_s"] / 3600)) if used >= BUDGET[k]]
    if not hit:
        return False
    new = [k for k in hit if k not in b["breached"]]
    if new:
        b["breached"] += new
        save_state()
        what = ", ".join(f"{k} {b[k] if k != 'agent_hours' else round(b['agent_s'] / 3600, 1)}/{BUDGET[k]:g}" for k in new)
        qn = (f"Budget cap reached for {b['day']} UTC ({what}). The lane is idle until 00:00 UTC. Raise the cap in "
              f"org.json (max_consults_per_day / max_agent_starts_per_day / max_agent_hours_per_day) and restart "
              f"the lane, or let it resume tomorrow.")
        with open(f"{R}/owner-questions.md", "a") as f:
            f.write(f"\n## Budget ({now():%Y-%m-%d %H:%M} UTC)\n{qn}\n")
        log(f"BUDGET cap reached ({what}) — ASK_OWNER: {qn}")
        log_total(b)
    return True


def idle_until_rollover(running):
    """Spend guard: no consults and no agent starts until the UTC day changes or STOP. Running agents keep their
    deadlines; the ones that finish meanwhile are committed as usual, and overdue reports are still flagged."""
    day = today()
    while not stopped() and today() == day:
        done = [x for x in running if x[0].poll() is not None]
        if done:
            finish(done)
            running[:] = [x for x in running if x not in done]
        watch_reports(running)
        spend(running)
        save_state()
        time.sleep(POLL_S)


MEMORY = f"{R}/lane-memory.md"            # the supervisor's own persistent, append-only memory (LEARN journal)
MEMORY_TAIL_BYTES = int(ORG.get("lane_memory_tail_bytes", 15000))
CONSOLIDATE_EVERY = int(ORG.get("lane_memory_consolidate_every", 25))


def report_key(p):
    """Sort by the numeric consult prefix (string sort breaks at 100), mtime as the tiebreak."""
    head = os.path.basename(p).split("-", 1)[0]
    return (int(head) if head.isdigit() else 0, os.path.getmtime(p))


def memory_tail():
    if not os.path.exists(MEMORY):
        return "(empty: record durable lessons with LEARN blocks)"
    data = open(MEMORY).read()
    return data if len(data) <= MEMORY_TAIL_BYTES else "…(older entries: lane-memory.md / lane-memory.archive-*.md)\n" + data[-MEMORY_TAIL_BYTES:]


# ── prompt sections ──────────────────────────────────────────────────────────────────────────────────
def project_rulings():
    """The project's standing rulings (.claude/rules/owner-rulings.md, versioned and protected). Claude sessions
    auto-load .claude/rules; a codex supervisor does not, so every consult carries them. Absent: nothing."""
    text = rd(f"{REPO}/.claude/rules/owner-rulings.md").strip()
    return f"\n## Owner rulings: the project's standing rules ({REPO}/.claude/rules/owner-rulings.md, binding)\n{text}\n" if text else ""


def owner_block():
    """The project's standing rulings, then rulings.md (this lane's curated law) in full + the newest raw
    owner-answers entries. Without rulings.md (lanes created before it existed) the whole owner-answers.md."""
    raw = rd(f"{R}/owner-answers.md", "(none)")
    if not os.path.exists(f"{R}/rulings.md"):
        return project_rulings() + f"\n## Owner answers (binding)\n{raw}\n"
    entries = re.split(r"(?m)^(?=## )", raw)[1:]          # [0] is the file's preamble
    recent = entries[-OWNER_ANSWERS_RECENT:]
    return (project_rulings()
            + f"\n## Owner rulings: the current law (binding; curated by the overseer)\n{rd(f'{R}/rulings.md')}\n"
            f"\n## Owner answers: the newest {len(recent)} of {len(entries)} raw entries (full log: {R}/owner-answers.md)\n"
            + "".join(recent) + "\n")


def report_digest(p):
    """A report's `## TL;DR` + its head + its tail (where "what to do next" lives); the file holds the rest."""
    text = rd(p)
    if len(text) <= REPORT_HEAD + REPORT_TAIL:
        return text
    m = re.search(r"(?msi)^##\s*TL;?DR\b.*?(?=^## |\Z)", text)
    tldr = m.group(0).strip()[:TLDR_MAX] + "\n\n…\n" if m and m.start() >= REPORT_HEAD // 2 else ""
    return (tldr + text[:REPORT_HEAD]
            + f"\n\n…[{len(text) - REPORT_HEAD - REPORT_TAIL} chars omitted; full report: {p}]…\n\n" + text[-REPORT_TAIL:])


def code_view(branches):
    """What the lane branch holds: its recent log, its diff against main, and each candidate branch's diff."""
    parts = [f"### git log --oneline -15 {INT_BR}\n" + git_out(f"git log --oneline -15 {q(INT_BR)}"),
             f"### git diff --stat {MAIN_BR}...{INT_BR}\n"
             + "\n".join(git_out(f"git diff --stat {q(MAIN_BR)}...{q(INT_BR)}").splitlines()[-40:])]
    for br in branches[:8]:
        stat = git_out(f"git diff --stat {q(INT_BR)}...{q(br)}").splitlines()
        parts.append(f"### git diff --stat {INT_BR}...{br}\n" + ("\n".join(stat[-15:]) or "(nothing beyond the lane branch)"))
    out = "\n\n".join(parts)
    return out if len(out) <= CODE_VIEW_MAX else out[:CODE_VIEW_MAX] + "\n…(code view capped)"


def images(since):
    """Pinned images (renders/owner, and renders/latest from older lanes) always; then worker images modified
    since the previous consult, newest first. IMAGE_MAX in all."""
    newest = lambda ps: sorted(ps, key=os.path.getmtime, reverse=True)
    pinned = newest(p for d in ("owner", "latest") for p in glob.glob(f"{R}/renders/{d}/**/*.png", recursive=True))
    fresh = newest(p for p in glob.glob(f"{R}/renders/**/*.png", recursive=True)
                   if p not in pinned and os.path.getmtime(p) > since)
    return (pinned + fresh)[:IMAGE_MAX]


# ── supervisor backends ──────────────────────────────────────────────────────────────────────────────
def consult(prompt, out, cwd, images=()):
    """Ask the supervisor model; wait out usage limits. Returns its text output."""
    while True:
        full = prompt + ("\n\n## Images to look at (Read them)\n" + "".join(f"\n- {i}" for i in images) if images else "")
        if SUP["backend"] == "codex":
            args = ["codex"] + (["--search"] if SUP.get("web_search", True) else []) + [
                "exec", "--skip-git-repo-check", "--sandbox", "read-only", "-m", SUP["model"],
                "-c", f'model_reasoning_effort="{SUP.get("effort", "high")}"', "-C", cwd, "-"]
            for img in images:
                args += ["-i", img]
            p = run_bounded(args, CONSULT_TIMEOUT, input=prompt)
        elif SUP["backend"] == "script":  # TEST-ONLY (scripts/test-supervise.sh): canned output, prompt on stdin, no model
            p = subprocess.run(["bash", SUP["command"]], input=full, text=True, capture_output=True, cwd=cwd,
                               env={**os.environ, **HEADLESS_ENV, "ORG_ROLE": "supervisor"})
        else:  # claude as a read-only supervisor: it may read, search and research, never edit
            # The whole prompt goes on stdin with NO prompt argument: `claude -p` then reads stdin as the prompt.
            # (stdin + a `-p "…"` argument is read as attachment content, which overflowed the context at 300 KiB,
            # and one argv string is capped at 128 KiB on Linux.)
            # Read-only by ALLOWLIST: --tools restricts the built-in set (--allowedTools would only pre-approve);
            # naming Glob/Grep brings them back on macOS/Linux; --tools does not cover MCP tools, so deny those.
            cmd = (f"cd {q(cwd)} && {q(CLAUDE)} -p --model {q(SUP['model'])} --tools {SUPERVISOR_TOOLS} "
                   f"--disallowedTools 'mcp__*' --dangerously-skip-permissions")
            p = run_bounded(["bash", "-c", f"env {env_str({'ORG_ROLE': 'supervisor'})} bash -c {q(cmd)}"], CONSULT_TIMEOUT,
                            input=full + "\n\nFollow the supervisor brief at the top of this prompt verbatim: emit your blocks now.\n")
        text = p.stdout
        open(out, "w").write(text)
        open(out + ".err", "w").write(p.stderr)
        # A limit is the CLI's complaint (stderr, or a failed exit), never a word in a normal reply
        if LIMIT_RE.search(p.stderr) or (p.returncode != 0 and LIMIT_RE.search(text)):
            log(f"supervisor hit a usage limit — waiting {USAGE_WAIT_S // 60} min")
            for _ in range(max(1, USAGE_WAIT_S // POLL_S)):
                if stopped():
                    return ""
                time.sleep(POLL_S)
            continue
        return text


# ── workers ──────────────────────────────────────────────────────────────────────────────────────────
def claude_cmd(model, prompt_file, cwd, env_extra, cont=False):
    """The prompt FILE is the agent's stdin and there is no prompt argument (see consult()): no argv size limit."""
    c = "--continue " if cont else ""
    inner = (f"cd {q(cwd)} && env {env_str(env_extra)} {q(CLAUDE)} -p {c}"
             f"--dangerously-skip-permissions --model {q(MODELS[model])} --disallowedTools Monitor < {q(prompt_file)}")
    return f"bash -c {q(inner)}"


def worktree(name, base):
    wt = f"{R}/wt/{name}"
    if not os.path.isdir(wt):
        r = sh(f"cd {q(REPO)} && git worktree add -B {q(f'{PREFIX}/{name}')} {q(wt)} {q(base)}")
        if r.returncode:
            log(f"worktree {name} from {base} FAILED: {r.stderr.strip()[:300]}")
            return None
        for src in ORG.get("worktree_links", []):          # e.g. node_modules, .env files: shared, never committed
            # Only IGNORED paths: a link to a tracked path would let a worker write the main checkout's files.
            if sh(f"cd {q(REPO)} && git check-ignore -q -- {q(src)}").returncode:
                log(f"worktree_links: skipped {src!r} for {name} — not ignored by git in {REPO}")
                continue
            sh(f"ln -sfn {q(f'{REPO}/{src}')} {q(f'{wt}/{src}')} 2>/dev/null")
    return wt


def run_agent(name, model, base, brief, rnd):
    wt = worktree(name, base)
    if not wt:
        return None
    report = f"{R}/reports/{rnd:04d}-{name}.md"
    renders = f"{R}/renders/{name}"
    os.makedirs(renders, exist_ok=True)
    pf = f"{R}/prompts/{rnd:04d}-{name}.md"
    open(pf, "w").write(open(f"{R}/agent-rules.md").read() + "\n\n" + rd(f"{R}/context.md")
                        + f"\n\n# YOUR BRIEF (supervisor, consult {rnd})\n\nYou are agent `{name}` in worktree `{wt}` "
                        f"on branch `{PREFIX}/{name}`.\n\n{brief}\n\n**Write your report to `{report}`, opening with "
                        f"`## TL;DR` (at most 10 lines).** Images the supervisor should see go in `{renders}/` (PNG; "
                        "only images newer than its last consult are shown to it).\n\n"
                        "Follow the brief above verbatim, starting now.\n")
    rf = f"{R}/prompts/{rnd:04d}-{name}.resume.md"
    open(rf, "w").write("You were interrupted — your process exits whenever you end your turn. Continue your brief "
                        f"from where you stopped, running every command in the FOREGROUND. Do not stop until {report} "
                        "is written.")
    env = {"AGENT_NAME": name, "LANE_ROOT": R, "RENDERS_DIR": renders, "ORG_LANE": LANE["name"]}
    if ORG.get("per_agent_build_dir"):
        env[ORG["per_agent_build_dir"]] = f"{R}/target/{name}"
        os.makedirs(env[ORG["per_agent_build_dir"]], exist_ok=True)
    agent_log = f"{R}/logs/{rnd:04d}-{name}.log"
    # lanes.sh gc spots a running agent by the leading "cd <wt> &&": keep that shape
    script = (f"cd {q(wt)} && {claude_cmd(model, pf, wt, env)} > {q(agent_log)} 2>&1; "
              f"for n in 1 2 3; do [ -s {q(report)} ] && break; "
              f"{claude_cmd(model, rf, wt, env, cont=True)} >> {q(agent_log)} 2>&1; done")
    log(f"agent {name} ({model}) start on {base}")
    p = subprocess.Popen(["bash", "-c", script], stdin=subprocess.DEVNULL, start_new_session=True)
    a = Agent(name, p.pid, time.time() + AGENT_TIMEOUT, p)
    write_pidfile(name, a, report)
    return a, report, name


def finish(procs):
    """Safety net: commit + push whatever the agent left, from its HEAD (never a stale branch ref)."""
    for p, report, name in procs:
        wt = f"{R}/wt/{name}"
        cenv = " ".join(f"{k}={q(v)}" for k, v in COMMIT_ENV.items())
        msg = q(f"{PREFIX} {name}: uncommitted agent work (safety net)")
        sh(f"cd {q(wt)} && git add -A && env {cenv} git commit --no-verify -q -m {msg}")
        sh(f"cd {q(wt)} && git push -q origin {q(f'HEAD:refs/heads/{PREFIX}/{name}')}")
        rc = "?" if p.returncode is None else p.returncode         # None: it ended while the loop was down
        log(f"agent {name} finished rc={rc} report={'present' if os.path.exists(report) else 'MISSING'}")
        for f in (f"{R}/pids/{name}.json",):
            if os.path.exists(f):
                os.remove(f)
        FINISHED.append(name)
        if name in ST["overdue"]:
            ST["overdue"].remove(name)
            save_state()


class Agent:
    """A worker's process group (its pid is the group id: start_new_session=True) and its deadline. `proc` is the
    Popen this loop started; an ADOPTED agent (started by a previous loop) has none and is polled by pid."""
    def __init__(self, name, pid, deadline, proc=None):
        self.name, self.pid, self.deadline, self.proc, self.returncode = name, pid, deadline, proc, None

    def poll(self):
        if self.returncode is None:
            if self.proc:
                self.returncode = self.proc.poll()
            elif not alive(self.pid):
                self.returncode = "?"                             # not our child: its exit status is unknowable
            if self.returncode is None and time.time() > self.deadline:
                log(f"agent {self.name} TIMED OUT (deadline passed) — terminating its process group")
                self.terminate()
                self.returncode = 124                              # timeout(1)'s code: lane-metrics counts it
        return self.returncode

    def terminate(self):
        killpg(self.pid)
        if self.proc:
            self.proc.wait()


def alive(pid):
    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False
    except PermissionError:
        return True


def write_pidfile(name, a, report):
    os.makedirs(f"{R}/pids", exist_ok=True)
    open(f"{R}/pids/{name}.json", "w").write(json.dumps({"pid": a.pid, "deadline": a.deadline, "report": report}))


def adopt_running():
    """Agents a previous loop started, from their pid files. A live pid whose command line is not this lane's
    agent (the pid was reused) is not adopted; an agent that ended while the loop was down is finished now."""
    out, gone = [], []
    for f in sorted(glob.glob(f"{R}/pids/*.json")):
        name = os.path.basename(f)[:-5]
        try:
            d = json.load(open(f))
        except (OSError, ValueError):
            os.remove(f)
            continue
        a = Agent(name, int(d["pid"]), float(d["deadline"]))
        cmd = sh(f"ps -ww -o args= -p {a.pid}").stdout              # ps, not /proc: macOS has no /proc
        if alive(a.pid) and f"{R}/wt/{name}" in cmd:
            out.append((a, d["report"], name))
            log(f"adopted running agent {name} (pid {a.pid})")
        else:
            a.returncode = "?"
            gone.append((a, d["report"], name))
    if gone:
        finish(gone)
    return out


def kill_agent(name, running, pending):
    """=== KILL name=… ===: terminate a running agent's process group, then commit its work like any finish."""
    for x in running:
        if x[2] == name and x[0].poll() is None:
            x[0].terminate()
            for _ in range(60):
                if x[0].poll() is not None:
                    break
                time.sleep(1)
            finish([x])
            running.remove(x)
            log(f"KILLED {name}")
            return
    if any(p[0] == name for p in pending):
        pending[:] = [p for p in pending if p[0] != name]
        log(f"KILLED {name} (was queued, never started)")
        return
    log(f"KILL {name}: no such running agent")


def started_at(report):
    """An agent's start = its prompt file's mtime (works for adopted agents too)."""
    pf = report.replace("/reports/", "/prompts/")
    return os.path.getmtime(pf) if pf != report and os.path.exists(pf) else None


def watch_reports(running):
    """Warn once per agent that is still running with no report file REPORT_OVERDUE_S after its start."""
    for proc, report, name in running:
        if proc.poll() is None and name not in ST["overdue"] and not os.path.exists(report):
            t0 = started_at(report)
            if t0 and time.time() - t0 > REPORT_OVERDUE_S:
                ST["overdue"].append(name)
                save_state()
                log(f"REPORT OVERDUE {name}: no report {int(time.time() - t0) // 60} min after start")


def valid_ref(ref):
    """A branch/base the supervisor named: never an option, never a revision expression, a legal branch name."""
    return (not ref.startswith("-") and "@{" not in ref
            and sh(f"cd {q(REPO)} && git check-ref-format --branch {q(ref)}").returncode == 0)


def refuse_block(what, why):
    """The supervisor's output is untrusted input: an invalid block is dropped, logged, and quoted back to it."""
    log(f"REFUSED {what}: {why}")
    ST["notes"].append(f"Your block `{what}` was refused ({why}); nothing was done for it.")
    save_state()


PROMOTE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "promote.py")


def coordinator(*args, rnd=0):
    """Ask the ONE trusted promotion coordinator (promote.py). The loop only requests; it decides and executes.
    Returns its JSON result; its notices reach the supervisor."""
    r = subprocess.run([sys.executable, PROMOTE, ORG_ROOT, *args, "--consult", str(rnd)], text=True, capture_output=True)
    try:
        res = json.loads(r.stdout.strip().splitlines()[-1])
    except (ValueError, IndexError):
        res = {"decision": "refused", "reason": f"coordinator error (exit {r.returncode}): {(r.stderr or r.stdout).strip()[-300:]}",
               "notices": [], "report": ""}
    for n in res.get("notices", []):
        log(f"RECONCILED: {n}")
        ST["notes"].append(n)
    if res.get("notices"):
        save_state()
    return res


def promotion(kind, br, rnd):
    """MERGE (into this lane's integration branch) or LAND (its integration branch into main), via the coordinator.
    Every refusal is logged, written where the supervisor and the overseer read, and quoted back to the supervisor."""
    res = coordinator("request", kind.lower(), R, br, rnd=rnd)
    d, why = res["decision"], res.get("reason", "")
    if d == "promoted":
        log(f"{kind} {br} ok ({res['sha'][:7]}, {res['prom']})")
    elif d == "nothing":
        log(f"{kind} {br}: nothing to {kind.lower()} ({why})")
        ST["notes"].append(f"{kind} {br}: nothing to {kind.lower()}, {why}.")
    else:
        rep = f"{R}/reports/{rnd:04d}-zz-{kind.lower()}-refused-{br.replace('/', '-')}.md"
        log(f"{kind} {br} REFUSED — {why}")
        open(rep, "w").write(f"# {kind} of {br} REFUSED (consult {rnd}, {res.get('prom')})\n\n{why}\n\n{res.get('report', '')}\n")
        ST["notes"].append(f"{kind} {br} was refused: {why}. See reports/{os.path.basename(rep)}.")
    save_state()


# ── main loop ────────────────────────────────────────────────────────────────────────────────────────
def main():
    # One user runs the whole org (remote: worker_user; local: the owner). No user switching: refuse instead.
    me = pwd.getpwuid(os.getuid()).pw_name
    if WORKER_USER and WORKER_USER != me:
        log(f"REFUSED to start: this lane runs as worker_user {WORKER_USER!r}, not {me!r} — start it as that user")
        sys.exit(2)
    for d in ("reports", "prompts", "logs", "rounds", "wt", "target", "renders/owner"):
        os.makedirs(f"{R}/{d}", exist_ok=True)
    # An empty or placeholder-filled brief would be sent to the supervisor as content: refuse instead.
    for f in ("context.md", "supervisor-brief.md"):
        text = rd(f"{R}/{f}")
        left = sorted(set(UNFILLED_RE.findall(text)))
        if not text.strip() or left:
            log(f"UNFILLED {f}: {'empty' if not text.strip() else ' '.join(left)} — fill it, then lanes.sh start")
            sys.exit(2)
    rnd = START_ROUND
    coordinator("reconcile", rnd=rnd)          # promotions a crash interrupted: finished or aborted, never replayed blind
    running, pending, candidates = adopt_running(), [], []
    while not stopped():
        if over_budget("consults", running):
            idle_until_rollover(running)
            continue
        reports = sorted(glob.glob(f"{R}/reports/*.md"), key=report_key)
        newest = reports[-6:]
        sh(f"cd {q(INT)} && git checkout -q {q(INT_BR)} 2>/dev/null; git reset -q --hard {q(INT_BR)}")
        watch_reports(running)
        branches = list(dict.fromkeys(candidates + [f"{PREFIX}/{n}" for n in FINISHED]))
        notes, ST["notes"] = ST["notes"], []
        prompt = (rd(f"{R}/supervisor-brief.md") + "\n\n" + rd(f"{R}/context.md")
                  + f"\n\n# CONSULT {rnd}  ({now():%Y-%m-%d %H:%M} UTC)\n"
                  + ("\n## Loop notices (act on these)\n" + "".join(f"- {n}\n" for n in notes) if notes else "")
                  + f"\n## Your lane memory (append-only LEARN journal: your durable lessons, newest last)\n{memory_tail()}\n"
                  + f"\n## Project index: decided, measured, tried and rejected (vault/Index.md)\n{rd(f'{INT}/vault/Index.md', '(none)')[:15000]}\n"
                  + f"\n## Your plan so far\n{rd(f'{R}/plan.md', '(none yet)')}\n"
                  + owner_block()
                  + f"\n## Agent reports (newest; TL;DR + head + tail of each; full files in {R}/reports/)\n"
                  + "\n".join(f"\n### {os.path.basename(p)}\n{report_digest(p)}" for p in newest)
                  + f"\n\nEarlier report files: {', '.join(os.path.basename(p) for p in reports[:-6]) or 'none'}\n"
                  + f"\n## Code: the lane branch, and the branches to judge\n{code_view(branches)}\n"
                  + "\n## Agents STILL RUNNING (do not re-dispatch; KILL one only for cause)\n"
                  + ("\n".join(f"- {x[2]}" + ("  (REPORT OVERDUE: no report file yet)" if x[2] in ST["overdue"] else "")
                               for x in running if x[0].poll() is None) or "- none")
                  + "\n## Agents queued\n" + ("\n".join(f"- {p[0]}" for p in pending) or "- none") + "\n"
                  + (f"\n## MEMORY CONSOLIDATION DUE (every {CONSOLIDATE_EVERY} consults)\nAlso emit === MEMORY_CONSOLIDATED === … === END MEMORY_CONSOLIDATED === : a deduplicated, still-true rewrite of your whole lane memory. The raw journal is archived, not lost.\n" if rnd % CONSOLIDATE_EVERY == 0 else ""))
        imgs = images(ST["last_consult"])
        ST["last_consult"] = time.time()
        FINISHED.clear()
        save_state()
        b = spend(running)
        b["consults"] += 1
        if time.time() - b.get("total_at", 0) >= 3600:
            log_total(b)
        save_state()
        log(f"=== CONSULT {rnd}: supervisor planning ({len(reports)} reports, {len(imgs)} images, {len(prompt)} chars)")
        out = consult(prompt, f"{R}/rounds/{rnd:04d}-supervisor.md", INT, imgs)
        if stopped():
            break
        if not out.strip():                       # the supervisor process failed: say why, in the log the feed watches
            err = " | ".join(rd(f"{R}/rounds/{rnd:04d}-supervisor.md.err").strip().splitlines()[:3])
            log(f"SUPERVISOR ERROR in consult {rnd}: empty output; stderr: {err[:300] or '(empty)'}")
        if not ACTION_RE.search(out):
            log(f"NO ACTIONABLE BLOCK in consult {rnd} ({len(out)} chars of output)")
            ST["notes"].append(f"Your previous consult ({rnd}) produced no actionable block (first 500 chars: "
                               f"{out.strip()[:500]!r}). Emit the blocks exactly as the brief specifies.")
            save_state()
        m = re.search(r"=== PLAN ===\n(.*?)\n=== END PLAN ===", out, re.S)
        if m:
            open(f"{R}/plan.md", "w").write(m.group(1))
        for note in re.findall(r"=== LEARN ===\n(.*?)\n=== END LEARN ===", out, re.S):
            with open(MEMORY, "a") as f:
                f.write(f"\n- {now():%Y-%m-%d} consult {rnd}: {note.strip()}\n")
            log(f"LEARN: {note.strip()[:160].replace(chr(10), ' ')}")
        m2 = re.search(r"=== MEMORY_CONSOLIDATED ===\n(.*?)\n=== END MEMORY_CONSOLIDATED ===", out, re.S)
        if m2 and m2.group(1).strip():
            if os.path.exists(MEMORY):
                os.rename(MEMORY, f"{R}/lane-memory.archive-{now():%Y%m%d-%H%M}.md")
            open(MEMORY, "w").write(f"# Lane memory (consolidated at consult {rnd}, {now():%Y-%m-%d})\n\n{m2.group(1).strip()}\n")
            log("lane memory consolidated (raw journal archived)")
        for qn in re.findall(r"=== ASK_OWNER ===\n(.*?)\n=== END ASK ===", out, re.S):
            with open(f"{R}/owner-questions.md", "a") as f:
                f.write(f"\n## Consult {rnd} ({now():%Y-%m-%d %H:%M} UTC)\n{qn}\n")
            log(f"ASK_OWNER: {qn[:200].replace(chr(10), ' ')}")
        for n in re.findall(r"=== KILL name=(\S+) ===", out):
            if not NAME_RE.match(n):
                refuse_block(f"KILL name={n}", "a name is 1-41 of a-z 0-9 -, starting alphanumeric")
                continue
            kill_agent(n, running, pending)
        merges, lands = [], []
        for kind, br in re.findall(r"=== (MERGE|LAND) branch=(\S+) ===", out):
            if not valid_ref(br):
                refuse_block(f"{kind} branch={br}", "not a legal branch name (git check-ref-format --branch)")
                continue
            (merges if kind == "MERGE" else lands).append(br)
        candidates = merges + lands
        for br in merges:
            promotion("MERGE", br, rnd)
        for br in lands:
            promotion("LAND", br, rnd)
        if re.search(r"^=== DONE ===", out, re.M):
            log("DONE claimed by the supervisor")
            res = coordinator("done", R, rnd=rnd)
            if res["decision"] == "verified":
                log(f"DONE verified: {res['reason']}")
            else:   # the mission is NOT complete: the lane halts (no consults burnt) and the owner is asked
                log(f"DONE NOT verified — {res['reason']} — lane halted, mission not complete")
                with open(f"{R}/owner-questions.md", "a") as f:
                    f.write(f"\n## Consult {rnd} ({now():%Y-%m-%d %H:%M} UTC) — DONE claimed, not verified\n{res['reason']}\n")
            break
        for n, mdl, base, b in re.findall(r"=== AGENT name=(\S+) model=(\S+)(?: base=(\S+))? ===\n(.*?)\n=== END AGENT ===", out, re.S):
            if not NAME_RE.match(n):
                refuse_block(f"AGENT name={n}", "a name is 1-41 of a-z 0-9 -, starting alphanumeric")
                continue
            if base and not valid_ref(base):
                refuse_block(f"AGENT name={n} base={base}", "not a legal branch name (git check-ref-format --branch)")
                continue
            if n in {x[2] for x in running} | {p[0] for p in pending}:
                log(f"agent {n} already running/queued — duplicate ignored")
                continue
            pending.append((n, mdl if mdl in MODELS else DEFAULT_MODEL, base or INT_BR, b))
        while not stopped():   # rolling dispatch
            while pending and len([x for x in running if x[0].poll() is None]) < MAX_PAR:
                if over_budget("starts", running):
                    break
                n, mdl, base, b = pending.pop(0)
                st = run_agent(n if not os.path.isdir(f"{R}/wt/{n}") else f"{n}-c{rnd}", mdl, base, b, rnd)
                if st:
                    coordinator("dispatch", R, st[2], f"{PREFIX}/{st[2]}", base, rnd=rnd)
                    running.append(st)
                    spend(running)["starts"] += 1
                    save_state()
            if pending and over_budget("starts", running) and not any(x[0].poll() is None for x in running):
                idle_until_rollover(running)
                break
            done = [x for x in running if x[0].poll() is not None]
            if done:
                finish(done)
                running = [x for x in running if x not in done]
                break
            if not running and not pending:
                log(f"nothing running; waiting {IDLE_WAIT_S // 60} min for owner answers / changes")
                for _ in range(max(1, IDLE_WAIT_S // POLL_S)):
                    if stopped():
                        break
                    time.sleep(POLL_S)
                break
            watch_reports(running)
            spend(running)
            save_state()
            time.sleep(POLL_S)
        rnd += 1
    if stopped():
        for x in running:
            x[0].terminate()
            x[0].poll()
        finish(running)
    log("supervisor loop exiting")


if __name__ == "__main__":
    main()
