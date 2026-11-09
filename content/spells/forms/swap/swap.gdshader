// SPDX-License-Identifier: GPL-3.0-or-later
shader_type canvas_item;
// world_vertex_coords: VERTEX is in world space in vertex(), so each quad is placed in the world
// and every pixel can be found on the world's pixel grid (nothing else moves its vertices).
render_mode blend_premul_alpha, world_vertex_coords;

// A swap's charm in flight, the chasing pair (content/spells/forms/swap/: its card's own look,
// `FormBase.look_shader`; docs/milestones/card-looks.md; the owner's pick, 2026-11-09): two sparks
// chasing each other round a tight circle as it flies, one white-hot and one in its light shade, each
// with a short trail behind it cooling to its shadow: two things trading places, shown in the shot.
// The sparks and their trails are twinkling motes, as the ward's (`twinkle_px`). Every infusion shows
// (its palette): a spell of two to four infusions has a spark an infusion chasing round the circle,
// each in its own colours.
// The trade itself is its card's `trade` cue. A copy of the plain head
// (`core/projectiles/shot_head.gdshader`: read it for the instance, the quad kinds and why the
// fragment stage stays small) with its core replaced by the pair: the same mesh of two quads, the
// core's light as the plain head's, the core quad grown to hold the pair and its trails. Drawn by its
// card's pair of head batches (`ProjectileManager.register_body(shader, MESH_HEAD)`), warmed before
// the first room.

#include "res://core/projectiles/shot_palette.gdshaderinc"
#include "res://core/projectiles/shot_look.gdshaderinc"

// The flags (HEAD_LIVE, HEAD_ORBIT in projectile_manager.gd): the shot is alive (its core is drawn), an orbit
// shot.
const float HF_LIVE = 1.0;
const float HF_ORBIT = 2.0;
// The quad kinds (HEAD_Q_* in projectile_manager.gd), in UV.y.
const float Q_LIGHT = 0.0;
const float Q_CORE = 1.0;
// The fragment's modes: a round light, the chasing pair.
const float M_GLOW = 0.0;
const float M_PAIR = 2.0;
// The pair: how fast it turns (radians a second), its circle's half sizes, and its trail: TRAIL
// places behind the head, TRAIL_STEP pixels apart, each where the pair was TRAIL_LAG seconds before.
const float TURN = 24.0;
const vec2 CIRCLE = vec2(2.6, 2.2);
const int TRAIL = 6;
const float TRAIL_STEP = 2.2;
const float TRAIL_LAG = 0.012;

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
// Its palette (`palette_floats`): the materials of its infusions, -1 past them.
varying flat vec4 inf;

// ---- Vertices ----

