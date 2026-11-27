// SPDX-License-Identifier: GPL-3.0-or-later
// The drawing of `shot_beam.gdshader` (read it for what this draws and how its instance or mesh
// is encoded), in an include so a card's own look that starts from it (`CarrierCard.look_shader`;
// docs/milestones/card-looks.md) includes it and keeps every fix to it, until the card replaces
// the include with code of its own. The including file has `shader_type` and `render_mode`.

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
// The pixels over which its light rises from nothing at its start (0: lit from its start): a beam of
// a fan (+2, +3), so the fan joins its trunk as one beam that splits, never a stack of lights.
uniform float beam_from = 0.0;
// A fan drawn as one (+2, +3 on a beam, the owner's decision of 2026-11-27, #972): its trunk and its
// beams, `fan_count` segments (start x, y, end x, y), the trunk first; `fan_base` how far along the
// trunk's end is. Every pixel takes the nearest of them, so the fan is one merged shape: one edge
// round it, no inner edges where its beams meet, one light. 0: the beam alone, along its path.
const int FAN_MOST = 48;
uniform int fan_count = 0;
uniform vec4 fan_segs[48];
uniform float fan_base = 0.0;

// The pixel in the world.
varying vec2 world;
varying flat float mode;
// A piece: its start (x, y, how far along), its way, the longer axis's share of its way (`cheb`),
// the lines across its ends it keeps between (a point and its normal each).
varying flat vec4 piece;
varying flat vec4 piece_way;
varying flat vec4 cut_lo;
varying flat vec4 cut_hi;

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
	vec3 b = look_channels(beam_look);
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
	// A fan: one quad over all its segments (its first slot's), each pixel finding its own.
	if (fan_count > 0) {
		vec2 box_lo = vec2(1.0e9);
		vec2 box_hi = vec2(-1.0e9);
		for (int i = 0; i < FAN_MOST; i++) {
			if (i < fan_count) {
				box_lo = min(box_lo, min(fan_segs[i].xy, fan_segs[i].zw));
				box_hi = max(box_hi, max(fan_segs[i].xy, fan_segs[i].zw));
			}
		}
		vec2 pad = vec2(beam_width + beam_lead);
		box_lo -= pad;
		box_hi += pad;
		VERTEX = slot == 0 ? vec2(mix(box_lo.x, box_hi.x, corner.x), mix(box_lo.y, box_hi.y, corner.y)) : vec2(-1.0e6);
		world = VERTEX;
		cut_lo = vec4(-1.0e6, 0.0, 1.0, 0.0);
		cut_hi = vec4(1.0e6, 0.0, 1.0, 0.0);
	}
}

// ---- Fragments ----

// The fan's segment nearest `P` (the trunk on a tie): how far along the beam `P` is on it, how far
// across, its way's longer axis share, its whole length to its end and its end (the trunk's none).
void fan_nearest(vec2 P, out float along, out float across, out float cheb, out float len, out vec2 end) {
	float best = 1.0e9;
	int k = 0;
	for (int i = 0; i < FAN_MOST; i++) {
		if (i < fan_count) {
			vec2 ab = fan_segs[i].zw - fan_segs[i].xy;
			float t = clamp(dot(P - fan_segs[i].xy, ab) / max(dot(ab, ab), 1.0e-6), 0.0, 1.0);
			float d = length(P - (fan_segs[i].xy + ab * t));
			if (d < best) {
				best = d;
				k = i;
			}
		}
	}
	vec4 s = fan_segs[0];
	for (int i = 1; i < FAN_MOST; i++) {
		if (i == k) {
			s = fan_segs[i];
		}
	}
	float base = k == 0 ? 0.0 : fan_base;
	vec2 ab = s.zw - s.xy;
	float l = max(length(ab), 0.001);
	vec2 way = ab / l;
	vec2 d = P - s.xy;
	along = base + dot(d, way);
	across = dot(d, vec2(-way.y, way.x));
	cheb = max(abs(way.x), abs(way.y));
	len = base + l;
	end = k == 0 ? vec2(-100000.0) : s.zw;
}
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

