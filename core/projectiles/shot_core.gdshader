// SPDX-License-Identifier: GPL-3.0-or-later
shader_type canvas_item;
render_mode blend_premul_alpha;

// The look of a player's shot (staffs B6a, docs/milestones/M2-staffs.md, "The look of a shot"),
// built here on a pixel grid, so a shot needs no art and no nodes.
//
// MultiMesh instances (the projectile manager) carry:
//   custom data rgb  the core colour (the first infusion's tint; white for none)
//   custom data a    the body kind and a code as 1 - (kind + code) / 16: kind 1 a bolt, 2 a
//                    rune, 3 an orbit shot, 4-8 an effect Feel draws (K_* below), 0 the texture
//                    (below); the code (0-0.45) is a bolt's or orbit shot's bend (how its path
//                    curves, so its tail follows it; BEND_* below), how much of a new rune is
//                    traced, or how far through its life an effect is (TRACE_* below)
//   colour r         player + zoom x 4, as n / 255: the shapes grow with the zoom while every
//                    line stays one pixel, so a bigger shot is bigger, never chunkier
//   colour g, b, a   the look: one bit per layer kind (kind 1 is bit 0 of green, kind 9 bit 0
//                    of blue, kind 17 bit 0 of alpha), every kind the shot's cards bring
// A bolt or orbit shot's quad is LENGTH x GRID pixels times the zoom, the shot FRONT pixels from
// its front edge and its tail behind; a rune's is GRID x GRID round its centre.
//
// The look (the owner, 2026-10-27): a small white-hot core, a long tail of pixels that cool from
// hot to dark and fray at the end, and a soft glow in the shot's colour round both. The core's
// tint names its palette material (docs/STYLE.md), whose three shades make the ramp; a plain shot
// uses its player's. In infused shots a quarter of the tail's pixels are the player's colour, so
// a shot still says whose it is in a crowd. Each card also shows as what the shot gives off (the
// owner, 2026-10-26: "the bolts could stay pretty plain, but then emit/sparkle with different
// added effects"): every look kind is a particle style; a shot keeps a few particles alive, each
// born at a random point of its tail (of a rune's outline), with a kind picked at random from
// the shot's kinds, so every card shows and many cards make a mix, not a crowd. A few kinds also
// shape the body: pierce lengthens the core, homing weaves it, frost draws a longer tail,
// lightning a jagged one, storm a swaying one, void a dark heart.
//
// Blending is premultiplied: a pixel of the shot is opaque (alpha 1), the glow round it is
// light added to what is below (alpha 0), so one pass draws both.
//
// Kind 0 is the old sprite path, still used by Feel's lone Sprite2D flashes: a neutral bone
// sprite whose Spark-coloured pixels take `core_override`'s colour (alpha above 0 turns it on).

uniform vec4 core_override = vec4(0.0);
// Multiplies the vertex colour of the sprite path: the tint and the fade of a lone Sprite2D.
uniform vec4 body_tint = vec4(1.0);
// Seconds of simulation, set by the projectile manager; everything animates from it, not TIME,
// so a run stepped by hand (the clip recorder) draws the same frames every time.
uniform float sim_time = 0.0;
// The spark pool's share (set by the projectile manager, 1.0 is everything): the fraction of
// every shot's particles and of every tail that is drawn this frame. Tails go first.
uniform float particle_share = 1.0;
uniform float trail_share = 1.0;
// How bright the glow is (1.0 the look; 0.0 none).
uniform float glow_strength = 1.0;

