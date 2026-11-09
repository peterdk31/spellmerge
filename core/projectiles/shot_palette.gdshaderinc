// SPDX-License-Identifier: GPL-3.0-or-later
// The shot shaders' shared constants and small helpers (core/README.md, "The shot shaders"):
// the palette ramps (docs/STYLE.md), the look kinds, the flash kinds and flags, and the pure
// functions every one of them uses. No uniforms, no varyings: `shot_look.gdshaderinc` has those.

// docs/STYLE.md: the players' ramps (shadow, base, light), then the enemy ramp (Blight ochre,
// ENEMY_PLAYER), and the colours the layers use.
const vec3 P_SHADOW[5] = vec3[](vec3(0.114, 0.227, 0.420), vec3(0.478, 0.137, 0.278), vec3(0.122, 0.290, 0.227), vec3(0.290, 0.165, 0.420), vec3(0.302, 0.247, 0.071));
const vec3 P_BASE[5] = vec3[](vec3(0.231, 0.451, 0.788), vec3(0.851, 0.278, 0.478), vec3(0.247, 0.561, 0.310), vec3(0.541, 0.310, 0.769), vec3(0.651, 0.541, 0.165));
const vec3 P_LIGHT[5] = vec3[](vec3(0.498, 0.753, 0.941), vec3(0.961, 0.604, 0.722), vec3(0.561, 0.831, 0.416), vec3(0.788, 0.604, 0.941), vec3(0.890, 0.812, 0.420));
const float ENEMY_PLAYER = 4.0;
const vec3 OUTLINE = vec3(0.078, 0.071, 0.122);
const vec3 FIRE_BASE = vec3(0.878, 0.349, 0.184);
const vec3 FIRE_LIGHT = vec3(1.0, 0.635, 0.235);
const vec3 ICE_LIGHT = vec3(0.769, 0.965, 0.949);
const vec3 SPARK_LIGHT = vec3(1.0, 0.953, 0.651);
const vec3 VOID_BASE = vec3(0.627, 0.188, 0.604);
const vec3 VOID_LIGHT = vec3(0.878, 0.541, 0.847);
const vec3 ARC_BASE = vec3(0.706, 0.910, 0.165);
const vec3 ARC_LIGHT = vec3(0.933, 1.0, 0.651);
const vec3 BONE_LIGHT = vec3(0.957, 0.945, 0.918);
const vec3 BONE_BASE = vec3(0.831, 0.816, 0.878);
const vec3 BONE_SHADOW = vec3(0.639, 0.624, 0.722);
const vec3 STONE_SHADOW = vec3(0.169, 0.157, 0.251);
const vec3 STONE_BASE = vec3(0.290, 0.275, 0.388);
const vec3 STONE_LIGHT = vec3(0.478, 0.463, 0.580);
// The materials a core's tint can name, three shades each (shadow, base, light): Fire, Spark,
// Ice, Void, Arc, Bone.
const int MATERIALS = 6;
const vec3 SHADES[18] = vec3[](
	vec3(0.561, 0.176, 0.165), vec3(0.878, 0.349, 0.184), vec3(1.0, 0.635, 0.235),
	vec3(0.722, 0.502, 0.122), vec3(0.949, 0.761, 0.188), vec3(1.0, 0.953, 0.651),
	vec3(0.122, 0.439, 0.502), vec3(0.310, 0.839, 0.863), vec3(0.769, 0.965, 0.949),
	vec3(0.290, 0.078, 0.314), vec3(0.627, 0.188, 0.604), vec3(0.878, 0.541, 0.847),
	vec3(0.247, 0.420, 0.063), vec3(0.706, 0.910, 0.165), vec3(0.933, 1.0, 0.651),
	vec3(0.639, 0.624, 0.722), vec3(0.831, 0.816, 0.878), vec3(0.957, 0.945, 0.918));

// The layer kinds (LOOK_* in projectile_manager.gd): one bit each in the look.
const float L_EMBERS = 1.0;
const float L_FLECKS = 2.0;
const float L_GUSTS = 3.0;
const float L_PULL = 4.0;
const float L_SPARKS = 5.0;
const float L_MOTES = 6.0;
const float L_GLINTS = 7.0;
const float L_STREAKS = 8.0;
const float L_BURST = 9.0;
const float L_ORBITERS = 10.0;
const float L_WEAVE = 11.0;
const float L_GLITTER = 12.0;
const float L_HOPS = 13.0;
const float L_WAKE = 14.0;
const float L_WEIGHT = 15.0;
const float L_RIPPLE = 16.0;
const float L_CURL = 17.0;
const float L_ZIG = 18.0;
const float L_DOUBLE = 19.0;
const float L_CONVERGE = 20.0;
const float L_DRIFT = 21.0;
const float KIND_COUNT = 21.0;
// Flags in the look, not particles: the enemy ramp (Blight ochre takes the player's place; staffs
// F2), and an exact colour (a reaction's own, its ramp made from it instead of the palette material
// it is nearest). Kind 22 is free (Feel's poof flag until flash kinds F2).
const float ENEMY_RAMP = 23.0;
const float EXACT = 24.0;
// Particles a shot keeps in the air at most, and how many a shot with `n` emitting kinds uses:
// 4 + 2n, so one card is a trickle, many cards a richer mix, never a cloud
// (`particles_of` in projectile_manager.gd; keep the two equal).
const int MAX_PARTICLES = 12;

