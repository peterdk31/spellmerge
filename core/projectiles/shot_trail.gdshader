// SPDX-License-Identifier: GPL-3.0-or-later
shader_type canvas_item;
// world_vertex_coords: VERTEX is in world space in vertex(), so each quad is placed in the world
// and every pixel can be found on the world's pixel grid (nothing else moves its vertices).
render_mode blend_premul_alpha, world_vertex_coords;

// A shot in flight and its trail (the projectile manager's trail batches; core/README.md, "The
// shot shaders"; the owner, 2026-10-28: "the tail of projectiles turn with the projectile"): a
// shot leaves its tail in the world, where it was, as the mockup does.
// The projectile manager keeps each shot's path in `trail_data`, one row per trail of
// TRAIL_SAMPLES texels (x, y, odometer, time; TRAIL_ROWS_PER_LINE rows to a line of the
// texture, `trail_texel`), a ring written 30 times a second and at every
// bounce and end. Each pixel of travel (a very fast shot's every 2-4, `gap`) leaves one tail pixel there, which drifts a little and
// cools through the ramp in its own time (0.1-0.3 s), so the tail bends with any path and frays
// at its end by itself. The card particles a shot gives off are not drawn here: they are motes
// (S3, docs/milestones/spell-spectacle-2.md; the projectile manager hands them out as births,
// `spark_births`, and Feel's motes throw them), and neither are a dash's speed streaks (motes too
// since S5; a dash's trail is not drawn). A pixel's number is its place on the path (the
// odometer), so it stays the same pixel from frame to frame. A trail outlives its shot by its
// longest life, so a tail cools where it ended. With the tails off (S5, the projectile manager's
// `tails_enabled`) a shot has no row: only its core and the core's light are drawn, turned the
// way its instance says it flies.
// Everything is drawn on the world's pixel grid, axis-aligned: the core is a `+` whatever way
// the shot flies, and a line is one pixel per step, as the mockup draws it.
//
// PARTICLES ARE GEOMETRY (the owner, 2026-10-29). Windows browsers compile WebGL through
// Direct3D, and the big, branchy fragment stage this shader had (every pixel walking its piece's
// tail pixels and births, a branch per look kind) took the compiler about 90 s on a real GPU,
// until the browser killed its GPU process. So the VERTEX stage does the work and the fragment
// stage only colours a pixel of its own quad: a few small modes, no loops, no kinds.
// A trail is one instance of a mesh (`trail_mesh` in projectile_manager.gd) of small quads, each
// told in its UV which QUAD KIND (Q_*) and which slot it is. The vertex shader works out, from
// `trail_data`, what that slot is now and puts its quad round it alone, or folds it away:
//   Q_HEAD_LIGHT  the core's light (and void's dark heart);
//   Q_PIECE_LIGHT a piece of the path between two samples, the tail's light round it;
//   Q_TAIL        tail pixel `slot` back from the head along the path;
//   Q_JAG         a 4-pixel step of the jagged line lightning draws behind its shot;
//   Q_CORE        the core: a white-hot `+`, pierce's run, void's dark heart.
// The mesh draws the lights first (added; the head's first, as its dark heart dims what is
// under it), then the pixels, oldest first and the core last, so the newest is on top.
// A quad is one triangle (performance, 2026-11-02: every vertex runs the whole vertex stage, and
// three are a quarter less than four): its corners are the box's low corner and twice the box
// along each axis, so the box is inside it, and the fragment stage cuts it to the box (`box`), a
// pixel in it when its centre is, as a square's two triangles take it.
// The instance carries its data in its transform (the batch must sit untransformed at the
// origin): origin the head (where the shot is drawn this frame), x axis (row, newest sample's
// number), y axis (samples kept, TF_* flags); a shot with no row (-1) has the way it flies (x, y)
// where the samples kept and the newest sample's number are. The colour and the custom data are the look
// (`shot_look.gdshaderinc`; worked out per vertex here, `look_from_color`).

