// @ts-check
// Stem engine — "ghost track" model.
//
// The user HEARS the real `original` mix (stems never reconstruct it cleanly —
// separation loses phase/spectral detail). The four stems (vocals/drums/bass/
// other) play SILENTLY, purely as analysis sources, in sample-accurate sync with
// the original. The Reactive Source selector reads the correct stem's analyser,
// so "Vocals" reacts to the actual vocal stem while your ears hear the pristine
// master.
//
// Sync: every slot is decoded to an AudioBuffer and played via an
// AudioBufferSourceNode; all sources start() at ONE shared clock time, so they
// share the Web Audio hardware sample clock and never drift. (A pool of <audio>
// elements can't do this — each runs its own clock and slides apart.)
//
// Graph (analysers are stable; source nodes are recreated on play/seek):
//
//   original → master → destination        (AUDIBLE)  ─→ masterAnalyser  ("Full Mix")
//   vocals   → vocalsAnalyser               (silent)
//   bass     → bassAnalyser                 (silent)
//   other    → otherAnalyser                (silent)
//   drums    → drumsAnalyser                (silent)
//   drums    → hp→hp→lp→lp → drumBandAnalyser (silent, kick/snare/hat sub-bands)
//
// If `original` is absent, the stems are routed to master too (audible fallback).

/**
 * @typedef {'vocals'|'drums'|'bass'|'other'} StemKey
 * @typedef {'original'|StemKey} SlotKey
 * @typedef {'perc'|'sust'} ReactType
 * @typedef {Object} SourceDef
 * @property {string}  label
 * @property {StemKey|'master'} stem   the stem this source listens to
 * @property {ReactType} type
 */

/** @type {StemKey[]} */
const STEM_KEYS = ['vocals', 'drums', 'bass', 'other'];
/** @type {SlotKey[]} */
const SLOT_KEYS = ['original', 'vocals', 'drums', 'bass', 'other'];

// Harmonic series of a piano note in KEY-space: overtones 2f/3f/4f/5f land
// ≈ +12/+19/+24/+28 semitones above the fundamental. Weights taper the way a
// real note's overtones do. Used by the multi-pitch extractor (_updateKeyEnergies).
const NOTE_HARM_OFF = [0, 12, 19, 24, 28];
const NOTE_HARM_W = [1.0, 0.6, 0.4, 0.25, 0.15];

// One reactive source per ISOLATED stem — nothing that isn't its own file.
// (Drums is the whole drum stem; no fake "snare / hi-hat" sub-bands.)
/** @type {Record<string, SourceDef>} */
const SOURCES = {
  vocals: { label: 'Vocals',   stem: 'vocals', type: 'sust' },
  drums:  { label: 'Drums',    stem: 'drums',  type: 'perc' },
  bass:   { label: 'Bass',     stem: 'bass',   type: 'sust' },
  other:  { label: 'Melody',   stem: 'other',  type: 'sust' },
  full:   { label: 'Full Mix', stem: 'master', type: 'sust' },
};
/** @type {any} */ (window).SOURCES = SOURCES;
/** @type {any} */ (window).SLOT_KEYS = SLOT_KEYS;