// The kind travels in the alpha of the custom data as 1 - (kind + code) / 16 (KIND_STEPS in
// projectile_manager.gd): the flashes Feel draws (KIND_* in gameplay/feel/feel.gd), each by the
// shader of its own batch.
const float K_BURST = 4.0;
const float K_RING_OUT = 5.0;
const float K_RING_IN = 6.0;
const float K_RUNE_BURST = 7.0;
const float K_CAST = 8.0;
const float K_DASH = 9.0;
const float K_BEAM = 10.0;
const float K_SPRAY = 11.0;
const float K_PUFF = 12.0;
const float K_ARC = 14.0;
const float K_STATUS = 15.0;
// A flash's age travels as TRACE_FROM + TRACE_SPAN x the fraction; so does a still shot's clock
// (`still_code` in projectile_manager.gd): its first STILL_START seconds as that, its last
// STILL_END seconds of life as that negated, 0 between (`still_since`, `still_left`).
const float TRACE_FROM = 0.02;
const float TRACE_SPAN = 0.42;
const float STILL_START = 1.25;
const float STILL_END = 1.0;
// A still shot's hit size as drawn, as a share of its quad: the unit a still card's look is shaped
// in (its `look_shape`; `STILL_HIT` in projectile_manager.gd, compared by test_projectile_looks).
const float STILL_HIT = 0.15;

bool bit_set(vec3 b, float look) {
	float bit = look - 1.0;
	float byte = bit < 8.0 ? b.x : (bit < 16.0 ? b.y : b.z);
	return mod(floor(byte / exp2(mod(bit, 8.0))), 2.0) > 0.5;
}

bool flag_set(float flags, float f) {
	return mod(floor(flags / f + 0.001), 2.0) > 0.5;
}

float triangle(float x) {
	return abs(fract(x) * 2.0 - 1.0) * 2.0 - 1.0;
}

// A number in [0, 1) from three numbers and a seed: the same on every machine.
float hash_seeded(float a, float b, float c, float s) {
	return fract(sin(dot(vec3(a, b, c) + s, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
}

// True when the pixel centred at `q` is the pixel of the point `at` (both in pixels).
bool on(vec2 q, vec2 at) {
	return all(equal(floor(q), floor(at)));
}

// 1 at the middle, 0 from `reach` on, eased: the shape of every glow.
float falloff(float x, float reach) {
	float k = max(1.0 - x / reach, 0.0);
	return k * k;
}

// A twinkling mote as a card shader draws one (the ward's look, gameplay/feel/barriers.gd; the
// owner, 2026-11-09: "use motes for everything you can", the world's magic building blocks): a
// pixel at `at` in its shade `shade` (0 shadow to 3 white-hot: `cooling`), white-hot at the start
// of its twinkle `tw` (0-1, a cycle of its own) and at its brightest a little plus round it in the
// light shade. The shade (0-3) of the pixel `p`, or -1 off it.
float twinkle_px(vec2 p, vec2 at, float shade, float tw) {
	vec2 d = abs(floor(p) - floor(at));
	float far = d.x + d.y;
	if (far < 0.5) {
		return tw < 0.12 ? 3.0 : shade;
	}
	return far < 1.5 && tw < 0.07 && shade > 0.5 ? 2.0 : -1.0;
}

// A mote's shade `a` (0-1) through its life, cooling: white-hot, light, base, then shadow.
float cooling(float a) {
	return a < 0.15 ? 3.0 : (a < 0.5 ? 2.0 : (a < 0.85 ? 1.0 : 0.0));
}

// The colour `u` (0-1) of the way through a ramp of three or four shades.
vec3 shade3(vec3 a, vec3 b, vec3 c, float u) {
	return u < 0.334 ? a : (u < 0.667 ? b : c);
}

vec3 shade4(vec3 a, vec3 b, vec3 c, vec3 d, float u) {
	return u < 0.25 ? a : (u < 0.5 ? b : (u < 0.75 ? c : d));
}

// The kind (0-15) and the code beside it (0-0.45 above the kind; below it, -0.45-0, for a flash
// that does not light the room: Feel's unlit flashes, S6 item 4) in an instance's custom data alpha.
float coded_kind(float custom_a) {
	return floor((1.0 - custom_a) * 16.0 + 0.5);
}

float coded_code(float custom_a) {
	float coded = (1.0 - custom_a) * 16.0;
	return coded - floor(coded + 0.5);
}

// How far through its life a flash is, from its code (either side of its kind).
float coded_age(float code) {
	float a = abs(code);
	return a > 0.01 ? clamp((a - TRACE_FROM) / TRACE_SPAN, 0.0, 1.0) : 1.0;
}

// A still shot's seconds since it was placed, from its code (STILL_START once past them).
float still_since(float code) {
	return code > 0.01 ? clamp((code - TRACE_FROM) / TRACE_SPAN, 0.0, 1.0) * STILL_START : STILL_START;
}

// A still shot's seconds of life left, from its code (STILL_END while it has more).
float still_left(float code) {
	return code < -0.01 ? (1.0 - clamp((-code - TRACE_FROM) / TRACE_SPAN, 0.0, 1.0)) * STILL_END : STILL_END;
}
