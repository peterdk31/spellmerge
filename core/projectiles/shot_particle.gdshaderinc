// SPDX-License-Identifier: GPL-3.0-or-later
// A card's particle drawn round a body (runes, familiars, beams, effects, statuses), in the
// body's own pixels (core/README.md, "The shot shaders"). Include `shot_palette.gdshaderinc` and
// `shot_look.gdshaderinc` first. A flying shot's particles are its trail's (`shot_trail.gdshader`),
// left in the world where the shot was.

// Particle `i` of kind `look`, born at `from` (pixels from the core), `a` of the way through
// its life (0-1), in cycle `cyc`: its colour at pixel `q`, or alpha 0. `z` is the zoom.
vec4 particle(float look, vec2 from, float a, float i, float cyc, vec2 q, float z) {
	float h = hash(i, cyc, 5.0);
	if (look == L_EMBERS) {
		// Fire: an ember that drifts back and up off the line, flickers and dims.
		vec2 at = from + vec2(-3.0 * a, ((h - 0.5) * 3.0 - 2.5) * a) * z;
		if (a < 0.85 && hash(i, floor(sim_time * 20.0), 6.0) > 0.2 && on(q, at)) {
			return vec4(a < 0.3 ? SPARK_LIGHT : (a < 0.6 ? FIRE_LIGHT : FIRE_BASE), 1.0);
		}
	} else if (look == L_FLECKS) {
		// Frost: a fleck left hanging behind, twinkling; young, a small star.
		vec2 at = from + vec2(-2.0 * a, 0.0) * z;
		vec2 d = abs(floor(q) - floor(at));
		bool star = h < 0.3 && a < 0.2 && d.x + d.y < 1.5 && d.x + d.y > 0.5;
		if (a < 0.9 && mod(floor(sim_time * 12.0 + i), 3.0) > 0.5 && (on(q, at) || star)) {
			return vec4(star ? ICE_LIGHT : BONE_LIGHT, 1.0);
		}
	} else if (look == L_GUSTS) {
		// Storm: a short streak blown back fast, curling.
		vec2 at = floor(from + vec2(-14.0 * a, (h - 0.5) * 8.0 * a * a) * z);
		vec2 d = floor(q) - at;
		if (a < 0.6 && d.y == 0.0 && d.x >= 0.0 && d.x <= 1.0 + z) {
			return vec4(a < 0.3 ? SPARK_LIGHT : vec3(0.949, 0.761, 0.188), 1.0);
		}
	} else if (look == L_PULL) {
		// Void: a pixel drawn in from round about, spiralling to the tail.
		float ang = h * 6.2832 + a * 2.0;
		vec2 at = mix(from + vec2(cos(ang), sin(ang)) * 7.0 * z, from, a);
		if (on(q, at)) {
			return vec4(a < 0.5 ? VOID_BASE : VOID_LIGHT, 1.0);
		}
	} else if (look == L_SPARKS) {
		// Lightning: a quick spark that jumps about each frame.
		float f = floor(sim_time * 20.0);
		vec2 at = from + (vec2(hash(i, f, 1.0), hash(i, f, 2.0)) - 0.5) * 6.0 * z;
		if (a < 0.4 && (on(q, at) || (a < 0.12 && on(q, at + vec2(1.0, -1.0))))) {
			return vec4(a < 0.12 ? ARC_LIGHT : ARC_BASE, 1.0);
		}
	} else if (look == L_MOTES) {
		// Mend: a mote that rises.
		vec2 at = from + vec2(-1.0 * a, -5.0 * a) * z;
		if (a < 0.9 && on(q, at)) {
			return vec4(ARC_LIGHT, 1.0);
		}
	} else if (look == L_GLINTS) {
		// Bigger: a glint that opens into a small cross and closes.
		vec2 at = floor(from + vec2(-2.0 * a, 0.0) * z);
		vec2 d = abs(floor(q) - at);
		bool open = a > 0.3 && a < 0.55;
		if (a > 0.2 && a < 0.65 && (d.x + d.y < 0.5 || (open && d.x + d.y < 1.5))) {
			return vec4(BONE_LIGHT, 1.0);
		}
	} else if (look == L_STREAKS) {
		// Pierce: a thin streak straight back off the core.
		vec2 at = floor(vec2(-2.0 * z - 8.0 * a * z, from.y * 0.3));
		vec2 d = floor(q) - at;
		if (a < 0.5 && d.y == 0.0 && d.x >= 0.0 && d.x <= 2.0 * z) {
			return vec4(BONE_LIGHT, 1.0);
		}
	} else if (look == L_BURST) {
		// Blast: a spark thrown out from the core.
		float ang = h * 6.2832;
		vec2 at = vec2(cos(ang), sin(ang)) * (2.0 + 6.0 * a) * z;
		if (a < 0.5 && on(q, at)) {
			return vec4(a < 0.25 ? FIRE_LIGHT : FIRE_BASE, 1.0);
		}
	} else if (look == L_ORBITERS) {
		// Shield: a spark circling the core.
		float ang = h * 6.2832 + a * 4.0;
		vec2 at = vec2(cos(ang), sin(ang)) * 4.5 * z;
		if (a < 0.8 && on(q, at)) {
			return vec4(BONE_LIGHT, 1.0);
		}
	} else if (look == L_GLITTER) {
		// Hold: glitter that stays close and blinks.
		float ang = h * 6.2832;
		vec2 at = vec2(cos(ang), sin(ang)) * (2.5 + 1.5 * hash(i, cyc, 6.0)) * z;
		if (mod(floor(sim_time * 10.0 + i), 2.0) < 0.5 && on(q, at)) {
			return vec4(SPARK_LIGHT, 1.0);
		}
	} else if (look == L_HOPS) {
		// Chain: a pixel that jumps sideways in steps, every other frame.
		vec2 at = from + vec2(-2.0 * a, (h < 0.5 ? -1.0 : 1.0) * (1.0 + floor(a * 4.0)) * 3.0) * z;
		if (a < 0.6 && mod(floor(sim_time * 24.0 + i), 2.0) < 0.5 && on(q, at)) {
			return vec4(a < 0.3 ? BONE_LIGHT : SPARK_LIGHT, 1.0);
		}
	} else if (look == L_WAKE) {
		// Faster: pixels flung straight back, fast, thinning out.
		vec2 at = from + vec2(-(3.0 + 14.0 * a) * z, (h - 0.5) * 4.0 * z);
		if (a < 0.5 && on(q, at)) {
			return vec4(a < 0.25 ? BONE_LIGHT : SPARK_LIGHT, 1.0);
		}
	}
	return vec4(0.0);
}
