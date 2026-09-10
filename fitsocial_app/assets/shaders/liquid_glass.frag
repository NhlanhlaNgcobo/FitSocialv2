// Liquid glass: a lens, not a filter.
//
// Frosted glass diffuses what is behind it. This bends it. Every pixel inside
// the pane samples the backdrop at an offset along the surface normal, hardest
// at the rim and falling to nothing through the middle, which is what reads as
// physical thickness rather than fog.
//
// On top of the bend there is a reflection. That is the half that makes a pane
// read as *thick*: real glass shows you what is behind it and what is in front
// of it at the same time, and the ratio between the two is decided by viewing
// angle. See the Fresnel block in main().
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

// How much of the pane is reflection rather than refraction, at its most
// oblique. Zero is the old material: a lens with a lit edge. Push it up and the
// bevel starts showing you the room instead of the feed, which is what glass
// with depth actually does.
//
// Appended after uRimColor for the same reason uRimColor was appended after
// everything else. Do not insert above.
uniform float uReflect;

// The dark half of what the pane reflects -- the floor, in the little
// environment the bevel is standing in. uRimColor is the other half, the sky.
// Together they are the whole world this glass can see: bright above, dark
// below, which on a phone held upright is very nearly true.
uniform vec3 uFloorColor;

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

  // The surface itself. Flat through the middle, turning hard as it approaches
  // the rim -- this one vector drives the reflection, the specular and the
  // meniscus below, which is why all three agree about where the bevel is.
  vec3 N = normalize(vec3(n * bend * 1.6, 1.0));
  vec3 L = normalize(vec3(uLight, 0.65));
  vec3 V = vec3(0.0, 0.0, 1.0);

  // Fresnel. Looking straight down at flat glass you see almost entirely what
  // is behind it; looking along its surface you see almost entirely what is in
  // front. On a pane lying flat on a screen the only place the eye gets an
  // oblique angle is the bevel, so this is what makes the rim of the capsule
  // read as a rolled edge with material in it rather than as a drawn outline.
  float fres = pow(1.0 - abs(N.z), 3.0);

  // What the bevel reflects. R.y is negative where the surface tips toward the
  // top of the screen, so the upper bevel picks up uRimColor and the lower one
  // picks up uFloorColor -- bright above, dark below. That asymmetry is the
  // entire read of thickness: a pane lit evenly all the way round looks like a
  // sticker.
  vec3 R = reflect(-V, N);
  float sky = clamp(0.5 - R.y * 0.5, 0.0, 1.0);
  vec3 env = mix(uFloorColor, uRimColor, sky * sky);
  col = mix(col, env, clamp(fres * uReflect, 0.0, 1.0));

  // Specular: the pane's surface turns hardest at the rim, so that is where it
  // catches the light.
  //
  // Mixed toward uRimColor rather than added onto what is already there. Adding
  // white reads as a lit edge on near-black, and as nothing at all on cream --
  // the ground is already white, so there is no brighter for it to go, and the
  // highlight either vanishes or smears out. A mix cannot overshoot its target,
  // so the same two lines give a white edge on dark and a dark hairline on
  // light purely by what colour they are handed.
  float spec = pow(max(dot(N, L), 0.0), 28.0);
  col = mix(col, uRimColor, clamp(spec * (0.3 + 0.7 * bend) * uSheen, 0.0, 1.0));

  // A second, much broader lobe. The tight one above is a glint; this is the
  // soft sheet of light that lies along a thick edge and gives it length. Two
  // lobes at different widths is most of the difference between plastic and
  // glass.
  float sheet = pow(max(dot(N, L), 0.0), 5.0);
  col = mix(col, uRimColor, clamp(sheet * bend * 0.30 * uSheen * uReflect,
                                  0.0, 1.0));

  // The lit rim: a hairline at the boundary, strongest where it faces the light
  // and fading away where it turns from it.
  float line = 1.0 - smoothstep(0.0, 1.6, abs(d));
  float lit = 0.35 + 0.65 * max(dot(n, uLight), 0.0);
  col = mix(col, uRimColor, clamp(line * lit * 0.85 * uSheen, 0.0, 1.0));

  // The meniscus. Directly opposite the lit rim, just inside the boundary, the
  // glass pools dark -- the shadow its own thickness casts. Without it the pane
  // is lit on one side and simply absent on the other, and the eye reads that
  // as a highlight painted on a flat shape rather than as a solid with two
  // sides to it.
  float away = max(-dot(n, uLight), 0.0);
  col = mix(col, uFloorColor,
            clamp(line * away * 0.45 * uReflect, 0.0, 1.0));

  fragColor = vec4(col, 1.0);
}
