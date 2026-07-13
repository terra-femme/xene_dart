// Resonance organism scene. A wireframe center body sits inside a reactive
// neural brain frame and low-poly instrument cage.

function createScene(canvas) {
  const renderer = new THREE.WebGLRenderer({ canvas, antialias: true, alpha: false });
  renderer.setClearColor(0x050509, 1);
  renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 1.5));

  const scene = new THREE.Scene();
  const camera = new THREE.PerspectiveCamera(42, 1, 0.1, 100);
  camera.position.set(0, 0.1, 5.2);

  const uniforms = {
    uTime: { value: 0 },
    uBass: { value: 0 },
    uDrums: { value: 0 },
    uVocals: { value: 0 },
    uMelody: { value: 0 },
    uWarp: { value: 0.8 },
    uSize: { value: 0.46 },
    uIdle: { value: 1 },
    uMode: { value: 0 },
    uColor: { value: new THREE.Color('#dbefff') },
    uColorHot: { value: new THREE.Color('#ffffff') },
    uColor1: { value: new THREE.Color('#9fb7c8') },
    uColor2: { value: new THREE.Color('#dbefff') },
    uColor3: { value: new THREE.Color('#ffffff') },
  };

  const brain = buildBrainReferenceBrain();
  scene.add(brain.group);

  const otherRegions = buildBrainOtherRegions();
  brain.mesh.add(otherRegions.mesh);

  // ── BASS asset: pulse waves expanding outward from the "other" perimeter ──
  // Each bass onset fires one GPU-expanded ring (see buildBrainBassWaves).
  const bassWaves = buildBrainBassWaves();
  brain.mesh.add(bassWaves.mesh);

  // Center noise-ball (drums drive it). Luminous white — the reference used
  // 0x000000 which is invisible on the 0x050509 void, so we override to a
  // bright cool-white so it reads inside the brain's central void.
  const blob = buildWireframeBlob({
    color: 0xeaf4ff, radius: 0.44, strokeCount: 23, pointsPerStroke: 131, step: 0.08,
    wander: 0.30, centerPull: 3.20, startSpread: 0.38, opacity: 0.43, size: 0.25,
    aspectX: 1.36, aspectY: 0.98, // oblong: threads reach wider than tall to fill the void
  });
  blob.group.position.set(0.06, 0.09, 0.08); // seated in the brain void
  scene.add(blob.group);

  // ── VOCALS asset: brain node-dots trail + waveform streamers ──────────────
  // Parented to the brain MESH so they stay locked to the baked dots as the brain
  // breathes. Driven by the isolated vocals stem (pitch + waveform), independent of
  // the reactive-source selector — vocals always own the dots. Tuned values from
  // tools/av_debug/brain-vocals-trail.html.
  const vocalDots = buildBrainDots();
  brain.mesh.add(vocalDots.points);
  const vDotPos = vocalDots.geo.attributes.position.array;
  const vBbox = computeDotBounds(vDotPos, vocalDots.count);
  const vStream = buildBrainStreamers(vocalDots, vDotPos, vBbox, 28);
  brain.mesh.add(vStream.points);
  brain.material.uniforms.uDim.value = 0.31; // dim the baked white nodes so the amber dots read
  const VOCAL_TUNE = {
    radius: 0.66, fade: 0.87, wind: 1.15, roam: 0.55, turb: 0.70, pull: 0.90,
    streamOn: true, streamLen: 1.50, waveAmp: 0.24, smooth: 0.77, sway: 0.11,
    streamWind: 0.62, streamSize: 0.048, streamBright: 2.31,
    baseDim: 0.00, vocalBright: 2.90, vocalSize: 0.83, twinkle: 0.51, twinkleSpeed: 15.0,
    tint: [1.00, 0.56, 0.20],
  };
  const vTrail = { lastPy: vBbox.cy };
  const vPitchState = { td: null, levPeak: 0.02, frame: 0, last: null };
  const vWaveState = { wtd: null };
  let smoothDt = 0.016; // EMA of frame time → adaptive throttle (back off only when FPS drops)
  let frameNo = 0;      // frame counter for the heavy-loop gating (ball verts, streamers)
  console.log('[scene] vocals layer built: ' + vocalDots.count + ' dots, ' + (vStream.count * vStream.L) + ' streamer points');

  let rotSpeed = 0.1;
  let targetTiltX = 0;
  let targetTiltY = 0;
  let tiltX = 0;
  let tiltY = 0;

  window.addEventListener('pointermove', (e) => {
    const nx = (e.clientX / window.innerWidth) * 2 - 1;
    const ny = (e.clientY / window.innerHeight) * 2 - 1;
    targetTiltY = nx * 0.18;
    targetTiltX = ny * 0.12;
  });

  function resize() {
    const w = canvas.clientWidth || window.innerWidth;
    const h = canvas.clientHeight || window.innerHeight;
    renderer.setSize(w, h, false);
    camera.aspect = w / h;
    camera.updateProjectionMatrix();

    const mobile = Math.min(w, h) < 640;
    const bodyScale = mobile ? 0.72 : 1.0;
    brain.layoutScale = bodyScale;
    blob.layoutScale = bodyScale;
  }
  window.addEventListener('resize', resize);
  window.addEventListener('load', resize);
  resize();
  requestAnimationFrame(resize);

  /**
   * @param {any} signals
   * @param {number} fallbackReact
   * @param {number} fallbackSlow
   */
  function readSignals(signals, fallbackReact, fallbackSlow) {
    const s = signals || {};
    const bass = s.bass || {};
    const drums = s.drums || {};
    const vocals = s.vocals || {};
    const other = s.other || {};
    const full = s.full || {};
    return {
      bass: clamp01(Math.max(bass.reactSlow || 0, (bass.react || 0) * 0.7)),
      drums: clamp01(drums.react || 0),
      vocals: clamp01(Math.max(vocals.reactSlow || 0, (vocals.react || 0) * 0.8)),
      melody: clamp01(Math.max(other.reactSlow || 0, (other.react || 0) * 0.8)),
      full: clamp01(Math.max(full.reactSlow || fallbackSlow || 0, fallbackReact || 0)),
    };
  }

  function update(dt, react, reactSlow, signals, keyEnergies, vocalAnalyser) {
    uniforms.uTime.value += dt;
    const sig = readSignals(signals, react, reactSlow);
    uniforms.uBass.value += (sig.bass - uniforms.uBass.value) * 0.16;
    uniforms.uDrums.value += (sig.drums - uniforms.uDrums.value) * 0.34;
    uniforms.uVocals.value += (sig.vocals - uniforms.uVocals.value) * 0.14;
    uniforms.uMelody.value += (sig.melody - uniforms.uMelody.value) * 0.12;

    tiltX += (targetTiltX - tiltX) * 0.04;
    tiltY += (targetTiltY - tiltY) * 0.04;
    const t = uniforms.uTime.value;

    // ── Perf gating ─────────────────────────────────────────────────────────
    // The two legacy CPU loops (ball vertex-dance ~3k pts, vocal streamers ~2.5k pts)
    // are gated: IDLE (nothing playing) → every 3rd frame; FPS sagging → every 2nd.
    // Rotation/scale/envelopes still run every frame so nothing visibly stutters.
    smoothDt += (dt - smoothDt) * 0.05;
    const fps = 1 / smoothDt;
    frameNo++;
    const idle = uniforms.uIdle.value >= 0.5;
    const heavyEvery = idle ? 3 : fps < 45 ? 2 : 1;
    const doHeavy = (frameNo % heavyEvery) === 0;

    // The brain does NOT react to vocals or the melodic/"other" stem — their own assets carry
    // them (vocals → brain dots, melodic → perimeter regions). Asset isolation.
    // full is zeroed too: it's the WHOLE mix, so any melodic note would leak back
    // into the brain's breath through it. The brain body breathes on bass only.
    const brainSig = { bass: sig.bass, drums: sig.drums, vocals: 0, melody: 0, full: 0 };
    updateBrainFrame(brain, t, brainSig, tiltX, tiltY);
    updateBrainOtherRegions(otherRegions, keyEnergies);
    // waves fire on onsets of the RAW bass react (percussive edge), not the
    // smoothed readSignals mix — smoothing would blur the rising edge away.
    updateBrainBassWaves(bassWaves, t, (signals && signals.bass && signals.bass.react) || 0);
    updateWireframeBlob(blob, t, dt, sig, rotSpeed, tiltX, tiltY, undefined, doHeavy);

    // VOCALS: pitch-steered dot trail + waveform streamers, from the vocals stem analyser.
    // The pitch detector is O(n²) autocorrelation — the heaviest per-frame CPU cost. Throttle it
    // ADAPTIVELY (full rate ≥55fps, ÷2 at 45–55, ÷3 below): pitch moves slowly and the trail
    // envelope smooths the gaps, so a struggling/overheating device backs off invisibly.
    const pitchEvery = fps < 45 ? 3 : fps < 55 ? 2 : 1;
    vPitchState.frame++;
    if (!vPitchState.last || (vPitchState.frame % pitchEvery) === 0) {
      vPitchState.last = readVocalInput(vocalAnalyser, vPitchState);
    }
    const vin = vPitchState.last;
    updateBrainTrail(vocalDots, vDotPos, vBbox, vin, t, VOCAL_TUNE, vTrail);
    if (doHeavy) {
      updateBrainStreamers(vStream, vocalDots, vDotPos, vin.level, VOCAL_TUNE, t, vocalAnalyser, vWaveState);
    }

    camera.position.x = tiltY * 0.6;
    camera.lookAt(0, -0.05, 0);
    renderer.render(scene, camera);
  }

  return {
    update,
    resize,
    regen: (density) => {
      brain.cageDensity = Math.max(0.55, Math.min(1.45, density / 6000));
    },
    setMode: (m) => { uniforms.uMode.value = m; },
    setWarp: (w) => { uniforms.uWarp.value = w; },
    setNoiseScale: (_n) => {},
    setSize: (s) => {
      uniforms.uSize.value = 0.34 + s * 0.22;
    },
    setIdle: (v) => { uniforms.uIdle.value = v; },
    setRotation: (r) => { rotSpeed = r * 0.7; },
    setColors: (base, hot) => {
      uniforms.uColor.value.set('#dbefff');
      uniforms.uColorHot.value.set('#ffffff');
      uniforms.uColor1.value.set('#9fb7c8');
      uniforms.uColor2.value.set('#dbefff');
      uniforms.uColor3.value.set('#ffffff');
      brain.setHot(hot);
    },
  };
}

function buildBlobHalo(count) {
  const geo = new THREE.BufferGeometry();
  const positions = new Float32Array(count * 3);
  const seeds = [];
  for (let i = 0; i < count; i++) {
    const theta = Math.random() * Math.PI * 2;
    const phi = Math.acos(2 * Math.random() - 1);
    const r = 1.86 + Math.random() * 1.15;
    positions[i * 3 + 0] = r * Math.sin(phi) * Math.cos(theta);
    positions[i * 3 + 1] = r * Math.sin(phi) * Math.sin(theta);
    positions[i * 3 + 2] = r * Math.cos(phi) * 0.72;
    seeds.push(Math.random() * 1000);
  }
  geo.setAttribute('position', new THREE.BufferAttribute(positions, 3));
  const mat = new THREE.PointsMaterial({
    size: 0.026,
    color: 0xffffff,
    transparent: true,
    opacity: 0.46,
    depthWrite: false,
    depthTest: false,
    sizeAttenuation: true,
    blending: THREE.AdditiveBlending,
  });
  const points = new THREE.Points(geo, mat);
  points.frustumCulled = false;
  points.renderOrder = 4;
  return { points, geo, seeds, count };
}

// ── "Other"/melodic stem: brain-perimeter network regions ────────────────────
// Irregular triangles filling the "yellow" band around the brain (outside the
// brain no-zone), generated by tools/av_debug/bandtri.py → js/brain-other-data.js
// (window.BRAIN_OTHER_REGIONS = {nodes:[[x,y]..], tris:[[i,j,k,key]..]}, image space).
// Each triangle is assigned a piano key; the melodic stem's per-key spectrum
// (keyEnergies) lights it. Replaces the old synthetic 88-wedge ring. Parented to
// the brain MESH so it locks to the brain image (same mapping as the vocal dots).
function buildBrainOtherRegions(opts) {
  opts = opts || {};
  const planeW = opts.planeW ?? 3.35, planeH = opts.planeH ?? 2.23, z = opts.z ?? 0.015;
  const data = (typeof window !== 'undefined' ? window.BRAIN_OTHER_REGIONS : null) || { nodes: [], tris: [] };
  const nodes = data.nodes || [], tris = data.tris || [], T = tris.length;
  const positions = new Float32Array(T * 9);
  const colors = new Float32Array(T * 9);
  const keys = new Int16Array(T);
  // ONE dedicated region per key: the data has more triangles than keys (105 vs
  // 88), so some keys own two — sometimes disjoint patches. Keep only the
  // largest triangle per key; the rest get key -1 and never light.
  const bestByKey = new Map();
  for (let i = 0; i < T; i++) {
    const tr = tris[i];
    const a = nodes[tr[0]] || [0, 0], b = nodes[tr[1]] || [0, 0], c = nodes[tr[2]] || [0, 0];
    const area = Math.abs((b[0] - a[0]) * (c[1] - a[1]) - (c[0] - a[0]) * (b[1] - a[1]));
    const best = bestByKey.get(tr[3]);
    if (!best || area > best.area) bestByKey.set(tr[3], { i, area });
  }
  for (let i = 0; i < T; i++) {
    const tr = tris[i];
    keys[i] = bestByKey.get(tr[3]).i === i ? tr[3] : -1;
    for (let j = 0; j < 3; j++) {
      const nd = nodes[tr[j]] || [0.5, 0.5];
      const vi = (i * 3 + j) * 3;
      positions[vi]     = (nd[0] - 0.5) * planeW;   // image x  → plane-local x
      positions[vi + 1] = (0.5 - nd[1]) * planeH;   // image y↓ → plane-local y↑
      positions[vi + 2] = z;
    }
  }
  const geo = new THREE.BufferGeometry();
  geo.setAttribute('position', new THREE.BufferAttribute(positions, 3));
  geo.setAttribute('color', new THREE.BufferAttribute(colors, 3));
  const mat = new THREE.MeshBasicMaterial({
    vertexColors: true, transparent: true, side: THREE.DoubleSide,
    depthWrite: false, depthTest: false, blending: THREE.AdditiveBlending,
  });
  const mesh = new THREE.Mesh(geo, mat);
  mesh.frustumCulled = false;
  mesh.renderOrder = 22; // above the brain plane (20), below the vocal dots (25)
  return { mesh, geo, colors, keys, count: T };
}

// MELODIC stem lights each region by its key's energy; gamma makes the dominant pop.
// Optional `tune` overrides (same pattern as updateWireframeBlob) let the isolation lab
// (tools/av_debug/brain-other.html) dial the look live; defaults = the app's baked values.
function updateBrainOtherRegions(reg, keyEnergies, tune) {
  if (!reg || !reg.count) return;
  const T = tune || {};
  const gamma  = T.gamma  ?? 0.88;
  const bright = T.bright ?? 1.25;
  const cold   = T.cold || [0.12, 0.42, 0.78];   // color at the lit floor …
  const hot    = T.hot  || [0.53, 0.74, 1.00];   // … blending to this at full energy
  // (baked from the user's brain-other.html readout 2026-07-12: hue/sat 213/0.85)
  const colors = reg.colors, keys = reg.keys;
  for (let i = 0; i < reg.count; i++) {
    const e = keyEnergies && keys[i] >= 0 ? keyEnergies[keys[i]] : 0;
    const lit = Math.pow(e < 0 ? 0 : e > 1 ? 1 : e, gamma);
    const b = lit * bright;                                // additive → color IS the emitted light (0 = invisible)
    const r = (cold[0] + lit * (hot[0] - cold[0])) * b;
    const g = (cold[1] + lit * (hot[1] - cold[1])) * b;
    const bl = (cold[2] + lit * (hot[2] - cold[2])) * b;
    for (let j = 0; j < 3; j++) {
      const vi = (i * 3 + j) * 3;
      colors[vi] = r; colors[vi + 1] = g; colors[vi + 2] = bl;
    }
  }
  reg.geo.attributes.color.needsUpdate = true;
}

