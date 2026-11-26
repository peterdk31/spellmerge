// SPDX-License-Identifier: GPL-3.0-or-later
shader_type canvas_item;

// A flat cover kind's look (gameplay/feel/cover_flat.gd; the floor's look, docs/milestones/floor-look.md):
// one sprite a room, its texture (and `cells`) the room's cover grid (a texel a cell,
// `CoverLayout.CELL` px of the world): red the state the cell shows (its index in its kind's states),
// green when it began to show it (Feel's clock, `view_time`'s), blue the state it showed before, alpha
// which of its 8 neighbours are drawn (bits NB_*, kept by cover_flat.gd), so a pixel reads one texel but
// at an inner bend. The
// sprite is scaled by the cell's side, so UV * the grid's size * CELL * art_detail is the room's art
// pixel. The cells stay the game's grid; only the look is shaped.
//
// **Shapes.** A drawn cell (its `fills` alpha above 0) fills its cell and joins its drawn neighbours.
// A side toward an undrawn cell (or the grid's edge) is its shape's edge, wobbling in or out by whole
// pixels along its length (a hash of where along the world's line it lies, so two cells' edges meet);
// where two such sides meet the corner is rounded (a stepped quarter circle, CORNER world px), and where
// three drawn cells meet round an undrawn one, the undrawn one draws the inner bend (a fillet) in its
// neighbour's look, so a puddle is one rounded shape across its cells. The shape's outer pixel is its
// material's shadow (`edges`). Everything is whole pixels: no blur, no fade (docs/STYLE.md, "Smooth").
//
// **Motion** (`motions` .x; CoverState.FlatMotion), played from when the cell began to show its state
// over .y frames at .z a second (.w above 0.5: looping), the puddle as one shape (the owner, 2026-11-26):
// a front moves through the puddle's distance from its edge (`depths`, `front`) by steps of its frames:
// STILL; GROW, spreading from the puddle's middle out; SHRINK, shrinking from its outer edge in, gone
// at its last frame; CRACKLE, sparks and arcs of `sparks` a frame each; GROW_IN, creeping from its
// outer edge in.
// While a state grows or shrinks, `unders` (alpha above 0) is drawn joined where it is not: ice over
// the water it freezes.
//
// **Surface** (`surfaces` .x; CoverState.FlatSurface): PLAIN, its base and glints; WATER, a deep band
// of its shadow under its upper left bank, a rim of its light inside its lower right one and ripples
// that shimmer; ICE, a raised sheet lit along its upper left edge, cracks of its shadow, a shine of its
// light that widens where the spell light is on it (`view_light`, the light grid) and twinkles; STEAM,
// wisps of `sparks` rising, thinning over the state's frames. `shimmer` off (the effects' Low row)
// holds the ripples, the twinkles and the wisps still; a crackle plays at every row (it is the game's
// danger).
//
// **Trace** (`traces`, `surfaces` .y its seconds): a cell undrawn now whose last state leaves a mark
// (dried water's damp, steam's scorch) shows a sparse speckle of it, thinning away in 4 steps.

#include "res://gameplay/feel/light_views.gdshaderinc"

const float CELL = 16.0;
const int STATES = 16;
// A cell's drawn neighbours, by bit (CoverFlat.NEIGHBOURS).
const int NB_L = 1;
const int NB_R = 2;
const int NB_U = 4;
const int NB_D = 8;
const int NB_UL = 16;
const int NB_UR = 32;
const int NB_DL = 64;
const int NB_DR = 128;
// The rounded corner's radius and how far an edge wobbles, in world px (times art_detail).
const int CORNER = 6;
const int WOBBLE_RUN = 4;
// The shimmer's clock (frames a second) and the light's brightest channel from which ice's shine
// widens and turns white-hot (the apply rect's lit and bright steps, SpellLight.lit_steps .y, .w).
const float SHIMMER_FPS = 6.0;
const float WISP_FPS = 12.0;
const float ICE_LIT = 0.16;
const float ICE_BRIGHT = 0.45;

