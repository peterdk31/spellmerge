// SPDX-License-Identifier: GPL-3.0-or-later
shader_type canvas_item;
render_mode blend_premul_alpha, world_vertex_coords;

// A swing card's own look (content/spells/forms/swing/: `FormBase.look_shader`; docs/milestones/card-looks.md;
// the owner, 2026-11-08: rework the carriers' looks). A copy of the plain trail
// (`core/projectiles/shot_swing.gdshaderinc`, the fallback) drawing a crescent slash instead of a
// line: white-hot along its line at the reach where the tip just passed, cooling inward through
// its ramp and with age, a stroke the way it swung (a hairline where it began, its head near where
// it ended, pointed at the end; each swing turns the other way, so its stroke does too), a pixel of
// light outside it while fresh and two broken smears inside it behind the tip. An infused slash is
// in its infusion's ramp with its player's colour along its inner edge; a plain one in its
// player's. Its vertices, quads and uniforms are the plain trail's (Feel's swing trails draw each
// swing's trail with it on the trail's own material); warmed as a mesh before the first room.

#include "res://core/projectiles/shot_palette.gdshaderinc"
#include "res://core/projectiles/shot_look.gdshaderinc"

// The quad kinds (SWING_Q_* in swing_trails.gd), in UV.y.
const float Q_LIGHT = 0.0;
const float Q_LINE = 1.0;
// The fragment's modes.
const float M_LIGHT = 0.0;
const float M_LINE = 1.0;
// Seconds a pixel of the slash stays after the tip passed it, and its light.
const float LINE_LIFE = 0.16;
const float LIGHT_LIFE = 0.3;
// How many pixels thick the slash is inside its line at the middle of its arc, fresh, and how far
// inside it the two smears run.
const float THICK = 4.0;
const float SMEAR_A = 2.0;
const float SMEAR_B = 4.0;
// How sharply its head comes to a point at the end (it tapers over the last 1 / HEAD of its arc),
// and the stroke's thickest share, so its head is THICK.
const float HEAD = 6.0;
const float HEAD_PEAK = 0.75;
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

// The pixel in the world.
varying vec2 world;
varying flat float mode;
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
	// The square round the hand, out past the reach.
	bool shown = slot == 0 && swing_reach > 0.0;
	float h = swing_reach + MARGIN;
	vec2 at = mix(swing_origin - vec2(h), swing_origin + vec2(h), corner);
	// Folded away when there is nothing to draw.
	VERTEX = shown ? at : vec2(-1.0e6);
	world = VERTEX;
	mode = quad == Q_LINE ? M_LINE : M_LIGHT;
}

// ---- Fragments ----
// Small on purpose (core/README.md, "The shot shaders"): no loops.

// The slash's shade `k` (0 white-hot to 3 shadow): its infusion's ramp, or its player's when plain.
vec3 slash_shade(float k) {
	vec3 own = ramp4(hot, hi, mid, lo, k / 3.0 * 0.99);
	vec3 theirs = ramp4(p_hot, p_hi, p_mid, p_lo, k / 3.0 * 0.99);
	return plain > 0.5 ? theirs : own;
}

void fragment() {
	vec4 colour = vec4(0.0);
	vec2 c = floor(world) + 0.5;
	float r = length(c - swing_origin);
	float a = angle_of(c);
	float age = sim_time - passed_at(a);
	bool on_arc = abs(a) <= swing_half;
	float line_r = swing_reach - LINE_IN;
	float u = age / LINE_LIFE;
	// A stroke the way it swung (`a` grows the way it turns, so the side it swung from is -half):
	// a hairline where it began, swelling to its head near where it ended, to a point at the end;
	// thinning as it ages. Each swing turns the other way, so its stroke does too.
	float along = clamp((a / max(swing_half, 0.001) + 1.0) * 0.5, 0.0, 1.0);
	float taper = clamp(pow(along, 1.6) * min((1.0 - along) * HEAD, 1.0) / HEAD_PEAK, 0.0, 1.0);
	float thick = floor(THICK * taper * pow(max(1.0 - u, 0.0), 0.7) + 0.5);
	// Pixels inside its line (0 on it), and from its inner edge.
	float dr = floor(line_r - r + 0.5);
	float from_edge = thick - dr;
	if (mode < M_LIGHT + 0.5) {
		if (on_arc && age >= 0.0 && age < LIGHT_LIFE) {
			float k = 1.0 - age / LIGHT_LIFE;
			float lit = 0.6 * k * k * falloff(abs(line_r - thick * 0.5 - r), 4.0 + thick);
			colour = vec4(glow * lit * swing_glow * glow_strength, 0.0);
		}
	} else if (on_arc && age >= 0.0 && u < 1.0) {
		// Its shade: white-hot at its line where the tip just passed, cooling inward and with age.
		float by_age = u < 0.2 ? 0.0 : (u < 0.45 ? 1.0 : (u < 0.7 ? 2.0 : 3.0));
		float by_edge = 3.0 - min(from_edge, 3.0);
		if (dr >= 0.0 && from_edge >= 0.0) {
			vec3 rgb = slash_shade(max(by_age, by_edge));
			// An infused slash keeps its player's colour along its inner edge, so it reads as whose.
			rgb = plain < 0.5 && from_edge < 0.5 && dr > 0.5 ? p_mid : rgb;
			colour = vec4(rgb, 1.0);
		} else if (dr == -1.0 && u < 0.45 && taper > 0.3) {
			// A pixel of light outside its line, fresh.
			colour = vec4(slash_shade(1.0), 1.0);
		} else if (u < 0.55 && (dr == thick + SMEAR_A || dr == thick + SMEAR_B) && taper > 0.2) {
			// Two broken smears inside it, shorter, where the tip has just been.
			float gap = mod(floor(a * r) + floor(swing_seed) + dr, 5.0);
			if (gap < (dr == thick + SMEAR_A ? 3.0 : 2.0)) {
				colour = vec4(slash_shade(dr == thick + SMEAR_A ? 2.0 : 3.0), 1.0);
			}
		}
	}
	COLOR = colour;
}
