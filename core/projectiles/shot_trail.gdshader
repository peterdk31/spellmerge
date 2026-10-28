// SPDX-License-Identifier: GPL-3.0-or-later
shader_type canvas_item;
// world_vertex_coords: VERTEX is in world space in vertex(), so each piece places its own quad
// and every pixel can be found on the world's pixel grid (nothing else moves its vertices).
render_mode blend_premul_alpha, world_vertex_coords;

// A shot in flight and its trail (the projectile manager's trail batches; core/README.md, "The
// shot shaders"; the owner, 2026-10-28: "the tail of projectiles turn with the projectile"): a
// shot leaves its tail and its card particles in the world, where it was, as the mockup does.
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
//
// RIBBONS (the owner, 2026-10-29: the web build lost its WebGL context on a real GPU when every
// pixel of one big quad walked the whole path). A trail is one instance of a ribbon mesh
// (`trail_mesh` in projectile_manager.gd): a quad for its HEAD (piece 0) and one per PIECE of its
// path, the piece between two samples (piece 1 + k runs from sample k to the next newer, or to
// the head for k = 0). The vertex shader reads its piece's two ends from `trail_data` and puts
// the quad round that piece alone (a piece outside the trail's window is folded away), so a
// pixel works out only the tail pixels and the particles born on its own piece: no pixel loops
// over the path. What needs the whole history has a per-piece stand-in: the tail's light is the
// nearest piece's (its neighbours' far ends travel with it), not the brightest of all; the
// particles that circle the shot (void's pull, shields, glitter) are the head's, which walks the
// moments of their short lives (at most BIRTHS_MAX) in its own small quad.
// The mesh draws every quad in two PASSES: first the light (the head's, with void's dark heart,
// then every piece's), then the pixels, oldest piece first and the head last, so the shot's own
// light never lands on its pixels and the newest pixel is on top.
// The instance carries its data in its transform (the batch must sit untransformed at the
// origin): origin the head (where the shot is drawn this frame), x axis (row, newest sample's
// number), y axis (samples kept, TF_* flags). The colour and the custom data are the look
// (`shot_look.gdshaderinc`).

#include "res://core/projectiles/shot_palette.gdshaderinc"
#include "res://core/projectiles/shot_look.gdshaderinc"

// The spark pool's share (set by the projectile manager, 1.0 is everything): the fraction of
// every shot's particles and of every tail that is drawn this frame. Tails go first.
uniform float particle_share = 1.0;
uniform float trail_share = 1.0;
// The paths, and the moment the heads are drawn at (the simulation clock less what the drawing
// lags behind the last step), in the samples' clock.
uniform sampler2D trail_data : filter_nearest;
uniform float trail_now = 0.0;

// Samples a row holds (TRAIL_SAMPLES in projectile_manager.gd), the moments a particle may be
// born a second, and the flags (TRAIL_* there): the shot is alive (its core is drawn and its path
// runs on to the head), an orbit shot (a shorter tail), a wizard's dash (speed streaks in the
// player's colours and the dash's cards, no tail, no core).
const int TRAIL_SAMPLES = 32;
const float BIRTHS = 60.0;
const float TF_HEAD = 1.0;
const float TF_ORBIT = 2.0;
const float TF_DASH = 4.0;
// The longest anything of a trail lives, so the pieces drawn stop there.
const float TRAIL_LONGEST = 1.0;
// The most moments the head walks for the particles that circle the shot.
const int BIRTHS_MAX = 64;
// How far round the shot void's pulled pixels are (6-12 px) and their light reaches (7 px more).
const float PULL_REACH = 20.0;
// The most tail pixels a pixel looks at either side of its place on the path.
const float SPAN_MAX = 24.0;
// A neighbour that is not there.
const vec2 FAR = vec2(1.0e7);

