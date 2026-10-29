// SPDX-License-Identifier: GPL-3.0-or-later
shader_type canvas_item;
render_mode blend_premul_alpha;

// A sprite in the shots' style (core/README.md, "The shot shaders"): Feel's afterimages and
// deaths, a wizard's dash ghosts (gameplay/player/staff_look.gd), Entities' decoys. A neutral
// bone sprite whose Spark-coloured (warm) pixels take `core_override`'s colour, that can fall
// apart pixel by pixel and glow round its own pixels. Blending is premultiplied: the sprite's
// pixels are opaque, the glow round them is light added to what is below.

#include "res://core/projectiles/shot_palette.gdshaderinc"

// The colour the warm pixels take (alpha above 0 turns it on; alpha 0 keeps the sprite's own colours:
// a staff's body glowing with its animation, gameplay/player/staff_look.gd).
uniform vec4 core_override = vec4(0.0);
// Multiplies the vertex colour: the tint and the fade of a lone Sprite2D.
uniform vec4 body_tint = vec4(1.0);
// How bright the glow is (1.0 the look; 0.0 none).
uniform float glow_strength = 1.0;
// The dissolve (Feel's death, a wizard's dash afterimages): 0 whole, 1 gone. Its pixels turn
// `dissolve_color` (white-hot unless set) and fall out one by one.
uniform float dissolve = 0.0;
uniform vec4 dissolve_color = vec4(0.957, 0.945, 0.918, 1.0);
// The glow: light added round the sprite's own pixels (a combo mark, an afterimage), as bright
// as this; the sprite needs a few empty pixels round it to hold it. Its hue is `glow_color` when
// that has alpha above 0 (a staff's charge in its player's colour), else the tint's or the dissolve's.
uniform float sprite_glow = 0.0;
uniform vec4 glow_color = vec4(0.0);

varying flat vec4 body;
varying flat vec3 core;

void vertex() {
	body = COLOR * body_tint;
	core = core_override.a > 0.0 ? core_override.rgb : vec3(1.0);
}

void fragment() {
	vec4 t = texture(TEXTURE, UV);
	vec3 rgb = t.rgb * body.rgb;
	float warm = core_override.a > 0.0 ? smoothstep(0.1, 0.25, t.r - t.b) : 0.0;
	float lum = dot(t.rgb, vec3(0.3, 0.59, 0.11));
	float shade = clamp((lum - 0.5) / 0.45, 0.0, 1.0);
	vec3 lit = mix(core * 0.55, mix(core, vec3(1.0), 0.55), shade);
	float alpha = t.a * body.a;
	vec3 shown = mix(rgb, lit, warm);
	if (dissolve > 0.0) {
		vec2 px = floor(UV / TEXTURE_PIXEL_SIZE);
		if (t.a > 0.5 && hash_seeded(px.x, px.y, 81.0, 0.0) < dissolve * 1.2 - 0.1) {
			alpha = 0.0;
		} else if (t.a > 0.5) {
			shown = mix(shown, dissolve_color.rgb, min(dissolve * 3.0, 1.0));
			alpha = 1.0;
		}
	}
	if (alpha < 0.5 && sprite_glow > 0.0) {
		// The glow: how much of the sprite is near, 2 and 4 pixels away in eight directions.
		float near = 0.0;
		for (int k = 0; k < 8; k++) {
			vec2 dir = vec2(cos(float(k) * 0.7854), sin(float(k) * 0.7854)) * TEXTURE_PIXEL_SIZE;
			near += texture(TEXTURE, UV + dir * 2.0).a * 0.09 + texture(TEXTURE, UV + dir * 4.0).a * 0.035;
		}
		vec3 hue = glow_color.a > 0.0 ? glow_color.rgb : (dissolve > 0.0 ? dissolve_color.rgb : body.rgb);
		COLOR = vec4(hue * near * sprite_glow * (1.0 - dissolve) * glow_strength, 0.0);
	} else {
		// Premultiplied, as the blend mode wants.
		COLOR = vec4(shown * alpha, alpha);
	}
}