class StemEngine {
  constructor() {
    /** @type {AudioContext|null} */ this.ctx = null;

    // ---- node graph (built lazily) ----
    /** @type {GainNode|null} */     this.master = null;
    /** @type {AnalyserNode|null} */ this.masterAnalyser = null;
    /** @type {Partial<Record<StemKey, AnalyserNode>>} */ this.stemAnalyser = {};

    // ---- decoded audio, keyed by slot ----
    /** @type {Partial<Record<SlotKey, AudioBuffer>>} */ this.buffers = {};
    /** @type {number} */ this._duration = 0;

    // ---- transport ----
    /** @type {AudioBufferSourceNode[]} */ this._sources = [];
    this._playing = false;
    this._offset = 0;
    this._startTime = 0;

    // ---- analysis ----
    /** @type {AnalyserNode|null} */ this._active = null;
    this.buf = new Float32Array(1024);
    this.sourceKey = 'vocals';
    /** @type {ReactType} */ this.sourceType = 'sust';

    // ---- tunables ----
    this.sensitivity = 1.6;
    this.attack = 0.6;
    this.decay = 0.90;
    this.noiseGate = 0.0016;

    // ---- live outputs ----
    this.prevLevel = 0;
    this.baseline = 0;
    this.level = 0;
    this.react = 0;
    this.reactSlow = 0;
    this.peak = 0.0001;
    this.signals = {};
    for (const key of Object.keys(SOURCES)) {
      this.signals[key] = {
        level: 0,
        react: 0,
        reactSlow: 0,
        peak: 0.0001,
        baseline: 0,
        prevLevel: 0,
      };
    }

    // ---- melodic spectrum → 88 piano-key energies (node network sections) ----
    /** @type {Float32Array} */ this.keyEnergies = new Float32Array(88);
    /** @type {AnalyserNode|null} */ this._melodyFreq = null;
    /** @type {Uint8Array|null} */ this._freqData = null;
    /** @type {Array<{start:number,end:number}>} */ this._keyBins = [];
    // note gate state: which keys are currently "held", plus per-frame scratch.
    /** @type {Uint8Array} */ this._noteOn = new Uint8Array(88);
    /** @type {Float32Array} */ this._keyRaw = new Float32Array(88);
    /** @type {Float32Array} */ this._keyWork = new Float32Array(88);
    /** @type {Float32Array} */ this._keyTarget = new Float32Array(88);
    /** @type {Float32Array} */ this._noteHold = new Float32Array(88);
    // note gate thresholds in SALIENCE units (harmonic-weighted sum, ~0..1.5
    // for a strong clean note): a key needs salience > noteOnThresh to light,
    // and candidate extraction keeps running down to noteOffThresh so held
    // notes can sustain quieter than they attacked. maxPolyphony caps how many
    // simultaneous notes can be lit (Guitar-Hero-style: 3 keys → 3 regions).
    // (baked from real-stem tuning in the brain-other.html lab, 2026-07-12:
    // high gate + poly 2 kills harmonic ghosts and ringing-tail regions)
    this.noteOnThresh = 0.74;
    this.noteOffThresh = 0.54;
    this.maxPolyphony = 2;

    // ---- chart drive mode (playlist playback) ----
    // A precomputed reactivity chart (see chart-gen.js). When set, signals +
    // keyEnergies are read from the chart at currentTime instead of live DSP —
    // so playlist tracks only ship the audible master (+ vocal stem for the
    // waveform trail). NULL = normal live-DSP analysis of the loaded stems.
    /** @type {any} */ this.chart = null;

    /** @type {(() => void)|null} */ this.onEnded = null;
  }

  /** @returns {SlotKey[]} */
  get loadedKeys() { return /** @type {SlotKey[]} */ (Object.keys(this.buffers)); }
  get hasStems() { return this.loadedKeys.length > 0; }
  get duration() { return this._duration; }
  get isPlaying() { return this._playing; }
  get currentTime() {
    if (!this.ctx) return this._offset;
    const t = this._playing
      ? this._offset + (this.ctx.currentTime - this._startTime)
      : this._offset;
    return Math.max(0, Math.min(this._duration, t));
  }

  _ensureGraph() {
    if (this.ctx) return;
    const Ctor = window.AudioContext || /** @type {any} */ (window).webkitAudioContext;
    const ctx = new Ctor();
    this.ctx = ctx;

    /** @param {AnalyserNode} a */
    const cfg = (a) => { a.fftSize = 1024; a.smoothingTimeConstant = 0.0; return a; };

    this.master = ctx.createGain();
    this.master.gain.value = 1.0;
    this.master.connect(ctx.destination);
    this.masterAnalyser = cfg(ctx.createAnalyser());
    this.master.connect(this.masterAnalyser);

    for (const key of STEM_KEYS) this.stemAnalyser[key] = cfg(ctx.createAnalyser());

    // High-res spectrum on the melodic ('other') stem → 88 piano-key bands.
    const mf = ctx.createAnalyser();
    mf.fftSize = 8192;
    mf.smoothingTimeConstant = 0.6;
    this._melodyFreq = mf;
    this._freqData = new Uint8Array(mf.frequencyBinCount);
    this._keyBins = this._computeKeyBins(ctx.sampleRate, mf.fftSize);

    this.buf = new Float32Array(1024);
    this.setSource(this.sourceKey);
  }

