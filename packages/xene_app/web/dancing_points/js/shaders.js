// GLSL for the dancing point-sphere.
// 3D simplex noise (Ashima / webgl-noise, public domain) is embedded for the warp field.

const SNOISE = `
vec4 permute(vec4 x){return mod(((x*34.0)+1.0)*x, 289.0);}
vec4 taylorInvSqrt(vec4 r){return 1.79284291400159 - 0.85373472095314 * r;}
float snoise(vec3 v){
  const vec2 C = vec2(1.0/6.0, 1.0/3.0);
  const vec4 D = vec4(0.0, 0.5, 1.0, 2.0);
  vec3 i  = floor(v + dot(v, C.yyy));
  vec3 x0 = v - i + dot(i, C.xxx);
  vec3 g = step(x0.yzx, x0.xyz);
  vec3 l = 1.0 - g;
  vec3 i1 = min(g.xyz, l.zxy);
  vec3 i2 = max(g.xyz, l.zxy);
  vec3 x1 = x0 - i1 + 1.0 * C.xxx;
  vec3 x2 = x0 - i2 + 2.0 * C.xxx;
  vec3 x3 = x0 - 1.0 + 3.0 * C.xxx;
  i = mod(i, 289.0);
  vec4 p = permute(permute(permute(
            i.z + vec4(0.0, i1.z, i2.z, 1.0))
          + i.y + vec4(0.0, i1.y, i2.y, 1.0))
          + i.x + vec4(0.0, i1.x, i2.x, 1.0));
  float n_ = 1.0/7.0;
  vec3 ns = n_ * D.wyz - D.xzx;
  vec4 j = p - 49.0 * floor(p * ns.z *ns.z);
  vec4 x_ = floor(j * ns.z);
  vec4 y_ = floor(j - 7.0 * x_);
  vec4 x = x_ *ns.x + ns.yyyy;
  vec4 y = y_ *ns.x + ns.yyyy;
  vec4 h = 1.0 - abs(x) - abs(y);
  vec4 b0 = vec4(x.xy, y.xy);
  vec4 b1 = vec4(x.zw, y.zw);
  vec4 s0 = floor(b0)*2.0 + 1.0;
  vec4 s1 = floor(b1)*2.0 + 1.0;
  vec4 sh = -step(h, vec4(0.0));
  vec4 a0 = b0.xzyw + s0.xzyw*sh.xxyy;
  vec4 a1 = b1.xzyw + s1.xzyw*sh.zzww;
  vec3 p0 = vec3(a0.xy, h.x);
  vec3 p1 = vec3(a0.zw, h.y);
  vec3 p2 = vec3(a1.xy, h.z);
  vec3 p3 = vec3(a1.zw, h.w);
  vec4 norm = taylorInvSqrt(vec4(dot(p0,p0), dot(p1,p1), dot(p2,p2), dot(p3,p3)));
  p0 *= norm.x; p1 *= norm.y; p2 *= norm.z; p3 *= norm.w;
  vec4 m = max(0.6 - vec4(dot(x0,x0), dot(x1,x1), dot(x2,x2), dot(x3,x3)), 0.0);
  m = m * m;
  return 42.0 * dot(m*m, vec4(dot(p0,x0), dot(p1,x1), dot(p2,x2), dot(p3,x3)));
}
`;

