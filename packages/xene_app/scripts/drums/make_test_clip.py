"""Known-answer test clip generator — the pipeline's self-test.

Synthesizes a 2-bar drum groove at 100 BPM (repeated twice, ~10 s) with
spectrally distinct voices and velocity variation, and writes THREE artifacts
that must agree with each other:

  test_beat.wav         — audio (a perfectly clean "drums stem")
  test_beat.truth.json  — ground-truth drum-events (schema v1)
  test_beat.mid         — the identical pattern as GM drum MIDI

Self-test contract (see README):
  midi_to_events.py test_beat.mid  -> must score P/R/F = 1.0 vs truth.json
  extract.py test_beat.wav         -> target F ~ 1.0, |mean offset| < 15 ms

One hat per phrase is deliberately swung off the 8th-note grid so a detector
can't score perfectly by grid luck. Snare noise is band-limited to 300-3500 Hz
so the synthetic voices stay separable — real-stem snare/hat bleed is a
tuning/audit problem, not a self-test problem.

Voice recipes are mirrored by drum-lab.html's tap-click synth so what you hear
in the lab matches what this clip sounds like.
"""

from __future__ import annotations

import argparse
import logging
import sys
from pathlib import Path

from events_io import add_verbosity_flag, apply_verbosity, write_events_json

logging.basicConfig(level=logging.INFO, format="%(levelname)s %(name)s %(message)s")
logger = logging.getLogger("make_test_clip")

SR = 44100
BPM = 100.0
BEAT = 60.0 / BPM  # 0.6 s
BARS_PER_PHRASE = 2
PHRASES = 2
SWING_S = 0.078  # swung hat lands this far after the 8th grid

# One 2-bar phrase, times in beats. (kick on 1, and-of-2, 3; snare on 2 and 4;
# 8th hats, accented on the beat, feathered off-beat.)
KICK_BEATS = [(0.0, 1.0), (1.5, 0.8), (2.0, 0.95), (4.0, 1.0), (5.5, 0.8), (6.0, 0.95)]
SNARE_BEATS = [(1.0, 0.9), (3.0, 1.0), (5.0, 0.9), (7.0, 1.0)]


def _hat_beats():
    """8th-note hats across the 2-bar phrase; the bar-2 'and-of-2' hat is swung."""
    hats = []
    for eighth in range(BARS_PER_PHRASE * 8):  # 8 eighths per 4/4 bar
        b = eighth * 0.5
        v = 0.8 if b == int(b) else 0.45
        if b == 6.5:  # bar 2, and-of-2: swing it off-grid
            hats.append((b + SWING_S / BEAT, v, True))
        else:
            hats.append((b, v, False))
    return hats


def build_events():
    """Ground-truth event list in seconds across all phrases."""
    events = []
    swung = 0
    for phrase in range(PHRASES):
        base = phrase * BARS_PER_PHRASE * 4  # beats
        for b, v in KICK_BEATS:
            events.append({"t": (base + b) * BEAT, "kind": "kick", "v": v})
        for b, v in SNARE_BEATS:
            events.append({"t": (base + b) * BEAT, "kind": "snare", "v": v})
        for b, v, is_swung in _hat_beats():
            events.append({"t": (base + b) * BEAT, "kind": "hat", "v": v})
            swung += is_swung
    logger.info(
        "[pattern] built %d events (%d kick, %d snare, %d hat, %d swung hats)",
        len(events), PHRASES * len(KICK_BEATS), PHRASES * len(SNARE_BEATS),
        PHRASES * len(_hat_beats()), swung,
    )
    return events


# ---------- voice synthesis ----------

def _render_kick(np, sr, v):
    """55 Hz sine with a fast pitch drop from 150 Hz and ~45 ms decay."""
    n = int(0.12 * sr)
    t = np.arange(n) / sr
    freq = 50.0 + 100.0 * np.exp(-t / 0.02)
    phase = 2.0 * np.pi * np.cumsum(freq) / sr
    attack = 1.0 - np.exp(-t / 0.001)
    return np.sin(phase) * np.exp(-t / 0.045) * attack * v


