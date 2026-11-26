// SPDX-License-Identifier: GPL-3.0-or-later
shader_type canvas_item;
render_mode blend_premul_alpha;

// A field, the circle that catches shots and lets them go in a burst (content/spells/carriers/field/:
// its card's own shot shader, `CarrierCard.look_shader`; docs/milestones/field.md, "The look";
// core/README.md, "The shot shaders"): a ring of light on the floor at its hit size (it grows with
// the shots it holds, so the ring does), two world pixels wide and drawn at the art's detail (lit
// from the top-left: its outer edge light on the upper left, base on the lower right; ART2), its edge
// trembling a world pixel in and out in stepped frames, seen from above at a slant
// (its card's `look_shape`), four short marks inside it pointing in, and a sparse shimmer of lit
// pixels drifting round inside it, all by whole pixels. It opens in 4 frames (the ring steps out from
// its middle to its edge over its card's `look_open`) and closes in 4 (the ring breaks into ever
// shorter arcs over its last `look_fade`): docs/STYLE.md, "Smooth". A bright pixel chases round the
// ring, the way a shot taking it comes in. Every infusion shows (its palette, `palette_turn`): the
// ring in the first, the marks in the second, the shimmer in the third (the first's with one). The
// motes rising off its ring are its card's `look_motes`. Blending is premultiplied: its pixels are
// opaque, the glow added light.
//
// It knows its time since it was placed, and its life left, from its still clock (`still_since`,
// `still_left`: the code beside its kind, `ProjectileManager.still_code`). Its quad is GRID x zoom
// pixels square round its centre, from the projectile manager's instance data (`_write_quad`).

#include "res://core/projectiles/shot_palette.gdshaderinc"
#include "res://core/projectiles/shot_look.gdshaderinc"
#include "res://core/projectiles/shot_particle.gdshaderinc"

// The spark pool's share (set by the projectile manager, 1.0 is everything): the fraction of
// every shot's particles drawn this frame.
uniform float particle_share = 1.0;

const float GRID = 24.0;
// It is drawn at the art's detail, ART_DETAIL of its pixels a world pixel (shot_palette.gdshaderinc;
// ART2), every place and size below in art pixels, so its ring's light and shade are an art pixel each.
// Its ring's half width and half depth in its hit size as drawn (STILL_HIT), its card's
// `look_shape` (set by the projectile manager, `set_body_shape`); `look_clock` the seconds it takes
// to open and the seconds of its end it closes over (its card's `look_open`, `look_fade`).
uniform vec2 look_shape = vec2(1.0, 0.7);
uniform vec2 look_clock = vec2(0.25, 0.5);

// Worked out once a field (vertex): how far open it is (0 to 4, whole frames), how far closed (0 to
// 4), where the chasing pixel is (0 to 1 round) and the shimmer's frame.
varying flat vec4 phase;
// Its palette (`palette_floats`): the materials of its infusions, -1 past them.
varying flat vec4 pal;

void vertex() {
	float code = coded_code(INSTANCE_CUSTOM.a);
	Look L = look_from_color(COLOR, INSTANCE_CUSTOM.rgb, float(INSTANCE_ID % 61) * 1.618, true);
	SET_LOOK(L);
	float opened = floor(clamp(still_since(code) / max(look_clock.x, 0.001), 0.0, 1.0) * 4.0 + 0.001);
	float closed = floor(clamp((STILL_END - still_left(code)) / max(look_clock.y, 0.001), 0.0, 1.0) * 4.0 + 0.001);
	phase = vec4(opened, closed, fract(sim_time * 0.6 + L.seed), floor(sim_time * 6.0 + L.seed));
	pal = palette_floats(L.core, L.bits);
}

