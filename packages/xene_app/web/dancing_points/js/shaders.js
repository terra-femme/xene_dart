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
