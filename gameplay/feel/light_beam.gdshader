// SPDX-License-Identifier: GPL-3.0-or-later
shader_type canvas_item;
render_mode blend_add, world_vertex_coords;

// A live beam's light (gameplay/feel/spell_light.gd; docs/milestones/spell-spectacle.md, P3b):
// drawn into the light buffer along the very path Feel hands the beam's own shader
// (shot_beam.gdshader's `beam_path`, `beam_points`, `beam_player`, `beam_look`, `core_override`),
// a soft band `beam_reach` wide each side of it, rounded past its two ends, in the beam's glow.
// The mesh is BEAM_POINTS - 1 quads (spell_light.gd's `beam_light_mesh`), quad k on the path's
// piece k: its UV.x the piece + 0.25 or 0.75, UV.y 0.25 or 0.75 (which side). A piece past the
// path's points is folded away.

#include "res://core/projectiles/shot_palette.gdshaderinc"
// A beam's light is its first infusion's, as the beam card's body (it shows the others as strands).
#define LOOK_OWN_INFUSIONS
#include "res://core/projectiles/shot_look.gdshaderinc"

// shot_beam.gdshader's BEAM_POINTS.
const int BEAM_POINTS = 80;

uniform vec3 beam_path[80];
uniform int beam_points = 0;
uniform int beam_player = 0;
uniform int beam_look = 0;
uniform vec4 core_override = vec4(1.0);
// How bright the light is on the beam (times `beam_fade` as it dissolves), and how far it reaches.
uniform float beam_strength = 0.8;
uniform float beam_fade = 1.0;
uniform float beam_reach = 24.0;

// Where the pixel is: along its piece (px from the piece's start) and across (-1 to 1); the
// piece's length, and whether its start and end are the beam's ends (1) or a bend (0).
varying vec2 spot;
varying flat vec3 piece;
varying flat vec3 lamp;

void vertex() {
	int k = int(floor(UV.x));
	float tail = fract(UV.x) > 0.5 ? 1.0 : 0.0;
	float side = fract(UV.y) > 0.5 ? 1.0 : -1.0;
	if (k >= beam_points - 1 || k >= BEAM_POINTS - 1) {
		VERTEX = vec2(0.0);
		lamp = vec3(0.0);
		spot = vec2(0.0);
		piece = vec3(0.0);
	} else {
		vec2 a = beam_path[k].xy;
		vec2 b = beam_path[k + 1].xy;
		float len = length(b - a);
		vec2 way = len > 0.0 ? (b - a) / len : vec2(1.0, 0.0);
		vec2 across = vec2(-way.y, way.x);
		float first = k == 0 ? 1.0 : 0.0;
		float last = k == beam_points - 2 ? 1.0 : 0.0;
		// The beam's ends are rounded past them; a bend is met by the next piece.
		float x = tail > 0.5 ? len + last * beam_reach : -first * beam_reach;
		VERTEX = a + way * x + across * side * beam_reach;
		spot = vec2(x, side);
		piece = vec3(len, first, last);
		vec3 look_bits = vec3(float(beam_look & 255), float((beam_look >> 8) & 255), float((beam_look >> 16) & 255));
		Look L = look_of(core_override.rgb, beam_player < 0 ? ENEMY_PLAYER : float(min(beam_player, 3)), 1.0, look_bits, 0.0, false);
		lamp = L.glow * beam_strength * beam_fade;
	}
}

void fragment() {
	// Past an end of the beam, the light rounds off; along it, only the way across counts.
	float past = 0.0;
	if (spot.x < 0.0 && piece.y > 0.5) {
		past = -spot.x / beam_reach;
	} else if (spot.x > piece.x && piece.z > 0.5) {
		past = (spot.x - piece.x) / beam_reach;
	}
	float f = clamp(1.0 - length(vec2(past, spot.y)), 0.0, 1.0);
	COLOR = vec4(lamp * f * f, 1.0);
}
