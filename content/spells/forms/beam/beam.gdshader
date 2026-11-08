// SPDX-License-Identifier: GPL-3.0-or-later
shader_type canvas_item;
render_mode blend_premul_alpha, world_vertex_coords;

// A beam card's own look (content/spells/forms/beam/: `FormBase.look_shader`; docs/milestones/card-looks.md;
// the owner, 2026-11-08: "it should glow hot white in the center and then apply the spell colors
// out on each side", "maybe void should have a dark center"). A copy of the plain beam
// (`core/projectiles/shot_beam.gdshaderinc`, which still draws a ray with no beam card: a chain's
// jump, a zap) with its pixels and light drawn its own way: bands across it, a white-hot core
// stepping out through its ramp (light, base, shadow) to a ragged edge on each side. Its flare
// widens the bands and the white with them; it thins to its core as it ends, the edge going
// first. Pulses of light run down it from the staff and push its bands out a pixel as they pass.
// Void turns it inside out: a dark rift down the middle with its ramp glowing at the lips.
// Its vertices, quads and uniforms are the plain beam's (Feel draws each live beam with it on the
// beam's own material); warmed as a mesh before the first room.

#include "res://core/projectiles/shot_palette.gdshaderinc"
#include "res://core/projectiles/shot_look.gdshaderinc"

// The most points a path has (LIVE_BEAM_POINTS in gameplay/feel/feel.gd).
const int BEAM_POINTS = 80;
// The quad kinds (BEAM_Q_* in gameplay/feel/feel.gd), in UV.y.
const float Q_PIECE_LIGHT = 0.0;
const float Q_PIECE = 1.0;
// The fragment's modes: a piece's light, a piece's pixels.
const float M_PIECE_LIGHT = 0.0;
const float M_PIECE = 1.0;
// How many pixels each side of its core the beam's bands reach at rest (its swell 1).
const float BANDS = 4.0;
// How fast its pulses run down it (px/s) and how many are on it at once.
const float PULSE_SPEED = 320.0;
const int PULSES = 4;

uniform vec4 core_override = vec4(1.0);
// Feel's fade of the beam (kept with the beam; the beam's own fade is `beam_fade`).
uniform vec4 body_tint = vec4(1.0);
uniform vec3 beam_path[80];
uniform int beam_points = 0;
uniform float beam_length = 0.0;
uniform float beam_width = 16.0;
uniform int beam_player = 0;
uniform int beam_look = 0;
uniform float beam_fade = 1.0;
uniform float beam_swell = 1.0;
uniform float beam_glow = 1.0;
// Where a beam starts (the staff) and ends in the world: its flares are drawn there, upright on
// the world's pixels.
uniform vec2 beam_start = vec2(-100000.0);
uniform vec2 beam_end = vec2(-100000.0);
// How far the beam's quads reach past each end, so the flares are whole.
uniform float beam_lead = 0.0;

// The pixel in the world.
varying vec2 world;
varying flat float mode;
// A piece: its start (x, y, how far along), its way, the longer axis's share of its way (`cheb`),
// the lines across its ends it keeps between (a point and its normal each).
varying flat vec4 piece;
varying flat vec4 piece_way;
varying flat vec4 cut_lo;
varying flat vec4 cut_hi;
// The whole beam's: how many pixels its bands reach each side now (its swell, kept inside its
// quads), whether it is void's dark rift (1) or a white-hot core (0).
varying flat float bands;
varying flat float rift;

// ---- Vertices ----

// Point `n` of the path (clamped to it).
vec3 path_point(int n) {
	return beam_path[clamp(n, 0, max(beam_points - 1, 0))];
}

// The way piece `n` runs.
vec2 way_of(int n) {
	vec2 ab = path_point(n + 1).xy - path_point(n).xy;
	return length(ab) > 0.001 ? normalize(ab) : vec2(1.0, 0.0);
}

