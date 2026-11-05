// SPDX-License-Identifier: GPL-3.0-or-later
shader_type canvas_item;
// world_vertex_coords: VERTEX is in world space in vertex(), so each quad is placed in the world
// and every pixel can be found on the world's pixel grid (nothing else moves its vertices).
render_mode blend_premul_alpha, world_vertex_coords;

// A shot in flight (the projectile manager's shot batches; core/README.md, "The shot shaders"):
// its core and the core's light. A shot's tail is motes since the owner's pick of 2026-11-05
// (docs/milestones/spell-spectacle-2.md, S5 step 4: the projectile manager lays it as births, one
// of three tail kinds a shot, and Feel's motes throw them), and so are the card particles it gives
// off (S3) and a dash's speed streaks (S5); the tail this shader once drew from each shot's path
// (a texture of the paths) is gone with the paths. Everything is drawn on the world's pixel grid,
// axis-aligned: the core is a `+` whatever way the shot flies, as the mockup draws it.
//
// PARTICLES ARE GEOMETRY (the owner, 2026-10-29). Windows browsers compile WebGL through
// Direct3D, and a big, branchy fragment stage took the compiler about 90 s on a real GPU, until
// the browser killed its GPU process. So the VERTEX stage does the work and the fragment stage only
// colours a pixel of its own quad: a few small modes, no loops, no kinds.
// A shot is one instance of a mesh (`head_mesh` in projectile_manager.gd) of small quads, each
// told in its UV which QUAD KIND (Q_*) it is. The vertex shader puts each quad round the head, or
// folds it away:
//   Q_LIGHT  the core's light (and void's dark heart);
//   Q_CORE        the core: a white-hot `+`, pierce's run, void's dark heart.
// The light is drawn first (added; void's dark heart dims what is under it), the core last.
// A quad is one triangle (performance, 2026-11-02: every vertex runs the whole vertex stage, and
// three are a quarter less than four): its corners are the box's low corner and twice the box
// along each axis, so the box is inside it, and the fragment stage cuts it to the box (`box`), a
// pixel in it when its centre is, as a square's two triangles take it.
// The instance carries its data in its transform (the batch must sit untransformed at the
// origin): origin the head (where the shot is drawn this frame), x axis (-1, the way it flies' y),
// y axis (the way it flies' x, HF_* flags). The colour and the custom data are the look
// (`shot_look.gdshaderinc`; worked out per vertex here, `look_from_color`).

#include "res://core/projectiles/shot_palette.gdshaderinc"
#include "res://core/projectiles/shot_look.gdshaderinc"

// The flags (HEAD_LIVE, HEAD_ORBIT in projectile_manager.gd): the shot is alive (its core is drawn), an orbit
// shot.
const float HF_LIVE = 1.0;
const float HF_ORBIT = 2.0;
// The quad kinds (HEAD_Q_* in projectile_manager.gd), in UV.y.
const float Q_LIGHT = 0.0;
const float Q_CORE = 1.0;
// The fragment's modes: a round light, pixels (a square, a cross, a line beside it).
const float M_GLOW = 0.0;
const float M_PIXELS = 2.0;
// A neighbour or a line that is not there.
const vec2 FAR = vec2(1.0e7);

// What the vertex stage hands a pixel (by mode; see `fragment`): the pixel's world position, the
// mode, two numbers and three colours.
varying vec2 world;
varying flat vec4 box;
varying flat float mode;
varying flat vec4 v0;
varying flat vec4 v1;
varying flat vec4 c0;
varying flat vec4 c1;
varying flat vec4 c2;

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
	// Zoom 0 in the look (`look_core_zoom`): a speck, its core one pixel; the rest is drawn at 1.
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
	bool shown = false;
	if (live && (quad == Q_LIGHT || quad == Q_CORE)) {
		shown = true;
		vec2 fly = length(way) > 0.01 ? normalize(way) : vec2(1.0, 0.0);
		vec2 at = head;
		if (bit_set(b, L_WEAVE)) {
			// Homing weaves it a pixel either side.
			at += vec2(-fly.y, fly.x) * (triangle(sim_time * 3.0 + L.seed * 0.25) > 0.0 ? 1.0 : 0.0);
		}
		vec2 px = floor(at);
		if (quad == Q_LIGHT) {
			m = M_GLOW;
			// A speck's light is a smaller one.
			float reach = speck ? 6.0 : 8.0 + 2.0 * z;
			q_lo = px + 0.5 - reach;
			q_hi = px + 0.5 + reach;
			a0 = vec4(px + 0.5, pull ? 0.45 : 0.0, 6.0);
			a1 = vec4((speck ? 0.6 : 0.8) * flicker, speck ? 2.0 : 3.0 + z, 0.35 * flicker, reach);
			k0 = vec4(hue, 1.0);
		} else {
			// A white-hot pixel with four round it, a pixel more each side a zoom (a speck's is
			// the pixel alone); pierce lengthens it along the flight; void's is a dark heart
			// ringed in pink.
			float half_size = 3.0 + 2.0 * z;
			q_lo = px - half_size;
			q_hi = px + half_size + 1.0;
			a0 = vec4(px, 1.0, speck ? 0.0 : z);
			if (bit_set(b, L_STREAKS)) {
				a1 = vec4(at, at - fly * (2.0 + z));
			}
			k0 = vec4(pull ? OUTLINE : L.hot, 1.0);
			k1 = vec4(pull ? VOID_LIGHT : L.hi, 1.0);
			k2 = pull ? vec4(VOID_BASE, 1.0) : vec4(0.0);
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
}

// ---- Fragments ----
// Small on purpose (core/README.md, "The shot shaders"): a pixel only colours itself from what
// its quad's vertices worked out. No loops, no look kinds, nothing read from the path.

// True when the pixel at `P` is on the one-pixel line from `a` to `b`, drawn as the mockup's
// lines are: one pixel per step along the longer axis; `along` is how far along it is.
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
	vec2 c = floor(P) + 0.5;
	vec4 colour = vec4(0.0);
	if (mode < M_GLOW + 0.5) {
		// A round light (v0 its middle, the dark it casts and how far; v1 two falloffs).
		float r = length(c - v0.xy);
		float lit = v1.x * falloff(r, v1.y) + v1.z * falloff(r, v1.w);
		colour = vec4(c0.rgb * lit * glow_strength, v0.z * falloff(r, v0.w));
	} else {
		// Pixels: a square of v0.z from v0.xy in c0, a cross of arms v0.w round its pixel and a
		// line v1.xy-v1.zw in c1, the pixels between the arms in c2.
		vec2 d = floor(P) - v0.xy;
		vec2 a = abs(d);
		float along;
		if (d.x >= 0.0 && d.y >= 0.0 && d.x < v0.z && d.y < v0.z) {
			colour = c0;
		} else if (((a.x == 0.0 || a.y == 0.0) && a.x + a.y <= v0.w) || (v1.x < 1.0e6 && on_line(P, v1.xy, v1.zw, along))) {
			colour = c1;
		} else if (a.x == 1.0 && a.y == 1.0) {
			colour = c2;
		}
	}
	// Only the box's pixels: the rest of the triangle is outside the quad.
	bool inside = all(greaterThanEqual(c, box.xy)) && all(lessThan(c, box.zw));
	COLOR = inside ? colour : vec4(0.0);
}
