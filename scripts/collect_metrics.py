#!/usr/bin/env python3
"""
collect_metrics.py — populate Tables 8.1, 8.2, and 8.3 from the thesis.

Reads:
  --log    events.csv      (from PADDING_LEAK_LOG during checker run)
  --cc     results.json    (from CodeChecker parse --export json)
  --project NAME           (label for the table row, e.g. "zlib")
  --baseline-ms INT        (optional: baseline timing from run_codechecker.sh)
  --checker-ms  INT        (optional: checker timing from run_codechecker.sh)

Outputs:
  - Table 8.1 row: |B|, |EB|, Nrec, Npad, NE2, NE3
  - Table 8.2 row: Nsup, rpad, rdiag
  - Table 8.3 row: baseline, with-checker, overhead%
  - A markdown summary for easy thesis copy-paste

Usage:
  python3 scripts/collect_metrics.py \\
    --project zlib \\
    --log events.csv \\
    --cc cc-results/json/results.json \\
    --baseline-ms 4200 \\
    --checker-ms 4580
"""

import argparse #handles command-lines flags
import csv      #reads event logs
import json     #reads CodeChecker export
import sys      #output formatting
from pathlib import Path    #cross-platform file handling


def load_events(log_path: str) -> list[dict]:
    #Parse the CSV event log written by the checker.
    path = Path(log_path)
    if not path.exists():
        print(f"[WARN] Event log not found: {log_path}", file=sys.stderr)
        return []
    rows = []
    with open(path) as f:
        reader = csv.DictReader(f)
        for row in reader:
            rows.append(row)
    return rows


def load_codechecker_json(cc_path: str) -> list[dict]:
    #Parse CodeChecker --export json output.
    path = Path(cc_path)
    if not path.exists():
        print(f"[WARN] CodeChecker JSON not found: {cc_path}", file=sys.stderr)
        return []
    with open(path) as f:
        data = json.load(f)
    # CodeChecker JSON is a list of report objects
    if isinstance(data, list):
        return data
    # Some versions wrap in {"reports": [...]}
    return data.get("reports", [])


def compute_table81(events: list[dict], reports: list[dict]) -> dict:
    #Table 8.1: |B|, |EB|, Nrec, Npad, NE2, NE3
    boundary_fns = set()
    all_record_types = set()
    padded_types = set()
    E2_count = 0
    E3_count = 0

    for e in events:
        boundary_fns.add(e["boundary_fn"])
        all_record_types.add(e["type_name"])
        if e["has_padding"].lower() == "true":
            padded_types.add(e["type_name"])

    # Count E2/E3 from event log (diag_emitted=true)
    for e in events:
        if e.get("diag_emitted", "false").lower() != "true":
            continue
        lvl = e.get("evidence_level", "")
        if lvl == "E3":
            E3_count += 1
        elif lvl == "E2":
            E2_count += 1

    # Also cross-check against CodeChecker reports
    cc_diags = [r for r in reports
                if "security-misc-padding-boundary-leak" in
                   r.get("checkerId", r.get("checker_name", ""))]

    return {
        "|B|":   len(boundary_fns),
        "|EB|":  len(events),
        "Nrec":  len(all_record_types),
        "Npad":  len(padded_types),
        "NE2":   E2_count,
        "NE3":   E3_count,
        "cc_diags": len(cc_diags),
    }


def compute_table82(events: list[dict], t81: dict) -> dict:
    #Table 8.2: Nsup, rpad, rdiag, revent
    #Nsup = events where has_padding=true but diag_emitted=false (suppressed)
    Nsup = sum(
        1 for e in events
        if e.get("has_padding", "false").lower() == "true"
        and e.get("init_class", "") == "whole_object"
        and e.get("diag_emitted", "false").lower() == "false"
    )

    Nrec   = max(1, t81["Nrec"])
    EB     = max(1, t81["|EB|"])
    B      = max(1, t81["|B|"])
    NE_tot = t81["NE2"] + t81["NE3"]

    rpad  = t81["Npad"] / Nrec
    rdiag = NE_tot / EB
    revent = EB / B

    return {
        "Nsup":    Nsup,
        "rpad":    round(rpad, 3),
        "rdiag":   round(rdiag, 3),
        "revent":  round(revent, 3),
    }


def compute_table83(baseline_ms: int, checker_ms: int) -> dict:
    #Table 8.3: timing and overhead.
    if baseline_ms > 0 and checker_ms > 0:
        overhead = 100 * (checker_ms - baseline_ms) / baseline_ms
    else:
        overhead = None
    return {
        "baseline_ms":  baseline_ms,
        "checker_ms":   checker_ms,
        "overhead_pct": round(overhead, 1) if overhead is not None else "—",
    }


def print_tables(project: str, t81: dict, t82: dict, t83: dict) -> None:
    print()
    print("=" * 64)
    print(f"  Thesis metrics for project: {project}")
    print("=" * 64)

    print()
    print("Table 8.1 — Boundary interfaces, events, record types, diagnostics")
    print(f"  Project : {project}")
    print(f"  |B|     : {t81['|B|']}")
    print(f"  |EB|    : {t81['|EB|']}")
    print(f"  Nrec    : {t81['Nrec']}")
    print(f"  Npad    : {t81['Npad']}")
    print(f"  NE2     : {t81['NE2']}")
    print(f"  NE3     : {t81['NE3']}")
    print(f"  (CodeChecker cross-check: {t81['cc_diags']} security-misc diags)")

    print()
    print("Table 8.2 — Suppression and rate metrics")
    print(f"  Project : {project}")
    print(f"  Nsup    : {t82['Nsup']}")
    print(f"  rpad    : {t82['rpad']}   (Npad / Nrec)")
    print(f"  rdiag   : {t82['rdiag']}  ((NE2+NE3) / |EB|)")
    print(f"  revent  : {t82['revent']}  (|EB| / |B|)")

    print()
    print("Table 8.3 — Performance")
    print(f"  Project      : {project}")
    print(f"  Baseline     : {t83['baseline_ms']} ms")
    print(f"  With checker : {t83['checker_ms']} ms")
    print(f"  Overhead     : {t83['overhead_pct']}%")

    print()
    print("--- Markdown row (copy into thesis Tables) ---")
    print(f"| {project:10s} | {t81['|B|']:3} | {t81['|EB|']:4} | "
          f"{t81['Nrec']:5} | {t81['Npad']:5} | {t81['NE2']:4} | "
          f"{t81['NE3']:4} | {t82['Nsup']:5} | {t82['rpad']:6.3f} | "
          f"{t82['rdiag']:6.3f} | {t83['baseline_ms']:7} | "
          f"{t83['checker_ms']:7} | {t83['overhead_pct']}% |")
    print()


def main() -> None:
    parser = argparse.ArgumentParser(description="Collect thesis evaluation metrics.")
    parser.add_argument("--project",      default="unknown", help="Project name label")
    parser.add_argument("--log",          required=True,     help="Path to events.csv")
    parser.add_argument("--cc",           default="",        help="Path to CodeChecker JSON export")
    parser.add_argument("--baseline-ms",  type=int, default=0)
    parser.add_argument("--checker-ms",   type=int, default=0)
    args = parser.parse_args()

    events  = load_events(args.log)
    reports = load_codechecker_json(args.cc) if args.cc else []

    t81 = compute_table81(events, reports)
    t82 = compute_table82(events, t81)
    t83 = compute_table83(args.baseline_ms, args.checker_ms)

    print_tables(args.project, t81, t82, t83)


if __name__ == "__main__":
    main()
