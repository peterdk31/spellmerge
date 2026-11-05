// SPDX-License-Identifier: GPL-3.0-or-later
shader_type canvas_item;
// world_vertex_coords: VERTEX is in world space in vertex(), so each light is placed in the world
// (the light buffer's canvas transform is the camera's, scaled down).
render_mode blend_add, world_vertex_coords;

// Spell light (gameplay/feel/spell_light.gd; docs/milestones/spell-spectacle.md, P3a, P3b): one
// soft round light per row, drawn into the light buffer, a small screen-sized texture cleared to
// black every frame, with a quad of size 1 at the origin. The rows are someone else's, handed
// over as they are uploaded (nothing is written twice), read as `rows` says (ROWS_* in
// spell_light.gd):
//   ROWS_TRAIL  the projectile manager's trail rows (shot_trail.gdshader): MODEL_MATRIX[0].x the
//               trail's row (below 0: none), MODEL_MATRIX[1].y its flags (TF_*),
//               MODEL_MATRIX[3].xy the head. Only a live shot's head gives light, not a trail
//               left behind or a dash. Every shot, the enemies' too (one rule).
//   ROWS_RUNE   its rune rows (shot_rune.gdshader): a real transform, a square quad of the
//               rune's size round its centre.
//   ROWS_EFFECT Feel's effect rows (shot_effect, shot_blast, shot_arc): a real transform (its
//               square, or an arc's length and width) round its centre, INSTANCE_CUSTOM.a its
//               kind and how far through its life it is (Feel's EFFECT_FROM, EFFECT_SPAN; coded
//               below the kind for an effect that does not light). Each kind's light is
//               `kind_light` (0: none), fading out over its life.
//   ROWS_CUE    the cues' `light` parts (S6 item 4), written by spell_light.gd while they last: a
//               transform scaled by the reach round the cue's point, COLOR and INSTANCE_CUSTOM.rgb
//               an effect row's colour (its ramp, cards and core, or an exact colour), and
//               INSTANCE_CUSTOM.a how bright it is now (it fades over its seconds).
//   ROWS_SPOT   the room's light spots (core/base/light_spot.gd), written by spell_light.gd: a
//               transform scaled by the reach, COLOR its colour and strength, INSTANCE_CUSTOM.x
//               its flicker and .y a seed.
// A shot's or an effect's colour is its glow (`look_of` in shot_look.gdshaderinc: its ramp, the
// enemies' for an enemy shot). The light's shape is soft; light_apply.gdshader cuts what it adds
// to the world into steps.

#include "res://core/projectiles/shot_palette.gdshaderinc"
#include "res://core/projectiles/shot_look.gdshaderinc"

const int ROWS_TRAIL = 0;
const int ROWS_RUNE = 1;
const int ROWS_EFFECT = 2;
const int ROWS_SPOT = 3;
const int ROWS_CUE = 4;
uniform int rows = 0;
// How bright a light is at its middle (the buffer adds them, up to 1 a channel).
uniform float shot_strength = 0.9;
uniform float rune_strength = 0.55;
// Each effect kind's light (by its code: Feel's KIND_*, less KIND_SHELL for a blast).
uniform float kind_light[16];
// An effect's light reaches this many times its half size, and this much past it (px).
uniform float effect_reach = 1.0;
uniform float effect_pad = 10.0;

// TRAIL_HEAD and TRAIL_DASH (TRAIL_* in projectile_manager.gd): the shot lives, a wizard's dash.
const float TF_HEAD = 1.0;
const float TF_DASH = 4.0;
// A shot's light reaches this far (px), and this much more a zoom; a speck's (zoom 0) is smaller.
const float SHOT_REACH = 26.0;
const float SHOT_REACH_ZOOM = 6.0;
const float SPECK_REACH = 14.0;
// A rune's light reaches this many times its quad's half size.
const float RUNE_REACH = 1.5;
// Feel's EFFECT_FROM and EFFECT_SPAN: how an effect's life is coded after its kind.
const float EFFECT_FROM = 0.02;
const float EFFECT_SPAN = 0.42;
// A light spot's flicker: steps a second.
const float SPOT_RATE = 7.0;

