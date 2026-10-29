// SPDX-License-Identifier: GPL-3.0-or-later
shader_type canvas_item;
render_mode blend_premul_alpha;

// Feel's flashes (gameplay/feel/feel.gd, its effect batch; core/README.md, "The shot shaders"), in
// a square GRID x zoom pixels across, +x along their aim, all in the ramp and look of the shot
// they come from; the age is the code beside the kind (`coded_age`). Blending is premultiplied: a
// pixel is opaque, the glow round it light added to what is below.
//   K_BURST       where a shot lands: a white-hot cross that shrinks, sparks thrown back
//                 against the flight that cool as they fly, and the shot's card particles
//   K_RING_OUT    a ring that flashes out (a nova's cast)
//   K_RING_IN     a ring that gathers in (a rune's or orbit's cast)
//   K_RUNE_BURST  a rune going off: a dotted flash over the diamond, a diamond ring widening
//                 to twice its size, sparks all round
//   K_CAST        the staff tip on a cast: a small cross and a few sparks along the aim
//   K_DASH        the dust of a wizard's dash where it started (the effect's place); its way is
//                 the caster's trail (TF_DASH in shot_trail.gdshader) and its landing Feel's
//                 ring; its square is zoom x 4 pixels plus DASH_MARGIN each end, DASH_ACROSS across
//   K_SPRAY       a hit on a character: sparks thrown on along the hit's way, cooling
//   K_PUFF        sparks all round and a dotted white-hot puff (a kill, a reaction, a hit
//                 with no way); with the POOF bit (kind 22) a staff's personality swap instead
//                 (living staffs H4): bone clouds along the staff (+x) that swell to their
//                 biggest at 35% of the effect (where the body changes) and shrink away, and a
//                 few sparks in the player's colour
//   K_CHIPS       stone chips knocked back off a wall, falling; stone does not glow
//   K_QUAKE       a slam's mark on the floor (Feel's floor batch, under the bodies): cracks out from
//                 the impact, white-hot and cooling to dark stone, a glow on the floor, rubble
//                 thrown up that lands and lies, dust rolling out along the floor; its reach is
//                 QUAKE_REACH x zoom pixels
// Lightning (K_ARC) and statuses (K_STATUS) have shaders and batches of their own.
//
// PARTICLES ARE GEOMETRY (as in `shot_trail.gdshader`; the owner, 2026-10-29): an effect is one
// instance of a mesh of small quads (`Feel.effect_mesh`), each told in its UV which QUAD KIND
// (Q_*) and slot it is. The vertex stage works out what that slot is now and puts its quad round
// it alone (in the effect's own pixels, so they turn with its aim), or folds it away; the
// fragment stage only colours a pixel of its own quad, in a few small modes with no loops:
//   Q_LIGHT     the effect's glow, over its whole square (added; drawn first)
//   Q_PARTICLE  one of the shot's card particles (`place_particle`), the newest on top
//   Q_SPARK     a spark (or a chip, or a speck of a dash's dust); the first is on top
//   Q_CLOUD     one of a poof's bone clouds; the first is on top
//   Q_SHAPE     the flash: a cross, a dotted disc, a fraying ring (drawn last, on top); a quake's
//               cracks
// The instance's square is drawn from the mesh's own corners: a pixel `d` (whole pixels from the
// middle; from where a dash left) is at UV (d + o) / size of the square, as a QuadMesh has it.

#include "res://core/projectiles/shot_palette.gdshaderinc"
#include "res://core/projectiles/shot_look.gdshaderinc"
#include "res://core/projectiles/shot_particle.gdshaderinc"

