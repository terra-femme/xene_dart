"""Chart lint — the gate between 'extracted' and 'blessed'.

Rules over a drum-events.json that catch charts which would feel BAD ON SKIN,
before a human wastes an audit pass or a bad chart reaches haptics:

  density      > 8 events/s in any rolling 1s window = WARN, > 10 = FAIL
               (vibrotactile parsing limit: the hand reads ~8-10 discrete
               events per second before pattern turns to undifferentiated buzz)
  min-gap      per-voice hits closer than the refractory floor
               (kick 110 / snare 100 / hat 70 ms — extract.py's defaults;
               extraction can't produce these, hand edits can)         = WARN
  coincident   kick+snare within 30 ms (flam-arbitration leftovers)    = WARN
  velocity     per-voice velocity std < 0.04 with n >= 8 (flat
               dynamics -> monotone feel)                              = WARN
  bounds       t < 0 or t > duration                                   = FAIL
  empty        a core voice with zero events                           = WARN

Exit code is the gate: 0 on PASS/WARN, 1 on any FAIL (--warn-only forces 0).
score.py measures quality; THIS decides shippability.

Usage (PowerShell):
  conda run -n xene-drums python lint_events.py track.drum-events.json
  conda run -n xene-drums python lint_events.py track.drum-events.json --report track.lint.json
"""

from __future__ import annotations

import argparse
import json
import logging
import sys
from pathlib import Path

from events_io import CORE_KINDS, add_verbosity_flag, apply_verbosity, load_events_json

logging.basicConfig(level=logging.INFO, format="%(levelname)s %(name)s %(message)s")
logger = logging.getLogger("lint_events")

DENSITY_WARN = 8   # events per rolling second
DENSITY_FAIL = 10
MIN_GAP_MS = {"kick": 110, "snare": 100, "hat": 70}
COINCIDENT_MS = 30
# 0.04, not 0.05: a two-level accent pattern (e.g. alternating 0.9/1.0)
# has std exactly 0.05 and is real dynamics, not flatness.
VEL_STD_FLOOR = 0.04
VEL_MIN_N = 8


def _finding(findings, level, rule, message):
    findings.append({"level": level, "rule": rule, "message": message})
    log = logger.error if level == "FAIL" else logger.warning
    log("[lint] %s %s: %s", level, rule, message)


def lint_density(events, findings):
    times = sorted(e["t"] for e in events if e["kind"] in CORE_KINDS)
    worst, worst_t = 0, 0.0
    j = 0
    for i, t in enumerate(times):
        while times[j] < t - 1.0:
            j += 1
        count = i - j + 1
        if count > worst:
            worst, worst_t = count, times[j]
    logger.info("[lint] density: worst rolling-1s window = %d events @ %.3fs", worst, worst_t)
    if worst > DENSITY_FAIL:
        _finding(findings, "FAIL", "density",
                 f"{worst} events in the 1s window starting {worst_t:.3f}s "
                 f"(limit {DENSITY_FAIL}; the hand reads buzz, not rhythm)")
    elif worst > DENSITY_WARN:
        _finding(findings, "WARN", "density",
                 f"{worst} events in the 1s window starting {worst_t:.3f}s (comfort limit {DENSITY_WARN})")


def lint_min_gap(by_kind, findings):
    for kind in CORE_KINDS:
        floor = MIN_GAP_MS[kind] / 1000.0
        times = [e["t"] for e in by_kind[kind]]
        offenders = [(a, b) for a, b in zip(times, times[1:]) if b - a < floor]
        logger.info("[lint] min-gap %s: %d violation(s) below %dms over %d hits",
                    kind, len(offenders), MIN_GAP_MS[kind], len(times))
        if offenders:
            a, b = offenders[0]
            _finding(findings, "WARN", "min-gap",
                     f"{len(offenders)} {kind} pair(s) closer than {MIN_GAP_MS[kind]}ms "
                     f"(first: {a:.3f}s -> {b:.3f}s = {(b - a) * 1000:.0f}ms)")