// The quad: GRID pixels across (and along, for a rune); LENGTH along for a bolt or orbit shot,
// the shot FRONT pixels from the front. LOOK_GRID, LOOK_LENGTH in projectile_manager.gd.
const float GRID = 24.0;
const float LENGTH = 72.0;
const float FRONT = 12.0;
// The tail of a bolt, in pixels at zoom 1 (frost's is longer, lightning's shorter). On a bend it
// covers at most TAIL_TURN radians of the curve, so it stays inside the quad.
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
// A rune's trace and an effect's age: TRACE_FROM + TRACE_SPAN x the fraction (RUNE_TRACE in
// projectile_manager.gd); a rune's code 0 is a whole rune.
const float TRACE_FROM = 0.02;
const float TRACE_SPAN = 0.42;
// The effects Feel draws with this shader (KIND_* in gameplay/feel/feel.gd), in a square quad
// GRID x zoom across, +x along their aim; all in the ramp and look of the shot they come from.
//   K_BURST       where a shot lands: a white-hot cross that shrinks, sparks thrown back
//                 against the flight that cool as they fly, and the shot's card particles
//   K_RING_OUT    a ring that flashes out (a nova's cast)
//   K_RING_IN     a ring that gathers in (a rune's or orbit's cast)
//   K_RUNE_BURST  a rune going off: a dotted flash over the diamond, a diamond ring widening
//                 to twice its size, sparks all round
//   K_CAST        the staff tip on a cast: a small cross and a few sparks along the aim
const float K_BURST = 4.0;
const float K_RING_OUT = 5.0;
const float K_RING_IN = 6.0;
const float K_RUNE_BURST = 7.0;
const float K_CAST = 8.0;
// A rune's reach at its rest (the 14 px of rune.tres, as `rune()` draws it at zoom 4).
const float RUNE_REACH = 14.4;
// Particles a shot keeps in the air at most, and how many a shot with `n` emitting kinds uses:
// 4 + 2n, so one card is a trickle, many cards a richer mix, never a cloud.
const int MAX_PARTICLES = 12;

