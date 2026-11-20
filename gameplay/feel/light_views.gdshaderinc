// SPDX-License-Identifier: GPL-3.0-or-later
// The spell light's buffers, one a view (gameplay/feel/spell_light.gd; connected biomes CB6,
// docs/milestones/connected-biomes.md): what reads the light by its pixel's place on the screen
// (`SCREEN_UV`: the apply rect, the lit-only motes, the mist) reads the buffer of the view it is
// drawn in. With one picture that is `light_buffer`, the world camera's.
// While the screen is split each view draws the world again through its own canvas transform, and
// has a buffer of its own that follows it (`light_buffer` the first view's, then `light_buffer_1`
// to `light_buffer_3`); the view a reader is drawn in is named by its instance uniform
// `light_view_id` (0 to 3; the performance pass of 2026-11-20, the owner: named, never matched):
// each reader is one canvas item a view, each on its view's visibility layer only (`ViewReaders`,
// gameplay/feel/view_readers.gd), all sharing one material, so nothing is drawn twice.
//
// A shader that includes this reads the light with `view_light(SCREEN_UV)` in its fragment function.

uniform sampler2D light_buffer : hint_default_black, filter_linear, repeat_disable;
uniform sampler2D light_buffer_1 : hint_default_black, filter_linear, repeat_disable;
uniform sampler2D light_buffer_2 : hint_default_black, filter_linear, repeat_disable;
uniform sampler2D light_buffer_3 : hint_default_black, filter_linear, repeat_disable;
// The view this canvas item is drawn in (ViewReaders.VIEW_ID); 0: the one picture or the first view.
instance uniform int light_view_id = 0;

// The light at `uv` on the screen, from the buffer of the view this is drawn in.
vec3 view_light(vec2 uv) {
	if (light_view_id == 1) {
		return textureLod(light_buffer_1, uv, 0.0).rgb;
	}
	if (light_view_id == 2) {
		return textureLod(light_buffer_2, uv, 0.0).rgb;
	}
	if (light_view_id == 3) {
		return textureLod(light_buffer_3, uv, 0.0).rgb;
	}
	return textureLod(light_buffer, uv, 0.0).rgb;
}