// ── BASS stem: pulse waves expanding outward from the "other" perimeter ──────
// A pool of W ring RIBBONS sharing ONE vertex shader: each bass onset stamps a
// spawn time onto the next ring in the pool, and the GPU slides that ribbon
// radially by (uTime - aSpawn) * speed. Per-frame CPU cost ≈ setting one
// uniform, so it stays cheap on mobile. The emit loop is the convex hull of the
// baked "other" region nodes (js/brain-other-data.js) — the waves visually
// radiate from the melodic perimeter band. Prototyped in
// tools/av_debug/brain-bass-waves.html, which drives these same functions.
function buildBrainBassWaves(opts) {
  opts = opts || {};
  const planeW = opts.planeW ?? 3.35, planeH = opts.planeH ?? 2.23, z = opts.z ?? 0.02;
  // P = segments around the loop. Each ring is a solid RIBBON (see below),
  // so P only controls curve smoothness — 512 is plenty for a convex hull.
  // W = 12 concurrent rings: life 1.2s / minGap 0.12s ≈ 10 alive at once.
  const W = opts.rings ?? 12, P = opts.segments ?? 512;
  const data = (typeof window !== 'undefined' ? window.BRAIN_OTHER_REGIONS : null) || { nodes: [] };
  const planeNodes = (data.nodes || []).map((nd) => [(nd[0] - 0.5) * planeW, (0.5 - nd[1]) * planeH]);

  // convex hull (monotone chain) → even resample into a P-point loop
  function convexHull(ptsIn) {
    const pts = ptsIn.slice().sort((a, b) => a[0] - b[0] || a[1] - b[1]);
    const cross = (o, a, b) => (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0]);
    const lo = []; for (const p of pts) { while (lo.length >= 2 && cross(lo[lo.length - 2], lo[lo.length - 1], p) <= 0) lo.pop(); lo.push(p); }
    const up = []; for (let i = pts.length - 1; i >= 0; i--) { const p = pts[i]; while (up.length >= 2 && cross(up[up.length - 2], up[up.length - 1], p) <= 0) up.pop(); up.push(p); }
    lo.pop(); up.pop(); return lo.concat(up);
  }
  function sampleLoop(hull, count) {
    const seg = []; let total = 0;
    for (let i = 0; i < hull.length; i++) { const a = hull[i], b = hull[(i + 1) % hull.length]; const L = Math.hypot(b[0] - a[0], b[1] - a[1]); seg.push({ a, b, L }); total += L; }
    const out = []; let acc = 0, si = 0; const step = total / count;
    for (let k = 0; k < count; k++) { const target = k * step; while (si < seg.length - 1 && acc + seg[si].L < target) { acc += seg[si].L; si++; } const t = seg[si].L ? (target - acc) / seg[si].L : 0; out.push([seg[si].a[0] + (seg[si].b[0] - seg[si].a[0]) * t, seg[si].a[1] + (seg[si].b[1] - seg[si].a[1]) * t]); }
    return out;
  }
  const hull = planeNodes.length >= 3 ? convexHull(planeNodes) : [[-1, -0.6], [1, -0.6], [1, 0.6], [-1, 0.6]];
  const loop = sampleLoop(hull, P);
  const cx = loop.reduce((s, p) => s + p[0], 0) / P, cy = loop.reduce((s, p) => s + p[1], 0) / P;

  // Each ring is a closed triangle-strip RIBBON: every loop point contributes
  // an inner and an outer vertex (aEdge ∓0.5), joined into quads around the
  // loop. The shader slides the whole ribbon outward — a solid continuous
  // stroke with hard edges and exact width (the crisp concentric-circles
  // look). Point sprites can't do this: they always read as dots or glow.
  const VPR = P * 2; // vertices per ring
  const N = W * VPR;
  const aBase = new Float32Array(N * 3), aDir = new Float32Array(N * 3), aEdge = new Float32Array(N), aSpawn = new Float32Array(N);
  const index = [];
  for (let w = 0; w < W; w++) {
    for (let i = 0; i < P; i++) {
      const p = loop[i];
      let dx = p[0] - cx, dy = p[1] - cy; const m = Math.hypot(dx, dy) || 1;
      for (let e = 0; e < 2; e++) {
        const idx = (w * P + i) * 2 + e;
        aBase[idx * 3] = p[0]; aBase[idx * 3 + 1] = p[1]; aBase[idx * 3 + 2] = z;
        aDir[idx * 3] = dx / m; aDir[idx * 3 + 1] = dy / m; aDir[idx * 3 + 2] = 0;
        aEdge[idx] = e === 0 ? -0.5 : 0.5;
        aSpawn[idx] = -999;
      }
      const a = (w * P + i) * 2, b = (w * P + ((i + 1) % P)) * 2;
      index.push(a, b, a + 1, a + 1, b, b + 1);
    }
  }
  const geo = new THREE.BufferGeometry();
  geo.setAttribute('position', new THREE.BufferAttribute(new Float32Array(N * 3), 3)); // unused; shader builds from aBase
  geo.setAttribute('aBase', new THREE.BufferAttribute(aBase, 3));
  geo.setAttribute('aDir', new THREE.BufferAttribute(aDir, 3));
  geo.setAttribute('aEdge', new THREE.BufferAttribute(aEdge, 1));
  geo.setAttribute('aSpawn', new THREE.BufferAttribute(aSpawn, 1).setUsage(THREE.DynamicDrawUsage));
  geo.setIndex(index);
  const mat = new THREE.ShaderMaterial({
    // NORMAL blending (not additive): the reference strokes are flat solid
    // color — born opaque, alpha-faded out. Additive would bloom to white.
    transparent: true, depthWrite: false, depthTest: false, side: THREE.DoubleSide,
    uniforms: { uTime: { value: 0 }, uSpeed: { value: 1.2 }, uLife: { value: 1.2 }, uThick: { value: 0.28 },
      uFade: { value: 1.8 }, uTail: { value: 2.2 },
      uColor: { value: new THREE.Color().setHSL(330 / 360, 0.85, 0.6) }, uBright: { value: 1.5 } },
    vertexShader: `
      attribute vec3 aBase; attribute vec3 aDir; attribute float aEdge; attribute float aSpawn;
      uniform float uTime, uSpeed, uLife, uThick, uFade;
      varying float vAlpha; varying float vEdge;
      void main() {
        float age = uTime - aSpawn;
        // 'alive', not 'active' — 'active' is a RESERVED word in GLSL ES 3.00,
        // which three.js auto-targets on WebGL2 (#version 300 es conversion)
        float alive = (aSpawn > 0.0 && age >= 0.0 && age <= uLife) ? 1.0 : 0.0;
        float lifeT = clamp(age / uLife, 0.0, 1.0);
        // dead rings collapse to zero-area triangles at the base loop
        vec3 pos = aBase + aDir * (age * uSpeed + aEdge * uThick) * alive;
        // born at FULL opacity, then a pow-curve fade-out: uFade > 1 holds
        // near-solid early and drops late; < 1 dims fast then lingers
        vAlpha = alive * pow(1.0 - lifeT, uFade);
        // 1.0 at the INNER edge (closest to the brain), 0.0 at the outer —
        // the band is opaque near the brain and dissolves as it reaches away
        vEdge = 0.5 - aEdge;
        gl_Position = projectionMatrix * modelViewMatrix * vec4(pos, 1.0);
      }`,
    fragmentShader: `
      precision mediump float; varying float vAlpha; varying float vEdge;
      uniform vec3 uColor; uniform float uBright, uTail;
      void main() {
        // comet band: opaque at the wavefront, gradient tail dissolving to
        // none behind it. uTail > 1 hugs the alpha to the front edge.
        gl_FragColor = vec4(uColor * uBright, vAlpha * pow(vEdge, uTail));
      }`,
  });
  const mesh = new THREE.Mesh(geo, mat);
  mesh.frustumCulled = false;
  mesh.renderOrder = 24;
  return { mesh, geo, mat, aSpawn, W, P, VPR, loop, cursor: 0, lastSpawn: -999, prevReact: 0 };
}

// Fire one wave (respects minGap so machine-gun onsets don't strobe).
function spawnBrainBassWave(wv, t, intensity, tune) {
  const T = tune || {};
  if (t - wv.lastSpawn < (T.minGap ?? 0.12)) return;
  wv.lastSpawn = t;
  const w = wv.cursor; wv.cursor = (wv.cursor + 1) % wv.W;
  const vpr = wv.VPR || wv.P;
  for (let i = 0; i < vpr; i++) wv.aSpawn[w * vpr + i] = t;
  wv.geo.attributes.aSpawn.needsUpdate = true;
  wv.mat.uniforms.uBright.value = (T.bright ?? 1.5) * (0.5 + 0.5 * intensity);
}

// BASS drives the waves: a rising edge of the bass stem's react crossing
// onsetThr fires one expanding ring. `tune` overrides (lab pattern) — defaults
// are the app's baked values.
function updateBrainBassWaves(wv, t, bassReact, tune) {
  if (!wv) return;
  const T = tune || {};
  const u = wv.mat.uniforms;
  u.uTime.value = t;
  u.uSpeed.value = T.speed ?? 1.2;
  u.uLife.value = T.life ?? 1.2;
  u.uThick.value = T.thick ?? 0.28;
  u.uFade.value = T.fade ?? 1.8;
  u.uTail.value = T.tail ?? 2.2;
  if (T.color) u.uColor.value.setRGB(T.color[0], T.color[1], T.color[2]);
  const thr = T.onsetThr ?? 0.30;
  const r = bassReact || 0;
  if (r > thr && wv.prevReact <= thr) spawnBrainBassWave(wv, t, Math.min(1, r), T);
  wv.prevReact = r;
}

// A "ball of scribbles": each stroke is a CONTINUOUS polyline (THREE.Line) that
// wanders through a noise field, tangling into a dense ball. This is the correct
// construction for the reference look — NOT SphereGeometry+EdgesGeometry, which
// emits disconnected edge stubs. `basePositions` holds each stroke's rest shape
// so update() can dance the vertices around it without redrawing the walk.
function buildWireframeBlob(opts) {
  // OUTER shell holds the fixed screen-space oval (aspect) + position and never
  // rotates, so "wider than tall" stays stable while the INNER ball spins and
  // reacts inside it. The void the ball lives in is oblong (wider than tall), so
  // aspectX>aspectY lets the threads reach farther horizontally than vertically.
  const group = new THREE.Group();
  const inner = new THREE.Group();
  group.add(inner);
  const lines = [];
  const basePositions = [];
  const color = opts.color || 0xeaf4ff;
  const strokeCount = opts.strokeCount || 26;
  const pointsPerStroke = opts.pointsPerStroke || 150;
  const radius = opts.radius || 0.9;
  const step = opts.step || 0.055;
  // Look/shape knobs (defaults = the app's tuned look; the ball-look lab
  // tools/av_debug/ball-look.html passes live overrides). noiseScale = how fast
  // the walk turns (curliness), curl = character of the wiggle, containment =
  // how hard strays are pulled back in, startSpread = how tight the walks begin,
  // lineOpacity = per-line glow, size = overall render scale.
  const wander = opts.wander ?? 0.25;           // curviness/jitter of each thread
  const concentration = opts.centerPull ?? 2.0; // radial density exponent (higher = denser core, thinner rim)
  const startSpread = opts.startSpread ?? 0.45;
  const lineOpacity = opts.opacity ?? 0.55;
  const size = opts.size ?? 0.42;
  // Oval reach: how far threads extend horizontally vs vertically (screen space).
  // 1.0 = round; aspectX>aspectY = wider than tall to fill the oblong void.
  const aspectX = opts.aspectX ?? 1.0;
  const aspectY = opts.aspectY ?? 1.0;

  for (let s = 0; s < strokeCount; s++) {
    // Per-thread reach A, drawn center-biased (pow with `concentration`): most
    // threads stay small and pack the core, a few reach the rim → density is
    // highest at the center and thins out EVENLY with radius. Steering is fully
    // isotropic random (no fixed noise field), so there's no directional bias and
    // the ball is radially symmetric — not top-heavy.
    const A = radius * (0.10 + 0.90 * Math.pow(Math.random(), concentration));
    let dx = Math.random() * 2 - 1, dy = Math.random() * 2 - 1, dz = Math.random() * 2 - 1;
    let dl = Math.hypot(dx, dy, dz) || 1; dx /= dl; dy /= dl; dz /= dl;
    let px = dx * A * startSpread * Math.random();
    let py = dy * A * startSpread * Math.random();
    let pz = dz * A * startSpread * Math.random();
    dx = Math.random() * 2 - 1; dy = Math.random() * 2 - 1; dz = Math.random() * 2 - 1;
    dl = Math.hypot(dx, dy, dz) || 1; dx /= dl; dy /= dl; dz /= dl;
    const pts = new Float32Array(pointsPerStroke * 3);

    for (let i = 0; i < pointsPerStroke; i++) {
      pts[i * 3] = px;
      pts[i * 3 + 1] = py;
      pts[i * 3 + 2] = pz;
      // isotropic smooth steering — a small random nudge to the heading
      dx += (Math.random() * 2 - 1) * wander;
      dy += (Math.random() * 2 - 1) * wander;
      dz += (Math.random() * 2 - 1) * wander;
      dl = Math.hypot(dx, dy, dz) || 1; dx /= dl; dy /= dl; dz /= dl;
      px += dx * step; py += dy * step; pz += dz * step;
      // soft-contain within THIS thread's reach A (a bounded scribble shell)
      const r = Math.sqrt(px * px + py * py + pz * pz);
      if (r > A) {
        const pull = (r - A) * 0.6;
        px -= (px / r) * pull; py -= (py / r) * pull; pz -= (pz / r) * pull;
      }
    }

    const geo = new THREE.BufferGeometry();
    geo.setAttribute('position', new THREE.BufferAttribute(pts, 3));
    const mat = new THREE.LineBasicMaterial({
      color,
      transparent: true,
      opacity: lineOpacity,
      blending: THREE.AdditiveBlending,
      depthWrite: false,
      depthTest: false,
    });
    const line = new THREE.Line(geo, mat);
    line.renderOrder = 60 + s;
    inner.add(line);
    lines.push(line);
    basePositions.push(pts.slice());
  }

  return { group, inner, lines, basePositions, radius, size, aspectX, aspectY };
}