// docs/STYLE.md: the players' ramps (shadow, base, light) and the colours the layers use.
const vec3 P_SHADOW[4] = vec3[](vec3(0.114, 0.227, 0.420), vec3(0.478, 0.137, 0.278), vec3(0.122, 0.290, 0.227), vec3(0.290, 0.165, 0.420));
const vec3 P_BASE[4] = vec3[](vec3(0.231, 0.451, 0.788), vec3(0.851, 0.278, 0.478), vec3(0.247, 0.561, 0.310), vec3(0.541, 0.310, 0.769));
const vec3 P_LIGHT[4] = vec3[](vec3(0.498, 0.753, 0.941), vec3(0.961, 0.604, 0.722), vec3(0.561, 0.831, 0.416), vec3(0.788, 0.604, 0.941));
const vec3 OUTLINE = vec3(0.078, 0.071, 0.122);
const vec3 FIRE_BASE = vec3(0.878, 0.349, 0.184);
const vec3 FIRE_LIGHT = vec3(1.0, 0.635, 0.235);
const vec3 ICE_LIGHT = vec3(0.769, 0.965, 0.949);
const vec3 SPARK_LIGHT = vec3(1.0, 0.953, 0.651);
const vec3 VOID_BASE = vec3(0.627, 0.188, 0.604);
const vec3 VOID_LIGHT = vec3(0.878, 0.541, 0.847);
const vec3 ARC_BASE = vec3(0.706, 0.910, 0.165);
const vec3 ARC_LIGHT = vec3(0.933, 1.0, 0.651);
const vec3 BONE_LIGHT = vec3(0.957, 0.945, 0.918);
// The materials a core's tint can name, three shades each (shadow, base, light): Fire, Spark,
// Ice, Void, Arc, Bone.
const int MATERIALS = 6;
const vec3 SHADES[18] = vec3[](
	vec3(0.561, 0.176, 0.165), vec3(0.878, 0.349, 0.184), vec3(1.0, 0.635, 0.235),
	vec3(0.722, 0.502, 0.122), vec3(0.949, 0.761, 0.188), vec3(1.0, 0.953, 0.651),
	vec3(0.122, 0.439, 0.502), vec3(0.310, 0.839, 0.863), vec3(0.769, 0.965, 0.949),
	vec3(0.290, 0.078, 0.314), vec3(0.627, 0.188, 0.604), vec3(0.878, 0.541, 0.847),
	vec3(0.247, 0.420, 0.063), vec3(0.706, 0.910, 0.165), vec3(0.933, 1.0, 0.651),
	vec3(0.639, 0.624, 0.722), vec3(0.831, 0.816, 0.878), vec3(0.957, 0.945, 0.918));

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
varying flat float bend;
// A rune's trace or an effect's age, 0 to 1 (1 for everything else).
varying flat float age;
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
	float coded = core_override.a > 0.0 ? 0.0 : (1.0 - INSTANCE_CUSTOM.a) * 16.0;
	kind = floor(coded + 0.5);
	float b = coded - kind;
	bend = 0.0;
	age = 1.0;
	if ((abs(kind - 2.0) < 0.5 || kind > 3.5) && b > 0.01) {
		age = clamp((b - TRACE_FROM) / TRACE_SPAN, 0.0, 1.0);
	} else if (kind < 3.5 && b > 0.01) {
		bend = (b - BEND_ZERO) / BEND_SPAN / BEND_RADIUS * BEND_SIDE;
		if (abs(bend) < BEND_MIN) {
			bend = 0.0;
		}
	}
	seed = float(INSTANCE_ID % 61) * 1.618;
	body = COLOR * body_tint;
	float red = floor(COLOR.r * 255.0 + 0.5);
	player = mod(red, 4.0);
	zoom = max(floor(red / 4.0), 1.0);
	bits = floor(COLOR.gba * 255.0 + 0.5);
	int pi = int(player);
	plain = all(greaterThan(core, vec3(0.99))) ? 1.0 : 0.0;
	if (plain > 0.5) {
		hot = BONE_LIGHT;
		hi = P_LIGHT[pi];
		mid = P_BASE[pi];
		lo = P_SHADOW[pi];
	} else {
		int best = 0;
		float near = 9.0;
		for (int i = 0; i < MATERIALS * 3; i++) {
			float d = distance(core, SHADES[i]);
			if (d < near) {
				near = d;
				best = i / 3;
			}
		}
		lo = SHADES[best * 3];
		mid = SHADES[best * 3 + 1];
		hi = SHADES[best * 3 + 2];
		hot = mix(hi, vec3(1.0), 0.5);
	}
	glow = mix(mid, hi, 0.35);
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

// 1 at the middle, 0 from `reach` on, eased: the shape of every glow.
float falloff(float x, float reach) {
	float k = max(1.0 - x / reach, 0.0);
	return k * k;
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
	}
	return vec4(0.0);
}

// Rune: a one-pixel diamond about its hit size with bright corners, a dotted ring inside and a
// glyph of four dots turning round a bright heart, swelling and settling while it waits. `reach`
// is in pixels. Returns the tier (0 none, 1 base, 2 light, 3 white-hot, 4 void's dark heart).
float rune(vec2 q, float reach, float swell) {
	float d = abs(q.x) + abs(q.y);
	if (d > reach) {
		return 0.0;
	}
	if (d > reach - 1.0) {
		// While it is new, the outline traces itself round from the top, clockwise.
		if (fract(atan(q.y, q.x) / 6.2832 + 1.25) > age) {
			return 0.0;
		}
		return abs(q.x) < 1.0 || abs(q.y) < 1.0 ? 3.0 : 2.0;
	}
	if (age < 1.0) {
		return 0.0;
	}
	if (d > reach - 5.0 && d <= reach - 4.0) {
		return mod(floor(q.x) + floor(q.y), 2.0) < 0.5 && mod(floor(sim_time * 4.0 + seed) + floor(q.x), 4.0) < 2.0 ? 1.0 : 0.0;
	}
	float ang = sim_time * 2.2 + seed;
	for (int k = 0; k < 4; k++) {
		float a = ang + float(k) * 1.5708;
		if (on(q, vec2(cos(a), sin(a)) * 4.0)) {
			return 2.0;
		}
	}
	if (d < 1.0) {
		return has_layer(L_PULL) ? 4.0 : (swell > 0.5 ? 3.0 : 2.0);
	}
	return 0.0;
}

