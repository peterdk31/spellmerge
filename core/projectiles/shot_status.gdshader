// SPDX-License-Identifier: GPL-3.0-or-later
shader_type canvas_item;
render_mode blend_premul_alpha;

// A status on a character (Feel's K_STATUS, its own batch in gameplay/feel/feel.gd; core/README.md,
// "The shot shaders"), kept while it lasts and moved with it: its look's particles round it,
// endless, and a pulsing glow, in a square quad GRID x zoom across.

#include "res://core/projectiles/shot_palette.gdshaderinc"
#include "res://core/projectiles/shot_look.gdshaderinc"
#include "res://core/projectiles/shot_particle.gdshaderinc"

const float GRID = 24.0;

void vertex() {
	Look L = look_from_color(COLOR, INSTANCE_CUSTOM.rgb, float(INSTANCE_ID % 61) * 1.618, true);
	SET_LOOK(L);
}

// A status (K_STATUS): its look's particles round the character, endless, and a pulsing glow.
vec4 status(vec2 uv) {
	vec2 size = vec2(GRID) * zoom;
	vec2 d = floor(uv * size) - size * 0.5;
	float reach = 4.0 * zoom;
	for (int n = 0; n < 8; n++) {
		float i = float(n);
		float t = sim_time * (1.2 + 0.8 * hash(i, 0.0, 71.0)) + hash(i, 0.0, 72.0);
		float cyc = floor(t);
		float ang = hash(i, cyc, 73.0) * 6.2832;
		vec2 from = vec2(cos(ang), sin(ang) * 0.8) * reach * (0.5 + 0.5 * hash(i, cyc, 74.0));
		vec4 p = vec4(0.0);
		if (emit_count() > 0.5) {
			float look = emitter(int(min(floor(hash(i, cyc, 75.0) * emit_count()), emit_count() - 1.0)));
			p = particle(look, from, fract(t), i, cyc, d, 1.0);
		} else if (fract(t) < 0.8 && on(d, from + vec2(0.0, -6.0 * fract(t)))) {
			p = vec4(fract(t) < 0.4 ? hi : mid, 1.0);
		}
		if (p.a > 0.0) {
			return p;
		}
	}
	float pulse = 0.6 + 0.4 * sin(sim_time * 6.0 + seed);
	return vec4(glow * 0.3 * pulse * falloff(length(d), reach * 1.6) * glow_strength, 0.0);
}

void fragment() {
	COLOR = status(UV);
}
