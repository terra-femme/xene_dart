// Three.js point-sphere. Points sit on a Fibonacci sphere; a ShaderMaterial
// warps them per the selected mode/react values. Factory returns a small API
// the app loop drives each frame.

function createScene(canvas) {
  const renderer = new THREE.WebGLRenderer({ canvas, antialias: true, alpha: false });
  renderer.setClearColor(0x07070a, 1);
  renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2));

  const scene = new THREE.Scene();
  const camera = new THREE.PerspectiveCamera(45, 1, 0.1, 100);
  camera.position.set(0, 0, 4.2);

  const RADIUS = 1.45;

  const uniforms = {
    uTime:      { value: 0 },
    uReact:     { value: 0 },
    uReactSlow: { value: 0 },
    uWarp:      { value: 0.8 },
    uNoiseScale:{ value: 1.6 },
    uSize:      { value: 0.7 },
    uScale:     { value: 600 },
    uIdle:      { value: 1 },
    uMode:      { value: 0 },
    uColor:     { value: new THREE.Color('#dfe6ee') },
    uColorHot:  { value: new THREE.Color('#bfe6f5') },
  };

  const material = new THREE.ShaderMaterial({
    uniforms,
    vertexShader: window.POINT_VERT,
    fragmentShader: window.POINT_FRAG,
    transparent: true,
    depthWrite: false,
    blending: THREE.AdditiveBlending,
  });

  let points = null;

  function buildGeometry(count) {
    const positions = new Float32Array(count * 3);
    const delays = new Float32Array(count);
    const rnds = new Float32Array(count);
    const GA = Math.PI * (3 - Math.sqrt(5)); // golden angle
    for (let i = 0; i < count; i++) {
      const y = 1 - (i / (count - 1)) * 2;
      const r = Math.sqrt(Math.max(0, 1 - y * y));
      const theta = i * GA;
      const x = Math.cos(theta) * r;
      const z = Math.sin(theta) * r;
      positions[i * 3 + 0] = x * RADIUS;
      positions[i * 3 + 1] = y * RADIUS;
      positions[i * 3 + 2] = z * RADIUS;
      delays[i] = Math.pow(Math.random(), 1.5); // bias toward small lag, some long
      rnds[i] = Math.random();
    }
    const geo = new THREE.BufferGeometry();
    geo.setAttribute('position', new THREE.BufferAttribute(positions, 3));
    geo.setAttribute('aDelay', new THREE.BufferAttribute(delays, 1));
    geo.setAttribute('aRnd', new THREE.BufferAttribute(rnds, 1));
    return geo;
  }

  function regen(count) {
    if (points) {
      points.geometry.dispose();
      scene.remove(points);
    }
    const geo = buildGeometry(count);
    points = new THREE.Points(geo, material);
    points.frustumCulled = false;
    scene.add(points);
  }

  regen(6000);

  // gentle auto-rotate + subtle pointer parallax
  let rotSpeed = 0.18;
  let targetTiltX = 0, targetTiltY = 0;
  window.addEventListener('pointermove', (e) => {
    const nx = (e.clientX / window.innerWidth) * 2 - 1;
    const ny = (e.clientY / window.innerHeight) * 2 - 1;
    targetTiltY = nx * 0.25;
    targetTiltX = ny * 0.18;
  });

  function resize() {
    const w = canvas.clientWidth || window.innerWidth;
    const h = canvas.clientHeight || window.innerHeight;
    renderer.setSize(w, h, false);
    camera.aspect = w / h;
    camera.updateProjectionMatrix();
    // point-size scale tied to viewport height & fov
    const fov = camera.fov * Math.PI / 180;
    uniforms.uScale.value = (h / (2 * Math.tan(fov / 2))) * 0.014;
  }
  window.addEventListener('resize', resize);
  window.addEventListener('load', resize);
  resize();
  requestAnimationFrame(resize);
  setTimeout(resize, 250);

  let tilt = { x: 0, y: 0 };

  function update(dt, react, reactSlow) {
    uniforms.uTime.value += dt;
    uniforms.uReact.value = react;
    uniforms.uReactSlow.value = reactSlow;

    points.rotation.y += rotSpeed * dt;
    tilt.x += (targetTiltX - tilt.x) * 0.04;
    tilt.y += (targetTiltY - tilt.y) * 0.04;
    points.rotation.x = tilt.x;
    camera.position.x = tilt.y * 0.8;
    camera.lookAt(0, 0, 0);

    renderer.render(scene, camera);
  }

  return {
    update,
    resize,
    regen,
    setMode: (m) => { uniforms.uMode.value = m; },
    setWarp: (w) => { uniforms.uWarp.value = w; },
    setNoiseScale: (n) => { uniforms.uNoiseScale.value = n; },
    setSize: (s) => { uniforms.uSize.value = s; },
    setIdle: (v) => { uniforms.uIdle.value = v; },
    setRotation: (r) => { rotSpeed = r; },
    setColors: (base, hot) => {
      uniforms.uColor.value.set(base);
      uniforms.uColorHot.value.set(hot);
    },
  };
}

window.createScene = createScene;
