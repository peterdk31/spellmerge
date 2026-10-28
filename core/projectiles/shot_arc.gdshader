// SPDX-License-Identifier: GPL-3.0-or-later
shader_type canvas_item;
render_mode blend_premul_alpha;

// Lightning jumping from the effect's place along its aim for zoom x 4 pixels (Feel's K_ARC, a
// discharge; its own batch in gameplay/feel/feel.gd; core/README.md, "The shot shaders"): a
// jagged line re-rolled 30 times a second that burns out from the ends as it ages. Its quad is
// that long plus ARC_MARGIN each end, ARC_ACROSS across; the age is the code beside the kind.

#include "res://core/projectiles/shot_palette.gdshaderinc"
#include "res://core/projectiles/shot_look.gdshaderinc"

const float ARC_MARGIN = 4.0;
const float ARC_ACROSS = 16.0;

varying flat float age;

void vertex() {
	age = coded_age(coded_code(INSTANCE_CUSTOM.a));
	Look L = look_from_color(COLOR, INSTANCE_CUSTOM.rgb, float(INSTANCE_ID % 61) * 1.618, false);
	SET_LOOK(L);
}

// A discharge (K_ARC): `uv` over a quad ARC_MARGIN longer than the arc at each end.
vec4 arc(vec2 uv) {
	float len = zoom * 4.0;
	vec2 size = vec2(len + 2.0 * ARC_MARGIN, ARC_ACROSS);
	vec2 d = floor(uv * size) - vec2(ARC_MARGIN, size.y * 0.5);
	float a = age;
	float seg = 5.0;
	float k = floor(d.x / seg);
	float jf = floor(sim_time * 30.0);
	float o0 = k < 0.5 ? 0.0 : (hash(k, jf, 61.0) - 0.5) * 6.0;
	float o1 = (k + 1.0) * seg >= len ? 0.0 : (hash(k + 1.0, jf, 61.0) - 0.5) * 6.0;
	float off = round(mix(o0, o1, fract(d.x / seg)));
	bool along = d.x >= 0.0 && d.x <= len;
	// It burns out from the ends inwards as it fades.
	bool kept = hash(d.x, 0.0, 62.0) > a * 1.2 - 0.2;
	if (along && kept && d.y == off) {
		return vec4(a < 0.4 ? hot : hi, 1.0);
	}
	if (along && kept && abs(d.y - off) == 1.0 && hash(d.x, jf, 63.0) < 0.25) {
		return vec4(mid, 1.0);
	}
	float lit = along ? (1.0 - a) * 0.6 * falloff(abs(d.y - off), 5.0) : 0.0;
	lit *= 0.6 + 0.8 * hash(jf, 0.0, 64.0);
	return vec4(glow * lit * glow_strength, 0.0);
}

void fragment() {
	COLOR = arc(UV);
}
