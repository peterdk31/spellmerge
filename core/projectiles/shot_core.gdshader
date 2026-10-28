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
//                    of blue, kind 17 bit 0 of alpha), every kind the shot's cards bring;
//                    kind 23 (ENEMY_RAMP) is a flag, not a particle: an enemy's spell, drawn
//                    in the enemy ramp wherever a player's colour would show (staffs F2)
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
// The sprite path's dissolve (Feel's death, a wizard's dash afterimages): 0 whole, 1 gone. Its
// pixels turn `dissolve_color` (white-hot unless set) and fall out one by one.
uniform float dissolve = 0.0;
uniform vec4 dissolve_color = vec4(0.957, 0.945, 0.918, 1.0);
// The sprite path's glow: light added round the sprite's own pixels (a combo mark, an
// afterimage), as bright as this; the sprite needs a few empty pixels round it to hold it.
uniform float sprite_glow = 0.0;
// Beam mode (Feel's beams; the instance data above is not used): 1 a Line2D stretched along its
// path (UV.x 0-1 along `beam_length` pixels, UV.y across `beam_width`), 2 a Sprite2D whose region
// is the beam (UV in texture pixels, 32 across). Its core colour is `core_override`, its player
// and look these (`beam_player` -1, NO_PLAYER, is an enemy's beam). `beam_fade` (1 to 0) dissolves it into pixels as it ends; `beam_swell` (1 at
// rest) widens its rim and glow when it flares and narrows them as it thins; `beam_glow` is how
// strongly it glows.
uniform int beam_mode = 0;
uniform float beam_length = 0.0;
uniform float beam_width = 16.0;
uniform int beam_player = 0;
uniform int beam_look = 0;
uniform float beam_fade = 1.0;
uniform float beam_swell = 1.0;
uniform float beam_glow = 1.0;
// Beam mode 3 is an enemy's telegraph (staffs F8b; a Sprite2D whose region is the lane, as mode
// 2): where its next cast goes, `beam_length` pixels along the aim and `telegraph_lane` pixels
// either side of the middle. `telegraph_progress` runs 0 to 1 over the windup: the dashes march
// toward the tip, the arrowhead grows, the lane brightens, and the last part is white-hot.
uniform float telegraph_progress = 0.0;
uniform float telegraph_lane = 6.0;

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
//   K_DASH        a wizard's dash, from where it started (the effect's place) along its aim for
//                 zoom x 4 pixels: speed streaks behind the head, dust where it left, a ring where
//                 it lands, the dash's card particles along the way (lightning: an arc from end
//                 to end); its quad is that long plus DASH_MARGIN each end, DASH_ACROSS across
//   K_BEAM        a beam (beam mode above): a white-hot one-pixel core, a rim that breathes
//                 along it, motes running down it, flares at both ends and its card particles
//   K_SPRAY       a hit on a character: sparks thrown on along the hit's way, cooling
//   K_PUFF        sparks all round and a dotted white-hot puff (a kill, a reaction, a hit
//                 with no way)
//   K_CHIPS       stone chips knocked back off a wall, falling; stone does not glow
//   K_ARC         lightning jumping from the effect's place along its aim for zoom x 4 pixels
//                 (a discharge): a jagged line re-rolled 30 times a second; its quad is that long
//                 plus ARC_MARGIN each end, ARC_ACROSS across
//   K_STATUS      a status on a character, kept while it lasts and moved with it: its look's
//                 particles round it and a pulsing glow
// An enemy's shot, beam or effect has the ENEMY_RAMP bit (kind 23): the enemy ramp (Blight ochre)
// takes the player's place.
// An effect whose look has the EXACT bit (kind 24) takes its colour as it is, the ramp made from
// it (a reaction's own colour), instead of the palette material the colour is nearest.
const float K_BURST = 4.0;
const float K_RING_OUT = 5.0;
const float K_RING_IN = 6.0;
const float K_RUNE_BURST = 7.0;
const float K_CAST = 8.0;
const float K_DASH = 9.0;
const float K_BEAM = 10.0;
const float K_SPRAY = 11.0;
const float K_PUFF = 12.0;
const float K_CHIPS = 13.0;
const float K_ARC = 14.0;
const float K_STATUS = 15.0;
const float ENEMY_RAMP = 23.0;
const float EXACT = 24.0;
const float ARC_MARGIN = 4.0;
const float ARC_ACROSS = 16.0;
const vec3 STONE_SHADOW = vec3(0.169, 0.157, 0.251);
const vec3 STONE_BASE = vec3(0.290, 0.275, 0.388);
const vec3 STONE_LIGHT = vec3(0.478, 0.463, 0.580);
const float DASH_MARGIN = 12.0;
const float DASH_ACROSS = 32.0;
// A rune's reach at its rest (the 14 px of rune.tres, as `rune()` draws it at zoom 4).
const float RUNE_REACH = 14.4;
// Particles a shot keeps in the air at most, and how many a shot with `n` emitting kinds uses:
// 4 + 2n, so one card is a trickle, many cards a richer mix, never a cloud.
const int MAX_PARTICLES = 12;

