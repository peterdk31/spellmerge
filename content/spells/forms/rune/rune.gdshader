// SPDX-License-Identifier: GPL-3.0-or-later
shader_type canvas_item;
render_mode blend_premul_alpha;

// A rune, the hovering seal (content/spells/forms/rune/: its card's own shot shader,
// `FormBase.look_shader`; core/README.md, "The shot shaders"; the owner's pick, 2026-11-09): a small
// crystal drops in and hovers over a ring on the floor at its hit size, bobbing, its shadow under it.
// While it arms (`SpellLimits.RUNE_ARM`, ARM here) the ring closes from an open arc, its tip lit, and
// the crystal fills with light from the bottom; armed, the ring is whole, a white-hot speck chases
// round it (a twinkling mote, `twinkle_px`) and the crystal spins (its facet's divide moving across
// it). The light dripping from it to the floor and the motes rising off the ring once armed are real
// motes (the owner, 2026-11-09: "use motes for everything you can"): its card's `look_motes` (`drip`
// from its middle at the crystal's foot, `rising` off the rim of its `look_shape`, both from its
// arming), given off by Feel (gameplay/feel/still_motes.gd). Its going off, the crystal slamming
// down, is its card's impact cue (`rune_burst`). Its card particles are given off from the ring,
// void's crystal has a dark heart and lightning's glow flickers. It is drawn upright on the screen
// even when its quad turns with a creeping (homing) rune.
// Every infusion shows (its palette, `palette_turn`): the crystal's lit facet in the first, its other
// facet in the second, the ring in the third (the first's with two).
// It knows its time since it was placed from its still clock (`still_since`, the code beside its
// kind: `ProjectileManager.still_code`). Its quad is GRID x zoom pixels square round its centre, from
// the projectile manager's instance data (`_write_quad`). Blending is premultiplied: its pixels are
// opaque, the glow added light.

#include "res://core/projectiles/shot_palette.gdshaderinc"
#include "res://core/projectiles/shot_look.gdshaderinc"
#include "res://core/projectiles/shot_particle.gdshaderinc"

// The spark pool's share (set by the projectile manager, 1.0 is everything): the fraction of
// every shot's particles drawn this frame.
uniform float particle_share = 1.0;

const float GRID = 24.0;
// Seconds from its placing: the crystal drops in over DROP; it is armed at ARM
// (`SpellLimits.RUNE_ARM`), filling with light between.
const float DROP = 0.3;
const float ARM = 1.0;
// Its ring's half width and half depth in its hit size as drawn (STILL_HIT), its card's
// `look_shape` (set by the projectile manager, `set_body_shape`), so the motes rising off the ring
// leave from the ring it draws. The default only draws a body no card has shaped yet.
uniform vec2 look_shape = vec2(1.0, 0.625);

// Worked out once a rune (vertex): the crystal's height over the ring and its scale; how much of
// the ring is drawn, where the chasing speck is and how far it has armed; the facet's divide,
// whether it glints and whether it is armed.
varying flat vec4 seal;
varying flat vec4 turn;
varying flat float scale;
// The quad's +x on the screen (it turns with a moving rune; the drawing stays upright).
varying flat vec2 axis;
// Its palette (`palette_floats`): the materials of its infusions, -1 past them.
varying flat vec4 pal;

void vertex() {
	float since = still_since(coded_code(INSTANCE_CUSTOM.a));
	Look L = look_from_color(COLOR, INSTANCE_CUSTOM.rgb, float(INSTANCE_ID % 61) * 1.618, true);
	SET_LOOK(L);
	float c = clamp(L.zoom * 0.25, 0.5, 2.0);
	float drop = clamp(since / DROP, 0.0, 1.0);
	float fall = 1.0 - (1.0 - drop) * (1.0 - drop);
	float bob = sin(sim_time * 3.0 + L.seed) * 1.2 * clamp((since - DROP) / 0.2, 0.0, 1.0);
	float hover = (mix(24.0, 10.0, fall) + bob) * c;
	float arm = clamp((since - DROP) / (ARM - DROP), 0.0, 1.0);
	float armed = since >= ARM ? 1.0 : 0.0;
	float ring_to = since < DROP ? 0.0 : 0.12 + arm * 0.88;
	float spin = sim_time * (armed > 0.5 ? 5.0 : 1.5) + L.seed;
	seal = vec4(floor(hover + 0.5), ring_to, fract(sim_time * 1.3 + L.seed), arm);
	turn = vec4(2.6 * c * sin(spin), cos(spin) > 0.5 ? 1.0 : 0.0, armed, 0.0);
	scale = c;
	pal = palette_floats(L.core, L.bits);
	axis = length(MODEL_MATRIX[0].xy) > 0.0001 ? normalize(MODEL_MATRIX[0].xy) : vec2(1.0, 0.0);
}

