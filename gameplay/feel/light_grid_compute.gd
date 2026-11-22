extends RefCounted
## The light grid's compute shader (gameplay/feel/light_grid_gpu.gd), its GLSL source as text:
## compiled by `GpuCompute.compile` on the render thread, on the desktop's Mobile renderer only (the
## web never makes a LightGridGpu, so this is never compiled there). GLSL has no file type of its own
## in the project (AGENTS.md, hard rule 2: no `.glsl`), and Godot's `RDShaderSource` is not a resource
## a `.tres` can hold, so it is a constant here (an open question with the owner: a `.glsl` file,
## imported by Godot as an `RDShaderFile`, would take its place).
##
## The shader is LightGrid's `_row`, `_lamp`, `add_beam` and `bake`, in two modes (see its head).

const SOURCE: String = """#version 450
// SPDX-License-Identifier: GPL-3.0-or-later
// The light grid worked out on the GPU (gameplay/feel/light_grid_gpu.gd; the owner's decision of
// 2026-11-22): the GDScript's and LightKernel's light grid (gameplay/feel/light_grid.gd,
// native/src/light_grid.cpp) in two steps, in one compute list.
//  - mode 0, a lamp a row: a segment's rows (the CPU's `_row`: the glows, the reaches, where a light
//    is lit from and which boxes come near it) into lamps, LAMP_VEC4 vec4s each, at `first` on;
//    `kind` ROWS_BEAM rows are a beam's pieces, worked out on the CPU (`add_beam`).
//  - mode 1, a cell a thread: view `kind`'s cells, each summing every lamp in order (as the CPU adds
//    them: segments in order, then the beams), cut at 1, rounded to a byte a channel and stored in
//    the atlas the readers sample (light_grid.gdshaderinc). A tile of 8 x 8 cells keeps only the
//    lamps whose box comes over it, 64 lamps at a time.
// The maths is the CPU's in floats (the CPU's in doubles): a cell may differ by a byte (the PR's
// measure; gameplay/feel/README.md, The light grid on the GPU).

layout(local_size_x = 64, local_size_y = 1, local_size_z = 1) in;

const int ROWS_SHOT = 0;
const int ROWS_RUNE = 1;
const int ROWS_FLASH = 2;
const int ROWS_SPOT = 3;
const int ROWS_CUE = 4;
const int ROWS_BEAM = 5;
const int LAMP_VEC4 = 5;
const int TILE = 8;

const float SHOT_STRENGTH = 0.9;
const float RUNE_STRENGTH = 0.55;
const float SHOT_REACH = 26.0;
const float SHOT_REACH_ZOOM = 6.0;
const float SPECK_REACH = 14.0;
const float RUNE_REACH = 1.5;
const float FLASH_FROM = 0.02;
const float FLASH_SPAN = 0.42;
const float HF_LIVE = 1.0;
const int MATERIALS = 7;
const int ENEMY_PLAYER = 4;
const int KIND_COUNT = 22;
const int ENEMY_RAMP = 23;
const int EXACT = 24;
const int PALETTE_MOST = 4;
const float INFUSION_MARK = 128.0 / 255.0;

const float P_BASE[15] = float[](0.231, 0.451, 0.788, 0.851, 0.278, 0.478, 0.247, 0.561, 0.310, 0.541, 0.310, 0.769, 0.651, 0.541, 0.165);
const float P_LIGHT[15] = float[](0.498, 0.753, 0.941, 0.961, 0.604, 0.722, 0.561, 0.831, 0.416, 0.788, 0.604, 0.941, 0.890, 0.812, 0.420);
const float SHADES[63] = float[](
	0.561, 0.176, 0.165, 0.878, 0.349, 0.184, 1.0, 0.635, 0.235,
	0.722, 0.502, 0.122, 0.949, 0.761, 0.188, 1.0, 0.953, 0.651,
	0.122, 0.439, 0.502, 0.310, 0.839, 0.863, 0.769, 0.965, 0.949,
	0.290, 0.078, 0.314, 0.627, 0.188, 0.604, 0.878, 0.541, 0.847,
	0.247, 0.420, 0.063, 0.706, 0.910, 0.165, 0.933, 1.0, 0.651,
	0.639, 0.624, 0.722, 0.831, 0.816, 0.878, 0.957, 0.945, 0.918,
	0.059, 0.290, 0.267, 0.118, 0.612, 0.549, 0.435, 0.863, 0.753);

// The frame (LightGridGpu.FRAME_*): head (cell, boxes, lamps, unused), a view's (origin x, y,
// columns, rows) and (atlas x, y, 0, 0), the infusion table, the boxes that block light and their
// columns (LightBlockers' `boxes`, `bodies`).
layout(set = 0, binding = 0, std430) restrict readonly buffer Frame {
	vec4 head;
	vec4 views[8];
	vec4 tints[32];
	vec4 boxes[32];
	vec4 bodies[32];
} frame;

layout(set = 0, binding = 1, std430) restrict buffer Lamps {
	vec4 lamps[];
};

layout(set = 0, binding = 2, rgba8) restrict writeonly uniform image2D atlas;

// A segment's rows (16 floats each: SpellLight's row format), a MultiMesh's buffer.
layout(set = 1, binding = 0, std430) restrict readonly buffer Rows {
	float rows[];
};

layout(push_constant, std430) uniform Push {
	int mode;
	int count;
	int first;
	int kind;
	float reach;
	float pad;
	int blocked;
	int tiles_across;
} pc;

shared uint keep[64];

// --- The colours (LightGrid.look_glow) ------------------------------------------------------------

bool bit_set(int b0, int b1, int b2, int look) {
	int bit = look - 1;
	int byte_of = bit < 8 ? b0 : (bit < 16 ? b1 : b2);
	return ((byte_of >> (bit % 8)) & 1) == 1;
}

int material_of(float r, float g, float b) {
	int best = 0;
	float nearest = 9.0;
	for (int i = 0; i < MATERIALS * 3; i++) {
		float dr = r - SHADES[i * 3];
		float dg = g - SHADES[i * 3 + 1];
		float db = b - SHADES[i * 3 + 2];
		float d = sqrt(dr * dr + dg * dg + db * db);
		if (d < nearest) {
			nearest = d;
			best = i / 3;
		}
	}
	return best;
}

vec3 shade_of(int m, int shade) {
	int i = (m * 3 + shade) * 3;
	return vec3(SHADES[i], SHADES[i + 1], SHADES[i + 2]);
}

vec3 mix_of(vec3 a, vec3 b, float t) {
	return a + (b - a) * t;
}

vec3 look_glow(float cr, float cg, float cb, int who, int b0, int b1, int b2) {
	int player = bit_set(b0, b1, b2, ENEMY_RAMP) ? ENEMY_PLAYER : who;
	vec3 mid = vec3(0.0);
	vec3 hi = vec3(0.0);
	int first = -1;
	bool plain = cr > 0.99 && cg > 0.99 && cb > 0.99;
	if (bit_set(b0, b1, b2, EXACT)) {
		mid = vec3(cr, cg, cb);
		hi = vec3(cr + (1.0 - cr) * 0.35, cg + (1.0 - cg) * 0.35, cb + (1.0 - cb) * 0.35);
	} else if (plain) {
		hi = vec3(P_LIGHT[player * 3], P_LIGHT[player * 3 + 1], P_LIGHT[player * 3 + 2]);
		mid = vec3(P_BASE[player * 3], P_BASE[player * 3 + 1], P_BASE[player * 3 + 2]);
	} else {
		first = material_of(cr, cg, cb);
		mid = shade_of(first, 1);
		hi = shade_of(first, 2);
	}
	vec3 glow = mix_of(mid, hi, 0.35);
	if (first >= 0) {
		int m1 = -1;
		int m2 = -1;
		int count = 1;
		for (int layer = 1; layer <= KIND_COUNT; layer++) {
			if (count < PALETTE_MOST && bit_set(b0, b1, b2, layer)) {
				vec4 t = frame.tints[layer];
				int m = first;
				if (abs(t.a - INFUSION_MARK) < 0.1) {
					m = material_of(t.r, t.g, t.b);
				}
				if (m != first && m != m1 && m != m2) {
					if (count == 1) {
						m1 = m;
					} else if (count == 2) {
						m2 = m;
					}
					count += 1;
				}
			}
		}
		if (count > 1) {
			int glows = count > 2 ? m2 : m1;
			glow = mix_of(shade_of(glows, 1), shade_of(glows, 2), 0.35);
		}
	}
	return glow;
}

vec3 glow_of(int at) {
	float red = floor(rows[at + 8] * 255.0 + 0.5);
	int who = int(mod(red, 4.0));
	int b0 = int(floor(rows[at + 9] * 255.0 + 0.5));
	int b1 = int(floor(rows[at + 10] * 255.0 + 0.5));
	int b2 = int(floor(rows[at + 11] * 255.0 + 0.5));
	return look_glow(rows[at + 12], rows[at + 13], rows[at + 14], who, b0, b1, b2);
}

// --- The boxes (LightBlockers) --------------------------------------------------------------------

bool box_holds(vec4 box, vec2 p) {
	return p.x >= box.x && p.x <= box.z && p.y >= box.y && p.y <= box.w;
}

int column_of(vec2 p, int n) {
	for (int k = 0; k < n; k++) {
		vec4 box = frame.boxes[k];
		vec4 body = frame.bodies[k];
		if (body.w > 0.0 && body.y < box.y && p.x >= body.x && p.x <= body.z && p.y >= body.y && p.y <= box.w) {
			return k;
		}
	}
	return -1;
}

bool crosses(vec2 a, vec2 b, vec4 box) {
	vec2 d = b - a;
	float t0 = 0.0;
	float t1 = 1.0;
	for (int axis = 0; axis < 2; axis++) {
		float from = axis == 0 ? a.x : a.y;
		float way = axis == 0 ? d.x : d.y;
		float low = axis == 0 ? box.x : box.y;
		float high = axis == 0 ? box.z : box.w;
		if (abs(way) < 0.0001) {
			if (from < low || from > high) {
				return false;
			}
		} else {
			float ta = (low - from) / way;
			float tb = (high - from) / way;
			t0 = max(t0, min(ta, tb));
			t1 = min(t1, max(ta, tb));
			if (t0 > t1) {
				return false;
			}
		}
	}
	return true;
}

float shade_between(vec2 p, vec2 l, int n, uint near_bits) {
	float shade = 0.0;
	int own = column_of(p, n);
	vec2 at = p;
	if (own >= 0) {
		at = vec2(p.x, frame.boxes[own].w + 0.5);
		if (l.y < frame.boxes[own].y) {
			shade = frame.bodies[own].w;
		}
	}
	for (int k = 0; k < n; k++) {
		if (k == own || ((near_bits >> uint(k)) & 1u) == 0u) {
			continue;
		}
		vec4 box = frame.boxes[k];
		float share = frame.bodies[k].w;
		if (share <= shade || box_holds(box, at) || box_holds(box, l)) {
			continue;
		}
		if (crosses(at, l, box)) {
			shade = share;
		}
	}
	return shade;
}

// --- Mode 0: a row into a lamp (LightGrid._row and _lamp's start) -----------------------------------

void write_lamp(uint i, vec4 l0, vec4 l1, vec4 l2, vec4 l3, vec4 l4) {
	uint at = (uint(pc.first) + i) * uint(LAMP_VEC4);
	lamps[at] = l0;
	lamps[at + 1u] = l1;
	lamps[at + 2u] = l2;
	lamps[at + 3u] = l3;
	lamps[at + 4u] = l4;
}

bool flag_set(float flags, float f) {
	return mod(floor(flags / f + 0.001), 2.0) > 0.5;
}

float coded_code(float custom_a) {
	float coded = (1.0 - custom_a) * 16.0;
	return coded - floor(coded + 0.5);
}

void row_to_lamp(uint i) {
	int at = int(i) * 16;
	float cell = frame.head.x;
	if (pc.kind == ROWS_BEAM) {
		// A beam's piece (LightGridGpu.add_beam): a, way, length, reach, ends; colour; box.
		vec4 l0 = vec4(rows[at], rows[at + 1], rows[at + 4], rows[at + 5]);
		vec4 l1 = vec4(rows[at + 2], rows[at + 3], 2.0, 0.0);
		vec4 l2 = vec4(rows[at + 8], rows[at + 9], rows[at + 10], rows[at + 6]);
		vec4 l4 = vec4(rows[at + 12], rows[at + 13], rows[at + 14], rows[at + 15]);
		write_lamp(i, l0, l1, l2, vec4(0.0), l4);
		return;
	}
	float cx = rows[at + 3];
	float cy = rows[at + 7];
	float hx = 0.0;
	float hy = 0.0;
	float wx = 1.0;
	float wy = 0.0;
	vec3 colour = vec3(0.0);
	float gx = 0.0;
	float gy = 0.0;
	if (pc.kind == ROWS_RUNE) {
		float half_size = sqrt(rows[at] * rows[at] + rows[at + 4] * rows[at + 4]) * 0.5 * RUNE_REACH * rows[at + 2];
		hx = half_size;
		hy = half_size;
		colour = glow_of(at) * (RUNE_STRENGTH * rows[at + 6]);
	} else if (pc.kind == ROWS_FLASH) {
		float through = clamp((coded_code(rows[at + 15]) - FLASH_FROM) / FLASH_SPAN, 0.0, 1.0);
		float strength = rows[at + 6] * (1.0 - through);
		if (strength > 0.0) {
			float ax = rows[at];
			float ay = rows[at + 4];
			float along = sqrt(ax * ax + ay * ay);
			if (along > 0.0) {
				wx = ax / along;
				wy = ay / along;
			}
			hx = along * 0.5 * pc.reach + pc.pad;
			hy = sqrt(rows[at + 1] * rows[at + 1] + rows[at + 5] * rows[at + 5]) * 0.5 * pc.reach + pc.pad;
			colour = glow_of(at) * strength;
		}
	} else if (pc.kind == ROWS_CUE) {
		float half_size = sqrt(rows[at] * rows[at] + rows[at + 4] * rows[at + 4]);
		hx = half_size;
		hy = half_size;
		colour = glow_of(at) * rows[at + 15];
	} else if (pc.kind == ROWS_SPOT) {
		// The flicker's dip worked out on the CPU (LightGridGpu: its hash needs doubles), at +12.
		float half_size = sqrt(rows[at] * rows[at] + rows[at + 4] * rows[at + 4]);
		hx = half_size;
		hy = half_size;
		float k = rows[at + 11] * (1.0 - rows[at + 12]);
		colour = vec3(rows[at + 8], rows[at + 9], rows[at + 10]) * k;
		gx = rows[at + 14];
		gy = rows[at + 15];
	} else if (flag_set(rows[at + 5], HF_LIVE)) {
		float red = floor(rows[at + 8] * 255.0 + 0.5);
		float shot_reach = red < 4.0 ? SPECK_REACH : SHOT_REACH + SHOT_REACH_ZOOM * max(floor(red / 4.0), 1.0);
		hx = shot_reach * rows[at + 2];
		hy = hx;
		colour = glow_of(at) * (SHOT_STRENGTH * rows[at + 6]);
	}
	if (hx <= 0.0 || dot(colour, colour) <= 0.0) {
		write_lamp(i, vec4(0.0), vec4(0.0), vec4(0.0), vec4(0.0), vec4(1.0, 1.0, -1.0, -1.0));
		return;
	}
	hx = max(hx, cell);
	hy = max(hy, cell);
	uint near_bits = 0u;
	vec2 lit = vec2(cx, cy);
	int n = int(frame.head.y);
	if (pc.blocked != 0 && n > 0) {
		if (pc.kind == ROWS_SPOT) {
			lit = vec2(cx + gx, cy + gy);
		} else {
			int k = column_of(lit, n);
			if (k >= 0) {
				lit = vec2(cx, frame.boxes[k].w + 0.5);
			}
		}
		float half_size = sqrt(hx * hx + hy * hy);
		float x0 = min(cx - half_size, lit.x);
		float y0 = min(cy - half_size, lit.y);
		float x1 = max(cx + half_size, lit.x);
		float y1 = max(cy + half_size, lit.y);
		for (int k = 0; k < n; k++) {
			vec4 box = frame.boxes[k];
			vec4 body = frame.bodies[k];
			if (body.w > 0.0 && min(box.x, body.x) <= x1 && max(box.z, body.z) >= x0 && min(box.y, body.y) <= y1 && box.w >= y0) {
				near_bits |= 1u << uint(k);
			}
		}
	}
	float big = max(hx, hy);
	write_lamp(i, vec4(cx, cy, hx, hy), vec4(wx, wy, 1.0, uintBitsToFloat(near_bits)), vec4(colour, 0.0), vec4(lit, 0.0, 0.0), vec4(cx - big, cy - big, cx + big, cy + big));
}

// --- Mode 1: a cell (LightGrid._lamp's and add_beam's loops, then bake) -----------------------------

vec3 lamp_at(uint lamp, vec2 p, int n) {
	uint at = lamp * uint(LAMP_VEC4);
	vec4 l0 = lamps[at];
	vec4 l1 = lamps[at + 1u];
	vec4 l2 = lamps[at + 2u];
	if (l1.z == 1.0) {
		float dx = p.x - l0.x;
		float dy = p.y - l0.y;
		float sx = (dx * l1.x + dy * l1.y) / l0.z;
		float sy = (-dx * l1.y + dy * l1.x) / l0.w;
		float f = 1.0 - sqrt(sx * sx + sy * sy);
		if (f <= 0.0) {
			return vec3(0.0);
		}
		float open = 1.0;
		uint near_bits = floatBitsToUint(l1.w);
		if (near_bits != 0u) {
			open = 1.0 - shade_between(p, lamps[at + 3u].xy, n, near_bits);
		}
		return l2.rgb * (f * f * open);
	}
	// A beam's piece: from its start a along its way, `reach` each side, rounded past its ends.
	float beam_reach = l0.w;
	float length_of = l0.z;
	bool first = mod(l2.w, 2.0) >= 1.0;
	bool last = l2.w >= 2.0;
	float qx = p.x - l0.x;
	float qy = p.y - l0.y;
	float x = qx * l1.x + qy * l1.y;
	float y = (-qx * l1.y + qy * l1.x) / beam_reach;
	float from_x = first ? -beam_reach : 0.0;
	float to_x = last ? length_of + beam_reach : length_of;
	if (x < from_x || x > to_x || y < -1.0 || y > 1.0) {
		return vec3(0.0);
	}
	float past = 0.0;
	if (x < 0.0 && first) {
		past = -x / beam_reach;
	} else if (x > length_of && last) {
		past = (x - length_of) / beam_reach;
	}
	float f = clamp(1.0 - sqrt(past * past + y * y), 0.0, 1.0);
	if (f <= 0.0) {
		return vec3(0.0);
	}
	return l2.rgb * (f * f);
}

void light_cells() {
	int view = pc.kind;
	vec4 v = frame.views[view * 2];
	vec4 placed = frame.views[view * 2 + 1];
	int columns = int(v.z);
	int lines = int(v.w);
	float cell = frame.head.x;
	int n = int(frame.head.y);
	uint lamp_count = uint(frame.head.z);
	uint tile = gl_WorkGroupID.x;
	int tile_x = int(tile % uint(pc.tiles_across));
	int tile_y = int(tile / uint(pc.tiles_across));
	uint local = gl_LocalInvocationIndex;
	int column = tile_x * TILE + int(local % uint(TILE));
	int line = tile_y * TILE + int(local / uint(TILE));
	bool inside = column < columns && line < lines;
	vec2 p = vec2(v.x + (float(column) + 0.5) * cell, v.y + (float(line) + 0.5) * cell);
	// The tile's cells' middles (what a lamp's box must come over).
	float tx0 = v.x + (float(tile_x * TILE) + 0.5) * cell;
	float ty0 = v.y + (float(tile_y * TILE) + 0.5) * cell;
	float tx1 = v.x + (float(min(tile_x * TILE + TILE - 1, columns - 1)) + 0.5) * cell;
	float ty1 = v.y + (float(min(tile_y * TILE + TILE - 1, lines - 1)) + 0.5) * cell;
	vec3 sum = vec3(0.0);
	for (uint base = 0u; base < lamp_count; base += 64u) {
		uint mine = base + local;
		uint keeps = 0u;
		if (mine < lamp_count) {
			vec4 box = lamps[mine * uint(LAMP_VEC4) + 4u];
			if (box.x <= tx1 && box.z >= tx0 && box.y <= ty1 && box.w >= ty0) {
				keeps = 1u;
			}
		}
		keep[local] = keeps;
		barrier();
		if (inside) {
			uint chunk = min(64u, lamp_count - base);
			for (uint j = 0u; j < chunk; j++) {
				if (keep[j] != 0u) {
					sum += lamp_at(base + j, p, n);
				}
			}
		}
		barrier();
	}
	if (inside) {
		vec3 bytes = floor(min(sum, vec3(1.0)) * 255.0 + 0.5);
		imageStore(atlas, ivec2(int(placed.x) + column, int(placed.y) + line), vec4(bytes / 255.0, 1.0));
	}
}

void main() {
	if (pc.mode == 0) {
		if (gl_GlobalInvocationID.x < uint(pc.count)) {
			row_to_lamp(gl_GlobalInvocationID.x);
		}
	} else {
		light_cells();
	}
}
"""
