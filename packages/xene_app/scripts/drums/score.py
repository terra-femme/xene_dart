"""Scoring harness: reference drum-events.json vs estimated drum-events.json.

Per-voice precision / recall / F-measure at a +/-tolerance window (default
50 ms, the community-standard onset-eval window), plus signed timing offset
stats (positive = estimate late). Uses mir_eval.onset.f_measure — the citable
standard implementation with maximum bipartite matching (greedy matching can
differ on dense hat patterns).

Rows:
  kick / snare / hat  — voice-aware scores (classification + timing)
  ANY                 — kind-agnostic pooled onsets (pure timing quality)
  micro               — micro-average over the three voices (TP-weighted)

The in-browser metrics panel in drum-lab.html is advisory; THIS script is the
source of truth. Exit code is always 0 unless inputs are invalid — it's a
report, not a gate.

Usage (PowerShell):
  conda run -n xene-drums python score.py truth.json extracted.json
  conda run -n xene-drums python score.py truth.json extracted.json --tol-ms 50 --offset-hist
"""

from __future__ import annotations

import argparse
import json
import logging
import sys
from pathlib import Path

from events_io import CORE_KINDS, events_by_kind, load_events_json

logging.basicConfig(level=logging.INFO, format="%(levelname)s %(name)s %(message)s")
logger = logging.getLogger("score")


def score_voice(ref_times, est_times, window):
    """Returns dict with n_ref, n_est, matched, P/R/F, offset mean/std (seconds)."""
    import mir_eval
    import numpy as np

    ref = np.asarray(ref_times, dtype=float)
    est = np.asarray(est_times, dtype=float)
    base = {"n_ref": len(ref), "n_est": len(est), "matched": 0,
            "P": 0.0, "R": 0.0, "F": 0.0, "mean_off": None, "std_off": None, "offsets": []}
    if len(ref) == 0 and len(est) == 0:
        # nothing to find and nothing found: vacuously perfect, flagged as empty
        return {**base, "P": 1.0, "R": 1.0, "F": 1.0, "empty": True}
    if len(ref) == 0 or len(est) == 0:
        return base

    f, p, r = mir_eval.onset.f_measure(ref, est, window=window)
    matching = mir_eval.util.match_events(ref, est, window)
    offsets = [est[j] - ref[i] for i, j in matching]
    return {
        **base,
        "matched": len(matching),
        "P": p, "R": r, "F": f,
        "mean_off": float(np.mean(offsets)) if offsets else None,
        "std_off": float(np.std(offsets)) if offsets else None,
        "offsets": offsets,
    }


def micro_average(voice_results):
    """TP-weighted pooled P/R/F across voices (classification-aware)."""
    tp = sum(r["matched"] for r in voice_results)
    n_est = sum(r["n_est"] for r in voice_results)
    n_ref = sum(r["n_ref"] for r in voice_results)
    p = tp / n_est if n_est else 0.0
    r = tp / n_ref if n_ref else 0.0
    f = 2 * p * r / (p + r) if (p + r) else 0.0
    offsets = [o for res in voice_results for o in res["offsets"]]
    import numpy as np
    return {
        "n_ref": n_ref, "n_est": n_est, "matched": tp, "P": p, "R": r, "F": f,
        "mean_off": float(np.mean(offsets)) if offsets else None,
        "std_off": float(np.std(offsets)) if offsets else None,
        "offsets": offsets,
    }


def fmt_row(label, res):
    ms = lambda v: f"{v * 1000:+7.1f}" if v is not None else "     --"
    return (
        f"{label:<6} {res['n_ref']:>5} {res['n_est']:>5} {res['matched']:>5}"
        f" {res['P']:>6.3f} {res['R']:>6.3f} {res['F']:>6.3f}"
        f" {ms(res['mean_off'])} {ms(res['std_off'])}"
    )


def print_offset_hist(offsets, window):
    """ASCII histogram of matched-pair offsets, 5 ms bins across the window."""
    import numpy as np

    if not offsets:
        print("\n(no matched pairs — no offset histogram)")
        return
    bin_ms = 5.0
    edges = np.arange(-window * 1000, window * 1000 + bin_ms, bin_ms)
    counts, _ = np.histogram(np.asarray(offsets) * 1000, bins=edges)
    peak = counts.max() or 1
    print(f"\nOffset histogram ({bin_ms:.0f} ms bins, negative = estimate early):")
    for lo, c in zip(edges[:-1], counts):
        if c:
            print(f"  {lo:+6.0f}..{lo + bin_ms:+6.0f} ms  {'#' * max(1, round(c / peak * 40))} {c}")


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("ref", help="reference drum-events.json (ground truth)")
    ap.add_argument("est", help="estimated drum-events.json (extraction output)")
    ap.add_argument("--tol-ms", type=float, default=50.0, help="match window in ms (default 50)")
    ap.add_argument("--report", help="also write a machine-readable JSON report here")
    ap.add_argument("--offset-hist", action="store_true", help="print ASCII offset histogram")
    args = ap.parse_args()

    ref_doc = load_events_json(args.ref)
    est_doc = load_events_json(args.est)
    window = args.tol_ms / 1000.0

    ref_by_kind = events_by_kind(ref_doc)
    est_by_kind = events_by_kind(est_doc)

    results = {}
    for kind in CORE_KINDS:
        results[kind] = score_voice(
            [e["t"] for e in ref_by_kind[kind]],
            [e["t"] for e in est_by_kind[kind]],
            window,
        )
        if results[kind].get("empty"):
            logger.warning("[score] voice '%s' empty in BOTH files", kind)

    any_res = score_voice(
        [e["t"] for e in ref_doc["events"] if e["kind"] in CORE_KINDS],
        [e["t"] for e in est_doc["events"] if e["kind"] in CORE_KINDS],
        window,
    )
    micro = micro_average([results[k] for k in CORE_KINDS])

    print(f"\nref: {args.ref}  ({ref_doc['source']}/{ref_doc['generator']})")
    print(f"est: {args.est}  ({est_doc['source']}/{est_doc['generator']})")
    print(f"tolerance: +/-{args.tol_ms:.0f} ms\n")
    print(f"{'voice':<6} {'nRef':>5} {'nEst':>5} {'match':>5} {'P':>6} {'R':>6} {'F':>6}"
          f" {'off ms':>7} {'std ms':>7}")
    print("-" * 60)
    for kind in CORE_KINDS:
        print(fmt_row(kind, results[kind]))
    print("-" * 60)
    print(fmt_row("ANY", any_res))
    print(fmt_row("micro", micro))

    if args.offset_hist:
        print_offset_hist(micro["offsets"], window)

    if args.report:
        strip = lambda r: {k: v for k, v in r.items() if k != "offsets"}
        report = {
            "ref": str(Path(args.ref)), "est": str(Path(args.est)),
            "tolMs": args.tol_ms,
            "voices": {k: strip(results[k]) for k in CORE_KINDS},
            "any": strip(any_res), "micro": strip(micro),
        }
        Path(args.report).write_text(json.dumps(report, indent=2), encoding="utf-8")
        logger.info("[score] wrote report %s", args.report)

    return 0


if __name__ == "__main__":
    sys.exit(main())