uniform float view_time = 0.0;
// Art pixels a world pixel (ArtDetail, core/display/art_detail.gd: CoverFlat.DETAIL, 2): a cell is
// 16 world px, 16 * art_detail art px; every shape, detail and step is whole art pixels.
uniform int art_detail = 1;
// The room's top-left corner in the world (the sprite's place), for the light grid's world point.
uniform vec2 room_origin = vec2(0.0);
// The effects' row's animated detail (EffectsQuality.floor_shimmer).
uniform bool shimmer = true;
// Ice's white-hot shine (Bone's light).
uniform vec4 white_hot = vec4(0.957, 0.945, 0.918, 1.0);
// The room's cover grid (the sprite's own texture, handed again whenever it is).
uniform sampler2D cells : filter_nearest;
// Each cell's distance from its puddle's edge (red, cells at its middle; -0.5 not drawn) and its
// puddle's most (green), worked out by cover_flat.gd as what is drawn changes.
uniform sampler2D depths : filter_nearest;
uniform vec4 fills[STATES];
uniform vec4 edges[STATES];
uniform vec4 glints[STATES];
uniform vec4 unders[STATES];
uniform vec4 under_edges[STATES];
uniform vec4 under_lights[STATES];
uniform vec4 sparks[STATES];
uniform vec4 motions[STATES];
uniform vec4 surfaces[STATES];
uniform vec4 traces[STATES];

void vertex() {
	LIGHT_VIEW_FIND;
}

vec4 cell_at(ivec2 cell, ivec2 size) {
	if (cell.x < 0 || cell.y < 0 || cell.x >= size.x || cell.y >= size.y) {
		return vec4(-1.0, 0.0, -1.0, 0.0);
	}
	return texelFetch(cells, cell, 0);
}

bool drawn(int state) {
	return state >= 0 && state < STATES && fills[state].a > 0.0;
}

int state_of(vec4 texel) {
	return texel.r < -0.5 ? -1 : int(texel.r + 0.5);
}

uint pixel_hash(ivec2 p, int salt) {
	uint h = uint(p.x) * 374761393u + uint(p.y) * 668265263u + uint(salt) * 2246822519u;
	h = (h ^ (h >> 13u)) * 1274126177u;
	return h ^ (h >> 16u);
}

// The frame of state `s`'s motion, `age` seconds after the cell began to show it.
int frame_of(int s, float age) {
	vec4 motion = motions[s];
	int frames = max(int(motion.y + 0.5), 1);
	int frame = int(floor(max(age, 0.0) * max(motion.z, 1.0)));
	return motion.w > 0.5 ? frame % frames : min(frame, frames - 1);
}

// How far in a closed side's edge lies at `along` art px along the world's line `line`: 0 to 2 world
// px, a height a run of WOBBLE_RUN world px, stepped by whole pixels from one run's height to the next.
int wobble(int along, int line, int salt, int d) {
	int run = WOBBLE_RUN * d;
	int k = along / run;
	int t = along - k * run;
	int a = int(pixel_hash(ivec2(k, line), salt) % uint(2 * d + 1));
	int b = int(pixel_hash(ivec2(k + 1, line), salt) % uint(2 * d + 1));
	return (a * (run - t) + b * t) / run;
}

// Whether state `s` grows or shrinks (GROW, SHRINK, GROW_IN): its front moves through the puddle.
bool moving(int s) {
	int kind = int(motions[s].x + 0.5);
	return kind == 1 || kind == 2 || kind == 4;
}

// Whether state `s` has finished growing in (GROW or GROW_IN at its last frame): its shape is whole.
bool settled(int s, float age) {
	int kind = int(motions[s].x + 0.5);
	if (kind != 1 && kind != 4) {
		return !moving(s);
	}
	return frame_of(s, age) >= max(int(motions[s].y + 0.5), 1) - 1;
}

