"""Lane B stage 1: full mix -> stems via Demucs (htdemucs_ft).

Invokes demucs as a subprocess (the CLI is the stable documented surface; a
subprocess also isolates torch's argparse/logging quirks from ours). Defaults
to the fine-tuned 4-model bag `htdemucs_ft` — a measurable step up from the
base `htdemucs` StemRoller uses — read from the StemRoller model folder
already on this machine, so nothing is re-downloaded.

--shifts N runs separation N times with random time shifts and averages
(quality up, runtime x N). Default 1 for iteration; use 2+ for final
artifacts. CPU runtime for a 30 s clip is minutes — this is an offline
authoring step, not a runtime path.

Usage (PowerShell):
  conda run -n xene-drums python separate.py "C:\\path\\to\\track.mp3"
  conda run -n xene-drums python separate.py track.wav --shifts 2 -o separated
"""

from __future__ import annotations

import argparse
import logging
import subprocess
import sys
import time
from pathlib import Path

logging.basicConfig(level=logging.INFO, format="%(levelname)s %(name)s %(message)s")
logger = logging.getLogger("separate")

DEFAULT_REPO = Path(r"C:\Users\aznkr\stemroller\anyos-extra-files\Models")
STEMS = ("drums", "bass", "other", "vocals")


def build_demucs_cmd(input_path, out_dir, model, shifts, repo):
    cmd = [sys.executable, "-m", "demucs.separate", str(input_path),
           "-o", str(out_dir), "-n", model, "--shifts", str(shifts)]
    if repo is not None:
        cmd += ["--repo", str(repo)]
    return cmd


def resolve_repo(repo_arg, model):
    """Use the local model repo only if it actually holds this model's yaml."""
    repo = Path(repo_arg)
    if (repo / f"{model}.yaml").exists():
        logger.info("[repo] using local model repo %s", repo)
        return repo
    logger.warning(
        "[repo] %s missing %s.yaml — falling back to demucs auto-download (~GBs to torch cache)",
        repo, model,
    )
    return None


def verify_stems(base_dir):
    """Check every expected stem exists and is non-silent; log duration + peak."""
    import numpy as np
    import soundfile as sf

    drums_path = None
    for stem in STEMS:
        path = base_dir / f"{stem}.wav"
        if not path.exists():
            logger.error("[verify] MISSING stem %s", path)
            continue
        data, sr = sf.read(path)
        peak = float(np.max(np.abs(data))) if len(data) else 0.0
        logger.info("[verify] %-6s %.3fs @ %d Hz, peak %.4f", stem, len(data) / sr, sr, peak)
        if peak < 1e-4:
            logger.warning("[verify] stem '%s' is SILENT (peak %.2e)", stem, peak)
        if stem == "drums":
            drums_path = path
    if drums_path is None:
        logger.error("[verify] no drums stem produced — separation failed")
        raise SystemExit(1)
    return drums_path


def run_separation(input_path, out_dir, model, shifts, repo):
    cmd = build_demucs_cmd(input_path, out_dir, model, shifts, repo)
    logger.info("[demucs] running: %s", " ".join(cmd))
    t0 = time.perf_counter()
    result = subprocess.run(cmd)
    elapsed = time.perf_counter() - t0
    if result.returncode != 0:
        logger.error("[demucs] exited %d after %.1fs", result.returncode, elapsed)
        raise SystemExit(result.returncode)
    logger.info("[demucs] done in %.1fs", elapsed)

    base_dir = Path(out_dir) / model / Path(input_path).stem
    if not base_dir.exists():
        logger.error("[demucs] expected output dir not found: %s", base_dir)
        raise SystemExit(1)
    return verify_stems(base_dir)


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("input", help="full-mix audio file (wav/mp3/flac)")
    ap.add_argument("-o", "--out-dir", default="separated",
                    help="output root (demucs adds <model>/<track>/ inside; default: separated)")
    ap.add_argument("-n", "--model", default="htdemucs_ft",
                    help="demucs model name (default: htdemucs_ft, the fine-tuned bag)")
    ap.add_argument("--shifts", type=int, default=1,
                    help="shift-trick passes; 2+ for final artifacts (default 1)")
    ap.add_argument("--repo", default=str(DEFAULT_REPO),
                    help=f"local demucs model repo (default: StemRoller's, {DEFAULT_REPO})")
    args = ap.parse_args()

    input_path = Path(args.input)
    if not input_path.exists():
        raise SystemExit(f"input not found: {input_path}")

    repo = resolve_repo(args.repo, args.model)
    drums_path = run_separation(input_path, args.out_dir, args.model, args.shifts, repo)
    logger.info("[done] drums stem ready: %s", drums_path.resolve())
    logger.info("[next] extract events with: python extract.py \"%s\"", drums_path.resolve())


if __name__ == "__main__":
    sys.exit(main())
