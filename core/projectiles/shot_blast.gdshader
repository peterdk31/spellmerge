// SPDX-License-Identifier: GPL-3.0-or-later
shader_type canvas_item;
render_mode blend_premul_alpha;

// An explosion (gameplay/feel/feel.gd, `explode`; core/README.md, "The shot shaders"): its parts,
// each an instance of Feel's blast mesh (`Feel.blast_mesh`) in a square BLAST_SPAN x 2 radii
// across round where it went off, in the ramp and look of what went off; the radius is the
// zoom x 2 pixels, the age the code beside the kind (`coded_age`). The parts (B_* here,
// Feel's KIND_SHELL and on, less KIND_SHELL):
//   B_SHELL     the ragged shell (blast, owner 2026-10-29): a disc of fire to the radius whose
//               edge wobbles like a flame front (88-100% of it), cooling from the middle out and
//               crumbling pixel by pixel, with a white-hot pop in the middle
//   B_FIREBALL  the rising fireball (an exploding barrel): a fireball of five lobes that turn to
//               smoke, rising up the screen on a stem of smoke, a dust ring rolling out at its foot
//   B_DEBRIS    fragments and rubble: twelve hot chunks and twelve of stone flung out past the
//               radius (to twice it), thrown hard on arcs with a streak behind, landing with a hop
//               and lying until they cool and crumble
//   B_SCORCH    the scorch (Feel's floor batch, under the bodies): a dark dithered burn round the
//               middle with embers glowing in it, after one frame of the whole radius lit
// Up is up the screen (the floor is seen from above at a slant, so the floor's own lines are
// squashed to FLOOR_FLAT top to bottom).
//
// PARTICLES ARE GEOMETRY (as `shot_effect.gdshader`): the mesh is a light and BLAST_PIECES small
// quads, each told in its UV its quad kind and slot; `vertex()` works out where each piece is now
// and what colours it has, and puts its quad round it alone or folds it away. The fragment stage
// only colours a pixel of its own quad, in a few small modes with no loops:
//   M_LIGHT   the light (added; drawn first)
//   M_BLOB    a disc: inner, outer and rim colours, a dither that can thin out towards the rim
//   M_STREAK  a line a few pixels wide (the fireball's stem)
//   M_PIECE   a flung chunk: its block, the streak behind it, its shadow on the floor
//   M_SHELL   the ragged shell (its edge and crumbling need the pixel's own way round)

#include "res://core/projectiles/shot_palette.gdshaderinc"
#include "res://core/projectiles/shot_look.gdshaderinc"

// The parts (the kind in the custom data, Feel's KIND_SHELL and on less KIND_SHELL) and their
// seconds (Feel's SHELL_SECONDS and on; keep the two equal).
const float B_SHELL = 0.0;
const float B_FIREBALL = 1.0;
const float B_DEBRIS = 2.0;
const float B_SCORCH = 3.0;
const float SHELL_SECONDS = 0.5;
const float FIREBALL_SECONDS = 1.2;
const float DEBRIS_SECONDS = 1.6;
const float SCORCH_SECONDS = 2.6;
// The square is BLAST_SPAN radii each way (Feel's; keep equal): room for the chunks, which land
// up to 2.05 radii out, and the fireball's rise.
const float BLAST_SPAN = 2.2;
const float FLOOR_FLAT = 0.75;
// The quad kinds (BLAST_Q_* in Feel) and the fragment's modes.
const float Q_LIGHT = 0.0;
const float Q_PIECE = 1.0;
const float M_LIGHT = 0.0;
const float M_BLOB = 1.0;
const float M_STREAK = 2.0;
const float M_PIECE = 3.0;
const float M_SHELL = 4.0;
// Smoke and a burn: not in the palette (nothing else is smoke), so here.
const vec3 SMOKE_SHADOW = vec3(0.165, 0.149, 0.220);
const vec3 SMOKE_BASE = vec3(0.239, 0.224, 0.314);
const vec3 SMOKE_LIGHT = vec3(0.345, 0.325, 0.431);
const vec3 BURN_DEEP = vec3(0.043, 0.039, 0.071);
const vec3 BURN_EDGE = vec3(0.067, 0.059, 0.102);

// An ordered 4 x 4 dither threshold for the pixel `p`, in [0, 1): the scorch, smoke and dust thin
// out in a pattern, as the mockup's did, not in noise.
float bayer2(vec2 p) {
	p = floor(p);
	return fract(p.x / 2.0 + p.y * p.y * 0.75);
}

float bayer4(vec2 p) {
	return bayer2(0.5 * p) * 0.25 + bayer2(p);
}

