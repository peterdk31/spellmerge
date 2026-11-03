// SPDX-License-Identifier: GPL-3.0-or-later
shader_type canvas_item;
// world_vertex_coords: VERTEX is in world space in vertex(), so each quad is placed in the world
// and the mote stands on the world's pixels (nothing else moves its vertices).
render_mode blend_premul_alpha, world_vertex_coords;

// Motes (gameplay/feel/mote.gd; docs/milestones/spell-spectacle.md, P1): single pixels (or a 2x2
// chunk) thrown from a point, with no game logic. A mote's whole flight comes from its row,
// written once by the CPU, and the time since its birth: it flies with drag, rises or falls by a
// fake height, lands, bounces once, lies still, and cools step by step through its ramp's
// shades (no partial alpha; docs/STYLE.md), then is gone. Blending is premultiplied: the pixel
// is opaque, the glow round a hot one light added to what is below.
//
// A row (Motes.DRAW_STRIDE floats; the batch sits untransformed at the origin, so the transform
// carries data, in full floats on every renderer):
//   MODEL_MATRIX[0].xy  its velocity along the floor (px/s)
//   MODEL_MATRIX[1].x   its birth, on `sim_time`'s clock (s)
//   MODEL_MATRIX[1].y   its height's velocity, up (px/s)
//   MODEL_MATRIX[3].xy  its ground point at birth (where it is drawn: that, raised by its height)
//   COLOR               kind / CODE, ramp / CODE, life / LIFE_MAX, a seed (0-1)
//   INSTANCE_CUSTOM     its height at birth (px), its size (1 or 2), its first shade (0 white-hot,
//                       1 light, 2 base, 3 shadow), unused
// The colour and custom data are small numbers only: the compatibility renderer may keep them
// as half floats.
//
// The kinds' numbers (K_*) are mote.gd's tables (GRAVITY, DRAG, ...), and `mote_flight` is
// `Motes.flight` line for line; tests/gameplay/feel/test_motes.gd fails when the two differ.

#include "res://core/projectiles/shot_palette.gdshaderinc"

uniform float sim_time = 0.0;
uniform float glow_strength = 1.0;

// The longest life a mote has, and what its kind and ramp are divided by in COLOR.
const float LIFE_MAX = 4.0;
const float CODE = 16.0;
// How far a hot mote's glow reaches past its pixel.
const float GLOW_REACH = 2.0;
// The kinds (Motes.KIND_NAMES): ember, spark, chip, shard, ash, splinter.
const int KINDS = 6;
// Down the height (px/s/s; below 0 it rises), drag along the floor (1/s), the share of its
// fall's speed a landing bounces back, a sideways sway (px) and its rate (rad/s), the glow while
// it is hot, and the shade it starts at.
const float K_GRAVITY[6] = float[](-12.0, 220.0, 320.0, 300.0, 18.0, 300.0);
const float K_DRAG[6] = float[](2.0, 3.5, 2.5, 2.5, 1.2, 2.5);
const float K_BOUNCE[6] = float[](0.0, 0.35, 0.3, 0.4, 0.0, 0.25);
const float K_WOBBLE[6] = float[](1.5, 0.0, 0.0, 0.0, 3.0, 0.0);
const float K_WOBBLE_RATE[6] = float[](7.0, 0.0, 0.0, 0.0, 3.0, 0.0);
const float K_GLOW[6] = float[](1.0, 1.0, 0.0, 0.4, 0.0, 0.0);
const float K_SHADE_FROM[6] = float[](0.0, 0.0, 1.0, 1.0, 2.0, 1.0);
// The ramps (Motes.RAMP_*): 0-3 the players', 4 the enemies' (Blight), 5-10 the materials of
// SHADES (Fire, Spark, Ice, Void, Arc, Bone), 11 Stone, 12 Wood (docs/STYLE.md).
const int RAMP_STONE = 11;
const vec3 WOOD_SHADOW = vec3(0.239, 0.165, 0.180);
const vec3 WOOD_BASE = vec3(0.478, 0.290, 0.208);
const vec3 WOOD_LIGHT = vec3(0.698, 0.478, 0.290);

// The mote's pixel (its top-left), its size, colour and glow, and the world pixel drawn.
varying flat vec2 m_at;
varying flat float m_size;
varying flat vec3 m_rgb;
varying flat float m_glow;
varying vec2 m_px;

