// SPDX-License-Identifier: GPL-3.0-or-later
// Grid lighting (gameplay/feel/light_grid.gd, spell_light.gd; the owner's decision of 2026-11-21): the
// spell light worked out on the CPU on a grid of world cells, `light_grid_cell` px each way, a grid a
// view laid side by side in one small texture (`light_grid`). A reader of the light takes the cell its
// world point lies in (`grid_light`): whole cells, never blurred; with `light_grid_smooth` the four
// nearest cells' middles weighed by where the point lies between them (the bands the readers cut it
// into then follow the world's pixels, still in hard steps). Outside its view's grid there is no light.
//
// View k's grid: `light_grid_view_k` its first cell's corner (world x, y) and where its cells start in
// the texture (x, y), `light_grid_size_k` its columns and rows (none: no light in that view, the equal
// split's void quarter). One uniform each, not arrays, so a frame hands over numbers, not arrays.

uniform sampler2D light_grid : hint_default_black, filter_nearest, repeat_disable;
uniform bool light_grid_smooth = true;
uniform float light_grid_cell = 8.0;
uniform vec4 light_grid_view_0 = vec4(0.0);
uniform vec4 light_grid_view_1 = vec4(0.0);
uniform vec4 light_grid_view_2 = vec4(0.0);
uniform vec4 light_grid_view_3 = vec4(0.0);
uniform vec4 light_grid_size_0 = vec4(0.0);
uniform vec4 light_grid_size_1 = vec4(0.0);
uniform vec4 light_grid_size_2 = vec4(0.0);
uniform vec4 light_grid_size_3 = vec4(0.0);

vec4 grid_view_of(int k) {
	return k == 1 ? light_grid_view_1 : (k == 2 ? light_grid_view_2 : (k == 3 ? light_grid_view_3 : light_grid_view_0));
}

vec4 grid_size_of(int k) {
	return k == 1 ? light_grid_size_1 : (k == 2 ? light_grid_size_2 : (k == 3 ? light_grid_size_3 : light_grid_size_0));
}

// View `k`'s cell (column, row) clamped to its grid, read from the texture.
vec3 grid_cell(int k, ivec2 c) {
	ivec2 size = ivec2(grid_size_of(k).xy);
	c = clamp(c, ivec2(0), max(size - ivec2(1), ivec2(0)));
	return texelFetch(light_grid, c + ivec2(grid_view_of(k).zw), 0).rgb;
}

// The light at world point `world` in view `k` (0 to 3; any other: none).
vec3 grid_light(int k, vec2 world) {
	if (k < 0 || k > 3) {
		return vec3(0.0);
	}
	vec2 size = grid_size_of(k).xy;
	if (size.x < 1.0) {
		return vec3(0.0);
	}
	vec2 at = (world - grid_view_of(k).xy) / light_grid_cell;
	if (at.x < 0.0 || at.y < 0.0 || at.x >= size.x || at.y >= size.y) {
		return vec3(0.0);
	}
	if (!light_grid_smooth) {
		return grid_cell(k, ivec2(floor(at)));
	}
	vec2 from_middle = at - 0.5;
	ivec2 c = ivec2(floor(from_middle));
	vec2 t = from_middle - floor(from_middle);
	vec3 top = mix(grid_cell(k, c), grid_cell(k, c + ivec2(1, 0)), t.x);
	vec3 bottom = mix(grid_cell(k, c + ivec2(0, 1)), grid_cell(k, c + ivec2(1, 1)), t.x);
	return mix(top, bottom, t.y);
}
