// SPDX-License-Identifier: GPL-3.0-or-later
// The look of a shot, effect or beam, shared by the shot shaders (core/README.md, "The shot
// shaders"): who it is (player ramp, zoom), its cards (the look bits and the kinds that give off
// particles), its ramp (white-hot, light, base, shadow and the glow) and the clock. Include
// `shot_palette.gdshaderinc` first.
//
// The instance data (the projectile manager's and Feel's batches):
//   custom data rgb  the core colour (the first infusion's tint; white for none)
//   custom data a    the kind and a code as 1 - (kind + code) / 16 (`coded_kind`, `coded_code`)
//   colour r         player + zoom x 4, as n / 255: the shapes grow with the zoom while every
//                    line stays one pixel, so a bigger shot is bigger, never chunkier
//   colour g, b, a   the look: one bit per layer kind (kind 1 is bit 0 of green, kind 9 bit 0
//                    of blue, kind 17 bit 0 of alpha), every kind the shot's cards bring, and
//                    the flags (POOF, ENEMY_RAMP, EXACT)
// A shader's vertex() works the look out once (`look_of`, `look_from_color`) and hands it to the
// fragments with SET_LOOK, so a pixel never does.

// Seconds of simulation (the projectile manager's, Feel's or Entities' clock); everything
// animates from it, not TIME, so a run stepped by hand (the clip recorder) draws the same frames.
uniform float sim_time = 0.0;
// How bright the glow is (1.0 the look; 0.0 none).
uniform float glow_strength = 1.0;

varying flat vec3 core;
varying flat float seed;
varying flat float player;
varying flat float zoom;
varying flat float plain;
varying flat vec3 bits;
// The ramp: white-hot, light, base, shadow; and the colour of the glow.
varying flat vec3 hot;
varying flat vec3 hi;
varying flat vec3 mid;
varying flat vec3 lo;
varying flat vec3 glow;
// The kinds that give off particles, in order, four to a number (4 bits each), and how many.
varying flat vec4 emits;

struct Look {
	vec3 core;
	float seed;
	float player;
	float zoom;
	float plain;
	vec3 bits;
	vec3 hot;
	vec3 hi;
	vec3 mid;
	vec3 lo;
	vec3 glow;
	vec4 emits;
};

#define SET_LOOK(L) core = L.core; seed = L.seed; player = L.player; zoom = L.zoom; plain = L.plain; bits = L.bits; hot = L.hot; hi = L.hi; mid = L.mid; lo = L.lo; glow = L.glow; emits = L.emits

// The look of `c` (the core colour) for `who` (0-3 a hat ramp; ENEMY_PLAYER) at `z` with the
// look bits `b`: its ramp and, with `particles`, the kinds it gives off.
Look look_of(vec3 c, float who, float z, vec3 b, float s, bool particles) {
	Look L;
	L.core = c;
	L.seed = s;
	L.zoom = z;
	L.bits = b;
	L.player = bit_set(b, ENEMY_RAMP) ? ENEMY_PLAYER : who;
	int pi = int(L.player);
	L.plain = all(greaterThan(c, vec3(0.99))) ? 1.0 : 0.0;
	if (bit_set(b, EXACT)) {
		L.plain = 0.0;
		L.mid = c;
		L.hi = mix(c, vec3(1.0), 0.35);
		L.hot = mix(c, vec3(1.0), 0.7);
		L.lo = c * 0.55;
	} else if (L.plain > 0.5) {
		L.hot = BONE_LIGHT;
		L.hi = P_LIGHT[pi];
		L.mid = P_BASE[pi];
		L.lo = P_SHADOW[pi];
	} else {
		int best = 0;
		float near = 9.0;
		for (int i = 0; i < MATERIALS * 3; i++) {
			float d = distance(c, SHADES[i]);
			if (d < near) {
				near = d;
				best = i / 3;
			}
		}
		L.lo = SHADES[best * 3];
		L.mid = SHADES[best * 3 + 1];
		L.hi = SHADES[best * 3 + 2];
		L.hot = mix(L.hi, vec3(1.0), 0.5);
	}
	L.glow = mix(L.mid, L.hi, 0.35);
	vec3 packed = vec3(0.0);
	float n = 0.0;
	if (particles) {
		for (float look = 1.0; look <= KIND_COUNT; look += 1.0) {
			if (look != L_WEAVE && bit_set(b, look)) {
				float slot = mod(n, 4.0);
				float add = look * exp2(slot * 5.0);
				if (n < 4.0) {
					packed.x += add;
				} else if (n < 8.0) {
					packed.y += add;
				} else {
					packed.z += add;
				}
				n += 1.0;
			}
		}
	}
	L.emits = vec4(packed, n);
	return L;
}

// The look an instance colour carries (see above), with the core colour `c`.
Look look_from_color(vec4 color, vec3 c, float s, bool particles) {
	float red = floor(color.r * 255.0 + 0.5);
	return look_of(c, mod(red, 4.0), max(floor(red / 4.0), 1.0), floor(color.gba * 255.0 + 0.5), s, particles);
}

// A number in [0, 1) from three numbers and the shot's seed: the same on every machine.
float hash(float a, float b, float c) {
	return hash_seeded(a, b, c, seed);
}

// The animation frame (0-3) at `rate` frames a second. Each shot starts on its own frame, so
// a volley does not blink together.
float frame_of(float rate) {
	return mod(floor(sim_time * rate + seed + 0.001), 4.0);
}

bool has_layer(float look) {
	return bit_set(bits, look);
}

float emit_count() {
	return emits.w;
}

// The `i`th kind that gives off particles.
float emitter(int i) {
	float word = i < 4 ? emits.x : (i < 8 ? emits.y : emits.z);
	return mod(floor(word / exp2(float(i % 4) * 5.0) + 0.001), 32.0);
}

// The ramp at `u` (0 white-hot, 1 shadow): what cools as it ages.
vec3 ramp(float u) {
	return u < 0.15 ? hot : (u < 0.4 ? hi : (u < 0.7 ? mid : lo));
}
