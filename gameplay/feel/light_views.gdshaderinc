// SPDX-License-Identifier: GPL-3.0-or-later
// The spell light's buffers, one a view (gameplay/feel/spell_light.gd; connected biomes CB6,
// docs/milestones/connected-biomes.md): what reads the light by its pixel's place on the screen
// (`SCREEN_UV`: the apply rect, the lit-only motes, the mist) reads the buffer of the view it is
// drawn in. With one picture (`light_view_count` 0) that is `light_buffer`, the world camera's.
// While the screen is split each view draws the world again through its own canvas transform, and
// has a buffer of its own that follows it (`light_buffer` the first view's, then `light_buffer_1`
// to `light_buffer_3`); the view a pixel is in is found by its canvas matrix (`CANVAS_MATRIX`, the
// view's own transform), the nearest of the views' (`light_view_0` to `light_view_3`: each its scale
// and origin, set by SpellLight every frame). One material serves every view, so nothing is drawn twice.
//
// A shader that includes this calls `LIGHT_VIEW_FIND` in its vertex function and reads the light
// with `view_light(SCREEN_UV)` in its fragment function.

uniform sampler2D light_buffer : hint_default_black, filter_linear, repeat_disable;
uniform sampler2D light_buffer_1 : hint_default_black, filter_linear, repeat_disable;
uniform sampler2D light_buffer_2 : hint_default_black, filter_linear, repeat_disable;
uniform sampler2D light_buffer_3 : hint_default_black, filter_linear, repeat_disable;
// By view: its canvas transform's scale (x), and its origin (y, z). Only the first
// `light_view_count` are read; 0: one picture, `light_buffer`. (Four uniforms, not an array, so
// they are set each frame without making an array.)
uniform vec4 light_view_0 = vec4(1.0, 0.0, 0.0, 0.0);
uniform vec4 light_view_1 = vec4(1.0, 0.0, 0.0, 0.0);
uniform vec4 light_view_2 = vec4(1.0, 0.0, 0.0, 0.0);
uniform vec4 light_view_3 = vec4(1.0, 0.0, 0.0, 0.0);
uniform int light_view_count = 0;

varying flat int light_view;

#define LIGHT_VIEW_FIND light_view = light_view_of(CANVAS_MATRIX)

// The view whose canvas transform is nearest `canvas` (0 with one picture).
int light_view_of(mat4 canvas) {
	int best = 0;
	float nearest = 1e30;
	for (int k = 0; k < 4; k++) {
		if (k >= light_view_count) {
			break;
		}
		vec4 v = k == 0 ? light_view_0 : (k == 1 ? light_view_1 : (k == 2 ? light_view_2 : light_view_3));
		float d = abs(canvas[0][0] - v.x) * 4096.0 + abs(canvas[3][0] - v.y) + abs(canvas[3][1] - v.z);
		if (d < nearest) {
			nearest = d;
			best = k;
		}
	}
	return best;
}

// The light at `uv` on the screen, from the buffer of the view this is drawn in.
vec3 view_light(vec2 uv) {
	if (light_view == 1) {
		return textureLod(light_buffer_1, uv, 0.0).rgb;
	}
	if (light_view == 2) {
		return textureLod(light_buffer_2, uv, 0.0).rgb;
	}
	if (light_view == 3) {
		return textureLod(light_buffer_3, uv, 0.0).rgb;
	}
	return textureLod(light_buffer, uv, 0.0).rgb;
}