void vertex() {
	float flags = MODEL_MATRIX[1].y;
	vec2 head = MODEL_MATRIX[3].xy;
	// The way it flies (`_write_head`).
	vec2 way = vec2(MODEL_MATRIX[1].x, MODEL_MATRIX[0].y);
	// The mesh's vertex: its quad kind and corner in UV.y (kind + 0.25 or 0.75), its corner in
	// UV.x; a corner of the triangle is 0 or twice the box.
	float quad = floor(UV.y);
	vec2 corner = vec2(fract(UV.x) > 0.5 ? 2.0 : 0.0, fract(UV.y) > 0.5 ? 2.0 : 0.0);
	Look L = look_from_color(COLOR, INSTANCE_CUSTOM.rgb, 0.0, true);
	// Zoom 0 in the look (`look_core_zoom`): a speck; the rest is drawn at 1.
	bool speck = floor(COLOR.r * 255.0 + 0.5) < 4.0;
	float z = L.zoom;
	vec3 b = L.bits;
	bool live = flag_set(flags, HF_LIVE);
	bool lightning = bit_set(b, L_SPARKS);
	bool pull = bit_set(b, L_PULL);
	// The light: lightning flickers, void's is dimmer.
	float flicker = (lightning ? 0.55 + 0.9 * hash_seeded(floor(sim_time * 20.0), 0.0, 21.0, L.seed) : 1.0) * (pull ? 0.6 : 1.0);
	vec2 q_lo = vec2(0.0);
	vec2 q_hi = vec2(0.0);
	float m = M_PAIR;
	vec4 a0 = vec4(0.0);
	vec4 a1 = vec4(0.0);
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
		vec2 px = floor(at);
		if (quad == Q_LIGHT) {
			m = M_GLOW;
			// A speck's light is a smaller one.
			float reach = speck ? 6.0 : 8.0 + 2.0 * z;
			q_lo = px + 0.5 - reach;
			q_hi = px + 0.5 + reach;
			a0 = vec4(px + 0.5, pull ? 0.45 : 0.0, 6.0);
			a1 = vec4((speck ? 0.6 : 0.8) * flicker, speck ? 2.0 : 3.0 + z, 0.35 * flicker, reach);
			k0 = vec4(L.glow, 1.0);
		} else {
			// The pair round the head, a pixel of circle more a zoom, its trail behind along the
			// way it flies: the box holds them all, and a twinkle's plus a pixel round a spark.
			vec2 back = at - fly * TRAIL_STEP * z * float(TRAIL - 1);
			float pad = CIRCLE.x * z + 2.0;
			q_lo = floor(min(at, back) - pad);
			q_hi = floor(max(at, back) + pad) + 1.0;
			a0 = vec4(at, sim_time * TURN, z);
			a1 = vec4(fly * TRAIL_STEP * z, TRAIL_LAG * TURN, 0.0);
			k0 = vec4(L.hot, 1.0);
			k1 = vec4(L.hi, 1.0);
			k2 = vec4(L.mid, 1.0);
			k3 = vec4(L.lo, 1.0);
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
	inf = palette_floats(L.core, L.bits);
}

// ---- Fragments ----
// Small on purpose (core/README.md, "The shot shaders"): a pixel only colours itself from what
// its quad's vertices worked out, over the trail's few places. No look kinds, nothing read from
// the path.

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
		// The pair (v0: the head, its turn now, the zoom; v1: a trail place's step back and turn
		// back), as twinkling motes (`twinkle_px`, the ward's look; the owner, 2026-11-09: "use
		// motes for everything you can"): from the trail's end to the head, so the nearer place is
		// drawn over; at each the white-hot spark (white-hot at the head, light, then shadow down
		// the trail) and, evenly round the circle from it, the others a shade cooler: one other
		// for a look of one infusion or none, else a spark an infusion, each in its own colours.
		float n = palette_count(inf);
		int sparks = n > 1.5 ? int(n) : 2;
		float m = -1.0;
		int who = 0;
		for (int j = TRAIL - 1; j >= 0; j--) {
			float f = float(j);
			float turn = v0.z - f * v1.z;
			vec2 at = v0.xy - v1.xy * f;
			float head = j == 0 ? 3.0 : (j < 3 ? 2.0 : 0.0);
			for (int k = 0; k < PALETTE_MOST; k++) {
				if (k >= sparks) {
					break;
				}
				float fk = float(k);
				float a = turn + TAU * fk / float(sparks);
				float shade = k == 0 ? head : max(head - 1.0, 0.0);
				float d = twinkle_px(P, at + vec2(cos(a), sin(a)) * CIRCLE * v0.w, shade, fract(sim_time * (1.3 + 0.37 * f + 0.2 * fk) + 0.21 * f + 0.5 * fk));
				if (d >= 0.0) {
					m = d;
					who = k;
				}
			}
		}
		vec3 own = m > 1.5 ? c1.rgb : (m > 0.5 ? c2.rgb : c3.rgb);
		colour = m > 2.5 ? c0 : (m > -0.5 ? vec4(palette_turn(inf, who, int(m), own), 1.0) : vec4(0.0));
	}
	// Only the box's pixels: the rest of the triangle is outside the quad.
	bool inside = all(greaterThanEqual(c, box.xy)) && all(lessThan(c, box.zw));
	COLOR = inside ? colour : vec4(0.0);
}
