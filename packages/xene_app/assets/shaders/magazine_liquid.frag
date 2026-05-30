#include <flutter/runtime_effect.glsl>

precision mediump float;

uniform vec2 uResolution;
uniform float uTime;
uniform float uIntensity;
uniform vec3 uAccent;

out vec4 fragColor;

float wave(vec2 uv, float speed, float scale, float phase) {
  return sin((uv.x * scale) + (uv.y * scale * 0.7) + (uTime * speed) + phase);
}

void main() {
  vec2 uv = FlutterFragCoord().xy / uResolution;
  vec2 centered = uv - vec2(0.5);
  float vignette = smoothstep(0.78, 0.12, length(centered));

  float scan = sin((uv.y * uResolution.y * 0.95) + (uTime * 9.0)) * 0.5 + 0.5;
  float shimmer =
      wave(uv, 0.9, 11.0, 0.0) * 0.35 +
      wave(uv.yx, -0.65, 17.0, 1.7) * 0.25 +
      wave(uv + vec2(scan * 0.025, 0.0), 1.25, 27.0, 3.1) * 0.18;

  float glow = smoothstep(0.1, 1.0, shimmer + 0.55) * vignette;
  float pulse = 0.7 + 0.3 * sin(uTime * 1.6);

  vec3 color = uAccent * glow * pulse;
  float alpha = clamp((glow * 0.42 + scan * 0.025) * uIntensity, 0.0, 0.55);
  fragColor = vec4(color, alpha);
}