const float GRID = 24.0;
const float DASH_MARGIN = 12.0;
const float DASH_ACROSS = 32.0;
// A rune's reach at its rest (the 14 px of rune.tres, as `shot_rune.gdshader` draws it at zoom 4).
const float RUNE_REACH = 14.4;
// The floor batch's kind (KIND_QUAKE in gameplay/feel/feel.gd): below K_BURST, where the shots'
// kinds are, which never come to this shader.
const float K_QUAKE = 3.0;
// A quake's reach per zoom in pixels, its cracks, the share of its life its rubble flies, and how
// flat the floor is seen (y over x).
const float QUAKE_REACH = 8.0;
const float QUAKE_CRACKS = 7.0;
const float QUAKE_FLIGHT = 0.3;
const float QUAKE_FLAT = 0.6;
// The quad kinds (EFFECT_Q_* in gameplay/feel/feel.gd), in UV.y, and the slots of each.
const float Q_LIGHT = 0.0;
const float Q_PARTICLE = 1.0;
const float Q_SPARK = 2.0;
const float Q_CLOUD = 3.0;
const float Q_SHAPE = 4.0;
// The fragment's modes.
const float M_LIGHT = 0.0;
const float M_PIXELS = 1.0;
const float M_CLOUD = 2.0;
const float M_SHAPE = 3.0;
const float M_CRACK = 4.0;

// What the vertex stage hands a pixel (by mode; see `fragment`): where it is in the effect's
// pixels, the mode, three numbers and three colours.
varying vec2 px;
varying flat float mode;
varying flat vec4 v0;
varying flat vec4 v1;
varying flat vec4 v2;
varying flat vec4 c0;
varying flat vec4 c1;
varying flat vec4 c2;

// ---- Vertices ----

// The ramp of look `L` at `u` (0 white-hot, 1 shadow), as `ramp` has it.
vec3 ramp_of(Look L, float u) {
	return u < 0.15 ? L.hot : (u < 0.4 ? L.hi : (u < 0.7 ? L.mid : L.lo));
}

// Spark `n` of an effect of `kind` at age `a`: shown or not, its pixel, a run of more pixels to
// its right (a chip's second), its colour.
struct Spark {
	bool shown;
	vec2 at;
	float run;
	vec3 rgb;
};

