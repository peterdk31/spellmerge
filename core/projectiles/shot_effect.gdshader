// SPDX-License-Identifier: GPL-3.0-or-later
shader_type canvas_item;
render_mode blend_premul_alpha;

// Feel's flashes (gameplay/feel/feel.gd, its effect batch; core/README.md, "The shot shaders"), in
// a square quad GRID x zoom across, +x along their aim, all in the ramp and look of the shot they
// come from; the age is the code beside the kind (`coded_age`). Blending is premultiplied: a
// pixel is opaque, the glow round it light added to what is below.
//   K_BURST       where a shot lands: a white-hot cross that shrinks, sparks thrown back
//                 against the flight that cool as they fly, and the shot's card particles
//   K_RING_OUT    a ring that flashes out (a nova's cast)
//   K_RING_IN     a ring that gathers in (a rune's or orbit's cast)
//   K_RUNE_BURST  a rune going off: a dotted flash over the diamond, a diamond ring widening
//                 to twice its size, sparks all round
//   K_CAST        the staff tip on a cast: a small cross and a few sparks along the aim
//   K_DASH        the dust of a wizard's dash where it started (the effect's place); its way is
//                 the caster's trail (TF_DASH in shot_trail.gdshader) and its landing Feel's
//                 ring; its quad is zoom x 4 pixels plus DASH_MARGIN each end, DASH_ACROSS across
//   K_SPRAY       a hit on a character: sparks thrown on along the hit's way, cooling
//   K_PUFF        sparks all round and a dotted white-hot puff (a kill, a reaction, a hit
//                 with no way); with the POOF bit (kind 22) a staff's personality swap instead
//                 (living staffs H4): bone clouds along the staff (+x) that swell to their
//                 biggest at 35% of the effect (where the body changes) and shrink away, and a
//                 few sparks in the player's colour
//   K_CHIPS       stone chips knocked back off a wall, falling; stone does not glow
// Lightning (K_ARC) and statuses (K_STATUS) have shaders and batches of their own.

#include "res://core/projectiles/shot_palette.gdshaderinc"
#include "res://core/projectiles/shot_look.gdshaderinc"
#include "res://core/projectiles/shot_particle.gdshaderinc"

const float GRID = 24.0;
const float DASH_MARGIN = 12.0;
const float DASH_ACROSS = 32.0;
// A rune's reach at its rest (the 14 px of rune.tres, as `shot_rune.gdshader` draws it at zoom 4).
const float RUNE_REACH = 14.4;

varying flat float kind;
// How far through its life the effect is, 0 to 1.
varying flat float age;

void vertex() {
	kind = coded_kind(INSTANCE_CUSTOM.a);
	age = coded_age(coded_code(INSTANCE_CUSTOM.a));
	Look L = look_from_color(COLOR, INSTANCE_CUSTOM.rgb, float(INSTANCE_ID % 61) * 1.618, true);
	SET_LOOK(L);
}

// A wizard's dash (K_DASH): the dust kicked up where it left, both ways along the floor, `uv`
// over a quad DASH_MARGIN longer than zoom x 4 pixels at each end. The way it went (speed
// streaks, its cards) is the caster's trail (TF_DASH), drawn where the wizard really went, and
// the ring where it lands is Feel's (staffs, 2026-10-28: the dash look followed the aim, not the
// wizard).
vec4 dash(vec2 uv) {
	float len = zoom * 4.0;
	vec2 size = vec2(len + 2.0 * DASH_MARGIN, DASH_ACROSS);
	// Whole pixels from where it left.
	vec2 d = floor(uv * size) - vec2(DASH_MARGIN, size.y * 0.5);
	float a = age;
	float travel = min(a / 0.45, 1.0);
	for (int n = 0; n < 6; n++) {
		float i = float(n);
		float way = hash(i, 9.0, 51.0) < 0.5 ? -1.0 : 1.0;
		vec2 at = vec2(way * (1.0 + 9.0 * hash(i, 4.0, 51.0)) * travel, 8.0 - 3.0 * hash(i, 5.0, 51.0) * travel);
		if (a < 0.5 && on(d + 0.5, at + 0.5)) {
			return vec4(a < 0.25 ? STONE_LIGHT : STONE_BASE, 1.0);
		}
	}
	return vec4(0.0);
}

