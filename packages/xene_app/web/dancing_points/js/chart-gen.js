// @ts-check
// Chart generator — offline replica of the StemEngine's live DSP.
//
// At export time we already hold every stem as a decoded AudioBuffer, so we can
// run the SAME math the engine runs at playback (RMS/flux envelopes per stem,
// 8192-FFT harmonic-salience note gate on the melodic stem) over the crop
// window at a fixed 60Hz — and save the result. Playback then only needs the
// audible master (+ the vocal stem for the raw-waveform trail); drums/bass/
// other/full reactivity comes from this chart (engine._updateFromChart).
//
// Chart contract (consumed by StemEngine.setChart):
//   {
//     version: 1,
//     rate: 30,                       // stored sample rate of signal arrays
//     duration: 30.0,
//     signals: { vocals|drums|bass|other|full:
//                { react: [0..250], reactSlow: [0..250], level: [0..250] } },
//     notes: [ { k, t0, t1, v } ],    // note gate events, times relative to crop
//     params: { ... },                // provenance: tunables used to render
//   }
//
// Fidelity notes (approximations, all visual-grade):
// - The live AnalyserNode smooths per getByteFrequencyData CALL (display rate);
//   we simulate at exactly 60Hz. Same constant (0.6), slightly different cadence.
// - Blackman window + 1/N magnitude + [-100,-30]dB byte mapping follow the Web
//   Audio spec for getByteFrequencyData.