Spark effect_spark(float kind, float n, float a, float ease, float z, Look L) {
	Spark S;
	S.shown = false;
	S.at = vec2(0.0);
	S.run = 0.0;
	S.rgb = vec3(0.0);
	float s = L.seed;
	float i = n;
	vec2 at = vec2(0.0);
	if (kind == K_BURST || kind == K_CAST) {
		// Sparks thrown back against the flight (along the aim from a staff), cooling as they fly.
		bool cast = kind == K_CAST;
		float life = 0.5 + 0.5 * hash_seeded(i, 1.0, 31.0, s);
		float ang = (cast ? 0.0 : 3.1416) + (hash_seeded(i, 2.0, 31.0, s) - 0.5) * (cast ? 1.0 : 2.8);
		float reach = (1.5 + (cast ? 6.0 : 10.0) * (0.6 + 0.4 * hash_seeded(i, 3.0, 31.0, s)) * ease) * z;
		S.shown = n < (cast ? 4.0 : 8.0) && a <= life;
		at = vec2(cos(ang), sin(ang)) * reach;
		S.rgb = ramp_of(L, a / life);
	} else if (kind == K_RUNE_BURST) {
		// Sparks all round.
		float ang = i * 0.3927 + (hash_seeded(i, 4.0, 31.0, s) - 0.5) * 0.4;
		float reach = (4.0 + 26.0 * (0.6 + 0.4 * hash_seeded(i, 5.0, 31.0, s)) * ease);
		S.shown = a < 0.8;
		at = vec2(cos(ang), sin(ang)) * reach;
		S.rgb = ramp_of(L, a);
	} else if (kind == K_PUFF && bit_set(L.bits, POOF)) {
		// A poof's sparks in the player's colour, flung wide.
		float ang = i / 6.0 * 6.2832 + hash_seeded(i, 19.0, 31.0, s);
		float reach = (4.0 + 6.0 * hash_seeded(i, 20.0, 31.0, s) * ease) * z;
		S.shown = n < 6.0 && a < 0.8;
		at = vec2(cos(ang) * 1.6, sin(ang)) * reach;
		S.rgb = a < 0.4 ? L.hi : L.mid;
	} else if (kind == K_SPRAY || kind == K_PUFF) {
		// Sparks thrown on along the hit's way, or all round.
		bool round_about = kind == K_PUFF;
		float life = 0.5 + 0.5 * hash_seeded(i, 11.0, 31.0, s);
		float ang = round_about ? i / 14.0 * 6.2832 + (hash_seeded(i, 12.0, 31.0, s) - 0.5) * 0.4 : (hash_seeded(i, 12.0, 31.0, s) - 0.5) * 1.6;
		float reach = (2.0 + (round_about ? 10.0 : 13.0) * (0.5 + 0.5 * hash_seeded(i, 13.0, 31.0, s)) * ease) * z;
		S.shown = n < (round_about ? 14.0 : 10.0) && a <= life;
		at = vec2(cos(ang), sin(ang)) * reach;
		S.rgb = ramp_of(L, a / life);
	} else if (kind == K_CHIPS) {
		// Stone chips knocked back off the wall, falling down the screen as they fly; no glow.
		float ang = (hash_seeded(i, 14.0, 31.0, s) - 0.5) * 2.2;
		float reach = (2.0 + 9.0 * (0.5 + 0.5 * hash_seeded(i, 15.0, 31.0, s)) * ease) * z;
		S.shown = n < 7.0 && a < 0.9;
		at = vec2(cos(ang), sin(ang)) * reach + vec2(0.0, 7.0 * a * a * z);
		S.run = hash_seeded(i, 16.0, 31.0, s) < 0.4 ? 1.0 : 0.0;
		S.rgb = a < 0.3 ? STONE_LIGHT : (a < 0.65 ? STONE_BASE : STONE_SHADOW);
	} else if (kind == K_DASH) {
		// The dust kicked up where it left, both ways along the floor.
		float travel = min(a / 0.45, 1.0);
		float way = hash_seeded(i, 9.0, 51.0, s) < 0.5 ? -1.0 : 1.0;
		S.shown = n < 6.0 && a < 0.5;
		at = vec2(way * (1.0 + 9.0 * hash_seeded(i, 4.0, 51.0, s)) * travel, 8.0 - 3.0 * hash_seeded(i, 5.0, 51.0, s) * travel);
		S.rgb = a < 0.25 ? STONE_LIGHT : STONE_BASE;
	} else if (kind == K_QUAKE && n < 8.0) {
		// Rubble thrown up all round, landing on the floor and lying there until it fades.
		float reach = QUAKE_REACH * z;
		float ang = i / 8.0 * 6.2832 + (hash_seeded(i, 40.0, 31.0, s) - 0.5) * 0.6;
		float far = reach * (0.35 + 0.55 * hash_seeded(i, 41.0, 31.0, s));
		float t = min(a / QUAKE_FLIGHT, 1.0);
		float high = (2.0 + 2.5 * hash_seeded(i, 42.0, 31.0, s)) * z;
		S.shown = a < 0.75 || hash_seeded(i, 43.0, 31.0, s) > (a - 0.75) / 0.2;
		at = vec2(cos(ang), sin(ang) * QUAKE_FLAT) * far * (1.0 - (1.0 - t) * (1.0 - t)) - vec2(0.0, 4.0 * t * (1.0 - t) * high);
		S.run = hash_seeded(i, 44.0, 31.0, s) < 0.5 ? 1.0 : 0.0;
		S.rgb = t < 1.0 ? BONE_BASE : STONE_LIGHT;
	} else if (kind == K_QUAKE) {
		// Dust rolling out along the floor, slowing, rising a little as it thins.
		float reach = QUAKE_REACH * z;
		float ang = (i - 8.0) / 8.0 * 6.2832 + hash_seeded(i, 45.0, 31.0, s) * 0.5;
		float roll = 1.0 - pow(1.0 - min(a / 0.6, 1.0), 3.0);
		S.shown = a < 0.6 && hash_seeded(i, 46.0, 31.0, s) > (a - 0.4) / 0.2;
		at = vec2(cos(ang), sin(ang) * QUAKE_FLAT) * reach * (0.3 + 1.0 * roll) - vec2(0.0, roll * z);
		S.run = 2.0;
		S.rgb = a < 0.25 ? BONE_SHADOW : STONE_LIGHT;
	}
	S.at = floor(at + 0.5);
	return S;
}