// The crystal's pixel `p` (from its centre): a diamond 3 x 5 a scale either side, its edge in
// shadow, lit left of its facet's divide, a white-hot pixel near its top and on the divide when it
// glints; dim above the light filling it while it arms; void's dark heart. Alpha 0 off it.
vec4 crystal(vec2 p) {
	float hx = 3.0 * scale;
	float hy = 5.0 * scale;
	float d = abs(p.x) / hx + abs(p.y) / hy;
	if (d > 1.05) {
		return vec4(0.0);
	}
	bool edge = d > 1.0 - 0.85 / hx;
	bool left = p.x < turn.x;
	vec3 rgb = edge ? lo : (left ? palette_turn(pal, 0, 2, hi) : palette_turn(pal, 1, 1, mid));
	if (p.y == -floor(hy - 0.5) && p.x == 0.0) {
		rgb = hot;
	}
	if (!edge && abs(p.x - turn.x) < 0.5 && turn.y > 0.5) {
		rgb = hot;
	}
	if (turn.z < 0.5 && (p.y + hy) / (2.0 * hy) < 1.0 - seal.w) {
		rgb = edge ? lo : (left ? palette_turn(pal, 0, 1, mid) : lo);
	}
	if (has_layer(L_PULL) && d < 0.34) {
		rgb = OUTLINE;
	}
	return vec4(rgb, 1.0);
}

vec4 rune_look(vec2 uv) {
	// The screen pixel, whole numbers, the rune's centre at 0, upright however the quad turns.
	vec2 size = vec2(GRID) * zoom;
	vec2 local = uv * size - size * 0.5;
	vec2 p = floor(vec2(axis.x * local.x - axis.y * local.y, axis.y * local.x + axis.x * local.y));
	// The ring at its hit size, seen from above at a slant.
	vec2 r = size.x * STILL_HIT * look_shape;
	vec4 colour = vec4(0.0);
	// What the cards give off: particles born at random points of the ring.
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
			vec4 q = particle(look, vec2(cos(ang), sin(ang)) * r, fract(t), i, cyc, p, zoom);
			if (q.a > 0.0) {
				colour = q;
			}
		}
	}
	// Its shadow on the floor under the crystal, dithered while it is high.
	vec2 s = p / (vec2(3.0, 1.5) * scale);
	if (dot(s, s) <= 1.0 && (seal.x < 13.0 * scale || mod(p.x + p.y, 2.0) > 0.5)) {
		colour = vec4(STONE_SHADOW, 1.0);
	}
	// The ring: a one-pixel ellipse, drawn round from the top as far as it is closed.
	vec2 e = p / r;
	float el = length(e);
	vec2 g = p / (r * r);
	float gl = max(length(g), 0.0001);
	vec2 n = g / gl;
	float dist = (el - 1.0) * el / gl;
	float fr = fract(atan(e.y, e.x) / TAU + 0.25);
	bool shown = fr <= seal.y;
	if (shown && abs(dist) < 0.5 * max(abs(n.x), abs(n.y))) {
		colour = vec4(turn.z > 0.5 ? palette_turn(pal, 2, 1, mid) : (fr > seal.y - 0.03 ? palette_turn(pal, 2, 2, hi) : palette_turn(pal, 2, 0, lo)), 1.0);
	}
	if (turn.z > 0.5) {
		// Armed: a white-hot mote chasing round the ring, twinkling.
		float a = seal.z * TAU - 1.5708;
		float m = twinkle_px(p, floor(vec2(cos(a), sin(a)) * r + 0.5), 3.0, fract(sim_time * 1.7 + seed));
		if (m >= 0.0) {
			colour = vec4(m > 2.5 ? hot : palette_turn(pal, 0, int(m), shade_rgb(m)), 1.0);
		}
	}
	vec4 gem = crystal(p + vec2(0.0, seal.x));
	if (gem.a > 0.0) {
		return gem;
	}
	if (colour.a > 0.0) {
		return colour;
	}
	// The glow: light round the crystal, brighter as it fills, the floor under it once armed and
	// the ring as far as it is drawn.
	float lit = (0.3 + 0.35 * seal.w) * falloff(length(p + vec2(0.0, seal.x)), 11.0 * scale)
			+ 0.25 * seal.w * falloff(el, 1.1)
			+ (shown ? 0.3 : 0.0) * falloff(abs(dist), 4.0);
	if (has_layer(L_SPARKS)) {
		// Lightning flickers.
		lit *= 0.55 + 0.9 * hash(floor(sim_time * 20.0), 0.0, 21.0);
	}
	if (has_layer(L_PULL)) {
		lit *= 0.6;
	}
	return vec4(glow * lit * glow_strength, 0.0);
}

void fragment() {
	COLOR = rune_look(UV);
}
