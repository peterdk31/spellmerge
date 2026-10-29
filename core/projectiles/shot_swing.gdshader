// SPDX-License-Identifier: GPL-3.0-or-later
shader_type canvas_item;
// world_vertex_coords: VERTEX is in world space in vertex(), so each quad is placed in the world
// and the trail stands upright on the world's pixels (nothing else moves its vertices).
render_mode blend_premul_alpha, world_vertex_coords;

// A swing's trail (Feel's swing trails, `gameplay/feel/swing_trails.gd`; melee I4, the owner's pick
// A3 "spark scatter"; core/README.md, "The shot shaders"): a brief one-pixel line at the arc's
// reach that follows the staff's tip and cools through the ramp behind it, pixel sparks it sheds
// outward as it passes, and its card particles. Blending is premultiplied: its pixels are
// opaque, its glow added light. The line is in its player's ramp with every fourth pixel in its
// infusion's (`core_override`), so a fire swing reads as fire and as whose.
//
// The sweep: round `swing_origin` (the hand) from `swing_dir` (the aim locked at the cast),
// turning `swing_side` (1 clockwise on screen, -1 back) from -`swing_lean` to +`swing_lean`
// radians in `swing_sweep` seconds from `swing_start` (both in `sim_time`'s seconds), slow, fast,
// slow (`Spells.swing_ease`); only -`swing_half` to +`swing_half` hits, and only that is drawn.
//
// PARTICLES ARE GEOMETRY (as in `shot_beam.gdshader`): a trail is a mesh of small quads
// (`SwingTrails.swing_mesh`), each told in its UV which QUAD KIND (Q_*) and slot it is:
//   Q_LIGHT     the line's glow, over the square round the hand (added; drawn first)
//   Q_PARTICLE  one of its card particles, in the swing's own pixels at the tip where it was born
//   Q_SPARK     a spark shed outward, upright on the world's pixels
//   Q_LINE      the line, over the square round the hand (drawn last, on top)
// The line and its light are worked out per pixel from its angle round the hand (when the tip
// passed it), with no loops.

#include "res://core/projectiles/shot_palette.gdshaderinc"
#include "res://core/projectiles/shot_look.gdshaderinc"
#include "res://core/projectiles/shot_particle.gdshaderinc"

// The quad kinds (SWING_Q_* in swing_trails.gd), in UV.y, and the sparks.
const float Q_LIGHT = 0.0;
const float Q_PARTICLE = 1.0;
const float Q_SPARK = 2.0;
const float Q_LINE = 3.0;
const float SPARKS = 28.0;
// The fragment's modes.
const float M_LIGHT = 0.0;
const float M_LINE = 1.0;
const float M_PIXELS = 2.0;
// Seconds a pixel of the line stays after the tip passed it, and its light.
const float LINE_LIFE = 0.12;
const float LIGHT_LIFE = 0.3;
// The line runs this far inside the reach, and the square round the hand this far outside it.
const float LINE_IN = 2.0;
const float MARGIN = 10.0;

uniform vec4 core_override = vec4(1.0);
uniform int swing_player = 0;
uniform int swing_look = 0;
uniform vec2 swing_origin = vec2(-100000.0);
uniform vec2 swing_dir = vec2(1.0, 0.0);
uniform float swing_side = 1.0;
uniform float swing_half = 0.785;
uniform float swing_lean = 1.178;
uniform float swing_reach = 24.0;
uniform float swing_start = 0.0;
uniform float swing_sweep = 0.06;
uniform float swing_glow = 1.0;
uniform float swing_seed = 0.0;

// The pixel in the world, and in its particle's pixels (the swing's own at the tip).
varying vec2 world;
varying vec2 local;
varying flat float mode;
// A spark's or particle's pixel and shape (see `particle_pixel`), its colours.
varying flat vec4 v0;
varying flat vec4 v1;
varying flat vec4 c0;
varying flat vec4 c1;
// The player's ramp (the line's own pixels; the look's ramp is its infusion's).
varying flat vec3 p_hot;
varying flat vec3 p_hi;
varying flat vec3 p_mid;
varying flat vec3 p_lo;