void vertex() {
	float kind = coded_kind(INSTANCE_CUSTOM.a);
	float a = coded_age(coded_code(INSTANCE_CUSTOM.a));
	Look L = look_from_color(COLOR, INSTANCE_CUSTOM.rgb, float(INSTANCE_ID % 61) * 1.618, true);
	float z = L.zoom;
	float s = L.seed;
	float ease = 1.0 - (1.0 - a) * (1.0 - a);
	bool poof = kind == K_PUFF && bit_set(L.bits, POOF);
	// The square in pixels, and where its pixel 0 is.
	vec2 size = vec2(GRID) * z;
	vec2 o = size * 0.5;
	if (kind == K_DASH) {
		size = vec2(z * 4.0 + 2.0 * DASH_MARGIN, DASH_ACROSS);
		o = vec2(DASH_MARGIN, size.y * 0.5);
	}
	// The mesh's vertex: its slot and corner in UV.x (slot + 0.25 or 0.75), its quad kind and
	// corner in UV.y (kind + 0.25 or 0.75).
	float slot = floor(UV.x);
	float quad = floor(UV.y);
	vec2 corner = vec2(fract(UV.x) > 0.5 ? 1.0 : 0.0, fract(UV.y) > 0.5 ? 1.0 : 0.0);
	vec2 q_lo = vec2(0.0);
	vec2 q_hi = vec2(0.0);
	bool shown = false;
	float m = M_PIXELS;
	vec4 a0 = vec4(0.0);
	vec4 a1 = vec4(0.0);
	vec4 a2 = vec4(0.0);
	vec4 k0 = vec4(0.0);
	vec4 k1 = vec4(0.0);
	vec4 k2 = vec4(0.0);
	bool glows = kind != K_CHIPS && kind != K_DASH;
	if (quad == Q_LIGHT || quad == Q_SHAPE) {
		// The flash and its light: a1 the light's two falloffs (how bright, how far: x of the
		// distance from a0.y, y of the distance), a0.x 1 for a diamond (the rune's) instead of a
		// circle; a0.yzw the cross's arms, the dotted disc's and the ring's reach (-1 for none).
		float k = 1.0;
		float metric = 0.0;
		float arm = -1.0;
		float disc = -1.0;
		float ring = -1.0;
		float salt = 32.0;
		vec4 lit = vec4(0.0, 1.0, 0.0, 1.0);
		vec3 first = vec3(0.0);
		vec3 second = vec3(0.0);
		if (kind == K_BURST || kind == K_CAST) {
			// A white-hot cross that shrinks.
			arm = round((kind == K_CAST ? 1.5 : 2.0) * z * (1.0 - a * 2.5));
			first = L.hot;
			second = L.hi;
			k = (1.0 - a) * (1.0 - a);
			lit = vec4(0.9, 4.0 * z, 0.4, 10.0 * z);
		} else if (kind == K_RING_OUT || kind == K_RING_IN) {
			// A ring that flashes out or gathers in, fraying as it goes.
			float big = 10.0 * z;
			float small = 2.0 * z;
			ring = kind == K_RING_OUT ? mix(small, big, ease) : mix(big, small, ease);
			second = ramp_of(L, a);
			k = 1.0 - a;
			lit = vec4(0.5, 3.0 * z, 0.0, 1.0);
		} else if (kind == K_RUNE_BURST) {
			// A dotted white-hot flash over the diamond, then a diamond ring that widens and frays.
			metric = 1.0;
			disc = a < 0.2 ? RUNE_REACH : -1.0;
			ring = mix(RUNE_REACH, RUNE_REACH * 2.2, ease);
			salt = 33.0;
			first = a < 0.1 ? L.hot : L.hi;
			second = ramp_of(L, a);
			k = 1.0 - a;
			lit = vec4(0.5, 6.0, a < 0.25 ? 0.8 : 0.0, RUNE_REACH);
		} else if (poof) {
			// Only a soft light: its clouds are quads of their own.
			k = 1.0 - a;
			lit = vec4(0.3, 6.0 * z, 0.0, 1.0);
		} else if (kind == K_SPRAY || kind == K_PUFF) {
			// A small white-hot cross where it struck, or a dotted puff.
			if (kind == K_PUFF) {
				disc = a < 0.18 ? 2.0 * z : -1.0;
				first = a < 0.09 ? L.hot : L.hi;
			} else {
				arm = a < 0.2 ? 1.0 : -1.0;
				first = L.hot;
				second = L.hot;
			}
			k = (1.0 - a) * (1.0 - a);
			lit = vec4(0.7, 3.0 * z, 0.3, 9.0 * z);
		} else if (kind == K_QUAKE) {
			// A glow on the floor round the impact, gone well before the cracks cool.
			k = max(1.0 - a * 2.5, 0.0);
			k *= k;
			lit = vec4(0.8, QUAKE_REACH * z * 0.6, 0.0, 1.0);
		}
		bool quake = kind == K_QUAKE;
		shown = glows && (quad == Q_LIGHT || arm >= 0.0 || disc >= 0.0 || ring >= 0.0 || quake);
		q_lo = -o;
		q_hi = size - o;
		if (quad == Q_LIGHT) {
			m = M_LIGHT;
			a0 = vec4(metric, ring < 0.0 ? 0.0 : ring, k * (bit_set(L.bits, L_PULL) ? 0.6 : 1.0), 0.0);
			a1 = lit;
			k0 = vec4(L.glow, 1.0);
		} else if (quake) {
			// The cracks: their reach, the age and seed, and the ramp they cool down.
			m = M_CRACK;
			a0 = vec4(QUAKE_REACH * z, a, s, 0.0);
			a2 = vec4(L.lo, 0.0);
			k0 = vec4(L.hot, 1.0);
			k1 = vec4(L.hi, 1.0);
			k2 = vec4(L.mid, 1.0);
		} else {
			m = M_SHAPE;
			a0 = vec4(metric, arm, disc, ring);
			a1 = vec4(salt, a, s, 0.0);
			k0 = vec4(first, 1.0);
			k1 = vec4(second, 1.0);
		}
	} else if (quad == Q_SPARK) {
		Spark S = effect_spark(kind, slot, a, ease, z, L);
		shown = S.shown;
		q_lo = S.at - 1.0;
		q_hi = S.at + vec2(S.run + 2.0, 2.0);
		a0 = vec4(S.at, S.run, 0.0);
		k0 = vec4(S.rgb, 1.0);
	} else if (quad == Q_CLOUD && poof) {
		// A staff's poof: four bone clouds along the staff, biggest at 35%, dotted as they go.
		float swell = a < 0.35 ? a / 0.35 : 1.0 - (a - 0.35) / 0.65;
		vec2 c = vec2((slot - 1.5) * 6.0, (hash_seeded(slot, 17.0, 31.0, s) - 0.5) * 3.0) * z * 0.5;
		float reach = (2.5 + 1.5 * hash_seeded(slot, 18.0, 31.0, s)) * swell * z * 0.5 + 0.5;
		shown = true;
		m = M_CLOUD;
		q_lo = floor(c - reach) - 1.0;
		q_hi = floor(c + reach) + 2.0;
		a0 = vec4(c, reach, a < 0.7 ? 0.0 : 1.0);
	} else if (quad == Q_PARTICLE && glows && kind != K_CAST && kind != K_QUAKE) {
		// The shot's cards: its particles, set off from round the middle at the start.
		float n = L.emits.w;
		float count = min(4.0 + 2.0 * n, float(MAX_PARTICLES));
		float i = slot;
		float spread = kind == K_RUNE_BURST ? RUNE_REACH : 2.0 * z;
		float pick = min(floor(hash_seeded(i, 6.0, 31.0, s) * n), n - 1.0);
		float word = pick < 4.0 ? L.emits.x : (pick < 8.0 ? L.emits.y : L.emits.z);
		float look = mod(floor(word / exp2(mod(pick, 4.0) * 4.0) + 0.001), 16.0);
		float ang = hash_seeded(i, 7.0, 31.0, s) * 6.2832;
		vec2 from = vec2(cos(ang), sin(ang)) * spread * hash_seeded(i, 8.0, 31.0, s);
		float pa = (a - 0.3 * hash_seeded(i, 9.0, 31.0, s)) / 0.7;
		if (n > 0.5 && i < count && pa > 0.0 && pa < 1.0) {
			Particle p = place_particle(look, from, pa, i, 0.0, z, s);
			vec2 at = floor(p.at);
			shown = p.shown;
			q_lo = at - 1.0;
			q_hi = at + vec2(p.run + 2.0, 2.0);
			a0 = vec4(at, p.run, p.arm);
			a1 = vec4(p.extra, 0.0, 0.0);
			k0 = vec4(p.rgb, 1.0);
			k1 = vec4(p.arm_rgb, 1.0);
		}
	}
	// Nothing outside the square, as one quad over it would have it.
	q_lo = max(q_lo, -o);
	q_hi = min(q_hi, size - o);
	shown = shown && all(lessThan(q_lo, q_hi));
	vec2 p = mix(q_lo, q_hi, corner);
	vec2 uv = (p + o) / size;
	// Folded away when there is nothing to draw.
	VERTEX = shown ? vec2(uv.x - 0.5, 0.5 - uv.y) : vec2(0.0);
	px = p;
	mode = m;
	v0 = a0;
	v1 = a1;
	v2 = a2;
	c0 = k0;
	c1 = k1;
	c2 = k2;
}