function updateWireframeBlob(blob, t, dt, sig, rotSpeed, tiltX, tiltY, tune, doVerts) {
  // Drum response coefficients. Defaults = the app's tuned values; the isolation
  // harness (tools/av_debug/blob-drums.html) passes live overrides so the drum
  // movement can be dialed in without editing this file each pass. The ball reacts
  // to DRUMS only — bass reactivity was removed (bass is becoming its own asset).
  const T = tune || {};
  const kDrumScale   = T.drumScale   ?? 0.28;
  const kDrumAmp     = T.drumAmp     ?? 0.26;
  const kDrumJitter  = T.drumJitter  ?? 0.12;
  const kJitterFreq  = T.jitterFreq  ?? 9.0;
  const kDrumOpacity = T.drumOpacity ?? 0.34;

  const drums = sig.drums, full = sig.full;
  // Spin + reactive scale live on the INNER ball; the OUTER shell only carries
  // the fixed screen-space oval so "wider than tall" stays put as the ball spins.
  const spin = blob.inner || blob.group;
  spin.rotation.y += dt * (0.12 + rotSpeed * 0.30 + full * 0.10);
  spin.rotation.x += dt * (0.05 + rotSpeed * 0.15);
  spin.rotation.z = tiltY * 0.08;
  // DRUMS punch the overall scale so a hit is unmistakable, not just subtle.
  spin.scale.setScalar((blob.layoutScale || 1) * blob.size * (1 + drums * kDrumScale));
  // Fixed oval: reach farther horizontally than vertically to fill the oblong void.
  blob.group.scale.set(blob.aspectX ?? 1.0, blob.aspectY ?? 1.0, 1.0);

  // DRUMS drive the dance: displace each vertex around its rest position by an
  // animated noise, amplitude riding the drum transient. At rest (drums≈0) it's
  // a quiet tangle; on a hit the whole scribble writhes. `jitter` is drums²
  // (squared so only real transients trigger it) feeding a fast high-frequency
  // shimmer — this reads as an electric "snap" on a hit, distinct from the slow
  // baseline sway, and is the first step toward drums live-warping the noise.
  // Vertex-dance loop (~3k points, the ball's main CPU cost) — skippable via doVerts
  // so createScene can gate it when idle or when FPS sags. Rotation/scale above still
  // ran, so the ball keeps spinning smoothly; the dance just holds its last pose a frame.
  if (doVerts === false) return;
  const amp = 0.008 + drums * kDrumAmp;
  const jitter = drums * drums * kDrumJitter;
  const w1 = t * 2.1, w2 = t * 1.7, w3 = t * 2.4;
  const jw = t * kJitterFreq;
  for (let li = 0; li < blob.lines.length; li++) {
    const line = blob.lines[li];
    const base = blob.basePositions[li];
    const arr = /** @type {any} */ (line.geometry.attributes.position.array);
    for (let i = 0; i < arr.length; i += 3) {
      const bx = base[i], by = base[i + 1], bz = base[i + 2];
      arr[i]     = bx + Math.sin(w1 + bx * 4.0 + li) * amp + Math.sin(jw + bx * 11.0 + li * 2.3) * jitter;
      arr[i + 1] = by + Math.cos(w2 + by * 4.0 + li * 1.3) * amp + Math.cos(jw + by * 11.0 + li * 1.9) * jitter;
      arr[i + 2] = bz + Math.sin(w3 + bz * 4.0 + li * 0.7) * amp + Math.sin(jw + bz * 11.0 + li * 3.1) * jitter;
    }
    line.geometry.attributes.position.needsUpdate = true;
    line.material.opacity = Math.min(0.95, 0.5 + drums * kDrumOpacity + full * 0.10 + sig.vocals * 0.08);
  }
}

// ── Brain vocal-reactive dots ─────────────────────────────────────────────
// Prominent node-dots that sit EXACTLY on the baked dots of the reference brain
// image. Positions were detected from brain_wire_reference.png and hand-picked
// to the brain silhouette (tools/av_debug/brain-zone-editor.html), stored in
// js/brain-dots-data.js as window.BRAIN_VOCAL_DOTS. Parent this layer to the
// brain MESH (not the group) so the glow inherits every breath/rotation/jitter
// and can never drift off its dot. VOCALS flare the dots in place — brightness
// and size only, NEVER position (moving a dot would break the seamless overlay).
function buildBrainDots(opts) {
  opts = opts || {};
  const planeW = opts.planeW ?? 3.35;   // must match the brain PlaneGeometry
  const planeH = opts.planeH ?? 2.23;
  const z = opts.z ?? 0.02;             // sit just in front of the plane
  const data = opts.dots || (typeof window !== 'undefined' ? window.BRAIN_VOCAL_DOTS : null) || [];
  const count = data.length;

  const positions = new Float32Array(count * 3);
  const colors = new Float32Array(count * 3);
  const seeds = new Float32Array(count);
  for (let i = 0; i < count; i++) {
    const d = data[i];
    const nx = d.x !== undefined ? d.x : d[0];
    const ny = d.y !== undefined ? d.y : d[1];
    positions[i * 3]     = (nx - 0.5) * planeW;   // image x  → plane-local x
    positions[i * 3 + 1] = (0.5 - ny) * planeH;   // image y↓ → plane-local y↑
    positions[i * 3 + 2] = z;
    colors[i * 3] = colors[i * 3 + 1] = colors[i * 3 + 2] = 0.12; // rest dim
    let h = Math.sin(nx * 127.1 + ny * 311.7) * 43758.5453;
    seeds[i] = h - Math.floor(h);                 // stable per-dot phase 0..1
  }
  const geo = new THREE.BufferGeometry();
  geo.setAttribute('position', new THREE.BufferAttribute(positions, 3));
  geo.setAttribute('color', new THREE.BufferAttribute(colors, 3));
  const mat = new THREE.PointsMaterial({
    size: opts.size ?? 0.064,
    vertexColors: true,
    transparent: true,
    depthWrite: false,
    depthTest: false,
    sizeAttenuation: true,
    blending: THREE.AdditiveBlending,
  });
  const points = new THREE.Points(geo, mat);
  points.frustumCulled = false;
  points.renderOrder = 25; // above the brain plane (renderOrder 20)
  return {
    points, geo, colors, seeds, count, baseSize: mat.size,
    env: new Float32Array(count),   // per-dot brightness envelope (0..1)
    active: new Uint8Array(count),  // which dots belong to the current word
    prevVocal: 0, wordActive: false, lastOnset: -999,
  };
}

// VOCALS light dots per WORD: each vocal onset lights a fresh random set of
// dots, and they stay bright for as long as the note is HELD (their envelope
// tracks the vocal level), then fade on release. A sharp rise mid-phrase
// retriggers a new word. Set tune.uniform=true for the old all-dots-together
// behavior. Positions never move — only brightness + size.
function updateBrainDots(dots, sig, t, tune) {
  if (!dots || !dots.count) return;
  const T = tune || {};
  const baseDim    = T.baseDim     ?? 0.00;   // rest floor (dots dark until a word lights them)
  const bright     = T.vocalBright ?? 2.90;   // lit brightness scale
  const attack     = T.attack      ?? 0.35;   // env rise speed while held
  const release    = T.release     ?? 0.90;   // env fade per frame after release
  const sizePulse  = T.vocalSize   ?? 0.83;
  const twinkleAmt = T.twinkle     ?? 0.51;   // shimmer on lit dots
  const twinkleSpd = T.twinkleSpeed ?? 8.0;
  const tint = T.tint || [1.00, 0.83, 0.69];  // warm amber — reads against a dimmed brain (see brain-dim note)
  const perWord  = Math.max(1, Math.round(T.dotsPerWord ?? 12));
  const onThr    = T.onThreshold  ?? 0.12;    // energy to fire a word from a gap
  const offThr   = T.offThreshold ?? 0.05;    // energy below which a word releases
  const refract  = T.refractory   ?? 0.11;    // min seconds between onsets
  const syllJump = T.syllableJump ?? 0.18;    // rise that retriggers mid-phrase
  const uniform  = !!T.uniform;

  const vocals = sig.vocals;
  const env = dots.env, active = dots.active, colors = dots.colors, seeds = dots.seeds;

  if (uniform) {
    dots.wordActive = true;
    for (let i = 0; i < dots.count; i++) active[i] = 1;
  } else {
    const canFire = (t - dots.lastOnset) > refract;
    let startWord;
    if (T.externalOnset) {
      // caller did the segmentation (e.g. pitch-note detection) and passes sig.onset
      startWord = !!sig.onset && canFire;
    } else {
      const rise = vocals - dots.prevVocal;
      startWord =
        (!dots.wordActive && vocals > onThr && canFire) ||   // onset from a gap
        (dots.wordActive && rise > syllJump && canFire);     // new syllable mid-phrase
    }
    if (startWord) {
      for (let i = 0; i < dots.count; i++) active[i] = 0;
      const k = Math.min(perWord, dots.count);
      let picked = 0;
      while (picked < k) { const idx = (Math.random() * dots.count) | 0; if (!active[idx]) { active[idx] = 1; picked++; } }
      dots.wordActive = true;
      dots.lastOnset = t;
    } else if (dots.wordActive && vocals < offThr) {
      dots.wordActive = false; // note released → members fall to the fade branch
    }
  }
  dots.prevVocal = vocals;

  for (let i = 0; i < dots.count; i++) {
    if (active[i] && dots.wordActive) {
      // held: rise fast toward the vocal level, fall slowly so a hold stays lit
      const d = vocals - env[i];
      env[i] += d * (d > 0 ? attack : attack * 0.25);
    } else {
      env[i] *= release;       // released / non-member → fade out
    }
    const tw = 0.5 + 0.5 * Math.sin(t * twinkleSpd + seeds[i] * 6.28318);
    const b = baseDim + env[i] * bright * (0.7 + 0.3 * tw);
    colors[i * 3]     = tint[0] * b;
    colors[i * 3 + 1] = tint[1] * b;
    colors[i * 3 + 2] = tint[2] * b;
  }
  dots.geo.attributes.color.needsUpdate = true;
  dots.points.material.size = dots.baseSize * (1 + vocals * sizePulse);
}

// ── VOCALS asset: pitch-steered dot trail + waveform streamers ───────────────
// Ported from tools/av_debug/brain-vocals-trail.html (the tuned vocal rig). The
// brain node-dots light along a pitch-steered "wind head" (spine), and each lit
// dot sprouts a point-streamer whose sideways wiggle traces the vocal waveform.
// Driven by the isolated vocals stem's analyser (pitch + time-domain read).
const VOCAL_MIN_MIDI = 45, VOCAL_MAX_MIDI = 81;

// bounding box of the baked dot positions (plane-local), for head + streamer geometry
function computeDotBounds(dotPos, count) {
  let minX = Infinity, maxX = -Infinity, minY = Infinity, maxY = -Infinity;
  for (let i = 0; i < count; i++) {
    const x = dotPos[i * 3], y = dotPos[i * 3 + 1];
    if (x < minX) minX = x; if (x > maxX) maxX = x;
    if (y < minY) minY = y; if (y > maxY) maxY = y;
  }
  return { minX, maxX, minY, maxY, cx: (minX + maxX) / 2, cy: (minY + maxY) / 2, rx: (maxX - minX) / 2, ry: (maxY - minY) / 2 };
}

// a strip of L points per dot (soft additive sprites), reaching out from the dot
function buildBrainStreamers(dots, dotPos, bbox, L) {
  const count = dots.count, total = count * L;
  const positions = new Float32Array(total * 3);
  const sizes = new Float32Array(total);
  const alphas = new Float32Array(total);
  const geo = new THREE.BufferGeometry();
  geo.setAttribute('position', new THREE.BufferAttribute(positions, 3).setUsage(THREE.DynamicDrawUsage));
  geo.setAttribute('aSize', new THREE.BufferAttribute(sizes, 1).setUsage(THREE.DynamicDrawUsage));
  geo.setAttribute('aAlpha', new THREE.BufferAttribute(alphas, 1).setUsage(THREE.DynamicDrawUsage));
  const mat = new THREE.ShaderMaterial({
    transparent: true, depthWrite: false, depthTest: false, blending: THREE.AdditiveBlending,
    uniforms: { uColor: { value: new THREE.Color(1, 0.56, 0.20) }, uBright: { value: 2.31 }, uScale: { value: 520.0 } },
    vertexShader: `
      attribute float aSize; attribute float aAlpha;
      varying float vAlpha; uniform float uScale;
      void main() {
        vAlpha = aAlpha;
        vec4 mv = modelViewMatrix * vec4(position, 1.0);
        gl_PointSize = aSize * uScale / max(-mv.z, 0.001);
        gl_Position = projectionMatrix * mv;
      }`,
    fragmentShader: `
      precision mediump float;
      varying float vAlpha; uniform vec3 uColor; uniform float uBright;
      void main() {
        float d = length(gl_PointCoord - 0.5);
        float a = smoothstep(0.5, 0.0, d) * vAlpha;
        gl_FragColor = vec4(uColor * uBright, a);
      }`,
  });
  const points = new THREE.Points(geo, mat);
  points.frustumCulled = false; points.renderOrder = 26; // above the dots (25)
  const dir = new Float32Array(count * 2);
  for (let i = 0; i < count; i++) {
    let dx = dotPos[i * 3] - bbox.cx, dy = dotPos[i * 3 + 1] - bbox.cy + bbox.ry * 0.5;
    const m = Math.hypot(dx, dy) || 1;
    dir[i * 2] = dx / m; dir[i * 2 + 1] = dy / m;
  }
  return { points, geo, positions, sizes, alphas, L, count, dir, wave: new Float32Array(L) };
}

// autocorrelation F0 (classic ACF + parabolic interp); f0 = -1 when unvoiced/quiet
function detectVocalPitch(analyser, st) {
  if (!analyser || !analyser.context) return { f0: -1, rms: 0 };
  if (!st.td || st.td.length !== analyser.fftSize) st.td = new Float32Array(analyser.fftSize);
  analyser.getFloatTimeDomainData(st.td);
  const buf = st.td, SIZE = buf.length, sr = analyser.context.sampleRate;
  let rms = 0;
  for (let i = 0; i < SIZE; i++) { const v = buf[i]; rms += v * v; }
  rms = Math.sqrt(rms / SIZE);
  if (rms < 0.0001) return { f0: -1, rms };
  let r1 = 0, r2 = SIZE - 1; const thres = 0.2;
  for (let i = 0; i < SIZE / 2; i++) { if (Math.abs(buf[i]) < thres) { r1 = i; break; } }
  for (let i = 1; i < SIZE / 2; i++) { if (Math.abs(buf[SIZE - i]) < thres) { r2 = SIZE - i; break; } }
  const b = buf.subarray(r1, r2), n = b.length;
  if (n < 8) return { f0: -1, rms };
  const c = new Float32Array(n);
  for (let i = 0; i < n; i++) { let s = 0; for (let j = 0; j < n - i; j++) s += b[j] * b[j + i]; c[i] = s; }
  let d = 0; while (d < n - 1 && c[d] > c[d + 1]) d++;
  let maxval = -1, maxpos = -1;
  for (let i = d; i < n; i++) { if (c[i] > maxval) { maxval = c[i]; maxpos = i; } }
  if (maxpos <= 0) return { f0: -1, rms };
  let T0 = maxpos;
  const x1 = c[T0 - 1] || 0, x2 = c[T0], x3 = c[T0 + 1] || 0;
  const aa = (x1 + x3 - 2 * x2) / 2, bb = (x3 - x1) / 2;
  if (aa) T0 = T0 - bb / (2 * aa);
  const f0 = sr / T0;
  const clarity = maxval / (c[0] + 1e-6);
  if (clarity < 0.55 || f0 < 60 || f0 > 1200) return { f0: -1, rms };
  return { f0, rms };
}

