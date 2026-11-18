// SPDX-License-Identifier: GPL-3.0-or-later
// The world's stirs (gameplay/feel/stirs.gd; docs/milestones/atmosphere.md, E), read by what takes
// notice of them: the ground cover (cover.gdshader) and the stirred motes (mote.gdshader). Handed
// over by `Stirs.hand_to`:
//   stir_field     the shots' wake: a texel a Stirs.CELL px cell of a window round the view
//                  (Stirs.FIELD_W x FIELD_H), red and green the way the air there is dragged (at
//                  most 1 long), eased on the CPU so it never pops; read bilinear.
//   stir_origin    the window's corner, world px.
//   stir_blasts    each blast's middle (x, y), how far it pushes (z, px) and when it began (w, Feel's
//                  clock); stir_strength how strongly (0: no blast in the slot).
// `stir_wake` and `stir_blasts_at` are Stirs.wake_at and Stirs.blast_push, line for line.

uniform sampler2D stir_field : hint_default_black, filter_linear, repeat_disable;
uniform vec2 stir_origin = vec2(0.0);
uniform vec4 stir_blasts[16];
uniform float stir_strength[16];

// Stirs.CELL, FIELD_W, FIELD_H, BLASTS, WAVE_SPEED, RISE, FALL.
const float STIR_CELL = 16.0;
const vec2 STIR_CELLS = vec2(96.0, 64.0);
const int STIR_BLASTS = 16;
const float STIR_WAVE_SPEED = 260.0;
const float STIR_RISE = 0.08;
const float STIR_FALL = 0.6;

// The wake at `p` (world px): the cells round it, bilinear; zero outside the window.
vec2 stir_wake(vec2 p) {
	vec2 at = (p - stir_origin) / STIR_CELL;
	if (at.x < 0.0 || at.y < 0.0 || at.x > STIR_CELLS.x || at.y > STIR_CELLS.y) {
		return vec2(0.0);
	}
	return textureLod(stir_field, at / STIR_CELLS, 0.0).rg;
}

// How far out a place is pushed `age` seconds after a blast's wave reached it.
float stir_envelope(float age) {
	if (age <= 0.0) {
		return 0.0;
	}
	if (age < STIR_RISE) {
		float r = age / STIR_RISE;
		return r * r * (3.0 - 2.0 * r);
	}
	float t = min((age - STIR_RISE) / STIR_FALL, 1.0);
	return (1.0 - t) * (1.0 - t) * cos(t * 3.14159265 * 1.5);
}

// The blasts' push at `p` at Feel's clock `now`: out from each that reaches it, added, at most 1 long.
vec2 stir_blasts_at(vec2 p, float now) {
	vec2 push = vec2(0.0);
	for (int k = 0; k < STIR_BLASTS; k++) {
		float strength = stir_strength[k];
		if (strength <= 0.0) {
			continue;
		}
		vec4 b = stir_blasts[k];
		vec2 away = p - b.xy;
		float far = length(away);
		if (far >= b.z || far < 0.5) {
			continue;
		}
		float age = now - b.w - far / STIR_WAVE_SPEED;
		push += away / far * (strength * (1.0 - far / b.z) * stir_envelope(age));
	}
	float most = length(push);
	return most > 1.0 ? push / most : push;
}
