// SPDX-License-Identifier: GPL-3.0-or-later
shader_type canvas_item;
// world_vertex_coords: VERTEX is in world space in vertex(), so each shadow is placed in the world.
render_mode world_vertex_coords;

#include "res://core/display/art_detail.gdshaderinc"

// A body's shadow (gameplay/feel/body_shadows.gd; docs/milestones/atmosphere.md, C): one row a
// body, a quad round its shadow (MODEL_MATRIX: its size and middle), its colour the shadow's,
// INSTANCE_CUSTOM.xy how far the shadow is cast (whole px, away from the light) and .z its radius
// (px). The shadow is the flat disc a body stands on (`flatness` times as deep as wide), swept along
// the cast: a hard shape in whole art pixels (each in or out by its middle; ART3), never soft.
// The row's middle is the feet (whole px) plus half the cast.

// How flat the disc lies (body_shadows.gd's FLAT).
uniform float flatness = 0.4;

varying vec2 world;
varying flat vec2 feet;
varying flat vec3 cast;

void vertex() {
	cast = INSTANCE_CUSTOM.xyz;
	feet = MODEL_MATRIX[3].xy - INSTANCE_CUSTOM.xy * 0.5;
	world = VERTEX;
}

void fragment() {
	// The pixel's middle from the feet, in the floor's measure (its depth stretched back out).
	vec2 squash = vec2(1.0, 1.0 / flatness);
	vec2 q = (art_centre(world) - feet) * squash;
	vec2 c = cast.xy * squash;
	float along = dot(c, c) > 0.0 ? clamp(dot(q, c) / dot(c, c), 0.0, 1.0) : 0.0;
	if (length(q - c * along) > cast.z) {
		discard;
	}
}
