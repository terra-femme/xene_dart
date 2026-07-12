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
    // note gate state: which keys are currently "held", plus a raw-band scratch.
    /** @type {Uint8Array} */ this._noteOn = new Uint8Array(88);
    /** @type {Float32Array} */ this._keyRaw = new Float32Array(88);
    // note gate hysteresis on raw band energy (0..1): a key must exceed
    // noteOnThresh to light, and stays lit until it drops below noteOffThresh.
    this.noteOnThresh = 0.32;
    this.noteOffThresh = 0.16;

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
  }

  _stopSources() {
    for (const s of this._sources) {
      try { s.onended = null; s.stop(); s.disconnect(); } catch (_e) { /* already stopped */ }
    }
    this._sources = [];
  }

  play() {
    this._ensureGraph();
    if (this.ctx && this.ctx.state === 'suspended') this.ctx.resume();
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
    for (const [key, def] of Object.entries(SOURCES)) {
      const analyser = def.stem === 'master'
        ? this.masterAnalyser
        : this.stemAnalyser[/** @type {StemKey} */ (def.stem)] || null;
      this._updateSignal(analyser, this.signals[key], def.type);
    }
    this._updateKeyEnergies();

    const active = this.signals[this.sourceKey] || this.signals.full;
    this.level = active.level;
    this.react = active.react;
    this.reactSlow = active.reactSlow;
    this.peak = active.peak;
  }

  /**
   * Fill keyEnergies[88] with NOTE envelopes (0..1 per piano key), not raw band
   * energy. A key lights only on a real note onset — a local spectral peak above
   * noteOnThresh that is not the octave harmonic of a stronger note 12 keys
   * below (kills the skirt of neighbours + overtones that lit many regions per
   * note). It then HOLDS steady while the band sustains above noteOffThresh,
   * and releases fast when the note ends — one region, lit for the note's
   * duration, then done (vocals-style).
   */
  _updateKeyEnergies() {
    const mf = this._melodyFreq, data = this._freqData, bins = this._keyBins;
    const e = this.keyEnergies, on = this._noteOn, raw = this._keyRaw;
    if (!mf || !data || !this._playing) {
      for (let k = 0; k < 88; k++) { e[k] *= 0.70; on[k] = 0; } // fade to dark
      return;
    }
    mf.getByteFrequencyData(/** @type {any} */ (data));
    for (let k = 0; k < 88; k++) {
      const { start, end } = bins[k];
      let sum = 0, n = 0;
      for (let b = start; b <= end && b < data.length; b++) { sum += data[b]; n++; }
      raw[k] = n > 0 ? (sum / n) / 255 : 0;
    }
    const ON = this.noteOnThresh, OFF = this.noteOffThresh;
    for (let k = 0; k < 88; k++) {
      if (!on[k]) {
        const peak = raw[k] > ON
          && raw[k] >= (k > 0 ? raw[k - 1] : 0)
          && raw[k] >= (k < 87 ? raw[k + 1] : 0);
        const harmonic = k >= 12 && raw[k - 12] > ON && raw[k - 12] > raw[k] * 0.85;
        if (peak && !harmonic) { on[k] = 1; e[k] = Math.min(1, 0.55 + raw[k] * 0.6); }
        else e[k] *= 0.70; // dark / finishing its release
      } else if (raw[k] < OFF) {
        on[k] = 0; e[k] *= 0.70; // note ended → fast release, done
      } else {
        // sustain: ease toward the note's current level so it stays lit
        // without pulsing hard with every tremolo of the band
        e[k] += (Math.min(1, 0.55 + raw[k] * 0.6) - e[k]) * 0.10;
      }
    }
  }
}

/** @type {any} */ (window).StemEngine = StemEngine;
