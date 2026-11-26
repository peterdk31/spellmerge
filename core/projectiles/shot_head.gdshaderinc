// SPDX-License-Identifier: GPL-3.0-or-later
// The drawing of `shot_head.gdshader` (read it for what this draws and how its instance or mesh
// is encoded), in an include so a card's own look that starts from it (`CarrierCard.look_shader`;
// docs/milestones/card-looks.md) includes it and keeps every fix to it, until the card replaces
// the include with code of its own. The including file has `shader_type` and `render_mode`.

// The core is drawn at the art's detail (HEAD_DETAIL art pixels a world unit: ArtDetail.DETAIL, 64 px
// a 32-unit cell; docs/STYLE.md, "The picture and the art's detail"; ART2), a shaded bead lit from the
// top-left: white-hot over its upper-left half (it is a light: shots outshine the floor, docs/STYLE.md
// "Readability"), its body in the light shade, its rim on the lower right in the base shade (and, from
// zoom 2, a one-pixel shadow-shade edge outside that: the shadow shade as an effect's outline,
// docs/STYLE.md "Outline"), and rays out of it a pixel wide. Its shape
// (`q` an art pixel's place from the middle pixel, `a` = abs(q)): HEAD_BODY(q) its distance from the
// middle by the body's own measure (the plain head's is round), HEAD_RAY(a, r, reach) a pixel of its
// rays past the body's radius `r` out to `reach` (the plain head's are a `+`). A card's own head may
// define all three before it includes this (the bolt's faceted diamond and `x`).
#ifndef HEAD_BODY
#define HEAD_BODY(q) length(q)
#define HEAD_RAY(a, r, reach) ((a.x == 0.0 || a.y == 0.0) && a.x + a.y > r && a.x + a.y <= reach)
#endif
const float HEAD_DETAIL = 2.0;

#include "res://core/projectiles/shot_palette.gdshaderinc"
#include "res://core/projectiles/shot_look.gdshaderinc"

// The flags (HEAD_LIVE in projectile_manager.gd): the shot is alive (its core is drawn).
const float HF_LIVE = 1.0;
// The quad kinds (HEAD_Q_* in projectile_manager.gd), in UV.y.
const float Q_LIGHT = 0.0;
const float Q_CORE = 1.0;
// The fragment's modes: a round light, pixels (a square, a cross, a line beside it).
const float M_GLOW = 0.0;
const float M_PIXELS = 2.0;
// A neighbour or a line that is not there.
const vec2 FAR = vec2(1.0e7);

// What the vertex stage hands a pixel (by mode; see `fragment`): the pixel's world position, the
// mode, two numbers and four colours.
varying vec2 world;
varying flat vec4 box;
varying flat float mode;
varying flat vec4 v0;
varying flat vec4 v1;
varying flat vec4 c0;
varying flat vec4 c1;
varying flat vec4 c2;
varying flat vec4 c3;

// ---- Vertices ----

void vertex() {
	float flags = MODEL_MATRIX[1].y;
	vec2 head = MODEL_MATRIX[3].xy;
	// The way it flies (`_write_head`), where a path's numbers once were.
	vec2 way = vec2(MODEL_MATRIX[1].x, MODEL_MATRIX[0].y);
	// The mesh's vertex: its quad kind and corner in UV.y (kind + 0.25 or 0.75), its corner in
	// UV.x; a corner of the triangle is 0 or twice the box.
	float quad = floor(UV.y);
	vec2 corner = vec2(fract(UV.x) > 0.5 ? 2.0 : 0.0, fract(UV.y) > 0.5 ? 2.0 : 0.0);
	Look L = look_from_color(COLOR, INSTANCE_CUSTOM.rgb, 0.0, true);
	// Zoom 0 in the look (`look_core_zoom`): a speck, its core one world pixel; the rest is drawn at 1.
	bool speck = floor(COLOR.r * 255.0 + 0.5) < 4.0;
	float z = L.zoom;
	vec3 b = L.bits;
	bool live = flag_set(flags, HF_LIVE);
	bool lightning = bit_set(b, L_SPARKS);
	bool pull = bit_set(b, L_PULL);
	// The light: lightning flickers, void's is dimmer.
	float flicker = (lightning ? 0.55 + 0.9 * hash_seeded(floor(sim_time * 20.0), 0.0, 21.0, L.seed) : 1.0) * (pull ? 0.6 : 1.0);
	vec3 hue = L.glow;
	vec2 q_lo = vec2(0.0);
	vec2 q_hi = vec2(0.0);
	float m = M_PIXELS;
	vec4 a0 = vec4(0.0);
	vec4 a1 = vec4(FAR, FAR);
	vec4 k0 = vec4(0.0);
	vec4 k1 = vec4(0.0);
	vec4 k2 = vec4(0.0);
	vec4 k3 = vec4(0.0);
	bool shown = false;
	if (live && (quad == Q_LIGHT || quad == Q_CORE)) {
		shown = true;
		vec2 fly = length(way) > 0.01 ? normalize(way) : vec2(1.0, 0.0);
		vec2 at = head;
		if (bit_set(b, L_WEAVE)) {
			// Homing weaves it a pixel either side.
			at += vec2(-fly.y, fly.x) * (triangle(sim_time * 3.0 + L.seed * 0.25) > 0.0 ? 1.0 : 0.0);
		}
		// Its middle art pixel (it moves by art pixels, half world units), in art pixels.
		vec2 px = floor(at * HEAD_DETAIL);
		vec2 mid_world = (px + 0.5) / HEAD_DETAIL;
		if (quad == Q_LIGHT) {
			m = M_GLOW;
			// A speck's light is a smaller one.
			float reach = speck ? 6.0 : 8.0 + 2.0 * z;
			q_lo = mid_world - reach;
			q_hi = mid_world + reach;
			a0 = vec4(mid_world, pull ? 0.45 : 0.0, 6.0);
			a1 = vec4((speck ? 0.6 : 0.8) * flicker, speck ? 2.0 : 3.0 + z, 0.35 * flicker, reach);
			k0 = vec4(hue, 1.0);
		} else {
			// The bead: its body's radius in art pixels (a speck's is its middle pixel and the
			// three right and down of it, one world pixel), its rays a pixel more each zoom past it;
			// pierce lengthens it along the flight with a one-pixel line; void's is a dark heart
			// ringed in pink.
			float r = speck ? 0.0 : 1.5 + 1.1 * z;
			float reach = speck ? 0.0 : r + 1.0 + z;
			float half_size = (reach + 2.0) / HEAD_DETAIL;
			q_lo = mid_world - half_size;
			q_hi = mid_world + half_size;
			a0 = vec4(px, speck ? -1.0 : r, reach);
			if (bit_set(b, L_STREAKS)) {
				a1 = vec4(at, at - fly * (2.0 + z)) * HEAD_DETAIL;
				q_lo = min(q_lo, min(at, at - fly * (2.0 + z)) - 1.0);
				q_hi = max(q_hi, max(at, at - fly * (2.0 + z)) + 1.0);
			}
			k0 = vec4(pull ? OUTLINE : L.hot, 1.0);
			k1 = vec4(pull ? VOID_LIGHT : L.hi, 1.0);
			k2 = vec4(pull ? VOID_BASE : L.mid, 1.0);
			// Void's dark heart (c3's alpha half: its middle dark, never its lit half).
			k3 = vec4(pull ? VOID_BASE : L.lo, pull ? 0.5 : 1.0);
		}
	}
	// Folded away when there is nothing to draw.
	VERTEX = shown ? q_lo + (q_hi - q_lo) * corner : vec2(-1.0e6);
	world = VERTEX;
	box = vec4(q_lo, q_hi);
	mode = m;
	v0 = a0;
	v1 = a1;
	c0 = k0;
	c1 = k1;
	c2 = k2;
	c3 = k3;
}

