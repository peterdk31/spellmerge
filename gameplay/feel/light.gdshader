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
//               its flicker, .y a seed and .zw where it stands on the floor from its middle (0: on
//               it; a carried light's staff tip is over its body's feet), what blocking goes by.
// A shot's or a flash's colour is its glow (`look_of` in shot_look.gdshaderinc: its ramp, the
// enemies' for an enemy shot). The light's shape is soft; light_apply.gdshader cuts what it adds
// to the world into steps.
//
// Light is blocked (docs/milestones/atmosphere.md, C): up to MAX_BLOCKERS boxes, the room's
// standing walls and the props that block light, handed over by spell_light.gd (`set_blockers`,
// worked out by gameplay/feel/light_blockers.gd, whose `shade_between` and `lit_as` are this pick in
// GDScript). A box stops the light between a pixel and the light's middle, unless it holds either
// end (a wall's own face, a light standing in a prop). A box may have a column drawn over it (a
// pillar's shaft, `blocker_body`): a pixel there is lit as the floor just in front of the box's
// base, so the shaft's face is lit by a light before or beside it and not by one behind it (its own
// box blocks only a light past its back edge). Where a light is lit from: a spot row from where it
// stands on the floor (its middle, or a carried light's body's feet: a wizard behind a pillar lights
// round itself, and its staff tip over a wall does not open the wall); a flash's or a cue's from its
// middle, moved in front of the base when it is on a shaft (a blast on the pillar's face). How much a box blocks is its strength (it eases out as a
// pillar crumbles). The vertex stage marks which boxes come near the light (`near`), so a
// light near none does no more work than before.

#include "res://core/projectiles/shot_palette.gdshaderinc"
#include "res://core/projectiles/shot_look.gdshaderinc"

// A shot row's light multipliers (its card's `look_light_reach` and `look_light_intensity`, 1 for a
// plain shot): the row's free floats the projectile manager writes them in, LIGHT_REACH_FLOAT (2)
// and LIGHT_INTENSITY_FLOAT (6) of its 16, which a 2D instance's transform hands a shader as
// MODEL_MATRIX[2].x and .y. Named once here (test_light checks they match the manager's).
#define LIGHT_REACH MODEL_MATRIX[2].x
#define LIGHT_INTENSITY MODEL_MATRIX[2].y

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

// The boxes that block light (spell_light.gd's `set_blockers`; light_blockers.gd's MAX): each base
// as x0, y0, x1, y1 (world px), and the column drawn over it as x0, top, x1 and how much it blocks
// (0 to 1; a top at y0 is no column).
const int MAX_BLOCKERS = 32;
uniform int blocker_count = 0;
uniform vec4 blocker_box[32];
uniform vec4 blocker_body[32];

// Where in the light the pixel is (-1 to 1 across), and the light's colour.
varying vec2 spot;
varying flat vec3 lamp;
// The pixel in the world, where the light is lit from (a spot row: where it stands on the floor; a
// flash or a cue: its middle, moved out of a column), and the boxes near the light (a bit each).
varying vec2 world;
varying flat vec2 lamp_at;
varying flat uint near;

bool holds(vec4 box, vec2 p) {
	return p.x >= box.x && p.x <= box.z && p.y >= box.y && p.y <= box.w;
}

// Whether the way from `a` to `b` crosses `box` (the slab test).
bool crosses(vec2 a, vec2 b, vec4 box) {
	vec2 d = b - a;
	float t0 = 0.0;
	float t1 = 1.0;
	for (int axis = 0; axis < 2; axis++) {
		float from = axis == 0 ? a.x : a.y;
		float way = axis == 0 ? d.x : d.y;
		float low = axis == 0 ? box.x : box.y;
		float high = axis == 0 ? box.z : box.w;
		if (abs(way) < 0.0001) {
			if (from < low || from > high) {
				return false;
			}
		} else {
			float ta = (low - from) / way;
			float tb = (high - from) / way;
			t0 = max(t0, min(ta, tb));
			t1 = min(t1, max(ta, tb));
			if (t0 > t1) {
				return false;
			}
		}
	}
	return true;
}

// The box whose column holds `p` (-1: none).
int column_of(vec2 p) {
	for (int k = 0; k < MAX_BLOCKERS; k++) {
		if (k >= blocker_count) {
			break;
		}
		vec4 box = blocker_box[k];
		vec4 body = blocker_body[k];
		if (body.w > 0.0 && body.y < box.y && p.x >= body.x && p.x <= body.z && p.y >= body.y && p.y <= box.w) {
			return k;
		}
	}
	return -1;
}

// Where `p` is lit as: in front of the base of a box whose column it is in, else itself
// (light_blockers.gd's `lit_as`).
vec2 lit_as(vec2 p) {
	int k = column_of(p);
	return k >= 0 ? vec2(p.x, blocker_box[k].w + 0.5) : p;
}