// The distance from its motion's edge (cells) at the room's art pixel `px`, for a cell whose texel is
// `here`: the cells' distances (`depths` red, at each cell's middle) weighed between the four nearest
// middles, a cell not of the same motion (another state or another start) or outside the grid -0.5;
// never below 0 inside the cell.
float depth_at(ivec2 px, int side, ivec2 size, vec4 here) {
	vec2 p = (vec2(px) + 0.5) / float(side) - 0.5;
	ivec2 c = ivec2(floor(p));
	vec2 t = p - floor(p);
	float v[4];
	for (int k = 0; k < 4; k++) {
		ivec2 at = c + ivec2(k % 2, k / 2);
		bool inside = at.x >= 0 && at.y >= 0 && at.x < size.x && at.y < size.y;
		ivec2 safe = clamp(at, ivec2(0), size - ivec2(1));
		vec4 other = texelFetch(cells, safe, 0);
		bool same = inside && abs(other.r - here.r) < 0.5 && other.g == here.g;
		v[k] = same ? texelFetch(depths, safe, 0).r : -0.5;
	}
	return max(mix(mix(v[0], v[1], t.x), mix(v[2], v[3], t.x), t.y), 0.0);
}

// How far (art px; below 0: not yet or no longer there) pixel `px` lies inside the front of state
// `s`'s motion, `age` seconds after its cell (texel `here`) began to show it, its motion `most` cells
// deep at its deepest: GROW spreads from the middle out, SHRINK shrinks from the outer edge in,
// GROW_IN creeps from the outer edge in, all by steps of the state's frames and as one shape. The last
// frame is exact: GROW and GROW_IN whole (the next state's shape), SHRINK gone.
int front(int s, float age, ivec2 px, int side, ivec2 size, vec4 here, float most, int d) {
	int kind = int(motions[s].x + 0.5);
	int frames = max(int(motions[s].y + 0.5), 1);
	int frame = frame_of(s, age);
	if (frame >= frames - 1) {
		return kind == 2 ? -1 : 9999;
	}
	// Past the deepest pixel, its wobble taken in.
	float deepest = most * float(side) + float(2 * d) + 1.0;
	float depth = depth_at(px, side, size, here) * float(side) + float(wobble(px.x + px.y, 7, 3, d));
	if (kind == 1) {
		return int(floor(depth - deepest * float(frames - 1 - frame) / float(frames)));
	}
	if (kind == 2) {
		return int(floor(depth - deepest * float(frame + 1) / float(frames)));
	}
	return int(floor(deepest * float(frame + 1) / float(frames) - depth));
}

