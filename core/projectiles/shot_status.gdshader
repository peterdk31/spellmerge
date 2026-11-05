// SPDX-License-Identifier: GPL-3.0-or-later
shader_type canvas_item;
render_mode blend_premul_alpha;

// A status on a character (Feel's K_STATUS, its own batch in gameplay/feel/feel.gd; core/README.md,
// "The shot shaders"), kept while it lasts and moved with it: a pulsing glow in its colour, in a
// square quad GRID x zoom across. Its particles are its element card's motes, given off round the
// character by Feel (spell spectacle 2, S6 item 11), not drawn here.

#include "res://core/projectiles/shot_palette.gdshaderinc"
#include "res://core/projectiles/shot_look.gdshaderinc"

const float GRID = 24.0;

void vertex() {
	Look L = look_from_color(COLOR, INSTANCE_CUSTOM.rgb, float(INSTANCE_ID % 61) * 1.618, true);
	SET_LOOK(L);
}

// A status (K_STATUS): a glow round the character that pulses.
vec4 status(vec2 uv) {
	vec2 size = vec2(GRID) * zoom;
	vec2 d = floor(uv * size) - size * 0.5;
	float reach = 4.0 * zoom;
	float pulse = 0.6 + 0.4 * sin(sim_time * 6.0 + seed);
	return vec4(glow * 0.3 * pulse * falloff(length(d), reach * 1.6) * glow_strength, 0.0);
}

void fragment() {
	COLOR = status(UV);
}
