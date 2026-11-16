// SPDX-License-Identifier: GPL-3.0-or-later
shader_type canvas_item;
render_mode blend_premul_alpha;

// A pool (content/spells/carriers/pool/; redesigned for the owner, 2026-11-16: "it should be drawn
// on the floor", "overlapping pools should be merged into one", "more flat", "more like something
// has been spilled on the floor"): its infusion spilled on the floor at its hit size, seen from
// above at a slant. It is drawn at the floor's z (its card's `look_on_floor`), under every body and
// over the floor's marks.
//
// A spill, not an oval, spat out of the wand (the owner, 2026-11-16: "like the wand spitting out
// the elements the pool is made of"): its outline is its oval reaching further the way it was
// thrown (its facing, `ProjectileManager.set_facing`, the way its quad turns) and pushed in and out
// by a noise over world pixels (big lobes and small bumps), so no two pools have one shape, and a
// creeping pool's shape flows as it moves instead of jumping; drops it threw lie round it, most and
// furthest ahead, streaked the way they flew, fewer and smaller further out.
//
// The pools that overlap are one spill (its card's `look_merges`): the projectile manager tells
// both batches of its body one list of every pool drawn this frame, in one order (`StillMerge`:
// the hat ramps' then the enemy ramp's; this batch's first at `merge_first`). Each pool picks the
// few near enough to reach its quad once, in vertex(), and a pixel takes the soft union of their
// outlines (a sum, the same in any order and with any far pool left out: a bridge of liquid
// between near ones) and is drawn by the pool nearest it (of two as near, the first listed), in
// its colours, so no pixel is drawn twice. Everything is worked out in world pixels, interpolated
// from the quad's corners, so two pools agree pixel for pixel.
//
// Its liquid, between thick and flat (the owner, 2026-11-16: "a mix"): an edge one pixel wide
// (catching the light along its far side, its base elsewhere: no shaded lip, which made it read as
// standing on the floor), a film of its base lightened the floor shows through, thicker and
// darker by a dither in its middle. Over it, in world space so they run on across merged pools: light lines
// slowly shifting (a warped noise, in its other infusions in turn by a slow noise: the first's
// with one), ripples spreading and fading (flattened by the slant) and glints of white-hot
// twinkling. It is spat out of the staff (its card's `shown_cue`, `pool_throw`: blobs of it and
// its spell's motes flying out as far as it lies) and lies there once they land, ARRIVE seconds
// on. It splashes in while it is new (it overshoots and settles; the drops it throws are
// motes too, its card's `look_motes`, off its rim for its first moments) and dries out over its
// last second, pulling back from its outline to its middle and leaving a wet stain that fades.
// Its card particles are given off from its outline; a faint light lies round it, gone as it
// dries. The motes rising off it (the owner, 2026-11-09: "this needs more motes!") are real motes,
// its card's `look_motes` (`rising`), given off by Feel from where its shots are drawn
// (gameplay/feel/still_motes.gd).
// Every infusion shows (its palette, `palette_turn`): its liquid is the first's, and its light
// lines run in the others.
// It knows its time since it was placed and its life left from its still clock (`still_since`,
// `still_left`: the code beside its kind, `ProjectileManager.still_code`). Its quad is GRID x zoom
// pixels square round its centre, from the projectile manager's instance data as a rune's
// (`ProjectileManager._write_quad`). Blending is premultiplied: the glow is added light. Drawn by its
// card's pair of batches (`CarrierCard.look_shader`, `ProjectileManager.register_body`), warmed
// before the first room.

#include "res://core/projectiles/shot_palette.gdshaderinc"
#include "res://core/projectiles/shot_look.gdshaderinc"
#include "res://core/projectiles/shot_particle.gdshaderinc"

// The spark pool's share (set by the projectile manager, 1.0 is everything): the fraction of
// every shot's particles drawn this frame.
uniform float particle_share = 1.0;

