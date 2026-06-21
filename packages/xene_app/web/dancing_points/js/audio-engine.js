// Audio engine: load a song, play it, and isolate one frequency band cleanly so
// the visual only reacts to (e.g.) the kick and nothing else.
//
// Isolation strategy: a 4-pole band-pass built from two high-pass + two low-pass
// biquads in series (24 dB/oct skirts) feeding a dedicated analyser. The main
// audio still plays full-range through a separate gain branch, so you HEAR the
// whole song but the points only SEE the isolated band.

window.BANDS = {
  kick:  { label: 'Kick / Sub',    lo: 35,   hi: 110,   type: 'perc' },
  bass:  { label: 'Bassline',      lo: 60,   hi: 250,   type: 'sust' },
  snare: { label: 'Snare / Clap',  lo: 170,  hi: 2200,  type: 'perc' },
  vocal: { label: 'Vocals / Mid',  lo: 300,  hi: 3400,  type: 'sust' },
  hat:   { label: 'Hi-hat / Cym',  lo: 7000, hi: 16000, type: 'perc' },
  full:  { label: 'Full Mix',      lo: 20,   hi: 20000, type: 'sust' },
};

class AudioEngine {
  constructor(audioEl) {
    this.audioEl = audioEl;
    this.ctx = null;
    this.ready = false;

    this.bandKey = 'kick';
    this.bandType = 'perc';
    this.lo = 35;
    this.hi = 110;

    // tunables (driven by UI)
    this.sensitivity = 1.6;
    this.attack = 0.6;   // 0..1, rise smoothing
    this.decay = 0.90;   // 0.80..0.99, fall coefficient

    // live state
    this.prevLevel = 0;
    this.baseline = 0;
    this.level = 0;      // raw band RMS (0..~1)
    this.react = 0;      // fast envelope -> warp
    this.reactSlow = 0;  // lingering envelope -> trails
    this.peak = 0.0001;  // running peak for auto-gain
  }

  // Must be called from a user gesture (first play).
  init() {
    if (this.ctx) return;
    const Ctx = window.AudioContext || window.webkitAudioContext;
    this.ctx = new Ctx();
    this.src = this.ctx.createMediaElementSource(this.audioEl);

    // audible branch — full range
    this.masterGain = this.ctx.createGain();
    this.masterGain.gain.value = 1.0;
    this.src.connect(this.masterGain);
    this.masterGain.connect(this.ctx.destination);

    // analysis branch — steep band-pass (2x HP + 2x LP)
    this.hp1 = this.ctx.createBiquadFilter(); this.hp1.type = 'highpass';
    this.hp2 = this.ctx.createBiquadFilter(); this.hp2.type = 'highpass';
    this.lp1 = this.ctx.createBiquadFilter(); this.lp1.type = 'lowpass';
    this.lp2 = this.ctx.createBiquadFilter(); this.lp2.type = 'lowpass';
    [this.hp1, this.hp2, this.lp1, this.lp2].forEach(f => { f.Q.value = 0.707; });

    this.analyser = this.ctx.createAnalyser();
    this.analyser.fftSize = 1024;
    this.analyser.smoothingTimeConstant = 0.0; // we do our own smoothing
    this.buf = new Float32Array(this.analyser.fftSize);

    this.src.connect(this.hp1);
    this.hp1.connect(this.hp2);
    this.hp2.connect(this.lp1);
    this.lp1.connect(this.lp2);
    this.lp2.connect(this.analyser);

    this.applyBand();
    this.ready = true;
  }

  setBand(key) {
    this.bandKey = key;
    const b = window.BANDS[key];
    this.bandType = b.type;
    this.lo = b.lo;
    this.hi = b.hi;
    this.peak = 0.0001;
    this.baseline = 0;
    this.applyBand();
  }

  // direct edge control (isolation fine-tune)
  setEdges(lo, hi) {
    this.lo = Math.max(20, Math.min(lo, hi - 5));
    this.hi = Math.min(20000, Math.max(hi, this.lo + 5));
    this.applyBand();
  }

  applyBand() {
    if (!this.ctx) return;
    const lo = this.lo, hi = this.hi;
    this.hp1.frequency.value = lo;
    this.hp2.frequency.value = lo;
    this.lp1.frequency.value = hi;
    this.lp2.frequency.value = hi;
  }

  // Per-frame analysis -> updates this.react / this.reactSlow (0..1).
  update() {
    if (!this.ready) {
      // idle decay
      this.react *= 0.9;
      this.reactSlow *= 0.95;
      return;
    }
    this.analyser.getFloatTimeDomainData(this.buf);
    let sum = 0;
    for (let i = 0; i < this.buf.length; i++) {
      const v = this.buf[i];
      sum += v * v;
    }
    const rms = Math.sqrt(sum / this.buf.length);
    this.level = rms;

    // running peak for auto-gain so different songs/bands normalize sanely
    this.peak = Math.max(this.peak * 0.9995, rms);
    const norm = rms / (this.peak + 1e-5); // ~0..1

    // slow baseline (noise floor of the band)
    this.baseline = this.baseline * 0.995 + norm * 0.005;

    let drive;
    if (this.bandType === 'perc') {
      // transient detection: positive flux above the floor -> sharp hits
      const flux = Math.max(0, norm - this.prevLevel);
      drive = flux * this.sensitivity * 6.0;
    } else {
      // sustained: how far above the floor the band currently sits
      drive = Math.max(0, norm - this.baseline) * this.sensitivity * 3.0;
    }
    this.prevLevel = norm;
    drive = Math.max(0, Math.min(1, drive));

    // fast envelope: smoothed attack, coefficient decay -> snap with lingering tail
    if (drive > this.react) {
      this.react += (drive - this.react) * this.attack;
    } else {
      this.react *= this.decay;
    }
    // slow envelope lags further for the trailing point layer
    const slowDecay = Math.min(0.995, this.decay + 0.04);
    this.reactSlow = Math.max(this.reactSlow * slowDecay, this.react * 0.9);
  }
}

window.AudioEngine = AudioEngine;