// docs/STYLE.md: the players' ramps (shadow, base, light), then the enemy ramp (Blight ochre,
// ENEMY_PLAYER), and the colours the layers use.
const vec3 P_SHADOW[5] = vec3[](vec3(0.114, 0.227, 0.420), vec3(0.478, 0.137, 0.278), vec3(0.122, 0.290, 0.227), vec3(0.290, 0.165, 0.420), vec3(0.302, 0.247, 0.071));
const vec3 P_BASE[5] = vec3[](vec3(0.231, 0.451, 0.788), vec3(0.851, 0.278, 0.478), vec3(0.247, 0.561, 0.310), vec3(0.541, 0.310, 0.769), vec3(0.651, 0.541, 0.165));
const vec3 P_LIGHT[5] = vec3[](vec3(0.498, 0.753, 0.941), vec3(0.961, 0.604, 0.722), vec3(0.561, 0.831, 0.416), vec3(0.788, 0.604, 0.941), vec3(0.890, 0.812, 0.420));
const float ENEMY_PLAYER = 4.0;
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
	bend = 0.0;
	age = 1.0;
	body = COLOR * body_tint;
	if (beam_mode > 0) {
		core = core_override.rgb;
		kind = K_BEAM;
		seed = 0.0;
		player = beam_player < 0 ? ENEMY_PLAYER : float(min(beam_player, 3));
		zoom = 1.0;
		bits = vec3(float(beam_look & 255), float((beam_look >> 8) & 255), float((beam_look >> 16) & 255));
	} else {
		core = core_override.a > 0.0 ? core_override.rgb : INSTANCE_CUSTOM.rgb;
		float coded = core_override.a > 0.0 ? 0.0 : (1.0 - INSTANCE_CUSTOM.a) * 16.0;
		kind = floor(coded + 0.5);
		float b = coded - kind;
		if ((abs(kind - 2.0) < 0.5 || kind > 3.5) && b > 0.01) {
			age = clamp((b - TRACE_FROM) / TRACE_SPAN, 0.0, 1.0);
		} else if (kind < 3.5 && b > 0.01) {
			bend = (b - BEND_ZERO) / BEND_SPAN / BEND_RADIUS * BEND_SIDE;
			if (abs(bend) < BEND_MIN) {
				bend = 0.0;
			}
		}
		seed = float(INSTANCE_ID % 61) * 1.618;
		float red = floor(COLOR.r * 255.0 + 0.5);
		player = mod(red, 4.0);
		zoom = max(floor(red / 4.0), 1.0);
		bits = floor(COLOR.gba * 255.0 + 0.5);
		if (bit_set(bits, ENEMY_RAMP)) {
			player = ENEMY_PLAYER;
		}
	}
	int pi = int(player);
	plain = all(greaterThan(core, vec3(0.99))) ? 1.0 : 0.0;
	if (bit_set(bits, EXACT)) {
		plain = 0.0;
		mid = core;
		hi = mix(core, vec3(1.0), 0.35);
		hot = mix(core, vec3(1.0), 0.7);
		lo = core * 0.55;
	} else if (plain > 0.5) {
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

// A wizard's dash (K_DASH): `uv` over a quad DASH_MARGIN longer than the dash at each end.
vec4 dash(vec2 uv) {
	float len = zoom * 4.0;
	vec2 size = vec2(len + 2.0 * DASH_MARGIN, DASH_ACROSS);
	// Whole pixels from where it left, +x along it.
	vec2 d = floor(uv * size) - vec2(DASH_MARGIN, size.y * 0.5);
	float a = age;
	int pi = int(player);
	// The wizard covers the dash in its first DASH_TRAVEL of the effect, then it lingers.
	float travel = min(a / 0.45, 1.0);
	float head = len * (1.0 - (1.0 - travel) * (1.0 - travel));
	vec4 colour = vec4(0.0);
	// Speed streaks in the player's colours, behind the head.
	for (int n = 0; n < 12; n++) {
		float i = float(n);
		float y = round((hash(i, 1.0, 51.0) - 0.5) * 16.0) - 2.0;
		float x = head - 3.0 - (8.0 + 30.0 * hash(i, 2.0, 51.0)) * (0.3 + 0.7 * travel);
		float span = 3.0 + 6.0 * hash(i, 3.0, 51.0) * (1.0 - a);
		if (a < 0.7 && d.y == y && d.x >= x && d.x <= x + span && d.x <= head && d.x >= 0.0) {
			colour = vec4(a < 0.35 ? P_LIGHT[pi] : P_BASE[pi], 1.0);
		}
	}
	// Dust kicked up where it left.
	for (int n = 0; n < 6; n++) {
		float i = float(n);
		vec2 at = vec2(-(1.0 + 9.0 * hash(i, 4.0, 51.0)) * travel, 8.0 - 3.0 * hash(i, 5.0, 51.0) * travel);
		if (a < 0.5 && on(d + 0.5, at + 0.5)) {
			colour = vec4(a < 0.25 ? vec3(0.478, 0.463, 0.580) : vec3(0.290, 0.275, 0.388), 1.0);
		}
	}
	// A ring where it lands.
	float ring = (a - 0.4) / 0.35;
	float radius = 3.0 + 8.0 * (1.0 - (1.0 - ring) * (1.0 - ring));
	float r = length(d - vec2(len, 0.0));
	if (ring > 0.0 && ring < 1.0 && abs(r - radius) < 0.5) {
		colour = vec4(ring < 0.4 ? P_LIGHT[pi] : P_BASE[pi], 1.0);
	}
	// Lightning: an arc from where it left to where it landed, re-rolled 30 times a second.
	if (has_layer(L_SPARKS) && a > 0.45 && a < 0.62 && d.x >= 0.0 && d.x <= len) {
		float seg = 6.0;
		float k = floor(d.x / seg);
		float jf = floor(sim_time * 30.0);
		float o0 = k < 0.5 ? 0.0 : (hash(k, jf, 52.0) - 0.5) * 6.0;
		float o1 = k + 1.0 >= len / seg ? 0.0 : (hash(k + 1.0, jf, 52.0) - 0.5) * 6.0;
		if (round(mix(o0, o1, fract(d.x / seg))) == d.y) {
			colour = vec4(ARC_LIGHT, 1.0);
		}
	}
	// The dash's cards along the way.
	if (colour.a == 0.0 && emit_count > 0.5) {
		// A dash is long: it always gives off the most a shot may.
		for (int n = 0; n < MAX_PARTICLES; n++) {
			float i = float(n);
			float look = emitter(int(min(floor(hash(i, 6.0, 53.0) * emit_count), emit_count - 1.0)));
			float x = len * hash(i, 7.0, 53.0);
			float born = 0.45 * x / max(len, 1.0);
			vec2 from = vec2(x, (hash(i, 8.0, 53.0) - 0.5) * 12.0);
			float pa = (a - born) / 0.5;
			if (pa > 0.0 && pa < 1.0) {
				vec4 p = particle(look, from, pa, i, 0.0, d, 1.0);
				if (p.a > 0.0) {
					colour = p;
				}
			}
		}
	}
	if (colour.a > 0.0) {
		return colour;
	}
	float lit = 0.0;
	if (d.x >= 0.0 && d.x <= head) {
		// Brightest just behind the head, faded in from where it left.
		lit += 0.35 * (1.0 - a) * falloff(abs(d.y + 2.0), 9.0) * d.x / max(head, 1.0);
	}
	if (ring > 0.0 && ring < 1.0) {
		lit += 0.4 * (1.0 - ring) * falloff(abs(r - radius), 4.0);
	}
	return vec4(P_BASE[pi] * lit * glow_strength, 0.0);
}

// A beam (beam mode): its pixel at `along` pixels from the staff and `across` from its middle.
vec4 beam(float along, float across) {
	float len = max(beam_length, 1.0);
	float at = floor(along);
	float jf = floor(sim_time * 30.0);
	// Where its middle runs: jagged for lightning, swaying for storm, wavering for fire.
	float off = 0.0;
	if (has_layer(L_SPARKS)) {
		float seg = 6.0;
		float k = floor(along / seg);
		float o0 = k < 0.5 ? 0.0 : (hash(k, jf, 41.0) - 0.5) * 6.0;
		float o1 = (k + 1.0) * seg >= len ? 0.0 : (hash(k + 1.0, jf, 41.0) - 0.5) * 6.0;
		off = mix(o0, o1, fract(along / seg));
	} else if (has_layer(L_GUSTS)) {
		off = sin(along * 0.11 - sim_time * 18.0) * 1.6;
	} else if (has_layer(L_EMBERS)) {
		off = sin(along * 0.55 - sim_time * 36.0) * 0.7;
	}
	float x = round(across - off);
	vec4 colour = vec4(0.0);
	// As it ends it falls apart into pixels.
	bool kept = hash(at, floor(across) + 7.0, 42.0) < beam_fade * 1.4;
	float rim = 1.0 + floor(0.5 * beam_swell + 0.25);
	if (kept) {
		if (x == 0.0) {
			colour = vec4(has_layer(L_PULL) ? OUTLINE : hot, 1.0);
		} else if (abs(x) <= rim && sin(along * 0.23 - sim_time * 27.0) > -0.25) {
			colour = vec4(hi, 1.0);
		} else if (abs(x) <= rim + 1.0 && hash(at, floor(sim_time * 15.0), 43.0) < 0.12) {
			colour = vec4(mid, 1.0);
		}
		// Motes running down it.
		for (int n = 0; n < 6; n++) {
			float i = float(n);
			float pos = fract(sim_time * 1.3 + i / 6.0 + hash(i, 0.0, 44.0)) * len;
			if (abs(along - pos) < 0.5 && x == (hash(i, 1.0, 44.0) < 0.5 ? -1.0 : 1.0)) {
				colour = vec4(hot, 1.0);
			}
		}
	}
	// Flares at the staff and where it lands, flickering a pixel.
	float flick = mod(floor(sim_time * 20.0), 2.0);
	vec2 start = vec2(at + 0.5, across);
	vec2 end = vec2(along - len, across);
	float sr = 1.0 + flick;
	float er = 2.0 + flick;
	if ((abs(start.x) < 0.5 && abs(start.y) <= sr) || (abs(start.y) < 0.5 && start.x >= 0.0 && start.x <= sr)) {
		colour = vec4(has_layer(L_PULL) ? VOID_LIGHT : hot, 1.0);
	}
	if ((abs(end.x) < 0.5 && abs(end.y) <= er) || (abs(end.y) < 0.5 && abs(end.x) <= er)) {
		colour = vec4(has_layer(L_PULL) ? VOID_LIGHT : hot, 1.0);
	}
	// Its cards, given off along it.
	if (colour.a == 0.0 && emit_count > 0.5) {
		float count = min(4.0 + 2.0 * emit_count, float(MAX_PARTICLES));
		for (int n = 0; n < MAX_PARTICLES; n++) {
			if (float(n) >= count) {
				break;
			}
			float i = float(n);
			float t = sim_time * (2.5 + 1.5 * hash(i, 0.0, 45.0)) + hash(i, 0.0, 46.0);
			float cyc = floor(t);
			float look = emitter(int(min(floor(hash(i, cyc, 47.0) * emit_count), emit_count - 1.0)));
			vec2 from = vec2(len * hash(i, cyc, 48.0), off);
			vec4 p = particle(look, from, fract(t), i, cyc, vec2(along, across), 1.0);
			if (p.a > 0.0) {
				colour = p;
			}
		}
	}
	if (colour.a > 0.0) {
		return colour;
	}
	float lit = 0.45 * falloff(abs(across - off), 3.0 + 3.0 * beam_swell) + 0.6 * falloff(length(end), 7.0) + 0.4 * falloff(length(start), 5.0);
	lit *= beam_fade * beam_glow;
	if (has_layer(L_SPARKS)) {
		lit *= 0.55 + 0.9 * hash(floor(sim_time * 20.0), 0.0, 21.0);
	}
	if (has_layer(L_PULL)) {
		lit *= 0.6;
	}
	return vec4(glow * lit * glow_strength, 0.0);
}

// A discharge (K_ARC): `uv` over a quad ARC_MARGIN longer than the arc at each end.
vec4 arc(vec2 uv) {
	float len = zoom * 4.0;
	vec2 size = vec2(len + 2.0 * ARC_MARGIN, ARC_ACROSS);
	vec2 d = floor(uv * size) - vec2(ARC_MARGIN, size.y * 0.5);
	float a = age;
	float seg = 5.0;
	float k = floor(d.x / seg);
	float jf = floor(sim_time * 30.0);
	float o0 = k < 0.5 ? 0.0 : (hash(k, jf, 61.0) - 0.5) * 6.0;
	float o1 = (k + 1.0) * seg >= len ? 0.0 : (hash(k + 1.0, jf, 61.0) - 0.5) * 6.0;
	float off = round(mix(o0, o1, fract(d.x / seg)));
	bool along = d.x >= 0.0 && d.x <= len;
	// It burns out from the ends inwards as it fades.
	bool kept = hash(d.x, 0.0, 62.0) > a * 1.2 - 0.2;
	if (along && kept && d.y == off) {
		return vec4(a < 0.4 ? hot : hi, 1.0);
	}
	if (along && kept && abs(d.y - off) == 1.0 && hash(d.x, jf, 63.0) < 0.25) {
		return vec4(mid, 1.0);
	}
	float lit = along ? (1.0 - a) * 0.6 * falloff(abs(d.y - off), 5.0) : 0.0;
	lit *= 0.6 + 0.8 * hash(jf, 0.0, 64.0);
	return vec4(glow * lit * glow_strength, 0.0);
}

// A status (K_STATUS): its look's particles round the character, endless, and a pulsing glow.
vec4 status(vec2 uv) {
	vec2 size = vec2(GRID) * zoom;
	vec2 d = floor(uv * size) - size * 0.5;
	float reach = 4.0 * zoom;
	for (int n = 0; n < 8; n++) {
		float i = float(n);
		float t = sim_time * (1.2 + 0.8 * hash(i, 0.0, 71.0)) + hash(i, 0.0, 72.0);
		float cyc = floor(t);
		float ang = hash(i, cyc, 73.0) * 6.2832;
		vec2 from = vec2(cos(ang), sin(ang) * 0.8) * reach * (0.5 + 0.5 * hash(i, cyc, 74.0));
		vec4 p = vec4(0.0);
		if (emit_count > 0.5) {
			float look = emitter(int(min(floor(hash(i, cyc, 75.0) * emit_count), emit_count - 1.0)));
			p = particle(look, from, fract(t), i, cyc, d, 1.0);
		} else if (fract(t) < 0.8 && on(d, from + vec2(0.0, -6.0 * fract(t)))) {
			p = vec4(fract(t) < 0.4 ? hi : mid, 1.0);
		}
		if (p.a > 0.0) {
			return p;
		}
	}
	float pulse = 0.6 + 0.4 * sin(sim_time * 6.0 + seed);
	return vec4(glow * 0.3 * pulse * falloff(length(d), reach * 1.6) * glow_strength, 0.0);
}

vec4 effect(vec2 uv) {
	if (kind == K_DASH) {
		return dash(uv);
	}
	if (kind == K_ARC) {
		return arc(uv);
	}
	if (kind == K_STATUS) {
		return status(uv);
	}
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
	} else if (kind == K_SPRAY || kind == K_PUFF) {
		bool round_about = kind == K_PUFF;
		// A small white-hot cross where it struck, or a dotted puff.
		if (round_about) {
			if (a < 0.18 && r <= 2.0 * zoom && mod(d.x + d.y, 2.0) == 0.0) {
				colour = vec4(a < 0.09 ? hot : hi, 1.0);
			}
		} else if (a < 0.2 && ((d.x == 0.0 && abs(d.y) <= 1.0) || (d.y == 0.0 && abs(d.x) <= 1.0))) {
			colour = vec4(hot, 1.0);
		}
		int sparks = round_about ? 14 : 10;
		for (int n = 0; n < 14; n++) {
			if (n >= sparks || colour.a > 0.0) {
				break;
			}
			float i = float(n);
			float life = 0.5 + 0.5 * hash(i, 11.0, 31.0);
			if (a > life) {
				continue;
			}
			float ang = round_about ? i / 14.0 * 6.2832 + (hash(i, 12.0, 31.0) - 0.5) * 0.4 : (hash(i, 12.0, 31.0) - 0.5) * 1.6;
			float reach = (2.0 + (round_about ? 10.0 : 13.0) * (0.5 + 0.5 * hash(i, 13.0, 31.0)) * ease) * zoom;
			if (on(d + 0.5, vec2(cos(ang), sin(ang)) * reach + 0.5)) {
				colour = vec4(ramp(a / life), 1.0);
			}
		}
		lit = (1.0 - a) * (1.0 - a) * (0.7 * falloff(r, 3.0 * zoom) + 0.3 * falloff(r, 9.0 * zoom));
	} else if (kind == K_CHIPS) {
		// Stone chips knocked back off the wall, falling as they fly; no glow.
		for (int n = 0; n < 7; n++) {
			float i = float(n);
			float ang = (hash(i, 14.0, 31.0) - 0.5) * 2.2;
			float reach = (2.0 + 9.0 * (0.5 + 0.5 * hash(i, 15.0, 31.0)) * ease) * zoom;
			vec2 at = vec2(cos(ang), sin(ang)) * reach + vec2(0.0, 0.0);
			// Down the screen as it falls, whatever the wall's side.
			vec2 fall = vec2(0.0, 7.0 * a * a * zoom);
			vec2 local = at;
			if (a < 0.9 && (on(d + 0.5, local + 0.5 + fall) || (hash(i, 16.0, 31.0) < 0.4 && on(d + 0.5, local + vec2(1.5, 0.5) + fall)))) {
				return vec4(a < 0.3 ? STONE_LIGHT : (a < 0.65 ? STONE_BASE : STONE_SHADOW), 1.0);
			}
		}
		return vec4(0.0);
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

// An enemy's telegraph (beam mode 3): its pixel at `along` pixels from the enemy and `across`
// from the middle of its lane. Drawn in the ramp of `core_override` (Fire, docs/STYLE.md: enemy
// telegraphs use Fire colours and are brighter than anything else on screen).
vec4 telegraph(float along, float across) {
	float len = max(beam_length, 1.0);
	float at = floor(along);
	float y = floor(across);
	float p = clamp(telegraph_progress, 0.0, 1.0);
	bool last = p >= 0.8;
	float lane = clamp(round(telegraph_lane), 1.0, 14.0);
	// The arrowhead at the far end, growing as the cast nears.
	float head = round(mix(3.0, 7.0, p));
	float back = len - at;
	if (back >= 0.0 && back <= head && abs(y + 0.5) <= back * 0.9 + 0.5) {
		return vec4(last || back < 1.5 ? hot : hi, 1.0);
	}
	if (at < 0.0 || at > len) {
		return vec4(0.0);
	}
	// Dashes down the middle, marching toward the tip as the windup runs.
	if ((y == 0.0 || y == -1.0) && mod(at - floor(p * 24.0), 8.0) < 4.0 && back > head) {
		return vec4(last ? hot : hi, 1.0);
	}
	// The lane's edges, dotted, so the hit width reads.
	if (abs(y + 0.5) == lane + 0.5 && mod(at, 3.0) < 1.0) {
		return vec4(mid, 1.0);
	}
	float inside = abs(y + 0.5) <= lane + 0.5 ? 1.0 : falloff(abs(y + 0.5) - lane, 3.0);
	float lit = inside * (0.14 + 0.3 * p) + 0.4 * p * falloff(abs(y + 0.5), 2.0);
	return vec4(glow * lit * beam_glow * glow_strength, 0.0);
}

void fragment() {
	if (beam_mode == 3) {
		COLOR = telegraph(UV.x / TEXTURE_PIXEL_SIZE.x, UV.y / TEXTURE_PIXEL_SIZE.y - 0.5 / TEXTURE_PIXEL_SIZE.y);
	} else if (beam_mode == 1) {
		COLOR = beam(UV.x * beam_length, (UV.y - 0.5) * beam_width);
	} else if (beam_mode == 2) {
		COLOR = beam(UV.x / TEXTURE_PIXEL_SIZE.x, UV.y / TEXTURE_PIXEL_SIZE.y - 0.5 / TEXTURE_PIXEL_SIZE.y);
	} else if (kind > 3.5) {
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
		vec3 shown = mix(rgb, lit, warm);
		if (dissolve > 0.0) {
			vec2 px = floor(UV / TEXTURE_PIXEL_SIZE);
			if (t.a > 0.5 && hash(px.x, px.y, 81.0) < dissolve * 1.2 - 0.1) {
				alpha = 0.0;
			} else if (t.a > 0.5) {
				shown = mix(shown, dissolve_color.rgb, min(dissolve * 3.0, 1.0));
				alpha = 1.0;
			}
		}
		if (alpha < 0.5 && sprite_glow > 0.0) {
			// The glow: how much of the sprite is near, 2 and 4 pixels away in eight directions.
			float near = 0.0;
			for (int k = 0; k < 8; k++) {
				vec2 dir = vec2(cos(float(k) * 0.7854), sin(float(k) * 0.7854)) * TEXTURE_PIXEL_SIZE;
				near += texture(TEXTURE, UV + dir * 2.0).a * 0.09 + texture(TEXTURE, UV + dir * 4.0).a * 0.035;
			}
			vec3 hue = dissolve > 0.0 ? dissolve_color.rgb : body.rgb;
			COLOR = vec4(hue * near * sprite_glow * (1.0 - dissolve) * glow_strength, 0.0);
		} else {
			// Premultiplied, as the blend mode wants.
			COLOR = vec4(shown * alpha, alpha);
		}
	}
}
