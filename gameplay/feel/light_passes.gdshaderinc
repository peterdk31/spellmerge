// SPDX-License-Identifier: GPL-3.0-or-later
// A pass drawn at the light's resolution, read by a reader of the light (gameplay/feel/light_passes.gd,
// picture_grid.gd; the owner's decision of 2026-11-21, docs/milestones/connected-biomes.md, "The light at
// a fixed resolution"). While the picture is bigger than PictureGrid.SIZE, what is worked out a pixel at a
// time over the whole picture (the apply rect's light, the mist's billows) is drawn into a pass a view
// `light_pass_scale` times smaller each way, and the reader drawn in the picture takes the pass's pixel
// for its whole block (`texelFetch`: whole blocks, never blurred). A view with no pass (the one picture
// at PictureGrid.SIZE, the equal split's void quarter) works it out where it is drawn, as before.
//
// Include it after light_views.gdshaderinc (it reads `light_view`). The pass writes its numbers packed and
// the reader unpacks them (light_pack.gdshaderinc).

#include "res://gameplay/feel/light_pack.gdshaderinc"

uniform sampler2D light_pass_0 : hint_default_black, filter_nearest, repeat_disable;
uniform sampler2D light_pass_1 : hint_default_black, filter_nearest, repeat_disable;
uniform sampler2D light_pass_2 : hint_default_black, filter_nearest, repeat_disable;
uniform sampler2D light_pass_3 : hint_default_black, filter_nearest, repeat_disable;
// A bit a view that has a pass (bit k: view k), and how many times smaller each way a pass is.
uniform int light_pass_views = 0;
uniform int light_pass_scale = 1;

// Whether the view this is drawn in has a pass.
bool light_pass_here() {
	return light_view >= 0 && light_view < 4 && ((light_pass_views >> light_view) & 1) != 0;
}

// The pass's pixel under the picture's pixel at `uv` (`SCREEN_UV`; `pixel`: `SCREEN_PIXEL_SIZE`): its block.
vec4 light_pass_at(vec2 uv, vec2 pixel) {
	ivec2 at = ivec2(floor(uv / pixel)) / ivec2(max(light_pass_scale, 1));
	if (light_view == 1) {
		return texelFetch(light_pass_1, at, 0);
	}
	if (light_view == 2) {
		return texelFetch(light_pass_2, at, 0);
	}
	if (light_view == 3) {
		return texelFetch(light_pass_3, at, 0);
	}
	return texelFetch(light_pass_0, at, 0);
}