// How much of the light at `l` (where it is lit from) is blocked on its way to the pixel `p` (0 to
// 1; light_blockers.gd's `shade_between`): the strongest box near it that the way crosses and that
// holds neither end. A pixel in a column is lit as the floor in front of its base (`lit_as`), and
// its own box blocks only a light behind it (past its base's back edge): the shaft's face is lit
// from before and beside it, not from behind.
float shade_between(vec2 p, vec2 l, uint near_bits) {
	float shade = 0.0;
	int own = column_of(p);
	vec2 at = p;
	if (own >= 0) {
		at = vec2(p.x, blocker_box[own].w + 0.5);
		if (l.y < blocker_box[own].y) {
			shade = blocker_body[own].w;
		}
	}
	for (int k = 0; k < MAX_BLOCKERS; k++) {
		if (k >= blocker_count) {
			break;
		}
		if (k == own || ((near_bits >> uint(k)) & 1u) == 0u) {
			continue;
		}
		vec4 box = blocker_box[k];
		float strength = blocker_body[k].w;
		if (strength <= shade || holds(box, at) || holds(box, l)) {
			continue;
		}
		if (crosses(at, l, box)) {
			shade = strength;
		}
	}
	return shade;
}

void vertex() {
	vec2 corner = UV * 2.0 - 1.0;
	spot = corner;
	vec2 centre = MODEL_MATRIX[3].xy;
	// The light's half size along its two ways (x along MODEL_MATRIX[0], y along [1]).
	vec2 half_size = vec2(0.0);
	vec2 way = vec2(1.0, 0.0);
	vec3 colour = vec3(0.0);
	// Where a spot row stands on the floor, from its middle.
	vec2 ground = vec2(0.0);
	if (rows == ROWS_RUNE) {
		// Its card's light reach and intensity (`look_light_reach`, `look_light_intensity`) in the
		// row's free floats (LIGHT_REACH, LIGHT_INTENSITY; 1 for a plain shot).
		float reach = length(MODEL_MATRIX[0].xy) * 0.5 * RUNE_REACH * LIGHT_REACH;
		half_size = vec2(reach);
		colour = look_from_color(COLOR, INSTANCE_CUSTOM.rgb, 0.0, false).glow * rune_strength * LIGHT_INTENSITY;
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
		ground = INSTANCE_CUSTOM.zw;
	} else {
		// Every live shot lights (tails are motes since the owner's pick of 2026-11-05: the shot
		// batches hold only live shots, each with HF_LIVE).
		float flags = MODEL_MATRIX[1].y;
		if (flag_set(flags, HF_LIVE)) {
			float red = floor(COLOR.r * 255.0 + 0.5);
			float reach = red < 4.0 ? SPECK_REACH : SHOT_REACH + SHOT_REACH_ZOOM * max(floor(red / 4.0), 1.0);
			// Times its card's light reach and intensity, as a rune's.
			half_size = vec2(reach * LIGHT_REACH);
			colour = look_from_color(COLOR, INSTANCE_CUSTOM.rgb, 0.0, false).glow * shot_strength * LIGHT_INTENSITY;
		}
	}
	near = 0u;
	lamp_at = centre;
	if (half_size.x <= 0.0 || dot(colour, colour) <= 0.0) {
		// Folded away: no light.
		VERTEX = vec2(0.0);
		lamp = vec3(0.0);
	} else {
		lamp = colour;
		vec2 across = vec2(-way.y, way.x);
		VERTEX = centre + way * corner.x * half_size.x + across * corner.y * half_size.y;
		if (blocker_count > 0) {
			lamp_at = rows == ROWS_SPOT ? centre + ground : lit_as(centre);
			// The boxes (with their columns) that meet the light's square, grown to where it is lit from.
			float r = length(half_size);
			vec4 lit = vec4(min(centre - vec2(r), lamp_at), max(centre + vec2(r), lamp_at));
			for (int k = 0; k < MAX_BLOCKERS; k++) {
				if (k >= blocker_count) {
					break;
				}
				vec4 box = blocker_box[k];
				vec4 all = vec4(min(box.x, blocker_body[k].x), min(box.y, blocker_body[k].y), max(box.z, blocker_body[k].z), box.w);
				if (blocker_body[k].w > 0.0 && all.x <= lit.z && all.z >= lit.x && all.y <= lit.w && all.w >= lit.y) {
					near |= 1u << uint(k);
				}
			}
		}
	}
	world = VERTEX;
}

void fragment() {
	float f = clamp(1.0 - length(spot), 0.0, 1.0);
	float open = 1.0;
	if (near != 0u && f > 0.0) {
		open = 1.0 - shade_between(world, lamp_at, near);
	}
	COLOR = vec4(lamp * f * f * open, 1.0);
}