vec4 effect(vec2 uv) {
	if (kind == K_DASH) {
		return dash(uv);
	}
	vec2 size = vec2(GRID) * zoom;
	vec2 d = floor(uv * size) + 0.5 - size * 0.5 - vec2(0.5);
	float a = age;
	float r = length(d);
	float ease = 1.0 - (1.0 - a) * (1.0 - a);
	vec4 colour = vec4(0.0);
	float lit = 0.0;
	if (kind == K_BURST || kind == K_CAST) {
		bool cast = kind == K_CAST;
		// The flash: a white-hot cross that shrinks.
		float arm = round((cast ? 1.5 : 2.0) * zoom * (1.0 - a * 2.5));
		if (arm >= 0.0 && ((d.x == 0.0 && abs(d.y) <= arm) || (d.y == 0.0 && abs(d.x) <= arm))) {
			colour = vec4(r < 0.5 ? hot : hi, 1.0);
		}
		// Sparks thrown back against the flight (along the aim from a staff), cooling as they fly.
		int sparks = cast ? 4 : 8;
		for (int n = 0; n < 8; n++) {
			if (n >= sparks || colour.a > 0.0) {
				break;
			}
			float i = float(n);
			float life = 0.5 + 0.5 * hash(i, 1.0, 31.0);
			if (a > life) {
				continue;
			}
			float ang = (cast ? 0.0 : 3.1416) + (hash(i, 2.0, 31.0) - 0.5) * (cast ? 1.0 : 2.8);
			float reach = (1.5 + (cast ? 6.0 : 10.0) * (0.6 + 0.4 * hash(i, 3.0, 31.0)) * ease) * zoom;
			if (on(d + 0.5, vec2(cos(ang), sin(ang)) * reach + 0.5)) {
				colour = vec4(ramp(a / life), 1.0);
			}
		}
		lit = (1.0 - a) * (1.0 - a) * (0.9 * falloff(r, 4.0 * zoom) + 0.4 * falloff(r, 10.0 * zoom));
	} else if (kind == K_RING_OUT || kind == K_RING_IN) {
		// A ring that flashes out or gathers in, fraying as it goes.
		float big = 10.0 * zoom, small = 2.0 * zoom;
		float radius = kind == K_RING_OUT ? mix(small, big, ease) : mix(big, small, ease);
		float bucket = floor(atan(d.y, d.x) * radius / 2.0);
		if (abs(r - radius) < 0.5 && hash(bucket, floor(a * 8.0), 32.0) > a * 0.7) {
			colour = vec4(ramp(a), 1.0);
		}
		lit = 0.5 * (1.0 - a) * falloff(abs(r - radius), 3.0 * zoom);
	} else if (kind == K_RUNE_BURST) {
		float m = abs(d.x) + abs(d.y);
		// A dotted white-hot flash over the diamond, then a diamond ring that widens and frays.
		if (a < 0.2 && m <= RUNE_REACH && mod(d.x + d.y, 2.0) == 0.0) {
			colour = vec4(a < 0.1 ? hot : hi, 1.0);
		}
		float wide = mix(RUNE_REACH, RUNE_REACH * 2.2, ease);
		float bucket = floor(atan(d.y, d.x) * wide / 2.0);
		if (abs(m - wide) < 0.5 && hash(bucket, floor(a * 8.0), 33.0) > a * 0.7) {
			colour = vec4(ramp(a), 1.0);
		}
		for (int n = 0; n < 16; n++) {
			if (colour.a > 0.0) {
				break;
			}
			float i = float(n);
			float ang = i * 0.3927 + (hash(i, 4.0, 31.0) - 0.5) * 0.4;
			float reach = (4.0 + 26.0 * (0.6 + 0.4 * hash(i, 5.0, 31.0)) * ease);
			if (a < 0.8 && on(d + 0.5, vec2(cos(ang), sin(ang)) * reach + 0.5)) {
				colour = vec4(ramp(a), 1.0);
			}
		}
		lit = (1.0 - a) * (0.5 * falloff(abs(m - wide), 6.0) + (a < 0.25 ? 0.8 : 0.0) * falloff(m, RUNE_REACH));
	} else if (kind == K_PUFF && bit_set(bits, POOF)) {
		// A staff's poof: four bone clouds along the staff, biggest at 35%, dotted as they go.
		float swell = a < 0.35 ? a / 0.35 : 1.0 - (a - 0.35) / 0.65;
		for (int n = 0; n < 4; n++) {
			float i = float(n);
			vec2 c = vec2((i - 1.5) * 6.0, (hash(i, 17.0, 31.0) - 0.5) * 3.0) * zoom * 0.5;
			float size = (2.5 + 1.5 * hash(i, 18.0, 31.0)) * swell * zoom * 0.5 + 0.5;
			float q = length(d - c);
			if (q <= size && (a < 0.7 || mod(d.x + d.y, 2.0) == 0.0)) {
				// Lit from the top-left: light on that side, shadow on the far rim.
				vec2 side = (d - c) / max(size, 1.0);
				vec3 shade = side.x + side.y < -0.5 ? BONE_LIGHT : (q > size - 1.0 && side.x + side.y > 0.3 ? BONE_SHADOW : BONE_BASE);
				colour = vec4(shade, 1.0);
				break;
			}
		}
		for (int n = 0; n < 6; n++) {
			if (colour.a > 0.0) {
				break;
			}
			float i = float(n);
			float ang = i / 6.0 * 6.2832 + hash(i, 19.0, 31.0);
			float reach = (4.0 + 6.0 * hash(i, 20.0, 31.0) * ease) * zoom;
			if (a < 0.8 && on(d + 0.5, vec2(cos(ang) * 1.6, sin(ang)) * reach + 0.5)) {
				colour = vec4(a < 0.4 ? hi : mid, 1.0);
			}
		}
		lit = (1.0 - a) * 0.3 * falloff(r, 6.0 * zoom);
	} else if (kind == K_SPRAY || kind == K_PUFF) {
		bool round_about = kind == K_PUFF;
		// A small white-hot cross where it struck, or a dotted puff.
		if (round_about) {
			if (a < 0.18 && r <= 2.0 * zoom && mod(d.x + d.y, 2.0) == 0.0) {
				colour = vec4(a < 0.09 ? hot : hi, 1.0);
			}
		} else if (a < 0.2 && ((d.x == 0.0 && abs(d.y) <= 1.0) || (d.y == 0.0 && abs(d.x) <= 1.0))) {
			colour = vec4(hot, 1.0);
		}
		int sparks = round_about ? 14 : 10;
		for (int n = 0; n < 14; n++) {
			if (n >= sparks || colour.a > 0.0) {
				break;
			}
			float i = float(n);
			float life = 0.5 + 0.5 * hash(i, 11.0, 31.0);
			if (a > life) {
				continue;
			}
			float ang = round_about ? i / 14.0 * 6.2832 + (hash(i, 12.0, 31.0) - 0.5) * 0.4 : (hash(i, 12.0, 31.0) - 0.5) * 1.6;
			float reach = (2.0 + (round_about ? 10.0 : 13.0) * (0.5 + 0.5 * hash(i, 13.0, 31.0)) * ease) * zoom;
			if (on(d + 0.5, vec2(cos(ang), sin(ang)) * reach + 0.5)) {
				colour = vec4(ramp(a / life), 1.0);
			}
		}
		lit = (1.0 - a) * (1.0 - a) * (0.7 * falloff(r, 3.0 * zoom) + 0.3 * falloff(r, 9.0 * zoom));
	} else if (kind == K_CHIPS) {
		// Stone chips knocked back off the wall, falling as they fly; no glow.
		for (int n = 0; n < 7; n++) {
			float i = float(n);
			float ang = (hash(i, 14.0, 31.0) - 0.5) * 2.2;
			float reach = (2.0 + 9.0 * (0.5 + 0.5 * hash(i, 15.0, 31.0)) * ease) * zoom;
			vec2 at = vec2(cos(ang), sin(ang)) * reach + vec2(0.0, 0.0);
			// Down the screen as it falls, whatever the wall's side.
			vec2 fall = vec2(0.0, 7.0 * a * a * zoom);
			vec2 local = at;
			if (a < 0.9 && (on(d + 0.5, local + 0.5 + fall) || (hash(i, 16.0, 31.0) < 0.4 && on(d + 0.5, local + vec2(1.5, 0.5) + fall)))) {
				return vec4(a < 0.3 ? STONE_LIGHT : (a < 0.65 ? STONE_BASE : STONE_SHADOW), 1.0);
			}
		}
		return vec4(0.0);
	}
	// The shot's cards: its particles, set off from round the middle at the start.
	if (colour.a == 0.0 && emit_count() > 0.5 && kind != K_CAST) {
		float spread = kind == K_RUNE_BURST ? RUNE_REACH : 2.0 * zoom;
		float count = min(4.0 + 2.0 * emit_count(), float(MAX_PARTICLES));
		for (int n = 0; n < MAX_PARTICLES; n++) {
			if (float(n) >= count) {
				break;
			}
			float i = float(n);
			float look = emitter(int(min(floor(hash(i, 6.0, 31.0) * emit_count()), emit_count() - 1.0)));
			float ang = hash(i, 7.0, 31.0) * 6.2832;
			vec2 from = vec2(cos(ang), sin(ang)) * spread * hash(i, 8.0, 31.0);
			float pa = (a - 0.3 * hash(i, 9.0, 31.0)) / 0.7;
			if (pa > 0.0 && pa < 1.0) {
				vec4 p = particle(look, from, pa, i, 0.0, d, zoom);
				if (p.a > 0.0) {
					colour = p;
				}
			}
		}
	}
	if (colour.a > 0.0) {
		return colour;
	}
	if (has_layer(L_PULL)) {
		lit *= 0.6;
	}
	return vec4(glow * lit * glow_strength, 0.0);
}

void fragment() {
	COLOR = effect(UV);
}
