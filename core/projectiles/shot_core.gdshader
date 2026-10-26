// SPDX-License-Identifier: GPL-3.0-or-later
shader_type canvas_item;
render_mode blend_mix;

// The look of a player's shot (staffs B6a, docs/milestones/M2-staffs.md, "The look of a shot"),
// built here on a pixel grid of GRID x GRID cells, so a shot needs no art and no nodes.
//
// MultiMesh instances (the projectile manager) carry:
//   custom data rgb  the core colour (the first infusion's tint; white for none)
//   custom data a    the body kind as 1 - kind / 16: 1 a bolt (with a trail), 2 a rune, 3 an
//                    orbit shot; 0 draws the texture (below)
//   colour r         player + zoom x 4, as n / 255: the quad is GRID x zoom screen pixels,
//                    and the shapes grow with the zoom while every line stays one pixel, so
//                    a bigger shot is bigger, never chunkier
//   colour g, b, a   the look: one bit per layer kind (kind 1 is bit 0 of green, kind 9 bit 0
//                    of blue, kind 17 bit 0 of alpha), every kind the shot's cards bring
// Paint order: the trail (in the player's colour, bolts only), the layers, the core (its
// outline is the player's shadow shade, so a shot says whose it is even in a crowd).
// A layer kind is one of the LOOK_* constants of `core/projectiles` (1-12); each card names
// its own in `look_layer`, so a new card only touches this file for a new kind of effect.
// The body stays plain; the cards show as what it gives off (the owner, 2026-10-26: "the bolts
// could stay pretty plain, but then emit/sparkle with different added effects", and "the tail
// of bolts should also emit from added effects randomly"). Each kind is a particle style; a
// shot keeps a few particles alive, each born at a random point of its tail (of a rune's
// outline, of an orbit shot's beads), with a kind picked at random from the shot's kinds, so
// every card shows and many cards make a mix, not a crowd. Pierce and homing change the body
// instead (a longer core, a weave); pierce also streaks.
//
// Kind 0 is the old sprite path, still used by Feel's lone Sprite2D flashes: a neutral bone
// sprite whose Spark-coloured pixels take `core_override`'s colour (alpha above 0 turns it on).

uniform vec4 core_override = vec4(0.0);
// Multiplies the vertex colour of the sprite path: the tint and the fade of a lone Sprite2D.
uniform vec4 body_tint = vec4(1.0);
// Seconds of simulation, set by the projectile manager; everything animates from it, not TIME,
// so a run stepped by hand (the clip recorder) draws the same frames every time.
uniform float sim_time = 0.0;

// The quad is GRID x zoom pixels: the core in the middle, the tail and its particles behind.
const float GRID = 24.0;
// Particles a shot keeps in the air at most, and how many a shot with `n` emitting kinds uses:
// 4 + 2n, so one card is a trickle, many cards a richer mix, never a cloud.
const int MAX_PARTICLES = 12;

// docs/STYLE.md: the players' ramps (shadow, base, light) and the colours the layers use.
const vec3 P_SHADOW[4] = vec3[](vec3(0.114, 0.227, 0.420), vec3(0.478, 0.137, 0.278), vec3(0.122, 0.290, 0.227), vec3(0.290, 0.165, 0.420));
const vec3 P_BASE[4] = vec3[](vec3(0.231, 0.451, 0.788), vec3(0.851, 0.278, 0.478), vec3(0.247, 0.561, 0.310), vec3(0.541, 0.310, 0.769));
const vec3 P_LIGHT[4] = vec3[](vec3(0.498, 0.753, 0.941), vec3(0.961, 0.604, 0.722), vec3(0.561, 0.831, 0.416), vec3(0.788, 0.604, 0.941));
const vec3 FIRE_BASE = vec3(0.878, 0.349, 0.184);
const vec3 FIRE_LIGHT = vec3(1.0, 0.635, 0.235);
const vec3 ICE_LIGHT = vec3(0.769, 0.965, 0.949);
const vec3 SPARK_LIGHT = vec3(1.0, 0.953, 0.651);
const vec3 VOID_BASE = vec3(0.627, 0.188, 0.604);
const vec3 VOID_LIGHT = vec3(0.878, 0.541, 0.847);
const vec3 ARC_BASE = vec3(0.706, 0.910, 0.165);
const vec3 ARC_LIGHT = vec3(0.933, 1.0, 0.651);
const vec3 BONE_LIGHT = vec3(0.957, 0.945, 0.918);

