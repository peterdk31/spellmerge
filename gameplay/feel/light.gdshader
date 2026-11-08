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
//   ROWS_SHOT   the projectile manager's shot rows (shot_head.gdshader): MODEL_MATRIX[1].y the
//               flags (HF_*), MODEL_MATRIX[3].xy the head. Only a live shot's head gives light, not
//               a dash. Every shot, the enemies' too (one rule).
//   ROWS_RUNE   its still shots' rows (one quad each: a card's shot shader, or shot_still.gdshader): a real transform, a square quad of the
//               rune's size round its centre.
//               Both kinds of shot row carry its card's light (`look_light_reach` and
//               `look_light_intensity`, 1 for a plain shot) in MODEL_MATRIX[2].x and .y (the
//               manager's LIGHT_REACH_FLOAT and LIGHT_INTENSITY_FLOAT): its reach and brightness
//               are multiplied by them.
//   ROWS_FLASH  Feel's flash rows (shot_flash, shot_blast, shot_arc): a real transform (its
//               square, or an arc's length and width) round its centre, its second unused float
//               (MODEL_MATRIX[2].y) how much it lights at its start (its kind's `room_light`, 0
//               for a flash that does not light), fading out over its life: INSTANCE_CUSTOM.a its
//               code and how far through its life it is (Feel's FLASH_FROM, FLASH_SPAN).
//   ROWS_CUE    the cues' `light` parts (S6 item 4), written by spell_light.gd while they last: a
//               transform scaled by the reach round the cue's point, COLOR and INSTANCE_CUSTOM.rgb
//               a flash row's colour (its ramp, cards and core, or an exact colour), and
//               INSTANCE_CUSTOM.a how bright it is now (it fades over its seconds).
//   ROWS_SPOT   the room's light spots (core/base/light_spot.gd), written by spell_light.gd: a
//               transform scaled by the reach, COLOR its colour and strength, INSTANCE_CUSTOM.x
//               its flicker and .y a seed.
// A shot's or a flash's colour is its glow (`look_of` in shot_look.gdshaderinc: its ramp, the
// enemies' for an enemy shot). The light's shape is soft; light_apply.gdshader cuts what it adds
// to the world into steps.

#include "res://core/projectiles/shot_palette.gdshaderinc"
#include "res://core/projectiles/shot_look.gdshaderinc"

const int ROWS_SHOT = 0;
const int ROWS_RUNE = 1;
const int ROWS_FLASH = 2;
const int ROWS_SPOT = 3;
const int ROWS_CUE = 4;
uniform int rows = 0;
// How bright a light is at its middle (the buffer adds them, up to 1 a channel).
uniform float shot_strength = 0.9;
uniform float rune_strength = 0.55;
// A flash's light reaches this many times its half size, and this much past it (px).
uniform float flash_reach = 1.0;
uniform float flash_pad = 10.0;

// HEAD_LIVE (in projectile_manager.gd): the shot lives.
const float HF_LIVE = 1.0;
// A shot's light reaches this far (px), and this much more a zoom; a speck's (zoom 0) is smaller.
const float SHOT_REACH = 26.0;
const float SHOT_REACH_ZOOM = 6.0;
const float SPECK_REACH = 14.0;
// A rune's light reaches this many times its quad's half size.
const float RUNE_REACH = 1.5;
// Feel's FLASH_FROM and FLASH_SPAN: how a flash's life is coded after its kind.
const float FLASH_FROM = 0.02;
const float FLASH_SPAN = 0.42;
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
		// Its card's light reach and intensity (`look_light_reach`, `look_light_intensity`) in the
		// row's free floats, MODEL_MATRIX[2].x and .y (the manager's LIGHT_*_FLOAT; 1 for a plain shot).
		float reach = length(MODEL_MATRIX[0].xy) * 0.5 * RUNE_REACH * MODEL_MATRIX[2].x;
		half_size = vec2(reach);
		colour = look_from_color(COLOR, INSTANCE_CUSTOM.rgb, 0.0, false).glow * rune_strength * MODEL_MATRIX[2].y;
	} else if (rows == ROWS_FLASH) {
		float through = clamp((coded_code(INSTANCE_CUSTOM.a) - FLASH_FROM) / FLASH_SPAN, 0.0, 1.0);
		float strength = MODEL_MATRIX[2].y * (1.0 - through);
		if (strength > 0.0) {
			vec2 along = MODEL_MATRIX[0].xy;
			way = length(along) > 0.0 ? normalize(along) : vec2(1.0, 0.0);
			half_size = vec2(length(along), length(MODEL_MATRIX[1].xy)) * 0.5 * flash_reach + vec2(flash_pad);
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
		// Every live shot lights (tails are motes since the owner's pick of 2026-11-05: the shot
		// batches hold only live shots, each with HF_LIVE).
		float flags = MODEL_MATRIX[1].y;
		if (flag_set(flags, HF_LIVE)) {
			float red = floor(COLOR.r * 255.0 + 0.5);
			float reach = red < 4.0 ? SPECK_REACH : SHOT_REACH + SHOT_REACH_ZOOM * max(floor(red / 4.0), 1.0);
			// Times its card's light reach and intensity, as a rune's (MODEL_MATRIX[2].x and .y).
			half_size = vec2(reach * MODEL_MATRIX[2].x);
			colour = look_from_color(COLOR, INSTANCE_CUSTOM.rgb, 0.0, false).glow * shot_strength * MODEL_MATRIX[2].y;
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
