// SPDX-License-Identifier: GPL-3.0-or-later
shader_type canvas_item;
// world_vertex_coords: VERTEX is in world space in vertex(), so a trail can place its own quad
// and every pixel can be found on the world's pixel grid (nothing else moves its vertices).
render_mode blend_premul_alpha, world_vertex_coords;

// The look of a player's shot (staffs B6a, docs/milestones/M2-staffs.md, "The look of a shot"),
// built here on a pixel grid, so a shot needs no art and no nodes.
//
// MultiMesh instances (the projectile manager) carry:
//   custom data rgb  the core colour (the first infusion's tint; white for none)
//   custom data a    the body kind and a code as 1 - (kind + code) / 16: kind 1 a shot in flight
//                    and its trail (TRAILS below), 2 a rune, 3 an orbit shot drawn round its
//                    circle (a familiar), 4-15 an effect Feel draws (K_* below), 0 the texture
//                    (below); the code (0-0.45) is an orbit shot's bend (how its path curves, so
//                    its tail follows it; BEND_* below), how much of a new rune is traced, or how
//                    far through its life an effect is (TRACE_* below)
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
//
// TRAILS (kind 1; the owner, 2026-10-28: "the tail of projectiles turn with the projectile"):
// a shot leaves its tail and its card particles in the world, where it was, as the mockup does.
// The projectile manager keeps each shot's path in `trail_data`, one row per trail of
// TRAIL_SAMPLES texels (x, y, odometer, time), a ring written 30 times a second and at every
// bounce and end. Each pixel of travel leaves one tail pixel there, which drifts a little and
// cools through the ramp in its own time (0.1-0.3 s), so the tail bends with any path and frays
// at its end by itself; each 60th of a second may give off a particle of one of the shot's kinds
// from where the shot was then, which moves on its own from there (embers rise, flecks hang,
// gusts blow back and curl, sparks jump, void pulls in to the shot). The pixel's or particle's
// number is its place on the path (the odometer) or its moment, so it stays the same pixel from
// frame to frame. A trail outlives its shot by its longest life, so a tail cools where it ended.
// Everything is drawn on the world's pixel grid, axis-aligned: the core is a `+` whatever way
// the shot flies, and a line is one pixel per step, as the mockup draws it.
// The instance carries its data in its transform (the batch must sit untransformed at the
// origin): origin the head (where the shot is drawn this frame), x axis (row, newest sample's
// number), y axis (samples kept, TF_* flags); the vertex shader places the quad round the path.

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
// Where a beam starts (the staff) and ends in the world, and its way at the end: its flares and
// the splash where it lands are drawn there, upright on the world's pixels.
uniform vec2 beam_start = vec2(-100000.0);
uniform vec2 beam_end = vec2(-100000.0);
uniform vec2 beam_end_dir = vec2(1.0, 0.0);
// How far the beam's quad reaches past each end, so the flares are whole: its line (or region)
// is beam_length + 2 x beam_lead long and starts beam_lead before the staff.
uniform float beam_lead = 0.0;
// The trails (TRAILS above): the paths, and the moment the heads are drawn at (the simulation
// clock less what the drawing lags behind the last step), in the samples' clock.
uniform sampler2D trail_data : filter_nearest;
uniform float trail_now = 0.0;

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
//   K_DASH        the dust of a wizard's dash where it started (the effect's place); its way is
//                 the caster's trail (TF_DASH) and its landing Feel's ring; its quad is zoom x 4
//                 pixels plus DASH_MARGIN each end, DASH_ACROSS across
//   K_BEAM        a beam (beam mode above): a white-hot one-pixel core, a rim that breathes
//                 along it, motes running down it, flares at both ends and its card particles
//   K_SPRAY       a hit on a character: sparks thrown on along the hit's way, cooling
//   K_PUFF        sparks all round and a dotted white-hot puff (a kill, a reaction, a hit
//                 with no way); with the POOF bit (kind 22) a staff's personality swap instead
//                 (living staffs H4): bone clouds along the staff (+x) that swell to their
//                 biggest at 35% of the effect (where the body changes) and shrink away, and a
//                 few sparks in the player's colour
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
const float POOF = 22.0;
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
// Trails: samples a row holds (TRAIL_SAMPLES in projectile_manager.gd), the moments a particle
// may be born a second, and the flags (TRAIL_* there): the shot is alive (its core is drawn and
// its path runs on to the head), an orbit shot (a shorter tail), a wizard's dash (speed streaks
// in the player's colours and the dash's cards, no tail, no core).
const int TRAIL_SAMPLES = 32;
const float BIRTHS = 60.0;
const float TF_HEAD = 1.0;
const float TF_ORBIT = 2.0;
const float TF_DASH = 4.0;
// The longest anything of a trail lives, so the quad and the walk back stop there.
const float TRAIL_LONGEST = 1.0;

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
const vec3 BONE_BASE = vec3(0.831, 0.816, 0.878);
const vec3 BONE_SHADOW = vec3(0.639, 0.624, 0.722);
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
// The world position of the pixel (every mode), and a trail's data (TRAILS above): its row, the
// number of its newest sample, how many it keeps, its flags, its head, how far back it is drawn
// (seconds) and how long its tail pixels live at most.
varying vec2 world;
varying flat float trail_row;
varying flat float trail_newest;
varying flat float trail_count;
varying flat float trail_flags;
varying flat vec2 trail_head;
varying flat float trail_window;
varying flat float tail_life;

bool bit_set(vec3 b, float look) {
	float bit = look - 1.0;
	float byte = bit < 8.0 ? b.x : (bit < 16.0 ? b.y : b.z);
	return mod(floor(byte / exp2(mod(bit, 8.0))), 2.0) > 0.5;
}

bool flag_set(float flags, float f) {
	return mod(floor(flags / f + 0.001), 2.0) > 0.5;
}