// The world position of the pixel.
varying vec2 world;
// A piece: its older end and its newer end (x, y, odometer, time), and the far ends of its older
// and newer neighbours (xy, zw; FAR for none). The head: the moments its circling particles were
// born between (x to y, in seconds; z 1 when there are any), and the way the shot flies (seg_b.xy).
varying flat vec4 seg_a;
varying flat vec4 seg_b;
varying flat vec4 seg_near;
// Where the shot is (or was last: the void pulls in to it, shields circle it), its row, its flags.
varying flat vec4 trail_v;
// How far back the trail is drawn (seconds), how long its tail pixels live at most, how far round
// a piece its particles may wander (pixels), and the piece (0 the head) + 64 x the pass (0 the
// light, 1 the pixels).
varying flat vec4 trail_info;

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
	float row = MODEL_MATRIX[0].x;
	float newest = MODEL_MATRIX[0].y;
	float count = row < 0.0 ? 0.0 : MODEL_MATRIX[1].x;
	float flags = MODEL_MATRIX[1].y;
	vec2 head = MODEL_MATRIX[3].xy;
	// The ribbon mesh's vertex: its piece and corner in UV.x (piece + 0.25 or 0.75), its pass and
	// corner in UV.y (pass + 0.25 or 0.75).
	float piece = floor(UV.x);
	float pass = floor(UV.y);
	vec2 corner = vec2(fract(UV.x) > 0.5 ? 1.0 : 0.0, fract(UV.y) > 0.5 ? 1.0 : 0.0);
	float red = floor(COLOR.r * 255.0 + 0.5);
	float z = max(floor(red / 4.0), 1.0);
	vec3 b = floor(COLOR.gba * 255.0 + 0.5);
	bool live = flag_set(flags, TF_HEAD);
	bool dash = flag_set(flags, TF_DASH);
	float mul = bit_set(b, L_FLECKS) ? 1.5 : (bit_set(b, L_SPARKS) ? 0.7 : (bit_set(b, L_PULL) ? 1.1 : 1.0));
	if (flag_set(flags, TF_ORBIT)) {
		mul *= 0.8;
	}
	float tail = dash ? 0.0 : 0.3 * mul * trail_share;
	vec2 reach = trail_reach(b, flags, z, tail);
	// The newest samples can be later than the moment drawn (taken in the step being drawn
	// towards): they are not drawn yet.
	float skip = 0.0;
	for (int j = 0; j < 4; j++) {
		if (float(j) >= count || trail_texel(row, newest, float(j)).w <= trail_now + 0.0001) {
			break;
		}
		skip += 1.0;
	}
	vec2 target = head;
	if (!live && skip < count) {
		target = trail_texel(row, newest, skip).xy;
	}
	vec4 a = vec4(0.0);
	vec4 bb = vec4(0.0);
	vec4 near = vec4(FAR, FAR);
	bool shown = false;
	if (piece < 0.5) {
		// The head: the core and its light, and the particles that circle the shot.
		bool circling = !dash && (bit_set(b, L_PULL) || bit_set(b, L_ORBITERS) || bit_set(b, L_GLITTER));
		bool births = live ? count - skip >= 1.0 : count - skip >= 2.0;
		float half_size = live && !dash ? 8.0 + 2.0 * z : 0.0;
		if (circling && births) {
			half_size = max(half_size, bit_set(b, L_PULL) ? max(reach.y, PULL_REACH) : reach.y);
			vec4 oldest = trail_texel(row, newest, count - 1.0);
			vec4 last = trail_texel(row, newest, skip);
			// The particles that circle it live 0.8 s at most.
			a = vec4(max(oldest.w, trail_now - min(reach.x, 0.8)), live ? trail_now : last.w, 1.0, 0.0);
		}
		if (half_size > 0.0) {
			shown = true;
			// The way it flies: from its newest sample to the head.
			vec2 last_at = count > 0.0 ? trail_texel(row, newest, 0.0).xy : head - vec2(1.0, 0.0);
			vec2 fly = head - last_at;
			bb = vec4(length(fly) > 0.01 ? normalize(fly) : vec2(1.0, 0.0), 0.0, 0.0);
			VERTEX = target + (corner * 2.0 - 1.0) * (half_size + 1.0);
		}
	} else {
		// A piece: from sample k + skip to the next newer (or the head).
		float k = piece - 1.0;
		float ia = k + skip;
		if (ia < count && (k > 0.5 || live)) {
			a = trail_texel(row, newest, ia);
			bb = k < 0.5 ? vec4(head, a.z + distance(head, a.xy), trail_now) : trail_texel(row, newest, ia - 1.0);
			if (trail_now - bb.w <= reach.x) {
				shown = true;
				if (ia + 1.0 < count && trail_now - a.w <= reach.x) {
					near.xy = trail_texel(row, newest, ia + 1.0).xy;
				}
				if (k > 1.5) {
					near.zw = trail_texel(row, newest, ia - 2.0).xy;
				} else if (k > 0.5 && live) {
					near.zw = head;
				}
				vec2 ab = bb.xy - a.xy;
				float len = length(ab);
				vec2 axis = len > 0.5 ? ab / len : vec2(1.0, 0.0);
				vec2 side = vec2(-axis.y, axis.x);
				float m = reach.y;
				VERTEX = a.xy + axis * mix(-m, len + m, corner.x) + side * mix(-m, m, corner.y);
			}
		}
	}
	if (!shown) {
		// Folded away: nothing to draw.
		VERTEX = vec2(-1.0e6);
	}
	world = VERTEX;
	seg_a = a;
	seg_b = bb;
	seg_near = near;
	trail_v = vec4(target, row, flags);
	trail_info = vec4(reach.x, tail, reach.y, piece + 64.0 * pass);
	Look L = look_from_color(COLOR, INSTANCE_CUSTOM.rgb, row < 0.0 ? 0.0 : mod(row, 61.0) * 1.618, true);
	SET_LOOK(L);
}

