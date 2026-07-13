# Note-chart transcription (offline build step)

The "Guitar Hero architecture" for the AV visualizer's melodic regions: each
owned clip's **other** stem is transcribed ONCE, offline, by Spotify's Basic
Pitch (ML transcription model). The resulting `*.chart.json` note chart ships
as a static asset, and the visualizer plays it back in sample-accurate sync —
zero realtime pitch guessing.

## One-time setup (Windows / PowerShell)

```powershell
# from anywhere — creates an isolated Python 3.11 env (basic-pitch can't run on 3.13)
conda create -y -n xene-chart python=3.11
conda run -n xene-chart python -m pip install -r C:\Users\aznkr\Documents\Fun_Apps\xene\xene_dart\packages\xene_app\scripts\chart\requirements.txt
```

## Usage

```powershell
cd C:\Users\aznkr\Documents\Fun_Apps\xene\xene_dart\packages\xene_app\scripts\chart

# self-test with known ground truth (writes test_clip.wav, then test_clip.chart.json)
conda run -n xene-chart python make_test_clip.py
conda run -n xene-chart python transcribe.py test_clip.wav

# real clip (the OTHER/melodic stem, not the full mix)
conda run -n xene-chart python transcribe.py path\to\track-other.mp3
```

Verified on the known-answer clip 2026-07-12: 6/6 ground-truth notes recovered,
onsets within ~16 ms, all 9 harmonic ghosts removed by the default
`--min-velocity 0.5` gate (true notes scored v >= 0.66, ghosts <= 0.43).

## Chart format

```json
{
  "version": 1,
  "source": "track-other.mp3",
  "generator": "basic-pitch",
  "duration": 30.0,
  "notes": [ { "k": 39, "t0": 0.50, "t1": 1.54, "v": 0.75 } ]
}
```

`k` = piano key 0–87 (`midi - 21`) · `t0`/`t1` = note on/off in clip seconds ·
`v` = model confidence/velocity 0–1. Notes sorted by `t0`.

## Tuning knobs

| Flag | Default | Effect |
|---|---|---|
| `--onset-thresh` | 0.5 | higher = fewer, more confident onsets |
| `--frame-thresh` | 0.3 | higher = notes end sooner |
| `--min-note-ms` | 80 | drop blips shorter than this |
| `--min-velocity` | 0.5 | drop low-confidence notes (harmonic ghosts); 0 disables |

Known artifact: long sustains occasionally split into two back-to-back events
(same key, `t1` == next `t0`). Harmless for visualization — the region stays lit.