// per-frame vocal input: { pitchNorm (0..1 or NaN), level (0..1), voiced }
function readVocalInput(analyser, st) {
  const { f0, rms } = detectVocalPitch(analyser, st);
  st.levPeak = Math.max((st.levPeak || 0.02) * 0.999, rms);
  let level = clamp01(rms / (st.levPeak + 1e-4));
  let pitchNorm = NaN, voiced = false;
  if (f0 > 0) {
    const midi = 69 + 12 * Math.log2(f0 / 440);
    pitchNorm = clamp01((midi - VOCAL_MIN_MIDI) / (VOCAL_MAX_MIDI - VOCAL_MIN_MIDI));
    voiced = true;
    level = Math.max(0.45, level); // a held note keeps the head energised
  }
  return { pitchNorm, level, voiced };
}

// fill `out` (length L) with the vocal waveform (oscilloscope read), normalised, then box-blur
// toward a clean ribbon by `smooth`. Silence → zeros (streamers vanish since dot brightness is 0).
function fillVocalWave(analyser, out, L, smooth, st) {
  let got = false;
  if (analyser) {
    if (!st.wtd || st.wtd.length !== analyser.fftSize) st.wtd = new Float32Array(analyser.fftSize);
    analyser.getFloatTimeDomainData(st.wtd);
    const SIZE = st.wtd.length, hop = Math.max(1, Math.floor(SIZE / L));
    let peak = 0.0001;
    for (let j = 0; j < L; j++) { const v = st.wtd[j * hop] || 0; out[j] = v; if (Math.abs(v) > peak) peak = Math.abs(v); }
    got = peak > 0.002;
    const g = 1 / Math.max(peak, 0.05);
    for (let j = 0; j < L; j++) out[j] *= g;
  }
  if (!got) for (let j = 0; j < L; j++) out[j] = 0;
  const passes = Math.round(smooth * 4);
  for (let k = 0; k < passes; k++) {
    let prev = out[0];
    for (let j = 0; j < L; j++) { const nx = j + 1 < L ? out[j + 1] : out[j]; const cur = out[j]; out[j] = (prev + cur + nx) / 3; prev = cur; }
  }
}

// light the dots along a pitch-steered wind head; dots fade behind it → a trail (the spine)
function updateBrainTrail(dots, dotPos, bbox, sig, t, T, trail) {
  const env = dots.env, colors = dots.colors, seeds = dots.seeds;
  const pitchY = bbox.minY + (isNaN(sig.pitchNorm) ? 0.5 : sig.pitchNorm) * (bbox.maxY - bbox.minY);
  const targetY = bbox.cy + (pitchY - bbox.cy) * T.pull;
  if (sig.voiced) trail.lastPy = trail.lastPy * 0.85 + targetY * 0.15;
  const py = trail.lastPy;
  const energy = 0.35 + sig.level * 0.65;
  const ws = 0.6 + T.wind * 2.0;
  const nx = 0.62 * Math.sin(t * ws * 0.31) + 0.38 * Math.sin(t * ws * 0.73 + 1.3);
  const ny = 0.62 * Math.cos(t * ws * 0.23) + 0.38 * Math.sin(t * ws * 0.53 + 2.1);
  const hx = bbox.cx + nx * bbox.rx * T.roam * energy;
  const hy = py + ny * bbox.ry * T.turb * energy * 0.6;
  const rel = T.fade, R = T.radius, R2 = R * R;
  const intensity = sig.voiced ? Math.max(0.15, sig.level) : 0;
  for (let i = 0; i < dots.count; i++) {
    env[i] *= rel;
    const dx = dotPos[i * 3] - hx, dy = dotPos[i * 3 + 1] - hy;
    const d2 = dx * dx + dy * dy;
    if (d2 < R2 && intensity > 0) {
      let w = 1 - Math.sqrt(d2) / R; w *= w;
      const lit = w * intensity;
      if (lit > env[i]) env[i] = lit;
    }
  }
  const baseDim = T.baseDim, bright = T.vocalBright, tw = T.twinkle, tws = T.twinkleSpeed, tint = T.tint;
  for (let i = 0; i < dots.count; i++) {
    const flick = 0.5 + 0.5 * Math.sin(t * tws + seeds[i] * 6.28318);
    const b = baseDim + env[i] * bright * (1 - tw + tw * flick);
    colors[i * 3] = tint[0] * b;
    colors[i * 3 + 1] = tint[1] * b;
    colors[i * 3 + 2] = tint[2] * b;
  }
  dots.geo.attributes.color.needsUpdate = true;
  dots.points.material.size = dots.baseSize * (1 + sig.level * T.vocalSize);
}

// redraw the waveform streamers off each lit dot (length + brightness ∝ dot lit-ness)
function updateBrainStreamers(stream, dots, dotPos, level, T, t, analyser, waveState) {
  if (!T.streamOn) { stream.points.visible = false; return; }
  stream.points.visible = true;
  const L = stream.L, pos = stream.positions, sz = stream.sizes, al = stream.alphas, env = dots.env, seeds = dots.seeds;
  fillVocalWave(analyser, stream.wave, L, T.smooth, waveState);
  const amp = T.waveAmp, len = T.streamLen, sway = T.sway, ws = 0.5 + T.streamWind * 3;
  let p = 0;
  for (let i = 0; i < stream.count; i++) {
    const bright = Math.min(1, env[i]);
    const ox = dotPos[i * 3], oy = dotPos[i * 3 + 1];
    const dx = stream.dir[i * 2], dy = stream.dir[i * 2 + 1];
    const px = -dy, py = dx;
    const seed = seeds[i] * 6.28318;
    for (let j = 0; j < L; j++, p++) {
      const tj = j / (L - 1);
      const reach = tj * len * bright;
      const wig = stream.wave[j] * amp;
      const sw = Math.sin(t * ws + seed + j * 0.4) * sway * tj;
      const trans = (wig + sw) * bright;
      pos[p * 3] = ox + dx * reach + px * trans;
      pos[p * 3 + 1] = oy + dy * reach + py * trans;
      pos[p * 3 + 2] = 0.03 + tj * 0.01;
      sz[p] = T.streamSize * (1 - 0.5 * tj);
      al[p] = bright * (1 - tj * 0.85);
    }
  }
  stream.geo.attributes.position.needsUpdate = true;
  stream.geo.attributes.aSize.needsUpdate = true;
  stream.geo.attributes.aAlpha.needsUpdate = true;
  stream.points.material.uniforms.uColor.value.setRGB(T.tint[0], T.tint[1], T.tint[2]);
  stream.points.material.uniforms.uBright.value = T.streamBright;
}

function buildBrainReferenceBrain() {
  const group = new THREE.Group();
  group.position.set(0, 0.02, -0.06);
  group.renderOrder = 10;

  const texture = new THREE.TextureLoader().load('assets/brain_wire_reference.png');
  texture.minFilter = THREE.LinearFilter;
  texture.magFilter = THREE.LinearFilter;
  texture.generateMipmaps = false;

  const material = new THREE.ShaderMaterial({
    transparent: true,
    depthWrite: false,
    depthTest: false,
    blending: THREE.AdditiveBlending,
    uniforms: {
      uMap: { value: texture },
      uTime: { value: 0 },
      uBass: { value: 0 },
      uDrums: { value: 0 },
      uVocals: { value: 0 },
      uMelody: { value: 0 },
      uDim: { value: 1.0 },   // global brain brightness; createScene dims it so the vocal dots read
    },
    vertexShader: `
      varying vec2 vUv;
      varying float vTide;
      uniform float uTime;
      uniform float uBass;
      uniform float uVocals;
      uniform float uMelody;

      void main() {
        vUv = uv;
        vec3 p = position;
        float horizontal = (uv.x - 0.5) * 2.0;
        float vertical = (uv.y - 0.5) * 2.0;
        float tide =
          sin(horizontal * 3.2 + vertical * 1.4 + uTime * 0.42) * 0.5 +
          cos(vertical * 4.4 - uTime * 0.31) * 0.35 +
          sin((horizontal + vertical) * 5.2 + uTime * 0.22) * 0.15;
        float centerEase = smoothstep(1.45, 0.12, length(vec2(horizontal, vertical)));
        float breath = 1.0 + uBass * 0.030 + tide * 0.010 * (0.35 + uVocals);
        p.xy *= breath;
        p.x += tide * 0.018 * centerEase * (0.35 + uMelody);
        p.y += sin(horizontal * 2.7 - uTime * 0.34) * 0.012 * centerEase * (0.25 + uVocals);
        p.z += tide * 0.050 * centerEase * (0.18 + uBass + uVocals * 0.55);
        vTide = tide;
        gl_Position = projectionMatrix * modelViewMatrix * vec4(p, 1.0);
      }
    `,
    fragmentShader: `
      precision highp float;
      uniform sampler2D uMap;
      uniform float uTime;
      uniform float uBass;
      uniform float uDrums;
      uniform float uVocals;
      uniform float uMelody;
      uniform float uDim;
      varying vec2 vUv;
      varying float vTide;

      vec2 flowField(vec2 uv, float t) {
        vec2 p = uv - 0.5;
        float r = length(p);
        float a = atan(p.y, p.x);
        float swirl = sin(a * 3.0 + t * 0.34) * 0.006 + cos(r * 18.0 - t * 0.22) * 0.005;
        vec2 tangent = vec2(-p.y, p.x) / max(r, 0.05);
        vec2 drift = vec2(
          sin(uv.y * 8.0 + t * 0.18) + sin((uv.x + uv.y) * 9.0 - t * 0.25),
          cos(uv.x * 7.0 - t * 0.20) + sin((uv.x - uv.y) * 6.0 + t * 0.19)
        ) * 0.0038;
        return tangent * swirl + drift;
      }

      void main() {
        vec2 q = vUv - 0.5;
        float centerEase = smoothstep(0.82, 0.08, length(q));
        float motion = 0.55 + uBass * 0.50 + uVocals * 0.42 + uMelody * 0.26;
        vec2 flow = flowField(vUv, uTime) * motion;
        vec2 uv0 = vUv + flow;
        vec2 uv1 = vUv + flow * 1.9 + vec2(sin(uTime * 0.13), cos(uTime * 0.11)) * 0.0035 * (0.4 + uVocals);
        vec2 uv2 = vUv - flow * 1.35 + vec2(cos(uTime * 0.09), sin(uTime * 0.16)) * 0.0028 * (0.4 + uBass);

        vec4 tex = texture2D(uMap, uv0);
        vec4 ghostA = texture2D(uMap, uv1);
        vec4 ghostB = texture2D(uMap, uv2);
        tex.rgb = max(tex.rgb, ghostA.rgb * (0.38 + uVocals * 0.22));
        tex.rgb = max(tex.rgb, ghostB.rgb * (0.24 + uBass * 0.20));
        float lum = max(max(tex.r, tex.g), tex.b);
        float alpha = smoothstep(0.030, 0.18, lum);
        float stars = smoothstep(0.48, 0.90, lum);
        float wave = 0.5 + 0.5 * sin(uTime * 0.82 + vUv.x * 18.0 + vUv.y * 7.0 + vTide * 2.0);
        float pulse = 1.0 + uBass * 0.22 + uVocals * 0.15 + uMelody * 0.10;
        float sparkle = 1.0 + stars * (uDrums * 1.05 + 0.25 * wave);
        vec3 blue = vec3(0.44, 0.74, 1.0);
        vec3 white = vec3(0.88, 0.96, 1.0);
        vec3 col = mix(blue, white, smoothstep(0.18, 0.85, lum));
        col *= tex.rgb * (1.20 + pulse * 0.50 + centerEase * 0.08) * sparkle;
        col += vec3(0.20, 0.45, 0.82) * alpha * (0.12 + wave * 0.08);
        gl_FragColor = vec4(col * uDim, alpha * (0.82 + wave * 0.12));
      }
    `,
  });

  const mesh = new THREE.Mesh(new THREE.PlaneGeometry(3.35, 2.23, 80, 54), material);
  mesh.renderOrder = 20;
  group.add(mesh);

  return {
    kind: 'reference-brain',
    group,
    mesh,
    material,
    layoutScale: 1,
    cageDensity: 1,
    setHot: (_hot) => {},
  };
}