// ---- Fragments ----

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
	uint h = mix_bits(uint(int(a)) ^ mix_bits(uint(int(b)) + mix_bits(uint(int(c)) + uint(int(trail_v.z)) * 7919u + 40503u)));
	return float(h & 16777215u) / 16777216.0;
}

// How far a pixel thrown at 1 px/s has gone after `ago` seconds, slowed by `drag` each 60th of a
// second (the mockup's particles).
float dragged(float ago, float drag) {
	float f = ago * 60.0;
	return drag * (1.0 - pow(drag, f)) / (1.0 - drag) / 60.0;
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
	if (emit_count() < 0.5) {
		return !dash && j < 0.5 && th(id, j, 151.0) < 0.18 * particle_share ? -1.0 : -2.0;
	}
	float look = emitter(int(min(floor(th(id, j, 152.0) * emit_count()), emit_count() - 1.0)));
	float rate = look == L_EMBERS ? 0.45 : (look == L_FLECKS ? 0.32 : (look == L_GUSTS ? 0.4 : (look == L_PULL ? 0.55 : (look == L_SPARKS ? 0.45 : 0.25))));
	if (dash) {
		rate = look == L_EMBERS ? 1.0 : (look == L_FLECKS ? 1.0 : min(rate * 2.0, 1.0));
	}
	return th(id, j, 153.0) < rate * particle_share ? look : -2.0;
}

// How far `c` is from the piece `p`-`q`, or very far when there is no such piece (FAR, or no
// length: it draws no light).
float piece_distance(vec2 c, vec2 p, vec2 q) {
	vec2 pq = q - p;
	float len = length(pq);
	if (p.x > 1.0e6 || q.x > 1.0e6 || len < 0.001) {
		return 1.0e9;
	}
	float f = clamp(dot(c - p, pq) / (len * len), 0.0, 1.0);
	return length(c - (p + pq * f));
}

