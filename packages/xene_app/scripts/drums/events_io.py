"""Shared I/O for the drum-events.json contract (schema v1).

Single source of truth for the schema on the Python side; drum-lab.html
mirrors the same validation in JS. Every pipeline stage reads/writes through
this module so the format lives in exactly one place.

Schema v1:
{
  "version": 1,
  "source": "midi" | "dsp" | "adt" | "manual" | "synthetic",
  "generator": "midi_to_events 1.0",
  "sourceFile": "drums.wav",
  "duration": 30.0,
  "events": [{"t": 0.512, "kind": "kick", "v": 0.85}],
  "params": {"kickBand": [35, 130]}
}

t    = seconds from clip start, 3 decimals, sorted ascending
kind = kick | snare | hat (| other — unmapped MIDI voices kept on request)
v    = 0..1 (MIDI velocity/127, DSP normalized peak band energy)
params = every tunable that produced the file, for provenance

The shape deliberately mirrors the AV chart contract (version/duration/params,
short keys) so a future chart-gen merge step is trivial.
"""

from __future__ import annotations

import json
import logging
from collections import Counter
from pathlib import Path

logger = logging.getLogger(__name__)

SCHEMA_VERSION = 1
KNOWN_SOURCES = ("midi", "dsp", "adt", "manual", "synthetic")
CORE_KINDS = ("kick", "snare", "hat")
KNOWN_KINDS = CORE_KINDS + ("other",)


# Our loggers only — flipping the ROOT logger to DEBUG unleashes numba/librosa
# internals (numba.core.byteflow dumps thousands of lines per compile).
PIPELINE_LOGGERS = (
    "events_io", "extract", "separate", "midi_to_events", "score", "make_test_clip",
)


def add_verbosity_flag(ap):
    """Shared -v/--verbose flag for every CLI in this pipeline."""
    ap.add_argument("-v", "--verbose", action="store_true",
                    help="enable DEBUG logging for pipeline loggers (per-hit detail)")


def apply_verbosity(args):
    """Call right after parse_args(): DEBUG on pipeline loggers, libraries stay INFO."""
    if getattr(args, "verbose", False):
        for name in PIPELINE_LOGGERS:
            logging.getLogger(name).setLevel(logging.DEBUG)
        logger.debug("[events_io] DEBUG logging enabled for %s", ", ".join(PIPELINE_LOGGERS))


def write_events_json(path, *, source, generator, source_file, duration, events, params):
    """Validate, sort, round, and write a drum-events.json. Returns the path."""
    path = Path(path)
    if source not in KNOWN_SOURCES:
        raise ValueError(f"unknown source '{source}' (expected one of {KNOWN_SOURCES})")
    for e in events:
        if e["kind"] not in KNOWN_KINDS:
            raise ValueError(f"unknown event kind '{e['kind']}' at t={e['t']}")

    out_events = sorted(
        (
            {"t": round(float(e["t"]), 3), "kind": e["kind"], "v": round(float(e["v"]), 3)}
            for e in events
        ),
        key=lambda e: (e["t"], e["kind"]),
    )
    counts = Counter(e["kind"] for e in out_events)
    for kind in CORE_KINDS:
        if counts[kind] == 0:
            logger.warning("[events_io] ZERO %s events going into %s", kind, path.name)
    if not out_events:
        logger.warning("[events_io] writing EMPTY event list to %s", path.name)

    doc = {
        "version": SCHEMA_VERSION,
        "source": source,
        "generator": generator,
        "sourceFile": str(source_file),
        "duration": round(float(duration), 3),
        "events": out_events,
        "params": params,
    }
    path.write_text(json.dumps(doc, indent=2), encoding="utf-8")
    logger.info(
        "[events_io] wrote %s: %d events (%s), duration=%.3fs",
        path.name,
        len(out_events),
        ", ".join(f"{k}={counts[k]}" for k in KNOWN_KINDS if counts[k]) or "none",
        doc["duration"],
    )
    return path


def load_events_json(path):
    """Load and validate a drum-events.json. Returns the parsed dict, events sorted."""
    path = Path(path)
    logger.info("[events_io] loading %s", path)
    doc = json.loads(path.read_text(encoding="utf-8"))

    version = doc.get("version")
    if version != SCHEMA_VERSION:
        raise ValueError(f"{path.name}: schema version {version!r}, expected {SCHEMA_VERSION}")
    events = doc.get("events")
    if not isinstance(events, list):
        raise ValueError(f"{path.name}: 'events' missing or not a list")

    unknown = Counter()
    for i, e in enumerate(events):
        if not isinstance(e, dict) or not {"t", "kind", "v"} <= e.keys():
            raise ValueError(f"{path.name}: events[{i}] missing t/kind/v: {e!r}")
        if e["kind"] not in KNOWN_KINDS:
            unknown[e["kind"]] += 1
    if unknown:
        logger.warning("[events_io] %s: unknown kinds %s (kept as-is)", path.name, dict(unknown))

    doc["events"] = sorted(events, key=lambda e: (e["t"], e["kind"]))
    if not doc["events"]:
        logger.warning("[events_io] %s: EMPTY event list", path.name)
    else:
        counts = Counter(e["kind"] for e in doc["events"])
        logger.info(
            "[events_io] %s: %d events (%s)",
            path.name,
            len(doc["events"]),
            ", ".join(f"{k}={v}" for k, v in sorted(counts.items())),
        )
    return doc


def events_by_kind(doc, kinds=CORE_KINDS):
    """Split a loaded doc's events into {kind: [event, ...]} for the given kinds."""
    out = {k: [] for k in kinds}
    for e in doc["events"]:
        if e["kind"] in out:
            out[e["kind"]].append(e)
    return out