const float GRID = 24.0;
// Its oval's half width and half depth in its hit size as drawn (STILL_HIT), its card's `look_shape`
// (set by the projectile manager, `set_body_shape`), so its motes leave from the oval it draws. Its
// come and go are its own (the splash, the drying), not the card's `look_clock`. The default only
// draws a body no card has shaped yet.
uniform vec2 look_shape = vec2(1.0, 1.0);

// Every pool of its body drawn this frame, both batches' in one order (`StillMerge`, set by the
// projectile manager): x, y its middle in world pixels, z its hit size as drawn, w its still
// clock's code plus its facing in whole steps of FACING_STEPS a turn (`code_of`, `facing_of`). This batch's pools start at `merge_first` (a pool's own entry is
// `merge_first + INSTANCE_ID`). None: drawn alone, as a pool past MERGE_MOST is.
const int MERGE_MOST = 64;
const float FACING_STEPS = 64.0;
// How much further it reaches ahead (and less behind), as a part of its size.
const float THROW = 0.25;
uniform int merge_count = 0;
uniform int merge_first = 0;
uniform vec4 merge_place[MERGE_MOST];

// The most other pools a pool runs together with (picked in vertex(), the nearest listed first).
const int NEAR_MOST = 4;
// Seconds before it lies there: the liquid spat out of the staff is in the air (its card's
// `shown_cue`, `pool_throw`: `glob` motes that land as their life ends, 0.26 to 0.3 s).
const float ARRIVE = 0.25;
// Seconds it splashes in for, once it lands.
const float SPILL = 0.35;
// How soft the union of outlines is, in pixels: how far apart two still run together.
const float MELD = 3.0;
// How far its outline is pushed in and out by the noise: its lobes and its bumps, as a part of its
// size, and their sizes in pixels.
const float LOBES = 0.3;
const float LOBE_PX = 15.0;
const float BUMPS = 0.1;
const float BUMP_PX = 5.0;
// Its drops: one at most in a cell of this many pixels, in a band this many hit sizes beyond its
// outline.
const float DROP_CELL = 6.0;
const float DROP_BAND = 0.9;
// Pixels from its edge its shallows end, and where its deep begins (a part of its depth).
const float SHALLOWS = 3.0;
const float DEEP = 0.5;
// Its ripples: one at most in a cell of this many pixels, flattened by the slant.
const float RIPPLE_CELL = 18.0;
const float RIPPLE_REACH = 7.0;
const float SLANT = 1.6;
// How much of the floor it hides: its edge, its film, its middle, its light lines, its drops.
const float EDGE_COVER = 0.85;
const float FILM_COVER = 0.55;
const float DEEP_COVER = 0.75;
const float LINE_COVER = 0.9;
const float DROP_COVER = 0.7;

// Worked out once a pool (vertex): its size (overshooting as it splashes in, shrinking as it dries)
// and how far it has dried (0 to 1).
varying flat vec2 life;
// Its palette (`palette_floats`): the materials of its infusions, -1 past them.
varying flat vec4 pal;
// Itself as the others see it: its middle (world pixels), its hit size as drawn, its still clock's
// code and facing (as listed); its own facing; its entry in the list (-1: drawn alone); the entries of the pools near enough to run
// together with it (-1 for none).
varying flat vec4 me;
varying flat vec2 me_facing;
varying flat float me_index;
varying flat vec4 near;
// The pixel's place in world pixels.
varying vec2 world;

// A pool's size and dryness by its still clock's code.
vec2 life_of(float code) {
	float since = still_since(code);
	float dry = 1.0 - still_left(code) / STILL_END;
	// Nothing while it flies, then an ease out that overshoots and settles.
	float k = clamp((since - ARRIVE) / SPILL, 0.0, 1.0) - 1.0;
	float splash = max(0.05, 1.0 + 2.70158 * k * k * k + 1.70158 * k * k);
	return vec2(since < ARRIVE ? 0.0 : (since < ARRIVE + SPILL ? splash : mix(1.0, 0.8, dry)), dry);
}

// A listed pool's still clock's code and facing (`StillMerge`: the code plus the facing's step).
float code_of(float w) {
	return w - round(w);
}

