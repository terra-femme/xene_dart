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

  const net = buildNodeNetwork();
  scene.add(net.group);

  // Center noise-ball (drums drive it). Luminous white — the reference used
  // 0x000000 which is invisible on the 0x050509 void, so we override to a
  // bright cool-white so it reads inside the brain's central void.
  const blob = buildWireframeBlob({
    color: 0xeaf4ff, radius: 0.5, strokeCount: 30, pointsPerStroke: 130, step: 0.04,
  });
  scene.add(blob.group);

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
    net.group.scale.setScalar(bodyScale);
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

  function update(dt, react, reactSlow, signals, keyEnergies) {
    uniforms.uTime.value += dt;
    const sig = readSignals(signals, react, reactSlow);
    uniforms.uBass.value += (sig.bass - uniforms.uBass.value) * 0.16;
    uniforms.uDrums.value += (sig.drums - uniforms.uDrums.value) * 0.34;
    uniforms.uVocals.value += (sig.vocals - uniforms.uVocals.value) * 0.14;
    uniforms.uMelody.value += (sig.melody - uniforms.uMelody.value) * 0.12;

    tiltX += (targetTiltX - tiltX) * 0.04;
    tiltY += (targetTiltY - tiltY) * 0.04;
    const t = uniforms.uTime.value;

    updateBrainFrame(brain, t, sig, tiltX, tiltY);
    updateNodeNetwork(net, sig, keyEnergies, t);
    updateWireframeBlob(blob, t, dt, sig, rotSpeed, tiltX, tiltY);

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

// ── Node network (base layer) ────────────────────────────────────────────────
// A ring around the brain split into 88 triangular wedge-sections (one per
// piano key), each with its own fill so it can light independently. The outer
// border (line + nodes) is a child group that BASS extrudes radially; the 88
// wedge fills are lit by the melodic stem's per-key spectrum (keyEnergies).
function buildNodeNetwork() {
  const KEYS = 88;
  const rxOut = 2.46, ryOut = 1.78;   // outer border ellipse (surrounds the brain)
  const rxIn = 1.80, ryIn = 1.30;     // inner apex ellipse (just outside the brain)
  const a = (k) => (k / KEYS) * Math.PI * 2 - Math.PI / 2;

  const group = new THREE.Group();
  group.position.set(0, 0.02, -0.02);
  group.renderOrder = 5;

  // --- outer border (bass-extruded): ring line + node points ---
  const borderGroup = new THREE.Group();
  const outerPts = [];
  for (let k = 0; k <= KEYS; k++) {
    outerPts.push(new THREE.Vector3(Math.cos(a(k)) * rxOut, Math.sin(a(k)) * ryOut, 0));
  }
  const borderLine = new THREE.Line(
    new THREE.BufferGeometry().setFromPoints(outerPts),
    new THREE.LineBasicMaterial({ color: 0x8fbfe6, transparent: true, opacity: 0.34, blending: THREE.AdditiveBlending })
  );
  borderGroup.add(borderLine);
  const nodePts = new THREE.Points(
    new THREE.BufferGeometry().setFromPoints(outerPts.slice(0, KEYS)),
    new THREE.PointsMaterial({ size: 0.055, color: 0xbfe6ff, transparent: true, opacity: 0.7, depthWrite: false, sizeAttenuation: true, blending: THREE.AdditiveBlending })
  );
  borderGroup.add(nodePts);
  group.add(borderGroup);

  // --- 88 triangular wedge fills + inward spokes (the network structure) ---
  const fills = [];
  const spokePts = [];
  for (let k = 0; k < KEYS; k++) {
    const a0 = a(k), a1 = a(k + 1), am = (a0 + a1) / 2;
    const verts = new Float32Array([
      Math.cos(a0) * rxOut, Math.sin(a0) * ryOut, 0,
      Math.cos(a1) * rxOut, Math.sin(a1) * ryOut, 0,
      Math.cos(am) * rxIn,  Math.sin(am) * ryIn,  0,
    ]);
    const g = new THREE.BufferGeometry();
    g.setAttribute('position', new THREE.BufferAttribute(verts, 3));
    const mat = new THREE.MeshBasicMaterial({
      color: new THREE.Color(0x14212e), transparent: true, opacity: 0.0,
      side: THREE.DoubleSide, depthWrite: false, blending: THREE.AdditiveBlending,
    });
    const mesh = new THREE.Mesh(g, mat);
    mesh.renderOrder = 6;
    group.add(mesh);
    fills.push(mesh);
    spokePts.push(
      new THREE.Vector3(Math.cos(am) * rxIn, Math.sin(am) * ryIn, 0),
      new THREE.Vector3(Math.cos(am) * rxOut, Math.sin(am) * ryOut, 0)
    );
  }
  const spokes = new THREE.LineSegments(
    new THREE.BufferGeometry().setFromPoints(spokePts),
    new THREE.LineBasicMaterial({ color: 0x4a6a86, transparent: true, opacity: 0.14, blending: THREE.AdditiveBlending })
  );
  group.add(spokes);

  return { group, borderGroup, fills };
}

function updateNodeNetwork(net, sig, keyEnergies, t) {
  // BASS extrudes the exterior border radially (a breathing perimeter).
  const push = 1 + sig.bass * 0.22;
  net.borderGroup.scale.set(push, push, 1);
  net.borderGroup.rotation.z = Math.sin(t * 0.05) * 0.008;

  // MELODIC pitch lights the 88 wedge sections; gamma makes the dominant key pop.
  const fills = net.fills;
  for (let k = 0; k < fills.length; k++) {
    const e = keyEnergies ? keyEnergies[k] : 0;
    const lit = Math.pow(e < 0 ? 0 : e > 1 ? 1 : e, 1.6);
    const mat = fills[k].material;
    mat.opacity = lit * 0.85;
    mat.color.setRGB(0.10 + lit * 0.32, 0.42 + lit * 0.48, 0.66 + lit * 0.34);
  }
}

// A "ball of scribbles": each stroke is a CONTINUOUS polyline (THREE.Line) that
// wanders through a noise field, tangling into a dense ball. This is the correct
// construction for the reference look — NOT SphereGeometry+EdgesGeometry, which
// emits disconnected edge stubs. `basePositions` holds each stroke's rest shape
// so update() can dance the vertices around it without redrawing the walk.
function buildWireframeBlob(opts) {
  const group = new THREE.Group();
  const lines = [];
  const basePositions = [];
  const color = opts.color || 0xeaf4ff;
  const strokeCount = opts.strokeCount || 26;
  const pointsPerStroke = opts.pointsPerStroke || 150;
  const radius = opts.radius || 0.9;
  const step = opts.step || 0.055;

  // Cheap deterministic pseudo-3D noise (trig sum). Enough to bend a walk into
  // organic curves without pulling in a noise library.
  const noise3 = (x, y, z) =>
    Math.sin(x * 1.7 + y * 0.9) * 0.6 +
    Math.cos(y * 1.3 - z * 1.1) * 0.55 +
    Math.sin(z * 1.9 + x * 0.7) * 0.5 +
    Math.sin((x + y + z) * 2.6) * 0.25;

  for (let s = 0; s < strokeCount; s++) {
    const seed = s * 12.9898;
    // Start somewhere in the inner ball so strokes cross the center and tangle.
    let px = (Math.random() * 2 - 1) * radius * 0.45;
    let py = (Math.random() * 2 - 1) * radius * 0.45;
    let pz = (Math.random() * 2 - 1) * radius * 0.45;
    const pts = new Float32Array(pointsPerStroke * 3);

    for (let i = 0; i < pointsPerStroke; i++) {
      pts[i * 3] = px;
      pts[i * 3 + 1] = py;
      pts[i * 3 + 2] = pz;
      // Direction from the noise field — smoothly turning, so the line curls.
      const nx = noise3(px * 2.4 + seed, py * 2.4, pz * 2.4);
      const ny = noise3(py * 2.4 + seed + 31.4, pz * 2.4, px * 2.4);
      const nz = noise3(pz * 2.4 + seed + 57.1, px * 2.4, py * 2.4);
      px += nx * step;
      py += ny * step;
      pz += nz * step;
      // Soft containment: pull back in when the walk strays outside the ball so
      // it stays a ball of scribbles instead of escaping to infinity.
      const d = Math.sqrt(px * px + py * py + pz * pz);
      if (d > radius) {
        const pull = (d - radius) * 0.55;
        px -= (px / d) * pull;
        py -= (py / d) * pull;
        pz -= (pz / d) * pull;
      }
    }

    const geo = new THREE.BufferGeometry();
    geo.setAttribute('position', new THREE.BufferAttribute(pts, 3));
    const mat = new THREE.LineBasicMaterial({
      color,
      transparent: true,
      opacity: 0.55,
      blending: THREE.AdditiveBlending,
      depthWrite: false,
      depthTest: false,
    });
    const line = new THREE.Line(geo, mat);
    line.renderOrder = 60 + s;
    group.add(line);
    lines.push(line);
    basePositions.push(pts.slice());
  }

  return { group, lines, basePositions, radius, size: 0.42 };
}

function updateWireframeBlob(blob, t, dt, sig, rotSpeed, tiltX, tiltY) {
  const bass = sig.bass, drums = sig.drums, full = sig.full;
  blob.group.rotation.y += dt * (0.12 + rotSpeed * 0.30 + full * 0.10);
  blob.group.rotation.x += dt * (0.05 + rotSpeed * 0.15);
  blob.group.rotation.z = tiltY * 0.08;
  // DRUMS also punch the overall scale so a hit is unmistakable, not just subtle.
  blob.group.scale.setScalar((blob.layoutScale || 1) * blob.size * (1 + bass * 0.08 + drums * 0.16));

  // DRUMS drive the dance: displace each vertex around its rest position by an
  // animated noise, amplitude riding the drum transient. At rest (drums≈0) it's
  // a quiet tangle; on a hit the whole scribble writhes.
  const amp = 0.008 + drums * 0.15 + bass * 0.03;
  const w1 = t * 2.1, w2 = t * 1.7, w3 = t * 2.4;
  for (let li = 0; li < blob.lines.length; li++) {
    const line = blob.lines[li];
    const base = blob.basePositions[li];
    const arr = /** @type {any} */ (line.geometry.attributes.position.array);
    for (let i = 0; i < arr.length; i += 3) {
      const bx = base[i], by = base[i + 1], bz = base[i + 2];
      arr[i]     = bx + Math.sin(w1 + bx * 4.0 + li) * amp;
      arr[i + 1] = by + Math.cos(w2 + by * 4.0 + li * 1.3) * amp;
      arr[i + 2] = bz + Math.sin(w3 + bz * 4.0 + li * 0.7) * amp;
    }
    line.geometry.attributes.position.needsUpdate = true;
    line.material.opacity = Math.min(0.9, 0.5 + drums * 0.28 + full * 0.10 + sig.vocals * 0.08);
  }
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
        gl_FragColor = vec4(col, alpha * (0.82 + wave * 0.12));
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
