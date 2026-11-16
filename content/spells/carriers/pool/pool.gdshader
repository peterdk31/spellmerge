// SPDX-License-Identifier: GPL-3.0-or-later
shader_type canvas_item;
render_mode blend_premul_alpha;

// A pool (content/spells/carriers/pool/; redesigned for the owner, 2026-11-16: "it should be drawn
// on the floor", and "overlapping pools should be merged into one"): a flat puddle of its
// infusion lying on the floor at its hit size, seen from above at a slant, its outline wobbling.
// It is drawn at the floor's z (its card's `look_on_floor`), under every body and over the floor's
// marks, and the pools that overlap are one puddle (its card's `look_merges`): the projectile
// manager tells its shader where every pool of its body is drawn this frame (`StillMerge`), the
// outline is the smooth union of all their outlines (a bridge of liquid between two near ones) and
// each pixel is drawn by the pool nearest it, in its colours, so no pixel is drawn twice.
//
// Its liquid, in depth from the outline (pixels): a rim one pixel wide (lit along its far edge,
// catching the light, in shadow along its near one, its base at its sides), shallows its base you see the floor
// through, then its base, deepening by a dither into its shadow in the middle. Over the liquid,
// in world space so they run on across merged pools: light lines slowly shifting (a warped noise,
// in its other infusions in turn by a slow noise: the first's with one), ripples spreading and
// fading (flattened by the slant) and glints of white-hot twinkling. It splashes in while it is new
// (it overshoots and settles; the drops it throws are motes, its card's `look_motes`, off its rim
// for its first moments) and dries out over its last second, pulling back from its outline to its
// middle and leaving a wet stain that fades.
// Its card particles are given off from its outline; a soft light lies round it, gone as it dries.
// It is drawn upright on the screen even when its quad turns with a moving pool.
// The motes rising off it (the owner, 2026-11-09: "this needs more motes!") are real motes, its
// card's `look_motes` (`rising`), given off by Feel from where its shots are drawn
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

// Every pool of its body drawn this frame (`StillMerge`, set by the projectile manager): its own
// batch's first, in row order (a pool's own at its INSTANCE_ID), then the other batch's. Each
// place is x, y its middle in world pixels, z its hit size as drawn, w its still clock's code;
// each seed its wobble's. None: it is drawn alone (a pool past MERGE_MOST too).
const int MERGE_MOST = 32;
uniform int merge_count = 0;
uniform vec4 merge_place[MERGE_MOST];
uniform float merge_seed[MERGE_MOST];

// Seconds it splashes in for.
const float SPILL = 0.35;
// How far apart, in pixels, two outlines still run together (the smooth union's reach).
const float MELD = 6.0;
// Pixels from its outline: its shallows end, and where its deep begins (a part of its depth).
const float SHALLOWS = 3.0;
const float DEEP = 0.5;
// Its ripples: one at most in a cell of this many pixels, flattened by the slant.
const float RIPPLE_CELL = 18.0;
const float RIPPLE_REACH = 7.0;
const float SLANT = 1.6;

// Worked out once a pool (vertex): its size (overshooting as it splashes in, shrinking as it dries)
// and how far it has dried (0 to 1).
varying flat vec2 life;
// Its palette (`palette_floats`): the materials of its infusions, -1 past them.
varying flat vec4 pal;
// The quad's +x on the screen (it turns with a moving pool; the drawing stays upright).
varying flat vec2 axis;
// Itself as the other pools are told: its middle (world pixels), its hit size as drawn, its still
// clock's code; its wobble's seed, and its entry among the merged (-1: drawn alone).
varying flat vec4 me;
varying flat float me_seed;
varying flat float me_index;

// A pool's size and dryness by its still clock's code.
vec2 life_of(float code) {
	float since = still_since(code);
	float dry = 1.0 - still_left(code) / STILL_END;
	// An ease out that overshoots, then settles.
	float k = clamp(since / SPILL, 0.0, 1.0) - 1.0;
	float splash = max(0.05, 1.0 + 2.70158 * k * k * k + 1.70158 * k * k);
	return vec2(since < SPILL ? splash : mix(1.0, 0.8, dry), dry);
}

// The seed of the pool drawn as row `n` of its batch (`StillMerge.row_seed`).
float row_seed(int n) {
	return float(n % 61) * 1.618;
}

void vertex() {
	float code = coded_code(INSTANCE_CUSTOM.a);
	Look L = look_from_color(COLOR, INSTANCE_CUSTOM.rgb, float(INSTANCE_ID % 61) * 1.618, true);
	SET_LOOK(L);
	life = life_of(code);
	pal = palette_floats(L.core, L.bits);
	axis = length(MODEL_MATRIX[0].xy) > 0.0001 ? normalize(MODEL_MATRIX[0].xy) : vec2(1.0, 0.0);
	if (INSTANCE_ID < merge_count) {
		// As the others see it, to the bit, so two pools agree on every pixel's owner.
		me = merge_place[INSTANCE_ID];
		me_seed = merge_seed[INSTANCE_ID];
		me_index = float(INSTANCE_ID);
	} else {
		me = vec4(MODEL_MATRIX[3].xy, GRID * L.zoom * STILL_HIT, code);
		me_seed = row_seed(INSTANCE_ID);
		me_index = -1.0;
	}
}

