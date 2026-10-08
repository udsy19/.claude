#!/usr/bin/env python3
"""orgstate — the org's canonical state: one SQLite DB per org (ORG_ROOT/state/org.db), stdlib only.

Events are the truth: an append-only, gapless, hash-chained `events` table. The entity tables (missions,
acceptance_criteria, promotions, verifications, artifacts) are an index updated IN THE SAME TRANSACTION and
rebuildable from the events. Writers serialize with BEGIN IMMEDIATE. Only the coordinator (and later the verifier)
write, as the org's user; workers never reach ORG_ROOT.

Git is not a second writable truth: export_journal() appends the events as JSONL to ORG_ROOT/state/journal/
(segments) and commits them to the branch `state/journal` of the repo's origin, read-only for everyone else.

    python3 orgstate.py <ORG_ROOT> verify          chain intact? (exit 0/1)
    python3 orgstate.py <ORG_ROOT> rebuild <db>    replay ORG_ROOT/state/journal/*.jsonl into a fresh db, print head
    python3 orgstate.py <ORG_ROOT> head            seq and hash of the newest event
"""
import contextlib
import glob
import hashlib
import json
import os
import sqlite3
import sys
import time
from datetime import datetime, timezone

SCHEMA = 1
ENVELOPE = ("seq", "id", "ts", "type", "schema", "entity", "actor", "auth", "causation", "correlation", "payload")
DDL = """
CREATE TABLE IF NOT EXISTS events (
  seq INTEGER PRIMARY KEY, id TEXT UNIQUE NOT NULL, ts TEXT NOT NULL, type TEXT NOT NULL, schema INTEGER NOT NULL,
  entity TEXT, actor TEXT NOT NULL, auth TEXT NOT NULL, causation TEXT, correlation TEXT, payload TEXT NOT NULL,
  prev_hash TEXT NOT NULL, hash TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS counters (prefix TEXT PRIMARY KEY, n INTEGER NOT NULL);
CREATE TABLE IF NOT EXISTS missions (id TEXT PRIMARY KEY, slug TEXT UNIQUE, title TEXT, source TEXT, authored_by TEXT);
CREATE TABLE IF NOT EXISTS acceptance_criteria (id TEXT PRIMARY KEY, mission TEXT, key TEXT, text TEXT, check_json TEXT,
  authored_by TEXT, UNIQUE (mission, key));
CREATE TABLE IF NOT EXISTS promotions (id TEXT PRIMARY KEY, lane TEXT, op TEXT, requested_ref TEXT, candidate_sha TEXT,
  target TEXT, base_sha TEXT, merged_tree_sha TEXT, state TEXT, target_before TEXT, target_after TEXT, reason TEXT);
CREATE TABLE IF NOT EXISTS verifications (id TEXT PRIMARY KEY, promotion TEXT, kind TEXT, name TEXT, cmd TEXT,
  tree_sha TEXT, commit_sha TEXT, started TEXT, ended TEXT, exit INTEGER, env TEXT, log TEXT, ac TEXT);
CREATE TABLE IF NOT EXISTS artifacts (id TEXT PRIMARY KEY, sha256 TEXT UNIQUE, bytes INTEGER, media TEXT, produced_by TEXT);
CREATE TABLE IF NOT EXISTS dispatches (lane TEXT, agent TEXT, branch TEXT, base TEXT, consult INTEGER,
  PRIMARY KEY (lane, branch));
"""
GENESIS = "0" * 64


def utc():
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%fZ")