vec2 facing_of(float w) {
	float a = round(w) * TAU / FACING_STEPS;
	return vec2(cos(a), sin(a));
}

// How far from its middle a pool of hit size `reach` may draw: its spill, its drops and its glow.
float extent(float reach) {
	return reach * (max(look_shape.x, look_shape.y) * 1.35 * (1.0 + LOBES + BUMPS + THROW) + DROP_BAND * 2.0) + MELD * 3.0;
}

void vertex() {
	float code = coded_code(INSTANCE_CUSTOM.a);
	Look L = look_from_color(COLOR, INSTANCE_CUSTOM.rgb, float(INSTANCE_ID % 61) * 1.618, true);
	SET_LOOK(L);
	life = life_of(code);
	vec2 turned = MODEL_MATRIX[0].xy;
	me_facing = length(turned) > 0.0001 ? normalize(turned) : vec2(1.0, 0.0);
	pal = palette_floats(L.core, L.bits);
	world = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
	int own = merge_first + INSTANCE_ID;
	near = vec4(-1.0);
	if (own < merge_count) {
		// As the others see it, to the bit, so two pools agree on every pixel's owner.
		me = merge_place[own];
		me_index = float(own);
		// The pools that may draw on its quad: within its quad's half and their own reach.
		float half_quad = GRID * L.zoom * 0.5 * 1.42;
		int found = 0;
		for (int j = 0; j < MERGE_MOST; j++) {
			if (j >= merge_count || found >= NEAR_MOST) {
				break;
			}
			vec4 at = merge_place[j];
			if (j != own && length(at.xy - me.xy) < half_quad + extent(at.z)) {
				near[found] = float(j);
				found++;
			}
		}
	} else {
		float turn = mod(round(atan(me_facing.y, me_facing.x) / TAU * FACING_STEPS), FACING_STEPS);
		me = vec4(MODEL_MATRIX[3].xy, GRID * L.zoom * STILL_HIT, code + turn);
		me_index = -1.0;
	}
}

