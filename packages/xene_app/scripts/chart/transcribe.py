"""Offline note-chart transcriber: audio clip -> chart JSON for the AV visualizer.

The Guitar Hero architecture: run ML transcription ONCE per owned clip at build
time, ship the resulting note chart as a static asset, and let the visualizer do
dumb, deterministic playback — zero realtime pitch guessing.

Model: Spotify's Basic Pitch (Apache-2.0), a lightweight instrument-agnostic
CNN for Automatic Music Transcription. It emits note events
(start_s, end_s, midi_pitch, amplitude, ...) which we map to piano keys 0-87
(key = midi - 21; A0=21 ... C8=108) and write as JSON:

    {
      "version": 1,
      "source": "clip-other.mp3",
      "generator": "basic-pitch",
      "duration": 30.0,
      "notes": [ {"k": 39, "t0": 0.50, "t1": 1.48, "v": 0.81}, ... ]
    }

Run from packages/xene_app/scripts/chart/ (inside the xene-chart conda env):
    conda run -n xene-chart python transcribe.py test_clip.wav
    conda run -n xene-chart python transcribe.py path\to\track-other.mp3 -o out\dir

Tuning knobs (forwarded to Basic Pitch's event decoder):
    --onset-thresh  0..1  higher = fewer, more confident note onsets (default 0.5)
    --frame-thresh  0..1  higher = notes end sooner / fewer sustains (default 0.3)
    --min-note-ms         drop blips shorter than this (default 80)
"""

import argparse
import json
import logging
import sys
import time
from pathlib import Path

logging.basicConfig(level=logging.INFO, format="%(levelname)s %(name)s %(message)s")
logger = logging.getLogger(__name__)

PIANO_MIDI_LO = 21   # A0 == piano key 0
PIANO_MIDI_HI = 108  # C8 == piano key 87


def transcribe(audio_path: Path, onset_thresh: float, frame_thresh: float, min_note_ms: float,
               min_velocity: float) -> dict:
    """Run Basic Pitch on one clip and shape its note events into chart dict."""
    # imported here so `--help` works without the heavy ML deps installed
    from basic_pitch.inference import predict

    logger.info("[transcribe] predict start file=%s onset=%.2f frame=%.2f min_note=%.0fms",
                audio_path, onset_thresh, frame_thresh, min_note_ms)
    t_start = time.time()
    model_output, midi_data, note_events = predict(
        str(audio_path),
        onset_threshold=onset_thresh,
        frame_threshold=frame_thresh,
        minimum_note_length=min_note_ms,
    )
    logger.info("[transcribe] predict done in %.1fs, %d raw note events", time.time() - t_start, len(note_events))

    notes = []
    skipped = 0
    ghosts = 0
    for ev in note_events:
        start_s, end_s, midi_pitch, amplitude = ev[0], ev[1], int(ev[2]), float(ev[3])
        if midi_pitch < PIANO_MIDI_LO or midi_pitch > PIANO_MIDI_HI:
            skipped += 1
            logger.debug("[transcribe] skip out-of-piano-range midi=%d t=%.2f", midi_pitch, start_s)
            continue
        # Confidence gate: on the known-answer test clip, every TRUE note scored
        # v >= 0.66 and every harmonic ghost scored v <= 0.43 — low-velocity
        # events are the model saying "probably an overtone, not a note".
        if amplitude < min_velocity:
            ghosts += 1
            logger.debug("[transcribe] drop low-velocity midi=%d v=%.2f t=%.2f", midi_pitch, amplitude, start_s)
            continue
        notes.append({
            "k": midi_pitch - PIANO_MIDI_LO,
            "t0": round(float(start_s), 3),
            "t1": round(float(end_s), 3),
            "v": round(min(1.0, max(0.0, amplitude)), 3),
        })
    if skipped:
        logger.warning("[transcribe] skipped %d events outside piano range (midi %d-%d)",
                       skipped, PIANO_MIDI_LO, PIANO_MIDI_HI)
    if ghosts:
        logger.info("[transcribe] dropped %d low-velocity events (v < %.2f)", ghosts, min_velocity)
    if not notes:
        logger.warning("[transcribe] ZERO notes survived — thresholds too high, or clip is unpitched?")

    notes.sort(key=lambda n: (n["t0"], n["k"]))
    duration = max((n["t1"] for n in notes), default=0.0)
    logger.info("[transcribe] chart: %d notes, %.2fs span, keys %s..%s",
                len(notes), duration,
                min((n["k"] for n in notes), default="-"), max((n["k"] for n in notes), default="-"))
    return {
        "version": 1,
        "source": audio_path.name,
        "generator": "basic-pitch",
        "duration": round(duration, 3),
        "notes": notes,
    }


def main() -> int:
    ap = argparse.ArgumentParser(description="Audio clip -> note-chart JSON (Basic Pitch)")
    ap.add_argument("audio", nargs="+", help="input audio file(s): wav/mp3/m4a/ogg/flac")
    ap.add_argument("-o", "--out-dir", default=None, help="output dir (default: next to each input)")
    ap.add_argument("--onset-thresh", type=float, default=0.5)
    ap.add_argument("--frame-thresh", type=float, default=0.3)
    ap.add_argument("--min-note-ms", type=float, default=80.0)
    ap.add_argument("--min-velocity", type=float, default=0.5,
                    help="drop notes the model is unsure about (harmonic ghosts); 0 disables")
    args = ap.parse_args()

    failures = 0
    for a in args.audio:
        audio_path = Path(a)
        if not audio_path.is_file():
            logger.error("[transcribe] input not found: %s", audio_path)
            failures += 1
            continue
        out_dir = Path(args.out_dir) if args.out_dir else audio_path.parent
        out_dir.mkdir(parents=True, exist_ok=True)
        out_path = out_dir / (audio_path.stem + ".chart.json")
        try:
            chart = transcribe(audio_path, args.onset_thresh, args.frame_thresh, args.min_note_ms,
                               args.min_velocity)
        except Exception:
            logger.exception("[transcribe] FAILED on %s", audio_path)
            failures += 1
            continue
        out_path.write_text(json.dumps(chart, indent=1), encoding="utf-8")
        logger.info("[transcribe] wrote %s (%d notes)", out_path, len(chart["notes"]))
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
