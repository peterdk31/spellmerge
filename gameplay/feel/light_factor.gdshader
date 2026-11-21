// SPDX-License-Identifier: GPL-3.0-or-later
shader_type canvas_item;
render_mode blend_disabled;

// The spell light's factor at the light's resolution (gameplay/feel/spell_light.gd, light_passes.gd;
// the owner's decision of 2026-11-21, docs/milestones/connected-biomes.md, "The light at a fixed
// resolution"): one rect over the world in a view's factor pass, a pass `PictureGrid.scale_of` times
// smaller than the view, that writes what the apply rect multiplies each block of the picture by
// (light_apply.gdshaderinc's `light_factor`, packed: light_pack.gdshaderinc). It reads its view's
// light buffer at its own pixel, as the apply rect read it a pixel of the picture at PictureGrid.SIZE.
// Written as it is (`blend_disabled`): the pass holds numbers, not a picture.

uniform sampler2D light_buffer : hint_default_black, filter_linear, repeat_disable;
#include "res://gameplay/feel/light_apply.gdshaderinc"

// Where the pixel is in the world (the rect's own place through its transform: the world's).
varying vec2 world_at;

#include "res://gameplay/feel/light_pack.gdshaderinc"

void vertex() {
	world_at = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	bool unchanged;
	vec3 factor = light_factor(textureLod(light_buffer, SCREEN_UV, 0.0).rgb, world_at, unchanged);
	COLOR = light_pack_factor(unchanged ? vec3(1.0) : factor);
}
