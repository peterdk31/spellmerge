// SPDX-License-Identifier: GPL-3.0-or-later
shader_type canvas_item;
render_mode blend_premul_alpha;

// A pool's puddle (content/spells/forms/pool/): a flat oval on the floor in its card's colours,
// ripples running out over a dithered middle the floor shows through, a few bubbles, spreading out
// while it is new, its card particles given off from its outline and a soft glow.
// Its quad is GRID x zoom pixels square round its centre, from the projectile manager's instance
// data as a rune's (`ProjectileManager._write_quad`: the look in COLOR and the custom data, the
// trace code beside the kind in the custom data's alpha). Blending is premultiplied: its pixels are
// opaque, the glow added light. Drawn by its card's pair of batches (`FormBase.look_shader`,
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

// Pool: a flat oval `reach` x 1.3 wide and x 0.75 deep (seen from above at a slant), spreading
// out from its middle while it is new: a one-pixel rim in its base shade, light at its top-left
// edge; inside, a checker of its base shade the floor shows through, ripples of its light shade
// running out from the middle, and now and then a white-hot bubble. Returns the pixel's colour
// (alpha 0 for none).
vec4 pool_pixel(vec2 q, float reach) {
	vec2 e = q / vec2(reach * 1.3, reach * 0.75);
	float r = length(e);
	float spread = max(age, 0.15);
	if (r > spread) {
		return vec4(0.0);
	}
	float edge = (spread - r) * reach;
	if (edge < 1.0) {
		return vec4(q.x < 0.0 && q.y < 0.0 ? hi : mid, 1.0);
	}
	float ripple = fract(r * 2.5 - sim_time * 0.8 + seed);
	if (ripple < 0.12) {
		return vec4(hi, 1.0);
	}
	vec2 cell = floor(q * 0.25);
	float blink = hash(cell.x * 7.0 + cell.y, floor(sim_time * 3.0 + seed), 11.0);
	if (blink > 0.985 && mod(floor(q.x) + floor(q.y), 4.0) < 0.5) {
		return vec4(hot, 1.0);
	}
	if (mod(floor(q.x) + floor(q.y), 2.0) < 0.5) {
		return vec4(mid, 1.0);
	}
	return vec4(0.0);
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
	vec4 b = pool_pixel(q, reach);
	if (b.a > 0.0) {
		return b;
	}
	if (colour.a > 0.0) {
		return colour;
	}
	// Its glow: a soft light over the whole puddle.
	float lit_pool = 0.3 * falloff(length(q / vec2(1.3, 0.75)), reach * 1.2) * age;
	return vec4(glow * lit_pool * glow_strength, 0.0);
}

void fragment() {
	COLOR = body_look(UV);
}