// How far the pixel at `q` (world pixels) is outside the wobbling outline of the pool `at` of seed
// `s`, in pixels (below 0 inside): its oval's distance over its gradient.
float edge_of(vec2 q, vec4 at, float s) {
	vec2 rad = at.z * look_shape * life_of(at.w).x;
	vec2 e = (q - at.xy) / rad;
	float n = length(e);
	if (n < 0.001) {
		return -min(rad.x, rad.y);
	}
	float a = atan(e.y, e.x);
	float t = sim_time + s;
	float w = 1.0 + 0.06 * sin(2.0 * a + t * 0.7 + 1.0) + 0.045 * sin(3.0 * a - t * 0.9 + s) + 0.02 * sin(5.0 * a + t * 1.3);
	return (n - w) * n / length(e / rad);
}

// The smooth union of two outlines' distances.
float meld(float a, float b) {
	float h = max(MELD - abs(a - b), 0.0) / MELD;
	return min(a, b) - h * h * MELD * 0.25;
}

// The merged outline's distance at `q` (pixels, below 0 inside), and whether this pool is the one
// nearest it there (`mine`): the one drawing it. Of two exactly as near, the earlier entry.
float field(vec2 q, out bool mine) {
	float best = edge_of(q, me, me_seed);
	float merged = best;
	mine = true;
	if (me_index < 0.0) {
		return merged;
	}
	int own = int(me_index);
	for (int j = 0; j < MERGE_MOST; j++) {
		if (j >= merge_count) {
			break;
		}
		vec4 at = merge_place[j];
		// Only a pool whose quad may reach this one's pixels.
		if (j == own || length(q - at.xy) > (at.z + me.z) * 3.4) {
			continue;
		}
		float d = edge_of(q, at, merge_seed[j]);
		merged = meld(merged, d);
		if (d < best || (d == best && j < own)) {
			best = d;
			mine = false;
		}
	}
	return merged;
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

// Its liquid at the pixel `q` (world pixels), `depth` pixels in from its edge (it pulls back from
// the merged outline as it dries), deep from `deep` pixels in: premultiplied.
vec4 liquid(vec2 q, float depth, float deep) {
	vec3 light = palette_turn(pal, 0, 2, hi);
	vec3 base = palette_turn(pal, 0, 1, mid);
	vec3 shade = palette_turn(pal, 0, 0, lo);
	if (depth < 1.0) {
		// Its rim: lit along its far edge, in shadow along its near one (it lies in a dip of the
		// floor), its base between; which by where it is from its pool's middle (one look-up of
		// the merged outline a pixel: a loop's every call is compiled again).
		float up = (q.y - me.y) / max(length(q - me.xy), 1.0);
		return vec4(up < -0.35 ? light : (up > 0.35 ? shade : base), 1.0);
	}
	vec2 wp = floor(q);
	float t = sim_time;
	if (world_hash(vec3(wp, floor(t * 3.0 + world_hash(vec3(wp, 5.0)) * 3.0))) < 0.004) {
		// A glint.
		return vec4(hot, 1.0);
	}
	if (depth < SHALLOWS) {
		// The shallows: the floor shows through.
		return vec4(base * 0.7, 0.7);
	}
	if (ripple(q)) {
		return vec4(light, 1.0);
	}
	// Light lines through it, each in an infusion of its palette past the first.
	float n = noise(vec2(q.x * 0.11 + t * 0.12, q.y * 0.17 - t * 0.08));
	float v = abs(noise(vec2(q.x * 0.09 + n * 1.6, q.y * 0.14 + t * 0.18)) - 0.5);
	float others = max(palette_count(pal) - 1.0, 1.0);
	int line = 1 + int(min(floor(noise(q * 0.05 + vec2(t * 0.05, 7.0)) * others), others - 1.0));
	bool in_deep = depth > deep || (depth > deep - 1.5 && mod(wp.x + wp.y, 2.0) < 1.0);
	if (v < 0.022) {
		return vec4(palette_turn(pal, line, 2, light), 1.0);
	}
	if (in_deep && v < 0.045) {
		return vec4(palette_turn(pal, line, 1, base), 1.0);
	}
	return vec4(in_deep ? shade : base, 1.0);
}

vec4 body_look(vec2 uv) {
	// The world pixel: the same grid for every pool, so merged pools meet pixel for pixel, upright
	// however the quad turns.
	vec2 size = vec2(GRID) * zoom;
	vec2 local = uv * size - size * 0.5;
	vec2 wp = floor(me.xy + vec2(axis.x * local.x - axis.y * local.y, axis.y * local.x + axis.x * local.y));
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
		// Inside the merged puddle: only the pool nearest draws it, over its own particles.
		if (!mine) {
			return vec4(0.0);
		}
		// Drying out, its liquid pulls back from its outline to its middle, leaving a wet stain
		// that fades.
		float recede = life.y * (min(r.x, r.y) * life.x + 1.0);
		if (-m < recede) {
			float wet = 0.5 * (1.0 - life.y);
			return vec4(mix(palette_turn(pal, 0, 0, lo), OUTLINE, 0.5) * wet, wet);
		}
		return liquid(q, -m - recede, max(DEEP * min(r.x, r.y) * life.x, SHALLOWS + 1.0) - recede);
	}
	if (colour.a > 0.0) {
		return colour;
	}
	if (!mine) {
		return vec4(0.0);
	}
	// Its glow: a soft light round the puddle, gone as it dries.
	float lit = 0.08 * falloff(m, 0.4 * min(r.x, r.y) + MELD) * (1.0 - life.y);
	if (has_layer(L_SPARKS)) {
		// Lightning flickers.
		lit *= 0.55 + 0.9 * hash(floor(sim_time * 20.0), 0.0, 21.0);
	}
	return vec4(glow * lit * glow_strength, 0.0);
}

void fragment() {
	COLOR = body_look(UV);
}