// When the tip passed `a` radians off the aim (in the swing's turning): the sweep's ease undone.
float passed_at(float a) {
	float y = clamp((a + swing_lean) / max(2.0 * swing_lean, 0.001), 0.0, 1.0);
	float x = y < 0.5 ? sqrt(y * 0.5) : 1.0 - sqrt((1.0 - y) * 0.5);
	return swing_start + swing_sweep * x;
}

// The way out from the hand at `a` radians off the aim.
vec2 out_at(float a) {
	float w = atan(swing_dir.y, swing_dir.x) + a * swing_side;
	return vec2(cos(w), sin(w));
}

// `a` radians off the aim of the point `p` round the hand, in the swing's turning.
float angle_of(vec2 p) {
	vec2 v = p - swing_origin;
	float d = atan(v.y, v.x) - atan(swing_dir.y, swing_dir.x);
	d = mod(d + 3.14159265, 6.2831853) - 3.14159265;
	return d * swing_side;
}

vec3 ramp4(vec3 h, vec3 l, vec3 m, vec3 s, float u) {
	return u < 0.15 ? h : (u < 0.4 ? l : (u < 0.7 ? m : s));
}

void vertex() {
	vec3 b = vec3(float(swing_look & 255), float((swing_look >> 8) & 255), float((swing_look >> 16) & 255));
	float who = swing_player < 0 ? ENEMY_PLAYER : float(min(swing_player, 3));
	Look L = look_of(core_override.rgb, who, 1.0, b, swing_seed, true);
	SET_LOOK(L);
	// The player's ramp, as `look_of` gives a plain shot's (the enemy ramp's for an enemy).
	int pi = int(L.player);
	p_hot = BONE_LIGHT;
	p_hi = P_LIGHT[pi];
	p_mid = P_BASE[pi];
	p_lo = P_SHADOW[pi];
	int slot = int(floor(UV.x));
	float quad = floor(UV.y);
	vec2 corner = vec2(fract(UV.x) > 0.5 ? 1.0 : 0.0, fract(UV.y) > 0.5 ? 1.0 : 0.0);
	bool shown = false;
	vec2 at = vec2(0.0);
	vec2 here = vec2(0.0);
	float m = M_PIXELS;
	vec4 a0 = vec4(0.0);
	vec4 a1 = vec4(0.0);
	vec4 k0 = vec4(0.0);
	vec4 k1 = vec4(0.0);
	float i = float(slot);
	if (quad == Q_LIGHT || quad == Q_LINE) {
		// The square round the hand, out past the reach.
		shown = slot == 0 && swing_reach > 0.0;
		float h = swing_reach + MARGIN;
		at = mix(swing_origin - vec2(h), swing_origin + vec2(h), corner);
		m = quad == Q_LINE ? M_LINE : M_LIGHT;
	} else if (quad == Q_SPARK) {
		// Spark `slot`: shed at its own point of the arc as the tip passes, flung outward and a
		// little along the swing, slowing, cooling as it flies.
		float along = (i + hash_seeded(i, 1.0, 61.0, swing_seed)) / SPARKS;
		float a = mix(-swing_half, swing_half, along);
		float age = sim_time - passed_at(a);
		float life = 0.28 + 0.25 * hash_seeded(i, 2.0, 61.0, swing_seed);
		vec2 o = out_at(a);
		vec2 tg = vec2(-o.y, o.x) * swing_side;
		float speed = 25.0 + 45.0 * hash_seeded(i, 3.0, 61.0, swing_seed);
		float twist = (hash_seeded(i, 4.0, 61.0, swing_seed) - 0.3) * 30.0;
		float k = (1.0 - exp(-6.0 * max(age, 0.0))) / 6.0;
		vec2 pos = floor(swing_origin + o * (swing_reach - LINE_IN - 1.0 + 2.0 * hash_seeded(i, 5.0, 61.0, swing_seed)) + (o * speed + tg * twist) * k);
		shown = age >= 0.0 && age <= life;
		at = mix(pos, pos + 1.0, corner);
		here = at;
		a0 = vec4(pos, 0.0, 0.0);
		float u = age / life;
		k0 = vec4(mod(i, 4.0) < 0.5 ? ramp4(L.hot, L.hi, L.mid, L.lo, u) : ramp4(p_hot, p_hi, p_mid, p_lo, u), 1.0);
	} else if (quad == Q_PARTICLE) {
		// Its cards, given off where the tip passed, in the swing's own pixels there (+x the way
		// the tip moved).
		float n = L.emits.w;
		float count = min(4.0 + 2.0 * n, float(MAX_PARTICLES));
		float a = mix(-swing_half, swing_half, hash_seeded(i, 6.0, 61.0, swing_seed));
		float t = (sim_time - passed_at(a)) / 0.5;
		float pick = min(floor(hash_seeded(i, 7.0, 61.0, swing_seed) * n), n - 1.0);
		float word = pick < 4.0 ? L.emits.x : (pick < 8.0 ? L.emits.y : L.emits.z);
		float look = mod(floor(word / exp2(mod(pick, 4.0) * 5.0) + 0.001), 32.0);
		Particle p = place_particle(look, vec2(0.0), clamp(t, 0.0, 1.0), i, 0.0, 1.0, swing_seed);
		vec2 cell = floor(p.at);
		shown = n > 0.5 && i < count && p.shown && t >= 0.0 && t < 1.0;
		vec2 q = mix(cell - 1.0, cell + vec2(p.run + 2.0, 2.0), corner);
		vec2 o = out_at(a);
		vec2 way = vec2(-o.y, o.x) * swing_side;
		vec2 tip = swing_origin + o * (swing_reach - LINE_IN);
		at = tip + way * q.x + vec2(-way.y, way.x) * q.y;
		here = q;
		a0 = vec4(cell, p.run, p.arm);
		a1 = vec4(p.extra, 0.0, 0.0);
		k0 = vec4(p.rgb, 1.0);
		k1 = vec4(p.arm_rgb, 1.0);
	}
	// Folded away when there is nothing to draw.
	VERTEX = shown ? at : vec2(-1.0e6);
	world = VERTEX;
	local = here;
	mode = m;
	v0 = a0;
	v1 = a1;
	c0 = k0;
	c1 = k1;
}