// The distance (whole art px, 0 the outer pixel, below 0 outside) from pixel `f` of a cell of side
// `side` to its shape's edge, its closed sides given by `cl` (left, right, up, down; an open side is
// joined), `px` the room's pixel (for the wobble), `cell` the cell; `inset` more in from every side.
// `nb` the cell's drawn neighbours (NB_*; 0 while it is a shape of its own): a closed side's end that
// meets an inner bend (the side's neighbour beyond its end and the cell past it drawn) follows the
// bend's arc, the same arc the undrawn cell draws its fillet to, so the shape has no seam there.
// `low` is set to whether the nearest edge faces down or right (the shape's far, lower right side).
int edge_dist(ivec2 f, int side, bvec4 cl, ivec2 px, ivec2 cell, int inset, int nb, int d, out bool low) {
	int last = side - 1;
	int best = 9999;
	low = false;
	int r = CORNER * d;
	vec2 c = vec2(f) + 0.5;
	float fr = float(r);
	float fs = float(side);
	// Each closed side: its straight edge, or the bend's arc at an end that meets one.
	if (cl.x) {
		vec2 centre = f.y < r && (nb & (NB_U | NB_UL)) == (NB_U | NB_UL) ? vec2(-fr, fr) : (f.y > last - r && (nb & (NB_D | NB_DL)) == (NB_D | NB_DL) ? vec2(-fr, fs - fr) : vec2(-1.0e6));
		int v = centre.x > -1.0e5 ? int(floor(length(c - centre) - float(r))) : f.x - inset - wobble(px.y, cell.x * 2, 1, d);
		if (v < best) { best = v; low = false; }
	}
	if (cl.y) {
		vec2 centre = f.y < r && (nb & (NB_U | NB_UR)) == (NB_U | NB_UR) ? vec2(fs + fr, fr) : (f.y > last - r && (nb & (NB_D | NB_DR)) == (NB_D | NB_DR) ? vec2(fs + fr, fs - fr) : vec2(-1.0e6));
		int v = centre.x > -1.0e5 ? int(floor(length(c - centre) - float(r))) : last - f.x - inset - wobble(px.y, cell.x * 2 + 2, 1, d);
		if (v < best) { best = v; low = true; }
	}
	if (cl.z) {
		vec2 centre = f.x < r && (nb & (NB_L | NB_UL)) == (NB_L | NB_UL) ? vec2(fr, -fr) : (f.x > last - r && (nb & (NB_R | NB_UR)) == (NB_R | NB_UR) ? vec2(fs - fr, -fr) : vec2(-1.0e6));
		int v = centre.x > -1.0e5 ? int(floor(length(c - centre) - float(r))) : f.y - inset - wobble(px.x, cell.y * 2, 2, d);
		if (v < best) { best = v; low = false; }
	}
	if (cl.w) {
		vec2 centre = f.x < r && (nb & (NB_L | NB_DL)) == (NB_L | NB_DL) ? vec2(fr, fs + fr) : (f.x > last - r && (nb & (NB_R | NB_DR)) == (NB_R | NB_DR) ? vec2(fs - fr, fs + fr) : vec2(-1.0e6));
		int v = centre.x > -1.0e5 ? int(floor(length(c - centre) - float(r))) : last - f.y - inset - wobble(px.x, cell.y * 2 + 2, 2, d);
		if (v < best) { best = v; low = true; }
	}
	// A rounded corner where two closed sides meet: the distance in from a quarter circle, its radius
	// no more than half the (inset) shape, so one corner's square never reaches another's.
	int lo = inset;
	int hi = last - inset;
	int rr = min(r, (hi - lo + 1) / 2);
	bool left = f.x < lo + rr;
	bool right = f.x >= hi + 1 - rr;
	bool top = f.y < lo + rr;
	bool bottom = f.y >= hi + 1 - rr;
	ivec2 corner = ivec2(-1);
	if (cl.x && cl.z && left && top) { corner = ivec2(lo + rr, lo + rr); }
	else if (cl.y && cl.z && right && top) { corner = ivec2(hi + 1 - rr, lo + rr); }
	else if (cl.x && cl.w && left && bottom) { corner = ivec2(lo + rr, hi + 1 - rr); }
	else if (cl.y && cl.w && right && bottom) { corner = ivec2(hi + 1 - rr, hi + 1 - rr); }
	if (corner.x >= 0 && rr > 0) {
		vec2 from = c - vec2(corner);
		int v = int(floor(float(rr) - length(from)));
		if (v < best) {
			best = v;
			low = from.x + from.y > 0.0;
		}
	}
	return best;
}

// Ice's cracks: thin lines of its shadow, one or none a block of 10 world px, a hash of the block.
bool crack(ivec2 px, int d) {
	int b = 10 * d;
	ivec2 block = px / b;
	ivec2 l = px - block * b;
	uint h = pixel_hash(block, 7);
	int kind = int(h % 5u);
	int a = int((h >> 4u) % uint(b));
	int from = int((h >> 9u) % uint(b / 2));
	int len = b / 2 + int((h >> 13u) % uint(b / 2));
	if (kind == 1) {
		return l.x - l.y == a - b / 2 && l.y >= from && l.y < from + len;
	}
	if (kind == 2) {
		return l.x + l.y == a + b / 4 && l.y >= from && l.y < from + len;
	}
	if (kind == 3) {
		// A short run that steps down a pixel halfway along.
		return l.y == a / 2 + (l.x > from + len / 2 ? 1 : 0) && l.x >= from && l.x < from + len;
	}
	return false;
}