#include "res://core/projectiles/shot_palette.gdshaderinc"
#include "res://core/projectiles/shot_look.gdshaderinc"

// The pool's share of the tails (set by the projectile manager, 1.0 is everything): the fraction
// of every tail that is drawn this frame.
uniform float trail_share = 1.0;
// The paths, and the moment the heads are drawn at (the simulation clock less what the drawing
// lags behind the last step), in the samples' clock.
uniform sampler2D trail_data : filter_nearest;
uniform float trail_now = 0.0;

// Samples a row holds (TRAIL_SAMPLES in projectile_manager.gd), the steps of a search through
// them (2^5 = 32), and the flags (TRAIL_* there): the shot is alive (its core is drawn and its
// path runs on to the head), an orbit shot (a shorter tail).
const int TRAIL_SAMPLES = 32;
const int TRAIL_ROWS_PER_LINE = 64;
const int SEARCH_STEPS = 5;
const float TF_HEAD = 1.0;
const float TF_ORBIT = 2.0;
// The longest anything of a trail lives (TRAIL_KEEP; no particle row lives longer).
const float TRAIL_LONGEST = 1.0;
// The tail pixels a trail has (TRAIL_TAIL_PIXELS), and the most pixels of path one of them
// stands for: a shot too fast to leave one every pixel for its tail's life leaves one every
// `gap` (up to TAIL_GAP_MAX), so its tail reaches as far, sparser (an atom's long streak).
const float TAIL_PIXELS = 128.0;
const float TAIL_GAP_MAX = 4.0;
// The quad kinds (TRAIL_Q_* in projectile_manager.gd), in UV.y.
const float Q_HEAD_LIGHT = 0.0;
const float Q_PIECE_LIGHT = 1.0;
const float Q_TAIL = 4.0;
const float Q_JAG = 5.0;
const float Q_CORE = 6.0;
// The fragment's modes: a round light, the tail's light round a piece, pixels (a square, a
// cross, a line beside it), a one-pixel line.
const float M_GLOW = 0.0;
const float M_TAIL_GLOW = 1.0;
const float M_PIXELS = 2.0;
const float M_LINE = 3.0;
// A neighbour or a line that is not there.
const vec2 FAR = vec2(1.0e7);

// What the vertex stage hands a pixel (by mode; see `fragment`): the pixel's world position, the
// mode, three numbers and three colours.
varying vec2 world;
varying flat vec4 box;
varying flat float mode;
varying flat vec4 v0;
varying flat vec4 v1;
varying flat vec4 v2;
varying flat vec4 c0;
varying flat vec4 c1;
varying flat vec4 c2;

// ---- Vertices ----

// Sample `k` back from the newest (0) of trail `row`: x, y, odometer, time. The rows lie
// TRAIL_ROWS_PER_LINE to a line of the texture (a texture one row a line was too tall for the GPU
// at the high caps).
vec4 trail_texel(float row, float newest, float k) {
	float n = newest - k;
	int r = int(row);
	ivec2 at = ivec2((r % TRAIL_ROWS_PER_LINE) * TRAIL_SAMPLES + int(mod(n, float(TRAIL_SAMPLES))), r / TRAIL_ROWS_PER_LINE);
	return texelFetch(trail_data, at, 0);
}