window.POINT_VERT = `
precision highp float;
${SNOISE}
attribute float aDelay;   // 0..1 per-point lag -> trailing
attribute float aRnd;     // per-point random
uniform float uTime;
uniform float uReact;      // fast envelope
uniform float uReactSlow;  // slow / lingering envelope
uniform float uWarp;       // warp intensity
uniform float uNoiseScale;
uniform float uSize;
uniform float uScale;      // viewport size factor
uniform float uIdle;       // 0 playing, 1 idle breathing
uniform int   uMode;       // 0 shear, 1 burst, 2 ripple, 3 shards
varying float vGlow;

void main(){
  vec3 pos = position;
  vec3 nrm = normalize(pos);
  float t = uTime;

  // points with higher delay follow the slow envelope -> they linger/trail
  float react = mix(uReact, uReactSlow, aDelay);

  vec3 disp = vec3(0.0);

  // ---- idle breathing: gentle tangential drift so the sphere stays alive ----
  vec3 tA0 = normalize(cross(nrm, vec3(0.0, 1.0, 0.0) + 0.0001));
  vec3 tB0 = cross(nrm, tA0);
  float ib = snoise(pos * 1.4 + t * 0.18);
  disp += (tA0 * ib + tB0 * snoise(pos * 1.4 + 31.0 - t * 0.18)) * 0.03 * uIdle;

  if(uMode == 0){
    // SHEAR — sideways noise field, snaps back on decay (the hero look)
    float n1 = snoise(pos * uNoiseScale + t * 0.6);
    float n2 = snoise(pos * uNoiseScale + 100.0 - t * 0.6);
    disp += (tA0 * n1 + tB0 * n2) * react * uWarp;
    disp += nrm * snoise(pos * uNoiseScale * 3.0 + t * 4.0) * react * uWarp * 0.25;
  } else if(uMode == 1){
    // BURST — explosive radial push outward
    float n1 = 0.5 + 0.5 * snoise(pos * uNoiseScale + t * 0.5);
    disp += nrm * react * uWarp * (0.55 + n1);
    disp += (tA0 * snoise(pos*uNoiseScale*2.0+t)) * react * uWarp * 0.2;
  } else if(uMode == 2){
    // RIPPLE — wave traveling across the sphere
    float w = sin(pos.y * 4.2 - t * 3.0 + aRnd * 6.2831);
    float w2 = sin(dot(pos, vec3(2.0,0.0,3.0)) - t * 2.0);
    disp += nrm * (w * 0.7 + w2 * 0.3) * react * uWarp;
  } else {
    // SHARDS — quantized glitch displacement along an axis
    float q = floor(aRnd * 6.0);
    vec3 axis = q < 2.0 ? vec3(1.0,0.0,0.0) : (q < 4.0 ? vec3(0.0,1.0,0.0) : vec3(0.0,0.0,1.0));
    float s = step(0.5, fract(aRnd * 13.0)) * 2.0 - 1.0;
    float pulse = step(0.55, fract(react * 2.7 + aRnd));
    disp += axis * s * react * uWarp * (0.45 + pulse * 0.9);
    disp += nrm * (fract(aRnd*97.0) - 0.5) * react * uWarp * 0.3;
  }

  vec3 finalPos = pos + disp;
  vGlow = clamp(react, 0.0, 1.0);

  vec4 mv = modelViewMatrix * vec4(finalPos, 1.0);
  gl_Position = projectionMatrix * mv;
  gl_PointSize = uSize * (uScale / -mv.z) * (1.0 + react * 0.7);
}
`;

window.POINT_FRAG = `
precision highp float;
uniform vec3 uColor;
uniform vec3 uColorHot;
varying float vGlow;
void main(){
  vec2 c = gl_PointCoord - 0.5;
  float d = length(c);
  if(d > 0.5) discard;
  // soft core + faint halo
  float core = smoothstep(0.5, 0.0, d);
  float a = core;
  vec3 col = mix(uColor, uColorHot, vGlow);
  // brighten on hit
  col *= (1.0 + vGlow * 0.8);
  gl_FragColor = vec4(col, a);
}
`;

