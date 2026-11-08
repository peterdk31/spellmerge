// SPDX-License-Identifier: GPL-3.0-or-later
shader_type canvas_item;
render_mode blend_premul_alpha;

// A wall's standing ward stone (content/spells/forms/wall/): a slab lit from the top-left with a
// glyph cut down its face, light running up it, a glowing line at its foot, rising out of the floor
// while it is new, its card particles given off from its outline and a soft glow.
// Its quad is GRID x zoom pixels square round its centre, from the projectile manager's instance
// data as a rune's (`ProjectileManager._write_quad`: the look in COLOR and the custom data, the
// trace code beside the kind in the custom data's alpha). Blending is premultiplied: its pixels are
// opaque, the glow added light. Drawn by its card's pair of batches (`FormBase.shot_shader`,
// `ProjectileManager.register_body`), warmed before the first room.

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

// Stone: a slab `reach` x 1.25 either side of the middle (a wall's stones touch), from 3 reaches
// above it to 0.8 below, its top corners cut round, rimmed dark against the floor, its cap lit;
// lit down its left side, shadowed down its right; a glyph cut down
// its middle with ticks off alternate sides, a light running up it; a glowing line at its foot.
// While it is new it rises out of the floor. Returns the pixel's colour (alpha 0 for none).
vec4 stone_pixel(vec2 q, float reach) {
	float w = floor(reach * 1.25 + 0.5);
	float top = -floor(reach * 3.0 + 0.5);
	float foot = floor(reach * 0.8 + 0.5);
	float x = floor(q.x);
	float y = floor(q.y);
	if (y == foot + 1.0 && abs(x) <= w + 1.0) {
		return vec4(abs(x) <= w - 1.0 ? hi : mid, 1.0);
	}
	float risen = foot - (foot - top) * age;
	if (abs(x) > w || y < top || y > foot || y < risen || abs(x) > w - 2.0 + (y - top)) {
		return vec4(0.0);
	}
	if (x == 0.0 && y > top + 1.0 && y < foot - 1.0) {
		return vec4(mod(y - floor(-sim_time * 10.0 + seed * 7.0), 7.0) < 1.0 ? hot : hi, 1.0);
	}
	if (abs(x) == 1.0 && y > top + 1.0 && y < foot - 1.0 && mod(y + (x > 0.0 ? 2.0 : 0.0), 4.0) == 0.0) {
		return vec4(mid, 1.0);
	}
	// Its rim dark against the floor, its cap lit, its left face light and its right in shadow.
	bool rim = abs(x) == w || y == top || y == foot || abs(x) == w - 2.0 + (y - top);
	if (rim) {
		return vec4(OUTLINE, 1.0);
	}
	if (y <= top + 1.0 || abs(x) >= w - 3.0 + (y - top)) {
		return vec4(BONE_SHADOW, 1.0);
	}
	return vec4(x < -w * 0.4 ? STONE_LIGHT : (x > w * 0.4 ? STONE_SHADOW : STONE_BASE), 1.0);
}

vec4 body_look(vec2 uv) {
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
	vec4 b = stone_pixel(q, reach);
	if (b.a > 0.0) {
		return b;
	}
	if (colour.a > 0.0) {
		return colour;
	}
	// Its glow: light down its glyph and along its foot.
	float lit_stone = 0.5 * falloff(length(q - vec2(0.0, -reach * 1.1)), reach * 2.2) * age;
	return vec4(glow * lit_stone * glow_strength, 0.0);
}

void fragment() {
	COLOR = body_look(UV);
}
