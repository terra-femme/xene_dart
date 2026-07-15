// @ts-check
// Wires UI -> StemEngine -> Scene. Runs the render loop.
(function () {
  'use strict';

  /** @param {string} id */
  const $ = (id) => /** @type {any} */ (document.getElementById(id));
  const LS = 'dancingPoints.v2'; // v2: stem sources (was v1 band presets)

  // ---- color presets (minimal mono first) ----
  const COLORS = [
    { name: 'Mono',    base: '#dfe6ee', hot: '#bfe6f5' },
    { name: 'Ice',     base: '#cfe0ee', hot: '#9fd0ff' },
    { name: 'Amber',   base: '#efe7d8', hot: '#ffc879' },
    { name: 'Magenta', base: '#efdfe9', hot: '#ff9fd6' },
  ];
  const MODES = [
    { name: 'Shear',  desc: 'sideways noise' },
    { name: 'Burst',  desc: 'radial push' },
    { name: 'Ripple', desc: 'travelling wave' },
    { name: 'Shards', desc: 'glitch displace' },
  ];

  /** @type {Record<string, {label:string, stem:string, type:string, lo?:number, hi?:number}>} */
  const SOURCES = /** @type {any} */ (window).SOURCES;

  /** @param {number} s */
  const fmtTime = (s) => {
    if (!isFinite(s)) s = 0;
    const m = Math.floor(s / 60), ss = Math.floor(s % 60);
    return m + ':' + String(ss).padStart(2, '0');
  };

  const engine = new (/** @type {any} */ (window).StemEngine)();
  const scene = createScene($('gl'));
  // dev: console handle for live-tuning (e.g. xeneEngine.noteOnThresh = 0.4)
  /** @type {any} */ (window).xeneEngine = engine;

  // ---- xene: haptics (the accessibility core). Full-length playback, no cap. ----
  const capDuration = () => engine.duration || 0;

  // Native bridge: inside the Flutter WebView, XeneHaptics routes beats to
  // Flutter's HapticFeedback (works on iOS, where navigator.vibrate is ignored).
  const XH = /** @type {any} */ (window).XeneHaptics;
  const hapticBridge = !!(XH && XH.postMessage);
  /** @param {number} level */
  function fireHaptic(level) {
    if (hapticBridge) {
      XH.postMessage(level > 0.75 ? 'heavy' : level > 0.5 ? 'medium' : 'light');
    } else if (navigator.vibrate) {
      navigator.vibrate(Math.round(8 + Math.min(1, level) * 32)); // 8-40ms
    }
    pulseHapticIndicator(level); // visual mirror — SEE the tap timing where you can't feel it (desktop/iOS web)
  }

  // Visual haptic indicator (dev aid): a dot that flashes exactly when a haptic tap
  // fires, sized + coloured by intensity (green light / amber medium / pink heavy).
  const hapticDot = document.createElement('div');
  Object.assign(hapticDot.style, {
    position: 'fixed', left: '50%', top: '20px', transform: 'translateX(-50%) scale(0.7)',
    width: '20px', height: '20px', borderRadius: '50%', background: '#8fe6c2',
    opacity: '0.14', pointerEvents: 'none', zIndex: '30',
  });
  const hapticLbl = document.createElement('div');
  Object.assign(hapticLbl.style, {
    position: 'fixed', left: '50%', top: '42px', transform: 'translateX(-50%)',
    font: '9px ui-monospace, Menlo, monospace', letterSpacing: '0.18em',
    color: 'rgba(255,255,255,0.4)', pointerEvents: 'none', zIndex: '30',
  });
  hapticLbl.textContent = 'HAPTIC';
  document.body.appendChild(hapticDot);
  document.body.appendChild(hapticLbl);
  /** @param {number} level */
  function pulseHapticIndicator(level) {
    const lvl = Math.min(1, Math.max(0, level));
    const color = lvl > 0.75 ? '#ff5a7a' : lvl > 0.5 ? '#ffb14a' : '#8fe6c2';
    hapticDot.style.transition = 'none';
    hapticDot.style.background = color;
    hapticDot.style.boxShadow = '0 0 18px ' + color;
    hapticDot.style.opacity = '1';
    hapticDot.style.transform = 'translateX(-50%) scale(' + (0.9 + lvl * 1.2) + ')';
    void hapticDot.offsetWidth; // reflow so the fade re-triggers on every hit
    hapticDot.style.transition = 'opacity 0.3s ease, transform 0.3s ease';
    hapticDot.style.opacity = '0.14';
    hapticDot.style.transform = 'translateX(-50%) scale(0.7)';
  }
  let hapticsOn = ('vibrate' in navigator) || hapticBridge;
  // Drums-only haptic test: mirror the center wire/noise ball's drum drive.
  // Bass resonance is a separate later pass once the drum feel is judged.
  const HAPTIC_ON_THRESHOLD = 0.34;
  const HAPTIC_OFF_THRESHOLD = 0.14;
  const HAPTIC_ATTACK_DELTA = 0.08;
  const HAPTIC_MIN_GAP_MS = 115;
  const hapticGate = { prev: 0, armed: true, lastMs: -10000 };

  const state = {
    source: 'vocals',
    mode: 0,
    color: 0,
    warp: 0.8,
    density: 6000,
    size: 0.7,
    rot: 0.18,
  };

  // ---------- build source buttons (from stem-aware SOURCES) ----------
  const bandsEl = $('bands');
  Object.entries(SOURCES).forEach(([key, def]) => {
    const el = document.createElement('button');
    el.className = 'band' + (key === state.source ? ' active' : '');
    el.dataset.key = key;
    const sub = def.stem === 'master' ? 'mix' : def.stem;
    el.innerHTML = `<div class="bn">${def.label}</div><div class="bf">${sub}</div>`;
    el.addEventListener('click', () => selectSource(key));
    bandsEl.appendChild(el);
  });

  /** @param {string} key */
  function selectSource(key) {
    state.source = key;
    engine.setSource(key);
    [...bandsEl.children].forEach((c) => c.classList.toggle('active', c.dataset.key === key));
    persist();
  }

  // ---------- build mode buttons ----------
  const modesEl = $('modes');
  MODES.forEach((m, i) => {
    const el = document.createElement('button');
    el.className = 'mode' + (i === state.mode ? ' active' : '');
    el.innerHTML = `<div class="mn">${m.name}</div><div class="md">${m.desc}</div>`;
    el.addEventListener('click', () => {
      state.mode = i;
      scene.setMode(i);
      [...modesEl.children].forEach((c, j) => c.classList.toggle('active', j === i));
      persist();
    });
    modesEl.appendChild(el);
  });

  // ---------- color swatches ----------
  const swEl = $('swatches');
  COLORS.forEach((c, i) => {
    const el = document.createElement('button');
    el.className = 'sw' + (i === state.color ? ' active' : '');
    el.style.background = `radial-gradient(circle at 35% 35%, ${c.hot}, ${c.base})`;
    el.title = c.name;
    el.addEventListener('click', () => {
      state.color = i;
      scene.setColors(c.base, c.hot);
      $('vCol').textContent = c.name;
      [...swEl.children].forEach((s, j) => s.classList.toggle('active', j === i));
      persist();
    });
    swEl.appendChild(el);
  });

  // ---------- reaction controls ----------
  $('sens').addEventListener('input', (/** @type {any} */ e) => {
    engine.sensitivity = +e.target.value / 100;
    $('vSens').textContent = engine.sensitivity.toFixed(2) + '×';
    persist();
  });
  $('atk').addEventListener('input', (/** @type {any} */ e) => {
    engine.attack = +e.target.value / 100;
    $('vAtk').textContent = engine.attack.toFixed(2);
    persist();
  });
  $('rel').addEventListener('input', (/** @type {any} */ e) => {
    engine.decay = 0.80 + (+e.target.value / 100) * 0.19; // 0.80..0.99
    $('vRel').textContent = engine.decay.toFixed(2);
    persist();
  });
  $('warp').addEventListener('input', (/** @type {any} */ e) => {
    state.warp = +e.target.value / 100;
    scene.setWarp(state.warp);
    $('vWarp').textContent = state.warp.toFixed(2);
    persist();
  });

  // ---------- form controls ----------
  /** @type {any} */ let densTimer = null;
  $('dens').addEventListener('input', (/** @type {any} */ e) => {
    state.density = +e.target.value;
    $('vDens').textContent = String(state.density);
    clearTimeout(densTimer);
    densTimer = setTimeout(() => { scene.regen(state.density); }, 120);
    persist();
  });
  $('size').addEventListener('input', (/** @type {any} */ e) => {
    state.size = +e.target.value / 100;
    scene.setSize(state.size);
    $('vSize').textContent = state.size.toFixed(2);
    persist();
  });
  $('rot').addEventListener('input', (/** @type {any} */ e) => {
    state.rot = (+e.target.value / 100) * 0.5;
    scene.setRotation(state.rot);
    $('vRot').textContent = state.rot.toFixed(2);
    persist();
  });

  // ---------- stems: per-slot upload (incremental, ghost-track model) ----------
  // You HEAR `original`; the four stems play silently for analysis only.
  const SLOTS = [
    { key: 'original', label: 'Original — you hear this' },
    { key: 'vocals',   label: 'Vocals' },
    { key: 'drums',    label: 'Drums' },
    { key: 'bass',     label: 'Bass' },
    { key: 'other',    label: 'Other' },
  ];
  const slotsEl = $('slots');
  const slotInput = $('file');        // one hidden input, retargeted per slot click
  let slotTarget = 'original';
  /** @type {Record<string, any>} */
  const slotEls = {};

  SLOTS.forEach((s) => {
    const el = document.createElement('button');
    el.type = 'button';
    el.className = 'slot' + (s.key === 'original' ? ' original' : '');
    el.dataset.key = s.key;
    el.innerHTML = `<div class="sl-label">${s.label}</div><div class="sl-file" id="slf-${s.key}">— empty —</div>`;
    el.addEventListener('click', () => { slotTarget = s.key; slotInput.click(); });
    ['dragover', 'dragenter'].forEach((ev) => el.addEventListener(ev, (/** @type {any} */ e) => { e.preventDefault(); el.classList.add('drag'); }));
    ['dragleave', 'drop'].forEach((ev) => el.addEventListener(ev, (/** @type {any} */ e) => { e.preventDefault(); el.classList.remove('drag'); }));
    el.addEventListener('drop', (/** @type {any} */ e) => {
      if (e.dataTransfer && e.dataTransfer.files) handleDrop(e.dataTransfer.files, s.key);
    });
    slotsEl.appendChild(el);
    slotEls[s.key] = el;
  });

  slotInput.addEventListener('change', (/** @type {any} */ e) => {
    const f = e.target.files && e.target.files[0];
    if (f) assignFile(slotTarget, f);
    slotInput.value = ''; // let the same file be re-picked later
  });

  /**
   * Filename → slot key. StemRoller's `instrumental` is intentionally ignored
   * (it's mix-minus-vocals, not a single source).
   * @param {string} name
   * @returns {string|null}
   */
  function classifyStem(name) {
    const n = name.toLowerCase();
    if (n.includes('instrumental')) return null;
    if (n.includes('original') || n.includes('mixdown')) return 'original';
    if (n.includes('vocal')) return 'vocals';
    if (n.includes('drum'))  return 'drums';
    if (n.includes('bass'))  return 'bass';
    if (n.includes('other')) return 'other';
    return null;
  }

  // Drop on a slot: a single file goes to THAT slot; multiple files auto-sort
  // by filename (so you can still drag the whole folder in if you want).
  /** @param {FileList} fileList @param {string} targetKey */
  function handleDrop(fileList, targetKey) {
    const files = [...fileList].filter((f) => f.type.startsWith('audio') || /\.(wav|mp3|m4a|ogg|flac)$/i.test(f.name));
    if (files.length === 0) return;
    if (files.length === 1) { assignFile(targetKey, files[0]); return; }
    files.forEach((f) => { const k = classifyStem(f.name); if (k) assignFile(k, f); });
  }

  /** @param {string} key @param {File} file */
  async function assignFile(key, file) {
    const fileEl = $('slf-' + key);
    if (fileEl) fileEl.textContent = 'decoding…';
    try {
      const buf = await file.arrayBuffer();
      await engine.setSlot(key, buf);
      if (fileEl) fileEl.textContent = file.name.replace(/\.[^.]+$/, '');
      if (slotEls[key]) slotEls[key].classList.add('filled');
      onStemsChanged();
    } catch (err) {
      console.error('[dancing-points] load failed', key, err);
      if (fileEl) fileEl.textContent = 'error';
    }
  }

  // Reflect current stems into transport + source availability.
  function onStemsChanged() {
    $('status').textContent = engine.hasStems ? engine.loadedKeys.length + ' loaded' : 'no stems';
    $('play').disabled = !engine.hasStems;
    $('dur').textContent = fmtTime(capDuration());
    [...bandsEl.children].forEach((c) => {
      c.classList.toggle('unavail', !engine.isSourceAvailable(c.dataset.key));
    });
    syncPlayIcon();
    syncCropUi(); // crop slider range follows the loaded duration
  }

  // ---------- transport ----------
  const playBtn = $('play');
  const playIco = $('playIco');
  const scrub = $('scrub');
  let scrubbing = false;

  function syncPlayIcon() {
    playIco.innerHTML = engine.isPlaying
      ? '<path d="M6 5h4v14H6zM14 5h4v14h-4z"/>'
      : '<path d="M8 5v14l11-7z"/>';
  }

  playBtn.addEventListener('click', () => {
    if (!engine.hasStems) return;
    if (engine.isPlaying) engine.pause(); else engine.play();
    syncPlayIcon();
  });
  scrub.addEventListener('input', () => {
    scrubbing = true;
    $('cur').textContent = fmtTime((+scrub.value / 1000) * capDuration());
  });
  scrub.addEventListener('change', () => {
    engine.seek((+scrub.value / 1000) * capDuration());
    scrubbing = false;
    syncPlayIcon();
  });

  engine.onEnded = () => {
    scrub.value = '0';
    $('cur').textContent = '0:00';
    syncPlayIcon();
    // playlist auto-advance (no-op when nothing from the playlist is active)
    const XP = /** @type {any} */ (window).XenePlaylist;
    if (XP && XP.advance) XP.advance();
  };

  // ---------- save track: crop window + export (producer flow) ----------
  // Crop a 30s window out of the loaded track, loop-preview it, then export
  // every loaded slot cropped to that window + the tuned settings as one zip.
  // Bundle contract lives in track-export.js; the playlist loader reads it back.
  const CROP_LEN = 30;
  const crop = { start: 0, loop: false };
  const cropStartEl = $('cropStart');
  const cropLoopBtn = $('cropLoop');
  const exportBtn = $('exportTrack');

  const cropLen = () => Math.min(CROP_LEN, Math.max(0, capDuration() - crop.start));
  const cropEnd = () => crop.start + cropLen();

  function syncCropUi() {
    const dur = capDuration();
    const maxStart = Math.max(0, dur - CROP_LEN);
    if (crop.start > maxStart) crop.start = maxStart; // track got shorter
    cropStartEl.max = maxStart.toFixed(1);
    if (+cropStartEl.value !== crop.start) cropStartEl.value = String(crop.start);
    cropStartEl.disabled = !engine.hasStems;
    exportBtn.disabled = !engine.hasStems;
    $('vCrop').textContent = engine.hasStems
      ? fmtTime(crop.start) + ' – ' + fmtTime(cropEnd()) + ' · ' + cropLen().toFixed(0) + 's'
      : '—';
    cropLoopBtn.classList.toggle('active', crop.loop);
    $('cropLoopLabel').textContent = crop.loop ? 'Preview loop: ON' : 'Preview loop: OFF';
  }

  cropStartEl.addEventListener('input', () => {
    crop.start = +cropStartEl.value;
    syncCropUi();
  });
  cropStartEl.addEventListener('change', () => {
    // while loop-previewing, moving the window jumps playback into it
    if (crop.loop) { engine.seek(crop.start); syncPlayIcon(); }
  });
  cropLoopBtn.addEventListener('click', () => {
    if (!engine.hasStems) return;
    crop.loop = !crop.loop;
    if (crop.loop) {
      engine.seek(crop.start);
      if (!engine.isPlaying) engine.play();
      syncPlayIcon();
    }
    syncCropUi();
  });

  // One snapshot shape shared by export (track.json) and, later, the playlist
  // loader — keep in sync with restore()/persist().
  function settingsSnapshot() {
    return {
      engine: {
        sensitivity: engine.sensitivity,
        attack: engine.attack,
        decay: engine.decay,
        source: state.source,
      },
      look: {
        mode: state.mode,
        color: state.color,
        warp: state.warp,
        density: state.density,
        size: state.size,
        rot: state.rot,
      },
    };
  }

  exportBtn.addEventListener('click', () => {
    if (!engine.hasStems) return;
    const status = $('exportStatus');
    status.textContent = 'building…';
    try {
      const res = /** @type {any} */ (window).TrackExport.exportTrack({
        buffers: engine.buffers,
        title: $('trackTitle').value.trim(),
        crop: { start: crop.start, duration: cropLen() },
        settings: settingsSnapshot(),
        engineParams: {
          sensitivity: engine.sensitivity,
          attack: engine.attack,
          decay: engine.decay,
          noiseGate: engine.noiseGate,
          noteOnThresh: engine.noteOnThresh,
          noteOffThresh: engine.noteOffThresh,
          maxPolyphony: engine.maxPolyphony,
        },
      });
      status.textContent = res.zipName + ' · ' + (res.fileCount - 1) + ' stems + manifest';
    } catch (err) {
      console.error('[dancing-points] export failed', err);
      status.textContent = 'export failed: ' + (err && /** @type {any} */ (err).message);
    }
  });

  // ---------- haptics toggle (xene) ----------
  const hapticBtn = $('haptics');
  function syncHapticUi() {
    hapticBtn.classList.toggle('active', hapticsOn);
    $('hapticLabel').textContent = hapticsOn ? 'Haptics: ON' : 'Haptics: OFF';
  }
  if (!('vibrate' in navigator) && !hapticBridge) {
    hapticsOn = false;
    $('hapticMeta').textContent = 'unsupported here';
  } else if (hapticBridge) {
    $('hapticMeta').textContent = 'native';
  }
  syncHapticUi();
  hapticBtn.addEventListener('click', () => {
    if (!('vibrate' in navigator) && !hapticBridge) return;
    hapticsOn = !hapticsOn;
    syncHapticUi();
    if (hapticsOn) fireHaptic(0.3);
  });

  // ---------- panel toggle ----------
  $('toggle').addEventListener('click', () => {
    const p = $('panel');
    p.classList.toggle('hidden');
    $('toggle').textContent = p.classList.contains('hidden') ? 'Show' : 'Hide';
  });
  if (window.matchMedia('(max-width: 720px)').matches) {
    $('panel').classList.add('hidden');
    $('toggle').textContent = 'Show';
  }

  // ---------- persistence ----------
  function persist() {
    const save = {
      source: state.source, mode: state.mode, color: state.color, warp: state.warp,
      density: state.density, size: state.size, rot: state.rot,
      sens: engine.sensitivity, atk: engine.attack, dec: engine.decay,
    };
    localStorage.setItem(LS, JSON.stringify(save));
  }
  // Push current state + engine tunables into engine, scene, and every control.
  // Shared by localStorage restore and playlist track settings.
  function applyState() {
    engine.setSource(state.source);
    scene.setMode(state.mode);
    scene.setColors(COLORS[state.color].base, COLORS[state.color].hot);
    scene.setWarp(state.warp);
    scene.setSize(state.size);
    scene.setRotation(state.rot);
    scene.regen(state.density);

    [...bandsEl.children].forEach((c) => c.classList.toggle('active', c.dataset.key === state.source));
    [...modesEl.children].forEach((c, j) => c.classList.toggle('active', j === state.mode));
    [...swEl.children].forEach((c, j) => c.classList.toggle('active', j === state.color));
    $('vCol').textContent = COLORS[state.color].name;
    $('sens').value = engine.sensitivity * 100; $('vSens').textContent = engine.sensitivity.toFixed(2) + '×';
    $('atk').value = engine.attack * 100; $('vAtk').textContent = engine.attack.toFixed(2);
    $('rel').value = Math.round((engine.decay - 0.80) / 0.19 * 100); $('vRel').textContent = engine.decay.toFixed(2);
    $('warp').value = state.warp * 100; $('vWarp').textContent = state.warp.toFixed(2);
    $('dens').value = state.density; $('vDens').textContent = String(state.density);
    $('size').value = state.size * 100; $('vSize').textContent = state.size.toFixed(2);
    $('rot').value = (state.rot / 0.5) * 100; $('vRot').textContent = state.rot.toFixed(2);
  }

  function restore() {
    let s; try { s = JSON.parse(localStorage.getItem(LS) || 'null'); } catch (e) { s = null; }
    if (!s) { selectSource(state.source); return; }
    state.source = SOURCES[s.source] ? s.source : 'vocals';
    state.mode = s.mode || 0;
    state.color = s.color || 0;
    state.warp = s.warp ?? 0.8;
    state.density = s.density || 6000;
    state.size = s.size ?? 0.7;
    state.rot = s.rot ?? 0.18;
    engine.sensitivity = s.sens ?? 1.6;
    engine.attack = s.atk ?? 0.6;
    engine.decay = s.dec ?? 0.90;
    applyState();
  }
  restore();
  onStemsChanged(); // initial: nothing loaded → sources dimmed, play disabled

  // ---------- playlist (saved AV tracks from Supabase) ----------
  // playlist.js renders the floating panel; we hand it the hooks it needs.
  // Track settings arrive in the nested track.json shape (settingsSnapshot).
  /** @param {any} settings */
  function applyTrackSettings(settings) {
    if (!settings) return;
    const eng = settings.engine || {};
    const look = settings.look || {};
    if (typeof eng.sensitivity === 'number') engine.sensitivity = eng.sensitivity;
    if (typeof eng.attack === 'number') engine.attack = eng.attack;
    if (typeof eng.decay === 'number') engine.decay = eng.decay;
    if (typeof eng.source === 'string' && SOURCES[eng.source]) state.source = eng.source;
    if (typeof look.mode === 'number' && MODES[look.mode]) state.mode = look.mode;
    if (typeof look.color === 'number' && COLORS[look.color]) state.color = look.color;
    if (typeof look.warp === 'number') state.warp = look.warp;
    if (typeof look.density === 'number') state.density = look.density;
    if (typeof look.size === 'number') state.size = look.size;
    if (typeof look.rot === 'number') state.rot = look.rot;
    applyState();
  }

  const playlistApi = /** @type {any} */ (window).XenePlaylist;
  if (playlistApi) {
    playlistApi.init({
      engine,
      applySettings: applyTrackSettings,
      onTrackLoaded: (/** @type {any} */ track, /** @type {string[]} */ loadedSlots) => {
        SLOTS.forEach((s) => {
          const el = $('slf-' + s.key);
          const has = loadedSlots.includes(s.key);
          if (el) el.textContent = has ? (track.title || 'playlist') : '— empty —';
          if (slotEls[s.key]) slotEls[s.key].classList.toggle('filled', has);
        });
        onStemsChanged();
      },
    });
  }

  // ---------- render loop ----------
  const mLevel = $('mLevel'), mReact = $('mReact');
  const dbg = $('dbg');
  // DEV HUD: which stems are loaded + each stem's live react (0-100). Lets us
  // confirm the drums stem is actually producing signal without flipping the
  // Reactive Source selector. `peak` monitoring drum → is signal flowing at all?
  const dbgOrder = [['vocals', 'VOC'], ['drums', 'DRM'], ['bass', 'BAS'], ['other', 'MEL'], ['full', 'MIX']];
  /** @param {number} v */
  const bar10 = (v) => '█'.repeat(Math.round(Math.min(1, v) * 10)).padEnd(10, '·');
  const glCanvas = $('gl');
  function updateDbg() {
    if (!dbg) return;
    const loaded = engine.loadedKeys.join(' ') || 'none';
    const lines = dbgOrder.map(([key, tag]) => {
      const s = engine.signals[key] || {};
      const r = s.react || 0;
      return `${tag} ${bar10(r)} ${(r * 100).toFixed(0).padStart(3)}`;
    });
    // live layout scale (mirrors scene.js resize()): tells us exactly what the
    // app is drawing the organism at — 0.72 (mobile) or 1.0 (desktop).
    const cw = (glCanvas && glCanvas.clientWidth) || window.innerWidth;
    const ch = (glCanvas && glCanvas.clientHeight) || window.innerHeight;
    const bodyScale = Math.min(cw, ch) < 640 ? 0.72 : 1.0;
    dbg.textContent = `SCALE ${bodyScale.toFixed(2)}  canvas ${cw}x${ch}\nstems: ${loaded}\n${lines.join('\n')}`;
  }

  let last = performance.now();

  /** @param {number} now */
  function tick(now) {
    const dt = Math.min(0.05, (now - last) / 1000) || 0.016;
    last = now;

    engine.update();
    const playing = engine.isPlaying;
    scene.setIdle(playing ? 0 : 1);
    // vocals always drive the brain-dot trail (their own asset), via the isolated
    // vocals stem analyser — independent of the selected reactive source.
    scene.update(dt, engine.react, engine.reactSlow, engine.signals, engine.keyEnergies, engine.stemAnalyser && engine.stemAnalyser.vocals);

    // transport position UI (full-length, no cap)
    if (engine.hasStems && !scrubbing) {
      const cur = engine.currentTime;
      const denom = capDuration() || 1;
      scrub.value = String(Math.min(1000, (cur / denom) * 1000));
      $('cur').textContent = fmtTime(cur);
    }

    // crop preview loop: hold playback inside the save window
    if (crop.loop && playing && engine.currentTime >= cropEnd() - 0.03) {
      engine.seek(crop.start);
    }

    // Drums-only haptic onset. This tracks the same raw drums.react that drives
    // the center wire/noise ball in scene.js.
    const drive = (engine.signals.drums && engine.signals.drums.react) || 0;
    const rising = drive - hapticGate.prev;
    const enoughGap = now - hapticGate.lastMs >= HAPTIC_MIN_GAP_MS;
    if (playing && hapticGate.armed && enoughGap &&
        drive > HAPTIC_ON_THRESHOLD && rising > HAPTIC_ATTACK_DELTA) {
      hapticGate.lastMs = now;
      hapticGate.armed = false;
      if (hapticsOn) fireHaptic(Math.min(1, Math.max(0.35, drive)));
    } else if (drive < HAPTIC_OFF_THRESHOLD || !playing) {
      hapticGate.armed = true;
    }
    hapticGate.prev = drive;

    // meters
    mLevel.style.width = Math.min(100, (engine.level / (engine.peak + 1e-5)) * 100) + '%';
    mReact.style.width = Math.min(100, engine.react * 100) + '%';

    updateDbg();
  }

  // Drive with requestAnimationFrame, fall back to a timer if RAF stalls
  // (some embedded/backgrounded iframes throttle RAF to zero).
  let rafCount = 0;
  const nativeHost = !!(window.XeneDiagnostics || window.XeneHaptics);
  const frameMinMs = nativeHost && localStorage.getItem('dancingPoints.fullPower') !== '1'
    ? 33
    : 0;
  let lastFrame = 0;
  /** @param {number} now */
  function rafLoop(now) {
    if (frameMinMs && now - lastFrame < frameMinMs) {
      requestAnimationFrame(rafLoop);
      return;
    }
    lastFrame = now;
    rafCount++;
    tick(now);
    requestAnimationFrame(rafLoop);
  }
  requestAnimationFrame(rafLoop);

  tick(performance.now()); // immediate first paint

  setTimeout(() => {
    if (rafCount < 2) setInterval(() => tick(performance.now()), 16);
  }, 250);
})();
