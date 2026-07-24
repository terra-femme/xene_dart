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

from events_io import add_verbosity_flag, apply_verbosity, write_events_json

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
    logger.debug("[band] %s refined onset times (padded coords): %s",
                 kind, np.round(times, 3).tolist())

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


def _collapse_coincident(events, kind_a, kind_b, window_s, bias, label, suppress_below=None):
    """Suppress the weaker of two near-coincident cross-voice hits. The loser is
    the smaller RAW band peak (× `bias` on kind_b to offset the low-band energy
    tilt — low frequencies carry more energy).

    `suppress_below`: only collapse (drop the loser) when the loser's velocity
    is below this — the loser is then band bleed, not a real drum. When both
    hits are strong they are two real drums played together (a kick+snare
    backbeat, or a snare+hat), so keep both. This is what stops the arbitration
    from eating genuine simultaneous hits. Measured on the known-answer clip:
    real kicks land v>=0.80, snare bleed into the kick band lands v<=0.33 — a
    clean gap, so 0.4 separates them for both the flam and snare/hat passes.
    """
    pair = sorted((e for e in events if e["kind"] in (kind_a, kind_b)), key=lambda e: e["t"])
    suppressed = set()
    for a, b in zip(pair, pair[1:]):
        if b["t"] - a["t"] > window_s or a["kind"] == b["kind"]:
            continue
        if id(a) in suppressed or id(b) in suppressed:
            continue
        # weight kind_b's raw by bias so the low-band tilt doesn't always win
        ra = a.get("_raw", a["v"]) * (bias if a["kind"] == kind_b else 1.0)
        rb = b.get("_raw", b["v"]) * (bias if b["kind"] == kind_b else 1.0)
        loser, winner = (a, b) if ra < rb else (b, a)
        # kick+snare: if the loser is still a strong hit, it's a real second
        # drum, not bleed — keep both.
        if suppress_below is not None and loser["v"] >= suppress_below:
            continue
        suppressed.add(id(loser))
        logger.debug("[%s] suppressed %s@%.3f (raw=%.4f) vs %s@%.3f (raw=%.4f) within %.0f ms",
                     label, loser["kind"], loser["t"], loser.get("_raw", 0.0),
                     winner["kind"], winner["t"], winner.get("_raw", 0.0), window_s * 1000)
    if suppressed:
        counts = {}
        for e in pair:
            if id(e) in suppressed:
                counts[e["kind"]] = counts.get(e["kind"], 0) + 1
        logger.info("[%s] %d suppression(s): %s (per-hit detail at DEBUG)",
                    label, len(suppressed), counts)
    return [e for e in events if id(e) not in suppressed]


def arbitrate(events, flam_ms, flam_bleed_v, snare_hat_ms, snare_hat_bias, snare_hat_bleed_v,
              keep_flams, keep_snare_hat):
    """Collapse cross-band duplicates: kick+snare flams first, then snare+hat
    co-detections. RAW peaks are stripped afterward (internal only)."""
    if not keep_flams:
        events = _collapse_coincident(events, "kick", "snare", flam_ms / 1000.0, 1.0,
                                      "flam", suppress_below=flam_bleed_v)
    if not keep_snare_hat:
        events = _collapse_coincident(events, "snare", "hat", snare_hat_ms / 1000.0,
                                      snare_hat_bias, "snhat", suppress_below=snare_hat_bleed_v)
    for e in events:
        e.pop("_raw", None)
    return events


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
                    help="kick+snare within this window may be one hit (default 30)")
    ap.add_argument("--flam-bleed-v", type=float, default=0.60,
                    help="in a kick+snare flam, only drop the weaker hit if its velocity is "
                         "below this (below = band bleed; above = a real second drum, keep both). "
                         "Default 0.60 — on the known clip real kicks land >=0.80 and real snares "
                         ">=0.68, while cross-band bleed lands <=0.56, so 0.60 sits in the gap.")
    ap.add_argument("--keep-flams", action="store_true", help="disable flam arbitration")
    ap.add_argument("--snare-hat-ms", type=float, default=30,
                    help="snare+hat within this window = one transient in two bands, "
                         "keep the dominant band (default 30)")
    ap.add_argument("--snare-hat-bias", type=float, default=1.0,
                    help="multiply hat raw energy before the snare/hat compare; >1 keeps "
                         "more hats to offset the low-band energy tilt (default 1.0)")
    ap.add_argument("--snare-hat-bleed-v", type=float, default=0.40,
                    help="in a snare+hat coincidence, only drop the weaker if its velocity is "
                         "below this (below = one hit in two bands; above = a real snare AND hat, "
                         "keep both). Default 0.40.")
    ap.add_argument("--keep-snare-hat", action="store_true",
                    help="disable snare/hat arbitration (keep both co-detected dots)")
    add_verbosity_flag(ap)
    args = ap.parse_args()
    apply_verbosity(args)

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

    events = arbitrate(events, args.flam_ms, args.flam_bleed_v, args.snare_hat_ms,
                       args.snare_hat_bias, args.snare_hat_bleed_v,
                       args.keep_flams, args.keep_snare_hat)

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
            "flamMs": args.flam_ms, "flamBleedV": args.flam_bleed_v,
            "keepFlams": args.keep_flams,
            "snareHatMs": args.snare_hat_ms, "snareHatBias": args.snare_hat_bias,
            "snareHatBleedV": args.snare_hat_bleed_v, "keepSnareHat": args.keep_snare_hat,
        },
    )


if __name__ == "__main__":
    sys.exit(main())
