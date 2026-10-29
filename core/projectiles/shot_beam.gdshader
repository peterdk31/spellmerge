// SPDX-License-Identifier: GPL-3.0-or-later
shader_type canvas_item;
// world_vertex_coords: VERTEX is in world space in vertex(), so each quad is placed in the world
// and the flares stand upright on the world's pixels (nothing else moves its vertices).
render_mode blend_premul_alpha, world_vertex_coords;

// A beam (Feel's beams; core/README.md, "The shot shaders"): a white-hot one-pixel core, a rim
// that breathes along it, motes running down it, flares at both ends, a splash where it lands
// and its card particles. Blending is premultiplied: its pixels are opaque, its glow added light.
// Its path is `beam_path` (`beam_points` points: x, y and how far along the beam each is), cut
// where it got (`beam_length` pixels); a short beam is a path of two points. Its core colour is
// `core_override`, its player and look these (`beam_player` -1, NO_PLAYER, is an enemy's beam).
// `beam_fade` (1 to 0) dissolves it into pixels as it ends; `beam_swell` (1 at rest) widens its
// rim and glow when it flares and narrows them as it thins; `beam_glow` is how strongly it glows.
//
// PARTICLES ARE GEOMETRY (as in `shot_trail.gdshader`; the owner, 2026-10-29): a beam is a mesh of
// small quads (`Feel.beam_mesh`), each told in its UV which QUAD KIND (Q_*) and slot it is. The
// vertex stage works out what that slot is now and puts its quad round it alone, or folds it
// away; the fragment stage only colours a pixel of its own quad, with no loops over particles:
//   Q_PIECE_LIGHT  the glow round piece `slot` of the path (and its motes, and the ends' light)
//   Q_SPLASH_LIGHT the light of splash spark `slot` where it lands
//   Q_PARTICLE     one of its card particles, in the beam's own pixels, the newest on top
//   Q_SPLASH       splash spark `slot`, upright on the world's pixels; the first on top
//   Q_PIECE        the beam's pixels along piece `slot` (core, rim, sparkles) and the flares
// A piece's quads reach a beam's width each side of it and BEAM_LEAD past the beam's ends, and
// a pixel belongs to the piece whose side of the bend it is on, so a bent beam is one line.

#include "res://core/projectiles/shot_palette.gdshaderinc"
#include "res://core/projectiles/shot_look.gdshaderinc"
#include "res://core/projectiles/shot_particle.gdshaderinc"

// The most points a path has (LIVE_BEAM_POINTS in gameplay/feel/feel.gd).
const int BEAM_POINTS = 80;
// The steps of a search along them (2^7 = 128).
const int SEARCH_STEPS = 7;
// The quad kinds (BEAM_Q_* in gameplay/feel/feel.gd), in UV.y.
const float Q_PIECE_LIGHT = 0.0;
const float Q_SPLASH_LIGHT = 1.0;
const float Q_PARTICLE = 2.0;
const float Q_SPLASH = 3.0;
const float Q_PIECE = 4.0;
// The fragment's modes: a piece's light, a piece's pixels, a splash spark's light, a pixel of a
// splash spark or a particle.
const float M_PIECE_LIGHT = 0.0;
const float M_PIECE = 1.0;
const float M_SPLASH_LIGHT = 2.0;
const float M_PIXELS = 3.0;

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
// Where a beam starts (the staff) and ends in the world, and its way at the end: its flares and
// the splash where it lands are drawn there, upright on the world's pixels.
uniform vec2 beam_start = vec2(-100000.0);
uniform vec2 beam_end = vec2(-100000.0);
uniform vec2 beam_end_dir = vec2(1.0, 0.0);
// How far the beam's quads reach past each end, so the flares are whole.
uniform float beam_lead = 0.0;

// The pixel in the world; where it is in its spark's or particle's pixels (the world's for a
// splash spark, the beam's own for a particle: along it from the staff, across from its middle).
varying vec2 world;
varying vec2 local;
varying flat float mode;
// A piece: its start (x, y, how far along), its way, the longer axis's share of its way (`cheb`),
// the lines across its ends it keeps between (a point and its normal each).
varying flat vec4 piece;
varying flat vec4 piece_way;
varying flat vec4 cut_lo;
varying flat vec4 cut_hi;
// A particle's or splash spark's pixel and shape (see `particle_pixel`), its colours.
varying flat vec4 v0;
varying flat vec4 v1;
varying flat vec4 c0;
varying flat vec4 c1;

// ---- Vertices ----

// Point `n` of the path (clamped to it).
vec3 path_point(int n) {
	return beam_path[clamp(n, 0, max(beam_points - 1, 0))];
}

// The piece `along` pixels from the staff is on: the index of its first point.
int piece_at(float along) {
	int low_k = 0;
	int high_k = max(beam_points - 2, 0);
	for (int i = 0; i < SEARCH_STEPS; i++) {
		int half_k = (low_k + high_k + 1) / 2;
		if (path_point(half_k).z <= along) {
			low_k = half_k;
		} else {
			high_k = half_k - 1;
		}
	}
	return min(low_k, high_k);
}

