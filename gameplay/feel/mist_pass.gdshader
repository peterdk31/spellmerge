// SPDX-License-Identifier: GPL-3.0-or-later
shader_type canvas_item;
render_mode blend_disabled;

// A room's low floor mist at the light's resolution (gameplay/feel/mist.gd, light_passes.gd; the owner's
// decision of 2026-11-21, docs/milestones/connected-biomes.md, "The light at a fixed resolution"): the
// room's mist rect's twin in the mist's pass (a view's, `PictureGrid.scale_of` times smaller than the
// view), writing how thick the mist is (mist_density.gdshaderinc, a share of THICKEST_DRAWN, packed:
// light_pack.gdshaderinc) for the room's rect in the picture to take whole for each block and light
// (mist.gdshader). Written as it is (`blend_disabled`): the pass holds numbers, not a picture.

#include "res://gameplay/feel/mist_density.gdshaderinc"
#include "res://gameplay/feel/light_pack.gdshaderinc"

varying vec2 world;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	COLOR = light_pack_unit(mist_density(world) / THICKEST_DRAWN);
}