// Shade `shade` (0 white-hot, 1 light, 2 base, 3 shadow) of `ramp`. Stone and Wood have no
// white-hot. Stone is one step lighter than the material (Bone shadow, Stone light, Stone shadow):
// the floor is Stone base, which a chip must never be.
vec3 ramp_shade(int ramp, int shade) {
	if (ramp < 5) {
		return shade == 0 ? BONE_LIGHT : (shade == 1 ? P_LIGHT[ramp] : (shade == 2 ? P_BASE[ramp] : P_SHADOW[ramp]));
	}
	if (ramp < RAMP_STONE) {
		int m = (ramp - 5) * 3;
		return shade == 0 ? mix(SHADES[m + 2], vec3(1.0), 0.5) : SHADES[m + 3 - shade];
	}
	if (ramp == RAMP_STONE) {
		return shade <= 1 ? BONE_SHADOW : (shade == 2 ? STONE_LIGHT : STONE_SHADOW);
	}
	return shade <= 1 ? WOOD_LIGHT : (shade == 2 ? WOOD_BASE : WOOD_SHADOW);
}

// Where a mote of kind `k` is `t` seconds after its birth at the ground point `from` with the
// velocity `vel`, the height `h0` and the height's velocity `vz`: its ground point (xy) and its
// height (z). A falling kind lands, bounces once and then lies still.
vec3 mote_flight(vec2 from, vec2 vel, float h0, float vz, float t, int k, float seed) {
	float g = K_GRAVITY[k];
	float land = 1.0e9;
	float rest = 1.0e9;
	float rebound = 0.0;
	if (g > 0.0) {
		land = (vz + sqrt(vz * vz + 2.0 * g * max(h0, 0.0))) / g;
		rebound = (g * land - vz) * K_BOUNCE[k];
		rest = land + 2.0 * rebound / g;
	}
	float tm = min(max(t, 0.0), rest);
	float h = 0.0;
	if (tm < land) {
		h = h0 + vz * tm - 0.5 * g * tm * tm;
	} else if (tm < rest) {
		float s = tm - land;
		h = rebound * s - 0.5 * g * s * s;
	}
	float drag = K_DRAG[k];
	float along = drag > 0.0 ? (1.0 - exp(-drag * tm)) / drag : tm;
	vec2 ground = from + vel * along;
	float phase = seed * 6.2832;
	ground.x += K_WOBBLE[k] * (sin(tm * K_WOBBLE_RATE[k] + phase) - sin(phase));
	return vec3(ground, max(h, 0.0));
}

void vertex() {
	vec2 vel = MODEL_MATRIX[0].xy;
	float born = MODEL_MATRIX[1].x;
	float vz = MODEL_MATRIX[1].y;
	vec2 from = MODEL_MATRIX[3].xy;
	int k = clamp(int(COLOR.r * CODE + 0.5), 0, KINDS - 1);
	int ramp = clamp(int(COLOR.g * CODE + 0.5), 0, 12);
	float life = COLOR.b * LIFE_MAX;
	float seed = COLOR.a;
	float h0 = INSTANCE_CUSTOM.r;
	float size = INSTANCE_CUSTOM.g > 1.5 ? 2.0 : 1.0;
	float shade_from = INSTANCE_CUSTOM.b;
	float t = sim_time - born;
	bool alive = life > 0.0 && t >= 0.0 && t < life;
	vec3 at = mote_flight(from, vel, h0, vz, t, k, seed);
	vec2 pixel = floor(at.xy - vec2(0.0, at.z));
	// Cooling: evenly from its first shade down to shadow over its life.
	float u = clamp(t / max(life, 0.001), 0.0, 1.0);
	int shade = int(min(shade_from + floor(u * (4.0 - shade_from)), 3.0));
	float glow = shade <= 1 ? K_GLOW[k] * glow_strength : 0.0;
	float reach = glow > 0.0 ? GLOW_REACH : 0.0;
	vec2 corner = vec2(UV.x > 0.5 ? 1.0 : 0.0, UV.y > 0.5 ? 1.0 : 0.0);
	vec2 p = mix(pixel - reach, pixel + size + reach, corner);
	// Folded away when it is not alive (an unused row has no life).
	VERTEX = alive ? p : vec2(0.0);
	m_px = p;
	m_at = pixel;
	m_size = size;
	m_rgb = ramp_shade(ramp, shade);
	m_glow = glow;
}

void fragment() {
	vec2 d = floor(m_px) - m_at;
	if (all(greaterThanEqual(d, vec2(0.0))) && all(lessThan(d, vec2(m_size)))) {
		COLOR = vec4(m_rgb, 1.0);
	} else {
		// The glow round a hot mote: light added, no alpha.
		vec2 c = clamp(d, vec2(0.0), vec2(m_size - 1.0));
		COLOR = vec4(m_rgb * m_glow * 0.5 * falloff(length(d - c), GLOW_REACH + 1.0), 0.0);
	}
}