// The light of the tail round the piece from `A` to `B` (each x, y, odometer, time; A the
// older), as bright as the tail is young there. A pixel takes it from the piece nearest it (of
// this piece and its two neighbours), which stands in for the brightest of the whole path.
float tail_light(vec4 A, vec4 B, vec2 P, float z) {
	vec2 ab = B.xy - A.xy;
	float len = length(ab);
	if (len < 0.001 || B.z - A.z < 0.001) {
		return 0.0;
	}
	vec2 dir = ab / len;
	float speed = len / max(B.w - A.w, 0.001);
	vec2 c = floor(P) + 0.5;
	float f = clamp(dot(c - A.xy, dir) / len, 0.0, 1.0);
	float dist = length(c - (A.xy + ab * f));
	if (dist > 3.0 + z + speed * 0.012 + 6.0) {
		return 0.0;
	}
	// The older neighbour's piece ends at A, the newer one's starts at B; a tie goes to the newer.
	if (dist > piece_distance(c, seg_near.xy, A.xy) || dist >= piece_distance(c, B.xy, seg_near.zw)) {
		return 0.0;
	}
	float tail_life = trail_info.y;
	float t_near = mix(A.w, B.w, f);
	float u_near = clamp((trail_now - t_near) / max(tail_life, 0.01), 0.0, 1.0);
	float glow_e = (has_layer(L_PULL) ? 0.45 : 0.75) * (1.0 - 0.75 * u_near) * (1.0 - u_near);
	return glow_e * (0.32 * falloff(dist, 2.0 + z) + 0.36 * falloff(dist, 7.0 + 2.0 * z));
}