// The layer kinds (LOOK_* in projectile_manager.gd).
const float L_EMBERS = 1.0;
const float L_FLECKS = 2.0;
const float L_GUSTS = 3.0;
const float L_PULL = 4.0;
const float L_SPARKS = 5.0;
const float L_MOTES = 6.0;
const float L_GLINTS = 7.0;
const float L_STREAKS = 8.0;
const float L_BURST = 9.0;
const float L_ORBITERS = 10.0;
const float L_WEAVE = 11.0;
const float L_GLITTER = 12.0;
const float KIND_COUNT = 12.0;

varying flat vec4 body;
varying flat vec3 core;
varying flat float kind;
varying flat float seed;
varying flat float player;
varying flat float zoom;
varying flat vec3 bits;
// The kinds that give off particles, in order, and how many there are.
varying flat vec4 emit0;
varying flat vec4 emit1;
varying flat vec4 emit2;
varying flat float emit_count;

bool bit_set(vec3 b, float look) {
	float bit = look - 1.0;
	float byte = bit < 8.0 ? b.x : (bit < 16.0 ? b.y : b.z);
	return mod(floor(byte / exp2(mod(bit, 8.0))), 2.0) > 0.5;
}

void vertex() {
	core = core_override.a > 0.0 ? core_override.rgb : INSTANCE_CUSTOM.rgb;
	kind = core_override.a > 0.0 ? 0.0 : floor((1.0 - INSTANCE_CUSTOM.a) * 16.0 + 0.5);
	seed = float(INSTANCE_ID % 61) * 1.618;
	body = COLOR * body_tint;
	float red = floor(COLOR.r * 255.0 + 0.5);
	player = mod(red, 4.0);
	zoom = max(floor(red / 4.0), 1.0);
	bits = floor(COLOR.gba * 255.0 + 0.5);
	float list[12];
	float n = 0.0;
	for (int k = 0; k < 12; k++) {
		list[k] = 0.0;
	}
	if (kind > 0.5) {
		for (float look = 1.0; look <= KIND_COUNT; look += 1.0) {
			if (look != L_WEAVE && bit_set(bits, look)) {
				list[int(n)] = look;
				n += 1.0;
			}
		}
	}
	emit0 = vec4(list[0], list[1], list[2], list[3]);
	emit1 = vec4(list[4], list[5], list[6], list[7]);
	emit2 = vec4(list[8], list[9], list[10], list[11]);
	emit_count = n;
}

float triangle(float x) {
	return abs(fract(x) * 2.0 - 1.0) * 2.0 - 1.0;
}

// The animation frame (0-3) at `rate` frames a second. Each shot starts on its own frame, so
// a volley does not blink together.
float frame_of(float rate) {
	return mod(floor(sim_time * rate + seed + 0.001), 4.0);
}

