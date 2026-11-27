// SPDX-License-Identifier: GPL-3.0-or-later
// A room's low floor mist, how thick it is at an art pixel (gameplay/feel/mist.gd; mist.gdshader, where it
// is drawn, a pixel at a time). See
// mist.gdshader for where it lies, its billows and what pushes it.

#include "res://core/display/art_detail.gdshaderinc"
#include "res://gameplay/feel/stir.gdshaderinc"

uniform sampler2D mask : hint_default_black, filter_linear, repeat_disable;
uniform vec2 mask_size = vec2(1.0);
// Where the room's mask and parting begin (world px): the room's place (connected biomes, a room laid
// away from the world's origin; its mask is of its walls as mirrored where it stands).
uniform vec2 origin = vec2(0.0);
uniform sampler2D parted : hint_default_black, filter_linear, repeat_disable;
uniform vec2 parted_size = vec2(1.0);
uniform float view_time = 0.0;
uniform vec3 colour = vec3(0.72, 0.78, 0.92);
uniform float thickness = 0.3;
uniform float middle = 0.25;
// Shares of MistMask.REACH (edge_reach, pit_reach) and SPILL (spill).
uniform float edge_reach = 0.5;
uniform float pit_reach = 0.5;
uniform float pit_share = 1.0;
uniform float spill = 0.2;
uniform float patchy = 0.6;
uniform float scale = 96.0;
uniform vec2 drift = vec2(4.0, 1.0);
// How many layers of billows are worked out (1 to 3; EffectsQuality.mist_billows): fewer is cheaper, the
// first layer standing for the rest.
uniform int billows = 3;
// Mist.THICKEST_DRAWN, STIR_SHOT_PIXELS, STIR_BLAST_PIXELS, STIR_THIN, PART_PIXELS, PART_THIN.
const float THICKEST_DRAWN = 0.6;
const float STIR_SHOT_PIXELS = 10.0;
const float STIR_BLAST_PIXELS = 26.0;
const float STIR_THIN = 0.9;
const float PART_PIXELS = 6.0;
const float PART_THIN = 0.92;

// A hash of a lattice point, 0 to 1 (no sine: the same on every GPU near enough, and cheap).
float mist_hash(vec2 c) {
	vec3 p3 = fract(vec3(c.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

// Smooth value noise, 0 to 1.
float mist_noise(vec2 q) {
	vec2 i = floor(q);
	vec2 f = fract(q);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = mist_hash(i);
	float b = mist_hash(i + vec2(1.0, 0.0));
	float c = mist_hash(i + vec2(0.0, 1.0));
	float d = mist_hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// How far the mist is parted at `p` (world px).
float mist_parted(vec2 p) {
	return textureLod(parted, (p - origin) / parted_size, 0.0).r;
}

// How thick the mist is at world point `world` (0: none drawn), an art pixel at a time (ART3: its
// edge against the walls, the pits and the void steps by the finer pixel).
float mist_density(vec2 world) {
	vec2 p = art_centre(world);
	// Where it lies first: past a wall's spill, or where even its thickest billow would not show, the
	// rest is not worked out.
	vec4 m = textureLod(mask, (p - origin) / mask_size, 0.0);
	float edge = 1.0 - smoothstep(0.0, max(edge_reach, 0.001), m.r);
	float pit = (1.0 - smoothstep(0.0, max(pit_reach, 0.001), m.g)) * pit_share;
	float over_wall = 1.0 - smoothstep(0.0, max(spill, 0.001), m.b);
	float density = thickness * mix(middle, 1.0, max(edge, pit)) * over_wall;
	if (density * mix(1.0, 1.6, patchy) < 0.004) {
		return 0.0;
	}
	vec2 wake = stir_wake(p);
	vec2 push = stir_blasts_at(p, view_time);
	float part = mist_parted(p);
	vec2 part_way = vec2(0.0);
	if (part > 0.001) {
		part_way = vec2(mist_parted(p + vec2(4.0, 0.0)) - mist_parted(p - vec2(4.0, 0.0)), mist_parted(p + vec2(0.0, 4.0)) - mist_parted(p - vec2(0.0, 4.0)));
	}
	// What is drawn here was pushed here: the wake drags it along, a blast pushes it out, a body
	// pushes it aside.
	vec2 q = p - wake * STIR_SHOT_PIXELS - push * STIR_BLAST_PIXELS + part_way * PART_PIXELS;
	vec2 moved = drift * view_time;
	float n = mist_noise((q - moved) / scale);
	if (billows > 1) {
		n = 0.55 * n + 0.3 * mist_noise(mat2(vec2(0.8, -0.6), vec2(0.6, 0.8)) * (q - moved * 1.6) / scale * 2.03 + vec2(17.3, 3.1));
		n += billows > 2 ? 0.15 * mist_noise((q + moved * 0.7) / scale * 4.1 + vec2(-5.2, 11.7)) : 0.15 * n / 0.85;
	}
	density *= mix(1.0, smoothstep(0.25, 0.75, n) * 1.6, patchy);
	density *= (1.0 - PART_THIN * smoothstep(0.0, 1.0, part)) * (1.0 - clamp((length(push) + length(wake) * 0.5) * STIR_THIN, 0.0, 0.85));
	density = min(density, THICKEST_DRAWN);
	if (density < 0.004) {
		return 0.0;
	}
	return density;
}
