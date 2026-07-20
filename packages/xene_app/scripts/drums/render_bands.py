"""Render a drums stem into the three per-voice band WAVs (audit aid).

Writes kick.wav / snare.wav / hat.wav using the SAME zero-phase bandpass
filters extract.py detects with — so each file is literally "what the
detector hears" for that voice. Note these are frequency bands, not true
instruments: a kick's click bleeds into the snare band, snare noise into the
hat band. For hearing why the extractor decided (or missed) something, that
bleed is the point.

--hpss additionally applies the percussive-only HPSS step first, matching the
detector's input even more closely (cymbal wash and tonal ring stripped).

Usage (PowerShell):
  conda run -n xene-drums python render_bands.py path\to\drums.wav
  # -> writes drums_bands\kick.wav, snare.wav, hat.wav next to the input
"""

from __future__ import annotations

import argparse
import logging
import sys
import time
from pathlib import Path

from events_io import add_verbosity_flag, apply_verbosity

logging.basicConfig(level=logging.INFO, format="%(levelname)s %(name)s %(message)s")
logger = logging.getLogger("render_bands")

BANDS = {"kick": (35, 130), "snare": (160, 2200), "hat": (4500, 11000)}


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("input", help="drums stem audio (wav/mp3)")
    ap.add_argument("-o", "--out-dir", help="output dir (default: <input>_bands/ next to input)")
    ap.add_argument("--sr", type=int, default=44100)
    ap.add_argument("--hpss", action="store_true",
                    help="apply HPSS (percussive-only) first — the detector's exact input")
    ap.add_argument("--kick-band", type=float, nargs=2, default=BANDS["kick"], metavar=("LO", "HI"))
    ap.add_argument("--snare-band", type=float, nargs=2, default=BANDS["snare"], metavar=("LO", "HI"))
    ap.add_argument("--hat-band", type=float, nargs=2, default=BANDS["hat"], metavar=("LO", "HI"))
    add_verbosity_flag(ap)
    args = ap.parse_args()
    apply_verbosity(args)

    in_path = Path(args.input)
    if not in_path.exists():
        raise SystemExit(f"input not found: {in_path}")
    out_dir = Path(args.out_dir) if args.out_dir else in_path.parent / f"{in_path.stem}_bands"
    out_dir.mkdir(parents=True, exist_ok=True)

    import librosa
    import numpy as np
    import soundfile as sf
    from scipy.signal import butter, sosfiltfilt

    t0 = time.perf_counter()
    y, sr = librosa.load(str(in_path), sr=args.sr, mono=True)
    logger.info("[load] %s: %.3fs @ %d Hz (%.1fs)", in_path.name, len(y) / sr, sr,
                time.perf_counter() - t0)
    if not len(y):
        logger.error("[load] EMPTY audio")
        raise SystemExit(1)

    if args.hpss:
        t0 = time.perf_counter()
        D = librosa.stft(y, n_fft=2048, hop_length=256)
        _, P = librosa.decompose.hpss(D, margin=2.0)
        y = librosa.istft(P, hop_length=256, length=len(y))
        logger.info("[hpss] percussive-only applied (%.1fs)", time.perf_counter() - t0)

    bands = {"kick": args.kick_band, "snare": args.snare_band, "hat": args.hat_band}
    for kind, (lo, hi) in bands.items():
        hi = min(hi, sr / 2 * 0.99)
        sos = butter(4, [lo, hi], btype="bandpass", fs=sr, output="sos")
        yb = sosfiltfilt(sos, y)
        peak = float(np.max(np.abs(yb))) or 1.0
        yb = yb * (0.9 / peak)  # normalize each band so quiet bands are audible
        out = out_dir / f"{kind}.wav"
        sf.write(out, yb, sr)
        logger.info("[band] %-5s %5.0f-%5.0f Hz -> %s (raw peak %.4f, normalized to 0.9)",
                    kind, lo, hi, out, peak)
        if peak < 1e-3:
            logger.warning("[band] %s band is nearly SILENT in this stem", kind)

    logger.info("[done] 3 band files in %s", out_dir.resolve())


if __name__ == "__main__":
    sys.exit(main())
