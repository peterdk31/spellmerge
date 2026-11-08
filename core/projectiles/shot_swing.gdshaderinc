// SPDX-License-Identifier: GPL-3.0-or-later
// The drawing of `shot_swing.gdshader` (read it for what this draws and how its instance or mesh
// is encoded), in an include so a card's own look that starts from it (`FormBase.look_shader`;
// docs/milestones/card-looks.md) includes it and keeps every fix to it, until the card replaces
// the include with code of its own. The including file has `shader_type` and `render_mode`.

#include "res://core/projectiles/shot_palette.gdshaderinc"
#include "res://core/projectiles/shot_look.gdshaderinc"

// The quad kinds (SWING_Q_* in swing_trails.gd), in UV.y.
const float Q_LIGHT = 0.0;
const float Q_LINE = 1.0;
// The fragment's modes.
const float M_LIGHT = 0.0;
const float M_LINE = 1.0;
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

void fragment() {
	vec4 colour = vec4(0.0);
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
	COLOR = colour;
}
