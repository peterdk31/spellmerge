// SPDX-License-Identifier: GPL-3.0-or-later
shader_type canvas_item;

// A flat cover kind's look (gameplay/feel/cover_flat.gd; the floor's first slice,
// docs/milestones/floor.md): one sprite a room, its texture (and `cells`) the room's cover grid (a texel a cell,
// `CoverLayout.CELL` px of the world): red the state the cell shows (its index in its kind's
// states), green when it began to show it (Feel's clock, `view_time`'s). The sprite is scaled by
// the cell's side, so UV * the grid's size * CELL is the room pixel.
//
// A cell whose state is drawn (its `fills` alpha above 0) fills its 16 px and joins its drawn
// neighbours: on a side toward an undrawn cell (or the grid's edge) it has a 1 px edge of its
// material's shadow, and where two such sides meet a stepped corner, so a puddle is one shape. Its
// light (`glints`) lies on a few pixels picked by a hash of the pixel. Everything is whole pixels:
// no blur, no fade (docs/STYLE.md, "Smooth").
//
// A state's motion (`motions` .x; CoverState.FlatMotion), played from when the cell began to show
// it over .y frames at .z a second (.w above 0.5: looping): STILL; GROW, its shape inset from its
// sides by INSET_MOST * (frames - 1 - frame) / frames px (all four while it plays: a cell of its
// own), so it grows in by steps; SHRINK, inset
// by INSET_MOST * (frame + 1) / frames, so it ends gone; CRACKLE, sparks of `sparks` on pixels a hash
// of the pixel and the frame picks. While a state grows or shrinks, `unders` (alpha above 0) is
// drawn whole (joined to its neighbours) where it is not: ice over the water it freezes.

const float CELL = 16.0;
const int INSET_MOST = 8;
const int STATES = 16;

uniform float view_time = 0.0;
// Art pixels a world pixel (ArtDetail, core/display/art_detail.gd: 2 once the floor states are drawn
// at 2x detail): a cell is 16 world px, 16 * art_detail art px; its edges, corners, insets and glints
// are whole art pixels.
uniform int art_detail = 1;
// The room's cover grid (the sprite's own texture, handed again whenever it is).
uniform sampler2D cells : filter_nearest;
uniform vec4 fills[STATES];
uniform vec4 edges[STATES];
uniform vec4 glints[STATES];
uniform vec4 unders[STATES];
uniform vec4 under_edges[STATES];
uniform vec4 sparks[STATES];
uniform vec4 motions[STATES];

int state_of(ivec2 cell, ivec2 size) {
	if (cell.x < 0 || cell.y < 0 || cell.x >= size.x || cell.y >= size.y) {
		return -1;
	}
	return int(texelFetch(cells, cell, 0).r + 0.5);
}

bool drawn(int state) {
	return state >= 0 && state < STATES && fills[state].a > 0.0;
}

// 0 outside the shape inset by `inset` from its outer sides, 1 inside, 2 on its edge.
int shape(int dl, int dr, int du, int dd, int inset) {
	int l = dl - inset;
	int r = dr - inset;
	int u = du - inset;
	int d = dd - inset;
	if (l < 0 || r < 0 || u < 0 || d < 0) {
		return 0;
	}
	// A stepped corner where two outer sides meet: the corner pixel and its two neighbours cut.
	if (l + u < 2 || r + u < 2 || l + d < 2 || r + d < 2) {
		return 0;
	}
	if (min(min(l, r), min(u, d)) == 0 || l + u == 2 || r + u == 2 || l + d == 2 || r + d == 2) {
		return 2;
	}
	return 1;
}

uint pixel_hash(ivec2 p, int salt) {
	uint h = uint(p.x) * 374761393u + uint(p.y) * 668265263u + uint(salt) * 2246822519u;
	h = (h ^ (h >> 13u)) * 1274126177u;
	return h ^ (h >> 16u);
}

void fragment() {
	ivec2 size = max(textureSize(cells, 0), ivec2(1));
	int side = 16 * max(art_detail, 1);
	int last = side - 1;
	ivec2 px = ivec2(floor(UV * vec2(size) * CELL * float(max(art_detail, 1))));
	ivec2 cell = clamp(px / ivec2(side), ivec2(0), size - ivec2(1));
	ivec2 f = px - cell * ivec2(side);
	vec4 here = texelFetch(cells, cell, 0);
	int s = int(here.r + 0.5);
	if (!drawn(s)) {
		discard;
	}
	bool open_l = drawn(state_of(cell + ivec2(-1, 0), size));
	bool open_r = drawn(state_of(cell + ivec2(1, 0), size));
	bool open_u = drawn(state_of(cell + ivec2(0, -1), size));
	bool open_d = drawn(state_of(cell + ivec2(0, 1), size));
	int dl = open_l ? 99 : f.x;
	int dr = open_r ? 99 : last - f.x;
	int du = open_u ? 99 : f.y;
	int dd = open_d ? 99 : last - f.y;
	vec4 motion = motions[s];
	int kind = int(motion.x + 0.5);
	int frames = max(int(motion.y + 0.5), 1);
	int frame = int(floor(max(view_time - here.g, 0.0) * max(motion.z, 1.0)));
	frame = motion.w > 0.5 ? frame % frames : min(frame, frames - 1);
	int inset = 0;
	if (kind == 1) {
		inset = (INSET_MOST * max(art_detail, 1) * (frames - 1 - frame)) / frames;
	} else if (kind == 2) {
		inset = (INSET_MOST * max(art_detail, 1) * (frame + 1)) / frames;
	}
	// While a cell grows or shrinks it is a shape of its own, inset from all four sides (a whole
	// puddle drying, freezing or steaming at once shrinks or grows cell by cell, never in one jump);
	// still, it joins its drawn neighbours.
	int at = inset > 0 ? shape(f.x, last - f.x, f.y, last - f.y, inset) : shape(dl, dr, du, dd, 0);
	if (at == 0) {
		if (unders[s].a > 0.0) {
			int under = shape(dl, dr, du, dd, 0);
			if (under == 0) {
				discard;
			}
			COLOR = under == 2 ? under_edges[s] : unders[s];
		} else {
			discard;
		}
	} else if (at == 2) {
		COLOR = edges[s];
	} else {
		COLOR = fills[s];
		if (pixel_hash(px, 0) % 31u == 0u) {
			COLOR = glints[s];
		}
		if (kind == 3 && pixel_hash(px, frame + 1) % 11u == 0u) {
			COLOR = sparks[s];
		}
	}
}