function buildBrainFrameV3() {
  const group = new THREE.Group();
  group.position.set(0, -0.02, 0);
  group.renderOrder = 10;

  const hullMat = new THREE.MeshBasicMaterial({
    color: 0x071c2b,
    transparent: true,
    opacity: 0.20,
    depthWrite: false,
    depthTest: false,
    side: THREE.DoubleSide,
    blending: THREE.AdditiveBlending,
  });
  const outlineMat = new THREE.LineBasicMaterial({
    color: 0xd7f4ff,
    transparent: true,
    opacity: 0.86,
    blending: THREE.AdditiveBlending,
    depthWrite: false,
    depthTest: false,
  });
  const neuralMat = new THREE.LineBasicMaterial({
    color: 0xb8eaff,
    transparent: true,
    opacity: 0.32,
    blending: THREE.AdditiveBlending,
    depthWrite: false,
    depthTest: false,
  });
  const cageMat = new THREE.LineBasicMaterial({
    color: 0x6db7ff,
    transparent: true,
    opacity: 0.38,
    blending: THREE.AdditiveBlending,
    depthWrite: false,
    depthTest: false,
  });

  const hull = makeSagittalBrainHull(hullMat);
  hull.renderOrder = 10;
  group.add(hull);

  const contours = [];
  const outer = makePolyline(sagittalOuterPoints(1.08, 0.05), outlineMat.clone(), true);
  outer.userData.baseOpacity = 0.66;
  outer.renderOrder = 24;
  group.add(outer);
  contours.push(outer);

  for (let i = 0; i < 9; i++) {
    const offset = -0.030 + i * 0.012;
    const echo = makePolyline(sagittalOuterPoints(1.04 - i * 0.014, offset), outlineMat.clone(), true);
    echo.userData.baseOpacity = 0.34 - i * 0.022;
    echo.renderOrder = 22 + i;
    group.add(echo);
    contours.push(echo);
  }

  const inner = makePolyline(sagittalInnerCavityPoints(1.00, 0.08), outlineMat.clone(), true);
  inner.userData.baseOpacity = 0.62;
  inner.renderOrder = 30;
  group.add(inner);
  contours.push(inner);

  const cerebellum = makePolyline(sagittalCerebellumPoints(1.0, 0.10), outlineMat.clone(), true);
  cerebellum.userData.baseOpacity = 0.58;
  cerebellum.renderOrder = 31;
  group.add(cerebellum);
  contours.push(cerebellum);

  const stem = makePolyline(sagittalStemPoints(1.0, 0.12), outlineMat.clone(), false);
  stem.userData.baseOpacity = 0.62;
  stem.renderOrder = 32;
  group.add(stem);
  contours.push(stem);

  const gyri = [];
  const loopSpecs = [
    [-0.78, 0.08, 0.38, 0.34, -0.08, 8],
    [-0.45, 0.32, 0.36, 0.24, 0.06, 7],
    [-0.08, 0.42, 0.34, 0.22, 0.12, 7],
    [0.32, 0.35, 0.40, 0.25, -0.04, 8],
    [0.66, 0.11, 0.36, 0.36, 0.06, 8],
    [0.50, -0.23, 0.36, 0.28, -0.08, 7],
    [-0.10, -0.31, 0.42, 0.24, 0.05, 8],
    [-0.55, -0.18, 0.32, 0.28, -0.02, 7],
  ];
  loopSpecs.forEach((spec, specIndex) => {
    for (let i = 0; i < spec[5] + 5; i++) {
      const jitterX = (pseudo(specIndex * 20 + i * 3.1) - 0.5) * spec[2] * 0.36;
      const jitterY = (pseudo(specIndex * 17 + i * 4.7) - 0.5) * spec[3] * 0.32;
      const pts = makeNoisyLoop(
        spec[0] + jitterX,
        spec[1] + jitterY,
        spec[2] * (0.62 + pseudo(i * 5.2 + specIndex) * 0.36),
        spec[3] * (0.58 + pseudo(i * 7.4 + specIndex) * 0.34),
        spec[4] + (pseudo(i * 9.8) - 0.5) * 0.25,
        -0.06 + pseudo(i * 6.6 + specIndex) * 0.22,
        i * 1.83 + specIndex,
      );
      const line = new THREE.Line(new THREE.BufferGeometry().setFromPoints(pts), neuralMat.clone());
      line.userData.baseOpacity = 0.18 + pseudo(i * 11.1 + specIndex) * 0.16;
      line.renderOrder = 38 + specIndex * 8 + i;
      group.add(line);
      gyri.push(line);
    }
  });

  for (let i = 0; i < 82; i++) {
    const pts = [];
    const start = sagittalSampleInside(i * 1.71, 0.10);
    const len = 0.32 + pseudo(i * 8.3) * 0.52;
    for (let j = 0; j < 22; j++) {
      const u = j / 21;
      const x = start.x + (u - 0.5) * len;
      const y = start.y + Math.sin(u * Math.PI * (1.5 + pseudo(i) * 2.5) + i) * (0.035 + pseudo(i * 3.3) * 0.065);
      const z = start.z + Math.sin(u * Math.PI * 2 + i) * 0.05;
      if (sagittalBrainMask(x, y) > 0.08) pts.push(new THREE.Vector3(x, y, z));
    }
    if (pts.length > 4) {
      const line = new THREE.Line(new THREE.BufferGeometry().setFromPoints(new THREE.CatmullRomCurve3(pts).getPoints(34)), neuralMat.clone());
      line.userData.baseOpacity = 0.12 + pseudo(i * 4.4) * 0.10;
      line.renderOrder = 60 + i;
      group.add(line);
      gyri.push(line);
    }
  }

  const nodeCount = 150;
  const nodePositions = new Float32Array(nodeCount * 3);
  const nodeSeeds = [];
  for (let i = 0; i < nodeCount; i++) {
    const p = sagittalSampleInside(i * 2.87, 0.12);
    nodePositions[i * 3] = p.x;
    nodePositions[i * 3 + 1] = p.y;
    nodePositions[i * 3 + 2] = p.z;
    nodeSeeds.push(pseudo(i * 31.7) * 100);
  }
  const nodeGeo = new THREE.BufferGeometry();
  nodeGeo.setAttribute('position', new THREE.BufferAttribute(nodePositions, 3));
  const nodeMat = new THREE.PointsMaterial({
    color: 0xe9f7ff,
    size: 0.030,
    transparent: true,
    opacity: 0.76,
    depthWrite: false,
    depthTest: false,
    sizeAttenuation: true,
    blending: THREE.AdditiveBlending,
  });
  const nodes = new THREE.Points(nodeGeo, nodeMat);
  nodes.frustumCulled = false;
  nodes.renderOrder = 92;
  group.add(nodes);

  const cageGeo = new THREE.BufferGeometry();
  cageGeo.setAttribute('position', new THREE.BufferAttribute(makeSagittalCagePositions(), 3));
  const cage = new THREE.LineSegments(cageGeo, cageMat);
  cage.frustumCulled = false;
  cage.renderOrder = 18;
  group.add(cage);

  return {
    group,
    hull,
    contours,
    gyri,
    nodes,
    nodePositions,
    nodeBasePositions: nodePositions.slice(),
    nodeSeeds,
    cage,
    cageDensity: 1,
    layoutScale: 1,
    setHot: (_hot) => {
      outlineMat.color.set(0xd7f4ff);
      neuralMat.color.set(0xb8eaff);
      cageMat.color.set(0x6db7ff);
      nodeMat.color.set(0xe9f7ff);
    },
  };
}

function makeSagittalBrainHull(material) {
  const shape = new THREE.Shape();
  const outer = sagittalOuterPoints(1.02, 0);
  outer.forEach((p, i) => {
    if (i === 0) shape.moveTo(p.x, p.y);
    else shape.lineTo(p.x, p.y);
  });
  const hole = new THREE.Path();
  const inner = sagittalInnerCavityPoints(0.98, 0).reverse();
  inner.forEach((p, i) => {
    if (i === 0) hole.moveTo(p.x, p.y);
    else hole.lineTo(p.x, p.y);
  });
  shape.holes.push(hole);
  return new THREE.Mesh(new THREE.ShapeGeometry(shape, 36), material);
}

function sagittalOuterPoints(scale, z) {
  const raw = [
    [-1.03, -0.08], [-0.98, 0.15], [-0.84, 0.35], [-0.58, 0.50],
    [-0.22, 0.58], [0.18, 0.57], [0.55, 0.46], [0.84, 0.26],
    [1.00, 0.02], [0.98, -0.22], [0.82, -0.43], [0.55, -0.52],
    [0.30, -0.46], [0.14, -0.58], [0.06, -0.78], [-0.05, -0.86],
    [-0.18, -0.76], [-0.16, -0.56], [-0.38, -0.47], [-0.66, -0.40],
    [-0.90, -0.27],
  ];
  return smoothClosedPolyline(raw.map((p) => new THREE.Vector3(p[0] * scale, p[1] * scale, z)), 6);
}

function sagittalInnerCavityPoints(scale, z) {
  const raw = [
    [-0.42, -0.08], [-0.31, 0.12], [-0.08, 0.24], [0.23, 0.23],
    [0.43, 0.08], [0.47, -0.12], [0.34, -0.29], [0.08, -0.36],
    [-0.20, -0.31], [-0.40, -0.21],
  ];
  return smoothClosedPolyline(raw.map((p) => new THREE.Vector3(p[0] * scale, p[1] * scale, z)), 7);
}

function sagittalCerebellumPoints(scale, z) {
  const raw = [
    [0.30, -0.47], [0.50, -0.41], [0.73, -0.45], [0.86, -0.59],
    [0.80, -0.75], [0.58, -0.82], [0.34, -0.75], [0.22, -0.61],
  ];
  return smoothClosedPolyline(raw.map((p) => new THREE.Vector3(p[0] * scale, p[1] * scale, z)), 7);
}

function sagittalStemPoints(scale, z) {
  return [
    new THREE.Vector3(0.12 * scale, -0.55 * scale, z),
    new THREE.Vector3(0.11 * scale, -0.72 * scale, z),
    new THREE.Vector3(0.02 * scale, -0.94 * scale, z),
    new THREE.Vector3(-0.11 * scale, -1.08 * scale, z),
  ];
}

function smoothClosedPolyline(points, subdivisions) {
  const curve = new THREE.CatmullRomCurve3(points, true, 'catmullrom', 0.45);
  return curve.getPoints(points.length * subdivisions);
}

function makeNoisyLoop(cx, cy, rx, ry, rotation, z, seed) {
  const pts = [];
  const count = 96;
  const cr = Math.cos(rotation);
  const sr = Math.sin(rotation);
  for (let i = 0; i <= count; i++) {
    const a = (i / count) * Math.PI * 2;
    const wobble = 1 + Math.sin(a * 3.0 + seed) * 0.060 + Math.sin(a * 7.0 - seed * 0.7) * 0.035;
    const x0 = Math.cos(a) * rx * wobble;
    const y0 = Math.sin(a) * ry * wobble;
    const x = cx + x0 * cr - y0 * sr;
    const y = cy + x0 * sr + y0 * cr;
    if (sagittalBrainMask(x, y) > -0.20) pts.push(new THREE.Vector3(x, y, z + Math.sin(a * 2 + seed) * 0.030));
  }
  return pts;
}

function sagittalBrainMask(x, y) {
  const outer = [
    ellipseMask(x, y, -0.34, 0.05, 0.76, 0.52),
    ellipseMask(x, y, 0.28, 0.06, 0.76, 0.52),
    ellipseMask(x, y, -0.40, -0.23, 0.62, 0.32),
    ellipseMask(x, y, 0.50, -0.53, 0.42, 0.30),
    ellipseMask(x, y, -0.06, -0.66, 0.20, 0.42),
  ].reduce((m, v) => Math.max(m, v), -10);
  const cavity = ellipseMask(x, y, 0.03, -0.08, 0.50, 0.31);
  return Math.min(outer, -cavity + 0.16);
}

function ellipseMask(x, y, cx, cy, rx, ry) {
  const dx = (x - cx) / rx;
  const dy = (y - cy) / ry;
  return 1 - dx * dx - dy * dy;
}

function sagittalSampleInside(seed, zScale) {
  for (let tries = 0; tries < 32; tries++) {
    const x = -1.00 + pseudo(seed * 5.17 + tries * 11.3) * 2.00;
    const y = -0.78 + pseudo(seed * 7.31 + tries * 17.9) * 1.34;
    if (sagittalBrainMask(x, y) > 0.02) {
      return new THREE.Vector3(x, y, -zScale + pseudo(seed * 9.7 + tries) * zScale * 2);
    }
  }
  return new THREE.Vector3(0, 0.35, 0);
}

function makeSagittalCagePositions() {
  const points = [];
  sagittalOuterPoints(1.42, -0.22).forEach((p, i) => {
    points.push(p.clone().add(new THREE.Vector3(
      (pseudo(i * 5.2) - 0.5) * 0.42,
      (pseudo(i * 7.8) - 0.5) * 0.36,
      -0.18 + pseudo(i * 8.9) * 0.36,
    )));
  });
  for (let i = 0; i < 44; i++) {
    points.push(new THREE.Vector3(
      -1.58 + pseudo(i * 4.7) * 3.16,
      -1.12 + pseudo(i * 8.1) * 2.18,
      -0.36 + pseudo(i * 13.4) * 0.72,
    ));
  }

  const pairs = [];
  for (let i = 0; i < points.length; i++) {
    const ranked = [];
    for (let j = 0; j < points.length; j++) {
      if (i !== j) ranked.push({ j, d: points[i].distanceToSquared(points[j]) });
    }
    ranked.sort((a, b) => a.d - b.d);
    for (let k = 0; k < 3; k++) {
      const j = ranked[k].j;
      if (i < j) pairs.push([i, j]);
    }
  }

  const positions = new Float32Array(pairs.length * 6);
  pairs.forEach((pair, i) => {
    const a = points[pair[0]];
    const b = points[pair[1]];
    positions.set([a.x, a.y, a.z, b.x, b.y, b.z], i * 6);
  });
  return positions;
}

function buildBrainFrameV2() {
  const group = new THREE.Group();
  group.position.set(0, -0.02, 0);
  group.renderOrder = 10;

  const fillMat = new THREE.MeshBasicMaterial({
    color: 0x0a3450,
    transparent: true,
    opacity: 0.10,
    depthWrite: false,
    depthTest: false,
    side: THREE.DoubleSide,
    blending: THREE.AdditiveBlending,
  });
  const wireMat = new THREE.MeshBasicMaterial({
    color: 0x8fdcff,
    wireframe: true,
    transparent: true,
    opacity: 0.32,
    depthWrite: false,
    depthTest: false,
    blending: THREE.AdditiveBlending,
  });
  const outlineMat = new THREE.LineBasicMaterial({
    color: 0xc5f4ff,
    transparent: true,
    opacity: 0.76,
    blending: THREE.AdditiveBlending,
    depthWrite: false,
    depthTest: false,
  });
  const sulcusMat = new THREE.LineBasicMaterial({
    color: 0xa9e6ff,
    transparent: true,
    opacity: 0.18,
    blending: THREE.AdditiveBlending,
    depthWrite: false,
    depthTest: false,
  });
  const cageMat = new THREE.LineBasicMaterial({
    color: 0x4da8ff,
    transparent: true,
    opacity: 0.42,
    blending: THREE.AdditiveBlending,
    depthWrite: false,
    depthTest: false,
  });

  const hull = makeBrainSilhouetteMesh(fillMat.clone());
  hull.renderOrder = 10;
  group.add(hull);

  const lobeSpecs = [
    ['frontal', [-0.58, 0.10, 0.02], [0.60, 0.50, 0.32]],
    ['parietal', [-0.06, 0.31, 0.00], [0.78, 0.40, 0.36]],
    ['occipital', [0.58, 0.07, -0.02], [0.56, 0.44, 0.31]],
    ['temporal', [-0.12, -0.34, 0.02], [0.62, 0.31, 0.29]],
    ['cerebellum', [0.56, -0.46, 0.03], [0.34, 0.23, 0.23]],
  ];
  const lobes = lobeSpecs.map((spec, i) => makeBrainLobe(spec[0], spec[1], spec[2], fillMat, wireMat, i));
  lobes.forEach((lobe) => {
    group.add(lobe.fill);
    group.add(lobe.wire);
  });

  const outline = makePolyline(brainOutlinePoints(1.08, 0.08), outlineMat.clone(), true);
  outline.userData.baseOpacity = 0.70;
  outline.renderOrder = 30;
  group.add(outline);

  const brainstem = makeBrainStem(outlineMat.clone());
  group.add(brainstem);

  const gyri = [];
  for (let i = 0; i < 46; i++) {
    const spec = lobeSpecs[i % lobeSpecs.length];
    const center = new THREE.Vector3(spec[1][0], spec[1][1], spec[1][2]);
    const scale = spec[2];
    const pts = [];
    const yBias = -0.48 + pseudo(i * 4.71) * 0.96;
    const length = 0.55 + pseudo(i * 8.2) * 0.62;
    for (let j = 0; j < 18; j++) {
      const u = j / 17;
      const x = center.x + (u - 0.5) * length * scale[0] * 1.8;
      const y = center.y + yBias * scale[1] * 0.92 + Math.sin(u * Math.PI * (2.0 + pseudo(i) * 2.6) + i) * scale[1] * 0.17;
      const z = center.z + Math.sin(u * Math.PI + i * 0.4) * scale[2] * 0.70;
      if (brainInteriorMaskV2(x, y) > -0.08) pts.push(new THREE.Vector3(x, y, z));
    }
    if (pts.length > 4) {
      const line = new THREE.Line(new THREE.BufferGeometry().setFromPoints(new THREE.CatmullRomCurve3(pts).getPoints(34)), sulcusMat.clone());
      line.userData.baseOpacity = 0.075 + pseudo(i * 6.2) * 0.075;
      line.renderOrder = 38 + i;
      group.add(line);
      gyri.push(line);
    }
  }

  const nodeCount = 128;
  const nodePositions = new Float32Array(nodeCount * 3);
  const nodeSeeds = [];
  for (let i = 0; i < nodeCount; i++) {
    let x = 0;
    let y = 0;
    for (let tries = 0; tries < 16; tries++) {
      x = -1.06 + pseudo(i * 8.41 + tries * 0.37) * 2.16;
      y = -0.62 + pseudo(i * 12.79 + tries * 0.53) * 1.22;
      if (brainInteriorMaskV2(x, y) > 0.02) break;
    }
    nodePositions[i * 3] = x;
    nodePositions[i * 3 + 1] = y;
    nodePositions[i * 3 + 2] = -0.22 + pseudo(i * 19.3) * 0.44;
    nodeSeeds.push(pseudo(i * 31.7) * 100);
  }
  const nodeGeo = new THREE.BufferGeometry();
  nodeGeo.setAttribute('position', new THREE.BufferAttribute(nodePositions, 3));
  const nodeMat = new THREE.PointsMaterial({
    color: 0xe9f7ff,
    size: 0.026,
    transparent: true,
    opacity: 0.70,
    depthWrite: false,
    depthTest: false,
    sizeAttenuation: true,
    blending: THREE.AdditiveBlending,
  });
  const nodes = new THREE.Points(nodeGeo, nodeMat);
  nodes.frustumCulled = false;
  nodes.renderOrder = 42;
  group.add(nodes);

  const cageGeo = new THREE.BufferGeometry();
  cageGeo.setAttribute('position', new THREE.BufferAttribute(makeBrainCagePositionsV2(), 3));
  const cage = new THREE.LineSegments(cageGeo, cageMat);
  cage.frustumCulled = false;
  cage.renderOrder = 24;
  group.add(cage);

  return {
    group,
    hull,
    lobes,
    outline,
    brainstem,
    contours: [outline, brainstem],
    gyri,
    nodes,
    nodePositions,
    nodeBasePositions: nodePositions.slice(),
    nodeSeeds,
    cage,
    cageDensity: 1,
    layoutScale: 1,
    setHot: (_hot) => {
      outlineMat.color.set(0xc5f4ff);
      sulcusMat.color.set(0xa9e6ff);
      cageMat.color.set(0x4da8ff);
      nodeMat.color.set(0xe9f7ff);
    },
  };
}

