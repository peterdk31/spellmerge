// SPDX-License-Identifier: GPL-3.0-or-later
shader_type canvas_item;
render_mode blend_premul_alpha;

// A still shot whose card names no shader of its own (`FormBase.shot_shader`; the projectile
// manager's still and enemy still batches; core/README.md, "The shot shaders"): a plain mark, a
// white-hot 3 px cross in its light shade's ring, its card particles given off round it and a soft
// glow. Every card that stands still draws its own look (a rune's, a wall's stones, a pool's
// puddle); this is only the fallback. Its quad is GRID x zoom pixels square round its centre, from
// the manager's instance data (`ProjectileManager._write_quad`). Blending is premultiplied: its
// pixels are opaque, the glow added light.

#include "res://core/projectiles/shot_palette.gdshaderinc"
#include "res://core/projectiles/shot_look.gdshaderinc"
#include "res://core/projectiles/shot_particle.gdshaderinc"

// The spark pool's share (set by the projectile manager, 1.0 is everything): the fraction of
// every shot's particles drawn this frame.
uniform float particle_share = 1.0;

const float GRID = 24.0;

// How far it has grown since it was made, 0 to 1 (1 once it is whole).
varying flat float age;

void vertex() {
	age = coded_age(coded_code(INSTANCE_CUSTOM.a));
	Look L = look_from_color(COLOR, INSTANCE_CUSTOM.rgb, float(INSTANCE_ID % 61) * 1.618, true);
	SET_LOOK(L);
}

vec4 still_look(vec2 uv) {
	// The screen pixel, the centre at 0, pixel centres on whole numbers.
	vec2 size = vec2(GRID) * zoom;
	vec2 q = floor(uv * size) + 0.5 - size * 0.5;
	float reach = size.x * 0.5 * 0.3;
	vec4 colour = vec4(0.0);
	// What the cards give off: particles born at random points round it.
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
			float kind = emitter(int(min(floor(hash(i, cyc, 7.0) * emit_count()), emit_count() - 1.0)));
			float ang = hash(i, cyc, 8.0) * 6.2832;
			vec4 p = particle(kind, vec2(cos(ang), sin(ang)) * reach, fract(t), i, cyc, q, zoom);
			if (p.a > 0.0) {
				colour = p;
			}
		}
	}
	// Its mark: a white-hot cross, a ring of its light shade one pixel round it.
	float d = abs(q.x) + abs(q.y);
	if (d < 1.0 || (d < 2.0 && (abs(q.x) < 1.0 || abs(q.y) < 1.0))) {
		return vec4(hot, 1.0);
	}
	if (d < 3.0 && age > 0.5) {
		return vec4(hi, 1.0);
	}
	if (colour.a > 0.0) {
		return colour;
	}
	// Its glow.
	return vec4(glow * 0.5 * falloff(length(q), 8.0) * glow_strength, 0.0);
}

void fragment() {
	COLOR = still_look(UV);
}