def canon(obj):
    return json.dumps(obj, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def ev_hash(prev, ev):
    return hashlib.sha256((prev + canon({k: ev[k] for k in ENVELOPE})).encode()).hexdigest()


def new_id():
    # ULID-shaped: 48-bit ms time + 80 random bits, Crockford base32 — sortable by time
    alphabet = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"
    n = (int(time.time() * 1000) << 80) | int.from_bytes(os.urandom(10), "big")
    return "evt_" + "".join(alphabet[(n >> (5 * i)) & 31] for i in range(25, -1, -1))


def state_dir(org_root):
    return os.path.join(org_root, "state")


def open_db(org_root, path=None):
    d = state_dir(org_root)
    os.makedirs(os.path.join(d, "artifacts"), exist_ok=True)
    conn = sqlite3.connect(path or os.path.join(d, "org.db"), timeout=60, isolation_level=None)
    conn.execute("PRAGMA journal_mode=WAL")
    conn.execute("PRAGMA synchronous=FULL")
    conn.executescript(DDL)
    return conn


@contextlib.contextmanager
def tx(conn):
    """One writer at a time: BEGIN IMMEDIATE takes the write lock up front (no upgrade deadlocks)."""
    conn.execute("BEGIN IMMEDIATE")
    try:
        yield conn
        conn.execute("COMMIT")
    except BaseException:
        conn.execute("ROLLBACK")
        raise


def next_id(conn, prefix):
    row = conn.execute("SELECT n FROM counters WHERE prefix=?", (prefix,)).fetchone()
    n = (row[0] if row else 0) + 1
    conn.execute("INSERT OR REPLACE INTO counters (prefix, n) VALUES (?, ?)", (prefix, n))
    return f"{prefix}-{n:04d}"


def append(conn, type_, entity, actor, auth, payload, causation=None, correlation=None):
    """Append one event inside the caller's transaction; returns its id. Never edits or deletes an event."""
    last = conn.execute("SELECT seq, hash FROM events ORDER BY seq DESC LIMIT 1").fetchone()
    seq, prev = (last[0] + 1, last[1]) if last else (1, GENESIS)
    ev = {"seq": seq, "id": new_id(), "ts": utc(), "type": type_, "schema": SCHEMA, "entity": entity, "actor": actor,
          "auth": auth, "causation": causation, "correlation": correlation, "payload": canon(payload)}
    h = ev_hash(prev, ev)
    conn.execute("INSERT INTO events (seq, id, ts, type, schema, entity, actor, auth, causation, correlation, payload, "
                 "prev_hash, hash) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)",
                 tuple(ev[k] for k in ENVELOPE) + (prev, h))
    apply(conn, ev)
    return ev["id"]


def apply(conn, ev):
    """Project one event onto the entity tables (the same code rebuilds them from the journal)."""
    p, t, e = json.loads(ev["payload"]), ev["type"], ev["entity"]
    if t == "mission.defined":
        conn.execute("INSERT OR REPLACE INTO missions VALUES (?,?,?,?,?)", (e, p["slug"], p.get("title"), p.get("source"), p.get("authored_by", ev["actor"])))
    elif t == "acceptance.defined":
        conn.execute("INSERT OR REPLACE INTO acceptance_criteria VALUES (?,?,?,?,?,?)",
                     (e, p["mission"], p["key"], p["text"], canon(p["check"]), p.get("authored_by", ev["actor"])))
    elif t == "dispatch.recorded":
        conn.execute("INSERT OR REPLACE INTO dispatches VALUES (?,?,?,?,?)", (p["lane"], p["agent"], p["branch"], p.get("base"), p.get("consult")))
    elif t == "promotion.requested":
        conn.execute("INSERT INTO promotions (id, lane, op, requested_ref, target, state) VALUES (?,?,?,?,?, 'requested')",
                     (e, p["lane"], p["op"], p["ref"], p["target"]))
    elif t == "promotion.verifying":
        conn.execute("UPDATE promotions SET state='verifying', base_sha=?, candidate_sha=?, merged_tree_sha=?, target_before=? WHERE id=?",
                     (p["base_sha"], p["candidate_sha"], p["merged_tree_sha"], p["target_before"], e))
    elif t in ("promotion.promoted", "promotion.refused", "promotion.aborted"):
        conn.execute("UPDATE promotions SET state=?, target_after=?, reason=? WHERE id=?",
                     (t.split(".")[1], p.get("target_after"), p.get("reason"), e))
    elif t == "verification.recorded":
        conn.execute("INSERT INTO verifications VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)",
                     (e, p.get("promotion"), p["kind"], p["name"], p.get("cmd"), p["tree_sha"], p.get("commit_sha"),
                      p["started"], p["ended"], p["exit"], canon(p.get("env", {})), p.get("log"), p.get("ac")))
    elif t == "artifact.stored":
        conn.execute("INSERT OR IGNORE INTO artifacts VALUES (?,?,?,?,?)", (e, p["sha256"], p["bytes"], p.get("media"), p.get("produced_by")))
    if e and "-" in e:     # keep counters ahead of every id seen (rebuilds allocate after the replayed ones)
        prefix, _, n = e.rpartition("-")
        if n.isdigit():
            conn.execute("INSERT INTO counters (prefix, n) VALUES (?, ?) ON CONFLICT(prefix) DO UPDATE SET n=max(n, excluded.n)",
                         (prefix, int(n)))


def put_artifact(conn, org_root, path, actor, auth, media="text/plain", produced_by=None, correlation=None):
    """Store a file content-addressed (ORG_ROOT/state/artifacts/<sha256>, mode 0444) and record it. -> (EVD id, sha256)."""
    data = open(path, "rb").read()
    sha = hashlib.sha256(data).hexdigest()
    dst = os.path.join(state_dir(org_root), "artifacts", sha)
    if not os.path.exists(dst):
        tmp = dst + f".tmp{os.getpid()}"
        with open(tmp, "wb") as f:
            f.write(data)
            f.flush()
            os.fsync(f.fileno())
        os.chmod(tmp, 0o444)
        os.replace(tmp, dst)
    row = conn.execute("SELECT id FROM artifacts WHERE sha256=?", (sha,)).fetchone()
    if row:
        return row[0], sha
    evd = next_id(conn, "EVD")
    append(conn, "artifact.stored", evd, actor, auth, {"sha256": sha, "bytes": len(data), "media": media,
                                                       "produced_by": produced_by}, correlation=correlation)
    return evd, sha


def events_after(conn, seq):
    cols = ENVELOPE + ("prev_hash", "hash")
    return [dict(zip(cols, r)) for r in conn.execute(f"SELECT {', '.join(cols)} FROM events WHERE seq > ? ORDER BY seq", (seq,))]


def verify_chain(conn):
    """(ok, problem): every event's hash recomputes from its predecessor and its own fields, with no gaps."""
    prev, expect = GENESIS, 1
    for ev in events_after(conn, 0):
        if ev["seq"] != expect:
            return False, f"gap: expected seq {expect}, found {ev['seq']}"
        if ev["prev_hash"] != prev or ev_hash(prev, ev) != ev["hash"]:
            return False, f"hash mismatch at seq {ev['seq']} ({ev['type']} {ev['entity']})"
        prev, expect = ev["hash"], expect + 1
    return True, ""


def head(conn):
    r = conn.execute("SELECT seq, hash FROM events ORDER BY seq DESC LIMIT 1").fetchone()
    return (r[0], r[1]) if r else (0, GENESIS)


def export_journal(org_root, conn=None):
    """Append events not yet exported to ORG_ROOT/state/journal/<first-seq>.jsonl (one JSON object per line, the
    full envelope with prev_hash and hash). Append-only; returns the number of events written."""
    own = conn is None
    conn = conn or open_db(org_root)
    try:
        jdir = os.path.join(state_dir(org_root), "journal")
        os.makedirs(jdir, exist_ok=True)
        done = 0
        for f in glob.glob(os.path.join(jdir, "*.jsonl")):
            for line in open(f):
                if line.strip():
                    done = max(done, json.loads(line)["seq"])
        evs = events_after(conn, done)
        if evs:
            seg = os.path.join(jdir, f"{evs[0]['seq']:08d}.jsonl")
            with open(seg + ".tmp", "w") as f:
                for ev in evs:
                    f.write(canon(ev) + "\n")
                f.flush()
                os.fsync(f.fileno())
            os.replace(seg + ".tmp", seg)
        return len(evs)
    finally:
        if own:
            conn.close()


def rebuild(org_root, db_path):
    """Replay the exported journal into a fresh db at db_path (verifying every hash). Returns its head."""
    if os.path.exists(db_path):
        os.remove(db_path)
    conn = open_db(org_root, db_path)
    prev = GENESIS
    for f in sorted(glob.glob(os.path.join(state_dir(org_root), "journal", "*.jsonl"))):
        for line in open(f):
            if not line.strip():
                continue
            ev = json.loads(line)
            if ev["prev_hash"] != prev or ev_hash(prev, ev) != ev["hash"]:
                raise ValueError(f"journal hash mismatch at seq {ev['seq']}")
            with tx(conn):
                conn.execute("INSERT INTO events (seq, id, ts, type, schema, entity, actor, auth, causation, correlation, "
                             "payload, prev_hash, hash) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)",
                             tuple(ev[k] for k in ENVELOPE) + (ev["prev_hash"], ev["hash"]))
                apply(conn, ev)
            prev = ev["hash"]
    h = head(conn)
    conn.close()
    return h


if __name__ == "__main__":
    org, cmd = sys.argv[1], sys.argv[2]
    if cmd == "verify":
        c = open_db(org)
        ok, why = verify_chain(c)
        print("chain ok" if ok else f"CHAIN BROKEN: {why}")
        sys.exit(0 if ok else 1)
    if cmd == "head":
        print("%d %s" % head(open_db(org)))
    elif cmd == "rebuild":
        print("%d %s" % rebuild(org, sys.argv[3]))
    elif cmd == "export":
        print(export_journal(org))
    else:
        sys.exit(f"unknown command {cmd}")