function makeBrainLobe(name, position, scale, fillMat, wireMat, index) {
  const geometry = new THREE.IcosahedronGeometry(1, 3);
  const fill = new THREE.Mesh(geometry, fillMat.clone());
  fill.name = `${name}-fill`;
  fill.position.set(position[0], position[1], position[2]);
  fill.scale.set(scale[0], scale[1], scale[2]);
  fill.renderOrder = 12 + index;

  const wire = new THREE.Mesh(geometry.clone(), wireMat.clone());
  wire.name = `${name}-wire`;
  wire.position.copy(fill.position);
  wire.scale.copy(fill.scale);
  wire.renderOrder = 20 + index;
  return { fill, wire, baseScale: new THREE.Vector3(scale[0], scale[1], scale[2]), seed: index * 11.7 };
}

function makeBrainSilhouetteMesh(material) {
  const shape = new THREE.Shape();
  const pts = brainOutlinePoints(1.03, 0);
  pts.forEach((p, i) => {
    if (i === 0) shape.moveTo(p.x, p.y);
    else shape.lineTo(p.x, p.y);
  });
  const mesh = new THREE.Mesh(new THREE.ShapeGeometry(shape, 24), material);
  mesh.scale.z = 0.01;
  return mesh;
}

function makeBrainStem(material) {
  const curve = new THREE.CatmullRomCurve3([
    new THREE.Vector3(0.34, -0.45, 0.08),
    new THREE.Vector3(0.40, -0.62, 0.07),
    new THREE.Vector3(0.32, -0.78, 0.05),
    new THREE.Vector3(0.12, -0.88, 0.04),
  ]);
  const line = new THREE.Line(new THREE.BufferGeometry().setFromPoints(curve.getPoints(32)), material);
  line.userData.baseOpacity = 0.58;
  line.renderOrder = 32;
  return line;
}

function brainOutlinePoints(scale, z) {
  return [
    [-1.08, -0.04], [-1.03, 0.20], [-0.88, 0.39], [-0.60, 0.55],
    [-0.23, 0.63], [0.18, 0.61], [0.56, 0.48], [0.87, 0.26],
    [1.04, -0.02], [0.99, -0.25], [0.78, -0.39], [0.53, -0.39],
    [0.38, -0.48], [0.25, -0.64], [0.41, -0.77], [0.25, -0.86],
    [0.04, -0.73], [-0.24, -0.58], [-0.58, -0.52], [-0.88, -0.36],
    [-1.05, -0.17],
  ].map((p) => new THREE.Vector3(p[0] * scale, p[1] * scale, z));
}

function makePolyline(points, material, closed) {
  const pts = closed ? points.concat([points[0].clone()]) : points;
  return new THREE.Line(new THREE.BufferGeometry().setFromPoints(pts), material);
}

function brainInteriorMaskV2(x, y) {
  const lobes = [
    [-0.58, 0.10, 0.68, 0.54],
    [-0.06, 0.29, 0.80, 0.43],
    [0.58, 0.07, 0.60, 0.47],
    [-0.12, -0.34, 0.66, 0.34],
    [0.56, -0.46, 0.38, 0.27],
  ];
  let best = -10;
  lobes.forEach((l) => {
    const dx = (x - l[0]) / l[2];
    const dy = (y - l[1]) / l[3];
    best = Math.max(best, 1 - dx * dx - dy * dy);
  });
  return best;
}

function makeBrainCagePositionsV2() {
  const points = [];
  const outline = brainOutlinePoints(1.24, -0.08);
  outline.forEach((p, i) => {
    const jitter = new THREE.Vector3((pseudo(i * 4.1) - 0.5) * 0.24, (pseudo(i * 7.2) - 0.5) * 0.22, -0.28 + pseudo(i * 3.3) * 0.56);
    points.push(p.clone().add(jitter));
  });
  for (let i = 0; i < 24; i++) {
    points.push(new THREE.Vector3(
      -1.35 + pseudo(i * 5.1) * 2.72,
      -0.92 + pseudo(i * 8.9) * 1.78,
      -0.46 + pseudo(i * 13.4) * 0.92,
    ));
  }

  const pairs = [];
  for (let i = 0; i < points.length; i++) {
    const ranked = [];
    for (let j = 0; j < points.length; j++) {
      if (i !== j) ranked.push({ j, d: points[i].distanceToSquared(points[j]) });
    }
    ranked.sort((a, b) => a.d - b.d);
    for (let k = 0; k < 3; k++) {
      const j = ranked[k].j;
      if (i < j) pairs.push([i, j]);
    }
  }
  const positions = new Float32Array(pairs.length * 6);
  pairs.forEach((pair, i) => {
    const a = points[pair[0]];
    const b = points[pair[1]];
    positions.set([a.x, a.y, a.z, b.x, b.y, b.z], i * 6);
  });
  return positions;
}

function buildBrainFrame() {
  const group = new THREE.Group();
  group.position.set(0, -0.04, 0.00);
  group.renderOrder = 10;

  const hull = new THREE.Mesh(
    makeBrainSurfaceGeometry(),
    new THREE.MeshBasicMaterial({
      color: 0x0d3955,
      transparent: true,
      opacity: 0.16,
      depthWrite: false,
      depthTest: false,
      side: THREE.DoubleSide,
      blending: THREE.AdditiveBlending,
    }),
  );
  hull.renderOrder = 10;
  group.add(hull);

  const lineMat = new THREE.LineBasicMaterial({
    color: 0x9fdcff,
    transparent: true,
    opacity: 0.42,
    blending: THREE.AdditiveBlending,
    depthWrite: false,
    depthTest: false,
  });
  const innerMat = new THREE.LineBasicMaterial({
    color: 0xc8ecff,
    transparent: true,
    opacity: 0.14,
    blending: THREE.AdditiveBlending,
    depthWrite: false,
    depthTest: false,
  });
  const cageMat = new THREE.LineBasicMaterial({
    color: 0x68b7ff,
    transparent: true,
    opacity: 0.38,
    blending: THREE.AdditiveBlending,
    depthWrite: false,
    depthTest: false,
  });

  const contours = [];
  for (let layer = 0; layer < 9; layer++) {
    const z = -0.34 + layer * 0.085;
    const scale = 1 - Math.abs(layer - 4) * 0.035;
    const pts = [];
    for (let i = 0; i <= 160; i++) {
      const a = (i / 160) * Math.PI * 2;
      pts.push(brainProfilePoint(a, scale, z, layer * 0.31));
    }
    const line = new THREE.Line(new THREE.BufferGeometry().setFromPoints(pts), lineMat.clone());
    line.renderOrder = 18 + layer;
    line.userData.baseOpacity = 0.30 + (1 - Math.abs(layer - 4) / 4) * 0.16;
    group.add(line);
    contours.push(line);
  }

  const gyri = [];
  for (let i = 0; i < 56; i++) {
    const lane = i / 55;
    const yBase = -0.44 + lane * 0.90;
    const length = 0.78 + pseudo(i * 9.1) * 0.98;
    const xStart = -0.94 + pseudo(i * 17.2) * 0.34;
    const z = -0.24 + pseudo(i * 5.7) * 0.48;
    const pts = [];
    for (let j = 0; j < 18; j++) {
      const u = j / 17;
      const wave = Math.sin(u * Math.PI * (2.2 + pseudo(i) * 2.4) + i) * (0.035 + pseudo(i * 4.3) * 0.055);
      const x = xStart + u * length;
      const y = yBase + wave + Math.sin(u * Math.PI + i * 0.7) * 0.055;
      const edge = brainInteriorMask(x, y);
      if (edge > 0.08) pts.push(new THREE.Vector3(x, y, z + Math.sin(u * Math.PI * 2 + i) * 0.035));
    }
    if (pts.length > 3) {
      const curve = new THREE.CatmullRomCurve3(pts);
      const line = new THREE.Line(new THREE.BufferGeometry().setFromPoints(curve.getPoints(42)), innerMat.clone());
      line.renderOrder = 34;
      line.userData.baseOpacity = 0.045 + pseudo(i * 3.1) * 0.065;
      group.add(line);
      gyri.push(line);
    }
  }

  for (let i = 0; i < 24; i++) {
    const pts = [];
    const yBase = -0.34 + pseudo(i * 11.8) * 0.82;
    const z = -0.25 + pseudo(i * 8.3) * 0.50;
    for (let j = 0; j < 34; j++) {
      const u = j / 33;
      const x = -0.82 + u * 1.72;
      const y =
        yBase +
        Math.sin(u * Math.PI * (2.4 + pseudo(i * 2.1) * 3.0) + i * 0.7) * 0.045 +
        Math.sin(u * Math.PI + i) * 0.060;
      const edge = brainInteriorMask(x, y);
      if (edge > 0.04) pts.push(new THREE.Vector3(x, y, z + Math.sin(u * Math.PI * 2 + i) * 0.026));
    }
    if (pts.length > 4) {
      const curve = new THREE.CatmullRomCurve3(pts);
      const line = new THREE.Line(new THREE.BufferGeometry().setFromPoints(curve.getPoints(48)), innerMat.clone());
      line.renderOrder = 35;
      line.userData.baseOpacity = 0.040 + pseudo(i * 5.4) * 0.055;
      group.add(line);
      gyri.push(line);
    }
  }

  for (let i = 0; i < 14; i++) {
    const pts = [];
    const z = -0.20 + pseudo(i * 6.7) * 0.42;
    for (let j = 0; j < 28; j++) {
      const u = j / 27;
      const x = -0.10 + u * (0.72 + pseudo(i * 2.2) * 0.18);
      const y =
        -0.40 -
        Math.sin(u * Math.PI) * (0.15 + i * 0.006) -
        i * 0.010 +
        Math.sin(u * Math.PI * 4 + i) * 0.022;
      pts.push(new THREE.Vector3(x, y, z + Math.sin(u * Math.PI * 2 + i) * 0.035));
    }
    const curve = new THREE.CatmullRomCurve3(pts);
    const line = new THREE.Line(new THREE.BufferGeometry().setFromPoints(curve.getPoints(38)), innerMat.clone());
    line.renderOrder = 28;
    line.userData.baseOpacity = 0.10 + pseudo(i * 4.7) * 0.08;
    group.add(line);
    gyri.push(line);
  }

  const nodeCount = 165;
  const nodePositions = new Float32Array(nodeCount * 3);
  const nodeSeeds = [];
  for (let i = 0; i < nodeCount; i++) {
    const a = pseudo(i * 12.79) * Math.PI * 2;
    const r = Math.sqrt(pseudo(i * 8.41)) * 0.92;
    const p = brainProfilePoint(a, r, -0.28 + pseudo(i * 19.3) * 0.56, i * 0.2);
    nodePositions[i * 3] = p.x;
    nodePositions[i * 3 + 1] = p.y;
    nodePositions[i * 3 + 2] = p.z;
    nodeSeeds.push(pseudo(i * 31.7) * 100);
  }
  const nodeGeo = new THREE.BufferGeometry();
  nodeGeo.setAttribute('position', new THREE.BufferAttribute(nodePositions, 3));
  const nodeMat = new THREE.PointsMaterial({
    color: 0xe9f7ff,
    size: 0.024,
    transparent: true,
    opacity: 0.68,
    depthWrite: false,
    depthTest: false,
    sizeAttenuation: true,
    blending: THREE.AdditiveBlending,
  });
  const nodes = new THREE.Points(nodeGeo, nodeMat);
  nodes.frustumCulled = false;
  nodes.renderOrder = 30;
  group.add(nodes);

  const cagePoints = [];
  for (let i = 0; i < 48; i++) {
    const a = pseudo(i * 2.77) * Math.PI * 2;
    const radius = 1.10 + pseudo(i * 8.9) * 0.34;
    const z = -0.52 + pseudo(i * 4.55) * 1.04;
    const p = brainProfilePoint(a, radius, z, i * 0.11);
    p.x += (pseudo(i * 12.2) - 0.5) * 0.55;
    p.y += (pseudo(i * 19.4) - 0.5) * 0.42;
    cagePoints.push(p);
  }
  const cagePairs = [];
  for (let i = 0; i < cagePoints.length; i++) {
    const ranked = [];
    for (let j = 0; j < cagePoints.length; j++) {
      if (i !== j) ranked.push({ j, d: cagePoints[i].distanceToSquared(cagePoints[j]) });
    }
    ranked.sort((a, b) => a.d - b.d);
    for (let k = 0; k < 3; k++) {
      const j = ranked[k].j;
      if (i < j) cagePairs.push([i, j]);
    }
  }
  const cagePos = new Float32Array(cagePairs.length * 6);
  cagePairs.forEach((pair, i) => {
    const a = cagePoints[pair[0]];
    const b = cagePoints[pair[1]];
    cagePos.set([a.x, a.y, a.z, b.x, b.y, b.z], i * 6);
  });
  const cageGeo = new THREE.BufferGeometry();
  cageGeo.setAttribute('position', new THREE.BufferAttribute(cagePos, 3));
  const cage = new THREE.LineSegments(cageGeo, cageMat);
  cage.frustumCulled = false;
  cage.renderOrder = 24;
  group.add(cage);

  return {
    group,
    hull,
    contours,
    gyri,
    nodes,
    nodePositions,
    nodeBasePositions: nodePositions.slice(),
    nodeSeeds,
    cage,
    cageDensity: 1,
    layoutScale: 1,
    setHot: (_hot) => {
      lineMat.color.set(0x9fdcff);
      innerMat.color.set(0xc8ecff);
      cageMat.color.set(0x68b7ff);
      nodeMat.color.set(0xe9f7ff);
    },
  };
}

