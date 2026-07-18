"""Lane B: drums stem -> drum-events.json (DSP v1 baseline).

Chain (all offline, exploiting non-causal tricks the live detector can't use):
  librosa.load (mono)
  -> HPSS, keep percussive        (strips cymbal wash / tonal ring)
  -> per-voice zero-phase bandpass (sosfiltfilt: no group delay skewing onsets)
  -> onset envelope + non-causal peak picking (librosa)
  -> velocity = normalized local peak band energy
  -> kick-vs-snare flam arbitration (a flam IS one hit to the hand)

Band/gap defaults are seeded from the live detector (audio-engine.js
pollDrumOnset: kick 35-130 Hz / snare 160-550 Hz / hat 3-9.5 kHz, refractory
110/100/70 ms) — snare/hat bands widened for offline filtering. Every tunable
is a CLI flag and is echoed into the output JSON's params for provenance.

Usage (PowerShell):
  conda run -n xene-drums python extract.py test_beat.wav
  conda run -n xene-drums python extract.py "C:\\...\\drums.wav" --hpss-margin 3 --delta 0.1
"""

from __future__ import annotations

import argparse
import logging
import sys
import time
from pathlib import Path

from events_io import write_events_json

logging.basicConfig(level=logging.INFO, format="%(levelname)s %(name)s %(message)s")
logger = logging.getLogger("extract")

HOP = 256
N_FFT = 2048
# Silence pad on both ends before filtering/HPSS: a hit at t=0.000 (crop
# boundary) otherwise has no filter/window history and gets missed. Onset
# times are shifted back after detection.
PAD_S = 0.1


def load_and_hpss(path, sr, margin):
    """Load mono audio (padded) and return the percussive component (time domain)."""
    import librosa
    import numpy as np

    t0 = time.perf_counter()
    y, sr = librosa.load(str(path), sr=sr, mono=True)
    logger.info("[load] %s: %.3fs @ %d Hz (%.1fs elapsed)",
                Path(path).name, len(y) / sr, sr, time.perf_counter() - t0)
    if not len(y):
        logger.error("[load] EMPTY audio")
        raise SystemExit(1)

    pad = int(PAD_S * sr)
    y_padded = np.concatenate([np.zeros(pad), y, np.zeros(pad)])

    t0 = time.perf_counter()
    D = librosa.stft(y_padded, n_fft=N_FFT, hop_length=HOP)
    _, P = librosa.decompose.hpss(D, margin=margin)
    yp = librosa.istft(P, hop_length=HOP, length=len(y_padded))
    logger.info("[hpss] margin=%.1f done (%.1fs elapsed)", margin, time.perf_counter() - t0)
    return y, yp, sr


def band_events(yp, sr, kind, lo, hi, delta, min_gap_ms):
    """One voice: bandpass -> onset envelope -> peak pick. Returns [(t, vRaw)]."""
    import librosa
    import numpy as np
    from scipy.signal import butter, sosfiltfilt

    t0 = time.perf_counter()
    nyq = sr / 2
    hi = min(hi, nyq * 0.99)
    sos = butter(4, [lo, hi], btype="bandpass", fs=sr, output="sos")
    yb = sosfiltfilt(sos, yp)  # zero-phase: band edges don't smear attack timing

    env = librosa.onset.onset_strength(y=yb, sr=sr, hop_length=HOP)
    wait = max(1, round(min_gap_ms / 1000 * sr / HOP))
    frames = librosa.onset.onset_detect(
        onset_envelope=env, sr=sr, hop_length=HOP,
        backtrack=False, normalize=True, delta=delta, wait=wait,
    )
    times = librosa.frames_to_time(frames, sr=sr, hop_length=HOP)
    times = _refine_onsets(np, yb, sr, times)

    # velocity = peak band amplitude in the 30 ms after the onset
    win = int(0.03 * sr)
    raws = []
    for t in times:
        i = int(t * sr)
        seg = np.abs(yb[i : i + win])
        raws.append(float(seg.max()) if len(seg) else 0.0)

    logger.info("[band] %-5s %5.0f-%5.0f Hz: %d onsets (delta=%.3f wait=%df, %.1fs)",
                kind, lo, hi, len(times), delta, wait, time.perf_counter() - t0)
    if not len(times):
        logger.warning("[band] ZERO %s onsets — check band/delta against this stem", kind)
    return list(zip(times.tolist(), raws))


def _refine_onsets(np, yb, sr, times):
    """Snap each onset to the band-signal attack: mel-flux frame timing runs up
    to half a window early (centered STFT), so walk back from the local
    amplitude peak to the 25% crossing — the perceptual start of the hit."""
    if not len(times):
        return times
    env = np.abs(yb)
    # ~1 ms moving average so single-sample spikes don't fake the crossing
    k = max(1, int(0.001 * sr))
    kernel = np.ones(k) / k
    env = np.convolve(env, kernel, mode="same")

    refined = []
    for t in times:
        i0 = max(0, int((t - 0.03) * sr))
        i1 = min(len(env), int((t + 0.04) * sr))
        seg = env[i0:i1]
        if not len(seg):
            refined.append(t)
            continue
        peak_i = int(np.argmax(seg))
        thresh = seg[peak_i] * 0.25
        attack_i = peak_i
        while attack_i > 0 and seg[attack_i - 1] >= thresh:
            attack_i -= 1
        refined.append((i0 + attack_i) / sr)
    return np.array(refined)