// A number in [0, 1) from three numbers and the shot's seed: the same on every machine.
float hash(float a, float b, float c) {
	return fract(sin(dot(vec3(a, b, c) + seed, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
}

bool has_layer(float look) {
	return bit_set(bits, look);
}

float emitter(int i) {
	return i < 4 ? emit0[i] : (i < 8 ? emit1[i - 4] : emit2[i - 8]);
}

// True when the pixel centred at `q` is the pixel of the point `at` (both in pixels).
bool on(vec2 q, vec2 at) {
	return all(equal(floor(q), floor(at)));
}

// Particle `i` of kind `look`, born at `from` (pixels from the core), `a` of the way through
// its life (0-1), in cycle `cyc`: its colour at pixel `q`, or alpha 0. `z` is the zoom.
vec4 particle(float look, vec2 from, float a, float i, float cyc, vec2 q, float z) {
	float h = hash(i, cyc, 5.0);
	if (look == L_EMBERS) {
		// Fire: an ember that drifts back and off the line, and dims.
		vec2 at = from + vec2(-3.0 * a, ((h - 0.5) * 3.0 - 1.5) * a) * z;
		if (a < 0.85 && on(q, at)) {
			return vec4(a < 0.4 ? FIRE_LIGHT : FIRE_BASE, 1.0);
		}
	} else if (look == L_FLECKS) {
		// Frost: a fleck left hanging behind, twinkling.
		vec2 at = from + vec2(-5.0 * a, 0.0) * z;
		if (a < 0.9 && mod(floor(sim_time * 12.0 + i), 3.0) > 0.5 && on(q, at)) {
			return vec4(ICE_LIGHT, 1.0);
		}
	} else if (look == L_GUSTS) {
		// Storm: a short streak blown back fast.
		vec2 at = floor(from + vec2(-9.0 * a, 0.0) * z);
		vec2 d = floor(q) - at;
		if (a < 0.6 && d.y == 0.0 && d.x >= 0.0 && d.x <= 1.0 + z) {
			return vec4(SPARK_LIGHT, 1.0);
		}
	} else if (look == L_PULL) {
		// Void: a pixel drawn in from round about, to the tail.
		float ang = h * 6.2832;
		vec2 at = mix(from + vec2(cos(ang), sin(ang)) * 5.0 * z, from, a);
		if (on(q, at)) {
			return vec4(a < 0.5 ? VOID_BASE : VOID_LIGHT, 1.0);
		}
	} else if (look == L_SPARKS) {
		// Lightning: a quick spark that jumps about each frame.
		float f = floor(sim_time * 20.0);
		vec2 at = from + (vec2(hash(i, f, 1.0), hash(i, f, 2.0)) - 0.5) * 4.0 * z;
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
	}
	return vec4(0.0);
}

// Rune: a diamond outline about its hit size that swells and settles while it waits, with a
// sparse dotted fill so the floor shows through and a bright heart. `reach` is in pixels.
// Returns the tier (0 none, 1 the player's edge, 2 the core colour, 3 its light).
float rune(vec2 q, float reach, float swell) {
	float d = abs(q.x) + abs(q.y);
	if (d > reach) {
		return 0.0;
	}
	if (d > reach - 1.5) {
		return 1.0;
	}
	if (d > reach - 2.5 || d < 2.5) {
		return d < 1.5 && swell > 1.5 ? 3.0 : 2.0;
	}
	return mod(floor(q.x), 3.0) < 0.5 && mod(floor(q.y), 3.0) < 0.5 ? 2.0 : 0.0;
}

// Orbit shot: two beads on opposite sides of a middle (`off` from it), about 5 pixels across
// at zoom 1.
float beads(vec2 q, vec2 off, float z) {
	float near = min(length(q - off), length(q + off));
	if (near > 1.6 * z + 0.9) {
		return 0.0;
	}
	if (near > 1.6 * z) {
		return 1.0;
	}
	return near < 0.8 * z ? 3.0 : 2.0;
}

vec4 procedural(vec2 uv) {
	// The screen pixel, with +x along the flight, the centre of the quad at 0, pixel centres at .5.
	float size = GRID * zoom;
	vec2 q = floor(uv * size) - size * 0.5 + 0.5;
	int pi = int(player);
	vec3 light = mix(core, vec3(1.0), 0.55);
	vec4 colour = vec4(0.0);
	vec2 c = vec2(0.0);
	bool bolt = kind < 1.5;
	if (bolt && has_layer(L_WEAVE)) {
		// Homing: the shot weaves a pixel either side.
		c.y = triangle(sim_time * 3.0 + seed * 0.25) > 0.0 ? 1.0 : 0.0;
	}
	// The body's own numbers: a rune's reach and swell, an orbit shot's bead offset.
	float swell = 0.0;
	float reach = 0.0;
	vec2 off = vec2(0.0);
	if (kind > 1.5 && kind < 2.5) {
		float f = frame_of(3.0);
		swell = f < 0.5 ? 0.0 : (f < 1.5 ? 1.0 : (f < 2.5 ? 2.0 : 1.0));
		reach = size * 0.5 * (0.30 + 0.03 * swell);
	} else if (kind > 2.5) {
		float f = mod(floor(sim_time * 8.0 + seed), 8.0);
		off = vec2(cos(f * 0.7854), sin(f * 0.7854)) * (3.5 + 0.7 * triangle(f * 0.25)) * zoom;
	}
	// The trail: two pixels wide near the shot, one further back, in the player's colour.
	if (bolt) {
		float t = (c.x - 2.0 * zoom - q.x) / zoom;
		float dy = q.y - c.y;
		if (t > 0.0 && t < 7.0) {
			bool near = t < 3.5 && abs(dy) < zoom;
			bool far = t >= 3.5 && dy > 0.0 && dy < max(zoom * 0.5, 1.0) && (t < 6.0 || mod(floor(sim_time * 10.0 + seed), 2.0) < 0.5);
			if (near || far) {
				colour = vec4(near ? P_LIGHT[pi] : P_BASE[pi], 1.0);
			}
		}
	}
	// What the cards give off: particles born at random points of the tail (or the outline).
	if (emit_count > 0.5) {
		int count = int(min(4.0 + 2.0 * emit_count, float(MAX_PARTICLES)));
		for (int n = 0; n < MAX_PARTICLES; n++) {
			if (n >= count) {
				break;
			}
			float i = float(n);
			float t = sim_time * (2.5 + 1.5 * hash(i, 0.0, 3.0)) + hash(i, 0.0, 4.0);
			float cyc = floor(t);
			float look = emitter(int(min(floor(hash(i, cyc, 7.0) * emit_count), emit_count - 1.0)));
			vec2 from;
			if (bolt) {
				from = c + vec2(-(1.0 + 6.0 * hash(i, cyc, 8.0)), (hash(i, cyc, 9.0) - 0.5) * 2.0) * zoom;
			} else if (kind < 2.5) {
				float ang = hash(i, cyc, 8.0) * 6.2832;
				vec2 dir = vec2(cos(ang), sin(ang));
				from = dir * reach / (abs(dir.x) + abs(dir.y));
			} else {
				from = (hash(i, cyc, 8.0) < 0.5 ? off : -off) + (vec2(hash(i, cyc, 9.0), hash(i, cyc, 10.0)) - 0.5) * 2.0 * zoom;
			}
			vec4 p = particle(look, from, fract(t), i, cyc, q, zoom);
			if (p.a > 0.0) {
				colour = p;
			}
		}
	}
	float tier = 0.0;
	if (bolt) {
		vec2 d = q - c;
		if (has_layer(L_STREAKS)) {
			d.x *= 0.6;
		}
		float r = length(d);
		tier = r < 0.8 * zoom ? 3.0 : (r < 1.6 * zoom ? 2.0 : (r < 1.6 * zoom + 0.9 ? 1.0 : 0.0));
	} else if (kind < 2.5) {
		tier = rune(q, reach, swell);
	} else {
		tier = beads(q, off, zoom);
	}
	if (tier > 0.5) {
		vec3 rgb = tier < 1.5 ? P_SHADOW[pi] : (tier < 2.5 ? core : light);
		colour = vec4(rgb, 1.0);
	}
	return colour;
}

void fragment() {
	if (kind > 0.5) {
		COLOR = procedural(UV);
	} else {
		vec4 t = texture(TEXTURE, UV);
		vec3 rgb = t.rgb * body.rgb;
		float warm = smoothstep(0.1, 0.25, t.r - t.b);
		float lum = dot(t.rgb, vec3(0.3, 0.59, 0.11));
		float shade = clamp((lum - 0.5) / 0.45, 0.0, 1.0);
		vec3 lit = mix(core * 0.55, mix(core, vec3(1.0), 0.55), shade);
		COLOR = vec4(mix(rgb, lit, warm), t.a * body.a);
	}
}