// For each of `v`'s two numbers, the newest sample from `first` back to `last` whose odometer is
// at most it, the older end of the piece it is on: its k, or -1 when
// even the oldest is later. Both are searched at once, and the vertex stage searches the path in
// one place only (`vertex`): the compiler builds a loop once for every place it is called from,
// and the Direct3D one takes its time over each.
vec2 samples_before(float row, float newest, float first, float last, vec2 v) {
	vec2 lo_k = vec2(first);
	vec2 hi_k = vec2(last);
	for (int i = 0; i < SEARCH_STEPS; i++) {
		vec2 half_k = floor((lo_k + hi_k) * 0.5);
		vec4 s0 = trail_texel(row, newest, half_k.x);
		vec4 s1 = trail_texel(row, newest, half_k.y);
		vec2 earlier = vec2(lessThanEqual(vec2(s0.z, s1.z), v));
		hi_k = mix(hi_k, half_k, earlier);
		lo_k = mix(half_k + 1.0, lo_k, earlier);
	}
	vec4 s0 = trail_texel(row, newest, lo_k.x);
	vec4 s1 = trail_texel(row, newest, lo_k.y);
	vec2 earlier = vec2(lessThanEqual(vec2(s0.z, s1.z), v));
	vec2 inside = vec2(lessThanEqual(lo_k, vec2(last))) * (first <= last ? 1.0 : 0.0);
	return mix(vec2(-1.0), lo_k, earlier * inside);
}

// A number in [0, 1) from three whole numbers and the trail's row: an integer hash, so a pixel's
// number (its place on the path, its moment) keeps its looks however large it grows.
uint mix_bits(uint x) {
	x ^= x >> 16u;
	x *= 2146121005u;
	x ^= x >> 15u;
	x *= 2221713035u;
	x ^= x >> 16u;
	return x;
}

float th(float a, float b, float c, float row) {
	uint h = mix_bits(uint(int(a)) ^ mix_bits(uint(int(b)) + mix_bits(uint(int(c)) + uint(int(row)) * 7919u + 40503u)));
	return float(h & 16777215u) / 16777216.0;
}

// How far a pixel thrown at 1 px/s has gone after `ago` seconds, slowed by `drag` each 60th of a
// second (the mockup's particles).
float dragged(float ago, float drag) {
	float f = ago * 60.0;
	return drag * (1.0 - pow(drag, f)) / (1.0 - drag) / 60.0;
}

