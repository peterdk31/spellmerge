// SPDX-License-Identifier: GPL-3.0-or-later
// The spell light's buffers, one a view (gameplay/feel/spell_light.gd; connected biomes CB6,
// docs/milestones/connected-biomes.md): what reads the light by its pixel's place on the screen
// (`SCREEN_UV`: the apply rect, the lit-only motes, the mist) reads the buffer of the view it is
// drawn in. With one picture that is `light_buffer`, the world camera's.
// While the screen is split each view draws the world again through its own canvas transform, and
// has a buffer of its own that follows it (`light_buffer` the first view's, then `light_buffer_1`
// to `light_buffer_3`). Which view a reader is drawn in (`ViewReaders`,
// gameplay/feel/view_readers.gd; the owner's decisions of 2026-11-20):
// - the third and fourth views draw a copy of it, on their own visibility layer, with their own copy
//   of the material, which names its view by the uniform `light_view_id` (2 or 3);
// - the first two views share the item itself (`light_view_id` 0): while they are drawn
//   (`light_views_shared`) it is in the one whose canvas transform and size (`light_view_0`,
//   `light_view_1`: scale, origin; `light_view_size_0`, `_1`) are nearer what it is drawn through
//   (`CANVAS_MATRIX`, and the viewport's size from `SCREEN_MATRIX`), `ViewReaders.view_of` line for line.
//
// A shader that includes this calls `LIGHT_VIEW_FIND` in its vertex function and reads the light
// with `view_light(SCREEN_UV)` in its fragment function.

uniform sampler2D light_buffer : hint_default_black, filter_linear, repeat_disable;
uniform sampler2D light_buffer_1 : hint_default_black, filter_linear, repeat_disable;
uniform sampler2D light_buffer_2 : hint_default_black, filter_linear, repeat_disable;
uniform sampler2D light_buffer_3 : hint_default_black, filter_linear, repeat_disable;
// The view a copy is drawn in (ViewReaders.VIEW_ID); 0: the item itself (the one picture, or one of
// the first two views).
uniform int light_view_id = 0;
uniform bool light_views_shared = false;
uniform vec4 light_view_0 = vec4(0.0);
uniform vec4 light_view_1 = vec4(0.0);
uniform vec2 light_view_size_0 = vec2(0.0);
uniform vec2 light_view_size_1 = vec2(0.0);
// ViewReaders.SIZE_WEIGHT: a pixel of size against a pixel of origin (only a tie's breaker).
const float LIGHT_SIZE_WEIGHT = 0.001;

varying flat int light_view;

#define LIGHT_VIEW_FIND light_view = light_view_of(CANVAS_MATRIX, SCREEN_MATRIX)

// The view this is drawn in: a copy's own, or the nearer of the first two by what it is drawn
// through (`canvas`, and `screen`'s size: 2 / its scale each way).
int light_view_of(mat4 canvas, mat4 screen) {
	if (light_view_id != 0 || !light_views_shared) {
		return light_view_id;
	}
	vec2 size = 2.0 / max(abs(vec2(screen[0][0], screen[1][1])), vec2(1.0e-6));
	int best = 0;
	float nearest = 1.0e30;
	for (int k = 0; k < 2; k++) {
		vec4 v = k == 0 ? light_view_0 : light_view_1;
		vec2 s = k == 0 ? light_view_size_0 : light_view_size_1;
		float d = abs(canvas[0][0] - v.x) * 4096.0 + abs(canvas[3][0] - v.y) + abs(canvas[3][1] - v.z);
		d += (abs(size.x - s.x) + abs(size.y - s.y)) * LIGHT_SIZE_WEIGHT;
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
