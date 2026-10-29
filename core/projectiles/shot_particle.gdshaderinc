// SPDX-License-Identifier: GPL-3.0-or-later
// A card's particle drawn round a body (runes, familiars, beams, effects, statuses), in the
// body's own pixels (core/README.md, "The shot shaders"). Include `shot_palette.gdshaderinc` and
// `shot_look.gdshaderinc` first. A flying shot's particles are its trail's (`shot_trail.gdshader`),
// left in the world where the shot was.
//
// `place_particle` works out where a particle is and what it looks like, once: a vertex stage
// puts a small quad round it (PARTICLES ARE GEOMETRY, `shot_effect.gdshader`) and the fragment
// colours its pixels with `particle_pixel`. `particle` does both for one pixel, for the shaders
// that still loop over their particles per pixel.

// A particle as it is now: shown or not, its pixel (`at`, floored), a run of `run` more pixels
// to its right, a cross of arms `arm` round it in `arm_rgb`, one more pixel at `extra` from it
// (none when zero), its colour.
struct Particle {
	bool shown;
	vec2 at;
	float run;
	float arm;
	vec2 extra;
	vec3 rgb;
	vec3 arm_rgb;
};

// Particle `i` of kind `look`, born at `from` (pixels from the core), `a` of the way through
// its life (0-1), in cycle `cyc`, numbered with the seed `s`. `z` is the zoom.
Particle place_particle(float look, vec2 from, float a, float i, float cyc, float z, float s) {
	Particle p;
	p.shown = false;
	p.at = from;
	p.run = 0.0;
	p.arm = 0.0;
	p.extra = vec2(0.0);
	p.rgb = vec3(0.0);
	p.arm_rgb = vec3(0.0);
	float h = hash_seeded(i, cyc, 5.0, s);
	if (look == L_EMBERS) {
		// Fire: an ember that drifts back and up off the line, flickers and dims.
		p.at = from + vec2(-3.0 * a, ((h - 0.5) * 3.0 - 2.5) * a) * z;
		p.shown = a < 0.85 && hash_seeded(i, floor(sim_time * 20.0), 6.0, s) > 0.2;
		p.rgb = a < 0.3 ? SPARK_LIGHT : (a < 0.6 ? FIRE_LIGHT : FIRE_BASE);
	} else if (look == L_FLECKS) {
		// Frost: a fleck left hanging behind, twinkling; young, a small star.
		p.at = from + vec2(-2.0 * a, 0.0) * z;
		p.shown = a < 0.9 && mod(floor(sim_time * 12.0 + i), 3.0) > 0.5;
		p.arm = h < 0.3 && a < 0.2 ? 1.0 : 0.0;
		p.rgb = BONE_LIGHT;
		p.arm_rgb = ICE_LIGHT;
	} else if (look == L_GUSTS) {
		// Storm: a short streak blown back fast, curling.
		p.at = floor(from + vec2(-14.0 * a, (h - 0.5) * 8.0 * a * a) * z);
		p.shown = a < 0.6;
		p.run = 1.0 + z;
		p.rgb = a < 0.3 ? SPARK_LIGHT : vec3(0.949, 0.761, 0.188);
	} else if (look == L_PULL) {
		// Void: a pixel drawn in from round about, spiralling to the tail.
		float ang = h * 6.2832 + a * 2.0;
		p.at = mix(from + vec2(cos(ang), sin(ang)) * 7.0 * z, from, a);
		p.shown = true;
		p.rgb = a < 0.5 ? VOID_BASE : VOID_LIGHT;
	} else if (look == L_SPARKS) {
		// Lightning: a quick spark that jumps about each frame.
		float f = floor(sim_time * 20.0);
		p.at = from + (vec2(hash_seeded(i, f, 1.0, s), hash_seeded(i, f, 2.0, s)) - 0.5) * 6.0 * z;
		p.shown = a < 0.4;
		p.extra = a < 0.12 ? vec2(1.0, -1.0) : vec2(0.0);
		p.rgb = a < 0.12 ? ARC_LIGHT : ARC_BASE;
	} else if (look == L_MOTES) {
		// Mend: a mote that rises.
		p.at = from + vec2(-1.0 * a, -5.0 * a) * z;
		p.shown = a < 0.9;
		p.rgb = ARC_LIGHT;
	} else if (look == L_GLINTS) {
		// Bigger: a glint that opens into a small cross and closes.
		p.at = floor(from + vec2(-2.0 * a, 0.0) * z);
		p.shown = a > 0.2 && a < 0.65;
		p.arm = a > 0.3 && a < 0.55 ? 1.0 : 0.0;
		p.rgb = BONE_LIGHT;
		p.arm_rgb = BONE_LIGHT;
	} else if (look == L_STREAKS) {
		// Pierce: a thin streak straight back off the core.
		p.at = floor(vec2(-2.0 * z - 8.0 * a * z, from.y * 0.3));
		p.shown = a < 0.5;
		p.run = 2.0 * z;
		p.rgb = BONE_LIGHT;
	} else if (look == L_BURST) {
		// Blast: a spark thrown out from the core.
		float ang = h * 6.2832;
		p.at = vec2(cos(ang), sin(ang)) * (2.0 + 6.0 * a) * z;
		p.shown = a < 0.5;
		p.rgb = a < 0.25 ? FIRE_LIGHT : FIRE_BASE;
	} else if (look == L_ORBITERS) {
		// Shield: a spark circling the core.
		float ang = h * 6.2832 + a * 4.0;
		p.at = vec2(cos(ang), sin(ang)) * 4.5 * z;
		p.shown = a < 0.8;
		p.rgb = BONE_LIGHT;
	} else if (look == L_GLITTER) {
		// Hold: glitter that stays close and blinks.
		float ang = h * 6.2832;
		p.at = vec2(cos(ang), sin(ang)) * (2.5 + 1.5 * hash_seeded(i, cyc, 6.0, s)) * z;
		p.shown = mod(floor(sim_time * 10.0 + i), 2.0) < 0.5;
		p.rgb = SPARK_LIGHT;
	} else if (look == L_HOPS) {
		// Chain: a pixel that jumps sideways in steps, blinking two frames in three.
		p.at = from + vec2(-2.0 * a, (h < 0.5 ? -1.0 : 1.0) * (1.0 + floor(a * 4.0)) * 3.0) * z;
		p.shown = a < 0.8 && mod(floor(sim_time * 24.0 + i), 3.0) < 2.0;
		p.rgb = a < 0.3 ? BONE_LIGHT : SPARK_LIGHT;
	} else if (look == L_WAKE) {
		// Faster: pixels flung straight back, fast, thinning out.
		p.at = from + vec2(-(3.0 + 14.0 * a) * z, (h - 0.5) * 4.0 * z);
		p.shown = a < 0.5;
		p.rgb = a < 0.25 ? BONE_LIGHT : SPARK_LIGHT;
	} else if (look == L_WEIGHT) {
		// Heavy: a grey drip that falls, as long as it is fast.
		p.at = floor(from + vec2((h - 0.5) * 6.0 * z, (2.0 + 9.0 * a * a) * z));
		p.shown = a < 0.8;
		p.rgb = a < 0.4 ? BONE_LIGHT : BONE_SHADOW;
	} else if (look == L_RIPPLE) {
		// Growth: a two-pixel dash on a ring that opens round the core.
		float ang = h * 6.2832;
		p.at = floor(from + vec2(cos(ang), sin(ang)) * (2.0 + 9.0 * a) * z);
		p.shown = a < 0.8;
		p.run = 1.0;
		p.rgb = a < 0.5 ? BONE_LIGHT : BONE_BASE;
	} else if (look == L_CURL) {
		// Spiral and return: a two-pixel dash that swings out and curls back.
		float ang = h * 6.2832 + a * 7.0;
		p.at = floor(from + vec2(cos(ang) * 6.0 * a - 3.0 * a, sin(ang) * 6.0 * a) * z);
		p.shown = a < 0.9;
		p.run = 1.0;
		p.rgb = a < 0.5 ? BONE_LIGHT : BONE_BASE;
	} else if (look == L_ZIG) {
		// Bounce: a dash thrown back at an angle, either side.
		float side = h < 0.5 ? -1.0 : 1.0;
		p.at = floor(from + vec2(-3.0 - 6.0 * a, side * (1.0 + 7.0 * a)) * z);
		p.shown = a < 0.5;
		p.run = 1.0;
		p.rgb = a < 0.25 ? BONE_LIGHT : SPARK_LIGHT;
	} else if (look == L_DOUBLE) {
		// Echo, mirror, ghost: a steady dash peeling away to each side, a copy of the path.
		float side = h < 0.5 ? -1.0 : 1.0;
		p.at = floor(from + vec2(-2.0 * a * z, side * (2.0 + 5.0 * a) * z));
		p.shown = a < 0.7;
		p.run = 1.0 + z;
		p.rgb = BONE_SHADOW;
	} else if (look == L_CONVERGE) {
		// Magnet, siphon, possess: a two-pixel dash pulled in towards the core from ahead.
		p.at = floor(from + vec2((12.0 - 12.0 * a) * z, (h - 0.5) * 6.0 * (1.0 - a) * z));
		p.shown = a < 0.9;
		p.run = 1.0;
		p.rgb = a < 0.6 ? SPARK_LIGHT : BONE_LIGHT;
	} else if (look == L_DRIFT) {
		// Slow, hold, short delay: a cool grey pixel that hangs where it was and fades.
		p.at = from + vec2(-2.0 * z - (h - 0.5) * 3.0 * z, (h - 0.5) * 3.0 * z);
		p.shown = a < 0.95 && mod(floor(sim_time * 12.0 + i), 3.0) > 0.5;
		p.rgb = a < 0.5 ? STONE_LIGHT : STONE_BASE;
	}
	return p;
}

// The colour of particle `p` at the pixel `q`, or alpha 0.
vec4 particle_pixel(Particle p, vec2 q) {
	vec2 e = floor(q) - floor(p.at);
	vec2 m = abs(e);
	if (!p.shown) {
		return vec4(0.0);
	}
	if (e.y == 0.0 && e.x >= 0.0 && e.x <= p.run) {
		return vec4(p.rgb, 1.0);
	}
	if ((m.x == 0.0 || m.y == 0.0) && m.x + m.y <= p.arm) {
		return vec4(p.arm_rgb, 1.0);
	}
	if (any(notEqual(p.extra, vec2(0.0))) && all(equal(e, p.extra))) {
		return vec4(p.rgb, 1.0);
	}
	return vec4(0.0);
}

// Particle `i` of kind `look`, born at `from` (pixels from the core), `a` of the way through
// its life (0-1), in cycle `cyc`: its colour at pixel `q`, or alpha 0. `z` is the zoom.
vec4 particle(float look, vec2 from, float a, float i, float cyc, vec2 q, float z) {
	return particle_pixel(place_particle(look, from, a, i, cyc, z, seed), q);
}
