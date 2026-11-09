// SPDX-License-Identifier: GPL-3.0-or-later
shader_type canvas_item;
render_mode blend_premul_alpha;

// A pool, the glowing mire (content/spells/forms/pool/; the owner's pick, 2026-11-09): a dark, thick
// blob on the floor at its hit size, seen from above at a slant, its outline wobbling; veins of light
// slowly shifting through its dark (white-hot, light and base where a warped noise is near its
// middle), a lit rim one pixel wide where a pixel beside it is outside the wobbling outline (light
// along its top, base elsewhere) and a dark lip under its bottom edge. It splashes in while it is
// new (it overshoots and settles; the drops it throws are motes, a stream of its card's
// `look_motes` off its rim for its first moments) and dries out over its last second, shrinking, breaking up into scorch. Its card particles are given off from its
// outline. It is drawn upright on the screen even when its quad turns with a moving pool.
// The many motes rising off it from all over (the owner, 2026-11-09: "this needs more motes!") are
// real motes, the card's `look_motes` (`rising`), given off by Feel from where its shots are drawn
// (gameplay/feel/still_motes.gd), in its infusions in turn and their own kinds.
// Every infusion shows (its palette, `palette_turn`): its surface and rim are the first's, and its
// veins run through it in the others (each vein's in turn, by a slow noise; the first's too with
// one).
// It knows its time since it was placed and its life left from its still clock (`still_since`,
// `still_left`: the code beside its kind, `ProjectileManager.still_code`). Its quad is GRID x zoom
// pixels square round its centre, from the projectile manager's instance data as a rune's
// (`ProjectileManager._write_quad`). Blending is premultiplied: its pixels are opaque, the glow
// added light. Drawn by its card's pair of batches (`FormBase.look_shader`,
// `ProjectileManager.register_body`), warmed before the first room.

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

// Seconds it splashes in for.
const float SPILL = 0.35;

// Worked out once a pool (vertex): its size (overshooting as it splashes in, shrinking as it dries)
// and how far it has dried (0 to 1).
varying flat vec2 life;
// Its palette (`palette_floats`): the materials of its infusions, -1 past them.
varying flat vec4 pal;
// The quad's +x on the screen (it turns with a moving pool; the drawing stays upright).
varying flat vec2 axis;

void vertex() {
	float code = coded_code(INSTANCE_CUSTOM.a);
	float since = still_since(code);
	float dry = 1.0 - still_left(code) / STILL_END;
	Look L = look_from_color(COLOR, INSTANCE_CUSTOM.rgb, float(INSTANCE_ID % 61) * 1.618, true);
	SET_LOOK(L);
	// An ease out that overshoots, then settles.
	float k = clamp(since / SPILL, 0.0, 1.0) - 1.0;
	float splash = max(0.05, 1.0 + 2.70158 * k * k * k + 1.70158 * k * k);
	float size = since < SPILL ? splash : mix(1.0, 0.8, dry);
	life = vec2(size, dry);
	pal = palette_floats(L.core, L.bits);
	axis = length(MODEL_MATRIX[0].xy) > 0.0001 ? normalize(MODEL_MATRIX[0].xy) : vec2(1.0, 0.0);
}

// How far out its outline is at the pixel `p`, as a part of its size: it wobbles round the rim.
float wobble(vec2 e) {
	float a = atan(e.y, e.x);
	float t = sim_time + seed;
	return life.x * (1.0 + 0.07 * sin(3.0 * a + t * 1.1 + 1.0) + 0.05 * sin(5.0 * a - t * 1.7) + 0.035 * sin(7.0 * a + t * 2.3));
}

// True for the pixel `p` (from its centre) inside the outline of a pool of half sizes `r`.
bool in_pool(vec2 p, vec2 r) {
	vec2 e = p / r;
	return length(e) <= wobble(e);
}

