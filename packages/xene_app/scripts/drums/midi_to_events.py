"""Lane A: producer MIDI drum export -> drum-events.json (schema v1).

Uses pretty_midi because it resolves the MIDI tempo map to absolute seconds —
the entire hard part of MIDI timing. Times come out in clip seconds no matter
how many tempo/meter changes the export contains.

GM drum mapping (override with --map):
  35, 36        -> kick
  38, 40        -> snare
  42, 44, 46    -> hat   (open hat is still a hat to the hand)

Unmapped notes (toms, crashes, rides, percussion) are counted and reported in
a summary table — never silently dropped. Pass --include-other to keep them
in the JSON as kind "other" (the lab page renders unknown kinds dimly).

Usage (PowerShell):
  conda run -n xene-drums python midi_to_events.py drums_export.mid
  conda run -n xene-drums python midi_to_events.py export.mid --map "47:snare,49:hat"
"""

from __future__ import annotations

import argparse
import logging
import sys
from collections import Counter
from pathlib import Path

from events_io import CORE_KINDS, add_verbosity_flag, apply_verbosity, write_events_json

logging.basicConfig(level=logging.INFO, format="%(levelname)s %(name)s %(message)s")
logger = logging.getLogger("midi_to_events")

GM_MAP = {35: "kick", 36: "kick", 38: "snare", 40: "snare", 42: "hat", 44: "hat", 46: "hat"}

GM_DRUM_NAMES = {
    35: "Acoustic Bass Drum", 36: "Bass Drum 1", 37: "Side Stick", 38: "Acoustic Snare",
    39: "Hand Clap", 40: "Electric Snare", 41: "Low Floor Tom", 42: "Closed Hi-Hat",
    43: "High Floor Tom", 44: "Pedal Hi-Hat", 45: "Low Tom", 46: "Open Hi-Hat",
    47: "Low-Mid Tom", 48: "Hi-Mid Tom", 49: "Crash Cymbal 1", 50: "High Tom",
    51: "Ride Cymbal 1", 52: "Chinese Cymbal", 53: "Ride Bell", 54: "Tambourine",
    55: "Splash Cymbal", 56: "Cowbell", 57: "Crash Cymbal 2", 58: "Vibraslap",
    59: "Ride Cymbal 2", 60: "Hi Bongo", 61: "Low Bongo", 62: "Mute Hi Conga",
    63: "Open Hi Conga", 64: "Low Conga", 69: "Cabasa", 70: "Maracas",
    75: "Claves", 76: "Hi Wood Block", 77: "Low Wood Block", 80: "Mute Triangle",
    81: "Open Triangle",
}


def parse_map_overrides(spec):
    """--map "47:snare,49:hat" -> {47: 'snare', 49: 'hat'}"""
    overrides = {}
    if not spec:
        return overrides
    for pair in spec.split(","):
        pitch_s, _, kind = pair.strip().partition(":")
        pitch = int(pitch_s)
        if kind not in CORE_KINDS:
            raise SystemExit(f"--map: '{kind}' is not one of {CORE_KINDS}")
        overrides[pitch] = kind
    logger.info("[map] overrides: %s", overrides)
    return overrides


def midi_to_events(path, mapping, all_channels=False, include_other=False):
    """Returns (events, unmapped_counts, duration)."""
    import pretty_midi

    logger.info("[midi] loading %s", path)
    pm = pretty_midi.PrettyMIDI(str(path))
    duration = pm.get_end_time()

    instruments = pm.instruments if all_channels else [i for i in pm.instruments if i.is_drum]
    logger.info(
        "[midi] %d instrument(s) total, using %d (%s)",
        len(pm.instruments), len(instruments),
        "all channels" if all_channels else "drum channels only",
    )
    if not instruments:
        logger.warning(
            "[midi] ZERO drum-channel instruments — producer exports sometimes land on "
            "melodic channels; retry with --all-channels"
        )

    events = []
    unmapped = Counter()
    for inst in instruments:
        logger.info("[midi] instrument '%s': %d notes", inst.name or "(unnamed)", len(inst.notes))
        for note in inst.notes:
            kind = mapping.get(note.pitch)
            if kind is None:
                unmapped[note.pitch] += 1
                if not include_other:
                    continue
                kind = "other"
            events.append({"t": note.start, "kind": kind, "v": note.velocity / 127.0})

    if unmapped:
        logger.warning("[midi] %d note(s) had no kick/snare/hat mapping:", sum(unmapped.values()))
        for pitch, count in sorted(unmapped.items()):
            name = GM_DRUM_NAMES.get(pitch, f"note {pitch}")
            kept = "kept as 'other'" if include_other else "DROPPED (use --include-other or --map)"
            logger.warning("[midi]   pitch %3d %-20s x%-4d %s", pitch, name, count, kept)

    if not events:
        logger.warning("[midi] ZERO events extracted from %s", path)
    return events, unmapped, duration


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("input", help="MIDI file (.mid) with the drum part")
    ap.add_argument("-o", "--out", help="output path (default: <input>.drum-events.json)")
    ap.add_argument("--map", dest="map_spec", help='extra pitch mappings, e.g. "47:snare,49:hat"')
    ap.add_argument("--all-channels", action="store_true",
                    help="read every instrument, not just drum-channel ones")
    ap.add_argument("--include-other", action="store_true",
                    help="keep unmapped notes as kind 'other' instead of dropping them")
    add_verbosity_flag(ap)
    args = ap.parse_args()
    apply_verbosity(args)

    in_path = Path(args.input)
    if not in_path.exists():
        raise SystemExit(f"input not found: {in_path}")
    out_path = Path(args.out) if args.out else in_path.with_suffix(".drum-events.json")

    mapping = {**GM_MAP, **parse_map_overrides(args.map_spec)}
    events, unmapped, duration = midi_to_events(
        in_path, mapping, all_channels=args.all_channels, include_other=args.include_other
    )

    write_events_json(
        out_path,
        source="midi",
        generator="midi_to_events 1.0",
        source_file=in_path.name,
        duration=duration,
        events=events,
        params={
            "map": {str(k): v for k, v in sorted(mapping.items())},
            "allChannels": args.all_channels,
            "includeOther": args.include_other,
            "unmapped": {str(k): v for k, v in sorted(unmapped.items())},
        },
    )


if __name__ == "__main__":
    sys.exit(main())
