#!/usr/bin/env python3
"""Per-lane, per-day health of the org, read from each lanes/*/lane.log (the loop's own log, nothing else).

  python3 lane-metrics.py <ORG_ROOT> [--days N] [--json]

Columns: consults, dispatches, finished, report missing, rc timeouts (124), merges ok, merges refused (of them
conflicts), lands, lands refused, KILLs, NO ACTIONABLE BLOCK, reconciled promotions, DONE verified / not verified,
median dispatch→finish and dispatch→merge minutes.
Log lines are "YYYY-MM-DD HH:MM msg". Older "HH:MM msg" lines are dated from their neighbours: forward from
the last dated line before them, backward from the first dated line after them (or from the log's mtime if
no line is dated), a day changing whenever the clock runs the other way. The loop logs at least every idle
wait (20 min), so a silent gap of a whole day, the one case this misdates, does not occur in a live lane.
"""
import argparse, datetime, glob, json, os, re, statistics

LINE = re.compile(r"^(?:(\d{4}-\d{2}-\d{2}) )?(\d{2}):(\d{2}) (.*)$")
COUNTS = [  # (column, pattern on the message)
    ("consults", r"^=== CONSULT \d+"),
    ("dispatches", r"^agent \S+ \(\S+\) start on "),
    ("finished", r"^agent \S+ finished rc="),
    ("report_missing", r"^agent \S+ finished rc=\S+ report=MISSING"),
    ("rc_timeouts", r"^agent \S+ finished rc=124 "),
    ("merges_ok", r"^MERGE \S+ ok"),
    ("merges_refused", r"^MERGE \S+ REFUSED"),                     # promote.py: scope, gates, verification, conflict
    ("merge_conflicts", r"^MERGE \S+ (?:REFUSED — )?CONFLICT"),       # "REFUSED — CONFLICT …" (coordinator) or older "CONFLICT"
    ("lands", r"^LAND \S+ ok"),
    ("lands_refused", r"^LAND \S+ (REFUSED|CONFLICT)"),
    ("kills", r"^KILLED \S+"),
    ("no_action", r"^NO ACTIONABLE BLOCK"),
    ("reconciled", r"^RECONCILED"),                                  # a promotion interrupted by a crash, settled on restart
    ("done_verified", r"^DONE verified"),
    ("done_not_verified", r"^DONE NOT verified"),
]
COLS = [c for c, _ in COUNTS] + ["med_finish_min", "med_merge_min"]


def events(path):
    """Return [(datetime, day label, message)] for every timestamped line, dating the undated ones."""
    lines = [m.groups() for m in map(LINE.match, open(path, errors="replace").read().splitlines()) if m]
    if not lines:
        return []
    anchor = next((i for i, l in enumerate(lines) if l[0]), None)
    if anchor is None:                                   # nothing dated: the last line was written on the mtime's day
        anchor, day0 = len(lines) - 1, datetime.datetime.fromtimestamp(os.path.getmtime(path), datetime.timezone.utc).date()
    else:
        day0 = datetime.date.fromisoformat(lines[anchor][0])
    hm = lambda l: (int(l[1]), int(l[2]))
    days = [None] * len(lines)
    days[anchor] = day0
    for i in range(anchor - 1, -1, -1):                  # backward: the clock running forward means the day before
        days[i] = days[i + 1] - datetime.timedelta(days=1) if hm(lines[i]) > hm(lines[i + 1]) else days[i + 1]
    for i in range(anchor + 1, len(lines)):              # forward: a date wins; else the clock running back = next day
        d = lines[i][0]
        days[i] = (datetime.date.fromisoformat(d) if d else
                   days[i - 1] + datetime.timedelta(days=1) if hm(lines[i]) < hm(lines[i - 1]) else days[i - 1])
    return [(datetime.datetime.combine(day, datetime.time(*hm(l))), day.isoformat(), l[3]) for day, l in zip(days, lines)]


def lane_rows(path):
    rows, starts, fin, mer = {}, {}, {}, {}
    for ts, day, msg in events(path):
        row = rows.setdefault(day, {c: 0 for c, _ in COUNTS})
        for col, pat in COUNTS:
            if re.search(pat, msg):
                row[col] += 1
        if m := re.match(r"agent (\S+) \(\S+\) start on ", msg):
            starts[m.group(1)] = ts
        elif (m := re.match(r"agent (\S+) finished rc=", msg)) and m.group(1) in starts:
            fin.setdefault(day, []).append((ts - starts[m.group(1)]).total_seconds() / 60)
        elif (m := re.match(r"MERGE (\S+) ok", msg)) and m.group(1).rsplit("/", 1)[-1] in starts:
            mer.setdefault(day, []).append((ts - starts[m.group(1).rsplit("/", 1)[-1]]).total_seconds() / 60)
    for day, row in rows.items():
        row["med_finish_min"] = round(statistics.median(fin[day])) if fin.get(day) else None
        row["med_merge_min"] = round(statistics.median(mer[day])) if mer.get(day) else None
    return rows


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("org_root")
    ap.add_argument("--days", type=int, default=7, help="only the last N days (0 = all)")
    ap.add_argument("--json", action="store_true")
    a = ap.parse_args()
    cutoff = (datetime.date.today() - datetime.timedelta(days=a.days - 1)).isoformat() if a.days > 0 else ""
    if not os.path.isdir(os.path.join(a.org_root, "lanes")):
        ap.exit(2, f"lane-metrics: no lanes/ under {a.org_root}\n")
    out = {}
    for log in sorted(glob.glob(os.path.join(a.org_root, "lanes", "*", "lane.log"))):
        rows = lane_rows(log)
        out[os.path.basename(os.path.dirname(log))] = {d: r for d, r in sorted(rows.items()) if d >= cutoff}
    if a.json:
        print(json.dumps(out, indent=1))
        return
    heads = ["lane", "day", "cons", "disp", "fin", "norep", "t/o", "merge", "mrefus", "confl", "land", "lrefus", "kill", "noact",
             "recon", "done", "!done", "fin_m", "mrg_m"]
    assert len(heads) == 2 + len(COLS)   # one head per column, positionally
    table = [[lane, day] + ["-" if r[c] is None else str(r[c]) for c in COLS] for lane, rows in out.items() for day, r in rows.items()]
    widths = [max(len(x) for x in col) for col in zip(heads, *table)]
    for line in [heads] + table:
        print("  ".join(x.ljust(w) if i < 2 else x.rjust(w) for i, (x, w) in enumerate(zip(line, widths))))
    if not table:
        print("(no lane activity in range)")


if __name__ == "__main__":
    main()