  /**
   * iOS/Safari only unlocks Web Audio from a real user gesture. Playlist
   * playback fetches and decodes before it starts, so the tap handler must call
   * this immediately, before any await loses the gesture activation.
   * @returns {Promise<string>}
   */
  async unlockAudio() {
    this._ensureGraph();
    const ctx = this.ctx;
    if (!ctx) return 'unavailable';
    if (ctx.state === 'suspended') {
      await ctx.resume();
    }
    console.log('[stem-engine] audio context state:', ctx.state);
    return ctx.state;
  }

  /**
   * FFT bin ranges for the 88 equal-tempered piano keys (A0=27.5Hz … C8).
   * @param {number} sampleRate @param {number} fftSize
   */
  _computeKeyBins(sampleRate, fftSize) {
    const binHz = sampleRate / fftSize;
    const bins = [];
    for (let k = 0; k < 88; k++) {
      const f = 27.5 * Math.pow(2, k / 12);                 // key fundamental
      const start = Math.max(0, Math.floor((f / Math.pow(2, 1 / 24)) / binHz));
      const end = Math.max(start, Math.ceil((f * Math.pow(2, 1 / 24)) / binHz));
      bins.push({ start, end });
    }
    return bins;
  }

  /**
   * Decode + install ONE slot's file. Incremental — other slots are kept.
   * If playing, re-locks all sources in sync so the new one joins cleanly.
   * @param {SlotKey} key
   * @param {ArrayBuffer} data
   * @returns {Promise<void>}
   */
  async setSlot(key, data) {
    this._ensureGraph();
    const ctx = this.ctx;
    if (!ctx) throw new Error('AudioContext unavailable');
    const buffer = await ctx.decodeAudioData(data.slice(0)); // slice: decode detaches
    this.buffers[key] = buffer;
    this._recomputeDuration();
    console.log(
      '[stem-engine] decoded',
      key,
      'duration=' + buffer.duration.toFixed(2),
      'channels=' + buffer.numberOfChannels,
      'ctx=' + ctx.state
    );
    if (this._playing) { this._offset = this.currentTime; this._startPlayback(); }
  }

  _recomputeDuration() {
    let d = 0;
    for (const k of this.loadedKeys) {
      const b = this.buffers[k];
      if (b) d = Math.max(d, b.duration);
    }
    this._duration = d;
  }

  /** Which reactive sources currently have their stem loaded. */
  /** @param {string} sourceKey */
  isSourceAvailable(sourceKey) {
    const def = SOURCES[sourceKey];
    if (!def) return false;
    if (def.stem === 'master') return !!this.buffers.original || this.hasStems;
    return !!this.buffers[def.stem];
  }

  _startPlayback() {
    const ctx = this.ctx;
    if (!ctx || !this.hasStems || !this.master) return;
    this._stopSources();

    const hasOriginal = !!this.buffers.original;
    const when = ctx.currentTime + 0.03; // shared lead → all start on the same tick
    /** @type {AudioBufferSourceNode[]} */
    const sources = [];
    for (const key of this.loadedKeys) {
      const buffer = this.buffers[key];
      if (!buffer) continue;
      const src = ctx.createBufferSource();
      src.buffer = buffer;

      if (key === 'original') {
        src.connect(this.master);                 // audible
      } else {
        const a = this.stemAnalyser[key];
        if (a) src.connect(a);                     // silent analysis
        if (key === 'other' && this._melodyFreq) src.connect(this._melodyFreq);
        if (!hasOriginal) src.connect(this.master); // fallback: make stems audible
      }
      src.start(when, this._offset);
      sources.push(src);
    }
    console.log(
      '[stem-engine] playback start',
      'slots=' + this.loadedKeys.join('+'),
      'offset=' + this._offset.toFixed(2),
      'duration=' + this._duration.toFixed(2),
      'ctx=' + ctx.state,
      'hasOriginal=' + hasOriginal
    );
    if (sources[0]) {
      sources[0].onended = () => {
        this._playing = false;
        this._offset = 0;
        if (this.onEnded) this.onEnded();
      };
    }
    this._sources = sources;
    this._startTime = when;
    this._playing = true;
    setTimeout(() => this._probeMasterOutput('250ms'), 250);
  }