// Where in the light the pixel is (-1 to 1 across), and the light's colour.
varying vec2 spot;
varying flat vec3 lamp;

void vertex() {
	vec2 corner = UV * 2.0 - 1.0;
	spot = corner;
	vec2 centre = MODEL_MATRIX[3].xy;
	// The light's half size along its two ways (x along MODEL_MATRIX[0], y along [1]).
	vec2 half_size = vec2(0.0);
	vec2 way = vec2(1.0, 0.0);
	vec3 colour = vec3(0.0);
	if (rows == ROWS_RUNE) {
		float reach = length(MODEL_MATRIX[0].xy) * 0.5 * RUNE_REACH;
		half_size = vec2(reach);
		colour = look_from_color(COLOR, INSTANCE_CUSTOM.rgb, 0.0, false).glow * rune_strength;
	} else if (rows == ROWS_EFFECT) {
		// Its age below its kind: an effect of a cue that lights by its own `light` part, unlit.
		float kind = coded_kind(INSTANCE_CUSTOM.a);
		float code = coded_code(INSTANCE_CUSTOM.a);
		float through = clamp((code - EFFECT_FROM) / EFFECT_SPAN, 0.0, 1.0);
		float strength = code > 0.0 ? kind_light[int(clamp(kind, 0.0, 15.0))] * (1.0 - through) : 0.0;
		if (strength > 0.0) {
			vec2 along = MODEL_MATRIX[0].xy;
			way = length(along) > 0.0 ? normalize(along) : vec2(1.0, 0.0);
			half_size = vec2(length(along), length(MODEL_MATRIX[1].xy)) * 0.5 * effect_reach + vec2(effect_pad);
			colour = look_from_color(COLOR, INSTANCE_CUSTOM.rgb, 0.0, false).glow * strength;
		}
	} else if (rows == ROWS_CUE) {
		half_size = vec2(length(MODEL_MATRIX[0].xy));
		colour = look_from_color(COLOR, INSTANCE_CUSTOM.rgb, 0.0, false).glow * INSTANCE_CUSTOM.a;
	} else if (rows == ROWS_SPOT) {
		float reach = length(MODEL_MATRIX[0].xy);
		float step_of = floor(TIME * SPOT_RATE + INSTANCE_CUSTOM.y * 13.0);
		float dip = INSTANCE_CUSTOM.x * fract(sin(step_of * 12.9898 + INSTANCE_CUSTOM.y * 78.233) * 43758.5453);
		half_size = vec2(reach);
		colour = COLOR.rgb * COLOR.a * (1.0 - dip);
	} else {
		// Every live shot lights, with a trail row or without (tails as motes: none has one; the
		// owner, 2026-11-05). A cooling tail's row is no head, a dash's is TF_DASH.
		float flags = MODEL_MATRIX[1].y;
		if (flag_set(flags, TF_HEAD) && !flag_set(flags, TF_DASH)) {
			float red = floor(COLOR.r * 255.0 + 0.5);
			float reach = red < 4.0 ? SPECK_REACH : SHOT_REACH + SHOT_REACH_ZOOM * max(floor(red / 4.0), 1.0);
			half_size = vec2(reach);
			colour = look_from_color(COLOR, INSTANCE_CUSTOM.rgb, 0.0, false).glow * shot_strength;
		}
	}
	if (half_size.x <= 0.0 || dot(colour, colour) <= 0.0) {
		// Folded away: no light.
		VERTEX = vec2(0.0);
		lamp = vec3(0.0);
	} else {
		lamp = colour;
		vec2 across = vec2(-way.y, way.x);
		VERTEX = centre + way * corner.x * half_size.x + across * corner.y * half_size.y;
	}
}

void fragment() {
	float f = clamp(1.0 - length(spot), 0.0, 1.0);
	COLOR = vec4(lamp * f * f, 1.0);
}