// The way piece `n` runs.
vec2 way_of(int n) {
	vec2 ab = path_point(n + 1).xy - path_point(n).xy;
	return length(ab) > 0.001 ? normalize(ab) : vec2(1.0, 0.0);
}

// Where the middle of the beam runs `along` pixels from the staff, pushed `off` across: jagged
// for lightning, swaying for storm, wavering for fire.
float middle_off(float along, float len, Look L) {
	float jf = floor(sim_time * 30.0);
	float off = 0.0;
	if (bit_set(L.bits, L_SPARKS)) {
		float seg = 6.0;
		float k = floor(along / seg);
		float o0 = k < 0.5 ? 0.0 : (hash_seeded(k, jf, 41.0, L.seed) - 0.5) * 6.0;
		float o1 = (k + 1.0) * seg >= len ? 0.0 : (hash_seeded(k + 1.0, jf, 41.0, L.seed) - 0.5) * 6.0;
		off = mix(o0, o1, fract(along / seg));
	} else if (bit_set(L.bits, L_GUSTS)) {
		off = sin(along * 0.11 - sim_time * 18.0) * 1.6;
	} else if (bit_set(L.bits, L_EMBERS)) {
		off = sin(along * 0.55 - sim_time * 36.0) * 0.7;
	}
	return off;
}

void vertex() {
	vec3 b = vec3(float(beam_look & 255), float((beam_look >> 8) & 255), float((beam_look >> 16) & 255));
	Look L = look_of(core_override.rgb, beam_player < 0 ? ENEMY_PLAYER : float(min(beam_player, 3)), 1.0, b, 0.0, true);
	SET_LOOK(L);
	float len = max(beam_length, 1.0);
	// The mesh's vertex: its slot and corner in UV.x (slot + 0.25 or 0.75), its quad kind and
	// corner in UV.y (kind + 0.25 or 0.75).
	int slot = int(floor(UV.x));
	float quad = floor(UV.y);
	vec2 corner = vec2(fract(UV.x) > 0.5 ? 1.0 : 0.0, fract(UV.y) > 0.5 ? 1.0 : 0.0);
	bool shown = false;
	vec2 at = vec2(0.0);
	float m = M_PIXELS;
	vec4 p0 = vec4(0.0);
	vec4 p1 = vec4(0.0);
	vec4 lo_cut = vec4(0.0);
	vec4 hi_cut = vec4(0.0);
	vec4 a0 = vec4(0.0);
	vec4 a1 = vec4(0.0);
	vec4 k0 = vec4(0.0);
	vec4 k1 = vec4(0.0);
	vec2 here = vec2(0.0);
	if (quad == Q_PIECE_LIGHT || quad == Q_PIECE) {
		// Piece `slot`: from its point to the next, a lead past the beam's ends, as wide as the
		// beam each side and a beam's width more at a bend, cut at the bend's middle.
		shown = slot < beam_points - 1;
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
		at = along_corner + side * mix(-half_width, half_width, corner.y);
		m = quad == Q_PIECE ? M_PIECE : M_PIECE_LIGHT;
		p0 = vec4(A.xy, A.z, 0.0);
		p1 = vec4(way, max(abs(way.x), abs(way.y)), 0.0);
		lo_cut = vec4(first ? A.xy - way * beam_lead : A.xy, lo_n);
		hi_cut = vec4(last ? B.xy + way * beam_lead : B.xy, hi_n);
	} else if (quad == Q_SPLASH_LIGHT || quad == Q_SPLASH) {
		// A splash where it lands: sparks thrown back off the end, cooling.
		float i = float(slot);
		float life = 0.1 + 0.12 * hash_seeded(i, 0.0, 49.0, L.seed);
		float t = sim_time / life + hash_seeded(i, 1.0, 49.0, L.seed);
		float cyc = floor(t);
		float a = fract(t);
		vec2 back = -normalize(beam_end_dir + vec2(0.0001, 0.0));
		float ang = atan(back.y, back.x) + (hash_seeded(i, cyc, 50.0, L.seed) - 0.5) * 2.4;
		vec2 pos = floor(beam_end + vec2(cos(ang), sin(ang)) * (40.0 + 60.0 * hash_seeded(i, cyc, 51.0, L.seed)) * (0.9 * (1.0 - pow(0.9, a * life * 60.0)) / 0.1 / 60.0));
		if (quad == Q_SPLASH_LIGHT) {
			shown = beam_points > 1;
			m = M_SPLASH_LIGHT;
			at = mix(pos - 7.0, pos + 8.0, corner);
			a0 = vec4(pos, 0.9 * (1.0 - 0.75 * a) * beam_fade, 0.0);
		} else {
			shown = beam_points > 1 && beam_fade > 0.3;
			at = mix(pos, pos + 1.0, corner);
			here = at;
			a0 = vec4(pos, 0.0, 0.0);
			k0 = vec4(a < 0.15 ? L.hot : (a < 0.4 ? L.hi : (a < 0.7 ? L.mid : L.lo)), 1.0);
		}
	} else if (quad == Q_PARTICLE) {
		// Its cards, given off along it, in the beam's own pixels.
		float n = L.emits.w;
		float count = min(4.0 + 2.0 * n, float(MAX_PARTICLES));
		float i = float(slot);
		float t = sim_time * (2.5 + 1.5 * hash_seeded(i, 0.0, 45.0, L.seed)) + hash_seeded(i, 0.0, 46.0, L.seed);
		float cyc = floor(t);
		float pick = min(floor(hash_seeded(i, cyc, 47.0, L.seed) * n), n - 1.0);
		float word = pick < 4.0 ? L.emits.x : (pick < 8.0 ? L.emits.y : L.emits.z);
		float look = mod(floor(word / exp2(mod(pick, 4.0) * 4.0) + 0.001), 16.0);
		float along = len * hash_seeded(i, cyc, 48.0, L.seed);
		Particle p = place_particle(look, vec2(along, middle_off(along, len, L)), fract(t), i, cyc, 1.0, L.seed);
		vec2 cell = floor(p.at);
		shown = n > 0.5 && i < count && p.shown && beam_points > 1;
		// Its quad in the beam's pixels, laid along the piece it is on.
		vec2 q = mix(cell - 1.0, cell + vec2(p.run + 2.0, 2.0), corner);
		int k = piece_at(cell.x);
		vec3 A = path_point(k);
		vec2 way = way_of(k);
		at = A.xy + way * (q.x - A.z) + vec2(-way.y, way.x) * q.y;
		here = q;
		a0 = vec4(cell, p.run, p.arm);
		a1 = vec4(p.extra, 0.0, 0.0);
		k0 = vec4(p.rgb, 1.0);
		k1 = vec4(p.arm_rgb, 1.0);
	}
	// Folded away when there is nothing to draw.
	VERTEX = shown ? at : vec2(-1.0e6);
	world = VERTEX;
	local = here;
	mode = m;
	piece = p0;
	piece_way = p1;
	cut_lo = lo_cut;
	cut_hi = hi_cut;
	v0 = a0;
	v1 = a1;
	c0 = k0;
	c1 = k1;
}