(function () {
  'use strict';

  const SIM_RATE = 60;   // engine math cadence (matches typical RAF)
  const STORE_RATE = 30; // stored envelope rate (lerped back up at playback)
  const FFT_SIZE = 8192; // matches engine._melodyFreq
  const Q = 250;         // quantisation ceiling for stored envelopes

  // engine's harmonic model (audio-engine.js NOTE_HARM_OFF / NOTE_HARM_W)
  const HARM_OFF = [0, 12, 19, 24, 28];
  const HARM_W = [1.0, 0.6, 0.4, 0.25, 0.15];

  // source key → slot buffer it reads (mirrors SOURCES in audio-engine.js)
  const SOURCE_SLOT = { vocals: 'vocals', drums: 'drums', bass: 'bass', other: 'other', full: 'original' };
  const SOURCE_TYPE = { vocals: 'sust', drums: 'perc', bass: 'sust', other: 'sust', full: 'sust' };

  /** @param {AudioBuffer} buffer */
  function monoOf(buffer) {
    const n = buffer.length;
    const out = new Float32Array(n);
    const chs = Math.min(2, buffer.numberOfChannels);
    for (let c = 0; c < chs; c++) {
      const d = buffer.getChannelData(c);
      for (let i = 0; i < n; i++) out[i] += d[i] / chs;
    }
    return out;
  }

  /** @param {number} v */
  const q = (v) => Math.max(0, Math.min(Q, Math.round(v * Q)));

  // ---------- per-stem envelope sim (exact _updateSignal math) ----------
  /**
   * @param {Float32Array} mono @param {number} sampleRate
   * @param {{start:number, duration:number}} crop
   * @param {'perc'|'sust'} type
   * @param {{sensitivity:number, attack:number, decay:number, noiseGate:number}} p
   */
  function simSignal(mono, sampleRate, crop, type, p) {
    const frames = Math.ceil(crop.duration * SIM_RATE);
    const react = [], reactSlow = [], level = [];
    const sig = { level: 0, react: 0, reactSlow: 0, peak: 0.0001, baseline: 0, prevLevel: 0 };
    const slowDecay = Math.min(0.995, p.decay + 0.04);

    for (let f = 0; f < frames; f++) {
      const t = crop.start + f / SIM_RATE;
      const end = Math.min(mono.length, Math.floor(t * sampleRate));
      const s0 = Math.max(0, end - 1024);
      let sum = 0;
      for (let i = s0; i < end; i++) { const v = mono[i]; sum += v * v; }
      const rms = end > s0 ? Math.sqrt(sum / (end - s0)) : 0;
      sig.level = rms;

      if (rms < p.noiseGate) {
        sig.prevLevel = 0;
        sig.react *= p.decay;
        sig.reactSlow *= slowDecay;
      } else {
        sig.peak = Math.max(sig.peak * 0.9995, rms);
        const norm = rms / (sig.peak + 1e-5);
        sig.baseline = sig.baseline * 0.995 + norm * 0.005;

        let drive;
        if (type === 'perc') {
          drive = Math.max(0, norm - sig.prevLevel) * p.sensitivity * 6.0;
        } else {
          drive = Math.max(0, norm - sig.baseline) * p.sensitivity * 3.0;
        }
        sig.prevLevel = norm;
        drive = Math.max(0, Math.min(1, drive));

        if (drive > sig.react) sig.react += (drive - sig.react) * p.attack;
        else sig.react *= p.decay;
        sig.reactSlow = Math.max(sig.reactSlow * slowDecay, sig.react * 0.9);
      }

      if (f % (SIM_RATE / STORE_RATE) === 0) {
        react.push(q(sig.react));
        reactSlow.push(q(sig.reactSlow));
        level.push(q(Math.min(1, sig.level)));
      }
    }
    return { react, reactSlow, level };
  }

  // ---------- FFT (iterative radix-2, real input) ----------
  /** @param {Float32Array} re @param {Float32Array} im */
  function fftInPlace(re, im) {
    const n = re.length;
    for (let i = 1, j = 0; i < n; i++) { // bit reversal
      let bit = n >> 1;
      for (; j & bit; bit >>= 1) j ^= bit;
      j ^= bit;
      if (i < j) {
        let t = re[i]; re[i] = re[j]; re[j] = t;
        t = im[i]; im[i] = im[j]; im[j] = t;
      }
    }
    for (let len = 2; len <= n; len <<= 1) {
      const ang = (-2 * Math.PI) / len;
      const wr = Math.cos(ang), wi = Math.sin(ang);
      for (let i = 0; i < n; i += len) {
        let cwr = 1, cwi = 0;
        for (let k = 0; k < len / 2; k++) {
          const ur = re[i + k], ui = im[i + k];
          const vr = re[i + k + len / 2] * cwr - im[i + k + len / 2] * cwi;
          const vi = re[i + k + len / 2] * cwi + im[i + k + len / 2] * cwr;
          re[i + k] = ur + vr; im[i + k] = ui + vi;
          re[i + k + len / 2] = ur - vr; im[i + k + len / 2] = ui - vi;
          const nwr = cwr * wr - cwi * wi;
          cwi = cwr * wi + cwi * wr;
          cwr = nwr;
        }
      }
    }
  }

  // ---------- note gate sim (exact _updateKeyEnergies logic) ----------
  /**
   * @param {Float32Array} mono @param {number} sampleRate
   * @param {{start:number, duration:number}} crop
   * @param {{noteOnThresh:number, noteOffThresh:number, maxPolyphony:number}} p
   * @returns {Array<{k:number, t0:number, t1:number, v:number}>}
   */
  function simNotes(mono, sampleRate, crop, p) {
    const frames = Math.ceil(crop.duration * SIM_RATE);
    const half = FFT_SIZE / 2;

    // Blackman window (Web Audio spec's analyser window)
    const win = new Float32Array(FFT_SIZE);
    for (let i = 0; i < FFT_SIZE; i++) {
      const x = (2 * Math.PI * i) / FFT_SIZE;
      win[i] = 0.42 - 0.5 * Math.cos(x) + 0.08 * Math.cos(2 * x);
    }

    // key → FFT bin ranges (engine._computeKeyBins)
    const binHz = sampleRate / FFT_SIZE;
    const bins = [];
    for (let k = 0; k < 88; k++) {
      const f = 27.5 * Math.pow(2, k / 12);
      const start = Math.max(0, Math.floor((f / Math.pow(2, 1 / 24)) / binHz));
      const end = Math.max(start, Math.ceil((f * Math.pow(2, 1 / 24)) / binHz));
      bins.push({ start, end });
    }

    const re = new Float32Array(FFT_SIZE), im = new Float32Array(FFT_SIZE);
    const smooth = new Float32Array(half);           // analyser temporal smoothing
    const byte = new Uint8Array(half);
    const raw = new Float32Array(88), work = new Float32Array(88), tgt = new Float32Array(88);
    const on = new Uint8Array(88), hold = new Float32Array(88), vmax = new Float32Array(88), tOn = new Float32Array(88);
    /** @type {Array<{k:number, t0:number, t1:number, v:number}>} */
    const events = [];

    for (let f = 0; f < frames; f++) {
      const t = crop.start + f / SIM_RATE;
      const end = Math.min(mono.length, Math.floor(t * sampleRate));
      const s0 = end - FFT_SIZE;
      for (let i = 0; i < FFT_SIZE; i++) {
        const idx = s0 + i;
        re[i] = idx >= 0 && idx < mono.length ? mono[idx] * win[i] : 0;
        im[i] = 0;
      }
      fftInPlace(re, im);

      // |X|/N → smooth(0.6) → dB → byte, per the Web Audio analyser spec
      for (let k2 = 0; k2 < half; k2++) {
        const mag = Math.hypot(re[k2], im[k2]) / FFT_SIZE;
        smooth[k2] = 0.6 * smooth[k2] + 0.4 * mag;
        const db = 20 * Math.log10(smooth[k2] + 1e-12);
        byte[k2] = Math.max(0, Math.min(255, Math.round(((db + 100) / 70) * 255)));
      }

      for (let k = 0; k < 88; k++) {
        const { start, end: bEnd } = bins[k];
        let sum = 0, n = 0;
        for (let b = start; b <= bEnd && b < half; b++) { sum += byte[b]; n++; }
        raw[k] = n > 0 ? sum / n / 255 : 0;
      }

      // greedy multi-pitch (identical to engine)
      work.set(raw);
      tgt.fill(0);
      for (let it = 0; it < p.maxPolyphony; it++) {
        let bestK = -1, bestS = 0;
        for (let k = 0; k < 88; k++) {
          if (work[k] <= 0.02) continue;
          let s = 0;
          for (let h = 0; h < HARM_OFF.length; h++) {
            const j = k + HARM_OFF[h];
            if (j < 88) s += HARM_W[h] * work[j];
          }
          if (s > bestS) { bestS = s; bestK = k; }
        }
        if (bestK < 0 || bestS < p.noteOffThresh) break;
        tgt[bestK] = Math.min(1, bestS);
        const fu = work[bestK];
        for (let h = 0; h < HARM_OFF.length; h++) {
          const j = bestK + HARM_OFF[h];
          if (j < 88) work[j] = Math.max(0, work[j] - HARM_W[h] * fu);
        }
      }

      // hysteresis state machine → events (t relative to crop start)
      const rel = f / SIM_RATE;
      for (let k = 0; k < 88; k++) {
        if (!on[k]) {
          if (tgt[k] > p.noteOnThresh) { on[k] = 1; hold[k] = 5; vmax[k] = tgt[k]; tOn[k] = rel; }
        } else if (tgt[k] > 0) {
          hold[k] = 5;
          vmax[k] = Math.max(vmax[k], tgt[k]);
        } else if (--hold[k] <= 0) {
          on[k] = 0;
          events.push({ k, t0: +tOn[k].toFixed(3), t1: +rel.toFixed(3), v: +vmax[k].toFixed(3) });
        }
      }
    }
    for (let k = 0; k < 88; k++) { // close notes still sounding at crop end
      if (on[k]) events.push({ k, t0: +tOn[k].toFixed(3), t1: +crop.duration.toFixed(3), v: +vmax[k].toFixed(3) });
    }
    events.sort((a, b) => a.t0 - b.t0);
    return events;
  }

  // ---------- public API ----------
  /**
   * @param {{
   *   buffers: Partial<Record<string, AudioBuffer>>,
   *   crop: { start: number, duration: number },
   *   engineParams: { sensitivity:number, attack:number, decay:number, noiseGate:number,
   *                   noteOnThresh:number, noteOffThresh:number, maxPolyphony:number },
   * }} opts
   */
  function generateChart(opts) {
    const { buffers, crop, engineParams: p } = opts;
    const started = performance.now();
    /** @type {Record<string, any>} */
    const signals = {};

    for (const [srcKey, slot] of Object.entries(SOURCE_SLOT)) {
      const buffer = buffers[slot];
      if (!buffer) continue;
      signals[srcKey] = simSignal(monoOf(buffer), buffer.sampleRate, crop,
        /** @type {'perc'|'sust'} */ (SOURCE_TYPE[srcKey]), p);
    }
    if (Object.keys(signals).length === 0) throw new Error('no buffers to chart');

    let notes = [];
    const other = buffers.other;
    if (other) {
      notes = simNotes(monoOf(other), other.sampleRate, crop, p);
    } else {
      console.warn('[chart-gen] no melodic stem — chart will have no note events');
    }

    const chart = {
      version: 1,
      rate: STORE_RATE,
      duration: +crop.duration.toFixed(3),
      signals,
      notes,
      params: { ...p, simRate: SIM_RATE },
    };
    console.log('[chart-gen] rendered', Object.keys(signals).join('+'),
      notes.length + ' notes in', Math.round(performance.now() - started) + 'ms');
    return chart;
  }

  /** @type {any} */ (window).ChartGen = { generateChart };
})();
