// SPDX-License-Identifier: GPL-3.0-or-later
shader_type canvas_item;
// world_vertex_coords: VERTEX is in world space in vertex(), so each light is placed in the world
// (the light buffer's canvas transform is the camera's, scaled down).
render_mode blend_add, world_vertex_coords;

// Shot light (gameplay/feel/spell_light.gd; docs/milestones/spell-spectacle.md, P3a): one soft
// round light per live shot, drawn into the light buffer, a small screen-sized texture cleared
// to black every frame. The rows are the projectile manager's own (its batch's buffer, handed
// over as it is uploaded: `mirror_batch`), drawn with a quad of size 1 at the origin:
//   trail rows   (`rune_rows` false; shot_trail.gdshader): MODEL_MATRIX[0].x the trail's row
//                (below 0: none), MODEL_MATRIX[1].y its flags (TF_*), MODEL_MATRIX[3].xy the
//                head. Only a live shot's head gives light, not a trail left behind or a dash.
//   rune rows    (`rune_rows` true; shot_rune.gdshader): a real transform, a square quad of the
//                rune's size round its centre.
// The colour is the shot's glow (`look_of` in shot_look.gdshaderinc: its ramp, the enemies' for
// an enemy shot). The light's shape is soft; light_apply.gdshader cuts what it adds to the world
// into three steps.

#include "res://core/projectiles/shot_palette.gdshaderinc"
#include "res://core/projectiles/shot_look.gdshaderinc"

// The batch's rows are runes (a real transform) rather than trails.
uniform bool rune_rows = false;
// How bright a light is at its middle (the buffer adds them, up to 1 a channel).
uniform float shot_strength = 0.9;
uniform float rune_strength = 0.55;

// TRAIL_HEAD and TRAIL_DASH (TRAIL_* in projectile_manager.gd): the shot lives, a wizard's dash.
const float TF_HEAD = 1.0;
const float TF_DASH = 4.0;
// A shot's light reaches this far (px), and this much more a zoom; a speck's (zoom 0) is smaller.
const float SHOT_REACH = 26.0;
const float SHOT_REACH_ZOOM = 6.0;
const float SPECK_REACH = 14.0;
// A rune's light reaches this many times its quad's half size.
const float RUNE_REACH = 1.5;

// Where in the light the pixel is (-1 to 1 across), and the light's colour.
varying vec2 spot;
varying flat vec3 lamp;

void vertex() {
	vec2 corner = UV * 2.0 - 1.0;
	spot = corner;
	vec2 centre = MODEL_MATRIX[3].xy;
	float reach = 0.0;
	float strength = 0.0;
	if (rune_rows) {
		reach = length(MODEL_MATRIX[0].xy) * 0.5 * RUNE_REACH;
		strength = rune_strength;
	} else {
		float row = MODEL_MATRIX[0].x;
		float flags = MODEL_MATRIX[1].y;
		if (row >= 0.0 && flag_set(flags, TF_HEAD) && !flag_set(flags, TF_DASH)) {
			float red = floor(COLOR.r * 255.0 + 0.5);
			reach = red < 4.0 ? SPECK_REACH : SHOT_REACH + SHOT_REACH_ZOOM * max(floor(red / 4.0), 1.0);
			strength = shot_strength;
		}
	}
	if (reach <= 0.0) {
		// Folded away: no light.
		VERTEX = vec2(0.0);
		lamp = vec3(0.0);
	} else {
		Look L = look_from_color(COLOR, INSTANCE_CUSTOM.rgb, 0.0, false);
		lamp = L.glow * strength;
		VERTEX = centre + corner * reach;
	}
}

void fragment() {
	float f = clamp(1.0 - length(spot), 0.0, 1.0);
	COLOR = vec4(lamp * f * f, 1.0);
}