void vertex() {
	vec3 b = vec3(float(beam_look & 255), float((beam_look >> 8) & 255), float((beam_look >> 16) & 255));
	Look L = look_of(core_override.rgb, beam_player < 0 ? ENEMY_PLAYER : float(min(beam_player, 3)), 1.0, b, 0.0, true);
	SET_LOOK(L);
	// The mesh's vertex: its slot and corner in UV.x (slot + 0.25 or 0.75), its quad kind and
	// corner in UV.y (kind + 0.25 or 0.75). Piece `slot`: from its point to the next, a lead past
	// the beam's ends, as wide as the beam each side and a beam's width more at a bend, cut at the
	// bend's middle.
	int slot = int(floor(UV.x));
	float quad = floor(UV.y);
	vec2 corner = vec2(fract(UV.x) > 0.5 ? 1.0 : 0.0, fract(UV.y) > 0.5 ? 1.0 : 0.0);
	bool shown = slot < beam_points - 1;
	vec3 A = path_point(slot);
	vec3 B = path_point(slot + 1);
	vec2 way = way_of(slot);
	vec2 side = vec2(-way.y, way.x);
	float half_width = beam_width * 0.5;
	bool first = slot == 0;
	bool last = slot >= beam_points - 2;
	float back = first ? beam_lead : beam_width;
	float on = last ? beam_lead : beam_width;
	vec2 lo_n = first ? way : normalize(way_of(slot - 1) + way);
	vec2 hi_n = last ? way : normalize(way + way_of(slot + 1));
	vec2 along_corner = mix(A.xy - way * back, B.xy + way * on, corner.x);
	vec2 at = along_corner + side * mix(-half_width, half_width, corner.y);
	// Folded away when there is nothing to draw.
	VERTEX = shown ? at : vec2(-1.0e6);
	world = VERTEX;
	mode = quad == Q_PIECE ? M_PIECE : M_PIECE_LIGHT;
	piece = vec4(A.xy, A.z, 0.0);
	piece_way = vec4(way, max(abs(way.x), abs(way.y)), 0.0);
	cut_lo = vec4(first ? A.xy - way * beam_lead : A.xy, lo_n);
	cut_hi = vec4(last ? B.xy + way * beam_lead : B.xy, hi_n);
	// Two pixels inside its quad's edge: room for a pulse's bulge and a sparkle past it.
	bands = clamp(floor(BANDS * beam_swell + 0.25), 1.0, max(half_width - 3.0, 1.0));
	rift = has_layer(L_PULL) ? 1.0 : 0.0;
}

// ---- Fragments ----
// Small on purpose (core/README.md, "The shot shaders"): a pixel only colours itself from what
// its quad's vertices worked out. Nothing read from the path.

// Where the middle of the beam runs `along` pixels from the staff, pushed across: jagged for
// lightning, swaying for storm, wavering for fire (from the fragment's look).
float off_at(float along, float len) {
	float jf = floor(sim_time * 30.0);
	float off = 0.0;
	if (has_layer(L_SPARKS)) {
		float seg = 6.0;
		float k = floor(along / seg);
		float o0 = k < 0.5 ? 0.0 : (hash(k, jf, 41.0) - 0.5) * 6.0;
		float o1 = (k + 1.0) * seg >= len ? 0.0 : (hash(k + 1.0, jf, 41.0) - 0.5) * 6.0;
		off = mix(o0, o1, fract(along / seg));
	} else if (has_layer(L_GUSTS)) {
		off = sin(along * 0.11 - sim_time * 18.0) * 1.6;
	} else if (has_layer(L_EMBERS)) {
		off = sin(along * 0.55 - sim_time * 36.0) * 0.7;
	}
	return off;
}

// How close `along` is to the nearest pulse running down a beam `len` long (1 on it, 0 from
// `reach` pixels off).
float pulse_at(float along, float len, float reach) {
	float gap = len / float(PULSES);
	float d = mod(along - sim_time * PULSE_SPEED, gap);
	return falloff(min(d, gap - d), reach);
}