vec4 procedural(vec2 uv) {
	// The screen pixel, with +x along the flight, the core at 0, pixel centres on whole numbers.
	bool runic = kind > 1.5 && kind < 2.5;
	vec2 size = runic ? vec2(GRID) * zoom : vec2(LENGTH, GRID) * zoom;
	vec2 q = floor(uv * size) + 0.5 - (runic ? size * 0.5 : vec2(size.x - FRONT * zoom, size.y * 0.5));
	int pi = int(player);
	vec4 colour = vec4(0.0);
	float lit = 0.0;
	vec2 c = vec2(0.5);
	if (!runic && has_layer(L_WEAVE)) {
		// Homing: the shot weaves a pixel either side.
		c.y += triangle(sim_time * 3.0 + seed * 0.25) > 0.0 ? 1.0 : 0.0;
	}
	vec2 d = q - c;
	// A rune's reach and swell.
	float swell = 0.0;
	float reach = 0.0;
	if (runic) {
		float f = frame_of(3.0);
		swell = f < 0.5 ? 0.0 : (f < 1.5 ? 1.0 : (f < 2.5 ? 2.0 : 1.0));
		reach = size.x * 0.5 * (0.30 + 0.03 * swell);
	}
	// The tail: one pixel a column (zoom pixels for a bigger shot), cooling from white-hot to
	// shadow and fraying towards its end, re-rolled 24 times a second.
	float tail = TAIL * zoom * trail_share * (has_layer(L_FLECKS) ? 1.2 : 1.0) * (has_layer(L_SPARKS) ? 0.7 : 1.0);
	if (bend != 0.0) {
		tail = min(tail, TAIL_TURN / abs(bend));
	}
	vec2 tn = runic ? vec2(-1.0) : tail_coords(d);
	if (!runic && tn.x > 1.5 && tn.x < tail) {
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
	// What the cards give off: particles born at random points of the tail (or the outline).
	if (emit_count > 0.5) {
		// The same rule as `particles_of` in projectile_manager.gd; keep the two equal.
		float asked = min(4.0 + 2.0 * emit_count, float(MAX_PARTICLES));
		// Each shot rounds its share by its own seed, so the pool's total stays near the share.
		int count = int(floor(asked * particle_share + fract(seed)));
		for (int n = 0; n < MAX_PARTICLES; n++) {
			if (n >= count) {
				break;
			}
			float i = float(n);
			float t = sim_time * (2.5 + 1.5 * hash(i, 0.0, 3.0)) + hash(i, 0.0, 4.0);
			float cyc = floor(t);
			float look = emitter(int(min(floor(hash(i, cyc, 7.0) * emit_count), emit_count - 1.0)));
			vec2 from;
			if (!runic) {
				from = c + tail_point((1.0 + 0.5 * TAIL * hash(i, cyc, 8.0)) * zoom) + vec2(0.0, (hash(i, cyc, 9.0) - 0.5) * 2.0 * zoom);
			} else {
				float ang = hash(i, cyc, 8.0) * 6.2832;
				vec2 dir = vec2(cos(ang), sin(ang));
				from = dir * reach / (abs(dir.x) + abs(dir.y));
			}
			vec4 p = particle(look, from, fract(t), i, cyc, q, zoom);
			if (p.a > 0.0) {
				colour = p;
			}
		}
	}
	// The body: a white-hot heart in a rim, a 3-pixel cross at zoom 1 that grows a pixel each
	// side a zoom, or the rune.
	float tier = 0.0;
	if (!runic) {
		vec2 dc = d;
		if (has_layer(L_STREAKS)) {
			dc.x *= 0.6;
		}
		float m = abs(dc.x) + abs(dc.y);
		tier = m < 0.5 * zoom ? (has_layer(L_PULL) ? 4.0 : 3.0) : (m < zoom + 0.5 ? 2.0 : 0.0);
	} else {
		tier = rune(q, reach, swell);
	}
	if (tier > 0.5) {
		vec3 rgb = tier < 1.5 ? mid : (tier < 2.5 ? hi : (tier < 3.5 ? hot : OUTLINE));
		colour = vec4(rgb, 1.0);
	}
	if (colour.a > 0.0) {
		return colour;
	}
	// The glow: light added round the core and along the tail (round a rune's outline).
	if (runic) {
		float ring = abs(abs(q.x) + abs(q.y) - reach);
		lit = (0.35 * (0.7 + 0.15 * swell) * falloff(ring, 6.0) + 0.5 * falloff(length(q), 8.0)) * age;
	} else {
		float r = length(d);
		lit = 0.8 * falloff(r, 4.0 * zoom) + 0.35 * falloff(r, 10.0 * zoom);
		if (tn.x > 0.0 && tn.x < tail) {
			float u = tn.x / tail;
			lit += 0.4 * (1.0 - u) * (1.0 - u) * falloff(abs(tn.y), 5.0 * zoom);
		}
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

// The ramp at `u` (0 white-hot, 1 shadow): what cools as it ages.
vec3 ramp(float u) {
	return u < 0.15 ? hot : (u < 0.4 ? hi : (u < 0.7 ? mid : lo));
}

vec4 effect(vec2 uv) {
	vec2 size = vec2(GRID) * zoom;
	vec2 d = floor(uv * size) + 0.5 - size * 0.5 - vec2(0.5);
	float a = age;
	float r = length(d);
	float ease = 1.0 - (1.0 - a) * (1.0 - a);
	vec4 colour = vec4(0.0);
	float lit = 0.0;
	if (kind == K_BURST || kind == K_CAST) {
		bool cast = kind == K_CAST;
		// The flash: a white-hot cross that shrinks.
		float arm = round((cast ? 1.5 : 2.0) * zoom * (1.0 - a * 2.5));
		if (arm >= 0.0 && ((d.x == 0.0 && abs(d.y) <= arm) || (d.y == 0.0 && abs(d.x) <= arm))) {
			colour = vec4(r < 0.5 ? hot : hi, 1.0);
		}
		// Sparks thrown back against the flight (along the aim from a staff), cooling as they fly.
		int sparks = cast ? 4 : 8;
		for (int n = 0; n < 8; n++) {
			if (n >= sparks || colour.a > 0.0) {
				break;
			}
			float i = float(n);
			float life = 0.5 + 0.5 * hash(i, 1.0, 31.0);
			if (a > life) {
				continue;
			}
			float ang = (cast ? 0.0 : 3.1416) + (hash(i, 2.0, 31.0) - 0.5) * (cast ? 1.0 : 2.8);
			float reach = (1.5 + (cast ? 6.0 : 10.0) * (0.6 + 0.4 * hash(i, 3.0, 31.0)) * ease) * zoom;
			if (on(d + 0.5, vec2(cos(ang), sin(ang)) * reach + 0.5)) {
				colour = vec4(ramp(a / life), 1.0);
			}
		}
		lit = (1.0 - a) * (1.0 - a) * (0.9 * falloff(r, 4.0 * zoom) + 0.4 * falloff(r, 10.0 * zoom));
	} else if (kind == K_RING_OUT || kind == K_RING_IN) {
		// A ring that flashes out or gathers in, fraying as it goes.
		float big = 10.0 * zoom, small = 2.0 * zoom;
		float radius = kind == K_RING_OUT ? mix(small, big, ease) : mix(big, small, ease);
		float bucket = floor(atan(d.y, d.x) * radius / 2.0);
		if (abs(r - radius) < 0.5 && hash(bucket, floor(a * 8.0), 32.0) > a * 0.7) {
			colour = vec4(ramp(a), 1.0);
		}
		lit = 0.5 * (1.0 - a) * falloff(abs(r - radius), 3.0 * zoom);
	} else if (kind == K_RUNE_BURST) {
		float m = abs(d.x) + abs(d.y);
		// A dotted white-hot flash over the diamond, then a diamond ring that widens and frays.
		if (a < 0.2 && m <= RUNE_REACH && mod(d.x + d.y, 2.0) == 0.0) {
			colour = vec4(a < 0.1 ? hot : hi, 1.0);
		}
		float wide = mix(RUNE_REACH, RUNE_REACH * 2.2, ease);
		float bucket = floor(atan(d.y, d.x) * wide / 2.0);
		if (abs(m - wide) < 0.5 && hash(bucket, floor(a * 8.0), 33.0) > a * 0.7) {
			colour = vec4(ramp(a), 1.0);
		}
		for (int n = 0; n < 16; n++) {
			if (colour.a > 0.0) {
				break;
			}
			float i = float(n);
			float ang = i * 0.3927 + (hash(i, 4.0, 31.0) - 0.5) * 0.4;
			float reach = (4.0 + 26.0 * (0.6 + 0.4 * hash(i, 5.0, 31.0)) * ease);
			if (a < 0.8 && on(d + 0.5, vec2(cos(ang), sin(ang)) * reach + 0.5)) {
				colour = vec4(ramp(a), 1.0);
			}
		}
		lit = (1.0 - a) * (0.5 * falloff(abs(m - wide), 6.0) + (a < 0.25 ? 0.8 : 0.0) * falloff(m, RUNE_REACH));
	}
	// The shot's cards: its particles, set off from round the middle at the start.
	if (colour.a == 0.0 && emit_count > 0.5 && kind != K_CAST) {
		float spread = kind == K_RUNE_BURST ? RUNE_REACH : 2.0 * zoom;
		float count = min(4.0 + 2.0 * emit_count, float(MAX_PARTICLES));
		for (int n = 0; n < MAX_PARTICLES; n++) {
			if (float(n) >= count) {
				break;
			}
			float i = float(n);
			float look = emitter(int(min(floor(hash(i, 6.0, 31.0) * emit_count), emit_count - 1.0)));
			float ang = hash(i, 7.0, 31.0) * 6.2832;
			vec2 from = vec2(cos(ang), sin(ang)) * spread * hash(i, 8.0, 31.0);
			float pa = (a - 0.3 * hash(i, 9.0, 31.0)) / 0.7;
			if (pa > 0.0 && pa < 1.0) {
				vec4 p = particle(look, from, pa, i, 0.0, d, zoom);
				if (p.a > 0.0) {
					colour = p;
				}
			}
		}
	}
	if (colour.a > 0.0) {
		return colour;
	}
	if (has_layer(L_PULL)) {
		lit *= 0.6;
	}
	return vec4(glow * lit * glow_strength, 0.0);
}

void fragment() {
	if (kind > 3.5) {
		COLOR = effect(UV);
	} else if (kind > 0.5) {
		COLOR = procedural(UV);
	} else {
		vec4 t = texture(TEXTURE, UV);
		vec3 rgb = t.rgb * body.rgb;
		float warm = smoothstep(0.1, 0.25, t.r - t.b);
		float lum = dot(t.rgb, vec3(0.3, 0.59, 0.11));
		float shade = clamp((lum - 0.5) / 0.45, 0.0, 1.0);
		vec3 lit = mix(core * 0.55, mix(core, vec3(1.0), 0.55), shade);
		float alpha = t.a * body.a;
		// Premultiplied, as the blend mode wants.
		COLOR = vec4(mix(rgb, lit, warm) * alpha, alpha);
	}
}