// The beam's pixel at `along` pixels from the staff and `across` from its middle, `cheb` the
// longer axis's share of its way on screen (so a line is one pixel per step of that axis, as the
// mockup draws it, never two), `P` the pixel in the world, `length_at` how long the beam is there and
// `end_at` where it lands (a fan's beam's own): its colour, or alpha 0.
vec4 beam_pixel(float along, float across, float cheb, vec2 P, float length_at, vec2 end_at) {
	float len = max(length_at, 1.0);
	float at = floor(along);
	float off = off_at(along, len);
	// The lane across, in art pixels (ART_DETAIL a world pixel; ART2): a line an art pixel thin.
	float x = floor((across - off) * ART_DETAIL / max(cheb, 0.5) + 0.5);
	vec4 colour = vec4(0.0);
	// As it ends it falls apart into pixels.
	bool kept = hash(at, x + 7.0, 42.0) < beam_fade * 1.4;
	float rim = (1.0 + floor(0.5 * beam_swell + 0.25)) * ART_DETAIL;
	if (kept && along >= 0.0 && along <= len) {
		if (x == 0.0) {
			colour = vec4(has_layer(L_PULL) ? OUTLINE : hot, 1.0);
		} else if (abs(x) <= rim && sin(along * 0.23 - sim_time * 27.0) > -0.25) {
			// The rim breathes along it.
			colour = vec4(hi, 1.0);
		} else if (abs(x) == rim + 1.0 && x * (mod(at, 2.0) - 0.5) > 0.0 && mod(at * 7.0 + floor(sim_time * 30.0) * 13.0, 11.0) < 2.0) {
			// Sparkles a pixel out, re-rolled every other frame.
			colour = vec4(mid, 1.0);
		}
	}
	// Flares at the staff and where it lands, upright crosses that flicker a pixel.
	float flick = mod(floor(sim_time * 30.0), 2.0);
	vec2 ds = floor(P) - floor(beam_start);
	vec2 de = floor(P) - floor(end_at);
	float sr = 1.0 + flick;
	float er = 2.0 + flick;
	vec3 flare = has_layer(L_PULL) ? VOID_LIGHT : hot;
	if ((ds.x == 0.0 && abs(ds.y) <= sr) || (ds.y == 0.0 && abs(ds.x) <= sr)) {
		colour = vec4(ds == vec2(0.0) ? flare : hi, 1.0);
	}
	if (beam_fade > 0.3 && ((de.x == 0.0 && abs(de.y) <= er) || (de.y == 0.0 && abs(de.x) <= er))) {
		colour = vec4(de == vec2(0.0) ? flare : hi, 1.0);
	}
	return colour;
}

// How much of the beam's light reaches `P` (`along` it, `across` from its middle, `length_at` and
// `end_at` as `beam_pixel`'s): round its middle, at both ends, and the motes of light running down it
// from the staff.
float beam_light(float along, float across, vec2 P, float length_at, vec2 end_at) {
	float len = max(length_at, 1.0);
	float off = off_at(along, len);
	float lit = 0.45 * falloff(abs(across - off), 3.0 + 3.0 * beam_swell) + 0.6 * falloff(length(floor(P) - floor(end_at)), 7.0) + 0.4 * falloff(length(floor(P) - floor(beam_start)), 5.0);
	for (int n = 0; n < 4; n++) {
		float pos = mod(sim_time * 320.0 + float(n) * len / 4.0, len);
		lit += 0.35 * falloff(abs(along - pos), 5.0) * falloff(abs(across - off), 4.0);
	}
	return beam_from > 0.0 ? lit * smoothstep(0.0, beam_from, along) : lit;
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
	vec2 c = art_centre(P);
	bool inside = dot(c - cut_lo.xy, cut_lo.zw) >= 0.0 && dot(c - cut_hi.xy, cut_hi.zw) < 0.0;
	vec2 d = P - piece.xy;
	float along = piece.z + dot(d, piece_way.xy);
	float across = dot(d, vec2(-piece_way.y, piece_way.x));
	float cheb = piece_way.z;
	float len = beam_length;
	vec2 end_at = beam_end;
	if (fan_count > 0) {
		// A fan: the nearest of its segments draws the pixel, as one merged beam.
		fan_nearest(P, along, across, cheb, len, end_at);
	}
	if (inside && mode < M_PIECE_LIGHT + 0.5) {
		colour = vec4(glow * beam_light(along, across, P, len, end_at) * light_scale() * glow_strength, 0.0);
	} else if (inside) {
		colour = beam_pixel(along, across, cheb, P, len, end_at);
	}
	COLOR = colour;
}
