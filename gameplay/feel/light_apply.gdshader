// SPDX-License-Identifier: GPL-3.0-or-later
shader_type canvas_item;

// Spell light on the world (gameplay/feel/spell_light.gd; docs/milestones/spell-spectacle.md,
// P3a): one rect over the whole view, drawn above the room and the bodies and under every shot,
// effect and telegraph, that multiplies what is under it by `ambient` plus the light buffer's
// light. The light is cut into three steps by its brightest channel (dim: none; lit; bright), in
// its own hue, so a lit floor changes by whole bands, like a shade step, never by a smooth
// gradient. Where it is dim and the ambient is 1.0 nothing is drawn: the room looks as it does
// without spell light until something glows.
//
// It multiplies by reading the screen, not by blending: a multiply blend cannot brighten (its
// factor is clamped to 1 in an 8-bit target, the web's included), and light added on top would
// wash a dark floor out instead of lighting its colours.

// The light buffer (the light viewport's texture: the same view, smaller). Linear, so a band's
// edge is cut at the world's pixels, not the buffer's.
uniform sampler2D light_buffer : filter_linear, repeat_disable;
uniform sampler2D screen : hint_screen_texture, filter_nearest, repeat_disable;
// The room's light where no spell lights it (1.0: as it is).
uniform float ambient = 1.0;
// From how bright a light the world is lit, and bright; and how much each step adds.
uniform float lit_from = 0.16;
uniform float bright_from = 0.45;
uniform float lit_gain = 0.22;
uniform float bright_gain = 0.45;

void fragment() {
	vec3 shine = texture(light_buffer, SCREEN_UV).rgb;
	float most = max(shine.r, max(shine.g, shine.b));
	float gain = most >= bright_from ? bright_gain : (most >= lit_from ? lit_gain : 0.0);
	if (gain <= 0.0 && ambient >= 1.0) {
		discard;
	}
	vec3 hue = gain > 0.0 ? shine / most : vec3(0.0);
	vec3 under = texture(screen, SCREEN_UV).rgb;
	COLOR = vec4(under * (vec3(ambient) + hue * gain), 1.0);
}
