// SPDX-License-Identifier: GPL-3.0-or-later
shader_type canvas_item;
render_mode blend_premul_alpha;

// A familiar card's own look (content/spells/forms/familiar/: `FormBase.look_shader`;
// docs/milestones/card-looks.md; the owner, 2026-11-08: rework the carriers' looks). A copy of the
// plain orbit shot (`core/projectiles/shot_orbit.gdshaderinc`, the fallback) that draws a little
// spirit instead of a shot: a round orb in its owner's ramp, shadowed at its rim, lit from the
// front with a white-hot glint, two eyes looking the way it flies that blink now and then, bobbing
// as it circles, and a wispy tail behind it along its circle that waves like a flame and frays.
// Its instance, quad and particle rule are the orbit shot's; Entities draws every familiar's orb
// with it; warmed as a batch before the first room.

#include "res://core/projectiles/shot_palette.gdshaderinc"
#include "res://core/projectiles/shot_look.gdshaderinc"
#include "res://core/projectiles/shot_particle.gdshaderinc"

// The spark pool's share (1.0 is everything): the fraction of the particles drawn.
uniform float particle_share = 1.0;

// The quad: GRID pixels across, LENGTH along, the shot FRONT pixels from the front
// (LOOK_GRID, LOOK_LENGTH in projectile_manager.gd).
const float GRID = 24.0;
const float LENGTH = 72.0;
const float FRONT = 12.0;
// The tail, in pixels at zoom 1 (frost's is longer, lightning's shorter). On a bend it covers at
// most TAIL_TURN radians of the curve, so it stays inside the quad.
const float TAIL = 48.0;
const float TAIL_TURN = 0.6;
// The bend: 1 / the radius of the path's curve, BEND_ZERO for a straight path, BEND_SPAN either
// side for the tightest (1 / BEND_RADIUS); the same numbers as BEND_* in projectile_manager.gd.
// Below BEND_MIN a path counts as straight.
const float BEND_ZERO = 0.225;
const float BEND_SPAN = 0.2;
const float BEND_RADIUS = 16.0;
const float BEND_MIN = 0.004;
// Which side of the quad a positive bend turns to.
const float BEND_SIDE = 1.0;

varying flat float bend;

void vertex() {
	float b = coded_code(INSTANCE_CUSTOM.a);
	bend = 0.0;
	if (b > 0.01) {
		bend = (b - BEND_ZERO) / BEND_SPAN / BEND_RADIUS * BEND_SIDE;
		if (abs(bend) < BEND_MIN) {
			bend = 0.0;
		}
	}
	Look L = look_from_color(COLOR, INSTANCE_CUSTOM.rgb, float(INSTANCE_ID % 61) * 1.618, true);
	SET_LOOK(L);
}

// Where the shot was `t` pixels ago along its path, from its core: straight back, or round the
// bend's circle.
vec2 tail_point(float t) {
	if (bend == 0.0) {
		return vec2(-t, 0.0);
	}
	float r = 1.0 / bend;
	return vec2(-r * sin(t / r), r * (1.0 - cos(t / r)));
}

// A point `d` from the core in tail coordinates: how far back along the path, how far across.
vec2 tail_coords(vec2 d) {
	if (bend == 0.0) {
		return vec2(-d.x, d.y);
	}
	float r = 1.0 / bend;
	vec2 v = d - vec2(0.0, r);
	float a = atan(-v.x, -v.y * sign(r));
	return vec2(a * abs(r), sign(r) * (abs(r) - length(v)));
}

// The orb's radius and its wispy tail's length, in pixels at zoom 1; how often it blinks (a
// second) and for how long (a share of a blink's turn).
const float ORB = 3.0;
const float WISP = 22.0;
// The most of its circle the wisp covers (radians), so it stays inside its quad.
const float WISP_TURN = 0.9;
const float BLINK_RATE = 0.31;
const float BLINK_SHARE = 0.05;