// ---- Fragments ----
// Small on purpose (core/README.md, "The shot shaders"): no loops.

void fragment() {
	vec4 colour = vec4(0.0);
	if (mode < M_LINE + 0.5) {
		vec2 c = floor(world) + 0.5;
		float r = length(c - swing_origin);
		float a = angle_of(c);
		float age = sim_time - passed_at(a);
		bool on_arc = abs(a) <= swing_half;
		float line_r = swing_reach - LINE_IN;
		if (mode < M_LIGHT + 0.5) {
			if (on_arc && age >= 0.0 && age < LIGHT_LIFE) {
				float k = 1.0 - age / LIGHT_LIFE;
				float lit = 0.55 * k * k * falloff(abs(r - line_r), 5.0);
				colour = vec4(glow * lit * swing_glow * glow_strength, 0.0);
			}
		} else if (on_arc && age >= 0.0 && age < LINE_LIFE && abs(r - line_r) < 0.5) {
			// Every fourth pixel along it in the infusion's ramp, the rest in the player's.
			float u = age / LINE_LIFE;
			bool infused = mod(floor(a * line_r), 4.0) < 0.5;
			colour = vec4(infused ? ramp(u) : ramp4(p_hot, p_hi, p_mid, p_lo, u), 1.0);
		}
	} else {
		// A spark (on the world's pixels) or a particle (in the swing's).
		Particle p;
		p.shown = true;
		p.at = v0.xy;
		p.run = v0.z;
		p.arm = v0.w;
		p.extra = v1.xy;
		p.rgb = c0.rgb;
		p.arm_rgb = c1.rgb;
		colour = particle_pixel(p, local);
	}
	COLOR = colour;
}
