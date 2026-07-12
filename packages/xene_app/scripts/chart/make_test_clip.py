"""Synthesize a test clip with KNOWN ground-truth notes for the chart pipeline.

Why this exists: never evaluate a transcription pipeline for the first time on
audio you can't check. This clip's notes are chosen by us, so transcribe.py's
output can be verified exactly (a "known-answer test").

Ground truth (MIDI pitch / piano key 0-87 / seconds):
    C4  midi 60  key 39   0.50 - 1.50
    E4  midi 64  key 43   2.00 - 3.00
    G4  midi 67  key 46   3.50 - 4.50
    C4+E4+G4 chord        5.00 - 7.00   (polyphony test)

Run from packages/xene_app/scripts/chart/:
    conda run -n xene-chart python make_test_clip.py
Writes test_clip.wav next to this script.
"""

import logging
import math
import wave
from pathlib import Path

import numpy as np

logging.basicConfig(level=logging.INFO, format="%(levelname)s %(name)s %(message)s")
logger = logging.getLogger(__name__)

SR = 44100  # CD-standard sample rate; basic-pitch resamples internally anyway

# (midi_pitch, start_s, end_s) — THE ground truth transcribe.py must recover
GROUND_TRUTH = [
    (60, 0.50, 1.50),
    (64, 2.00, 3.00),
    (67, 3.50, 4.50),
    (60, 5.00, 7.00),
    (64, 5.00, 7.00),
    (67, 5.00, 7.00),
]

# A bare sine is NOT a piano-like note; real notes carry overtones. Give each
# note harmonics 1..4 with 1/h amplitude so the transcriber sees a natural comb.
HARMONICS = [1.0, 0.5, 0.33, 0.25]


def midi_to_hz(midi: int) -> float:
    """A4 (midi 69) = 440 Hz; each semitone is a factor of 2^(1/12)."""
    return 440.0 * (2.0 ** ((midi - 69) / 12.0))


def render_note(buf: np.ndarray, midi: int, t0: float, t1: float) -> None:
    """Additively render one note into buf with a 10ms attack / 60ms release
    envelope (clicks from hard edges would confuse onset detection)."""
    logger.info("[make_test_clip] render_note midi=%d (%.1f Hz) t=%.2f-%.2f", midi, midi_to_hz(midi), t0, t1)
    i0, i1 = int(t0 * SR), int(t1 * SR)
    n = i1 - i0
    t = np.arange(n) / SR
    f = midi_to_hz(midi)
    tone = np.zeros(n)
    for h, amp in enumerate(HARMONICS, start=1):
        tone += amp * np.sin(2 * math.pi * f * h * t)
    env = np.minimum(1.0, t / 0.010)                       # 10 ms attack
    env *= np.minimum(1.0, (t[-1] - t) / 0.060)            # 60 ms release
    env *= np.exp(-t * 0.35)                               # gentle piano-ish decay
    buf[i0:i1] += tone * env * 0.22                        # headroom: chord peaks < 1.0


def main() -> None:
    out_path = Path(__file__).parent / "test_clip.wav"
    duration = max(t1 for _, _, t1 in GROUND_TRUTH) + 0.5
    logger.info("[make_test_clip] synthesizing %.1fs at %d Hz, %d ground-truth notes", duration, SR, len(GROUND_TRUTH))
    buf = np.zeros(int(duration * SR))
    for midi, t0, t1 in GROUND_TRUTH:
        render_note(buf, midi, t0, t1)

    peak = float(np.max(np.abs(buf)))
    logger.info("[make_test_clip] peak amplitude %.3f (must stay < 1.0 to avoid clipping)", peak)
    if peak >= 1.0:
        logger.warning("[make_test_clip] clipping! normalizing down")
        buf /= peak * 1.05

    pcm = (buf * 32767).astype(np.int16)
    with wave.open(str(out_path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)  # 16-bit
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    logger.info("[make_test_clip] wrote %s (%d samples)", out_path, len(pcm))


if __name__ == "__main__":
    main()
