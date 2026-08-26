"""Re-apply a drum-lab correction layer to a fresh extraction.

Your manual edits in drum-lab (kick adds, false-beat deletes) are stored in the
edited export's `corrections` block. When you later re-extract a track with an
improved pipeline, the fresh chart has NONE of those edits. Run this to inherit
them automatically instead of redoing them by hand:

  conda run -n xene-drums python apply_corrections.py \\
      fresh.drum-events.json  my_edit.drum-events.json  -o merged.drum-events.json

`fresh` = the new (re-extracted) chart. `corrections` = any edited export that
carries a `corrections` block (drum-lab embeds one on every Export). Deletes are
matched to the nearest fresh hit of the same voice within the tolerance; adds are
inserted. The tolerance defaults to the one recorded in the corrections block.
"""

from __future__ import annotations

import argparse
import json
import logging
import sys
from pathlib import Path

from events_io import load_events_json, write_events_json

logging.basicConfig(level=logging.INFO, format="%(levelname)s %(name)s %(message)s")
logger = logging.getLogger("apply_corrections")


def apply_corrections(fresh_events, corr, tol_s):
    """Return fresh_events with the correction layer applied (pure; sorts result)."""
    events = [dict(e) for e in fresh_events]
    deleted = corr.get("deleted", [])
    added = corr.get("added", [])

    removed = 0
    for d in deleted:
        best_i, best_dt = -1, tol_s + 1e-9
        for i, e in enumerate(events):
            if e["kind"] != d["kind"]:
                continue
            dt = abs(e["t"] - d["t"])
            if dt < best_dt:
                best_dt, best_i = dt, i
        if best_i >= 0:
            logger.debug("[apply] delete %s@%.3f -> removed fresh hit @%.3f",
                         d["kind"], d["t"], events[best_i]["t"])
            events.pop(best_i)
            removed += 1
        else:
            logger.debug("[apply] delete %s@%.3f -> no fresh hit within tol (already gone)",
                         d["kind"], d["t"])

    for a in added:
        events.append({"t": float(a["t"]), "kind": a["kind"], "v": float(a.get("v", 0.8))})

    events.sort(key=lambda e: (e["t"], e["kind"] if isinstance(e["kind"], str) else ""))
    return events, removed


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("fresh", help="the new (re-extracted) drum-events.json")
    ap.add_argument("corrections", help="an edited export carrying a 'corrections' block")
    ap.add_argument("-o", "--out", help="output path (default: <fresh>.merged.drum-events.json)")
    ap.add_argument("--tol-ms", type=float, default=None,
                    help="override the match tolerance (default: the one in the corrections block)")
    args = ap.parse_args()

    fresh = load_events_json(Path(args.fresh))
    corr_doc = json.loads(Path(args.corrections).read_text(encoding="utf-8"))
    corr = corr_doc.get("corrections")
    if not corr:
        raise SystemExit(f"no 'corrections' block in {args.corrections} — export it from drum-lab "
                         "(every Export embeds one)")

    tol_ms = args.tol_ms if args.tol_ms is not None else corr.get("tolMs", 50)
    events, removed = apply_corrections(fresh["events"], corr, tol_ms / 1000.0)

    added = corr.get("added", [])
    deleted = corr.get("deleted", [])
    logger.info("[apply] +%d added, -%d/%d deleted (matched within %.0f ms)",
                len(added), removed, len(deleted), tol_ms)

    out_path = Path(args.out) if args.out else Path(args.fresh).with_suffix(".merged.drum-events.json")
    write_events_json(
        out_path,
        source="manual",
        generator="apply_corrections 1.0",
        source_file=fresh.get("sourceFile", ""),
        duration=fresh["duration"],
        events=events,
        params={
            "mergedFrom": Path(args.fresh).name,
            "corrections": Path(args.corrections).name,
            "tolMs": tol_ms,
            "applied": {"added": len(added), "deletedMatched": removed, "deletedRequested": len(deleted)},
        },
    )


if __name__ == "__main__":
    sys.exit(main())