varying vec2 px;
varying flat float mode;
varying flat vec4 v0;
varying flat vec4 v1;
varying flat vec4 v2;
varying flat vec4 c0;
varying flat vec4 c1;
varying flat vec4 c2;

// ---- Vertices ----

// The ramp of `L` at heat `h` (0 white-hot, then light, base, and the shadow from 0.6).
vec3 heat(Look L, float h) {
	return h < 0.08 ? L.hot : (h < 0.28 ? L.hi : (h < 0.6 ? L.mid : L.lo));
}

float ease_out(float x) {
	return 1.0 - (1.0 - x) * (1.0 - x);
}

float ease_out3(float x) {
	return 1.0 - (1.0 - x) * (1.0 - x) * (1.0 - x);
}

// A flung chunk at `t` seconds: thrown along `way` to land `far` out after `flight` seconds, at
// most `high` up, most of the way in the first third of its flight, then a hop of 4 px out and 3
// up where it lands. xy where it is on the floor, z how high above it.
vec3 chunk_at(vec2 way, float far, float flight, float high, float t) {
	float u = min(t / flight, 1.0);
	float hop = t > flight ? min((t - flight) / 0.14, 1.0) : 0.0;
	float d = far * ease_out3(u) + (t > flight ? 4.0 * ease_out(hop) : 0.0);
	float up = t < flight ? high * sin(3.1416 * u) : (hop < 1.0 ? 3.0 * sin(3.1416 * hop) : 0.0);
	return vec3(way.x * d, way.y * d * FLOOR_FLAT, up);
}

