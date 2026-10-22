// SPDX-License-Identifier: GPL-3.0-or-later
shader_type canvas_item;
render_mode blend_mix;

// Draws a neutral bone sprite whose Spark-coloured pixels (the "core") take an element's
// colour. The bone part is multiplied by the vertex colour (the owner's tint); the core
// colour is the MultiMesh custom data of the shot, or `core_override` for a lone Sprite2D
// (alpha above 0 turns it on). A pixel is core when it is warm (red well above blue);
// every bone shade is near neutral, so no new palette colour is needed. The core keeps the
// three Spark shades as light and dark.

uniform vec4 core_override = vec4(0.0);
// Multiplies the vertex colour: the tint and the fade of a lone Sprite2D (its modulate stays white).
uniform vec4 body_tint = vec4(1.0);

varying flat vec4 body;
varying flat vec3 core;

void vertex() {
	body = COLOR * body_tint;
	core = core_override.a > 0.0 ? core_override.rgb : INSTANCE_CUSTOM.rgb;
}

void fragment() {
	vec4 t = texture(TEXTURE, UV);
	vec3 rgb = t.rgb * body.rgb;
	float warm = smoothstep(0.1, 0.25, t.r - t.b);
	float lum = dot(t.rgb, vec3(0.3, 0.59, 0.11));
	float shade = clamp((lum - 0.5) / 0.45, 0.0, 1.0);
	vec3 lit = mix(core * 0.55, mix(core, vec3(1.0), 0.55), shade);
	COLOR = vec4(mix(rgb, lit, warm), t.a * body.a);
}