// A number in [0, 1) for the point `x`: no sine (a GPU's sine of a big number is coarse, and world
// pixels are big numbers), small numbers only. The same for every pool, so its details run on
// across merged pools.
float world_hash(vec3 x) {
	vec3 p = fract(x * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}

// Smooth value noise over world pixels, the same on every machine.
float noise(vec2 x) {
	vec2 i = floor(x);
	vec2 f = x - i;
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = mix(world_hash(vec3(i, 7.0)), world_hash(vec3(i + vec2(1.0, 0.0), 7.0)), u.x);
	float b = mix(world_hash(vec3(i + vec2(0.0, 1.0), 7.0)), world_hash(vec3(i + vec2(1.0, 1.0), 7.0)), u.x);
	return mix(a, b, u.y);
}

// How far out a spill's outline is at the pixel `q`, as a part of its oval: the same for every
// pool there, so it is worked out once a pixel. Its bumps creep slowly.
float spill_at(vec2 q) {
	float lobes = noise(q / LOBE_PX + vec2(31.0, 17.0)) - 0.5;
	float bumps = noise(q / BUMP_PX + vec2(sim_time * 0.16, 5.0)) - 0.5;
	return 1.0 + 2.0 * (LOBES * lobes + BUMPS * bumps);
}

// How far the pixel at `q` (world pixels) is outside the outline of the listed pool `at`, in pixels
// (below 0 inside): its oval, pushed out to `spill` of it there and further the way it was thrown,
// over its gradient.
float edge_of(vec2 q, vec4 at, float spill) {
	vec2 rad = at.z * look_shape * max(life_of(code_of(at.w)).x, 0.001);
	vec2 d = q - at.xy;
	vec2 e = d / rad;
	float n = length(e);
	if (n < 0.001) {
		return -spill * min(rad.x, rad.y);
	}
	float ahead = dot(d, facing_of(at.w)) / length(d);
	return (n - spill * (1.0 + THROW * ahead)) * n / length(e / rad);
}

// The merged outline's distance at `q` (pixels, below 0 inside), and whether this pool is the one
// nearest it there (`mine`): the one drawing it. The union is a soft minimum by a sum, so it is the
// same whichever pool works it out (a pool left out, far away, adds nearly nothing).
float field(vec2 q, out bool mine) {
	float spill = spill_at(q);
	float best = edge_of(q, me, spill);
	float sum = exp(-clamp(best, -40.0 * MELD, 40.0 * MELD) / MELD);
	mine = true;
	for (int k = 0; k < NEAR_MOST; k++) {
		int j = int(near[k]);
		if (j < 0) {
			break;
		}
		float d = edge_of(q, merge_place[j], spill);
		sum += exp(-clamp(d, -40.0 * MELD, 40.0 * MELD) / MELD);
		if (d < best || (d == best && float(j) < me_index)) {
			best = d;
			mine = false;
		}
	}
	return -MELD * log(sum);
}

// True on a drop thrown round a spill at the pixel `q`, `beyond` pixels beyond the merged outline, of
// this pool (its hit size `reach`, dried `dry`): one at most a cell, most and furthest ahead the way
// it was thrown, streaked the way they flew, fewer and smaller further out.
bool drop(vec2 q, float beyond, float reach, float dry) {
	vec2 from = q - me.xy;
	float ahead = max(dot(from, me_facing) / max(length(from), 0.001), 0.0);
	float band = DROP_BAND * reach * (1.0 + 1.2 * ahead);
	if (beyond > band || dry > 0.6) {
		return false;
	}
	float near_edge = (1.0 - beyond / band) * (0.35 + 0.65 * ahead);
	vec2 across = vec2(-me_facing.y, me_facing.x);
	vec2 cell = floor(q / DROP_CELL);
	for (int dy = -1; dy <= 1; dy++) {
		for (int dx = -1; dx <= 1; dx++) {
			vec2 k = cell + vec2(float(dx), float(dy));
			if (world_hash(vec3(k, 11.0)) > 0.55 * near_edge) {
				continue;
			}
			vec2 at = (k + vec2(world_hash(vec3(k, 12.0)), world_hash(vec3(k, 13.0)))) * DROP_CELL;
			float size = (0.6 + 1.6 * world_hash(vec3(k, 14.0))) * near_edge * (1.0 - dry / 0.6);
			vec2 rel = q - at;
			if (length(vec2(dot(rel, me_facing) / (1.0 + 1.5 * ahead), dot(rel, across))) < size) {
				return true;
			}
		}
	}
	return false;
}

// True on a ripple's ring at the pixel `q`: each cell of RIPPLE_CELL pixels has one spreading from
// a place of its own, again and again, thinning as it spreads.
bool ripple(vec2 q) {
	vec2 cell = floor(q / RIPPLE_CELL);
	for (int dy = -1; dy <= 1; dy++) {
		for (int dx = -1; dx <= 1; dx++) {
			vec2 k = cell + vec2(float(dx), float(dy));
			vec2 from = (k + vec2(world_hash(vec3(k, 1.0)), world_hash(vec3(k, 2.0)))) * RIPPLE_CELL;
			float h = world_hash(vec3(k, 3.0));
			float age = fract(sim_time / (1.8 + 1.4 * h) + h * 7.0);
			float off = length((q - from) * vec2(1.0, SLANT));
			if (age < 0.8 && abs(off - age * RIPPLE_REACH) < 0.5 && world_hash(vec3(floor(q), 4.0)) > age * 1.1) {
				return true;
			}
		}
	}
	return false;
}

// `colour` covering `amount` of the floor, premultiplied.
vec4 cover(vec3 colour, float amount) {
	return vec4(colour * amount, amount);
}

// Its liquid at the pixel `q` (world pixels), `depth` pixels in from its edge (it pulls back from
// the merged outline as it dries), deep from `deep` pixels in: premultiplied.
vec4 liquid(vec2 q, float depth, float deep) {
	vec3 light = palette_turn(pal, 0, 2, hi);
	vec3 base = palette_turn(pal, 0, 1, mid);
	vec3 shade = palette_turn(pal, 0, 0, lo);
	vec2 wp = floor(q);
	if (depth < 1.0) {
		// Its edge, catching the light along its far side (which by where it is from its pool's
		// middle: one look-up of the merged outline a pixel).
		float up = (q.y - me.y) / max(length(q - me.xy), 1.0);
		return cover(up < -0.35 ? light : base, EDGE_COVER);
	}
	float t = sim_time;
	if (world_hash(vec3(wp, floor(t * 3.0 + world_hash(vec3(wp, 5.0)) * 3.0))) < 0.003) {
		// A glint.
		return cover(hot, 1.0);
	}
	if (depth >= SHALLOWS && ripple(q)) {
		return cover(light, LINE_COVER);
	}
	// Light lines through it, each in an infusion of its palette past the first.
	float n = noise(vec2(q.x * 0.11 + t * 0.12, q.y * 0.17 - t * 0.08));
	float v = abs(noise(vec2(q.x * 0.09 + n * 1.6, q.y * 0.14 + t * 0.18)) - 0.5);
	float others = max(palette_count(pal) - 1.0, 1.0);
	int line = 1 + int(min(floor(noise(q * 0.05 + vec2(t * 0.05, 7.0)) * others), others - 1.0));
	if (depth >= SHALLOWS && v < 0.02) {
		return cover(palette_turn(pal, line, 2, light), LINE_COVER);
	}
	// A film the floor shows through, thicker and darker in its middle.
	bool in_deep = depth > deep || (depth > deep - 1.5 && mod(wp.x + wp.y, 2.0) < 1.0);
	return in_deep ? cover(mix(base, shade, 0.4), DEEP_COVER) : cover(mix(base, light, 0.35), FILM_COVER);
}

vec4 body_look() {
	if (life.x <= 0.0) {
		// Still in the air.
		return vec4(0.0);
	}
	vec2 wp = floor(world);
	vec2 q = wp + 0.5;
	// The pixel from its own middle, whole numbers, for its particles.
	vec2 p = wp - floor(me.xy);
	// Its hit size, wide and shallow: seen from above at a slant.
	vec2 r = me.z * look_shape;
	vec4 colour = vec4(0.0);
	// What the cards give off: particles born at random points of the outline.
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
			float ang = hash(i, cyc, 8.0) * TAU;
			vec4 q4 = particle(look, vec2(cos(ang), sin(ang)) * r * life.x, fract(t), i, cyc, p, zoom);
			if (q4.a > 0.0) {
				colour = q4;
			}
		}
	}
	bool mine;
	float m = field(q, mine);
	if (m <= 0.0) {
		// Inside the merged spill: only the pool nearest draws it, over its own particles.
		if (!mine) {
			return vec4(0.0);
		}
		// Drying out, its liquid pulls back from its outline to its middle, leaving a wet stain
		// that fades.
		float recede = life.y * (min(r.x, r.y) * life.x + 1.0);
		if (-m < recede) {
			return cover(mix(palette_turn(pal, 0, 0, lo), OUTLINE, 0.5), 0.5 * (1.0 - life.y));
		}
		return liquid(q, -m - recede, max(DEEP * min(r.x, r.y) * life.x, SHALLOWS + 1.0) - recede);
	}
	if (colour.a > 0.0) {
		return colour;
	}
	if (!mine) {
		return vec4(0.0);
	}
	if (drop(q, m, me.z * life.x, life.y)) {
		return cover(mix(palette_turn(pal, 0, 1, mid), palette_turn(pal, 0, 2, hi), 0.35), DROP_COVER);
	}
	// Its glow: a faint light round the spill, gone as it dries.
	float lit = 0.08 * falloff(m, 0.4 * min(r.x, r.y) + MELD) * (1.0 - life.y);
	if (has_layer(L_SPARKS)) {
		// Lightning flickers.
		lit *= 0.55 + 0.9 * hash(floor(sim_time * 20.0), 0.0, 21.0);
	}
	return vec4(glow * lit * glow_strength, 0.0);
}

void fragment() {
	COLOR = body_look();
}