function updateBrainFrame(brain, t, sig, tiltX, tiltY) {
  if (brain.kind === 'reference-brain') {
    const breath = 1 + sig.bass * 0.025 + sig.full * 0.010 + Math.sin(t * 0.35) * 0.004;
    brain.group.scale.setScalar((brain.layoutScale || 1) * 1.0 * breath);
    brain.group.rotation.x = -0.025 + tiltX * 0.10 + Math.sin(t * 0.17) * 0.006;
    brain.group.rotation.y = tiltY * 0.08 + Math.sin(t * 0.13) * 0.014;
    brain.group.rotation.z = Math.sin(t * 0.11) * 0.006;
    brain.mesh.scale.x = 1 + Math.sin(t * 0.29) * 0.006 + sig.bass * 0.010;
    brain.mesh.scale.y = 1 + Math.cos(t * 0.23) * 0.005 + sig.vocals * 0.008;
    brain.mesh.position.x = Math.sin(t * 0.19) * 0.010;
    brain.mesh.position.y = Math.cos(t * 0.16) * 0.008;
    brain.material.uniforms.uTime.value = t;
    brain.material.uniforms.uBass.value = sig.bass;
    brain.material.uniforms.uDrums.value = sig.drums;
    brain.material.uniforms.uVocals.value = sig.vocals;
    brain.material.uniforms.uMelody.value = sig.melody;
    return;
  }

  const breath = 1 + sig.bass * 0.060 + sig.full * 0.025 + Math.sin(t * 0.35) * 0.008;
  brain.group.scale.setScalar((brain.layoutScale || 1) * 1.46 * breath);
  brain.group.rotation.x = -0.04 + tiltX * 0.30 + Math.sin(t * 0.18) * 0.010;
  brain.group.rotation.y = tiltY * 0.18 + Math.sin(t * 0.13) * 0.020;
  if (brain.hull?.material) {
    brain.hull.material.opacity = 0.13 + sig.bass * 0.08 + sig.full * 0.04;
    brain.hull.scale.setScalar(1 + sig.bass * 0.018);
  }
  if (brain.lobes) {
    brain.lobes.forEach((lobe, i) => {
      const swell = 1 + sig.bass * 0.035 + Math.sin(t * 0.42 + lobe.seed) * 0.006;
      lobe.fill.scale.set(lobe.baseScale.x * swell, lobe.baseScale.y * swell, lobe.baseScale.z * (1 + sig.full * 0.035));
      lobe.wire.scale.copy(lobe.fill.scale);
      lobe.wire.rotation.y += 0.0008 + sig.melody * 0.0018;
      lobe.fill.rotation.y = lobe.wire.rotation.y;
      lobe.wire.material.opacity = 0.24 + sig.drums * 0.18 + i * 0.008;
      lobe.fill.material.opacity = 0.070 + sig.bass * 0.055;
    });
  }

  brain.contours.forEach((line, i) => {
    line.rotation.z = Math.sin(t * 0.12 + i) * 0.008;
    line.material.opacity = Math.min(0.86, line.userData.baseOpacity + sig.bass * 0.14 + sig.full * 0.04);
  });
  brain.gyri.forEach((line, i) => {
    line.rotation.z = Math.sin(t * 0.22 + i * 0.33) * (0.003 + sig.vocals * 0.010);
    line.material.opacity = Math.min(0.42, line.userData.baseOpacity + sig.vocals * 0.070 + sig.full * 0.025);
  });

  brain.nodes.material.opacity = 0.42 + sig.drums * 0.55 + sig.full * 0.10;
  brain.nodes.material.size = 0.018 + sig.drums * 0.034;
  const pos = brain.nodePositions;
  const basePos = brain.nodeBasePositions;
  for (let i = 0; i < brain.nodeSeeds.length; i++) {
    const seed = brain.nodeSeeds[i];
    const flicker = Math.sin(t * 6.0 + seed) * sig.drums * 0.010;
    pos[i * 3] = basePos[i * 3];
    pos[i * 3 + 1] = basePos[i * 3 + 1];
    pos[i * 3 + 2] = basePos[i * 3 + 2] + flicker;
  }
  brain.nodes.geometry.attributes.position.needsUpdate = true;

  brain.cage.rotation.y += 0.0008 + sig.melody * 0.004;
  brain.cage.rotation.z = Math.sin(t * 0.16) * 0.020;
  brain.cage.material.opacity = Math.min(0.72, (0.18 + sig.melody * 0.40 + sig.full * 0.10) * (brain.cageDensity || 1));
}

function makeBrainSurfaceGeometry() {
  const shape = new THREE.Shape();
  for (let i = 0; i <= 132; i++) {
    const a = (i / 132) * Math.PI * 2;
    const p = brainProfilePoint(a, 1.045, 0, 0.45);
    if (i === 0) shape.moveTo(p.x, p.y);
    else shape.lineTo(p.x, p.y);
  }
  const geo = new THREE.ShapeGeometry(shape, 28);
  geo.computeVertexNormals();
  return geo;
}

function brainProfilePoint(a, scale, z, phase) {
  const c = Math.cos(a);
  const s = Math.sin(a);
  const frontal = Math.max(0, -c);
  const rear = Math.max(0, c);
  const top = Math.max(0, s);
  const lower = Math.max(0, -s);
  const frontalRound = frontal * frontal;
  const rearRound = rear * rear;
  const temporal = lower * (0.55 + 0.45 * Math.cos(a - 0.15));
  const x =
    (0.98 * c +
      0.19 * rearRound -
      0.10 * frontalRound +
      0.08 * Math.cos(2 * a) -
      0.08 * lower * frontal) *
    scale;
  const y =
    (0.57 * s +
      0.16 * top -
      0.16 * lower -
      0.18 * temporal +
      0.055 * Math.sin(3 * a + phase) +
      0.025 * Math.sin(7 * a - phase)) *
    scale;
  return new THREE.Vector3(x, y, z * (0.74 + 0.14 * Math.abs(s)));
}

function brainInteriorMask(x, y) {
  const nx = (x + 0.02) / 1.12;
  const ny = (y - 0.02) / 0.68;
  return 1 - (nx * nx + ny * ny);
}

function pseudo(n) {
  return fract(Math.sin(n * 12.9898) * 43758.5453);
}

function fract(v) {
  return v - Math.floor(v);
}

function updateBlobHalo(halo, t, sig) {
  halo.points.rotation.y += 0.0018 + sig.melody * 0.003 + sig.full * 0.002;
  halo.points.rotation.x = Math.sin(t * 0.11) * 0.05;
  halo.points.material.opacity = 0.22 + sig.vocals * 0.18 + sig.full * 0.16;
  halo.points.material.size = 0.020 + sig.vocals * 0.010 + sig.drums * 0.006;
}

function buildRibs() {
  const group = new THREE.Group();
  const rings = [];
  for (let i = 0; i < 5; i++) {
    const pts = [];
    const y = -0.22 + i * 0.18;
    const rx = 1.36 + i * 0.03;
    const rz = 0.55 + i * 0.04;
    for (let j = 0; j <= 96; j++) {
      const a = (j / 96) * Math.PI * 2;
      pts.push(new THREE.Vector3(Math.cos(a) * rx, y, Math.sin(a) * rz));
    }
    const geo = new THREE.BufferGeometry().setFromPoints(pts);
    const mat = new THREE.LineBasicMaterial({
      color: 0x9fd0ff,
      transparent: true,
      opacity: 0.18,
      blending: THREE.AdditiveBlending,
    });
    const line = new THREE.Line(geo, mat);
    group.add(line);
    rings.push(line);
  }
  group.position.y = -0.06;
  return { group, rings };
}

function updateRibs(ribs, t, sig, baseScale) {
  ribs.group.scale.setScalar(baseScale * (1 + sig.drums * 0.10));
  ribs.group.rotation.y += 0.002 + sig.drums * 0.012;
  ribs.rings.forEach((ring, i) => {
    const pulse = sig.drums;
    ring.scale.x = 1 + pulse * (0.12 + i * 0.035) + Math.sin(t * 2.0 - i) * 0.018;
    ring.scale.z = 1 + pulse * (0.20 + i * 0.04);
    ring.material.opacity = 0.08 + pulse * 0.50;
  });
}

function buildReferenceFlower(texture, side) {
  const geo = new THREE.PlaneGeometry(1.54, 1.06, 1, 1);
  const mat = new THREE.ShaderMaterial({
    transparent: true,
    depthWrite: false,
    side: THREE.DoubleSide,
    blending: THREE.AdditiveBlending,
    uniforms: {
      uMap: { value: texture },
      uFlip: { value: side < 0 ? 1 : 0 },
      uTime: { value: 0 },
      uPulse: { value: 0 },
      uAlpha: { value: 0.92 },
    },
    vertexShader: `
      varying vec2 vUv;
      uniform float uTime;
      uniform float uPulse;
      void main(){
        vUv = uv;
        vec3 p = position;
        float center = 1.0 - abs(uv.x - 0.5) * 2.0;
        p.z += sin(uv.x * 6.2831 + uTime * 0.55) * 0.012 * center;
        p.z += uPulse * 0.030 * center * smoothstep(0.08, 0.92, uv.y);
        gl_Position = projectionMatrix * modelViewMatrix * vec4(p, 1.0);
      }
    `,
    fragmentShader: `
      precision highp float;
      uniform sampler2D uMap;
      uniform float uFlip;
      uniform float uTime;
      uniform float uPulse;
      uniform float uAlpha;
      varying vec2 vUv;

      void main(){
        vec2 uv = vUv;
        if(uFlip > 0.5) uv.x = 1.0 - uv.x;
        vec4 tex = texture2D(uMap, uv);
        float lum = max(max(tex.r, tex.g), tex.b);
        vec2 bloomQ = (uv - vec2(0.5, 0.44)) / vec2(0.45, 0.62);
        float bloomMask = 1.0 - smoothstep(0.70, 0.98, dot(bloomQ, bloomQ));
        float edgeFade = smoothstep(0.0, 0.05, uv.x)
          * smoothstep(0.0, 0.06, uv.y)
          * smoothstep(0.0, 0.05, 1.0 - uv.x)
          * smoothstep(0.0, 0.05, 1.0 - uv.y);
        float alpha = tex.a * smoothstep(0.38, 0.66, lum) * edgeFade * bloomMask;
        float edgeGlow = smoothstep(0.34, 0.92, lum);
        vec3 blueLift = vec3(0.18, 0.38, 1.0) * edgeGlow * 0.26;
        vec3 warmLift = vec3(1.0, 0.42, 0.22) * smoothstep(0.28, 0.86, tex.r - tex.b * 0.18) * 0.28;
        vec3 col = tex.rgb * (1.15 + uPulse * 0.22) + blueLift + warmLift;
        col += vec3(0.42, 0.68, 1.0) * alpha * (0.05 + uPulse * 0.12);
        gl_FragColor = vec4(col * alpha, alpha * uAlpha);
      }
    `,
  });
  const mesh = new THREE.Mesh(geo, mat);
  mesh.position.set(0, 0.07, 0.05);
  mesh.rotation.x = -0.08;
  mesh.scale.set(1.0, 1.0, 1);
  return { mesh, material: mat };
}

function buildFlower(x, y, scale, side) {
  const group = new THREE.Group();
  group.position.set(x, y, 0.2);
  group.scale.setScalar(scale);
  group.rotation.z = 0;
  const head = new THREE.Group();
  head.rotation.z = side * 0.92;
  head.rotation.x = -0.22;
  head.rotation.y = -side * 0.12;
  group.add(head);

  const petals = [];
  const petalGeo = makePetalGeometry();
  const petalLayout = [];
  const single = Math.abs(side) < 0.5;
  const layers = [
    { count: 24, radius: 0.315, sx: 0.76, sy: 0.54, alpha: 0.11, turn: 0.03, y: -0.045, z: -0.050, cup: -0.72 },
    { count: 22, radius: 0.260, sx: 0.66, sy: 0.50, alpha: 0.14, turn: 0.17, y: -0.018, z: -0.010, cup: -0.48 },
    { count: 19, radius: 0.205, sx: 0.56, sy: 0.44, alpha: 0.17, turn: 0.08, y: 0.012, z: 0.036, cup: -0.20 },
    { count: 15, radius: 0.145, sx: 0.44, sy: 0.36, alpha: 0.21, turn: 0.25, y: 0.052, z: 0.085, cup: 0.06 },
    { count: 11, radius: 0.085, sx: 0.32, sy: 0.28, alpha: 0.27, turn: 0.02, y: 0.090, z: 0.130, cup: 0.28 },
  ];
  for (let layer = 0; layer < layers.length; layer++) {
    const cfg = layers[layer];
    for (let i = 0; i < cfg.count; i++) {
      const a = cfg.turn + (i / cfg.count) * Math.PI * 2;
      const back = Math.sin(a) < -0.42;
      const sideDepth = Math.cos(a);
      const front = Math.sin(a) > 0.18;
      const depthScale = back ? 0.76 : front ? 1.10 : 0.98;
      petalLayout.push({
        angle: a,
        x: Math.cos(a) * cfg.radius * depthScale,
        y: Math.sin(a) * cfg.radius * 0.58 + cfg.y,
        sx: cfg.sx * (back ? 0.78 : front ? 1.02 : 0.92),
        sy: cfg.sy * (back ? 0.76 : front ? 1.05 : 0.94),
        z: cfg.z + layer * 0.012 + (front ? 0.056 : 0) - (back ? 0.040 : 0),
        alpha: back ? cfg.alpha * 0.55 : cfg.alpha,
        tiltX: cfg.cup + (front ? -0.22 : back ? 0.26 : 0.02),
        tiltY: sideDepth * (0.36 + layer * 0.035),
      });
    }
  }
  petalLayout.forEach((p, i) => {
    const mat = makeWirePetalMaterial(p.alpha);
    const petal = new THREE.Mesh(petalGeo, mat);
    petal.position.set(p.x, p.y, p.z);
    petal.rotation.z = p.angle - Math.PI / 2;
    petal.rotation.x = p.tiltX;
    petal.rotation.y = p.tiltY;
    petal.scale.set(p.sx, p.sy, 1);
    petal.userData.baseScale = { x: p.sx, y: p.sy };
    petal.userData.baseRotation = { x: p.tiltX, y: p.tiltY, z: p.angle - Math.PI / 2 };
    petal.userData.baseAlpha = p.alpha;
    head.add(petal);
    petals.push(petal);
  });

  const core = new THREE.Mesh(
    new THREE.SphereGeometry(0.058, 14, 10),
    new THREE.MeshBasicMaterial({
      color: 0xdbefff,
      wireframe: true,
      transparent: true,
      opacity: 0.38,
      blending: THREE.AdditiveBlending,
      depthWrite: false,
    }),
  );
  core.position.set(0, 0.080, 0.145);
  head.add(core);

  const centerBeads = [];
  for (let i = 0; i < 22; i++) {
    const ring = i < 8 ? 0.030 : i < 16 ? 0.055 : 0.078;
    const a = i * 2.39996;
    const bead = new THREE.Mesh(
      new THREE.SphereGeometry(i < 8 ? 0.014 : 0.011, 10, 8),
      new THREE.MeshBasicMaterial({
        color: 0xdbefff,
        wireframe: true,
        transparent: true,
        opacity: 0.34,
        blending: THREE.AdditiveBlending,
        depthWrite: false,
      }),
    );
    bead.position.set(Math.cos(a) * ring, 0.075 + Math.sin(a) * ring * 0.72, 0.145 + (i % 5) * 0.008);
    head.add(bead);
    centerBeads.push(bead);
  }

  const stemPoints = Math.abs(side) < 0.5
    ? [
      new THREE.Vector3(-0.10, -0.62, 0.02),
      new THREE.Vector3(-0.06, -0.43, 0.025),
      new THREE.Vector3(0.02, -0.26, 0.035),
      new THREE.Vector3(0.00, -0.10, 0.045),
      new THREE.Vector3(0.0, 0.00, 0.055),
    ]
    : [
      new THREE.Vector3(-side * 1.34, -0.56, 0.02),
      new THREE.Vector3(-side * 0.84, -0.46, 0.025),
      new THREE.Vector3(-side * 0.34, -0.31, 0.035),
      new THREE.Vector3(-side * 0.055, -0.14, 0.045),
      new THREE.Vector3(0.0, 0.00, 0.055),
    ];
  const stemCurve = new THREE.CatmullRomCurve3(stemPoints);
  const stem = new THREE.Mesh(
    new THREE.TubeGeometry(stemCurve, 36, 0.011, 7, false),
    new THREE.MeshBasicMaterial({
      color: 0x5c8f43,
      transparent: true,
      opacity: 0.20,
    }),
  );
  group.add(stem);

  const filaments = [];
  for (let i = 0; i < 28; i++) {
    const fan = (i - 13.5) / 13.5;
    const curl = Math.sin(i * 1.37) * 0.026;
    const arch = 1 - Math.abs(fan);
    const tip = new THREE.Vector3(
      fan * 0.205 + curl,
      0.16 + arch * 0.18 + Math.cos(i * 0.91) * 0.014,
      0.165,
    );
    const curve = new THREE.CatmullRomCurve3([
      new THREE.Vector3(fan * 0.010, -0.01, 0.095),
      new THREE.Vector3(fan * 0.045 - curl * 0.4, 0.074, 0.120),
      new THREE.Vector3(fan * 0.120 + curl * 0.6, 0.130 + arch * 0.065, 0.148),
      tip,
    ]);
    const filamentGroup = new THREE.Group();
    filamentGroup.rotation.z = fan * 0.055;

    const tube = new THREE.Mesh(
      new THREE.TubeGeometry(curve, 18, 0.0048, 5, false),
      new THREE.MeshBasicMaterial({
        color: 0xdbefff,
        transparent: true,
        opacity: 0.28,
        depthWrite: false,
      }),
    );
    const anther = new THREE.Mesh(
      new THREE.SphereGeometry(0.0125, 10, 8),
      new THREE.MeshBasicMaterial({
        color: 0xdbefff,
        wireframe: true,
        transparent: true,
        opacity: 0.38,
        blending: THREE.AdditiveBlending,
        depthWrite: false,
      }),
    );
    anther.position.copy(tip);
    anther.scale.set(0.78, 1.22, 0.78);
    filamentGroup.add(tube, anther);
    head.add(filamentGroup);
    filaments.push({
      group: filamentGroup,
      tube,
      anther,
      baseRotation: filamentGroup.rotation.z,
      spread: Math.abs(fan),
    });
  }

  const pistil = new THREE.Mesh(
    new THREE.SphereGeometry(0.036, 12, 10),
    new THREE.MeshBasicMaterial({
      color: 0xdbefff,
      wireframe: true,
      transparent: true,
      opacity: 0.78,
      blending: THREE.AdditiveBlending,
      depthWrite: false,
    }),
  );
  pistil.position.set(0, 0.055, 0.13);
  head.add(pistil);

  return {
    group,
    head,
    reference: null,
    petals,
    core,
    centerBeads,
    filaments,
    pistil,
    stem,
    side,
    setHot: (_hot) => {
      core.material.color.set(0xdbefff);
      pistil.material.color.set(0xdbefff);
      centerBeads.forEach((bead) => bead.material.color.set(0xdbefff));
      filaments.forEach((f) => {
        f.tube.material.color.set(0xdbefff);
        f.anther.material.color.set(0xdbefff);
      });
    },
  };
}

