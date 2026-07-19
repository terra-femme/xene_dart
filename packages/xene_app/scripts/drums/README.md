# Drum-events extraction pipeline (offline build step)

The data lane for **drum haptics**: instead of detecting drum onsets live at
playback (jittery, misclassifies — see `audio-engine.js pollDrumOnset`), each
clip's drum events are extracted ONCE, offline, audited by a human in
`tools/av_debug/drum-lab.html`, and only then allowed to drive haptics.

Two lanes, one contract (`drum-events.json`, schema v1 — `events_io.py` is the
source of truth):

- **Lane A — ground truth:** producer MIDI drum export → `midi_to_events.py`.
  Zero detection error; also the reference the extraction lane is graded against.
- **Lane B — extraction:** any track → `separate.py` (Demucs `htdemucs_ft`)
  → `extract.py` (HPSS + zero-phase band filtering + non-causal onset picking).
  This is the scalable lane; `score.py` measures it against Lane A.

## One-time setup (Windows / PowerShell)

```powershell
# from anywhere — isolated Python 3.11 env. Separate from xene-chart on purpose:
# basic-pitch's TensorFlow pins conflict with the torch stack demucs needs.
conda create -y -n xene-drums python=3.11
conda run -n xene-drums python -m pip install -r C:\Users\aznkr\Documents\Fun_Apps\xene\xene_dart\packages\xene_app\scripts\drums\requirements.txt
```

Torch CPU wheels are ~2.5 GB — the install takes a while. If pip's resolver
fights, install `torch`/`torchaudio` first, then the rest of requirements.txt.

## Workflow

```powershell
cd C:\Users\aznkr\Documents\Fun_Apps\xene\xene_dart\packages\xene_app\scripts\drums

# 1. self-test with known ground truth (writes test_beat.wav/.mid/.truth.json)
conda run -n xene-drums python make_test_clip.py
conda run -n xene-drums python midi_to_events.py test_beat.mid
conda run -n xene-drums python score.py test_beat.truth.json test_beat.drum-events.json
#    -> expect P/R/F = 1.000 on every voice (MIDI lane sanity)

conda run -n xene-drums python extract.py test_beat.wav
conda run -n xene-drums python score.py test_beat.truth.json test_beat.drum-events.json
#    -> target F ~ 1.0 per voice, |mean offset| < 15 ms (DSP lane sanity)

# 2. real track, already-separated stem (e.g. StemRoller output)
conda run -n xene-drums python extract.py "C:\Users\aznkr\Music\StemRoller\Tweakz - Unintentional_demo\drums.wav"

# 3. or separate fresh from the full mix with the better fine-tuned model
#    (--shifts 2 for final artifacts; each shift multiplies runtime)
conda run -n xene-drums python separate.py "C:\path\to\track.mp3" --shifts 2
conda run -n xene-drums python extract.py "separated\htdemucs_ft\track\drums.wav"

# 4. audit: run the lab server (serves the page AND runs the pipeline for it)
conda run -n xene-drums python drum_lab_server.py
# open http://127.0.0.1:8123/drum-lab.html  (127.0.0.1, NOT file://)
```

The lab's **Track prep** section (enabled when served by `drum_lab_server.py`)
does steps 3 in the browser: upload a full track, drag the 30 s crop window,
click Separate — the server runs `separate.py` + `extract.py` and the lab
auto-loads the drums stem + events when done. Uploads/outputs land in
`uploads/` and `separated/` (both gitignored).

In the lab: Set A = ground truth (solid), Set B = extracted (hollow). Solo the
tap clicks per set to *hear* each grid against the stem, hand-correct B in edit
mode, export. `score.py` the export against the raw extraction to quantify how
much correction was needed.

## drum-events.json (schema v1)

```json
{
  "version": 1,
  "source": "midi | dsp | adt | manual | synthetic",
  "generator": "extract 1.0 (hpss+bandflux)",
  "sourceFile": "drums.wav",
  "duration": 30.0,
  "events": [ { "t": 0.512, "kind": "kick", "v": 0.85 } ],
  "params": { "kickBand": [35, 130] }
}
```

`t` seconds (3 decimals, sorted) · `kind` = `kick|snare|hat` (`other` for
unmapped MIDI voices) · `v` 0–1 · `params` = every tunable used (provenance).
The shape mirrors the AV chart contract so a future chart-gen merge is trivial.

## extract.py tuning knobs

| Flag | Default | Effect |
|---|---|---|
| `--hpss-margin` | 2.0 | higher = stricter percussive isolation before detection |
| `--kick-band` / `--snare-band` / `--hat-band` | 35–130 / 160–2200 / 4500–11000 Hz | per-voice bandpass (zero-phase) |
| `--min-gap-kick/-snare/-hat` | 110 / 100 / 70 ms | per-voice re-trigger dead time |
| `--delta` | 0.08 | peak-pick threshold on the normalized onset envelope |
| `--min-v` | 0.05 | drop events below this normalized velocity |
| `--flam-ms` | 30 | kick+snare closer than this = one hit, keep stronger |

## Scoring story (record results here)

| Date | Track | Ref | Est | micro F | mean offset | Notes |
|---|---|---|---|---|---|---|
| 2026-07-18 | test_beat (synthetic) | truth | midi lane | **1.000** | +0.0 ms (±0.2) | self-test A: all 52 events, tempo map verified |
| 2026-07-18 | test_beat (synthetic) | truth | dsp lane | **1.000** | +1.8 ms (±3.4) | self-test B: worst voice bias +8 ms (kick), std ≤0.5 ms per voice |
| 2026-07-18 | Tweakz 60–90s | dsp on htdemucs stem | dsp on htdemucs_ft stem | 0.958 | −0.0 ms (±1.0) | stem-quality A/B, no ground truth: kind-agnostic onsets agree at F=0.984 (hats 335/335 perfect); kick/snare labels flip on ~14 layered hits — classification, not timing, is the open problem |

Self-test history: first run scored F=0.980 with kick bias −22 ms — the two
misses were the t=0.000 hits (fixed by silence padding) and the bias was mel
frame-centering (fixed by waveform attack refinement). Both fixes are why the
self-test exists.

The ADT (ML drum transcription) model is v2 of Lane B — it gets graded on this
same harness, against the same ground truth, so the DSP baseline numbers above
are the bar it has to clear.

## Notes

- `separate.py` defaults `--repo` to StemRoller's local model folder
  (`C:\Users\aznkr\stemroller\anyos-extra-files\Models`) so `htdemucs_ft` loads
  without re-downloading; if the yaml isn't there it falls back to demucs'
  auto-download (~GBs into the torch cache) with a warning.
- CPU separation of a 30 s clip is minutes (`htdemucs_ft` is a 4-model bag);
  fine for an authoring step.
- If an mp3 fails to load, convert to wav first (demucs outputs wav anyway).
