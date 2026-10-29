// SPDX-License-Identifier: GPL-3.0-or-later
shader_type canvas_item;
render_mode blend_premul_alpha;

// A rune (the projectile manager's rune batches; core/README.md, "The shot shaders"): a one-pixel
// diamond about its hit size with bright corners, a dotted ring inside and a glyph of four dots
// turning round a bright heart, swelling and settling while it waits, tracing itself onto the
// floor while it is new (the code beside its kind), its card particles given off from its outline
// and a soft glow. Its quad is GRID x zoom pixels square round its centre. Blending is
// premultiplied: its pixels are opaque, the glow added light.

#include "res://core/projectiles/shot_palette.gdshaderinc"
#include "res://core/projectiles/shot_look.gdshaderinc"
#include "res://core/projectiles/shot_particle.gdshaderinc"

// The spark pool's share (set by the projectile manager, 1.0 is everything): the fraction of
// every shot's particles drawn this frame.
uniform float particle_share = 1.0;

const float GRID = 24.0;

// How much of a new rune is traced, 0 to 1 (1 once it is whole).
varying flat float age;

void vertex() {
	age = coded_age(coded_code(INSTANCE_CUSTOM.a));
	Look L = look_from_color(COLOR, INSTANCE_CUSTOM.rgb, float(INSTANCE_ID % 61) * 1.618, true);
	SET_LOOK(L);
}

// Rune: a one-pixel diamond about its hit size with bright corners, a dotted ring inside and a
// glyph of four dots turning round a bright heart, swelling and settling while it waits. `reach`
// is in pixels. Returns the tier (0 none, 1 base, 2 light, 3 white-hot, 4 void's dark heart).
float rune(vec2 q, float reach, float swell) {
	float d = abs(q.x) + abs(q.y);
	if (d > reach) {
		return 0.0;
	}
	if (d > reach - 1.0) {
		// While it is new, the outline traces itself round from the top, clockwise.
		if (fract(atan(q.y, q.x) / 6.2832 + 1.25) > age) {
			return 0.0;
		}
		return abs(q.x) < 1.0 || abs(q.y) < 1.0 ? 3.0 : 2.0;
	}
	if (age < 1.0) {
		return 0.0;
	}
	if (d > reach - 5.0 && d <= reach - 4.0) {
		return mod(floor(q.x) + floor(q.y), 2.0) < 0.5 && mod(floor(sim_time * 4.0 + seed) + floor(q.x), 4.0) < 2.0 ? 1.0 : 0.0;
	}
	float ang = sim_time * 2.2 + seed;
	for (int k = 0; k < 4; k++) {
		float a = ang + float(k) * 1.5708;
		if (on(q, vec2(cos(a), sin(a)) * 4.0)) {
			return 2.0;
		}
	}
	if (d < 1.0) {
		return has_layer(L_PULL) ? 4.0 : (swell > 0.5 ? 3.0 : 2.0);
	}
	return 0.0;
}

vec4 rune_look(vec2 uv) {
	// The screen pixel, the centre at 0, pixel centres on whole numbers.
	vec2 size = vec2(GRID) * zoom;
	vec2 q = floor(uv * size) + 0.5 - size * 0.5;
	vec4 colour = vec4(0.0);
	float f = frame_of(3.0);
	float swell = f < 0.5 ? 0.0 : (f < 1.5 ? 1.0 : (f < 2.5 ? 2.0 : 1.0));
	float reach = size.x * 0.5 * (0.30 + 0.03 * swell);
	// What the cards give off: particles born at random points of the outline.
	if (emit_count() > 0.5) {
		// The same rule as `particles_of` in projectile_manager.gd; keep the two equal.
		float asked = min(4.0 + 2.0 * emit_count(), float(MAX_PARTICLES));
		// Each shot rounds its share by its own seed, so the pool's total stays near the share.
		int count = int(floor(asked * particle_share + fract(seed)));
		for (int n = 0; n < MAX_PARTICLES; n++) {
			if (n >= count) {
				break;
			}
			float i = float(n);
			float t = sim_time * (2.5 + 1.5 * hash(i, 0.0, 3.0)) + hash(i, 0.0, 4.0);
			float cyc = floor(t);
			float look = emitter(int(min(floor(hash(i, cyc, 7.0) * emit_count()), emit_count() - 1.0)));
			float ang = hash(i, cyc, 8.0) * 6.2832;
			vec2 dir = vec2(cos(ang), sin(ang));
			vec2 from = dir * reach / (abs(dir.x) + abs(dir.y));
			vec4 p = particle(look, from, fract(t), i, cyc, q, zoom);
			if (p.a > 0.0) {
				colour = p;
			}
		}
	}
	float tier = rune(q, reach, swell);
	if (tier > 0.5) {
		vec3 rgb = tier < 1.5 ? mid : (tier < 2.5 ? hi : (tier < 3.5 ? hot : OUTLINE));
		colour = vec4(rgb, 1.0);
	}
	if (colour.a > 0.0) {
		return colour;
	}
	// The glow: light added round its outline and its heart.
	float ring = abs(abs(q.x) + abs(q.y) - reach);
	float lit = (0.35 * (0.7 + 0.15 * swell) * falloff(ring, 6.0) + 0.5 * falloff(length(q), 8.0)) * age;
	if (has_layer(L_SPARKS)) {
		// Lightning flickers.
		lit *= 0.55 + 0.9 * hash(floor(sim_time * 20.0), 0.0, 21.0);
	}
	if (has_layer(L_PULL)) {
		lit *= 0.6;
	}
	return vec4(glow * lit * glow_strength, 0.0);
}

void fragment() {
	COLOR = rune_look(UV);
}