void vertex() {
	float row = MODEL_MATRIX[0].x;
	float newest = MODEL_MATRIX[0].y;
	float count = row < 0.0 ? 0.0 : MODEL_MATRIX[1].x;
	float flags = MODEL_MATRIX[1].y;
	vec2 head = MODEL_MATRIX[3].xy;
	// The mesh's vertex: its slot and corner in UV.x (slot + 0.25 or 0.75), its quad kind and
	// corner in UV.y (kind + 0.25 or 0.75); a corner of the triangle is 0 or twice the box.
	float slot = floor(UV.x);
	float quad = floor(UV.y);
	vec2 corner = vec2(fract(UV.x) > 0.5 ? 2.0 : 0.0, fract(UV.y) > 0.5 ? 2.0 : 0.0);
	Look L = look_from_color(COLOR, INSTANCE_CUSTOM.rgb, row < 0.0 ? 0.0 : mod(row, 61.0) * 1.618, true);
	// Zoom 0 in the look (`look_core_zoom`): a speck, its core one pixel; the rest is drawn at 1.
	bool speck = floor(COLOR.r * 255.0 + 0.5) < 4.0;
	float z = L.zoom;
	vec3 b = L.bits;
	int pi = int(L.player);
	bool live = flag_set(flags, TF_HEAD);
	bool lightning = bit_set(b, L_SPARKS);
	bool pull = bit_set(b, L_PULL);
	float mul = bit_set(b, L_FLECKS) ? 1.5 : (bit_set(b, L_SPARKS) ? 0.7 : (pull ? 1.1 : 1.0));
	if (flag_set(flags, TF_ORBIT)) {
		mul *= 0.8;
	}
	float tail = 0.3 * mul * trail_share;
	// Every light of the trail: lightning flickers, void's is dimmer.
	float flicker = (lightning ? 0.55 + 0.9 * hash_seeded(floor(sim_time * 20.0), 0.0, 21.0, L.seed) : 1.0) * (pull ? 0.6 : 1.0);
	vec3 hue = L.glow;
	// The newest samples can be later than the moment drawn (taken in the step being drawn
	// towards): they are not drawn yet.
	float skip = 0.0;
	for (int j = 0; j < 4; j++) {
		if (float(j) >= count || trail_texel(row, newest, float(j)).w <= trail_now + 0.0001) {
			break;
		}
		skip += 1.0;
	}
	// Where the shot is (or was last), and the newest end of its path: the head while it lives.
	vec4 last = count > skip ? trail_texel(row, newest, skip) : vec4(head, 0.0, trail_now);
	vec2 target = live || count <= skip ? head : last.xy;
	vec4 head_end = vec4(head, last.z + distance(head, last.xy), trail_now);
	float o_top = live ? head_end.z : last.z;
	float t_top = live ? trail_now : last.w;
	if (count <= skip || (!live && count - skip < 2.0)) {
		t_top = -1.0e9;
		o_top = -1.0e9;
	}
	vec2 q_lo = vec2(0.0);
	vec2 q_hi = vec2(0.0);
	float m = M_PIXELS;
	vec4 a0 = vec4(0.0);
	vec4 a1 = vec4(FAR, FAR);
	vec4 a2 = vec4(0.0);
	vec4 k0 = vec4(0.0);
	vec4 k1 = vec4(0.0);
	vec4 k2 = vec4(0.0);
	bool shown = false;
	// A tail pixel's number (its place on the path: one every `gap` pixels, from the shot's pace
	// over its whole kept path, so it holds still while the shot flies), and the ends of a step of
	// lightning's line.
	float gap = 1.0;
	if (count - skip >= 2.0) {
		vec4 oldest = trail_texel(row, newest, count - 1.0);
		float pace = (o_top - oldest.z) / max(t_top - oldest.w, 0.001);
		gap = clamp(ceil(pace * tail / TAIL_PIXELS), 1.0, TAIL_GAP_MAX);
	}
	float n = (ceil(o_top / gap) - 1.0 - slot) * gap;
	float o_hi = min(4.0 * (floor(o_top / 4.0) - slot + 1.0), o_top);
	float o_lo = 4.0 * (floor(o_top / 4.0) - slot);
	// The one search of the path: the pieces the quad's moment, pixel or step ends are on. Only a
	// slot that may still draw searches (performance, 2026-11-02: the search is most of a vertex's
	// work): a tail pixel while the trail has a tail, a step of lightning's line. The head, the core
	// and the pieces' lights never read it.
	bool search = quad == Q_TAIL ? tail > 0.0 : quad == Q_JAG && lightning;
	vec2 before = vec2(-1.0);
	if (search) {
		vec2 key = quad == Q_TAIL ? vec2(n) : vec2(o_hi, o_lo);
		before = samples_before(row, newest, skip, count - 1.0, key);
	}
	if (quad == Q_HEAD_LIGHT || quad == Q_CORE) {
		// The head, while the shot lives: the core and its light.
		if (live) {
			shown = true;
			// The way it flies: from its newest sample to the head; with no row (tails off, S5) the
			// instance's way (`_write_trail`), in the row's numbers' place.
			vec2 way = vec2(MODEL_MATRIX[1].x, MODEL_MATRIX[0].y);
			vec2 last_at = row < 0.0 ? head - way : (count > 0.0 ? trail_texel(row, newest, 0.0).xy : head - vec2(1.0, 0.0));
			vec2 fly = head - last_at;
			fly = length(fly) > 0.01 ? normalize(fly) : vec2(1.0, 0.0);
			vec2 at = head;
			if (bit_set(b, L_WEAVE)) {
				// Homing weaves it a pixel either side.
				at += vec2(-fly.y, fly.x) * (triangle(sim_time * 3.0 + L.seed * 0.25) > 0.0 ? 1.0 : 0.0);
			}
			vec2 px = floor(at);
			if (quad == Q_HEAD_LIGHT) {
				m = M_GLOW;
				// A speck's light is a smaller one.
				float reach = speck ? 6.0 : 8.0 + 2.0 * z;
				q_lo = px + 0.5 - reach;
				q_hi = px + 0.5 + reach;
				a0 = vec4(px + 0.5, pull ? 0.45 : 0.0, 6.0);
				a1 = vec4((speck ? 0.6 : 0.8) * flicker, speck ? 2.0 : 3.0 + z, 0.35 * flicker, reach);
				k0 = vec4(hue, 1.0);
			} else {
				// A white-hot pixel with four round it, a pixel more each side a zoom (a speck's
				// is the pixel alone); pierce lengthens it along the flight; void's is a dark
				// heart ringed in pink.
				float half_size = 3.0 + 2.0 * z;
				q_lo = px - half_size;
				q_hi = px + half_size + 1.0;
				a0 = vec4(px, 1.0, speck ? 0.0 : z);
				if (bit_set(b, L_STREAKS)) {
					a1 = vec4(at, at - fly * (2.0 + z));
				}
				k0 = vec4(pull ? OUTLINE : L.hot, 1.0);
				k1 = vec4(pull ? VOID_LIGHT : L.hi, 1.0);
				k2 = pull ? vec4(VOID_BASE, 1.0) : vec4(0.0);
			}
		}
	} else if (quad == Q_PIECE_LIGHT) {
		// A piece of the path: from sample `slot` + skip to the next newer (or the head), and the
		// tail's light round it while it is young.
		float ia = slot + skip;
		if (ia < count && (slot > 0.5 || live)) {
			vec4 A = trail_texel(row, newest, ia);
			vec4 B = slot < 0.5 ? head_end : trail_texel(row, newest, ia - 1.0);
			vec2 ab = B.xy - A.xy;
			float len = length(ab);
			if (trail_now - B.w <= tail && len >= 0.001 && B.z - A.z >= 0.001) {
				shown = true;
				m = M_TAIL_GLOW;
				// The far ends of its neighbours: a pixel takes its light from the piece nearest it.
				if (ia + 1.0 < count) {
					a1.xy = trail_texel(row, newest, ia + 1.0).xy;
				}
				if (slot > 1.5) {
					a1.zw = trail_texel(row, newest, ia - 2.0).xy;
				} else if (slot > 0.5 && live) {
					a1.zw = head;
				}
				float reach = 8.0 + 2.0 * z;
				q_lo = min(A.xy, B.xy) - reach;
				q_hi = max(A.xy, B.xy) + reach;
				float speed = len / max(B.w - A.w, 0.001);
				float tl = max(tail, 0.01);
				a0 = vec4(A.xy, B.xy);
				a2 = vec4((trail_now - A.w) / tl, (trail_now - B.w) / tl, 3.0 + z + speed * 0.012 + 6.0, z);
				k0 = vec4(hue, (pull ? 0.45 : 0.75) * flicker);
			}
		}
	} else if (quad == Q_TAIL) {
		// Tail pixel `slot` back from the head: one pixel per pixel of travel, thrown back a
		// little, cooling as it ages (and lightning's only now and then).
		float k = before.x;
		if (k >= 0.0) {
			vec4 A = trail_texel(row, newest, k);
			vec4 B = k < skip + 0.5 ? head_end : trail_texel(row, newest, k - 1.0);
			vec2 ab = B.xy - A.xy;
			float len = length(ab);
			float fr = (n - A.z) / max(B.z - A.z, 0.001);
			float tn = mix(A.w, B.w, fr);
			float ago = trail_now - tn;
			float life = (0.1 + 0.2 * th(n, 0.0, 162.0, row)) / 0.3 * tail;
			if (len >= 0.001 && B.z - A.z >= 0.001 && ago >= 0.0 && ago < life && !(lightning && th(n, 0.0, 161.0, row) > 0.35)) {
				vec2 dir = ab / len;
				float speed = len / max(B.w - A.w, 0.001);
				vec2 v = -dir * speed * 0.04 + (vec2(th(n, 0.0, 163.0, row), th(n, 0.0, 164.0, row)) - 0.5) * 5.0;
				vec2 pos = mix(A.xy, B.xy, fr) + (vec2(th(n, 0.0, 165.0, row), th(n, 0.0, 166.0, row)) - 0.5) * 0.8 + v * dragged(ago, 0.94);
				if (bit_set(b, L_GUSTS)) {
					// Storm: the tail sways side to side as it is left.
					pos += vec2(-dir.y, dir.x) * sin(tn * 30.0) * 1.4;
				}
				float u = ago / life;
				vec3 rgb = u < 0.17 ? L.hot : (u < 0.45 ? L.hi : (u < 0.8 ? L.mid : L.lo));
				if (L.plain < 0.5 && th(n, 0.0, 167.0, row) < 0.25) {
					// A quarter of an infused tail is its player's colour.
					rgb = u < 0.25 ? P_LIGHT[pi] : (u < 0.75 ? P_BASE[pi] : P_SHADOW[pi]);
				}
				float size = max(z - 1.0, 1.0);
				vec2 px = floor(pos) - floor((size - 1.0) * 0.5);
				shown = true;
				q_lo = px;
				q_hi = px + size;
				a0 = vec4(px, size, 0.0);
				k0 = vec4(rgb, 1.0);
			}
		}
	} else if (quad == Q_JAG && lightning) {
		// Step `slot` back from the head of the jagged line lightning draws behind its shot along
		// the last tenth of a second of its path: it bends every 4 pixels, re-rolled every other
		// frame, newer than 0.05 s in its light.
		float jf = floor(trail_now * 30.0);
		vec2 ends[2];
		float agos[2];
		bool found = o_hi > o_lo;
		for (int e = 0; e < 2; e++) {
			float o = e == 0 ? o_hi : o_lo;
			float k = e == 0 ? before.x : before.y;
			found = found && k >= 0.0;
			vec4 A = trail_texel(row, newest, max(k, 0.0));
			vec4 B = k < skip + 0.5 ? head_end : trail_texel(row, newest, k - 1.0);
			float fr = clamp((o - A.z) / max(B.z - A.z, 0.001), 0.0, 1.0);
			vec2 ab = B.xy - A.xy;
			vec2 dir = length(ab) > 0.001 ? normalize(ab) : vec2(1.0, 0.0);
			agos[e] = trail_now - mix(A.w, B.w, fr);
			float node = floor(o / 4.0);
			float off = mix((th(node, jf, 171.0, row) - 0.5) * 4.0, (th(node + 1.0, jf, 171.0, row) - 0.5) * 4.0, fract(o / 4.0)) * min(agos[e] / 0.02, 1.0);
			ends[e] = mix(A.xy, B.xy, fr) + vec2(-dir.y, dir.x) * off;
		}
		if (found && agos[0] <= 0.1) {
			vec2 p0 = ends[0];
			vec2 p1 = ends[1];
			float span = max(agos[1] - agos[0], 0.0001);
			if (agos[1] > 0.1) {
				// Cut where it is a tenth of a second old.
				p1 = mix(p0, p1, (0.1 - agos[0]) / span);
			}
			shown = true;
			m = M_LINE;
			q_lo = min(p0, p1) - 1.0;
			q_hi = max(p0, p1) + 1.0;
			a0 = vec4(p0, p1);
			a2 = vec4(clamp((0.05 - agos[0]) / span, 0.0, 1.0) * distance(ends[0], ends[1]), 0.0, 0.0, 0.0);
			k0 = vec4(ARC_LIGHT, 1.0);
			k1 = vec4(ARC_BASE, 1.0);
		}
	}
	// Folded away when there is nothing to draw.
	VERTEX = shown ? q_lo + (q_hi - q_lo) * corner : vec2(-1.0e6);
	world = VERTEX;
	box = vec4(q_lo, q_hi);
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
// its quad's vertices worked out. No loops, no look kinds, nothing read from the path.

// True when the pixel at `P` is on the one-pixel line from `a` to `b`, drawn as the mockup's
// lines are: one pixel per step along the longer axis; `along` is how far along it is.
bool on_line(vec2 P, vec2 a, vec2 b, out float along) {
	vec2 ab = b - a;
	float l = length(ab);
	vec2 c = floor(P) + 0.5;
	if (l < 0.5) {
		along = 0.0;
		return all(equal(floor(P), floor(a)));
	}
	vec2 dir = ab / l;
	along = dot(c - a, dir);
	float s = dot(c - a, vec2(-dir.y, dir.x));
	float thin = 0.5 * max(abs(dir.x), abs(dir.y));
	return along >= -0.5 && along <= l + 0.5 && s >= -thin && s < thin;
}

// How far `c` is from the piece `p`-`q`, or very far when there is no such piece.
float piece_distance(vec2 c, vec2 p, vec2 q) {
	vec2 pq = q - p;
	float len = length(pq);
	if (p.x > 1.0e6 || q.x > 1.0e6 || len < 0.001) {
		return 1.0e9;
	}
	return length(c - (p + pq * clamp(dot(c - p, pq) / (len * len), 0.0, 1.0)));
}

void fragment() {
	vec2 P = world;
	vec2 c = floor(P) + 0.5;
	vec4 colour = vec4(0.0);
	if (mode < M_GLOW + 0.5) {
		// A round light (v0 its middle, the dark it casts and how far; v1 two falloffs).
		float r = length(c - v0.xy);
		float lit = v1.x * falloff(r, v1.y) + v1.z * falloff(r, v1.w);
		colour = vec4(c0.rgb * lit * glow_strength, v0.z * falloff(r, v0.w));
	} else if (mode < M_TAIL_GLOW + 0.5) {
		// The tail's light round its piece v0.xy-v0.zw, as bright as the tail is young there (v2.xy
		// its age at the ends, in tail lives), from the nearest piece (v1 the neighbours' far ends).
		vec2 ab = v0.zw - v0.xy;
		float f = clamp(dot(c - v0.xy, ab) / dot(ab, ab), 0.0, 1.0);
		float dist = length(c - (v0.xy + ab * f));
		float u = clamp(mix(v2.x, v2.y, f), 0.0, 1.0);
		float z = v2.w;
		float lit = c0.a * (1.0 - 0.75 * u) * (1.0 - u) * (0.32 * falloff(dist, 2.0 + z) + 0.36 * falloff(dist, 7.0 + 2.0 * z));
		// A tie goes to the newer piece.
		bool nearest = dist <= piece_distance(c, v1.xy, v0.xy) && dist < piece_distance(c, v0.zw, v1.zw);
		colour = vec4(c0.rgb * (dist <= v2.z && nearest ? lit : 0.0) * glow_strength, 0.0);
	} else if (mode < M_PIXELS + 0.5) {
		// Pixels: a square of v0.z from v0.xy in c0, a cross of arms v0.w round its pixel and a
		// line v1.xy-v1.zw in c1, the pixels between the arms in c2.
		vec2 d = floor(P) - v0.xy;
		vec2 a = abs(d);
		float along;
		if (d.x >= 0.0 && d.y >= 0.0 && d.x < v0.z && d.y < v0.z) {
			colour = c0;
		} else if (((a.x == 0.0 || a.y == 0.0) && a.x + a.y <= v0.w) || (v1.x < 1.0e6 && on_line(P, v1.xy, v1.zw, along))) {
			colour = c1;
		} else if (a.x == 1.0 && a.y == 1.0) {
			colour = c2;
		}
	} else {
		// A one-pixel line from v0.xy to v0.zw: c0 for its first v2.x pixels, then c1.
		float along;
		if (on_line(P, v0.xy, v0.zw, along)) {
			colour = along < v2.x ? c0 : c1;
		}
	}
	// Only the box's pixels: the rest of the triangle is outside the quad.
	bool inside = all(greaterThanEqual(c, box.xy)) && all(lessThan(c, box.zw));
	COLOR = inside ? colour : vec4(0.0);
}