// Ice's shine: diagonal bands of its light (`wide` adds a pixel each side); 2: the band's middle.
int shine(ivec2 px, int d, bool wide) {
	int period = 23 * d;
	int k = (px.x + px.y) / period;
	if (pixel_hash(ivec2(k, 0), 9) % 3u == 0u) {
		return 0;
	}
	int at = (px.x + px.y) - k * period;
	int half_width = d + (wide ? d : 0);
	if (at < half_width * 2) {
		return at >= half_width - d / 2 && at < half_width + d / 2 + 1 ? 2 : 1;
	}
	return 0;
}

// A twinkle: a + of light, an art pixel each arm, round a few art pixels picked by a hash, played over
// 3 frames of an 8-frame cycle.
bool twinkle(ivec2 px, int t, int d) {
	bool lit = false;
	for (int k = 0; k < 5; k++) {
		ivec2 o = k == 0 ? ivec2(0) : (k == 1 ? ivec2(1, 0) : (k == 2 ? ivec2(-1, 0) : (k == 3 ? ivec2(0, 1) : ivec2(0, -1))));
		uint h = pixel_hash(px + o, 11);
		int phase = (t + int((h >> 8u) % 8u)) % 8;
		lit = lit || (h % uint(53 * d * d) == 0u && (phase == 2 || (k == 0 && (phase == 1 || phase == 3))));
	}
	return lit;
}

// Water's ripples: dashes of its light an art pixel tall, a block of 7 x 4 world px each, each growing
// and shrinking by an art pixel each side a frame of a 6-frame cycle from its own phase, with a second,
// shorter dash under its middle at its widest (a ripple's two crests).
bool ripple(ivec2 px, int t, int d) {
	ivec2 size = ivec2(7, 4) * d;
	ivec2 block = px / size;
	ivec2 l = px - block * size;
	uint h = pixel_hash(block, 5);
	if (h % 3u != 0u) {
		return false;
	}
	int y0 = int((h >> 4u) % uint(size.y - 1));
	int phase = (t + int((h >> 8u) % 6u)) % 6;
	int reach = phase < 3 ? phase + 1 : 6 - phase;
	int mid = size.x / 2;
	if (l.y == y0) {
		return abs(l.x - mid) < reach + 1;
	}
	return l.y == y0 + 1 && reach >= 3 && abs(l.x - mid) < 2;
}

// Live water's arcs: a zig-zag of the spark's light an art pixel thick (it steps a pixel up or down
// each pixel along), across a block of 12 world px, a new one each frame.
bool arc(ivec2 px, int frame, int d) {
	int size = 12 * d;
	ivec2 block = px / size;
	ivec2 l = px - block * size;
	uint h = pixel_hash(block + ivec2(frame * 17, frame * 31), 13);
	if (h % 2u != 0u || l.x < d || l.x >= size - d) {
		return false;
	}
	int y0 = 3 * d + int((h >> 4u) % uint(6 * d));
	int run = 3 + int((h >> 8u) % 3u);
	int at = (l.x + int((h >> 12u) % 8u)) % (run * 2);
	return l.y == y0 + (at < run ? at : run * 2 - at) - run / 2;
}

