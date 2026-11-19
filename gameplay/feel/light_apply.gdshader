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
// It multiplies by reading the screen, not by blending: a multiply blend cannot brighten (its
// factor is clamped to 1 in an 8-bit target, the web's included), and light added on top would
// wash a dark floor out instead of lighting its colours.

// The light buffer (the light viewport's texture: the same view, smaller; a view's own while the
// screen is split, light_views.gdshaderinc). Linear, so a band's edge is cut at the world's pixels,
// not the buffer's.
#include "res://gameplay/feel/light_views.gdshaderinc"
uniform sampler2D screen : hint_screen_texture, filter_nearest, repeat_disable;
// The room's light where no spell lights it (1.0: as it is), and the colour of its dark
// (`RoomBase.shade`; white: an even dark), multiplied together.
uniform float ambient = 1.0;
uniform vec3 shade = vec3(1.0);
// From how bright a light the world is lit, and bright (set from SpellLight.LIT_FROM and
// BRIGHT_FROM, which the lit-only motes' steps come from too); and how much each step adds.
uniform float lit_from = 0.16;
uniform float bright_from = 0.45;
uniform float lit_gain = 0.22;
uniform float bright_gain = 0.45;
// The steps the light comes in (see above): 0 smooth, else that many (dim counted), at least 2.
uniform int bands = 3;
// Each room's own light tinted by its kind (connected biomes CB12b, gameplay/feel/room_tints.gd):
// `tint_count` world rectangles (x0, y0, x1, y1) and, for each, the hue its dark and its light lean
// toward (rgb) and how far (a). Past a room's edge its tint steps down in EDGE_BANDS whole-pixel
// bands EDGE_BAND px wide onto its bridges (two thirds, a third, then none: RoomTints.EDGE_BAND and
// EDGE_BANDS); a pixel farther from every tinted room is untinted. MAX_TINTS is SpellLight.MAX_TINTS.
#define MAX_TINTS 40
#define EDGE_BAND 6.0
#define EDGE_BANDS 2.0
uniform vec4 tint_rects[MAX_TINTS];
uniform vec4 tint_hues[MAX_TINTS];
uniform int tint_count = 0;

// Where the pixel is in the world (the rect's own place through its transform: the world's).
varying vec2 world_at;

// The tint at world point `at`: the room's it is in, else the strongest edge band of a room it is
// near (a: 0 for none). Worked out a world pixel at a time (whole-pixel bands).
vec4 room_tint(vec2 at) {
	vec2 p = floor(at) + 0.5;
	vec4 edge = vec4(1.0, 1.0, 1.0, 0.0);
	for (int k = 0; k < MAX_TINTS; k++) {
		if (k >= tint_count) {
			break;
		}
		vec4 r = tint_rects[k];
		if (at.x >= r.x && at.y >= r.y && at.x < r.z && at.y < r.w) {
			return tint_hues[k];
		}
		vec2 out_by = max(max(r.xy - p, p - r.zw), vec2(0.0));
		float band = floor(max(out_by.x, out_by.y) / EDGE_BAND);
		if (band < EDGE_BANDS) {
			float a = tint_hues[k].a * (EDGE_BANDS - band) / (EDGE_BANDS + 1.0);
			if (a > edge.a) {
				edge = vec4(tint_hues[k].rgb, a);
			}
		}
	}
	return edge;
}

// The light a pixel adds for a light of brightest channel `most`.
float gain_of(float most) {
	if (bands <= 0) {
		// The same light with no steps: a line through the steps' corners (none to lit at
		// lit_from, to bright at bright_from), then flat.
		if (most < lit_from) {
			return most / lit_from * lit_gain;
		}
		return mix(lit_gain, bright_gain, clamp((most - lit_from) / (bright_from - lit_from), 0.0, 1.0));
	}
	// Steps at lit_from .. bright_from, their gains lit_gain .. bright_gain, evenly between.
	int steps = max(bands - 1, 1);
	float gain = 0.0;
	for (int k = 0; k < steps; k++) {
		float share = steps > 1 ? float(k) / float(steps - 1) : 0.0;
		if (most >= mix(lit_from, bright_from, share)) {
			gain = mix(lit_gain, bright_gain, share);
		}
	}
	return gain;
}

void vertex() {
	LIGHT_VIEW_FIND;
	world_at = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	vec3 shine = view_light(SCREEN_UV);
	float most = max(shine.r, max(shine.g, shine.b));
	float gain = gain_of(most);
	vec4 tint = tint_count > 0 ? room_tint(world_at) : vec4(1.0, 1.0, 1.0, 0.0);
	vec3 dark = vec3(ambient) * shade * mix(vec3(1.0), tint.rgb, tint.a);
	if (gain < 0.004 && min(dark.r, min(dark.g, dark.b)) >= 1.0) {
		discard;
	}
	vec3 hue = gain > 0.0 && most > 0.0 ? mix(shine / most, tint.rgb, tint.a) : vec3(0.0);
	vec3 under = texture(screen, SCREEN_UV).rgb;
	COLOR = vec4(under * (dark + hue * gain), 1.0);
}