  /** @param {string} label */
  _probeMasterOutput(label) {
    const analyser = this.masterAnalyser;
    if (!analyser) return;
    analyser.getFloatTimeDomainData(this.buf);
    let sum = 0;
    for (let i = 0; i < this.buf.length; i++) {
      const v = this.buf[i];
      sum += v * v;
    }
    const rms = Math.sqrt(sum / this.buf.length);
    console.log('[stem-engine] master rms', label, rms.toFixed(5), 'playing=' + this._playing);
  }

  _stopSources() {
    for (const s of this._sources) {
      try { s.onended = null; s.stop(); s.disconnect(); } catch (_e) { /* already stopped */ }
    }
    this._sources = [];
  }

  play() {
    this._ensureGraph();
    if (this.ctx && this.ctx.state === 'suspended') {
      this.ctx.resume().then(() => {
        console.log('[stem-engine] audio context state:', this.ctx && this.ctx.state);
      }).catch((err) => {
        console.warn('[stem-engine] audio resume failed', err);
      });
    }
    if (this._playing) return;
    this._startPlayback();
  }

  pause() {
    if (!this._playing) return;
    const pos = this.currentTime;
    this._stopSources();
    this._offset = pos;
    this._playing = false;
  }

  /** @param {number} seconds */
  seek(seconds) {
    const t = Math.max(0, Math.min(this._duration || 0, seconds));
    this._offset = t;
    if (this._playing) this._startPlayback();
  }

  stop() {
    this._stopSources();
    this._offset = 0;
    this._playing = false;
  }

  /** Drop every decoded slot (the playlist swaps tracks wholesale). */
  reset() {
    this.stop();
    this.buffers = {};
    this._duration = 0;
    this.chart = null;
    for (const sig of Object.values(this.signals)) {
      sig.level = 0; sig.react = 0; sig.reactSlow = 0;
      sig.peak = 0.0001; sig.baseline = 0; sig.prevLevel = 0;
    }
    this.keyEnergies.fill(0);
    this._noteOn.fill(0);
    this._noteHold.fill(0);
  }

  /**
   * Install (or clear) a precomputed reactivity chart. Invalid charts are
   * rejected loudly and playback falls back to live DSP.
   * @param {any} chart
   */
  setChart(chart) {
    if (chart && (chart.version !== 1 || !chart.rate || !chart.signals)) {
      console.warn('[stem-engine] unsupported chart, falling back to DSP', chart && chart.version);
      this.chart = null;
      return;
    }
    this.chart = chart || null;
    console.log('[stem-engine] chart mode', this.chart ? 'ON rate=' + this.chart.rate : 'off');
  }

  /** @param {string} key */
  setSource(key) {
    const def = SOURCES[key] || SOURCES.full;
    this.sourceKey = key;
    this.sourceType = def.type;

    // Full Mix reads the audible original; every other source reads its own stem.
    this._active = def.stem === 'master'
      ? this.masterAnalyser
      : this.stemAnalyser[/** @type {StemKey} */ (def.stem)] || null;

    this.peak = 0.0001;
    this.baseline = 0;
    this.prevLevel = 0;
  }