// ---- Fragments ----
// Small on purpose (core/README.md, "The shot shaders"): a pixel only colours itself from what
// its quad's vertices worked out. No loops, no look kinds, nothing read from the path.

// True when the art pixel at `P` (art pixels) is on the one-pixel line from `a` to `b`, drawn as the
// mockup's lines are: one pixel per step along the longer axis; `along` is how far along it is.
bool on_line(vec2 P, vec2 a, vec2 b, out float along) {
	vec2 ab = b - a;
	float l = length(ab);
	vec2 c = floor(P) + 0.5;
	if (l < 0.5) {
		along = 0.0;
		return all(equal(floor(P), floor(a)));
	}
	vec2 dir = ab / l;
	along = dot(c - a, dir);
	float s = dot(c - a, vec2(-dir.y, dir.x));
	float thin = 0.5 * max(abs(dir.x), abs(dir.y));
	return along >= -0.5 && along <= l + 0.5 && s >= -thin && s < thin;
}

void fragment() {
	vec2 P = world;
	// The art pixel (HEAD_DETAIL a world unit) and its middle, in world units.
	vec2 A = floor(P * HEAD_DETAIL);
	vec2 c = (A + 0.5) / HEAD_DETAIL;
	vec4 colour = vec4(0.0);
	if (mode < M_GLOW + 0.5) {
		// A round light (v0 its middle, the dark it casts and how far; v1 two falloffs).
		float r = length(c - v0.xy);
		float lit = v1.x * falloff(r, v1.y) + v1.z * falloff(r, v1.w);
		colour = vec4(c0.rgb * lit * glow_strength, v0.z * falloff(r, v0.w));
	} else {
		// The bead round art pixel v0.xy, its body's radius v0.z (below 0: a speck) and its rays'
		// reach v0.w; a line v1.xy-v1.zw (art pixels) beside it. c0 white-hot, c1 light, c2 base,
		// c3 shadow.
		vec2 q = A - v0.xy;
		vec2 a = abs(q);
		float d = HEAD_BODY(q);
		float lit = q.x + q.y;
		float along;
		if (v0.z < 0.0) {
			// A speck: one world pixel, its highlight at the top-left.
			colour = q.x >= 0.0 && q.y >= 0.0 && q.x < 2.0 && q.y < 2.0 ? (lit < 0.5 ? c0 : c1) : vec4(0.0);
		} else if (d <= v0.z) {
			// The body: the highlight up and left of the middle, the rim's lower right in the base.
			bool white = all(equal(q, vec2(0.0))) || (d <= v0.z - 1.0 && lit <= 0.0);
			white = c3.a < 0.75 ? d <= max(v0.z - 2.0, 0.0) : white;
			colour = white ? c0 : (d > v0.z - 1.0 && lit > 0.0 ? c2 : c1);
		} else if (HEAD_RAY(a, v0.z, v0.w)) {
			// A ray: light, its tip in the base.
			colour = HEAD_RAY((a + step(vec2(0.5), a)), v0.z, v0.w) ? c1 : c2;
		} else if (d <= v0.z + 1.0 && lit >= 1.0 && v0.z >= 3.0) {
			// A big bead's shadow edge, on the lower right, outside its body.
			colour = vec4(c3.rgb, 1.0);
		} else if (v1.x < 1.0e6 && on_line(A + 0.5, v1.xy, v1.zw, along)) {
			colour = c1;
		}
	}
	// Only the box's pixels: the rest of the triangle is outside the quad.
	bool inside = all(greaterThanEqual(c, box.xy)) && all(lessThan(c, box.zw));
	COLOR = inside ? colour : vec4(0.0);
}
