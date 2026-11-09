// SPDX-License-Identifier: GPL-3.0-or-later
shader_type canvas_item;
render_mode blend_premul_alpha;

// A wall's piece, rising sparks (content/spells/forms/wall/; the owner's pick, 2026-11-09): a seam of
// light opens along the floor under the wall, a white-hot glint running along it, and a glow over it.
// It fades over its last second, the seam cooling. Its card particles are given off from the seam.
// The stream of motes rising off the seam, thick enough to read as a wall, is real motes (the owner:
// "use motes instead of custom sparks"): the card's `look_motes` (`rising`), given off by Feel along
// each piece of the row from where its shots are drawn (gameplay/feel/still_motes.gd), thinning as it
// fades, in its infusions in turn and their own kinds; a hit's burst is the hitting shot's impact.
// Every infusion shows (its palette, `palette_turn`): the seam is banded, a run of world pixels an
// infusion in turn.
// A wall is one solid shot drawn as a row of pieces (`ProjectileManager._write_stones`), each quad
// turned along the row (`Solid.across`, its +x): each piece draws its own span of the seam and its
// sparks, so the pieces join into one wall whichever way it runs, and the glint runs along the seam
// in world pixels, the same in every piece. It is drawn upright on the screen. It knows its time since
// it was placed and its life left from its still clock (`still_since`, `still_left`: the code beside
// its kind, `ProjectileManager.still_code`). Its quad is GRID x zoom pixels square round its centre.
// Blending is premultiplied: its pixels are opaque, the glow added light. Drawn by its card's pair of
// batches (`FormBase.look_shader`, `ProjectileManager.register_body`), warmed before the first room.

#include "res://core/projectiles/shot_palette.gdshaderinc"
#include "res://core/projectiles/shot_look.gdshaderinc"
#include "res://core/projectiles/shot_particle.gdshaderinc"

// The spark pool's share (set by the projectile manager, 1.0 is everything): the fraction of
// every shot's particles drawn this frame.
uniform float particle_share = 1.0;

const float GRID = 24.0;
// Seconds the seam takes to open, and the seconds of its end it fades over.
const float OPEN = 0.3;
const float FADE = 0.8;
// World pixels a band of the seam is long (one infusion's).
const float BAND = 4.0;

// Worked out once a piece (vertex): how far its seam is open, how far it has faded and where it is
// along its row in world pixels; the way the row runs on the screen; its palette (`palette_floats`).
varying flat vec4 piece;
varying flat vec2 axis;
varying flat vec4 pal;

void vertex() {
	float code = coded_code(INSTANCE_CUSTOM.a);
	float since = still_since(code);
	float fade = clamp((1.0 - still_left(code) / STILL_END) / FADE, 0.0, 1.0);
	vec2 at = MODEL_MATRIX[3].xy;
	// Its seed from where it stands, so its motes keep their ways when other shots come and go.
	Look L = look_from_color(COLOR, INSTANCE_CUSTOM.rgb, fract(dot(floor(at), vec2(0.1031, 0.1137))) * 97.0, true);
	SET_LOOK(L);
	float k = 1.0 - clamp(since / OPEN, 0.0, 1.0);
	axis = length(MODEL_MATRIX[0].xy) > 0.0001 ? normalize(MODEL_MATRIX[0].xy) : vec2(1.0, 0.0);
	piece = vec4(1.0 - k * k, fade, 0.0, dot(at, axis));
	pal = palette_floats(L.core, L.bits);
}

vec4 body_look(vec2 uv) {
	// The screen pixel, whole numbers, the piece's centre at 0, upright however the quad turns.
	vec2 size = vec2(GRID) * zoom;
	vec2 local = uv * size - size * 0.5;
	vec2 p = floor(vec2(axis.x * local.x - axis.y * local.y, axis.y * local.x + axis.x * local.y));
	float reach = size.x * 0.15;
	// Its span of the seam (its half, a pixel more than half the step to the next piece so they
	// meet), through its foot, open from its middle; how high its stream's glow reaches.
	float span = reach * 1.25;
	float open = (span + 0.5) * piece.x;
	vec2 foot = vec2(0.0, floor(reach * 0.6 + 0.5));
	float high = reach * 2.8;
	vec2 across = vec2(-axis.y, axis.x);
	vec4 colour = vec4(0.0);
	// What the cards give off: particles born at random points of the seam.
	if (emit_count() > 0.5) {
		// The same rule as `particles_of` in projectile_manager.gd; keep the two equal.
		float asked = min(4.0 + 2.0 * emit_count(), float(MAX_PARTICLES));
		// Each shot rounds its share by its own seed, so the pool's total stays near the share.
		int count = int(floor(asked * particle_share + fract(seed)));
		for (int n = 0; n < MAX_PARTICLES; n++) {
			if (n >= count) {
				break;
			}
			float i = float(n);
			float t = sim_time * (2.5 + 1.5 * hash(i, 0.0, 3.0)) + hash(i, 0.0, 4.0);
			float cyc = floor(t);
			float look = emitter(int(min(floor(hash(i, cyc, 7.0) * emit_count()), emit_count() - 1.0)));
			vec2 from = foot + axis * (hash(i, cyc, 8.0) * 2.0 - 1.0) * span;
			vec4 q = particle(look, from, fract(t), i, cyc, p, zoom);
			if (q.a > 0.0) {
				colour = q;
			}
		}
	}
	// The seam: a one-pixel line along the row through its foot, a white-hot glint every fifth
	// world pixel running along it, cooling as it fades; and a dotted dark line under it.
	vec2 d = p - foot;
	float along = dot(d, axis);
	float off = dot(d, across);
	float thin = 0.5 * max(abs(across.x), abs(across.y));
	float world = floor(piece.w + along);
	if (abs(along) <= open && abs(off) < thin) {
		int band = int(floor(world / BAND));
		colour = vec4(mod(world + floor(sim_time * 12.0), 5.0) < 0.5 ? hot : (piece.y > 0.5 ? palette_turn(pal, band, 0, lo) : palette_turn(pal, band, 2, hi)), 1.0);
	} else if (piece.x > 0.5 && abs(axis.y) < 0.7 && abs(dot(d - vec2(0.0, 1.0), axis)) <= open
			&& abs(dot(d - vec2(0.0, 1.0), across)) < thin && mod(world, 2.0) < 0.5) {
		colour = vec4(palette_turn(pal, int(floor(world / BAND)), 0, lo), 1.0);
	}
	if (colour.a > 0.0) {
		return colour;
	}
	// Its glow: light up through its stream and along its seam, gone as it fades.
	float lit = (0.3 * falloff(length(p - foot + vec2(0.0, high * 0.45)), high * 0.9) + 0.3 * falloff(abs(off), 3.0) * step(abs(along), open))
			* piece.x * (1.0 - piece.y);
	if (has_layer(L_SPARKS)) {
		// Lightning flickers.
		lit *= 0.55 + 0.9 * hash(floor(sim_time * 20.0), 0.0, 21.0);
	}
	return vec4(glow * lit * glow_strength, 0.0);
}

void fragment() {
	COLOR = body_look(UV);
}