function makePetalGeometry() {
  const rows = 24;
  const cols = 18;
  const positions = [];
  const uvs = [];
  const indices = [];
  for (let y = 0; y <= rows; y++) {
    const v = y / rows;
    const bloom = Math.sin(Math.PI * v);
    const shoulder = smoothstep(0.08, 0.62, v) * (1 - smoothstep(0.86, 1.0, v));
    const rawWidth = (0.040 + shoulder * 0.160 + bloom * 0.045) * (1 - smoothstep(0.88, 1.0, v) * 0.18);
    const width = rawWidth * (1 - smoothstep(0.96, 1.0, v) * 0.18);
    const tipTaper = 1 - Math.pow(v, 4.0) * 0.22;
    for (let x = 0; x <= cols; x++) {
      const u = x / cols;
      const sx = (u - 0.5) * 2;
      const edge = Math.abs(sx);
      const px = sx * width * tipTaper;
      const py = v * 0.92 - 0.025 * bloom * edge;
      const centerCup = (1 - edge * edge) * bloom * (0.070 + v * 0.030);
      const edgeCurl = edge * edge * (0.045 + v * 0.080);
      const tipCurl = smoothstep(0.72, 1.0, v) * (0.060 + 0.040 * Math.sin(u * Math.PI));
      const pz = centerCup - edgeCurl + tipCurl;
      positions.push(px, py, pz);
      uvs.push(u, v);
    }
  }
  for (let y = 0; y < rows; y++) {
    for (let x = 0; x < cols; x++) {
      const a = y * (cols + 1) + x;
      const b = a + 1;
      const c = a + cols + 1;
      const d = c + 1;
      indices.push(a, c, b, b, c, d);
    }
  }
  const geo = new THREE.BufferGeometry();
  geo.setAttribute('position', new THREE.Float32BufferAttribute(positions, 3));
  geo.setAttribute('uv', new THREE.Float32BufferAttribute(uvs, 2));
  geo.setIndex(indices);
  geo.computeVertexNormals();
  return geo;
}

function makeWirePetalMaterial(alpha) {
  return new THREE.MeshBasicMaterial({
    color: 0xdbefff,
    wireframe: true,
    transparent: true,
    opacity: alpha * 0.42,
    depthWrite: false,
    side: THREE.DoubleSide,
  });
}

function makePetalMaterial(hue, alpha) {
  const base = new THREE.Color().setHSL(hue, 0.88, 0.30);
  const blush = new THREE.Color().setHSL(hue + 0.040, 0.96, 0.50);
  const rim = new THREE.Color().setHSL(hue - 0.045, 1.0, 0.67);
  return new THREE.ShaderMaterial({
    transparent: true,
    side: THREE.DoubleSide,
    depthWrite: false,
    blending: THREE.AdditiveBlending,
    uniforms: {
      uBase: { value: base },
      uBlush: { value: blush },
      uRim: { value: rim },
      uAlpha: { value: alpha },
      uTime: { value: 0 },
      uPulse: { value: 0 },
    },
    vertexShader: `
      varying vec2 vUv;
      varying vec3 vN;
      varying vec3 vP;
      uniform float uPulse;
      uniform float uTime;
      void main(){
        vUv = uv;
        vec3 p = position;
        float mid = 1.0 - abs(uv.x - 0.5) * 2.0;
        float edge = abs(uv.x - 0.5) * 2.0;
        float wave = sin(uv.y * 9.5 + uTime * 0.8) * 0.009 * mid;
        p.z += wave + uPulse * 0.038 * mid * smoothstep(0.12, 0.92, uv.y);
        p.x += sin(uv.y * 4.2 + uTime * 0.35) * 0.004 * edge;
        vN = normalize(normalMatrix * normal);
        vP = p;
        gl_Position = projectionMatrix * modelViewMatrix * vec4(p, 1.0);
      }
    `,
    fragmentShader: `
      precision highp float;
      uniform vec3 uBase;
      uniform vec3 uBlush;
      uniform vec3 uRim;
      uniform float uAlpha;
      uniform float uPulse;
      varying vec2 vUv;
      varying vec3 vN;
      varying vec3 vP;

      float line(float x, float w){
        return 1.0 - smoothstep(0.0, w, abs(x));
      }

      void main(){
        float center = 1.0 - abs(vUv.x - 0.5) * 2.0;
        float edge = 1.0 - smoothstep(0.58, 1.0, center);
        float baseFade = smoothstep(0.0, 0.14, vUv.y);
        float tipFade = 1.0 - smoothstep(0.92, 1.0, vUv.y);
        float silhouette = smoothstep(0.015, 0.145, center) * baseFade * tipFade;

        float mainVein = line(vUv.x - 0.5, 0.024) * smoothstep(0.05, 0.96, vUv.y);
        float sideVeins = 0.0;
        for(int i = 1; i <= 6; i++){
          float f = float(i);
          float y = 0.12 + f * 0.115;
          float branch = abs(vUv.y - y) * 2.45;
          float spread = abs(vUv.x - 0.5) - branch * (0.12 + f * 0.016);
          sideVeins += (1.0 - smoothstep(0.0, 0.013, abs(spread))) * (1.0 - smoothstep(0.0, 0.15, branch));
        }
        sideVeins = clamp(sideVeins, 0.0, 1.0);

        vec3 L = normalize(vec3(-0.32, 0.58, 0.86));
        float shade = 0.42 + 0.58 * max(dot(normalize(vN), L), 0.0);
        float fresnel = pow(1.0 - abs(dot(normalize(vN), normalize(vec3(0.0, 0.0, 1.0)))), 1.7);
        float blushMask = smoothstep(0.08, 0.72, vUv.y) * smoothstep(0.12, 0.95, center);
        vec3 col = mix(uBase, uBlush, blushMask * 0.66);
        col = mix(col, uRim, edge * 0.48 + mainVein * 0.22);
        col += uRim * (sideVeins * 0.16 + edge * 0.18 + fresnel * 0.13);
        col *= shade * (0.74 + uPulse * 0.18);
        float glow = mainVein * 0.15 + sideVeins * 0.10 + edge * 0.12 + fresnel * 0.10;
        col += uRim * glow * (0.34 + uPulse * 0.26);
        float alpha = uAlpha * silhouette * (0.32 + center * 0.26 + edge * 0.42 + fresnel * 0.12);
        gl_FragColor = vec4(col, alpha);
      }
    `,
  });
}

function updateFlower(flower, t, melody, vocals, phase) {
  const single = Math.abs(flower.side) < 0.5;
  flower.core.scale.setScalar(1 + melody * 0.45 + vocals * 0.18);
  flower.core.material.opacity = single
    ? 0.12 + melody * 0.16 + vocals * 0.08
    : 0.55 + melody * 0.35 + vocals * 0.1;
  if (flower.reference) {
    flower.reference.material.uniforms.uTime.value = t;
    flower.reference.material.uniforms.uPulse.value = melody * 0.62 + vocals * 0.28;
    flower.reference.material.uniforms.uAlpha.value = 0.86 + melody * 0.10 + vocals * 0.06;
  }
  flower.group.rotation.z = Math.sin(t * 0.28 + phase) * 0.006;
  flower.head.rotation.z = single ? Math.sin(t * 0.22 + phase) * 0.010 : flower.side * (0.92 + Math.sin(t * 0.42 + phase) * 0.012 + melody * 0.018);
  flower.head.rotation.x = -0.05 + Math.sin(t * 0.31 + phase) * 0.010;
  flower.head.rotation.y = single ? Math.sin(t * 0.18 + phase) * 0.018 : -flower.side * (0.12 + melody * 0.016);
  flower.petals.forEach((petal, i) => {
    const note = Math.max(0, Math.sin(t * 0.7 + i * 1.77 + phase)) * melody;
    const outer = i < 6;
    const baseX = petal.userData.baseScale?.x ?? (outer ? 0.78 : 0.58);
    const baseY = petal.userData.baseScale?.y ?? (outer ? 0.82 : 0.66);
    const baseRot = petal.userData.baseRotation || { x: 0, y: 0, z: petal.rotation.z };
    petal.scale.x = baseX + note * 0.12;
    petal.scale.y = baseY + melody * 0.10 + note * 0.08;
    petal.rotation.x = baseRot.x + note * 0.030 + Math.sin(t * 0.38 + i) * 0.010;
    petal.rotation.y = baseRot.y + Math.sin(t * 0.32 + phase + i * 0.21) * (0.010 + melody * 0.018);
    petal.rotation.z = baseRot.z;
    if (petal.material.uniforms) {
      petal.material.uniforms.uTime.value = t;
      petal.material.uniforms.uPulse.value = melody * 0.55 + note * 0.45;
      petal.material.uniforms.uAlpha.value =
        (petal.userData.baseAlpha ?? 0.5) + melody * 0.16 + note * 0.12;
    } else {
      petal.material.opacity = Math.min(0.24, ((petal.userData.baseAlpha ?? 0.18) * 0.42) + melody * 0.045 + note * 0.030);
    }
  });
  flower.pistil.scale.setScalar(1 + vocals * 0.38 + melody * 0.15);
  flower.pistil.material.opacity = 0.48 + vocals * 0.36 + melody * 0.10;
  flower.centerBeads.forEach((bead, i) => {
    const pulse = Math.max(melody * 0.45, vocals * 0.35) + Math.max(0, Math.sin(t * 1.25 + i * 0.9 + phase)) * melody * 0.22;
    bead.scale.setScalar(1 + pulse * 0.45);
    bead.material.opacity = single ? 0.30 + pulse * 0.28 : 0.46 + pulse * 0.48;
  });
  flower.filaments.forEach((f, i) => {
    const sway = Math.sin(t * 1.15 + phase + i * 0.74) * (0.025 + vocals * 0.12);
    const stretch = 1 + vocals * (0.32 + f.spread * 0.28);
    f.group.rotation.z = f.baseRotation + sway;
    f.group.scale.y = stretch;
    f.tube.material.opacity = 0.24 + vocals * 0.36 + melody * 0.08;
    f.anther.material.opacity = 0.38 + vocals * 0.36;
    f.anther.scale.y = 1.08 + vocals * 0.30;
  });
}

function buildPollen(count) {
  const geo = new THREE.BufferGeometry();
  const mat = new THREE.PointsMaterial({
    size: 0.026,
    color: 0xdbefff,
    transparent: true,
    opacity: 0.72,
    depthWrite: false,
    blending: THREE.AdditiveBlending,
  });
  const points = new THREE.Points(geo, mat);
  points.frustumCulled = false;
  const pollen = { points, geo, positions: new Float32Array(0), seeds: [], count: 0 };
  resetPollen(pollen, count);
  return pollen;
}

function resetPollen(pollen, count) {
  pollen.count = count;
  pollen.positions = new Float32Array(count * 3);
  pollen.seeds = [];
  for (let i = 0; i < count; i++) {
    pollen.seeds.push(Math.random() * 1000);
  }
  pollen.geo.setAttribute('position', new THREE.BufferAttribute(pollen.positions, 3));
}

function updatePollen(pollen, t, vocals, full) {
  const pos = pollen.positions;
  for (let i = 0; i < pollen.count; i++) {
    const seed = pollen.seeds[i];
    const side = seed % 2 < 1 ? -1 : 1;
    const life = (t * (0.08 + vocals * 0.24) + seed * 0.013) % 1;
    const lift = smoothstep(0, 1, life);
    const sway = Math.sin(seed + t * 1.7 + lift * 4.0) * (0.08 + vocals * 0.18);
    const rootX = side * (0.46 + Math.sin(seed) * 0.08);
    pos[i * 3 + 0] = rootX + sway + Math.sin(seed * 1.7 + t) * 0.05;
    pos[i * 3 + 1] = -1.26 + lift * (2.08 + vocals * 0.55);
    pos[i * 3 + 2] = 0.18 + Math.cos(seed + t * 0.8) * (0.14 + full * 0.08);
  }
  pollen.points.material.opacity = 0.12 + vocals * 0.72;
  pollen.points.material.size = 0.016 + vocals * 0.034;
  pollen.geo.attributes.position.needsUpdate = true;
}

function clamp01(v) {
  return Math.max(0, Math.min(1, v || 0));
}

function smoothstep(edge0, edge1, x) {
  const t = clamp01((x - edge0) / (edge1 - edge0));
  return t * t * (3 - 2 * t);
}

window.createScene = createScene;