// Steam's wisps: rising strokes an art pixel wide, curling a pixel aside every few, a block of
// 6 x 10 world px each, `share` of 8 of the blocks drawn, risen `rise` art px.
bool wisp(ivec2 px, int rise, int share, int d) {
	int w = 6 * d;
	int tall = 10 * d;
	int bx = px.x / w;
	int ly = (px.y + rise) % tall;
	uint h = pixel_hash(ivec2(bx, (px.y + rise) / tall), 17);
	if (int(h % 8u) >= share) {
		return false;
	}
	int y0 = int((h >> 4u) % uint(tall / 2));
	int len = 3 * d + int((h >> 7u) % uint(3 * d));
	int x = d + int((h >> 10u) % uint(w - 3 * d)) + ((ly / 3) % 3 == 1 ? 1 : 0);
	return px.x - bx * w == x && ly >= y0 && ly < y0 + len;
}

// Water's detail on interior pixel `px` (`dist` in from its edge, `low` its facing) in `base`, `shadow`
// and `light`: a puddle lies below the floor, so its upper left bank shades it and its lower right one
// catches the light; ripples shimmer on it.
vec4 water(vec4 base, vec4 shadow, vec4 light, ivec2 px, int dist, bool low, int t, int d) {
	if (dist <= d) {
		return low ? light : shadow;
	}
	return ripple(px, t, d) ? light : base;
}

// The colour of interior pixel `px` (`dist` in from its edge, `low` its facing) of state `s`, `frame`
// of its motion, `t` the shimmer's frame.
vec4 surface(int s, ivec2 px, int dist, bool low, int frame, int t, int d, vec2 world) {
	int kind = int(surfaces[s].x + 0.5);
	int motion = int(motions[s].x + 0.5);
	vec4 colour = fills[s];
	if (pixel_hash(px, 0) % uint(31 * d * d) == 0u && kind != 2) {
		colour = glints[s];
	}
	if (kind == 1 || kind == 3) {
		colour = water(fills[s], edges[s], glints[s], px, dist, low, t, d);
	} else if (kind == 2) {
		// Ice: a raised sheet, lit along its upper left edge.
		float lit = 0.0;
		vec3 light = view_light(world);
		lit = max(light.r, max(light.g, light.b));
		if (!low && dist <= d) {
			colour = glints[s];
		} else if (crack(px, d)) {
			colour = edges[s];
		} else {
			int band = shine(px, d, lit >= ICE_LIT);
			if (band == 2 && lit >= ICE_BRIGHT) {
				colour = white_hot;
			} else if (band > 0) {
				colour = glints[s];
			} else if (twinkle(px, t, d) || (lit >= ICE_LIT && pixel_hash(px, 3) % uint(23 * d * d) == 0u)) {
				colour = lit >= ICE_BRIGHT ? white_hot : glints[s];
			}
		}
	}
	if (motion == 3) {
		if (pixel_hash(px, frame + 1) % uint(41 * d * d) == 0u || arc(px, frame, d)) {
			colour = sparks[s];
		}
	}
	return colour;
}