// The tail pixels of the piece from `A` to `B`: one pixel per pixel of travel, thrown back a
// little, cooling as it ages.
void tail_pixels(vec4 A, vec4 B, vec2 P, float z, inout vec4 colour, inout float best) {
	vec2 ab = B.xy - A.xy;
	float len = length(ab);
	if (len < 0.001 || B.z - A.z < 0.001) {
		return;
	}
	vec2 dir = ab / len;
	float speed = len / max(B.w - A.w, 0.001);
	vec2 c = floor(P) + 0.5;
	float f = clamp(dot(c - A.xy, dir) / len, 0.0, 1.0);
	float dist = length(c - (A.xy + ab * f));
	// What is back along the path from the head drifts at most a few pixels.
	if (dist > 3.0 + z + speed * 0.012) {
		return;
	}
	float tail_life = trail_info.y;
	int pi = int(player);
	bool storm = has_layer(L_GUSTS);
	bool lightning = has_layer(L_SPARKS);
	float o = mix(A.z, B.z, f);
	float drift = 0.04 * speed + 3.0;
	float span = min(ceil(drift * dragged(tail_life, 0.94) + 2.0 + z), SPAN_MAX);
	for (int s = 0; s <= int(SPAN_MAX) * 2; s++) {
		float k = float(s) - span;
		if (k > span) {
			break;
		}
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

// The kinds whose particles circle the shot, not the place they were born.
bool circles(float look) {
	return look == L_PULL || look == L_ORBITERS || look == L_GLITTER;
}

// The particles born on the piece from `A` to `B`: one moment every 60th of a second, each
// moment up to `per` particles. A shot's circling particles are the head's (`head_births`); a
// dash's are drawn round where they were born, near its head.
void piece_births(vec4 A, vec4 B, vec2 P, float z, float reach, bool dash, vec2 target, inout vec4 colour, inout float best, inout float lit) {
	vec2 ab = B.xy - A.xy;
	float len = length(ab);
	vec2 dir = len > 0.001 ? ab / len : vec2(1.0, 0.0);
	vec2 c = floor(P) + 0.5;
	float f = len > 0.001 ? clamp(dot(c - A.xy, dir) / len, 0.0, 1.0) : 0.0;
	bool near_path = length(c - (A.xy + ab * f)) <= reach;
	bool near_head = length(c - target) <= reach;
	if (!near_path && !(dash && near_head)) {
		return;
	}
	float from = ceil(A.w * BIRTHS);
	float to = B.w * BIRTHS;
	float per = dash ? 3.0 : 1.0;
	float window = trail_info.x;
	for (int m = 0; m < 6; m++) {
		float id = from + float(m);
		if (id >= to) {
			break;
		}
		float t = id / BIRTHS;
		float ago = trail_now - t;
		if (ago < 0.0 || ago > window) {
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
			if (circles(look)) {
				if (!dash || (!near_head && !(look == L_PULL && near_path))) {
					continue;
				}
			} else if (!near_path) {
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

// The particles that circle the shot (void's pull, shields, glitter), born at the moments
// seg_a.x to seg_a.y: wherever on its path they were born, they are round the shot now.
void head_births(vec2 P, float z, float reach, vec2 target, inout vec4 colour, inout float best, inout float lit) {
	if (seg_a.z < 0.5) {
		return;
	}
	bool near_head = length(floor(P) + 0.5 - target) <= reach;
	float from = ceil(seg_a.x * BIRTHS);
	float to = seg_a.y * BIRTHS;
	float window = trail_info.x;
	for (int m = 0; m < BIRTHS_MAX; m++) {
		float id = from + float(m);
		if (id >= to) {
			break;
		}
		float ago = trail_now - id / BIRTHS;
		if (ago < 0.0 || ago > window) {
			continue;
		}
		float look = trail_kind(id, 0.0, false);
		if (!circles(look) || (!near_head && look != L_PULL)) {
			continue;
		}
		trail_particle(look, target, vec2(1.0, 0.0), ago, id, 0.0, P, target, z, colour, best, lit);
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

void fragment() {
	vec2 P = world;
	float z = zoom;
	vec2 target = trail_v.xy;
	float flags = trail_v.w;
	bool live = flag_set(flags, TF_HEAD);
	bool dash = flag_set(flags, TF_DASH);
	float reach = trail_info.z;
	float piece = mod(trail_info.w, 64.0);
	bool light = trail_info.w < 63.5;
	bool lightning = has_layer(L_SPARKS);
	vec4 colour = vec4(0.0);
	float best = 1e9;
	float lit = 0.0;
	float dark = 0.0;
	if (piece < 0.5) {
		// The head.
		head_births(P, z, reach, target, colour, best, lit);
		if (live && !dash) {
			// The core: a white-hot pixel with four round it, a pixel more each side a zoom; pierce
			// lengthens it along the flight; homing weaves it a pixel either side; void's is a dark
			// heart ringed in pink.
			vec2 head = target;
			vec2 fly = seg_b.xy;
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
			if (has_layer(L_PULL)) {
				// Void pulls the light down round its heart.
				dark = 0.45 * falloff(length(floor(P) - floor(trail_v.xy)), 6.0);
			}
		}
	} else {
		// A piece of the path.
		vec4 A = seg_a;
		vec4 B = seg_b;
		if (!dash) {
			if (light) {
				lit += tail_light(A, B, P, z);
			} else {
				tail_pixels(A, B, P, z, colour, best);
				if (lightning) {
					bool newer;
					if (lightning_tail(A, B, P, newer)) {
						put(newer ? ARC_LIGHT : ARC_BASE, 0.0, colour, best);
					}
				}
			}
		}
		piece_births(A, B, P, z, reach, dash, target, colour, best, lit);
	}
	if (!light) {
		// The pixels pass: what is not a pixel of the shot adds nothing.
		COLOR = colour.a > 0.0 ? colour : vec4(0.0);
	} else {
		if (lightning) {
			// Lightning flickers.
			lit *= 0.55 + 0.9 * hash(floor(sim_time * 20.0), 0.0, 21.0);
		}
		if (has_layer(L_PULL)) {
			lit *= 0.6;
		}
		vec3 hue = dash ? P_BASE[int(player)] : glow;
		COLOR = vec4(hue * lit * glow_strength, dark);
	}
}