// The beam's pixel at `along` pixels from the staff and `across` from its middle, `cheb` the
// longer axis's share of its way on screen (so a band is one pixel per step of that axis, never
// two), `P` the pixel in the world: its colour, or alpha 0.
vec4 beam_pixel(float along, float across, float cheb, vec2 P) {
	float len = max(beam_length, 1.0);
	float at = floor(along);
	float off = off_at(along, len);
	float x = abs(floor((across - off) / max(cheb, 0.5) + 0.5));
	// Its edge here: a ripple that runs down it, and a pixel more where a pulse passes, on its own
	// side each (`x` the pixel's, so the two edges ripple apart).
	float side = across - off < 0.0 ? 1.0 : 0.0;
	float ripple = sin(along * 0.31 + side * 2.1 - sim_time * 23.0) > 0.55 ? 1.0 : 0.0;
	float edge = bands + ripple + floor(pulse_at(along, len, 6.0) * 1.6);
	// Its band, counted in from its edge: 0 its edge (shadow), 1 base, 2 light, 3 white-hot, more the
	// core. A rift counts the other way round: lips bright, the dark at its middle.
	float band = edge - x;
	vec3 shade = band < 0.5 ? lo : (band < 1.5 ? mid : (band < 2.5 ? hi : (band < 3.5 ? hot : BONE_LIGHT)));
	vec3 rift_shade = band < 0.5 ? hi : (band < 1.5 ? mid : (band < 2.5 ? lo : OUTLINE));
	vec3 inner = mix(shade, rift_shade, rift);
	// The core's middle pixel is always white-hot (or void's darkest), however thin the beam.
	inner = x < 0.5 ? mix(BONE_LIGHT, OUTLINE, rift) : inner;
	vec4 colour = vec4(0.0);
	// As it ends it falls apart into pixels, its edge first, its core last.
	bool kept = hash(at, x + side * 17.0 + 7.0, 42.0) < beam_fade * 1.4 - (x / max(edge, 1.0)) * (1.0 - beam_fade);
	if (kept && along >= 0.0 && along <= len) {
		if (x <= edge) {
			colour = vec4(inner, 1.0);
		} else if (x == edge + 1.0 && mod(at * 7.0 + side * 5.0 + floor(sim_time * 30.0) * 13.0, 11.0) < 1.5) {
			// Sparkles a pixel past its edge, re-rolled every other frame.
			colour = vec4(mix(hi, VOID_LIGHT, rift), 1.0);
		}
	}
	// Flares at the staff and where it lands, upright crosses that flicker a pixel: white-hot at
	// the heart (void's dark), its light round it.
	float flick = mod(floor(sim_time * 30.0), 2.0);
	vec2 ds = floor(P) - floor(beam_start);
	vec2 de = floor(P) - floor(beam_end);
	float sr = 1.0 + flick;
	float er = 2.0 + flick + floor(0.5 * bands - 1.0);
	vec3 heart = mix(BONE_LIGHT, OUTLINE, rift);
	vec3 arm = mix(hot, VOID_LIGHT, rift);
	if ((ds.x == 0.0 && abs(ds.y) <= sr) || (ds.y == 0.0 && abs(ds.x) <= sr)) {
		colour = vec4(ds == vec2(0.0) ? heart : arm, 1.0);
	}
	if (beam_fade > 0.3 && ((de.x == 0.0 && abs(de.y) <= er) || (de.y == 0.0 && abs(de.x) <= er))) {
		colour = vec4(abs(de.x) + abs(de.y) < 1.5 ? heart : (abs(de.x) + abs(de.y) < er ? arm : hi), 1.0);
	}
	return colour;
}

// How much of the beam's light reaches `P` (`along` it, `across` from its middle): a soft band as
// wide as its bands and more, the pulses running down it, and both ends.
float beam_light(float along, float across, vec2 P) {
	float len = max(beam_length, 1.0);
	float off = off_at(along, len);
	float a = abs(across - off);
	float lit = 0.5 * falloff(a, 3.0 + 1.5 * bands) + 0.6 * falloff(length(floor(P) - floor(beam_end)), 7.0 + bands) + 0.4 * falloff(length(floor(P) - floor(beam_start)), 5.0);
	lit += 0.45 * pulse_at(along, len, 6.0) * falloff(a, 3.0 + bands);
	return lit;
}

// The light's strength after the beam's fade, glow, flicker and void's dimming.
float light_scale() {
	float k = beam_fade * beam_glow;
	if (has_layer(L_SPARKS)) {
		k *= 0.55 + 0.9 * hash(floor(sim_time * 20.0), 0.0, 21.0);
	}
	if (has_layer(L_PULL)) {
		k *= 0.6;
	}
	return k;
}

void fragment() {
	// A piece: only the pixels on its side of each bend (the cuts), along it from its start.
	vec4 colour = vec4(0.0);
	vec2 P = world;
	vec2 c = floor(P) + 0.5;
	bool inside = dot(c - cut_lo.xy, cut_lo.zw) >= 0.0 && dot(c - cut_hi.xy, cut_hi.zw) < 0.0;
	vec2 d = P - piece.xy;
	float along = piece.z + dot(d, piece_way.xy);
	float across = dot(d, vec2(-piece_way.y, piece_way.x));
	if (inside && mode < M_PIECE_LIGHT + 0.5) {
		colour = vec4(glow * beam_light(along, across, P) * light_scale() * glow_strength, 0.0);
	} else if (inside) {
		colour = beam_pixel(along, across, piece_way.z, P);
	}
	COLOR = colour;
}