vec4 field_look(vec2 uv) {
	// The screen pixel, whole numbers, the field's centre at 0 (it never turns: a field is round).
	vec2 size = vec2(GRID) * zoom * ART_DETAIL;
	vec2 p = floor(uv * size - size * 0.5);
	vec2 full = size.x * STILL_HIT * look_shape;
	// Opening: the ring steps out from a quarter of its size to the whole of it, a frame a step.
	float grow = max(phase.x, 1.0) / 4.0;
	vec2 r = max(floor(full * grow + 0.5), vec2(2.0 * ART_DETAIL));
	vec2 e = p / r;
	float el = length(e);
	vec2 g = p / (r * r);
	float gl = max(length(g), 0.0001);
	vec2 n = g / gl;
	// Distance to the ring in pixels (its outward side positive).
	float dist = (el - 1.0) * el / gl;
	float edge = max(abs(n.x), abs(n.y));
	float round_at = fract(atan(e.y, e.x) / TAU + 0.25);
	// The trembling edge: the ring steps a pixel in or out round its length, in 4 frames a loop at
	// 12 a second, whole pixels.
	float tremble = floor(1.6 * ART_DETAIL * sin(round_at * TAU * 9.0 + frame_of(12.0) * 1.5708) + 0.5);
	dist -= tremble * edge;
	// Closing: the ring breaks into 8 arcs, each shorter a frame, gone at the fourth.
	float keep = 1.0 - phase.y / 4.0;
	bool shown = phase.y < 0.5 || fract(round_at * 8.0) < keep;
	vec4 colour = vec4(0.0);
	// What the cards give off: particles born at random points of the ring.
	if (emit_count() > 0.5) {
		// The same rule as `particles_of` in projectile_manager.gd; keep the two equal.
		float asked = min(4.0 + 2.0 * emit_count(), float(MAX_PARTICLES));
		// Each shot rounds its share by its own seed, so the pool's total stays near the share.
		int count = int(floor(asked * particle_share + fract(seed)));
		for (int k = 0; k < MAX_PARTICLES; k++) {
			if (k >= count) {
				break;
			}
			float i = float(k);
			float t = sim_time * (1.5 + 1.0 * hash(i, 0.0, 3.0)) + hash(i, 0.0, 4.0);
			float cyc = floor(t);
			float look = emitter(int(min(floor(hash(i, cyc, 7.0) * emit_count()), emit_count() - 1.0)));
			float ang = hash(i, cyc, 8.0) * TAU;
			vec4 q = particle(look, vec2(cos(ang), sin(ang)) * r / ART_DETAIL, fract(t), i, cyc, floor(p / ART_DETAIL), zoom);
			if (q.a > 0.0) {
				colour = q;
			}
		}
	}
	if (shown && dist > -3.5 * edge && dist < 0.5 * edge) {
		// Two world pixels wide, lit from the top-left (ART2): its outer art pixel in the base on
		// the lower right and the light on the upper left, its inner art pixel a shade down, the
		// light between.
		float lower_right = n.x + n.y;
		bool outer = dist > -0.5 * edge;
		bool inner = dist <= -2.5 * edge;
		vec3 base_shade = palette_turn(pal, 0, 1, mid);
		vec3 light_shade = palette_turn(pal, 0, 2, hi);
		colour = vec4(outer ? (lower_right > 0.0 ? base_shade : light_shade) : (inner ? base_shade : light_shade), 1.0);
		// The chasing pixel, white-hot, and its tail a shade down.
		float lag = fract(phase.z - round_at);
		if (lag < 0.02) {
			colour = vec4(hot, 1.0);
		} else if (lag < 0.06) {
			colour = vec4(palette_turn(pal, 0, 2, hi), 1.0);
		}
	}
	// Four marks inside the ring, pointing in, once it is open.
	if (phase.x > 3.5 && phase.y < 3.5) {
		vec2 a = abs(p);
		bool across = a.x < 0.5 && a.y > r.y - 5.0 * ART_DETAIL && a.y < r.y - 2.0 * ART_DETAIL;
		bool along = a.y < 0.5 && a.x > r.x - 6.0 * ART_DETAIL && a.x < r.x - 2.0 * ART_DETAIL;
		if (across || along) {
			colour = vec4(palette_turn(pal, 1, 1, mid), 1.0);
		}
	}
	// The shimmer: a few lit pixels inside it, drifting a pixel a frame.
	if (colour.a == 0.0 && el < 0.85 && phase.y < 2.5) {
		float step_px = 5.0 * ART_DETAIL;
		vec2 cell = floor((p + vec2(phase.w, 0.0)) / step_px);
		float h = hash(cell.x, cell.y, 11.0);
		vec2 at = floor(cell * step_px + vec2(hash(cell.x, cell.y, 12.0), hash(cell.x, cell.y, 13.0)) * step_px) - vec2(phase.w, 0.0);
		if (h > 0.86 && p == at) {
			colour = vec4(palette_turn(pal, 2, 2, hi), 1.0);
		}
	}
	if (colour.a > 0.0) {
		return colour;
	}
	// The glow: a soft light over its floor and round its ring, dimmer as it closes.
	float lit = (0.10 * falloff(el, 1.0) + 0.35 * falloff(abs(dist), 3.0 * ART_DETAIL)) * (shown ? 1.0 : 0.3) * keep;
	if (has_layer(L_SPARKS)) {
		// Lightning flickers.
		lit *= 0.55 + 0.9 * hash(floor(sim_time * 20.0), 0.0, 21.0);
	}
	return vec4(glow * lit * glow_strength, 0.0);
}

void fragment() {
	COLOR = field_look(UV);
}
