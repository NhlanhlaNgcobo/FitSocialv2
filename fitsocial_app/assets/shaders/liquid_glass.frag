// Liquid glass: a lens, not a filter.
//
// Frosted glass diffuses what is behind it. This bends it. Every pixel inside
// the pane samples the backdrop at an offset along the surface normal, hardest
// at the rim and falling to nothing through the middle, which is what reads as
// physical thickness rather than fog.
//
// Bound through ImageFilter.shader, which fixes two things about this file:
// uSize must be the first uniform (the engine writes the bound texture's size
// into it), and the first sampler2D is the filter input (the engine binds the
// backdrop into it -- never set it from Dart).

#include <flutter/runtime_effect.glsl>

precision highp float;

uniform vec2 uSize;

// Corner radii in Flutter's order: top-left, top-right, bottom-right,
// bottom-left. Four rather than one so a bottom sheet -- round on top, square
// where it meets the screen edge -- is the same material as a card.
uniform vec4 uRadii;

// How far the rim drags the backdrop inward, in pixels.
uniform float uRefraction;

// How deep into the pane the bend reaches. Past this the glass is flat and the
// backdrop passes through undisplaced.
uniform float uEdge;

// Per-channel spread at the lens edge. The detail that stops this reading as a
// photo filter.
uniform float uAberration;

// Direction the light comes from. Drives both the specular and which side of
// the rim is lit.
uniform vec2 uLight;

// The fill that buys legibility. Liquid glass holds text with refraction and a
// rim, so this stays low -- past about 0.2 it is fog and the bend stops being
// visible at all.
uniform float uTint;
uniform vec3 uTintColor;

// Scales the specular and the rim together, so a theme can dim the highlights
// without touching the optics.
uniform float uSheen;

// What the rim and the specular tend toward. White on the dark theme, near
// black on the light one -- see the note in main(), which is the whole reason
// this is a uniform and not a constant.
//
// Declared last on purpose. The engine lays uniforms out in declaration order,
// so appending here leaves every existing float index where it was; inserting
// above would silently shift all of them.
uniform vec3 uRimColor;

uniform sampler2D uBackdrop;

out vec4 fragColor;

// Inigo Quilez's rounded box, with the corner selection rewritten for a y-down
// space: here p.y greater than zero is the *bottom* of the pane, not the top.
float sdRoundBox(vec2 p, vec2 b, vec4 radii) {
  vec2 pair = (p.x > 0.0) ? vec2(radii.z, radii.y) : vec2(radii.w, radii.x);
  float r = (p.y > 0.0) ? pair.x : pair.y;
  vec2 q = abs(p) - b + r;
  return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - r;
}

float shape(vec2 p) {
  vec2 halfSize = uSize * 0.5;
  return sdRoundBox(p - halfSize, halfSize, uRadii);
}

vec3 backdropAt(vec2 px) {
  vec2 uv = px / uSize;
  // Impeller's GLES backend hands the texture over with the y-axis reversed.
#ifdef IMPELLER_TARGET_OPENGLES
  uv.y = 1.0 - uv.y;
#endif
  return texture(uBackdrop, clamp(uv, vec2(0.0), vec2(1.0))).rgb;
}

void main() {
  vec2 px = FlutterFragCoord().xy;
  float d = shape(px);

  // The caller clips to this same rounded rect, so anything out here is a
  // fringe pixel. Pass it through rather than inventing a colour for it.
  if (d > 0.0) {
    fragColor = vec4(backdropAt(px), 1.0);
    return;
  }

  // Outward normal, by central difference on the distance field. Cheaper and
  // steadier than an analytic normal across the rounded corners.
  vec2 e = vec2(1.0, 0.0);
  vec2 n = normalize(vec2(
    shape(px + e.xy) - shape(px - e.xy),
    shape(px + e.yx) - shape(px - e.yx)
  ) + vec2(1e-6));

  // Thickness profile. Squared so the bend stays an edge event instead of
  // warping the middle of the pane.
  float rim = 1.0 - smoothstep(0.0, max(uEdge, 0.001), -d);
  float bend = rim * rim;

  vec2 off = n * bend * uRefraction;
  vec3 col;
  col.r = backdropAt(px + off * (1.0 + uAberration * 0.10)).r;
  col.g = backdropAt(px + off).g;
  col.b = backdropAt(px + off * (1.0 - uAberration * 0.10)).b;

  col = mix(col, uTintColor, uTint);

  // Specular: the pane's surface turns hardest at the rim, so that is where it
  // catches the light.
  //
  // Mixed toward uRimColor rather than added onto what is already there. Adding
  // white reads as a lit edge on near-black, and as nothing at all on cream --
  // the ground is already white, so there is no brighter for it to go, and the
  // highlight either vanishes or smears out. A mix cannot overshoot its target,
  // so the same two lines give a white edge on dark and a dark hairline on
  // light purely by what colour they are handed.
  vec3 N = normalize(vec3(n * bend * 1.6, 1.0));
  vec3 L = normalize(vec3(uLight, 0.65));
  float spec = pow(max(dot(N, L), 0.0), 28.0);
  col = mix(col, uRimColor, clamp(spec * (0.3 + 0.7 * bend) * uSheen, 0.0, 1.0));

  // The lit rim: a hairline at the boundary, strongest where it faces the light
  // and fading away where it turns from it.
  float line = 1.0 - smoothstep(0.0, 1.6, abs(d));
  float lit = 0.35 + 0.65 * max(dot(n, uLight), 0.0);
  col = mix(col, uRimColor, clamp(line * lit * 0.85 * uSheen, 0.0, 1.0));

  fragColor = vec4(col, 1.0);
}