  /**
   * @param {AnalyserNode|null} analyser
   * @param {any} sig
   * @param {ReactType} type
   */
  _updateSignal(analyser, sig, type) {
    if (!analyser || !this._playing) {
      sig.react *= this.decay;
      sig.reactSlow *= Math.min(0.995, this.decay + 0.04);
      sig.level *= 0.85;
      return;
    }
    analyser.getFloatTimeDomainData(this.buf);
    let sum = 0;
    for (let i = 0; i < this.buf.length; i++) { const v = this.buf[i]; sum += v * v; }
    const rms = Math.sqrt(sum / this.buf.length);
    sig.level = rms;

    if (rms < this.noiseGate) {
      sig.prevLevel = 0;
      sig.react *= this.decay;
      sig.reactSlow *= Math.min(0.995, this.decay + 0.04);
      return;
    }

    sig.peak = Math.max(sig.peak * 0.9995, rms);
    const norm = rms / (sig.peak + 1e-5);
    sig.baseline = sig.baseline * 0.995 + norm * 0.005;

    let drive;
    if (type === 'perc') {
      const flux = Math.max(0, norm - sig.prevLevel);
      drive = flux * this.sensitivity * 6.0;
    } else {
      drive = Math.max(0, norm - sig.baseline) * this.sensitivity * 3.0;
    }
    sig.prevLevel = norm;
    drive = Math.max(0, Math.min(1, drive));

    if (drive > sig.react) sig.react += (drive - sig.react) * this.attack;
    else sig.react *= this.decay;
    const slowDecay = Math.min(0.995, this.decay + 0.04);
    sig.reactSlow = Math.max(sig.reactSlow * slowDecay, sig.react * 0.9);
  }

  update() {
    if (this.chart) {
      this._updateFromChart();
    } else {
      for (const [key, def] of Object.entries(SOURCES)) {
        const analyser = def.stem === 'master'
          ? this.masterAnalyser
          : this.stemAnalyser[/** @type {StemKey} */ (def.stem)] || null;
        this._updateSignal(analyser, this.signals[key], def.type);
      }
      this._updateKeyEnergies();
    }

    const active = this.signals[this.sourceKey] || this.signals.full;
    this.level = active.level;
    this.react = active.react;
    this.reactSlow = active.reactSlow;
    this.peak = active.peak;
  }

  /**
   * Chart drive: read signals + note events from the precomputed chart at the
   * transport position. Charted signals are quantised 0..250 at chart.rate Hz
   * and linearly interpolated; keys not covered by a note event get the same
   * 0.70 release the live note gate uses, so the look matches DSP playback.
   */
  _updateFromChart() {
    const chart = this.chart;
    const t = this.currentTime;
    const playing = this._playing;

    for (const key of Object.keys(SOURCES)) {
      const sig = this.signals[key];
      const ch = playing ? chart.signals[key] : null;
      if (!ch) {
        // not charted (or paused) → decay exactly like a missing analyser
        sig.react *= this.decay;
        sig.reactSlow *= Math.min(0.995, this.decay + 0.04);
        sig.level *= 0.85;
        continue;
      }
      sig.react = this._sampleChart(ch.react, t, chart.rate);
      sig.reactSlow = this._sampleChart(ch.reactSlow, t, chart.rate);
      sig.level = this._sampleChart(ch.level, t, chart.rate);
      sig.peak = 1.0; // charted levels are already normalised for the meters
    }

    // note events → keyEnergies, mirroring the live gate's envelopes
    const e = this.keyEnergies, on = this._noteOn;
    const notes = playing && chart.notes ? chart.notes : null;
    for (let k = 0; k < 88; k++) {
      let v = 0;
      if (notes) {
        for (let i = 0; i < notes.length; i++) {
          const ev = notes[i];
          if (ev.k === k && t >= ev.t0 && t <= ev.t1) { v = ev.v; break; }
        }
      }
      if (v > 0) {
        const target = Math.min(1, 0.35 + v * 0.55);
        if (!on[k]) { on[k] = 1; e[k] = target; }        // onset: snap on
        else e[k] += (target - e[k]) * 0.10;             // sustain: ease
      } else {
        on[k] = 0;
        e[k] *= 0.70;                                    // release: fast dim
      }
    }
  }

  /**
   * Linear interpolation into a quantised (0..250) chart array.
   * @param {number[]} arr @param {number} t @param {number} rate
   */
  _sampleChart(arr, t, rate) {
    if (!arr || arr.length === 0) return 0;
    const x = Math.max(0, Math.min(arr.length - 1, t * rate));
    const i = Math.floor(x);
    const f = x - i;
    const a = arr[i], b = arr[Math.min(arr.length - 1, i + 1)];
    return ((a + (b - a) * f) / 250);
  }

