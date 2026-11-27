// SPDX-License-Identifier: GPL-3.0-or-later
shader_type canvas_item;

// Spell light on the world (gameplay/feel/spell_light.gd; docs/milestones/spell-spectacle.md,
// P3a, P3b): one rect over the whole view, drawn above the room and the bodies and under every
// shot, effect and telegraph, that multiplies what is under it by `ambient` plus the light
// buffer's light, in the light's own hue. How the light is cut is `bands`, by its brightest
// channel: 3 (the default) is three steps (dim: none; lit; bright), so a lit floor changes by
// whole bands, like a shade step; 2 is one step; more are more steps between `lit_from` and
// `bright_from`; 0 is no steps, a smooth gradient through the same light (through the steps'
// corners). The owner's choice between the two is open (2026-11-04). Where nothing is lit and the ambient is 1.0
// nothing is drawn: the room looks as it does without spell light until something glows.
//
// The one pass (the owner's decision of 2026-11-22): at any size of picture the factor is worked out
// here, a pixel at a time, from the grid, and the screen is read once; nothing is drawn for it first.
//
// It multiplies by reading the screen, not by blending: a multiply blend cannot brighten (its
// factor is clamped to 1 in an 8-bit target, the web's included), and light added on top would
// wash a dark floor out instead of lighting its colours.

// The light: the grid of the view it is drawn in, at the pixel's world point (light_views.gdshaderinc,
// light_grid.gdshaderinc; grid lighting).
#include "res://gameplay/feel/light_views.gdshaderinc"
#include "res://gameplay/feel/light_apply.gdshaderinc"
uniform sampler2D screen : hint_screen_texture, filter_nearest, repeat_disable;
// Where the pixel is in the world (the rect's own place through its transform: the world's).
varying vec2 world_at;

void vertex() {
	LIGHT_VIEW_FIND;
	world_at = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	// An art pixel at a time (whole-pixel bands at any size of picture, as the mist and the tints; ART3:
	// a light's pool on the floor steps by the art's finer pixel).
	vec2 at = art_centre(world_at);
	bool unchanged;
	vec3 factor = light_factor(view_light(at), at, unchanged);
	if (unchanged) {
		discard;
	}
	vec3 under = texture(screen, SCREEN_UV).rgb;
	COLOR = vec4(under * factor, 1.0);
}