// ---- Fragments ----
// Small on purpose (core/README.md, "The shot shaders"): a pixel only colours itself from what
// its quad's vertices worked out. No loops over particles, nothing read from the path.

// Where the middle of the beam runs `along` pixels from the staff (`middle_off`, from the
// fragment's look).
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
// mockup draws it, never two), `P` the pixel in the world: its colour, or alpha 0.
vec4 beam_pixel(float along, float across, float cheb, vec2 P) {
	float len = max(beam_length, 1.0);
	float at = floor(along);
	float off = off_at(along, len);
	float x = floor((across - off) / max(cheb, 0.5) + 0.5);
	vec4 colour = vec4(0.0);
	// As it ends it falls apart into pixels.
	bool kept = hash(at, x + 7.0, 42.0) < beam_fade * 1.4;
	float rim = 1.0 + floor(0.5 * beam_swell + 0.25);
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
	vec2 de = floor(P) - floor(beam_end);
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

// How much of the beam's light reaches `P` (`along` it, `across` from its middle): round its
// middle, at both ends, and the motes of light running down it from the staff.
float beam_light(float along, float across, vec2 P) {
	float len = max(beam_length, 1.0);
	float off = off_at(along, len);
	float lit = 0.45 * falloff(abs(across - off), 3.0 + 3.0 * beam_swell) + 0.6 * falloff(length(floor(P) - floor(beam_end)), 7.0) + 0.4 * falloff(length(floor(P) - floor(beam_start)), 5.0);
	for (int n = 0; n < 4; n++) {
		float pos = mod(sim_time * 320.0 + float(n) * len / 4.0, len);
		lit += 0.35 * falloff(abs(along - pos), 5.0) * falloff(abs(across - off), 4.0);
	}
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
	vec4 colour = vec4(0.0);
	if (mode < M_PIECE + 0.5) {
		// A piece: only the pixels on its side of each bend (the cuts), along it from its start.
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
	} else if (mode < M_SPLASH_LIGHT + 0.5) {
		// A splash spark's light round its pixel v0.xy, v0.z bright.
		float r = length(floor(world) - v0.xy);
		float lit = v0.z * (0.16 * falloff(r, 2.5) + 0.07 * falloff(r, 7.0));
		colour = vec4(glow * lit * light_scale() * glow_strength, 0.0);
	} else {
		// A splash spark (on the world's pixels) or a particle (in the beam's).
		Particle p;
		p.shown = true;
		p.at = v0.xy;
		p.run = v0.z;
		p.arm = v0.w;
		p.extra = v1.xy;
		p.rgb = c0.rgb;
		p.arm_rgb = c1.rgb;
		colour = particle_pixel(p, local);
	}
	COLOR = colour;
}