  /**
   * Fill keyEnergies[88] with NOTE envelopes (0..1 per piano key) via greedy
   * multi-pitch extraction (simplified Klapuri harmonic-salience method):
   *
   *   1. Raw band energy per key from the melodic spectrum.
   *   2. Score every key by harmonic SALIENCE — weighted sum of energy at its
   *      fundamental and overtones (+12/+19/+24/+28 keys ≈ 2f/3f/4f/5f). A real
   *      note scores high at its fundamental; its overtone keys score low
   *      because they lack their own harmonic series above them.
   *   3. Accept the strongest key as a note, SUBTRACT its harmonic series from
   *      the working spectrum (so its overtones can't win as fake notes), and
   *      repeat — up to maxPolyphony notes per frame.
   *   4. Hysteresis + envelope per key: snap on at note onset, hold steady
   *      while the note sustains (short grace so one dropped frame doesn't
   *      flicker), fast-release when it ends — one region per audible note,
   *      lit for the note's duration, then a quick dim-out.
   */
  _updateKeyEnergies() {
    const mf = this._melodyFreq, data = this._freqData, bins = this._keyBins;
    const e = this.keyEnergies, on = this._noteOn, raw = this._keyRaw;
    const work = this._keyWork, tgt = this._keyTarget, hold = this._noteHold;
    if (!mf || !data || !this._playing) {
      for (let k = 0; k < 88; k++) { e[k] *= 0.70; on[k] = 0; hold[k] = 0; } // fade to dark
      return;
    }
    mf.getByteFrequencyData(/** @type {any} */ (data));
    for (let k = 0; k < 88; k++) {
      const { start, end } = bins[k];
      let sum = 0, n = 0;
      for (let b = start; b <= end && b < data.length; b++) { sum += data[b]; n++; }
      raw[k] = n > 0 ? (sum / n) / 255 : 0;
    }

    // greedy extraction: strongest salience wins, its harmonics are removed
    work.set(raw);
    tgt.fill(0);
    const OFF = this.noteOffThresh;
    for (let it = 0; it < this.maxPolyphony; it++) {
      let bestK = -1, bestS = 0;
      for (let k = 0; k < 88; k++) {
        if (work[k] <= 0.02) continue; // a note needs SOME fundamental energy
        let s = 0;
        for (let h = 0; h < NOTE_HARM_OFF.length; h++) {
          const j = k + NOTE_HARM_OFF[h];
          if (j < 88) s += NOTE_HARM_W[h] * work[j];
        }
        if (s > bestS) { bestS = s; bestK = k; }
      }
      if (bestK < 0 || bestS < OFF) break;
      tgt[bestK] = Math.min(1, bestS);
      const f = work[bestK];
      for (let h = 0; h < NOTE_HARM_OFF.length; h++) {
        const j = bestK + NOTE_HARM_OFF[h];
        if (j < 88) work[j] = Math.max(0, work[j] - NOTE_HARM_W[h] * f);
      }
    }

    // hysteresis + envelopes
    const ON = this.noteOnThresh;
    for (let k = 0; k < 88; k++) {
      if (!on[k]) {
        if (tgt[k] > ON) { on[k] = 1; hold[k] = 5; e[k] = Math.min(1, 0.35 + tgt[k] * 0.55); }
        else e[k] *= 0.70; // dark / finishing its release
      } else if (tgt[k] > 0) {
        hold[k] = 5; // still sounding: refresh grace, ease toward its level
        e[k] += (Math.min(1, 0.35 + tgt[k] * 0.55) - e[k]) * 0.10;
      } else if (--hold[k] <= 0) {
        on[k] = 0; e[k] *= 0.70; // note ended → fast release, done
      }
      // else: within grace — hold the current lit level, no flicker
    }
  }
}

/** @type {any} */ (window).StemEngine = StemEngine;