def _render_snare(np, sosfiltfilt, noise_sos, rng, sr, v):
    """190 Hz body plus a 300-3500 Hz noise burst, ~40 ms decay."""
    n = int(0.10 * sr)
    t = np.arange(n) / sr
    body = np.sin(2.0 * np.pi * 190.0 * t) * np.exp(-t / 0.03)
    noise = sosfiltfilt(noise_sos, rng.standard_normal(n)) * np.exp(-t / 0.04)
    return (0.6 * body + 0.7 * noise) * v


def _render_hat(np, sosfiltfilt, hat_sos, rng, sr, v):
    """High-passed (6 kHz) noise tick, ~8 ms decay."""
    n = int(0.035 * sr)
    t = np.arange(n) / sr
    noise = sosfiltfilt(hat_sos, rng.standard_normal(n)) * np.exp(-t / 0.008)
    return noise * 0.8 * v


def render_audio(events):
    import numpy as np
    from scipy.signal import butter, sosfiltfilt

    duration = max(e["t"] for e in events) + 0.4
    mix = np.zeros(int(duration * SR) + 1)
    rng = np.random.default_rng(20260718)  # fixed seed: clip is reproducible
    snare_sos = butter(4, [300, 3500], btype="bandpass", fs=SR, output="sos")
    hat_sos = butter(4, 6000, btype="highpass", fs=SR, output="sos")

    for e in events:
        if e["kind"] == "kick":
            y = _render_kick(np, SR, e["v"])
        elif e["kind"] == "snare":
            y = _render_snare(np, sosfiltfilt, snare_sos, rng, SR, e["v"])
        else:
            y = _render_hat(np, sosfiltfilt, hat_sos, rng, SR, e["v"])
        i = int(e["t"] * SR)
        mix[i : i + len(y)] += y[: len(mix) - i]

    peak = np.max(np.abs(mix))
    if peak == 0:
        logger.error("[render] silent mix — no events rendered")
        raise SystemExit(1)
    mix *= 0.9 / peak
    logger.info("[render] %.3fs of audio, peak normalized to 0.9", duration)
    return mix, duration


def write_midi(events, path):
    import pretty_midi

    KIND_TO_PITCH = {"kick": 36, "snare": 38, "hat": 42}
    pm = pretty_midi.PrettyMIDI(initial_tempo=BPM)
    inst = pretty_midi.Instrument(program=0, is_drum=True, name="xene test groove")
    for e in events:
        inst.notes.append(
            pretty_midi.Note(
                velocity=max(1, min(127, round(e["v"] * 127))),
                pitch=KIND_TO_PITCH[e["kind"]],
                start=e["t"],
                end=e["t"] + 0.05,
            )
        )
    pm.instruments.append(inst)
    pm.write(str(path))
    logger.info("[midi] wrote %s: %d notes", path.name, len(inst.notes))


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--out-dir", default=".", help="output directory (default: cwd)")
    add_verbosity_flag(ap)
    args = ap.parse_args()
    apply_verbosity(args)

    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    events = build_events()
    mix, duration = render_audio(events)

    import soundfile as sf

    wav_path = out_dir / "test_beat.wav"
    sf.write(wav_path, mix, SR)
    logger.info("[out] wrote %s (%d samples @ %d Hz)", wav_path.name, len(mix), SR)

    write_events_json(
        out_dir / "test_beat.truth.json",
        source="synthetic",
        generator="make_test_clip 1.0",
        source_file=wav_path.name,
        duration=duration,
        events=events,
        params={"bpm": BPM, "phrases": PHRASES, "swingS": SWING_S, "seed": 20260718},
    )
    write_midi(events, out_dir / "test_beat.mid")
    logger.info("[done] self-test artifacts ready in %s", out_dir.resolve())


if __name__ == "__main__":
    sys.exit(main())