vec4 shot(vec2 uv) {
	// The screen pixel, with +x along the flight, the core at 0, pixel centres on whole numbers.
	vec2 size = vec2(LENGTH, GRID) * zoom;
	vec2 q = floor(uv * size) + 0.5 - vec2(size.x - FRONT * zoom, size.y * 0.5);
	vec4 colour = vec4(0.0);
	vec2 c = vec2(0.5);
	// It bobs a pixel across its way, slowly, each on its own beat.
	c.y += triangle(sim_time * 1.3 + seed * 0.25) > 0.3 ? 1.0 : 0.0;
	vec2 d = q - c;
	float R = ORB * zoom;
	// Its tail: a wisp behind it along its circle, as wide as the orb where it leaves it and a
	// pixel at its end, waving like a flame, fraying and cooling as it goes.
	float tail = WISP * zoom;
	if (bend != 0.0) {
		tail = min(tail, WISP_TURN / abs(bend));
	}
	vec2 tn = tail_coords(d);
	if (tn.x > 0.5 && tn.x < tail) {
		float t = floor(tn.x);
		float u = t / tail;
		float fr = floor(sim_time * 12.0 + seed);
		float wave = sin(t * 0.38 / zoom - sim_time * 9.0 + seed) * 1.4 * zoom * u;
		float half_w = max((R - 0.5) * (1.0 - u), 0.5 * zoom);
		float across = abs(tn.y - wave);
		bool shown = across <= half_w && (u < 0.6 || hash(t, fr + floor(tn.y), 12.0) > (u - 0.6) * 2.2);
		if (shown) {
			float edge = half_w - across;
			vec3 rgb = u < 0.35 ? (edge > 0.75 ? hi : mid) : (u < 0.7 ? (edge > 0.75 ? mid : lo) : lo);
			colour = vec4(rgb, 1.0);
		}
	}
	// What the cards give off: particles born at random points of the tail.
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
			vec2 from = c + tail_point((1.0 + 0.5 * WISP * hash(i, cyc, 8.0)) * zoom) + vec2(0.0, (hash(i, cyc, 9.0) - 0.5) * 2.0 * zoom);
			vec4 p = particle(look, from, fract(t), i, cyc, q, zoom);
			if (p.a > 0.0) {
				colour = p;
			}
		}
	}
	// The orb: round, its shadow at the rim, lit from the front, a white-hot glint, and two eyes
	// looking where it flies that blink now and then.
	float d2 = dot(d, d);
	if (d2 <= R * R + R * 0.6) {
		bool rim = d2 > (R - 1.0) * (R - 1.0) + (R - 1.0) * 0.6;
		vec3 rgb = rim ? lo : (d.x > 0.5 * zoom ? hi : mid);
		vec2 glint = floor(vec2(-0.3, -0.6) * R + 0.5);
		rgb = all(equal(floor(d / zoom), floor(glint / zoom))) ? BONE_LIGHT : rgb;
		bool blink = fract(sim_time * BLINK_RATE + seed * 0.13) < BLINK_SHARE;
		vec2 eye = vec2(floor(0.45 * R + 0.5), 0.0);
		vec2 de = floor(d / zoom) - floor(eye / zoom);
		bool on_eye = de.x == 0.0 && abs(de.y) == 1.0;
		rgb = on_eye ? (blink ? lo : OUTLINE) : rgb;
		colour = vec4(rgb, 1.0);
	}
	if (colour.a > 0.0) {
		return colour;
	}
	// The glow: light added round the orb and along its wisp.
	float r = length(d);
	float lit = 0.7 * falloff(r, (R + 4.0) * zoom) + 0.3 * falloff(r, (R + 11.0) * zoom);
	if (tn.x > 0.0 && tn.x < tail) {
		float u = tn.x / tail;
		lit += 0.35 * (1.0 - u) * (1.0 - u) * falloff(abs(tn.y), 4.0 * zoom);
	}
	return vec4(glow * lit * glow_strength, 0.0);
}

void fragment() {
	COLOR = shot(UV);
}