window.RESONANCE_BLOB_VERT = `
precision highp float;
uniform float uTime;
uniform float uBass;
uniform float uDrums;
uniform float uVocals;
uniform float uMelody;
uniform float uWarp;
uniform float uSize;
uniform float uIdle;
uniform int uMode;
varying vec3 vNormalW;
varying vec3 vPosition;
varying vec3 vPosW;
varying float vDisplacement;
varying float vPulse;

void main(){
  float stemPulse = clamp(uBass * 0.55 + uDrums * 0.28 + uMelody * 0.18 + uVocals * 0.14, 0.0, 1.0);
  float morphSpeed = 0.92 + uMelody * 0.30 + uDrums * 0.16;
  float t = uTime * morphSpeed;

  float x = position.x;
  float y = position.y;
  float z = position.z;
  float noise1 = sin(x * 2.0 + t * 0.8) * cos(y * 2.0 + t * 0.6) * sin(z * 2.0);
  float noise2 = cos(x * 3.0 - t * 0.5) * sin(y * 3.0 + t * 0.4) * 0.5;
  float noise3 = sin(x * 5.0 + y * 3.0 + t * 0.3) * 0.25;
  float breath = sin(uTime * 0.75 + y * 1.35) * 0.5 + 0.5;
  float displacement = 0.18 + uWarp * 0.08 + stemPulse * 0.10;
  float disp = 1.0 + (noise1 + noise2 + noise3) * displacement;
  disp += uBass * 0.075 + uIdle * 0.018 * breath;
  disp += uDrums * 0.026 * sin(length(position.xy) * 9.0 - uTime * 5.5);

  vec3 p = position * disp * uSize;
  p.y *= 0.96 + sin(t * 0.28 + x * 1.35) * 0.025;
  p.x *= 1.0 + cos(t * 0.22 + y * 1.1) * 0.018;

  vec4 world = modelMatrix * vec4(p, 1.0);
  vPosition = position;
  vPosW = world.xyz;
  vNormalW = normalize(mat3(modelMatrix) * normalize(normal + position * (disp - 1.0) * 0.55));
  vDisplacement = disp;
  vPulse = stemPulse;
  gl_Position = projectionMatrix * modelViewMatrix * vec4(p, 1.0);
}
`;