// A number in [0, 1) for the lattice point `i`, by its seed: no sine (a GPU's sine of a big number
// is coarse, and the noise went flat, its veins wide), small numbers only.
float corner(vec2 i) {
	vec3 p = fract(vec3(i.xyx + seed * 7.13) * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}

// Smooth value noise, the same on every machine.
float noise(vec2 x) {
	vec2 i = floor(x);
	vec2 f = x - i;
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = mix(corner(i), corner(i + vec2(1.0, 0.0)), u.x);
	float b = mix(corner(i + vec2(0.0, 1.0)), corner(i + vec2(1.0, 1.0)), u.x);
	return mix(a, b, u.y);
}

// The mire's pixel `p`: veins of light through its dark (the outline and the first's shadow), each
// vein in an infusion of its palette past the first (by a slow noise: the first's with one).
vec3 mire(vec2 p) {
	float t = sim_time;
	float n = noise(vec2(p.x * 0.17 + t * 0.12, p.y * 0.26 - t * 0.08));
	float v = abs(noise(vec2(p.x * 0.13 + n * 1.6, p.y * 0.2 + t * 0.18)) - 0.5);
	float others = max(palette_count(pal) - 1.0, 1.0);
	int vein = 1 + int(min(floor(noise(p * 0.06 + vec2(t * 0.05, 7.0)) * others), others - 1.0));
	return v < 0.03 ? hot : (v < 0.065 ? palette_turn(pal, vein, 2, hi) : (v < 0.11 ? palette_turn(pal, vein, 1, mid) : (n < 0.4 ? OUTLINE : palette_turn(pal, 0, 0, lo))));
}

vec4 body_look(vec2 uv) {
	// The screen pixel, whole numbers, the pool's centre at 0, upright however the quad turns.
	vec2 size = vec2(GRID) * zoom;
	vec2 local = uv * size - size * 0.5;
	vec2 p = floor(vec2(axis.x * local.x - axis.y * local.y, axis.y * local.x + axis.x * local.y));
	float reach = size.x * STILL_HIT;
	// Its hit size, wide and shallow: seen from above at a slant.
	vec2 r = reach * look_shape;
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
			vec4 q = particle(look, vec2(cos(ang), sin(ang)) * r * life.x, fract(t), i, cyc, p, zoom);
			if (q.a > 0.0) {
				colour = q;
			}
		}
	}
	vec2 e = p / r;
	bool inside = in_pool(p, r);
	if (inside) {
		if (life.y > 0.0 && hash(p.x, p.y, 31.0) < life.y * 1.15) {
			// Drying out: it breaks up, leaving scorch.
			colour = hash(p.x, p.y, 32.0) < 0.55 * (1.0 - life.y) ? vec4(OUTLINE, 1.0) : colour;
		} else {
			// Its rim where a pixel beside it is outside (each judged by its own place on the outline,
			// so the rim is one pixel all round, as the pick's mockup).
			bool edge = !in_pool(p + vec2(1.0, 0.0), r) || !in_pool(p - vec2(1.0, 0.0), r)
					|| !in_pool(p + vec2(0.0, 1.0), r) || !in_pool(p - vec2(0.0, 1.0), r);
			colour = vec4(edge ? (e.y < -0.2 ? palette_turn(pal, 0, 2, hi) : palette_turn(pal, 0, 1, mid)) : mire(p), 1.0);
		}
	} else if (p.y > 0.0 && in_pool(p - vec2(0.0, 1.0), r)) {
		// A dark lip under its bottom edge.
		colour = vec4(OUTLINE, 1.0);
	}
	if (colour.a > 0.0) {
		return colour;
	}
	// Its glow: a soft light over the whole mire, gone as it dries.
	float lit = 0.22 * falloff(length(e), 1.6 * life.x) * (1.0 - life.y);
	if (has_layer(L_SPARKS)) {
		// Lightning flickers.
		lit *= 0.55 + 0.9 * hash(floor(sim_time * 20.0), 0.0, 21.0);
	}
	return vec4(glow * lit * glow_strength, 0.0);
}

void fragment() {
	COLOR = body_look(UV);
}