void fragment() {
	int d = max(art_detail, 1);
	ivec2 size = max(textureSize(cells, 0), ivec2(1));
	int side = 16 * d;
	int last = side - 1;
	ivec2 px = ivec2(floor(UV * vec2(size) * CELL * float(d)));
	ivec2 cell = clamp(px / ivec2(side), ivec2(0), size - ivec2(1));
	ivec2 f = px - cell * ivec2(side);
	vec2 world = room_origin + (vec2(px) + 0.5) / float(d);
	vec4 here = texelFetch(cells, cell, 0);
	int s = int(here.r + 0.5);
	int t = shimmer ? int(floor(view_time * SHIMMER_FPS)) : 0;
	int r = CORNER * d;
	int nb = int(here.a + 0.5);
	if (!drawn(s)) {
		// The inner bend where three drawn cells (still, joined) meet round this one, in the look of
		// the one above or below it.
		int sx = f.x < r ? -1 : (f.x > last - r ? 1 : 0);
		int sy = f.y < r ? -1 : (f.y > last - r ? 1 : 0);
		int want = (sx < 0 ? NB_L : NB_R) | (sy < 0 ? NB_U : NB_D) | (sx < 0 ? (sy < 0 ? NB_UL : NB_DL) : (sy < 0 ? NB_UR : NB_DR));
		bool bend = false;
		if (sx != 0 && sy != 0 && (nb & want) == want) {
			vec4 a = cell_at(cell + ivec2(sx, 0), size);
			vec4 b = cell_at(cell + ivec2(0, sy), size);
			vec4 c = cell_at(cell + ivec2(sx, sy), size);
			int sa = state_of(a);
			int sb = state_of(b);
			int sc = state_of(c);
			if (drawn(sa) && drawn(sb) && drawn(sc) && settled(sa, view_time - a.g) && settled(sb, view_time - b.g) && settled(sc, view_time - c.g)) {
				ivec2 into = ivec2(sx < 0 ? r : side - r, sy < 0 ? r : side - r);
				float from_far = length(vec2(f) + 0.5 - vec2(into));
				if (from_far > float(r)) {
					bend = true;
					s = sb;
					here = b;
					COLOR = from_far < float(r) + 1.0 ? edges[s] : surface(s, px, int(from_far) - r, sy < 0, frame_of(s, view_time - b.g), t, d, world);
				}
			}
		}
		if (!bend) {
			// The mark the last state left, thinning away.
			int was = int(here.b + 0.5);
			if (here.b < -0.5 || was < 0 || was >= STATES || traces[was].a <= 0.0) {
				discard;
			}
			float age = view_time - here.g;
			float seconds = max(surfaces[was].y, 0.25);
			int step_of = int(floor(age / seconds * 4.0));
			if (age < 0.0 || step_of >= 4 || int(pixel_hash(px, 21) % 24u) >= 4 - step_of) {
				discard;
			}
			COLOR = traces[was];
		}
	} else {
		bvec4 joined = bvec4((nb & NB_L) == 0, (nb & NB_R) == 0, (nb & NB_U) == 0, (nb & NB_D) == 0);
		float age = view_time - here.g;
		int frame = frame_of(s, age);
		bool low = false;
		int dist = edge_dist(f, side, joined, px, cell, 0, nb, d, low);
		// While it grows or shrinks, its front moves through the puddle as one shape (the owner,
		// 2026-11-26: a puddle shrinks as one puddle from its outer edge, never cell by cell).
		if (moving(s)) {
			int ahead = front(s, age, px, side, size, here, texelFetch(depths, cell, 0).g, d);
			if (ahead < dist) {
				dist = ahead;
				low = false;
			}
		}
		int kind = int(surfaces[s].x + 0.5);
		if (dist < 0) {
			bool under_low = false;
			int under = unders[s].a > 0.0 ? edge_dist(f, side, joined, px, cell, 0, nb, d, under_low) : -1;
			if (under >= 0) {
				// The water under ice keeps its look while the ice grows over it or shrinks off it.
				COLOR = under == 0 ? under_edges[s] : water(unders[s], under_edges[s], under_lights[s], px, under, under_low, t, d);
			} else if (kind == 3) {
				// Steam rises off where the water was.
				int full = edge_dist(f, side, joined, px, cell, 0, nb, d, under_low);
				int share = 3 - abs(frame - 1);
				if (full < 0 || share <= 0 || !wisp(px, shimmer ? int(floor(view_time * WISP_FPS)) : 0, share, d)) {
					discard;
				}
				COLOR = sparks[s];
			} else {
				discard;
			}
		} else if (dist == 0) {
			COLOR = edges[s];
		} else {
			COLOR = surface(s, px, dist, low, frame, t, d, world);
			if (kind == 3 && wisp(px, shimmer ? int(floor(view_time * WISP_FPS)) : 0, max(3 - abs(frame - 1), 0), d)) {
				COLOR = sparks[s];
			}
		}
	}
}