window.RESONANCE_BLOB_FRAG = `
precision highp float;
uniform vec3 uColor1;
uniform vec3 uColor2;
uniform vec3 uColor3;
uniform float uTime;
uniform float uBass;
uniform float uDrums;
uniform float uVocals;
uniform float uMelody;
varying vec3 vNormalW;
varying vec3 vPosition;
varying vec3 vPosW;
varying float vDisplacement;
varying float vPulse;

vec3 bassHash3(vec3 p3) {
  p3 = fract(p3 * vec3(0.1031, 0.11369, 0.13787));
  p3 += dot(p3, p3.yxz + 19.19);
  return -1.0 + 2.0 * fract(vec3(
    (p3.x + p3.y) * p3.z,
    (p3.x + p3.z) * p3.y,
    (p3.y + p3.z) * p3.x
  ));
}

float bassPerlin(vec3 p) {
  vec3 pi = floor(p);
  vec3 pf = p - pi;
  vec3 w = pf * pf * (3.0 - 2.0 * pf);

  return mix(
    mix(
      mix(
        dot(pf - vec3(0.0, 0.0, 0.0), bassHash3(pi + vec3(0.0, 0.0, 0.0))),
        dot(pf - vec3(1.0, 0.0, 0.0), bassHash3(pi + vec3(1.0, 0.0, 0.0))),
        w.x),
      mix(
        dot(pf - vec3(0.0, 0.0, 1.0), bassHash3(pi + vec3(0.0, 0.0, 1.0))),
        dot(pf - vec3(1.0, 0.0, 1.0), bassHash3(pi + vec3(1.0, 0.0, 1.0))),
        w.x),
      w.z),
    mix(
      mix(
        dot(pf - vec3(0.0, 1.0, 0.0), bassHash3(pi + vec3(0.0, 1.0, 0.0))),
        dot(pf - vec3(1.0, 1.0, 0.0), bassHash3(pi + vec3(1.0, 1.0, 0.0))),
        w.x),
      mix(
        dot(pf - vec3(0.0, 1.0, 1.0), bassHash3(pi + vec3(0.0, 1.0, 1.0))),
        dot(pf - vec3(1.0, 1.0, 1.0), bassHash3(pi + vec3(1.0, 1.0, 1.0))),
        w.x),
      w.z),
    w.y);
}

float bassNoiseAbs(vec3 p) {
  float f = 0.0;
  p *= 3.0;
  f += 1.0000 * abs(bassPerlin(p)); p *= 2.0;
  f += 0.5000 * abs(bassPerlin(p)); p *= 2.6;
  f += 0.2500 * abs(bassPerlin(p)); p *= 3.2;
  f += 0.1250 * abs(bassPerlin(p)); p *= 3.8;
  f += 0.0625 * abs(bassPerlin(p));
  return f;
}

void main(){
  vec3 N = normalize(vNormalW);
  vec3 V = normalize(cameraPosition - vPosW);
  float t = uTime * 0.3;
  float fresnel = pow(1.0 - max(dot(N, V), 0.0), 2.0);
  float band1 = sin(t + vPosition.y * 2.0 + uBass * 0.9) * 0.5 + 0.5;
  float band2 = cos(t * 0.7 + vPosition.x * 1.5 + uMelody * 1.1) * 0.5 + 0.5;
  float innerBand = sin(vPosition.x * 3.7 + vPosition.y * 2.4 + vPosition.z * 1.6 + t * 1.8) * 0.5 + 0.5;
  float innerNoise = bassNoiseAbs(vPosition * 2.4 + vec3(t * 1.1, -t * 0.7, t * 0.45));
  float innerGlow = smoothstep(0.18, 0.68, innerNoise + innerBand * 0.42);
  float bassMotion = sin(uTime * 0.10) * cos(uTime * 0.10) * 5.0;
  vec3 bassDomain = vec3(
    vPosition.xy * vec2(2.2, 1.65) + N.xy * 0.75,
    bassMotion + vPosition.z * 2.4
  );
  float electricField = 0.88 * bassNoiseAbs(bassDomain);
  float electricRadius = length(vPosition.xy * vec2(1.0, 0.82)) - 0.36;
  float electricMass = clamp(1.0 - (electricField + electricRadius), 0.0, 1.0);
  float electricBands = electricMass;
  for(int i = 0; i < 7; i++){
    float level = 0.42 + float(i) * 0.085;
    electricBands -= step(level, electricBands) * 0.055;
  }
  float bassCurrent = clamp(electricBands + 0.72 - 2.55 * electricField, 0.0, 1.0);
  float bassDrive = smoothstep(0.03, 0.88, uBass) * 0.92 + 0.18;

  vec3 col = mix(uColor1, uColor2, band1);
  col = mix(col, uColor3, band2 * (0.46 + uVocals * 0.14));
  col = mix(col, col * 1.30 + uColor2 * 0.20, innerGlow * 0.30);
  vec3 bassBlue = vec3(0.35, 0.52, 0.82);
  vec3 bassIce = vec3(0.82, 0.93, 1.0);
  vec3 innerViolet = vec3(0.58, 0.42, 1.00);
  col = mix(col, bassBlue, bassCurrent * bassDrive * 0.34);

  vec3 lightDir = normalize(vec3(1.0, 1.0, 1.0));
  float diffuse = max(dot(N, lightDir), 0.0);
  float specular = pow(max(dot(reflect(-lightDir, N), V), 0.0), 32.0);
  float glass = 0.70 + vDisplacement * 0.13 + vPulse * 0.10;
  vec3 rimTint = mix(uColor3, uColor2, band1);
  vec3 specTint = mix(vec3(0.82, 0.90, 1.0), uColor3, 0.42);

  col *= glass * (0.84 + diffuse * 0.12);
  col += innerViolet * innerGlow * (0.13 + bassDrive * 0.20);
  col += bassIce * bassCurrent * bassDrive * (0.36 + fresnel * 0.22);
  col += rimTint * fresnel * (0.14 + uVocals * 0.13);
  col += specTint * specular * (0.08 + uDrums * 0.12 + uBass * 0.08);
  col = pow(col, vec3(1.02));
  gl_FragColor = vec4(col, 1.0);
}
`;
