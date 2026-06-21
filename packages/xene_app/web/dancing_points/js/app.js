// Wires UI -> AudioEngine -> Scene. Runs the render loop.
(function () {
  'use strict';

  const $ = (id) => document.getElementById(id);
  const LS = 'dancingPoints.v1';

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

  // ---- log frequency mapping for edge sliders (0..1000 -> 20..20000 Hz) ----
  const sliderToHz = (s) => Math.round(20 * Math.pow(1000, s / 1000));
  const hzToSlider = (hz) => Math.round(1000 * Math.log(hz / 20) / Math.log(1000));
  const fmtHz = (hz) => hz >= 1000 ? (hz / 1000).toFixed(hz >= 10000 ? 0 : 1) + 'k' : hz + ' Hz';
  const fmtTime = (s) => {
    if (!isFinite(s)) s = 0;
    const m = Math.floor(s / 60), ss = Math.floor(s % 60);
    return m + ':' + String(ss).padStart(2, '0');
  };

  const audioEl = $('audio');
  const engine = new AudioEngine(audioEl);
  const scene = createScene($('gl'));

  // ---- xene additions: short-clip cap + haptics (the accessibility core) ----
  const CLIP_SECONDS = 30;        // cap uploaded-clip playback (modest, in-session)
  let clipCap = true;             // only uploads are capped; SC sources (later) won't be
  let hapticsOn = 'vibrate' in navigator;
  let prevReactForHaptic = 0;     // for rising-edge beat detection
  const HAPTIC_THRESHOLD = 0.45;  // react level that counts as a "hit"

  const state = {
    band: 'kick',
    mode: 0,
    color: 0,
    warp: 0.8,
    density: 6000,
    size: 0.7,
    rot: 0.18,
  };

  // ---------- build band buttons ----------
  const bandsEl = $('bands');
  Object.entries(window.BANDS).forEach(([key, b]) => {
    const el = document.createElement('button');
    el.className = 'band' + (key === state.band ? ' active' : '');
    el.dataset.key = key;
    const short = b.label.split(' / ')[0];
    el.innerHTML = `<div class="bn">${short}</div><div class="bf">${b.label.includes('/') ? b.label.split(' / ')[1] : ''}</div>`;
    el.addEventListener('click', () => selectBand(key));
    bandsEl.appendChild(el);
  });

  function selectBand(key) {
    state.band = key;
    engine.setBand(key);
    [...bandsEl.children].forEach(c => c.classList.toggle('active', c.dataset.key === key));
    // sync edge sliders to the band preset
    $('lo').value = hzToSlider(engine.lo);
    $('hi').value = hzToSlider(engine.hi);
    updateEdgeLabels();
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

  // ---------- isolation edges ----------
  function updateEdgeLabels() {
    $('vLo').textContent = fmtHz(engine.lo);
    $('vHi').textContent = fmtHz(engine.hi);
    $('bandHz').textContent = `${fmtHz(engine.lo)} – ${fmtHz(engine.hi)}`;
  }
  $('lo').addEventListener('input', (e) => {
    const lo = sliderToHz(+e.target.value);
    engine.setEdges(lo, engine.hi);
    $('lo').value = hzToSlider(engine.lo);
    updateEdgeLabels(); persist();
  });
  $('hi').addEventListener('input', (e) => {
    const hi = sliderToHz(+e.target.value);
    engine.setEdges(engine.lo, hi);
    $('hi').value = hzToSlider(engine.hi);
    updateEdgeLabels(); persist();
  });

  // ---------- reaction controls ----------
  $('sens').addEventListener('input', (e) => {
    engine.sensitivity = +e.target.value / 100;
    $('vSens').textContent = engine.sensitivity.toFixed(2) + '×';
    persist();
  });
  $('atk').addEventListener('input', (e) => {
    engine.attack = +e.target.value / 100;
    $('vAtk').textContent = engine.attack.toFixed(2);
    persist();
  });
  $('rel').addEventListener('input', (e) => {
    engine.decay = 0.80 + (+e.target.value / 100) * 0.19; // 0.80..0.99
    $('vRel').textContent = engine.decay.toFixed(2);
    persist();
  });
  $('warp').addEventListener('input', (e) => {
    state.warp = +e.target.value / 100;
    scene.setWarp(state.warp);
    $('vWarp').textContent = state.warp.toFixed(2);
    persist();
  });

  // ---------- form controls ----------
  let densTimer = null;
  $('dens').addEventListener('input', (e) => {
    state.density = +e.target.value;
    $('vDens').textContent = state.density;
    clearTimeout(densTimer);
    densTimer = setTimeout(() => { scene.regen(state.density); }, 120);
    persist();
  });
  $('size').addEventListener('input', (e) => {
    state.size = +e.target.value / 100;
    scene.setSize(state.size);
    $('vSize').textContent = state.size.toFixed(2);
    persist();
  });
  $('rot').addEventListener('input', (e) => {
    state.rot = (+e.target.value / 100) * 0.5;
    scene.setRotation(state.rot);
    $('vRot').textContent = state.rot.toFixed(2);
    persist();
  });

  // ---------- file upload ----------
  const drop = $('drop');
  const fileInput = $('file');
  drop.addEventListener('click', () => fileInput.click());
  fileInput.addEventListener('change', (e) => { if (e.target.files[0]) loadFile(e.target.files[0]); });
  ['dragover', 'dragenter'].forEach(ev => drop.addEventListener(ev, (e) => { e.preventDefault(); drop.classList.add('drag'); }));
  ['dragleave', 'drop'].forEach(ev => drop.addEventListener(ev, (e) => { e.preventDefault(); drop.classList.remove('drag'); }));
  drop.addEventListener('drop', (e) => {
    const f = e.dataTransfer.files[0];
    if (f && f.type.startsWith('audio')) loadFile(f);
  });

  function loadFile(file) {
    const url = URL.createObjectURL(file);
    audioEl.src = url;
    $('fname').textContent = file.name;
    $('status').textContent = 'loaded';
    $('play').disabled = false;
    localStorage.removeItem(LS + '.time');
  }

  // ---------- transport ----------
  const playBtn = $('play');
  const playIco = $('playIco');
  const scrub = $('scrub');
  let scrubbing = false;

  playBtn.addEventListener('click', () => {
    engine.init();
    if (engine.ctx && engine.ctx.state === 'suspended') engine.ctx.resume();
    if (audioEl.paused) audioEl.play(); else audioEl.pause();
  });
  audioEl.addEventListener('play', () => { playIco.innerHTML = '<path d="M6 5h4v14H6zM14 5h4v14h-4z"/>'; });
  audioEl.addEventListener('pause', () => { playIco.innerHTML = '<path d="M8 5v14l11-7z"/>'; });
  audioEl.addEventListener('loadedmetadata', () => {
    $('dur').textContent = fmtTime(audioEl.duration);
    const t = parseFloat(localStorage.getItem(LS + '.time'));
    if (!isNaN(t) && t < audioEl.duration) audioEl.currentTime = t;
  });
  audioEl.addEventListener('timeupdate', () => {
    // xene: cap the in-session upload clip at CLIP_SECONDS (modest, no storage).
    if (clipCap && audioEl.currentTime >= CLIP_SECONDS) {
      audioEl.pause();
      audioEl.currentTime = 0;
      return;
    }
    if (!scrubbing && audioEl.duration) {
      const denom = clipCap ? Math.min(audioEl.duration, CLIP_SECONDS) : audioEl.duration;
      scrub.value = (audioEl.currentTime / denom) * 1000;
      $('cur').textContent = fmtTime(audioEl.currentTime);
      localStorage.setItem(LS + '.time', audioEl.currentTime);
    }
  });
  scrub.addEventListener('input', () => { scrubbing = true; $('cur').textContent = fmtTime((scrub.value / 1000) * (audioEl.duration || 0)); });
  scrub.addEventListener('change', () => { if (audioEl.duration) audioEl.currentTime = (scrub.value / 1000) * audioEl.duration; scrubbing = false; });

  // ---------- haptics toggle (xene) ----------
  const hapticBtn = $('haptics');
  function syncHapticUi() {
    hapticBtn.classList.toggle('active', hapticsOn);
    $('hapticLabel').textContent = hapticsOn ? 'Haptics: ON' : 'Haptics: OFF';
  }
  if (!('vibrate' in navigator)) {
    // iOS Safari and desktops without vibration hardware: disable + label it.
    hapticsOn = false;
    $('hapticMeta').textContent = 'unsupported here';
  }
  syncHapticUi();
  hapticBtn.addEventListener('click', () => {
    if (!('vibrate' in navigator)) return;
    hapticsOn = !hapticsOn;
    syncHapticUi();
    if (hapticsOn) navigator.vibrate(15); // confirmation buzz
  });

  // ---------- panel toggle ----------
  $('toggle').addEventListener('click', () => {
    const p = $('panel');
    p.classList.toggle('hidden');
    $('toggle').textContent = p.classList.contains('hidden') ? 'Show' : 'Hide';
  });

  // ---------- persistence ----------
  function persist() {
    const save = {
      band: state.band, mode: state.mode, color: state.color, warp: state.warp,
      density: state.density, size: state.size, rot: state.rot,
      lo: engine.lo, hi: engine.hi,
      sens: engine.sensitivity, atk: engine.attack, dec: engine.decay,
    };
    localStorage.setItem(LS, JSON.stringify(save));
  }
  function restore() {
    let s; try { s = JSON.parse(localStorage.getItem(LS)); } catch (e) { s = null; }
    if (!s) { selectBand(state.band); updateEdgeLabels(); return; }
    state.band = s.band || 'kick';
    state.mode = s.mode || 0;
    state.color = s.color || 0;
    state.warp = s.warp ?? 0.8;
    state.density = s.density || 6000;
    state.size = s.size ?? 0.7;
    state.rot = s.rot ?? 0.18;
    engine.sensitivity = s.sens ?? 1.6;
    engine.attack = s.atk ?? 0.6;
    engine.decay = s.dec ?? 0.90;

    // apply to engine + scene
    engine.setBand(state.band);
    if (s.lo && s.hi) engine.setEdges(s.lo, s.hi);
    scene.setMode(state.mode);
    scene.setColors(COLORS[state.color].base, COLORS[state.color].hot);
    scene.setWarp(state.warp);
    scene.setSize(state.size);
    scene.setRotation(state.rot);
    scene.regen(state.density);

    // sync UI
    [...bandsEl.children].forEach(c => c.classList.toggle('active', c.dataset.key === state.band));
    [...modesEl.children].forEach((c, j) => c.classList.toggle('active', j === state.mode));
    [...swEl.children].forEach((c, j) => c.classList.toggle('active', j === state.color));
    $('vCol').textContent = COLORS[state.color].name;
    $('lo').value = hzToSlider(engine.lo);
    $('hi').value = hzToSlider(engine.hi);
    $('sens').value = engine.sensitivity * 100; $('vSens').textContent = engine.sensitivity.toFixed(2) + '×';
    $('atk').value = engine.attack * 100; $('vAtk').textContent = engine.attack.toFixed(2);
    $('rel').value = Math.round((engine.decay - 0.80) / 0.19 * 100); $('vRel').textContent = engine.decay.toFixed(2);
    $('warp').value = state.warp * 100; $('vWarp').textContent = state.warp.toFixed(2);
    $('dens').value = state.density; $('vDens').textContent = state.density;
    $('size').value = state.size * 100; $('vSize').textContent = state.size.toFixed(2);
    $('rot').value = (state.rot / 0.5) * 100; $('vRot').textContent = state.rot.toFixed(2);
    updateEdgeLabels();
  }
  restore();

  // ---------- render loop ----------
  const mLevel = $('mLevel'), mReact = $('mReact');
  let last = performance.now();

  function tick(now) {
    const dt = Math.min(0.05, (now - last) / 1000) || 0.016;
    last = now;

    engine.update();
    const playing = !audioEl.paused && !audioEl.ended;
    scene.setIdle(playing ? 0 : 1);
    scene.update(dt, engine.react, engine.reactSlow);

    // xene: fire a haptic pulse on each RISING beat in the isolated band.
    // The band-isolated transient IS the beat, so this maps the same signal
    // that warps the sphere onto touch — the accessibility payload.
    if (hapticsOn && playing && navigator.vibrate) {
      if (engine.react > HAPTIC_THRESHOLD && prevReactForHaptic <= HAPTIC_THRESHOLD) {
        navigator.vibrate(Math.round(8 + Math.min(1, engine.react) * 32)); // 8–40ms
      }
    }
    prevReactForHaptic = engine.react;

    // meters
    mLevel.style.width = Math.min(100, (engine.level / (engine.peak + 1e-5)) * 100) + '%';
    mReact.style.width = Math.min(100, engine.react * 100) + '%';
  }

  // Drive with requestAnimationFrame, but fall back to a timer if RAF stalls
  // (some embedded/backgrounded iframes throttle RAF to zero).
  let rafCount = 0;
  function rafLoop(now) { rafCount++; tick(now); requestAnimationFrame(rafLoop); }
  requestAnimationFrame(rafLoop);

  tick(performance.now()); // immediate first paint

  setTimeout(() => {
    if (rafCount < 2) {
      // RAF isn't ticking — run on an interval instead.
      setInterval(() => tick(performance.now()), 16);
    }
  }, 250);
})();
