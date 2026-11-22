// SPDX-License-Identifier: GPL-3.0-or-later
shader_type canvas_item;

// A room's low floor mist (gameplay/feel/mist.gd; docs/milestones/atmosphere.md, F; RoomMist): one
// rect over the room, under the bodies and over the floor, its cover, its marks and the bodies'
// shadows, and under the spell light's apply rect, so the room's dark darkens it and the light's
// bands light it as they light the floor. Soft and see-through: the owner's one exception to the
// pixel rules (2026-11-18, docs/STYLE.md), worked out a world pixel at a time.
//
// - **Where it lies:** `mask` (MistMask: how far each place is from a wall and from a pit, and how
//   deep in a wall it is) thickens it toward the walls within `edge_reach` and the pits within
//   `pit_reach`, thin over the middle (`middle`), spilling `spill` over a wall's edge.
// - **Its billows:** three layers of value noise in world px, each drifting its own way at Feel's
//   clock (`view_time`), so the sheet slowly turns over as it drifts; `patchy` opens floor between.
// - **Pushed:** the shots' wake drags it along and a blast's wave pushes it out and thins it
//   (stir.gdshaderinc, the world's stirs); `parted` (MistParting) parts it round the bodies' feet and
//   pushes it aside round them.
// - **At the light's resolution:** while the picture is bigger than PictureGrid.SIZE (gameplay/feel/
//   picture_grid.gd) how thick it is (mist_density.gdshaderinc) is worked out in a view's pass
//   (mist_pass.gdshader, gameplay/feel/light_passes.gd) and taken whole for each block of the picture
//   (light_passes.gdshaderinc); at PictureGrid.SIZE, and in a view with no pass, it is worked out here.
// - **Lit:** the spell light's grid under each world pixel (`view_light`, as the apply rect reads it)
//   brings it out and tints it the light's colour, so it glows warm in a candle's pool, in a wizard's
//   hat colour round their staff, and flares as a fireball passes.

#include "res://gameplay/feel/mist_density.gdshaderinc"

#include "res://gameplay/feel/light_views.gdshaderinc"
#include "res://gameplay/feel/light_passes.gdshaderinc"
uniform float in_dark = 0.5;
uniform float lit = 1.0;
// The floor's bright step (SpellLight.BRIGHT_FROM): a light this bright brings the mist out fully.
uniform float bright_from = 0.45;

varying vec2 world;

void vertex() {
	LIGHT_VIEW_FIND;
	world = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	// At the light's resolution its thickness and its light are its block's (light_passes.gdshaderinc).
	bool by_block = light_pass_here();
	float density = by_block ? light_unpack_unit(light_pass_at(SCREEN_UV, SCREEN_PIXEL_SIZE)) * THICKEST_DRAWN : mist_density(world);
	if (density < 0.004) {
		discard;
	}
	vec3 shine = view_light(floor(world) + 0.5);
	float most = max(shine.r, max(shine.g, shine.b));
	float bright = clamp(most / bright_from, 0.0, 1.0) * lit;
	vec3 hue = most > 0.001 ? shine / most : vec3(1.0);
	float shown = clamp(bright, 0.0, 1.0);
	vec3 tint = mix(colour, colour * 0.5 + hue * 0.6, shown * 0.8) * (1.0 + 0.25 * bright);
	COLOR = vec4(min(tint, vec3(1.0)), density * mix(in_dark, 1.0, shown));
}