void vertex() {
	float kind = coded_kind(INSTANCE_CUSTOM.a);
	float a = coded_age(coded_code(INSTANCE_CUSTOM.a));
	Look L = look_from_color(COLOR, INSTANCE_CUSTOM.rgb, float(INSTANCE_ID % 61) * 1.618, false);
	float s = L.seed;
	float r = L.zoom * 2.0;
	float life = kind == B_SHELL ? SHELL_SECONDS : (kind == B_FIREBALL ? FIREBALL_SECONDS : (kind == B_DEBRIS ? DEBRIS_SECONDS : SCORCH_SECONDS));
	float t = a * life;
	vec2 size = vec2(r * 2.0 * BLAST_SPAN);
	vec2 o = size * 0.5;
	float slot = floor(UV.x);
	float quad = floor(UV.y);
	vec2 corner = vec2(fract(UV.x) > 0.5 ? 1.0 : 0.0, fract(UV.y) > 0.5 ? 1.0 : 0.0);
	vec2 q_lo = -o;
	vec2 q_hi = size - o;
	bool shown = false;
	float m = M_BLOB;
	vec4 a0 = vec4(0.0);
	vec4 a1 = vec4(0.0);
	vec4 a2 = vec4(0.0);
	vec4 k0 = vec4(0.0);
	vec4 k1 = vec4(0.0);
	vec4 k2 = vec4(0.0);
	// The fireball's rise and its size now (its stem, dust and lobes all use them).
	float f = t / FIREBALL_SECONDS;
	float rise = r * 0.7 * ease_out(clamp((t - 0.08) / 0.7, 0.0, 1.0));
	float ball = r * 0.42 * ease_out3(min(t / 0.08, 1.0)) * (1.0 - f * 0.35);
	if (quad == Q_LIGHT) {
		// The light: a0 its middle and reach, and how bright (a0.w).
		float k = 0.0;
		float reach = r;
		vec2 at = vec2(0.0);
		if (kind == B_SHELL) {
			// No bloom in the game: the shell's light carries its glow.
			k = (1.0 - a) * (1.0 - a) * 1.2;
			reach = r * 1.15;
		} else if (kind == B_FIREBALL) {
			k = max(1.0 - t / 0.3, 0.0);
			at = vec2(0.0, -rise * 0.5);
		} else if (kind == B_DEBRIS) {
			// The flash as the chunks tear free.
			k = max(1.0 - t / 0.08, 0.0) * 0.8;
			reach = r * 0.9;
		} else {
			// The floor in the radius lit for a frame.
			k = t < 0.034 ? 0.5 : 0.0;
		}
		shown = k > 0.0;
		m = M_LIGHT;
		a0 = vec4(at, reach, k);
		k0 = vec4(L.glow, 1.0);
	} else if (kind == B_SHELL) {
		// One quad, worked out per pixel (M_SHELL): a0 radius, seconds, seed.
		shown = slot == 0.0;
		m = M_SHELL;
		q_lo = vec2(-r - 1.0);
		q_hi = vec2(r + 1.0);
		a0 = vec4(r, t, s, 0.0);
		k0 = vec4(L.hot, 1.0);
		k1 = vec4(L.hi, 1.0);
		k2 = vec4(L.mid, 1.0);
		a2 = vec4(L.lo, 0.0);
	} else if (kind == B_DEBRIS) {
		// Chunk `slot`: the first twelve glow, the rest are stone.
		bool stone = slot >= 12.0;
		float j = mod(slot, 12.0);
		float salt = stone ? 70.0 : 60.0;
		float turn = j / 12.0 * 6.2832 + (hash_seeded(j, salt, 31.0, s) - 0.5) * 0.5;
		vec2 way = vec2(cos(turn), sin(turn));
		float far = r * (1.2 + 0.85 * pow(hash_seeded(j, salt + 1.0, 31.0, s), 0.7));
		float flight = 0.26 + 0.2 * hash_seeded(j, salt + 2.0, 31.0, s);
		float high = (6.0 + 16.0 * hash_seeded(j, salt + 3.0, 31.0, s)) * r / 40.0;
		bool big = hash_seeded(j, salt + 4.0, 31.0, s) < 0.45;
		vec3 now = chunk_at(way, far, flight, high, t);
		vec3 back = chunk_at(way, far, flight, high, max(t - 0.084, 0.0));
		vec2 head = floor(now.xy - vec2(0.0, now.z) + 0.5);
		vec2 tail = floor(back.xy - vec2(0.0, back.z) + 0.5);
		bool flying = t < flight;
		vec3 rgb;
		if (t < 0.07) {
			rgb = L.hot;
		} else if (stone) {
			rgb = t < 0.2 ? L.hi : (t < flight + 0.14 ? STONE_LIGHT : STONE_BASE);
		} else {
			rgb = flying ? heat(L, 0.1 + t / flight * 0.3) : (t - flight < 0.9 ? heat(L, 0.4 + (t - flight) / 0.9 * 0.4) : STONE_SHADOW);
		}
		shown = true;
		m = M_PIECE;
		a0 = vec4(head, flying ? tail : head);
		a1 = vec4(floor(now.xy + 0.5), now.z > 2.0 ? 1.0 : 0.0, big ? 1.0 : 0.0);
		// How much of it is left: it crumbles from 1.15 s.
		a2 = vec4(t < 1.15 ? 1.0 : 1.0 - (t - 1.15) / 0.45, 0.0, 0.0, 0.0);
		k0 = vec4(rgb, 1.0);
		k1 = vec4(stone && t > 0.12 ? STONE_LIGHT : heat(L, 0.4 + t / flight * 0.3), 1.0);
		q_lo = min(min(head, tail), a1.xy) - 2.0;
		q_hi = max(max(head, tail), a1.xy) + 3.0;
	} else if (kind == B_FIREBALL && slot == 0.0) {
		// The stem of smoke from the floor up to the ball (M_STREAK: a0 its ends, a1.x its
		// half width, a1.y how much of it is left).
		shown = rise > 1.0 && f < 1.0;
		m = M_STREAK;
		a0 = vec4(0.0, 0.0, 0.0, -rise);
		a1 = vec4(2.0 * r / 40.0 + 1.0, (1.0 - f) * 0.9, 0.0, 0.0);
		k0 = vec4(SMOKE_BASE, 1.0);
		k1 = vec4(SMOKE_LIGHT, 1.0);
		q_lo = vec2(-a1.x - 2.0, -rise - 1.0);
		q_hi = vec2(a1.x + 3.0, 1.0);
	} else if (kind == B_FIREBALL && slot <= 16.0) {
		// The dust ring rolling out along the floor at its foot: 16 puffs.
		float i = slot - 1.0;
		float da = t / 0.6;
		float turn = i / 16.0 * 6.2832;
		vec2 at = vec2(cos(turn), sin(turn) * 0.6) * r * (0.4 + 0.75 * ease_out(min(da, 1.0)));
		float reach = 2.0 + da * 2.0;
		shown = da < 1.0;
		a0 = vec4(at, reach, 0.0);
		a1 = vec4((1.0 - da) * 0.9, 0.0, 0.5, 0.0);
		k0 = vec4(STONE_LIGHT, 1.0);
		k1 = vec4(STONE_BASE, 1.0);
		q_lo = floor(at - reach) - 1.0;
		q_hi = floor(at + reach) + 2.0;
	} else if (kind == B_FIREBALL && slot <= 21.0) {
		// Its five lobes, the middle one drawn last: each pops in a beat after the first, swells,
		// cools from the rim in to smoke and drifts up off the rising ball.
		float k = 21.0 - slot;
		float t0 = k > 0.0 ? 0.02 + 0.09 * hash_seeded(k, 90.0, 31.0, s) : 0.0;
		float la = t - t0;
		float lf = la / (FIREBALL_SECONDS - t0);
		float turn = hash_seeded(k, 91.0, 31.0, s) * 6.2832;
		float out_by = k > 0.0 ? ball * 0.5 * (0.5 + 0.5 * hash_seeded(k, 92.0, 31.0, s)) : 0.0;
		float reach = ball * 0.75 * (0.7 + 0.3 * hash_seeded(k, 93.0, 31.0, s)) * ease_out3(clamp(la / 0.12, 0.0, 1.0)) * (1.0 + la * 0.35);
		vec2 at = vec2(cos(turn) * out_by, -rise + sin(turn) * out_by * 0.8 - max(0.0, la - 0.15) * 6.0);
		float hc = lf * 1.25 - 0.1;
		shown = la > 0.0 && lf < 1.0 && reach > 0.5;
		a0 = vec4(at, reach, 0.0);
		// Fire while the middle is hot, a thinning dither of smoke once it is not.
		a1 = vec4(hc < 1.0 ? (lf < 0.5 ? 1.0 : (1.0 - lf) * 2.0) : (1.0 - lf) * 1.6, 0.0, 0.4, 1.0);
		k0 = vec4(k == 0.0 && t < 0.07 ? L.hot : (hc < 1.0 ? heat(L, hc) : SMOKE_LIGHT), 1.0);
		k1 = vec4(hc + 0.2 < 1.0 ? heat(L, hc + 0.2) : SMOKE_BASE, 1.0);
		k2 = vec4(hc + 0.45 < 1.0 ? heat(L, hc + 0.45) : SMOKE_SHADOW, 1.0);
		q_lo = floor(at - reach) - 1.0;
		q_hi = floor(at + reach) + 2.0;
	} else if (kind == B_SCORCH && slot == 0.0) {
		// The burn: dark, densest in the middle, thinning out to its rim and fading.
		float sf = t / SCORCH_SECONDS;
		float reach = r * 0.62;
		shown = true;
		a0 = vec4(0.0, 0.0, reach, 0.0);
		a1 = vec4((1.0 - sf) * 1.1, 1.0, 0.45, 0.0);
		k0 = vec4(BURN_DEEP, 1.0);
		k1 = vec4(BURN_EDGE, 1.0);
		q_lo = vec2(-reach - 1.0);
		q_hi = vec2(reach + 2.0);
	} else if (kind == B_SCORCH && slot == 1.0) {
		// The whole radius lit for one frame.
		shown = t < 0.034;
		a0 = vec4(0.0, 0.0, r, 0.0);
		a1 = vec4(0.5, 0.0, 1.0, 0.0);
		k0 = vec4(L.lo, 1.0);
		q_lo = vec2(-r - 1.0);
		q_hi = vec2(r + 2.0);
	} else if (kind == B_SCORCH && slot < 16.0) {
		// Embers glowing in the burn, flickering, cooling out one by one.
		float i = slot - 2.0;
		float last = 0.6 + 0.8 * hash_seeded(i, 80.0, 31.0, s);
		float g = t / last;
		float turn = hash_seeded(i, 81.0, 31.0, s) * 6.2832;
		vec2 at = floor(vec2(cos(turn), sin(turn) * FLOOR_FLAT) * r * 0.53 * sqrt(hash_seeded(i, 82.0, 31.0, s)) + 0.5);
		bool flicker = g > 0.4 && mod(floor(t * 12.0 + i), 5.0) == 0.0;
		shown = g < 1.0 && !flicker;
		a0 = vec4(at, 0.6, 0.0);
		a1 = vec4(1.0, 0.0, 1.0, 0.0);
		k0 = vec4(heat(L, 0.3 + g * 0.7), 1.0);
		q_lo = at - 1.0;
		q_hi = at + 2.0;
	}
	// Nothing outside the square.
	q_lo = max(q_lo, -o);
	q_hi = min(q_hi, size - o);
	shown = shown && all(lessThan(q_lo, q_hi));
	vec2 p = mix(q_lo, q_hi, corner);
	vec2 uv = (p + o) / size;
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
// its quad's vertices worked out. No loops.

void fragment() {
	vec2 d = floor(px);
	vec4 colour = vec4(0.0);
	if (mode < M_LIGHT + 0.5) {
		// The light: v0.w x the falloff from v0.xy over v0.z, in c0.
		colour = vec4(c0.rgb * v0.w * falloff(length(d - v0.xy), v0.z) * glow_strength, 0.0);
	} else if (mode < M_BLOB + 0.5) {
		// A disc round v0.xy of reach v0.z: c0 inside v1.z of it, c1 out to the rim, c2 on the
		// rim when it has one; kept at v1.x, thinning towards the rim by v1.y, in an ordered
		// dither (noise for a fire lobe, v1.w).
		float q = length(d - floor(v0.xy));
		float k = q / max(v0.z, 0.5);
		float cut = v1.w > 0.5 ? hash_seeded(d.x, d.y, 61.0, v0.x) : bayer4(d);
		bool kept = q <= v0.z && cut < v1.x * (1.0 - k * k * v1.y);
		vec4 rgb = q > v0.z - 1.3 && c2.a > 0.0 ? c2 : (k < v1.z ? c0 : c1);
		colour = kept ? rgb : vec4(0.0);
	} else if (mode < M_STREAK + 0.5) {
		// A line from v0.xy to v0.zw, v1.x either side of it, kept at v1.y; its left side c1.
		vec2 ab = v0.zw - v0.xy;
		vec2 rel = d + 0.5 - v0.xy;
		float along = clamp(dot(rel, ab) / max(dot(ab, ab), 1.0), 0.0, 1.0);
		float side = rel.x - ab.x * along;
		bool kept = abs(side) <= v1.x && bayer4(d) < v1.y;
		colour = kept ? (side < -v1.x * 0.3 ? c1 : c0) : vec4(0.0);
	} else if (mode < M_PIECE + 0.5) {
		// A chunk: its block at v0.xy (2 px wide, 2 tall when v1.w), the streak back to v0.zw in
		// c1 fading to its end, its shadow at v1.xy while it is up (v1.z); v2.x of it is left.
		vec2 b = d - v0.xy;
		bool block = b.x >= 0.0 && b.x <= 1.0 && b.y >= 0.0 && b.y <= v1.w;
		vec2 ab = v0.zw - v0.xy;
		vec2 rel = d - v0.xy;
		float along = clamp(dot(rel, ab) / max(dot(ab, ab), 1.0), 0.0, 1.0);
		float off = length(rel - ab * along);
		bool streak = dot(ab, ab) > 1.0 && off < 0.6 && hash_seeded(d.x, d.y, 63.0, v0.z) > along;
		bool shadow = v1.z > 0.5 && all(equal(d, v1.xy));
		bool left = hash_seeded(d.x, d.y, 64.0, v0.w) < v2.x;
		colour = !left ? vec4(0.0) : (block ? c0 : (streak ? c1 : (shadow ? vec4(BURN_DEEP, 1.0) : vec4(0.0))));
	} else {
		// The ragged shell: v0.x its radius, v0.y the seconds, v0.z the seed. Its edge is noise
		// round the circle (12 buckets, smoothed, a new draw every 0.1 s) between 88% and 100%
		// of the radius; it crumbles pixel by pixel from the middle out as it cools.
		float r = v0.x;
		float t = v0.y;
		float s = v0.z;
		float f = t / SHELL_SECONDS;
		float grow = 1.0 - pow(1.0 - min(t / 0.06, 1.0), 3.0);
		float q = length(d);
		float u = fract(atan(d.y, d.x) / 6.2832 + 1.0) * 12.0;
		float i = floor(u);
		float draw = floor(t * 10.0) * 13.0;
		float wob = mix(hash_seeded(i + draw, 65.0, 31.0, s), hash_seeded(mod(i + 1.0, 12.0) + draw, 65.0, 31.0, s), smoothstep(0.0, 1.0, u - i));
		float edge = r * grow * (0.88 + 0.12 * wob);
		bool gone = q > edge || hash_seeded(d.x, d.y, 66.0, s) < f * 1.5 - (1.0 - q / max(edge, 1.0)) * 0.4;
		float h = q > edge - 1.2 ? f * 0.6 : 0.05 + f * 0.95 + (1.0 - q / max(edge, 1.0)) * 0.15;
		vec3 rgb = h < 0.08 ? c0.rgb : (h < 0.28 ? c1.rgb : (h < 0.6 ? c2.rgb : v2.rgb));
		// The pop: white-hot in the middle for its first 0.07 s.
		bool pop = t < 0.07 && q < 4.0 - t * 40.0;
		colour = pop ? vec4(q < 1.5 ? c0.rgb : c1.rgb, 1.0) : (gone ? vec4(0.0) : vec4(rgb, 1.0));
	}
	COLOR = colour;
}
