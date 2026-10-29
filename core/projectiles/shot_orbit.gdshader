// SPDX-License-Identifier: GPL-3.0-or-later
shader_type canvas_item;
render_mode blend_premul_alpha;

// A shot drawn whole in its own quad, its tail bent round its path (core/README.md, "The shot
// shaders"): Entities' familiars, orbit shots flying round their wizard (gameplay/ai/entities.gd).
// A shot the projectile manager flies leaves its tail in the world instead (`shot_trail.gdshader`).
// The quad is LENGTH x GRID pixels times the zoom, the shot FRONT pixels from its front edge and
// its tail behind, +x along the flight. The code beside the kind is the bend (how its path
// curves, so its tail follows it; BEND_* below). The look (the owner, 2026-10-27): a small
// white-hot core, a long tail of pixels that cool from hot to dark and fray at the end, a soft
// glow round both, and the card particles given off from the tail. Blending is premultiplied:
// its pixels are opaque, the glow added light.

#include "res://core/projectiles/shot_palette.gdshaderinc"
#include "res://core/projectiles/shot_look.gdshaderinc"
#include "res://core/projectiles/shot_particle.gdshaderinc"

// The spark pool's share (1.0 is everything): the fraction of the particles and of the tail drawn.
uniform float particle_share = 1.0;
uniform float trail_share = 1.0;

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

vec4 shot(vec2 uv) {
	// The screen pixel, with +x along the flight, the core at 0, pixel centres on whole numbers.
	vec2 size = vec2(LENGTH, GRID) * zoom;
	vec2 q = floor(uv * size) + 0.5 - vec2(size.x - FRONT * zoom, size.y * 0.5);
	int pi = int(player);
	vec4 colour = vec4(0.0);
	vec2 c = vec2(0.5);
	if (has_layer(L_WEAVE)) {
		// Homing: the shot weaves a pixel either side.
		c.y += triangle(sim_time * 3.0 + seed * 0.25) > 0.0 ? 1.0 : 0.0;
	}
	vec2 d = q - c;
	// The tail: one pixel a column (zoom pixels for a bigger shot), cooling from white-hot to
	// shadow and fraying towards its end, re-rolled 24 times a second.
	float tail = TAIL * zoom * trail_share * (has_layer(L_FLECKS) ? 1.2 : 1.0) * (has_layer(L_SPARKS) ? 0.7 : 1.0);
	if (bend != 0.0) {
		tail = min(tail, TAIL_TURN / abs(bend));
	}
	vec2 tn = tail_coords(d);
	if (tn.x > 1.5 && tn.x < tail) {
		float t = floor(tn.x);
		float u = t / tail;
		float fr = floor(sim_time * 24.0 + seed);
		float across = 0.0;
		bool shown;
		if (has_layer(L_SPARKS)) {
			// Lightning: a jagged line, its bends re-rolled 30 times a second.
			float seg = 4.0 * zoom;
			float k = floor(t / seg);
			float jf = floor(sim_time * 30.0 + seed);
			float o0 = k < 0.5 ? 0.0 : (hash(k, jf, 13.0) - 0.5) * 4.0 * zoom;
			float o1 = (hash(k + 1.0, jf, 13.0) - 0.5) * 4.0 * zoom;
			across = mix(o0, o1, fract(t / seg));
			shown = u < 0.9 || hash(t, fr, 12.0) > u;
		} else {
			across = (hash(t, fr, 11.0) - 0.5) * 3.0 * u * zoom;
			float keep = pow(1.0 - u, has_layer(L_FLECKS) ? 0.5 : 0.8) * (has_layer(L_PULL) ? 0.7 : 1.0);
			shown = t < 3.0 * zoom || hash(t, fr, 12.0) < keep;
		}
		if (has_layer(L_GUSTS)) {
			// Storm: the tail sways side to side.
			across += sin(t * 0.35 / zoom - sim_time * 28.0) * 1.4 * zoom;
		}
		float k = round(tn.y) - round(across) + floor(zoom * 0.5);
		if (shown && k >= 0.0 && k < zoom) {
			bool own = plain < 0.5 && hash(t, fr, 14.0) < 0.25;
			vec3 rgb = u < 0.12 ? hot : (u < 0.35 ? hi : (u < 0.7 ? mid : lo));
			if (own) {
				rgb = u < 0.35 ? P_LIGHT[pi] : (u < 0.7 ? P_BASE[pi] : P_SHADOW[pi]);
			}
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
			vec2 from = c + tail_point((1.0 + 0.5 * TAIL * hash(i, cyc, 8.0)) * zoom) + vec2(0.0, (hash(i, cyc, 9.0) - 0.5) * 2.0 * zoom);
			vec4 p = particle(look, from, fract(t), i, cyc, q, zoom);
			if (p.a > 0.0) {
				colour = p;
			}
		}
	}
	// The body: a white-hot heart in a rim, a 3-pixel cross at zoom 1 that grows a pixel each
	// side a zoom; void's is a dark heart.
	vec2 dc = d;
	if (has_layer(L_STREAKS)) {
		dc.x *= 0.6;
	}
	float m = abs(dc.x) + abs(dc.y);
	float tier = m < 0.5 * zoom ? (has_layer(L_PULL) ? 4.0 : 3.0) : (m < zoom + 0.5 ? 2.0 : 0.0);
	if (tier > 0.5) {
		vec3 rgb = tier < 2.5 ? hi : (tier < 3.5 ? hot : OUTLINE);
		colour = vec4(rgb, 1.0);
	}
	if (colour.a > 0.0) {
		return colour;
	}
	// The glow: light added round the core and along the tail.
	float r = length(d);
	float lit = 0.8 * falloff(r, 4.0 * zoom) + 0.35 * falloff(r, 10.0 * zoom);
	if (tn.x > 0.0 && tn.x < tail) {
		float u = tn.x / tail;
		lit += 0.4 * (1.0 - u) * (1.0 - u) * falloff(abs(tn.y), 5.0 * zoom);
	}
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
	COLOR = shot(UV);
}