// Sample `k` back from the newest (0) of trail `row`: x, y, odometer, time.
vec4 trail_texel(float row, float newest, float k) {
	float n = newest - k;
	return texelFetch(trail_data, ivec2(int(mod(n, float(TRAIL_SAMPLES))), int(row)), 0);
}

// How long a trail with these look bits and flags is drawn back from its head (seconds), and how
// far round its path its particles may wander (pixels): the longest life and reach of its tail
// and of its kinds (`trail_particle`).
vec2 trail_reach(vec3 b, float flags, float z, float tail) {
	bool dash = flag_set(flags, TF_DASH);
	float longest = tail;
	// The glow round the core and the tail reaches this far.
	float margin = 9.0 + 2.0 * z;
	if (dash) {
		longest = max(longest, 0.18);
		margin = max(margin, 12.0);
	}
	if (!bit_set(b, L_EMBERS) && !bit_set(b, L_FLECKS) && !bit_set(b, L_GUSTS) && !bit_set(b, L_PULL) && !bit_set(b, L_SPARKS) && !bit_set(b, L_MOTES) && !bit_set(b, L_GLINTS) && !bit_set(b, L_STREAKS) && !bit_set(b, L_BURST) && !dash) {
		// A plain shot's twinkles.
		longest = max(longest, 0.6);
		margin = max(margin, 9.0);
	}
	if (bit_set(b, L_EMBERS)) {
		longest = max(longest, dash ? 0.85 : 0.65);
		margin = max(margin, 18.0);
	}
	if (bit_set(b, L_FLECKS)) {
		longest = max(longest, dash ? 1.0 : 0.9);
		margin = max(margin, 18.0);
	}
	if (bit_set(b, L_GUSTS)) {
		longest = max(longest, 0.22);
		margin = max(margin, 36.0);
	}
	if (bit_set(b, L_PULL)) {
		margin = max(margin, 14.0);
	}
	if (bit_set(b, L_SPARKS)) {
		longest = max(longest, 0.15);
		margin = max(margin, 14.0);
	}
	if (bit_set(b, L_MOTES)) {
		longest = max(longest, 0.8);
		margin = max(margin, 14.0);
	}
	if (bit_set(b, L_GLINTS)) {
		longest = max(longest, 0.6);
		margin = max(margin, 8.0);
	}
	if (bit_set(b, L_STREAKS)) {
		longest = max(longest, 0.25);
	}
	if (bit_set(b, L_BURST)) {
		longest = max(longest, 0.5);
		margin = max(margin, 4.0 + 8.0 * z);
	}
	if (bit_set(b, L_ORBITERS) || bit_set(b, L_GLITTER)) {
		margin = max(margin, 3.0 + 6.0 * z);
	}
	return vec2(min(longest, TRAIL_LONGEST), margin);
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
	world = VERTEX;
	trail_row = -1.0;
	trail_newest = 0.0;
	trail_count = 0.0;
	trail_flags = 0.0;
	trail_head = vec2(0.0);
	trail_window = 0.0;
	tail_life = 0.0;
	if (beam_mode == 0 && core_override.a <= 0.0 && abs(kind - 1.0) < 0.5) {
		// A trail: read its data from the transform and put the quad round its path.
		float row = MODEL_MATRIX[0].x;
		float newest = MODEL_MATRIX[0].y;
		float count = row < 0.0 ? 0.0 : MODEL_MATRIX[1].x;
		float flags = MODEL_MATRIX[1].y;
		vec2 head = MODEL_MATRIX[3].xy;
		bool live = flag_set(flags, TF_HEAD);
		bool dash = flag_set(flags, TF_DASH);
		float mul = bit_set(bits, L_FLECKS) ? 1.5 : (bit_set(bits, L_SPARKS) ? 0.7 : (bit_set(bits, L_PULL) ? 1.1 : 1.0));
		if (flag_set(flags, TF_ORBIT)) {
			mul *= 0.8;
		}
		float tail = dash ? 0.0 : 0.3 * mul * trail_share;
		vec2 reach = trail_reach(bits, flags, zoom, tail);
		// The newest point drawn (the head, or the last sample of a trail whose shot is gone)
		// and the oldest (the first sample past the window: its piece reaches into it).
		vec2 first = head;
		vec2 far = head;
		bool started = live;
		for (int j = 0; j < TRAIL_SAMPLES; j++) {
			if (float(j) >= count) {
				break;
			}
			vec4 s = trail_texel(row, newest, float(j));
			if (s.w > trail_now + 0.0001) {
				continue;
			}
			if (!started) {
				first = s.xy;
				started = true;
			}
			far = s.xy;
			if (trail_now - s.w > reach.x) {
				break;
			}
		}
		vec2 axis = far - first;
		axis = length(axis) > 0.5 ? normalize(axis) : vec2(1.0, 0.0);
		vec2 side = vec2(-axis.y, axis.x);
		vec2 box_lo = vec2(0.0);
		vec2 box_hi = vec2(0.0);
		if (live) {
			vec2 p = head - first;
			box_lo = min(box_lo, vec2(dot(p, axis), dot(p, side)));
			box_hi = max(box_hi, vec2(dot(p, axis), dot(p, side)));
		}
		for (int j = 0; j < TRAIL_SAMPLES; j++) {
			if (float(j) >= count) {
				break;
			}
			vec4 s = trail_texel(row, newest, float(j));
			if (s.w > trail_now + 0.0001) {
				continue;
			}
			vec2 p = s.xy - first;
			box_lo = min(box_lo, vec2(dot(p, axis), dot(p, side)));
			box_hi = max(box_hi, vec2(dot(p, axis), dot(p, side)));
			if (trail_now - s.w > reach.x) {
				break;
			}
		}
		box_lo -= vec2(reach.y);
		box_hi += vec2(reach.y);
		vec2 at = mix(box_lo, box_hi, UV);
		VERTEX = first + axis * at.x + side * at.y;
		world = VERTEX;
		trail_row = row;
		trail_newest = newest;
		trail_count = count;
		trail_flags = flags;
		trail_head = head;
		trail_window = reach.x;
		tail_life = tail;
		seed = row < 0.0 ? 0.0 : mod(row, 61.0) * 1.618;
	}
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

// A wizard's dash (K_DASH): the dust kicked up where it left, both ways along the floor, `uv`
// over a quad DASH_MARGIN longer than zoom x 4 pixels at each end. The way it went (speed
// streaks, its cards) is the caster's trail (TF_DASH), drawn where the wizard really went, and
// the ring where it lands is Feel's (staffs, 2026-10-28: the dash look followed the aim, not the
// wizard).
vec4 dash(vec2 uv) {
	float len = zoom * 4.0;
	vec2 size = vec2(len + 2.0 * DASH_MARGIN, DASH_ACROSS);
	// Whole pixels from where it left.
	vec2 d = floor(uv * size) - vec2(DASH_MARGIN, size.y * 0.5);
	float a = age;
	float travel = min(a / 0.45, 1.0);
	for (int n = 0; n < 6; n++) {
		float i = float(n);
		float way = hash(i, 9.0, 51.0) < 0.5 ? -1.0 : 1.0;
		vec2 at = vec2(way * (1.0 + 9.0 * hash(i, 4.0, 51.0)) * travel, 8.0 - 3.0 * hash(i, 5.0, 51.0) * travel);
		if (a < 0.5 && on(d + 0.5, at + 0.5)) {
			return vec4(a < 0.25 ? STONE_LIGHT : STONE_BASE, 1.0);
		}
	}
	return vec4(0.0);
}

// A beam (beam mode): its pixel at `along` pixels from the staff and `across` from its middle,
// `cheb` the longer axis's share of its way on screen (so a line is one pixel per step of that
// axis, as the mockup draws it, never two), `P` the pixel in the world.
vec4 beam(float along, float across, float cheb, vec2 P) {
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
	float x = floor((across - off) / max(cheb, 0.5) + 0.5);
	vec4 colour = vec4(0.0);
	// As it ends it falls apart into pixels.
	bool kept = hash(at, x + 7.0, 42.0) < beam_fade * 1.4;
	float rim = 1.0 + floor(0.5 * beam_swell + 0.25);
	if (kept && along >= 0.0 && along <= len) {
		if (x == 0.0) {
			colour = vec4(has_layer(L_PULL) ? OUTLINE : hot, 1.0);
		} else if (abs(x) <= rim && sin(along * 0.23 - sim_time * 27.0) > -0.25) {
			// The rim breathes along it.
			colour = vec4(hi, 1.0);
		} else if (abs(x) == rim + 1.0 && x * (mod(at, 2.0) - 0.5) > 0.0 && mod(at * 7.0 + floor(sim_time * 30.0) * 13.0, 11.0) < 2.0) {
			// Sparkles a pixel out, re-rolled every other frame.
			colour = vec4(mid, 1.0);
		}
	}
	// Flares at the staff and where it lands, upright crosses that flicker a pixel.
	float flick = mod(floor(sim_time * 30.0), 2.0);
	vec2 ds = floor(P) - floor(beam_start);
	vec2 de = floor(P) - floor(beam_end);
	float sr = 1.0 + flick;
	float er = 2.0 + flick;
	vec3 flare = has_layer(L_PULL) ? VOID_LIGHT : hot;
	if ((ds.x == 0.0 && abs(ds.y) <= sr) || (ds.y == 0.0 && abs(ds.x) <= sr)) {
		colour = vec4(ds == vec2(0.0) ? flare : hi, 1.0);
	}
	if (beam_fade > 0.3 && ((de.x == 0.0 && abs(de.y) <= er) || (de.y == 0.0 && abs(de.x) <= er))) {
		colour = vec4(de == vec2(0.0) ? flare : hi, 1.0);
	}
	// A splash where it lands: sparks thrown back off the end, cooling.
	float lit = 0.0;
	vec2 back = -normalize(beam_end_dir + vec2(0.0001, 0.0));
	for (int n = 0; n < 6; n++) {
		float i = float(n);
		float life = 0.1 + 0.12 * hash(i, 0.0, 49.0);
		float t = sim_time / life + hash(i, 1.0, 49.0);
		float cyc = floor(t);
		float a = fract(t);
		float ang = atan(back.y, back.x) + (hash(i, cyc, 50.0) - 0.5) * 2.4;
		vec2 pos = beam_end + vec2(cos(ang), sin(ang)) * (40.0 + 60.0 * hash(i, cyc, 51.0)) * (0.9 * (1.0 - pow(0.9, a * life * 60.0)) / 0.1 / 60.0);
		float r = length(floor(P) - floor(pos));
		lit += 0.9 * (1.0 - 0.75 * a) * (0.16 * falloff(r, 2.5) + 0.07 * falloff(r, 7.0)) * beam_fade;
		if (colour.a == 0.0 && beam_fade > 0.3 && r < 0.5) {
			colour = vec4(ramp(a), 1.0);
		}
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
	lit += 0.45 * falloff(abs(across - off), 3.0 + 3.0 * beam_swell) + 0.6 * falloff(length(floor(P) - floor(beam_end)), 7.0) + 0.4 * falloff(length(floor(P) - floor(beam_start)), 5.0);
	// Motes of light running down it from the staff.
	for (int n = 0; n < 4; n++) {
		float pos = mod(sim_time * 320.0 + float(n) * len / 4.0, len);
		lit += 0.35 * falloff(abs(along - pos), 5.0) * falloff(abs(across - off), 4.0);
	}
	lit *= beam_fade * beam_glow;
	if (has_layer(L_SPARKS)) {
		lit *= 0.55 + 0.9 * hash(floor(sim_time * 20.0), 0.0, 21.0);
	}
	if (has_layer(L_PULL)) {
		lit *= 0.6;
	}
	return vec4(glow * lit * glow_strength, 0.0);
}

// The longer axis's share of the way `along` grows on screen (1 for a level or upright beam,
// 0.71 for a diagonal one).
float cheb_of(float along) {
	vec2 g = vec2(dFdx(along), dFdy(along));
	float l = length(g);
	return l > 0.0001 ? max(abs(g.x), abs(g.y)) / l : 1.0;
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
	} else if (kind == K_PUFF && bit_set(bits, POOF)) {
		// A staff's poof: four bone clouds along the staff, biggest at 35%, dotted as they go.
		float swell = a < 0.35 ? a / 0.35 : 1.0 - (a - 0.35) / 0.65;
		for (int n = 0; n < 4; n++) {
			float i = float(n);
			vec2 c = vec2((i - 1.5) * 6.0, (hash(i, 17.0, 31.0) - 0.5) * 3.0) * zoom * 0.5;
			float size = (2.5 + 1.5 * hash(i, 18.0, 31.0)) * swell * zoom * 0.5 + 0.5;
			float q = length(d - c);
			if (q <= size && (a < 0.7 || mod(d.x + d.y, 2.0) == 0.0)) {
				// Lit from the top-left: light on that side, shadow on the far rim.
				vec2 side = (d - c) / max(size, 1.0);
				vec3 shade = side.x + side.y < -0.5 ? BONE_LIGHT : (q > size - 1.0 && side.x + side.y > 0.3 ? BONE_SHADOW : BONE_BASE);
				colour = vec4(shade, 1.0);
				break;
			}
		}
		for (int n = 0; n < 6; n++) {
			if (colour.a > 0.0) {
				break;
			}
			float i = float(n);
			float ang = i / 6.0 * 6.2832 + hash(i, 19.0, 31.0);
			float reach = (4.0 + 6.0 * hash(i, 20.0, 31.0) * ease) * zoom;
			if (a < 0.8 && on(d + 0.5, vec2(cos(ang) * 1.6, sin(ang)) * reach + 0.5)) {
				colour = vec4(a < 0.4 ? hi : mid, 1.0);
			}
		}
		lit = (1.0 - a) * 0.3 * falloff(r, 6.0 * zoom);
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

// ---- Trails (TRAILS above) ----

// A number in [0, 1) from three whole numbers and the trail: an integer hash, so a pixel's
// number (its place on the path, its moment) keeps its looks however large it grows.
uint mix_bits(uint x) {
	x ^= x >> 16u;
	x *= 2146121005u;
	x ^= x >> 15u;
	x *= 2221713035u;
	x ^= x >> 16u;
	return x;
}

float th(float a, float b, float c) {
	uint h = mix_bits(uint(int(a)) ^ mix_bits(uint(int(b)) + mix_bits(uint(int(c)) + uint(int(trail_row)) * 7919u + 40503u)));
	return float(h & 16777215u) / 16777216.0;
}

// How far a pixel thrown at 1 px/s has gone after `ago` seconds, slowed by `drag` each 60th of a
// second (the mockup's particles).
float dragged(float ago, float drag) {
	float f = ago * 60.0;
	return drag * (1.0 - pow(drag, f)) / (1.0 - drag) / 60.0;
}

// The colour `u` (0-1) of the way through a ramp of three or four shades.
vec3 shade3(vec3 a, vec3 b, vec3 c, float u) {
	return u < 0.334 ? a : (u < 0.667 ? b : c);
}

vec3 shade4(vec3 a, vec3 b, vec3 c, vec3 d, float u) {
	return u < 0.25 ? a : (u < 0.5 ? b : (u < 0.75 ? c : d));
}

// True when the pixel at `P` is pixel `at` of a shot of zoom `z` (a z x z square).
bool on_pixel(vec2 P, vec2 at, float z) {
	vec2 d = floor(P) - floor(at - vec2(floor((z - 1.0) * 0.5)));
	return d.x >= 0.0 && d.y >= 0.0 && d.x < z && d.y < z;
}

// True when the pixel at `P` is on the one-pixel line from `a` to `b`, drawn as the mockup's
// lines are: one pixel per step along the longer axis.
bool on_line(vec2 P, vec2 a, vec2 b) {
	vec2 ab = b - a;
	float l = length(ab);
	if (l < 0.5) {
		return on_pixel(P, a, 1.0);
	}
	vec2 dir = ab / l;
	vec2 c = floor(P) + 0.5;
	float t = dot(c - a, dir);
	float s = dot(c - a, vec2(-dir.y, dir.x));
	float thin = 0.5 * max(abs(dir.x), abs(dir.y));
	return t >= -0.5 && t <= l + 0.5 && s >= -thin && s < thin;
}

// Put `rgb` on the pixel if it is younger than what is there (the mockup draws the newest last).
void put(vec3 rgb, float ago, inout vec4 colour, inout float best) {
	if (ago < best) {
		colour = vec4(rgb, 1.0);
		best = ago;
	}
}

// A particle of kind `look` given off `ago` seconds ago where the shot was (`at`, flying along
// `dir`), numbered `id` (its moment) and `j` (its place among that moment's): drawn on `P` if it
// is there, its light added to `lit`. `target` is where the shot is now (the void pulls in to
// it). The motions are the mockup's: the starting spread and speeds, the drag, the lives.
void trail_particle(float look, vec2 at, vec2 dir, float ago, float id, float j, vec2 P, vec2 target, float z, inout vec4 colour, inout float best, inout float lit) {
	vec2 side = vec2(-dir.y, dir.x);
	float frame = floor(trail_now * 60.0);
	vec3 rgb = vec3(0.0);
	float e = 0.0;
	vec2 pos = at;
	bool shown = false;
	float life = 1.0;
	bool streak = false;
	vec2 tip = at;
	if (look == L_EMBERS) {
		// Fire: an ember that drifts back and rises, flickering, spark yellow to red.
		life = 0.3 + 0.35 * th(id, j, 21.0);
		vec2 v = vec2(-dir.x * 14.0 + (th(id, j, 22.0) - 0.5) * 14.0, -dir.y * 14.0 - 10.0 - th(id, j, 23.0) * 24.0);
		pos = at - dir * th(id, j, 24.0) * 4.0 + vec2(0.0, (th(id, j, 25.0) - 0.5) * 2.0) + v * dragged(ago, 0.97);
		float u = ago / life;
		rgb = shade4(SPARK_LIGHT, FIRE_LIGHT, FIRE_BASE, SHADES[0], u);
		e = 1.0;
		shown = th(id, frame, 26.0) >= 0.22;
	} else if (look == L_FLECKS) {
		// Frost: a fleck left hanging behind, twinkling; some open into a small star.
		life = 0.5 + 0.4 * th(id, j, 31.0);
		pos = at - dir * th(id, j, 32.0) * 14.0 + (vec2(th(id, j, 33.0), th(id, j, 34.0)) - 0.5) * 3.0 + (vec2(th(id, j, 35.0), th(id, j, 36.0)) - 0.5) * 4.0 * ago;
		float u = ago / life;
		rgb = shade4(BONE_LIGHT, ICE_LIGHT, ICE_LIGHT, SHADES[7], u);
		e = 0.9;
		shown = mod(frame + id * 3.0 + j, 7.0) >= 2.0;
		if (shown && th(id, j, 37.0) < 0.3 && u < 0.2) {
			vec2 d = abs(floor(P) - floor(pos));
			if (d.x + d.y == 1.0) {
				put(ICE_LIGHT, ago, colour, best);
			}
		}
	} else if (look == L_GUSTS) {
		// Storm: a short streak blown back fast past the shot, curling.
		life = 0.1 + 0.12 * th(id, j, 41.0);
		vec2 v = -dir * (80.0 + 70.0 * th(id, j, 42.0)) + side * (th(id, j, 43.0) - 0.5) * 40.0;
		float curl = (th(id, j, 44.0) - 0.5) * 9.0;
		float a = curl * ago;
		vec2 moved = abs(curl) < 0.01 ? v * ago : vec2(v.x * sin(a) - v.y * (1.0 - cos(a)), v.x * (1.0 - cos(a)) + v.y * sin(a)) / curl;
		pos = at + side * (th(id, j, 45.0) - 0.5) * 7.0 + moved;
		vec2 now_v = vec2(v.x * cos(a) - v.y * sin(a), v.x * sin(a) + v.y * cos(a));
		tip = pos - now_v * 0.025;
		streak = true;
		rgb = shade3(SPARK_LIGHT, SHADES[4], SHADES[3], ago / life);
		e = 0.8;
		shown = true;
	} else if (look == L_PULL) {
		// Void: a pixel drawn in from round about, spiralling in to the shot.
		life = 0.22 + 0.18 * th(id, j, 51.0);
		float a = clamp(ago / life, 0.0, 1.0);
		float ang = th(id, j, 52.0) * 6.2832 + a * (th(id, j, 53.0) < 0.5 ? -1.0 : 1.0) * (1.2 + th(id, j, 54.0));
		pos = target + vec2(cos(ang), sin(ang)) * (6.0 + 6.0 * th(id, j, 55.0)) * pow(1.0 - a, 1.4);
		rgb = shade4(SHADES[9], VOID_BASE, VOID_LIGHT, VOID_LIGHT, a);
		e = 0.7;
		shown = true;
	} else if (look == L_SPARKS) {
		// Lightning: a quick spark that jumps about every frame.
		life = 0.05 + 0.1 * th(id, j, 61.0);
		pos = at - dir * th(id, j, 62.0) * 10.0 + (vec2(th(id, frame, 63.0), th(id, frame, 64.0)) - 0.5) * 6.0;
		rgb = shade3(BONE_LIGHT, ARC_LIGHT, ARC_BASE, ago / life);
		e = 1.2;
		shown = true;
	} else if (look == L_MOTES) {
		// Mend: a mote that rises.
		life = 0.5 + 0.3 * th(id, j, 71.0);
		pos = at + (vec2(th(id, j, 72.0), th(id, j, 73.0)) - 0.5) * 4.0 + vec2(0.0, -14.0) * ago;
		rgb = ago / life < 0.5 ? ARC_LIGHT : ARC_BASE;
		e = 0.7;
		shown = true;
	} else if (look == L_GLINTS) {
		// Bigger: a glint that opens into a small cross and closes.
		life = 0.6;
		pos = at - dir * th(id, j, 81.0) * 6.0 + (vec2(th(id, j, 82.0), th(id, j, 83.0)) - 0.5) * 4.0;
		float u = ago / life;
		rgb = BONE_LIGHT;
		e = 0.8;
		shown = u > 0.2;
		vec2 d = abs(floor(P) - floor(pos));
		if (u > 0.35 && u < 0.6 && d.x + d.y == 1.0) {
			put(BONE_LIGHT, ago, colour, best);
		}
	} else if (look == L_STREAKS) {
		// Pierce: a thin streak left along the path.
		life = 0.25;
		pos = at;
		tip = at - dir * (2.0 + z);
		streak = true;
		rgb = BONE_LIGHT;
		e = 0.6;
		shown = true;
	} else if (look == L_BURST) {
		// Blast: a spark thrown out from where the shot was.
		life = 0.5;
		float ang = th(id, j, 91.0) * 6.2832;
		pos = at + vec2(cos(ang), sin(ang)) * (2.0 + 6.0 * ago / life) * z;
		rgb = ago / life < 0.5 ? FIRE_LIGHT : FIRE_BASE;
		e = 0.8;
		shown = true;
	} else if (look == L_ORBITERS) {
		// Shield: a spark circling the shot.
		life = 0.8;
		float ang = th(id, j, 101.0) * 6.2832 + ago * 5.0;
		pos = target + vec2(cos(ang), sin(ang)) * 4.5 * z;
		rgb = BONE_LIGHT;
		e = 0.6;
		shown = true;
	} else if (look == L_GLITTER) {
		// Hold: glitter that stays close to the shot and blinks.
		life = 0.5;
		float ang = th(id, j, 111.0) * 6.2832;
		pos = target + vec2(cos(ang), sin(ang)) * (2.5 + 1.5 * th(id, j, 112.0)) * z;
		rgb = SPARK_LIGHT;
		e = 0.6;
		shown = mod(frame + id, 6.0) < 3.0;
	} else if (look < 0.0) {
		// A plain shot's twinkle (look -1): a white-hot pixel left near the tail that rises and
		// blinks in the shot's colour.
		life = 0.3 + 0.3 * th(id, j, 121.0);
		pos = at - dir * th(id, j, 122.0) * 8.0 + (vec2(th(id, j, 123.0), th(id, j, 124.0)) - 0.5) * 4.0 + vec2(0.0, -6.0) * ago;
		rgb = shade3(BONE_LIGHT, hi, hi, ago / life);
		e = 0.7;
		shown = mod(frame + id * 3.0 + j, 7.0) >= 2.0;
	}
	if (ago >= life) {
		return;
	}
	float u = ago / life;
	float glow_e = e * (1.0 - 0.75 * u);
	float r = length(floor(P) + 0.5 - (floor(pos) + 0.5));
	lit += glow_e * (0.16 * falloff(r, 2.5) + 0.07 * falloff(r, 7.0));
	if (!shown) {
		return;
	}
	if (streak ? on_line(P, pos, tip) : on_pixel(P, pos, 1.0)) {
		put(rgb, ago, colour, best);
	}
}

// A wizard's dash, given off along its way (TF_DASH): speed streaks in the player's colours
// blown back past the body, and the dash's cards from its feet.
void dash_particle(float look, vec2 at, vec2 dir, float ago, float id, float j, vec2 P, float z, inout vec4 colour, inout float best, inout float lit) {
	int pi = int(player);
	vec2 side = vec2(-dir.y, dir.x);
	if (look == 0.0) {
		float life = 0.1 + 0.08 * th(id, j, 131.0);
		if (ago >= life) {
			return;
		}
		vec2 v = -dir * (60.0 + 50.0 * th(id, j, 132.0));
		vec2 pos = at + side * (th(id, j, 133.0) - 0.5) * 13.0 + dir * (th(id, j, 134.0) - 0.5) * 8.0 + v * ago;
		float u = ago / life;
		float r = length(floor(P) - floor(pos));
		lit += 0.4 * (1.0 - 0.75 * u) * 0.16 * falloff(r, 3.0);
		if (on_line(P, pos, pos - v * 0.025)) {
			put(u < 0.5 ? P_LIGHT[pi] : P_BASE[pi], ago, colour, best);
		}
		return;
	}
	// The cards from the feet: fire leaves flames on the floor, frost flecks that stay a while,
	// anything else its own particles round the body.
	vec2 feet = at + vec2(0.0, 8.0) + vec2((th(id, j, 135.0) - 0.5) * 8.0, (th(id, j, 136.0) - 0.5) * 2.0);
	if (look == L_EMBERS) {
		float life = 0.45 + 0.4 * th(id, j, 137.0);
		if (ago >= life) {
			return;
		}
		vec2 pos = feet + vec2(0.0, -(4.0 + 8.0 * th(id, j, 138.0)) * ago);
		float u = ago / life;
		float r = length(floor(P) - floor(pos));
		lit += (1.0 - 0.75 * u) * (0.16 * falloff(r, 2.5) + 0.07 * falloff(r, 7.0));
		if (th(id, floor(trail_now * 60.0), 139.0) >= 0.3 && on_pixel(P, pos, 1.0)) {
			put(shade4(SPARK_LIGHT, FIRE_LIGHT, FIRE_BASE, SHADES[0], u), ago, colour, best);
		}
	} else if (look == L_FLECKS) {
		float life = 0.6 + 0.4 * th(id, j, 140.0);
		if (ago >= life) {
			return;
		}
		vec2 pos = feet + vec2(0.0, -1.0);
		float u = ago / life;
		float r = length(floor(P) - floor(pos));
		lit += 0.8 * (1.0 - 0.75 * u) * (0.16 * falloff(r, 2.5) + 0.07 * falloff(r, 7.0));
		if (mod(floor(trail_now * 60.0) + id * 3.0 + j, 7.0) >= 2.0 && on_pixel(P, pos, 1.0)) {
			put(shade4(BONE_LIGHT, ICE_LIGHT, ICE_LIGHT, SHADES[7], u), ago, colour, best);
		}
	} else {
		trail_particle(look, at + side * (th(id, j, 141.0) - 0.5) * 10.0, dir, ago, id, j, P, at, z, colour, best, lit);
	}
}

// The kind given off by particle `j` born at moment `id`, or 0 for none: one of the shot's kinds,
// picked at random, each at its own rate (the mockup's); a plain shot's twinkle is -1. A dash
// gives off two speed streaks (kind 0) and its cards at twice a shot's rate.
float trail_kind(float id, float j, bool dash) {
	if (dash && j < 1.5) {
		return 0.0;
	}
	if (emit_count < 0.5) {
		return !dash && j < 0.5 && th(id, j, 151.0) < 0.18 * particle_share ? -1.0 : -2.0;
	}
	float look = emitter(int(min(floor(th(id, j, 152.0) * emit_count), emit_count - 1.0)));
	float rate = look == L_EMBERS ? 0.45 : (look == L_FLECKS ? 0.32 : (look == L_GUSTS ? 0.4 : (look == L_PULL ? 0.55 : (look == L_SPARKS ? 0.45 : 0.25))));
	if (dash) {
		rate = look == L_EMBERS ? 1.0 : (look == L_FLECKS ? 1.0 : min(rate * 2.0, 1.0));
	}
	return th(id, j, 153.0) < rate * particle_share ? look : -2.0;
}

// The tail pixels of the piece of path from `A` to `B` (each x, y, odometer, time; A the ago):
// one pixel per pixel of travel, thrown back a little, cooling as it ages. Adds the tail's light.
void trail_tail(vec4 A, vec4 B, vec2 P, float z, inout vec4 colour, inout float best, inout float lit) {
	vec2 ab = B.xy - A.xy;
	float len = length(ab);
	if (len < 0.001 || B.z - A.z < 0.001) {
		return;
	}
	vec2 dir = ab / len;
	float speed = len / max(B.w - A.w, 0.001);
	vec2 c = floor(P) + 0.5;
	float f = clamp(dot(c - A.xy, dir) / len, 0.0, 1.0);
	vec2 near = A.xy + ab * f;
	float dist = length(c - near);
	// What is back along the path from the head drifts at most a few pixels.
	float reach = 3.0 + z + speed * 0.012;
	if (dist > reach + 6.0) {
		return;
	}
	int pi = int(player);
	bool storm = has_layer(L_GUSTS);
	bool lightning = has_layer(L_SPARKS);
	// The light of the tail round its line, as bright as the tail is young there.
	float t_near = mix(A.w, B.w, f);
	float u_near = clamp((trail_now - t_near) / max(tail_life, 0.01), 0.0, 1.0);
	float glow_e = (has_layer(L_PULL) ? 0.45 : 0.75) * (1.0 - 0.75 * u_near) * (1.0 - u_near);
	lit = max(lit, glow_e * (0.32 * falloff(dist, 2.0 + z) + 0.36 * falloff(dist, 7.0 + 2.0 * z)));
	if (dist > reach) {
		return;
	}
	float o = mix(A.z, B.z, f);
	float drift = 0.04 * speed + 3.0;
	float span = ceil(drift * dragged(tail_life, 0.94) + 2.0 + z);
	for (float k = -span; k <= span; k += 1.0) {
		float n = floor(o) + k;
		if (n < A.z || n >= B.z) {
			continue;
		}
		if (lightning && th(n, 0.0, 161.0) > 0.35) {
			continue;
		}
		float fr = (n - A.z) / (B.z - A.z);
		float tn = mix(A.w, B.w, fr);
		float ago = trail_now - tn;
		float life = (0.1 + 0.2 * th(n, 0.0, 162.0)) / 0.3 * tail_life;
		if (ago < 0.0 || ago >= life) {
			continue;
		}
		vec2 base = mix(A.xy, B.xy, fr);
		vec2 v = -dir * speed * 0.04 + (vec2(th(n, 0.0, 163.0), th(n, 0.0, 164.0)) - 0.5) * 5.0;
		vec2 pos = base + (vec2(th(n, 0.0, 165.0), th(n, 0.0, 166.0)) - 0.5) * 0.8 + v * dragged(ago, 0.94);
		if (storm) {
			// Storm: the tail sways side to side as it is left.
			pos += vec2(-dir.y, dir.x) * sin(tn * 30.0) * 1.4;
		}
		if (!on_pixel(P, pos, max(z - 1.0, 1.0))) {
			continue;
		}
		float u = ago / life;
		vec3 rgb = u < 0.17 ? hot : (u < 0.45 ? hi : (u < 0.8 ? mid : lo));
		if (plain < 0.5 && th(n, 0.0, 167.0) < 0.25) {
			// A quarter of an infused tail is its player's colour.
			rgb = u < 0.25 ? P_LIGHT[pi] : (u < 0.75 ? P_BASE[pi] : P_SHADOW[pi]);
		}
		put(rgb, ago, colour, best);
	}
}

// The particles born on the piece of path from `A` to `B` (A the ago): one moment every
// 60th of a second, each moment up to `per` particles.
void trail_births(vec4 A, vec4 B, vec2 P, float z, float reach, bool dash, vec2 target, inout vec4 colour, inout float best, inout float lit) {
	vec2 ab = B.xy - A.xy;
	float len = length(ab);
	vec2 dir = len > 0.001 ? ab / len : vec2(1.0, 0.0);
	vec2 c = floor(P) + 0.5;
	float f = len > 0.001 ? clamp(dot(c - A.xy, dir) / len, 0.0, 1.0) : 0.0;
	bool near_path = length(c - (A.xy + ab * f)) <= reach;
	bool near_head = length(c - target) <= reach;
	if (!near_path && !near_head) {
		return;
	}
	float from = ceil(A.w * BIRTHS);
	float to = B.w * BIRTHS;
	float per = dash ? 3.0 : 1.0;
	for (int m = 0; m < 6; m++) {
		float id = from + float(m);
		if (id >= to) {
			break;
		}
		float t = id / BIRTHS;
		float ago = trail_now - t;
		if (ago < 0.0 || ago > trail_window) {
			continue;
		}
		vec2 at = mix(A.xy, B.xy, clamp((t - A.w) / max(B.w - A.w, 0.0001), 0.0, 1.0));
		for (float j = 0.0; j < 3.0; j += 1.0) {
			if (j >= per) {
				break;
			}
			float look = trail_kind(id, j, dash);
			if (look < -1.5) {
				continue;
			}
			bool round_head = look == L_PULL || look == L_ORBITERS || look == L_GLITTER;
			if (round_head ? !near_head && !(look == L_PULL && near_path) : !near_path) {
				continue;
			}
			if (dash) {
				dash_particle(look, at, dir, ago, id, j, P, z, colour, best, lit);
			} else {
				trail_particle(look, at, dir, ago, id, j, P, target, z, colour, best, lit);
			}
		}
	}
}

// The jagged line lightning draws behind its shot, from the head back along the last tenth of a
// second of its path: bends every 4 pixels, re-rolled every other frame.
bool lightning_tail(vec4 A, vec4 B, vec2 P, out bool newer) {
	newer = false;
	vec2 ab = B.xy - A.xy;
	float len = length(ab);
	if (len < 0.5) {
		return false;
	}
	vec2 dir = ab / len;
	vec2 c = floor(P) + 0.5;
	float along = dot(c - A.xy, dir);
	if (along < -0.5 || along > len + 0.5) {
		return false;
	}
	float o = A.z + along;
	float ago = trail_now - mix(A.w, B.w, clamp(along / len, 0.0, 1.0));
	if (ago > 0.1) {
		return false;
	}
	float node = floor(o / 4.0);
	float jf = floor(trail_now * 30.0);
	float o0 = (th(node, jf, 171.0) - 0.5) * 4.0;
	float o1 = (th(node + 1.0, jf, 171.0) - 0.5) * 4.0;
	float off = mix(o0, o1, fract(o / 4.0)) * min(ago / 0.02, 1.0);
	float s = dot(c - A.xy, vec2(-dir.y, dir.x)) - off;
	float thin = 0.5 * max(abs(dir.x), abs(dir.y));
	newer = ago < 0.05;
	return s >= -thin && s < thin;
}

vec4 trail_frag() {
	vec2 P = world;
	float z = zoom;
	bool live = flag_set(trail_flags, TF_HEAD);
	bool dash = flag_set(trail_flags, TF_DASH);
	vec2 reach = trail_reach(bits, trail_flags, z, tail_life);
	vec4 colour = vec4(0.0);
	float best = 1e9;
	float lit = 0.0;
	float tail_lit = 0.0;
	bool lightning = has_layer(L_SPARKS);
	vec4 B = vec4(trail_head, 0.0, trail_now);
	// Where the shot is (or was last): the void pulls in to it, shields circle it.
	vec2 target = trail_head;
	bool started = false;
	for (int j = 0; j < TRAIL_SAMPLES; j++) {
		if (float(j) >= trail_count) {
			break;
		}
		vec4 A = trail_texel(trail_row, trail_newest, float(j));
		if (A.w > trail_now + 0.0001) {
			continue;
		}
		if (!started) {
			started = true;
			if (live) {
				B.z = A.z + distance(trail_head, A.xy);
			} else {
				B = A;
				target = A.xy;
				continue;
			}
		}
		if (trail_now - B.w > trail_window) {
			break;
		}
		if (!dash) {
			trail_tail(A, B, P, z, colour, best, tail_lit);
			if (lightning) {
				bool newer;
				if (lightning_tail(A, B, P, newer)) {
					put(newer ? ARC_LIGHT : ARC_BASE, 0.0, colour, best);
				}
			}
		}
		trail_births(A, B, P, z, reach.y, dash, target, colour, best, lit);
		B = A;
	}
	lit += tail_lit;
	if (live && !dash) {
		// The core: a white-hot pixel with four round it, a pixel more each side a zoom; pierce
		// lengthens it along the flight; homing weaves it a pixel either side; void's is a dark
		// heart ringed in pink.
		vec2 head = trail_head;
		vec4 last = trail_count > 0.0 ? trail_texel(trail_row, trail_newest, 0.0) : vec4(head - vec2(1.0, 0.0), 0.0, 0.0);
		vec2 fly = head - last.xy;
		fly = length(fly) > 0.01 ? normalize(fly) : vec2(1.0, 0.0);
		if (has_layer(L_WEAVE)) {
			head += vec2(-fly.y, fly.x) * (triangle(sim_time * 3.0 + seed * 0.25) > 0.0 ? 1.0 : 0.0);
		}
		vec2 d = floor(P) - floor(head);
		float arm = z;
		float m = abs(d.x) + abs(d.y);
		bool cross_px = (d.x == 0.0 || d.y == 0.0) && m <= arm;
		if (has_layer(L_STREAKS)) {
			// Pierce: the core runs on a pixel or two along the flight.
			cross_px = cross_px || on_line(P, head, head - fly * (2.0 + arm));
		}
		if (has_layer(L_PULL)) {
			if (m == 0.0) {
				colour = vec4(OUTLINE, 1.0);
			} else if (cross_px) {
				colour = vec4(VOID_LIGHT, 1.0);
			} else if (abs(d.x) == 1.0 && abs(d.y) == 1.0) {
				colour = vec4(VOID_BASE, 1.0);
			}
		} else if (cross_px) {
			colour = vec4(m < 0.5 ? hot : hi, 1.0);
		}
		float r = length(floor(P) + 0.5 - (floor(head) + 0.5));
		lit += 0.8 * falloff(r, 3.0 + z) + 0.35 * falloff(r, 8.0 + 2.0 * z);
	}
	if (colour.a > 0.0) {
		return colour;
	}
	float dark = 0.0;
	if (lightning) {
		// Lightning flickers.
		lit *= 0.55 + 0.9 * hash(floor(sim_time * 20.0), 0.0, 21.0);
	}
	if (has_layer(L_PULL)) {
		// Void pulls the light down round its heart.
		lit *= 0.6;
		if (live && !dash) {
			dark = 0.45 * falloff(length(floor(P) - floor(trail_head)), 6.0);
		}
	}
	vec3 hue = dash ? P_BASE[int(player)] : glow;
	return vec4(hue * lit * glow_strength, dark);
}

void fragment() {
	if (beam_mode == 1) {
		float along = UV.x * (beam_length + 2.0 * beam_lead) - beam_lead;
		COLOR = beam(along, (UV.y - 0.5) * beam_width, cheb_of(along), world);
	} else if (beam_mode == 2) {
		float along = UV.x / TEXTURE_PIXEL_SIZE.x - beam_lead;
		COLOR = beam(along, UV.y / TEXTURE_PIXEL_SIZE.y - 0.5 / TEXTURE_PIXEL_SIZE.y, cheb_of(along), world);
	} else if (kind > 3.5) {
		COLOR = effect(UV);
	} else if (kind > 0.5 && kind < 1.5) {
		COLOR = trail_frag();
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