// ---- Fragments ----
// Small on purpose (core/README.md, "The shot shaders"): a pixel only colours itself from what
// its quad's vertices worked out. No loops, no look kinds.

void fragment() {
	vec2 d = floor(px);
	vec4 colour = vec4(0.0);
	// Its distance from the middle: round, or a diamond's (v0.x).
	float r = v0.x > 0.5 ? abs(d.x) + abs(d.y) : length(d);
	if (mode < M_LIGHT + 0.5) {
		// The light: v0.z x (v1.x falloff from the ring at v0.y over v1.y, v1.z falloff over v1.w).
		float lit = v0.z * (v1.x * falloff(abs(r - v0.y), v1.y) + v1.z * falloff(r, v1.w));
		colour = vec4(c0.rgb * lit * glow_strength, 0.0);
	} else if (mode < M_PIXELS + 0.5) {
		// A spark or a particle: the pixel v0.xy, a run of v0.z to its right, a cross of arms v0.w
		// in c1, a pixel more at v1.xy.
		Particle p;
		p.shown = true;
		p.at = v0.xy;
		p.run = v0.z;
		p.arm = v0.w;
		p.extra = v1.xy;
		p.rgb = c0.rgb;
		p.arm_rgb = c1.rgb;
		colour = particle_pixel(p, d);
	} else if (mode < M_CLOUD + 0.5) {
		// A bone cloud round v0.xy of reach v0.z, lit from the top-left: light on that side,
		// shadow on the far rim; dotted (v0.w) as it goes.
		vec2 c = v0.xy;
		float reach = v0.z;
		float q = length(d - c);
		if (q <= reach && (v0.w < 0.5 || mod(d.x + d.y, 2.0) == 0.0)) {
			vec2 side = (d - c) / max(reach, 1.0);
			colour = vec4(side.x + side.y < -0.5 ? BONE_LIGHT : (q > reach - 1.0 && side.x + side.y > 0.3 ? BONE_SHADOW : BONE_BASE), 1.0);
		}
	} else if (mode < M_SHAPE + 0.5) {
		// The flash: a dotted disc of reach v0.z in c0, a ring at v0.w in c1 fraying with the age
		// v1.y (its hash salt v1.x, seed v1.z), a cross of arms v0.y (white-hot c0 in the middle).
		if (v0.z >= 0.0 && r <= v0.z && mod(d.x + d.y, 2.0) == 0.0) {
			colour = c0;
		}
		float bucket = floor(atan(d.y, d.x) * v0.w / 2.0);
		if (v0.w >= 0.0 && abs(r - v0.w) < 0.5 && hash_seeded(bucket, floor(v1.y * 8.0), v1.x, v1.z) > v1.y * 0.7) {
			colour = c1;
		}
		if (v0.y >= 0.0 && ((d.x == 0.0 && abs(d.y) <= v0.y) || (d.y == 0.0 && abs(d.x) <= v0.y))) {
			colour = d.x == 0.0 && d.y == 0.0 ? c0 : c1;
		}
	} else {
		// A quake's cracks, on a floor seen flat: the crack nearest the pixel's way (one of
		// QUAKE_CRACKS round about, each turned and as long as its hash says, v0.x at most), its
		// line measured in whole pixels, jagged every 4 px, 2 px wide near the middle with a dark
		// rim (cut into the floor), dotted at the tip. They open at once, white-hot (c0), cool
		// from the tips in through c1, c2, v2 to dark stone, and crumble away.
		float s = v0.z;
		float a = v0.y;
		vec2 e = vec2(d.x, d.y / QUAKE_FLAT);
		float k = floor(atan(e.y, e.x) / 6.2832 * QUAKE_CRACKS + 0.5);
		float way = (k + (hash_seeded(k, 50.0, 31.0, s) - 0.5) * 0.5) * 6.2832 / QUAKE_CRACKS;
		vec2 u = vec2(cos(way), sin(way) * QUAKE_FLAT);
		float flat_len = length(u);
		u /= flat_len;
		float along = dot(d, u);
		float reach = v0.x * flat_len * (0.6 + 0.4 * hash_seeded(k, 51.0, 31.0, s)) * min(a / 0.04, 1.0);
		float rung = max(along, 0.0) / 4.0;
		float jag = mix(hash_seeded(k, floor(rung), 52.0, s), hash_seeded(k, floor(rung) + 1.0, 52.0, s), fract(rung)) - 0.5;
		float side = abs(u.x * d.y - u.y * d.x - jag * min(along, 10.0) * 0.5);
		float wide = along < reach * 0.4 ? 1.0 : 0.6;
		bool inside = along > 1.5 && along <= reach && (along < reach * 0.8 || mod(d.x + d.y, 2.0) == 0.0);
		bool crack = inside && side < wide;
		bool rim = inside && !crack && side < wide + 1.0 && along < reach * 0.6;
		bool kept = a < 0.7 || hash_seeded(d.x, d.y, 53.0, s) > (a - 0.7) / 0.3;
		float heat = a * 1.5 + along / max(reach, 1.0) * 0.4;
		vec3 rgb = heat < 0.12 ? c0.rgb : (heat < 0.3 ? c1.rgb : (heat < 0.5 ? c2.rgb : (heat < 0.7 ? v2.rgb : STONE_SHADOW)));
		colour = kept && crack ? vec4(rgb, 1.0) : (kept && rim ? vec4(STONE_SHADOW, 1.0) : vec4(0.0));
	}
	COLOR = colour;
}
