// SPDX-License-Identifier: GPL-3.0-or-later
shader_type canvas_item;

// Spell light on the world (gameplay/feel/spell_light.gd; docs/milestones/spell-spectacle.md,
// P3a, P3b): one rect over the whole view, drawn above the room and the bodies and under every
// shot, effect and telegraph, that multiplies what is under it by `ambient` plus the light
// buffer's light, in the light's own hue. How the light is cut is `bands`, by its brightest
// channel: 3 (the default) is three steps (dim: none; lit; bright), so a lit floor changes by
// whole bands, like a shade step; 2 is one step; more are more steps between `lit_from` and
// `bright_from`; 0 is no steps, a smooth gradient up to the bright step's light (the owner's
// choice between the two is open, 2026-11-04). Where nothing is lit and the ambient is 1.0
// nothing is drawn: the room looks as it does without spell light until something glows.
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
// The steps the light comes in (see above): 0 smooth, else that many (dim counted), at least 2.
uniform int bands = 3;

// The light a pixel adds for a light of brightest channel `most`.
float gain_of(float most) {
	if (bands <= 0) {
		return clamp(most / bright_from, 0.0, 1.0) * bright_gain;
	}
	// Steps at lit_from .. bright_from, their gains lit_gain .. bright_gain, evenly between.
	int steps = max(bands - 1, 1);
	float gain = 0.0;
	for (int k = 0; k < steps; k++) {
		float share = steps > 1 ? float(k) / float(steps - 1) : 0.0;
		if (most >= mix(lit_from, bright_from, share)) {
			gain = mix(lit_gain, bright_gain, share);
		}
	}
	return gain;
}

void fragment() {
	vec3 shine = texture(light_buffer, SCREEN_UV).rgb;
	float most = max(shine.r, max(shine.g, shine.b));
	float gain = gain_of(most);
	if (gain < 0.004 && ambient >= 1.0) {
		discard;
	}
	vec3 hue = gain > 0.0 && most > 0.0 ? shine / most : vec3(0.0);
	vec3 under = texture(screen, SCREEN_UV).rgb;
	COLOR = vec4(under * (vec3(ambient) + hue * gain), 1.0);
}