def normalize_velocities(raw_events, kind, min_v):
    """Per-voice normalize raw peaks to the 95th percentile; drop below min_v."""
    import numpy as np

    if not raw_events:
        return []
    raws = np.array([r for _, r in raw_events])
    ref = float(np.percentile(raws, 95)) or 1.0
    out, dropped = [], 0
    for t, r in raw_events:
        v = min(1.0, max(0.0, r / ref))
        if v < min_v:
            dropped += 1
            continue
        # _raw kept for flam arbitration (cross-voice comparable), stripped later
        out.append({"t": t, "kind": kind, "v": v, "_raw": r})
    if dropped:
        logger.info("[vel] %s: dropped %d event(s) below min-v %.2f", kind, dropped, min_v)
    return out


def arbitrate_flams(events, flam_ms, keep_flams):
    """Within flam_ms, a kick and a snare are one physical hit: keep the stronger.

    Strength is compared on RAW band peak amplitude (cross-voice comparable),
    not the per-voice normalized v — each voice normalizes to its own 95th
    percentile, so normalized values say nothing about which drum dominated
    the actual waveform at that instant.
    """
    if keep_flams:
        return events
    window = flam_ms / 1000.0
    ks = sorted((e for e in events if e["kind"] in ("kick", "snare")), key=lambda e: e["t"])
    suppressed = set()
    for a, b in zip(ks, ks[1:]):
        if b["t"] - a["t"] <= window and a["kind"] != b["kind"]:
            loser = a if a.get("_raw", a["v"]) < b.get("_raw", b["v"]) else b
            suppressed.add(id(loser))
            logger.debug("[flam] suppressed %s@%.3f (raw=%.4f) vs %s within %.0f ms",
                         loser["kind"], loser["t"], loser.get("_raw", 0.0),
                         (b if loser is a else a)["kind"], flam_ms)
    kept = [e for e in events if id(e) not in suppressed]
    if suppressed:
        counts = {}
        for e in ks:
            if id(e) in suppressed:
                counts[e["kind"]] = counts.get(e["kind"], 0) + 1
        logger.info("[flam] %d suppression(s): %s (per-hit detail at DEBUG)",
                    len(suppressed), counts)
    for e in events:
        e.pop("_raw", None)
    return kept


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("input", help="drums stem audio (wav/mp3)")
    ap.add_argument("-o", "--out", help="output path (default: <input>.drum-events.json)")
    ap.add_argument("--sr", type=int, default=44100)
    ap.add_argument("--hpss-margin", type=float, default=2.0,
                    help="HPSS separation margin; higher = stricter percussive (default 2.0)")
    ap.add_argument("--kick-band", type=float, nargs=2, default=[35, 130], metavar=("LO", "HI"))
    ap.add_argument("--snare-band", type=float, nargs=2, default=[160, 2200], metavar=("LO", "HI"))
    ap.add_argument("--hat-band", type=float, nargs=2, default=[4500, 11000], metavar=("LO", "HI"))
    ap.add_argument("--min-gap-kick", type=float, default=110, help="ms (default 110)")
    ap.add_argument("--min-gap-snare", type=float, default=100, help="ms (default 100)")
    ap.add_argument("--min-gap-hat", type=float, default=70, help="ms (default 70)")
    ap.add_argument("--delta", type=float, default=0.08,
                    help="peak-pick threshold on the normalized onset envelope (default 0.08)")
    ap.add_argument("--min-v", type=float, default=0.10,
                    help="drop events with normalized velocity below this (default 0.10 — "
                         "filter-skirt bleed lands ~0.07, real ghost notes ~0.15+)")
    ap.add_argument("--flam-ms", type=float, default=30,
                    help="kick+snare within this window = one hit, keep stronger (default 30)")
    ap.add_argument("--keep-flams", action="store_true", help="disable flam arbitration")
    args = ap.parse_args()

    in_path = Path(args.input)
    if not in_path.exists():
        raise SystemExit(f"input not found: {in_path}")
    out_path = Path(args.out) if args.out else in_path.with_suffix(".drum-events.json")

    y, yp, sr = load_and_hpss(in_path, args.sr, args.hpss_margin)

    bands = {
        "kick": (args.kick_band, args.min_gap_kick),
        "snare": (args.snare_band, args.min_gap_snare),
        "hat": (args.hat_band, args.min_gap_hat),
    }
    events = []
    for kind, ((lo, hi), gap) in bands.items():
        raw = band_events(yp, sr, kind, lo, hi, args.delta, gap)
        events.extend(normalize_velocities(raw, kind, args.min_v))

    # detection ran on the padded signal — shift times back to clip coordinates
    duration = len(y) / sr
    for e in events:
        e["t"] = min(duration, max(0.0, e["t"] - PAD_S))

    events = arbitrate_flams(events, args.flam_ms, args.keep_flams)

    write_events_json(
        out_path,
        source="dsp",
        generator="extract 1.0 (hpss+bandflux)",
        source_file=in_path.name,
        duration=duration,
        events=events,
        params={
            "sr": sr, "hop": HOP, "nFft": N_FFT, "hpssMargin": args.hpss_margin,
            "kickBand": args.kick_band, "snareBand": args.snare_band, "hatBand": args.hat_band,
            "minGapMs": {"kick": args.min_gap_kick, "snare": args.min_gap_snare,
                         "hat": args.min_gap_hat},
            "delta": args.delta, "minV": args.min_v,
            "flamMs": args.flam_ms, "keepFlams": args.keep_flams,
        },
    )


if __name__ == "__main__":
    sys.exit(main())