def lint_coincident(by_kind, findings):
    window = COINCIDENT_MS / 1000.0
    kicks = [e["t"] for e in by_kind["kick"]]
    snares = [e["t"] for e in by_kind["snare"]]
    pairs = []
    j = 0
    for t in kicks:
        while j < len(snares) and snares[j] < t - window:
            j += 1
        if j < len(snares) and abs(snares[j] - t) <= window:
            pairs.append(t)
    logger.info("[lint] coincident kick+snare: %d pair(s) within %dms", len(pairs), COINCIDENT_MS)
    if pairs:
        _finding(findings, "WARN", "coincident",
                 f"{len(pairs)} kick+snare pair(s) within {COINCIDENT_MS}ms (first @ {pairs[0]:.3f}s) "
                 f"— one physical hit to the hand; arbitration missed these or --keep-flams was used")


def lint_velocity(by_kind, findings):
    import numpy as np

    for kind in CORE_KINDS:
        vs = [e["v"] for e in by_kind[kind]]
        if len(vs) < VEL_MIN_N:
            continue
        std = float(np.std(vs))
        logger.info("[lint] velocity %s: n=%d std=%.3f", kind, len(vs), std)
        if std < VEL_STD_FLOOR:
            _finding(findings, "WARN", "velocity",
                     f"{kind} velocities are flat (std {std:.3f} over {len(vs)} hits) — monotone feel")


def lint_bounds(events, duration, findings):
    early = [e for e in events if e["t"] < 0]
    late = [e for e in events if duration and e["t"] > duration + 0.001]
    if early:
        _finding(findings, "FAIL", "bounds", f"{len(early)} event(s) before t=0")
    if late:
        _finding(findings, "FAIL", "bounds",
                 f"{len(late)} event(s) beyond duration {duration}s (first @ {late[0]['t']:.3f}s)")
    if not early and not late:
        logger.info("[lint] bounds: all %d events within [0, %s]", len(events), duration)


def lint_empty(by_kind, findings):
    for kind in CORE_KINDS:
        if not by_kind[kind]:
            _finding(findings, "WARN", "empty", f"ZERO {kind} events")


def run_lint(doc):
    events = [e for e in doc["events"] if e["kind"] in CORE_KINDS]
    by_kind = {k: [e for e in events if e["kind"] == k] for k in CORE_KINDS}
    findings = []
    if not events:
        _finding(findings, "FAIL", "empty", "no core-voice events at all")
    else:
        lint_density(events, findings)
        lint_min_gap(by_kind, findings)
        lint_coincident(by_kind, findings)
        lint_velocity(by_kind, findings)
        lint_bounds(events, doc.get("duration"), findings)
        lint_empty(by_kind, findings)

    fails = sum(1 for f in findings if f["level"] == "FAIL")
    warns = sum(1 for f in findings if f["level"] == "WARN")
    status = "FAIL" if fails else ("WARN" if warns else "PASS")
    return {"status": status, "fails": fails, "warns": warns, "findings": findings,
            "events": len(events)}


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("input", help="drum-events.json to lint")
    ap.add_argument("--report", help="also write a machine-readable JSON report here")
    ap.add_argument("--warn-only", action="store_true",
                    help="always exit 0, even on FAIL (report, don't gate)")
    add_verbosity_flag(ap)
    args = ap.parse_args()
    apply_verbosity(args)

    doc = load_events_json(args.input)
    result = run_lint(doc)

    print(f"\nlint {Path(args.input).name}: {result['status']} "
          f"({result['fails']} fail, {result['warns']} warn, {result['events']} events)")
    for f in result["findings"]:
        print(f"  {f['level']:<4} {f['rule']:<11} {f['message']}")
    if not result["findings"]:
        print("  clean — no findings")

    if args.report:
        Path(args.report).write_text(json.dumps(result, indent=2), encoding="utf-8")
        logger.info("[lint] wrote report %s", args.report)

    if result["status"] == "FAIL" and not args.warn_only:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
