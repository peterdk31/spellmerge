// SPDX-FileCopyrightText: 2026 peterdk31 and Spellmerge contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Grid lighting in native code (gameplay/feel/light_grid.gd; the owner's decision of 2026-11-21):
// MoteKernel's `light_grid_rows`, `light_grid_beam` and `light_grid_bake` do what LightGrid's
// `add_rows`, `add_beam` and `bake` do in GDScript, on the grid's own arrays in place, to the bit
// (tests/gameplay/feel/test_light_grid.gd compares them byte for byte). A GDScript `float` is a
// double here and a Vector2, Vector3, Vector4 or Color is single precision (as `glow`, a Vector3,
// and the blocking's points, Vector2s, are there); a packed float32 array's element is read as a
// float and written back rounded. What only draws keeps std:: maths (native/README.md): the spots'
// flicker's `sin` is the C library's, as GDScript's is.

#include "mote_kernel.h"

#include <cmath>

#include <godot_cpp/variant/color.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_color_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/packed_vector4_array.hpp>
#include <godot_cpp/variant/vector3.hpp>
#include <godot_cpp/variant/vector4.hpp>

#include "packed.h"

using namespace godot;

namespace {

// LightGrid's constants (checked against the script's by `check_light_grid`).
constexpr int64_t LG_STRIDE = 16;
constexpr int64_t LG_ROWS_SHOT = 0, LG_ROWS_RUNE = 1, LG_ROWS_FLASH = 2, LG_ROWS_SPOT = 3, LG_ROWS_CUE = 4;
constexpr double LG_SHOT_STRENGTH = 0.9, LG_RUNE_STRENGTH = 0.55, LG_SHOT_REACH = 26.0, LG_SHOT_REACH_ZOOM = 6.0;
constexpr double LG_SPECK_REACH = 14.0, LG_RUNE_REACH = 1.5, LG_FLASH_FROM = 0.02, LG_FLASH_SPAN = 0.42;
constexpr double LG_SPOT_RATE = 7.0, LG_HF_LIVE = 1.0;
constexpr int64_t LG_MATERIALS = 7, LG_ENEMY_PLAYER = 4, LG_KIND_COUNT = 22, LG_ENEMY_RAMP = 23, LG_EXACT = 24;
constexpr int64_t LG_PALETTE_MOST = 4, LG_BLOCKERS_MOST = 32;
constexpr double LG_INFUSION_MARK = 128.0 / 255.0;
const double LG_P_BASE[15] = {0.231, 0.451, 0.788, 0.851, 0.278, 0.478, 0.247, 0.561, 0.310, 0.541, 0.310, 0.769, 0.651, 0.541, 0.165};
const double LG_P_LIGHT[15] = {0.498, 0.753, 0.941, 0.961, 0.604, 0.722, 0.561, 0.831, 0.416, 0.788, 0.604, 0.941, 0.890, 0.812, 0.420};
const double LG_SHADES[63] = {
	0.561, 0.176, 0.165, 0.878, 0.349, 0.184, 1.0, 0.635, 0.235,
	0.722, 0.502, 0.122, 0.949, 0.761, 0.188, 1.0, 0.953, 0.651,
	0.122, 0.439, 0.502, 0.310, 0.839, 0.863, 0.769, 0.965, 0.949,
	0.290, 0.078, 0.314, 0.627, 0.188, 0.604, 0.878, 0.541, 0.847,
	0.247, 0.420, 0.063, 0.706, 0.910, 0.165, 0.933, 1.0, 0.651,
	0.639, 0.624, 0.722, 0.831, 0.816, 0.878, 0.957, 0.945, 0.918,
	0.059, 0.290, 0.267, 0.118, 0.612, 0.549, 0.435, 0.863, 0.753,
};

// The members read: C++ name, GDScript member, type.
#define LIGHT_GRID_FIELDS(X) \
	X(cell, "cell", FLOAT) \
	X(view_count, "view_count", INT) \
	X(view_origin, "view_origin", PACKED_FLOAT64_ARRAY) \
	X(view_size, "view_size", PACKED_INT32_ARRAY) \
	X(view_at, "view_at", PACKED_INT32_ARRAY) \
	X(atlas_width, "atlas_width", INT) \
	X(atlas_height, "atlas_height", INT) \
	X(rgb, "rgb", PACKED_FLOAT32_ARRAY) \
	X(bytes, "bytes", PACKED_BYTE_ARRAY) \
	X(blocker_boxes, "blocker_boxes", PACKED_VECTOR4_ARRAY) \
	X(blocker_bodies, "blocker_bodies", PACKED_VECTOR4_ARRAY) \
	X(blocker_count, "blocker_count", INT) \
	X(tints, "tints", PACKED_COLOR_ARRAY)

struct GridNames {
#define LG_DECLARE(id, gd, type) StringName id;
	LIGHT_GRID_FIELDS(LG_DECLARE)
#undef LG_DECLARE
	GridNames() {
#define LG_INIT(id, gd, type) id = StringName(gd);
		LIGHT_GRID_FIELDS(LG_INIT)
#undef LG_INIT
	}
};

GridNames *grid_names = nullptr;

const GridNames &gn() {
	if (grid_names == nullptr) {
		grid_names = memnew(GridNames);
	}
	return *grid_names;
}

// One frame's grid, read from the LightGrid for one call.
struct Grid {
	double cell = 8.0;
	int64_t views = 0;
	int64_t width = 1;
	Arr<PackedFloat64Array> origin;
	Arr<PackedInt32Array> size, at;
	Arr<PackedFloat32Array> rgb;
	Arr<PackedVector4Array> boxes, bodies;
	int64_t blockers = 0;
	Arr<PackedColorArray> tints;

	bool load(Object *g) {
		const GridNames &k = gn();
		cell = g->get(k.cell);
		views = g->get(k.view_count);
		width = g->get(k.atlas_width);
		const int64_t height = g->get(k.atlas_height);
		origin.load(g, k.view_origin);
		size.load(g, k.view_size);
		at.load(g, k.view_at);
		rgb.load(g, k.rgb);
		boxes.load(g, k.blocker_boxes);
		bodies.load(g, k.blocker_bodies);
		blockers = g->get(k.blocker_count);
		tints.load(g, k.tints);
		blockers = clampi(blockers, 0, mini(LG_BLOCKERS_MOST, mini(boxes.n, bodies.n)));
		return views >= 0 && origin.n >= views * 2 && size.n >= views * 2 && at.n >= views * 2 && rgb.n >= width * height * 3 && cell > 0.0;
	}

	// GDScript's `rgb[c] += v`: the element read as a float, added in doubles, rounded back.
	void add(int64_t c, double r, double g, double b) {
		rgb[c] = (float)((double)rgb[c] + r);
		rgb[c + 1] = (float)((double)rgb[c + 1] + g);
		rgb[c + 2] = (float)((double)rgb[c + 2] + b);
	}
};

// --- LightBlockers' pick (gameplay/feel/light_blockers.gd), in its types ---

bool box_holds(const Vector4 &box, const Vector2 &p) {
	return p.x >= box.x && p.x <= box.z && p.y >= box.y && p.y <= box.w;
}

int64_t column_of(const Vector2 &p, Grid &gr) {
	for (int64_t k = 0; k < gr.blockers; k++) {
		const Vector4 box = gr.boxes[k];
		const Vector4 body = gr.bodies[k];
		if (body.w > 0.0 && body.y < box.y && p.x >= body.x && p.x <= body.z && p.y >= body.y && p.y <= box.w) {
			return k;
		}
	}
	return -1;
}

Vector2 lit_as(const Vector2 &p, Grid &gr) {
	const int64_t k = column_of(p, gr);
	return k >= 0 ? Vector2(p.x, (real_t)((double)gr.boxes[k].w + 0.5)) : p;
}

bool crosses(const Vector2 &a, const Vector2 &b, const Vector4 &box) {
	const Vector2 d = b - a;
	double t0 = 0.0;
	double t1 = 1.0;
	for (int axis = 0; axis < 2; axis++) {
		const double from = axis == 0 ? a.x : a.y;
		const double way = axis == 0 ? d.x : d.y;
		const double low = axis == 0 ? box.x : box.y;
		const double high = axis == 0 ? box.z : box.w;
		if (std::fabs(way) < 0.0001) {
			if (from < low || from > high) {
				return false;
			}
		} else {
			const double ta = (low - from) / way;
			const double tb = (high - from) / way;
			t0 = maxf(t0, minf(ta, tb));
			t1 = minf(t1, maxf(ta, tb));
			if (t0 > t1) {
				return false;
			}
		}
	}
	return true;
}

double shade_between(const Vector2 &p, const Vector2 &l, Grid &gr, int64_t near_bits) {
	double shade = 0.0;
	const int64_t own = column_of(p, gr);
	Vector2 at = p;
	if (own >= 0) {
		at = Vector2(p.x, (real_t)((double)gr.boxes[own].w + 0.5));
		if (l.y < gr.boxes[own].y) {
			shade = gr.bodies[own].w;
		}
	}
	for (int64_t k = 0; k < gr.blockers; k++) {
		if (k == own || ((near_bits >> k) & 1) == 0) {
			continue;
		}
		const Vector4 box = gr.boxes[k];
		const double share = gr.bodies[k].w;
		if (share <= shade || box_holds(box, at) || box_holds(box, l)) {
			continue;
		}
		if (crosses(at, l, box)) {
			shade = share;
		}
	}
	return shade;
}

// --- The colours (LightGrid.look_glow) ---

int64_t material_of(double r, double g, double b) {
	int64_t best = 0;
	double nearest = 9.0;
	for (int64_t i = 0; i < LG_MATERIALS * 3; i++) {
		const double dr = r - LG_SHADES[i * 3];
		const double dg = g - LG_SHADES[i * 3 + 1];
		const double db = b - LG_SHADES[i * 3 + 2];
		const double d = std::sqrt(dr * dr + dg * dg + db * db);
		if (d < nearest) {
			nearest = d;
			best = i / 3;
		}
	}
	return best;
}

Vector3 shade_of(int64_t m, int64_t shade) {
	const int64_t i = (m * 3 + shade) * 3;
	return Vector3((real_t)LG_SHADES[i], (real_t)LG_SHADES[i + 1], (real_t)LG_SHADES[i + 2]);
}

Vector3 mix3(const Vector3 &a, const Vector3 &b, double t) {
	return Vector3((real_t)((double)a.x + ((double)b.x - (double)a.x) * t), (real_t)((double)a.y + ((double)b.y - (double)a.y) * t),
			(real_t)((double)a.z + ((double)b.z - (double)a.z) * t));
}

bool bit_set(int64_t b0, int64_t b1, int64_t b2, int64_t look) {
	const int64_t bit = look - 1;
	const int64_t byte = bit < 8 ? b0 : (bit < 16 ? b1 : b2);
	return ((byte >> (bit % 8)) & 1) == 1;
}

Vector3 look_glow(double cr, double cg, double cb, int64_t who, int64_t b0, int64_t b1, int64_t b2, bool own_infusions, Grid &gr) {
	const int64_t player = bit_set(b0, b1, b2, LG_ENEMY_RAMP) ? LG_ENEMY_PLAYER : who;
	Vector3 mid, hi;
	int64_t first = -1;
	const bool plain = cr > 0.99 && cg > 0.99 && cb > 0.99;
	if (bit_set(b0, b1, b2, LG_EXACT)) {
		mid = Vector3((real_t)cr, (real_t)cg, (real_t)cb);
		hi = Vector3((real_t)(cr + (1.0 - cr) * 0.35), (real_t)(cg + (1.0 - cg) * 0.35), (real_t)(cb + (1.0 - cb) * 0.35));
	} else if (plain) {
		hi = Vector3((real_t)LG_P_LIGHT[player * 3], (real_t)LG_P_LIGHT[player * 3 + 1], (real_t)LG_P_LIGHT[player * 3 + 2]);
		mid = Vector3((real_t)LG_P_BASE[player * 3], (real_t)LG_P_BASE[player * 3 + 1], (real_t)LG_P_BASE[player * 3 + 2]);
	} else {
		first = material_of(cr, cg, cb);
		mid = shade_of(first, 1);
		hi = shade_of(first, 2);
	}
	Vector3 glow = mix3(mid, hi, 0.35);
	if (first >= 0 && !own_infusions) {
		int64_t materials[4] = {first, -1, -1, -1};
		int64_t count = 1;
		for (int64_t layer = 1; layer <= LG_KIND_COUNT; layer++) {
			if (count < LG_PALETTE_MOST && bit_set(b0, b1, b2, layer)) {
				const Color t = layer < gr.tints.n ? gr.tints[layer] : Color(0, 0, 0, 0);
				int64_t m = first;
				if (std::fabs((double)t.a - LG_INFUSION_MARK) < 0.1) {
					m = material_of(t.r, t.g, t.b);
				}
				if (m != materials[0] && m != materials[1] && m != materials[2]) {
					materials[count] = m;
					count++;
				}
			}
		}
		if (count > 1) {
			const int64_t glows = count > 2 ? materials[2] : materials[1];
			glow = mix3(shade_of(glows, 1), shade_of(glows, 2), 0.35);
		}
	}
	return glow;
}

Vector3 glow_of(const float *row, Grid &gr) {
	const double red = std::floor((double)row[8] * 255.0 + 0.5);
	const int64_t who = (int64_t)std::fmod(red, 4.0);
	const int64_t b0 = (int64_t)std::floor((double)row[9] * 255.0 + 0.5);
	const int64_t b1 = (int64_t)std::floor((double)row[10] * 255.0 + 0.5);
	const int64_t b2 = (int64_t)std::floor((double)row[11] * 255.0 + 0.5);
	return look_glow(row[12], row[13], row[14], who, b0, b1, b2, false, gr);
}

bool flag_set(double flags, double f) {
	return std::fmod(std::floor(flags / f + 0.001), 2.0) > 0.5;
}

double coded_code(double custom_a) {
	const double coded = (1.0 - custom_a) * 16.0;
	return coded - std::floor(coded + 0.5);
}

double length2(double x, double y) {
	return std::sqrt(x * x + y * y);
}

// LightGrid._lamp.
void lamp(Grid &gr, double cx, double cy, double hx, double hy, double wx, double wy, double r, double g, double b, double gx, double gy,
		bool spot, bool blocked) {
	int64_t near = 0;
	double lx = cx;
	double ly = cy;
	if (blocked && gr.blockers > 0) {
		if (spot) {
			lx = cx + gx;
			ly = cy + gy;
		} else {
			const Vector2 lit = lit_as(Vector2((real_t)cx, (real_t)cy), gr);
			lx = lit.x;
			ly = lit.y;
		}
		const double half = std::sqrt(hx * hx + hy * hy);
		const double x0 = minf(cx - half, lx);
		const double y0 = minf(cy - half, ly);
		const double x1 = maxf(cx + half, lx);
		const double y1 = maxf(cy + half, ly);
		for (int64_t k = 0; k < gr.blockers; k++) {
			const Vector4 box = gr.boxes[k];
			const Vector4 body = gr.bodies[k];
			if (body.w > 0.0 && minf(box.x, body.x) <= x1 && maxf(box.z, body.z) >= x0 && minf(box.y, body.y) <= y1 && box.w >= y0) {
				near |= (int64_t)1 << k;
			}
		}
	}
	const Vector2 lamp_at((real_t)lx, (real_t)ly);
	const double big = maxf(hx, hy);
	for (int64_t view = 0; view < gr.views; view++) {
		const double ox = gr.origin[view * 2];
		const double oy = gr.origin[view * 2 + 1];
		const int64_t c0 = maxi(floori((cx - big - ox) / gr.cell), 0);
		const int64_t l0 = maxi(floori((cy - big - oy) / gr.cell), 0);
		const int64_t c1 = mini(floori((cx + big - ox) / gr.cell), (int64_t)gr.size[view * 2] - 1);
		const int64_t l1 = mini(floori((cy + big - oy) / gr.cell), (int64_t)gr.size[view * 2 + 1] - 1);
		for (int64_t line = l0; line <= l1; line++) {
			const double py = oy + ((double)line + 0.5) * gr.cell;
			const double dy = py - cy;
			for (int64_t column = c0; column <= c1; column++) {
				const double px = ox + ((double)column + 0.5) * gr.cell;
				const double dx = px - cx;
				const double sx = (dx * wx + dy * wy) / hx;
				const double sy = (-dx * wy + dy * wx) / hy;
				const double f = 1.0 - std::sqrt(sx * sx + sy * sy);
				if (f <= 0.0) {
					continue;
				}
				double open = 1.0;
				if (near != 0) {
					open = 1.0 - shade_between(Vector2((real_t)px, (real_t)py), lamp_at, gr, near);
				}
				const double lit = f * f * open;
				const int64_t c = (((int64_t)gr.at[view * 2 + 1] + line) * gr.width + gr.at[view * 2] + column) * 3;
				gr.add(c, r * lit, g * lit, b * lit);
			}
		}
	}
}

// LightGrid._row.
void row_light(Grid &gr, const float *row, int64_t kind, double reach, double pad, double now, bool blocked) {
	const double cx = row[3];
	const double cy = row[7];
	double hx = 0.0, hy = 0.0, wx = 1.0, wy = 0.0, r = 0.0, g = 0.0, b = 0.0, gx = 0.0, gy = 0.0;
	if (kind == LG_ROWS_RUNE) {
		const double half = length2(row[0], row[4]) * 0.5 * LG_RUNE_REACH * (double)row[2];
		hx = half;
		hy = half;
		const Vector3 glow = glow_of(row, gr);
		const double k = LG_RUNE_STRENGTH * (double)row[6];
		r = (double)glow.x * k;
		g = (double)glow.y * k;
		b = (double)glow.z * k;
	} else if (kind == LG_ROWS_FLASH) {
		const double through = clampf((coded_code(row[15]) - LG_FLASH_FROM) / LG_FLASH_SPAN, 0.0, 1.0);
		const double strength = (double)row[6] * (1.0 - through);
		if (strength > 0.0) {
			const double ax = row[0];
			const double ay = row[4];
			const double along = std::sqrt(ax * ax + ay * ay);
			if (along > 0.0) {
				wx = ax / along;
				wy = ay / along;
			}
			hx = along * 0.5 * reach + pad;
			hy = length2(row[1], row[5]) * 0.5 * reach + pad;
			const Vector3 glow = glow_of(row, gr);
			r = (double)glow.x * strength;
			g = (double)glow.y * strength;
			b = (double)glow.z * strength;
		}
	} else if (kind == LG_ROWS_CUE) {
		const double half = length2(row[0], row[4]);
		hx = half;
		hy = half;
		const Vector3 glow = glow_of(row, gr);
		const double bright = row[15];
		r = (double)glow.x * bright;
		g = (double)glow.y * bright;
		b = (double)glow.z * bright;
	} else if (kind == LG_ROWS_SPOT) {
		const double half = length2(row[0], row[4]);
		const double step_of = std::floor(now * LG_SPOT_RATE + (double)row[13] * 13.0);
		const double wave = std::sin(step_of * 12.9898 + (double)row[13] * 78.233) * 43758.5453;
		const double dip = (double)row[12] * (wave - std::floor(wave));
		hx = half;
		hy = half;
		const double k = (double)row[11] * (1.0 - dip);
		r = (double)row[8] * k;
		g = (double)row[9] * k;
		b = (double)row[10] * k;
		gx = row[14];
		gy = row[15];
	} else {
		if (flag_set(row[5], LG_HF_LIVE)) {
			const double red = std::floor((double)row[8] * 255.0 + 0.5);
			const double shot_reach = red < 4.0 ? LG_SPECK_REACH : LG_SHOT_REACH + LG_SHOT_REACH_ZOOM * maxf(std::floor(red / 4.0), 1.0);
			hx = shot_reach * (double)row[2];
			hy = hx;
			const Vector3 glow = glow_of(row, gr);
			const double k = LG_SHOT_STRENGTH * (double)row[6];
			r = (double)glow.x * k;
			g = (double)glow.y * k;
			b = (double)glow.z * k;
		}
	}
	if (hx <= 0.0 || r * r + g * g + b * b <= 0.0) {
		return;
	}
	lamp(gr, cx, cy, hx, hy, wx, wy, r, g, b, gx, gy, kind == LG_ROWS_SPOT, blocked);
}

} // namespace

PackedStringArray MoteKernel::check_light_grid(Object *object) const {
	PackedStringArray wrong;
	ERR_FAIL_NULL_V(object, wrong);
	const GridNames &k = gn();
#define LG_CHECK(id, gd, type)                                                   \
	if (object->get(k.id).get_type() != Variant::type) {                         \
		wrong.push_back(String("light grid member ") + gd + " missing or retyped"); \
	}
	LIGHT_GRID_FIELDS(LG_CHECK)
#undef LG_CHECK
	bool same = (int64_t)object->get("STRIDE") == LG_STRIDE && (int64_t)object->get("ROWS_SHOT") == LG_ROWS_SHOT &&
			(int64_t)object->get("ROWS_RUNE") == LG_ROWS_RUNE && (int64_t)object->get("ROWS_FLASH") == LG_ROWS_FLASH &&
			(int64_t)object->get("ROWS_SPOT") == LG_ROWS_SPOT && (int64_t)object->get("ROWS_CUE") == LG_ROWS_CUE &&
			(double)object->get("SHOT_STRENGTH") == LG_SHOT_STRENGTH && (double)object->get("RUNE_STRENGTH") == LG_RUNE_STRENGTH &&
			(double)object->get("SHOT_REACH") == LG_SHOT_REACH && (double)object->get("SHOT_REACH_ZOOM") == LG_SHOT_REACH_ZOOM &&
			(double)object->get("SPECK_REACH") == LG_SPECK_REACH && (double)object->get("RUNE_REACH") == LG_RUNE_REACH &&
			(double)object->get("FLASH_FROM") == LG_FLASH_FROM && (double)object->get("FLASH_SPAN") == LG_FLASH_SPAN &&
			(double)object->get("SPOT_RATE") == LG_SPOT_RATE && (double)object->get("HF_LIVE") == LG_HF_LIVE &&
			(int64_t)object->get("MATERIALS") == LG_MATERIALS && (int64_t)object->get("ENEMY_PLAYER") == LG_ENEMY_PLAYER &&
			(int64_t)object->get("KIND_COUNT") == LG_KIND_COUNT && (int64_t)object->get("ENEMY_RAMP") == LG_ENEMY_RAMP &&
			(int64_t)object->get("EXACT") == LG_EXACT && (int64_t)object->get("PALETTE_MOST") == LG_PALETTE_MOST &&
			(double)object->get("INFUSION_MARK") == LG_INFUSION_MARK;
	const PackedFloat64Array shades = object->get("SHADES");
	const PackedFloat64Array base = object->get("P_BASE");
	const PackedFloat64Array light = object->get("P_LIGHT");
	same = same && shades.size() == 63 && base.size() == 15 && light.size() == 15;
	for (int64_t i = 0; same && i < 63; i++) {
		same = shades[i] == LG_SHADES[i];
	}
	for (int64_t i = 0; same && i < 15; i++) {
		same = base[i] == LG_P_BASE[i] && light[i] == LG_P_LIGHT[i];
	}
	if (!same) {
		wrong.push_back("the light grid's numbers");
	}
	return wrong;
}

void MoteKernel::light_grid_rows(Object *grid, const PackedFloat32Array &rows, int64_t count, int64_t kind, double reach, double pad, double now,
		bool blocked) {
	ERR_FAIL_NULL(grid);
	Grid gr;
	ERR_FAIL_COND(!gr.load(grid));
	count = mini(count, rows.size() / LG_STRIDE);
	if (count <= 0 || gr.views == 0) {
		return;
	}
	const float *p = rows.ptr();
	for (int64_t i = 0; i < count; i++) {
		row_light(gr, p + i * LG_STRIDE, kind, reach, pad, now, blocked);
	}
}

void MoteKernel::light_grid_beam(Object *grid, const PackedVector3Array &path, int64_t points, double beam_reach, const Color &colour) {
	ERR_FAIL_NULL(grid);
	Grid gr;
	ERR_FAIL_COND(!gr.load(grid));
	points = mini(points, path.size());
	if (points < 2 || gr.views == 0 || beam_reach <= 0.0) {
		return;
	}
	const double r = colour.r;
	const double g = colour.g;
	const double b = colour.b;
	if (r * r + g * g + b * b <= 0.0) {
		return;
	}
	for (int64_t k = 0; k < points - 1; k++) {
		const double ax = path[k].x;
		const double ay = path[k].y;
		const double dx = (double)path[k + 1].x - ax;
		const double dy = (double)path[k + 1].y - ay;
		const double length = std::sqrt(dx * dx + dy * dy);
		const double wx = length > 0.0 ? dx / length : 1.0;
		const double wy = length > 0.0 ? dy / length : 0.0;
		const bool first = k == 0;
		const bool last = k == points - 2;
		const double from_x = first ? -beam_reach : 0.0;
		const double to_x = last ? length + beam_reach : length;
		const double low_x = minf(ax, ax + dx) - beam_reach;
		const double low_y = minf(ay, ay + dy) - beam_reach;
		const double high_x = maxf(ax, ax + dx) + beam_reach;
		const double high_y = maxf(ay, ay + dy) + beam_reach;
		for (int64_t view = 0; view < gr.views; view++) {
			const double ox = gr.origin[view * 2];
			const double oy = gr.origin[view * 2 + 1];
			const int64_t c0 = maxi(floori((low_x - ox) / gr.cell), 0);
			const int64_t l0 = maxi(floori((low_y - oy) / gr.cell), 0);
			const int64_t c1 = mini(floori((high_x - ox) / gr.cell), (int64_t)gr.size[view * 2] - 1);
			const int64_t l1 = mini(floori((high_y - oy) / gr.cell), (int64_t)gr.size[view * 2 + 1] - 1);
			for (int64_t line = l0; line <= l1; line++) {
				const double py = oy + ((double)line + 0.5) * gr.cell;
				for (int64_t column = c0; column <= c1; column++) {
					const double px = ox + ((double)column + 0.5) * gr.cell;
					const double qx = px - ax;
					const double qy = py - ay;
					const double x = qx * wx + qy * wy;
					const double y = (-qx * wy + qy * wx) / beam_reach;
					if (x < from_x || x > to_x || y < -1.0 || y > 1.0) {
						continue;
					}
					double past = 0.0;
					if (x < 0.0 && first) {
						past = -x / beam_reach;
					} else if (x > length && last) {
						past = (x - length) / beam_reach;
					}
					const double f = clampf(1.0 - std::sqrt(past * past + y * y), 0.0, 1.0);
					if (f <= 0.0) {
						continue;
					}
					const int64_t c = (((int64_t)gr.at[view * 2 + 1] + line) * gr.width + gr.at[view * 2] + column) * 3;
					const double lit = f * f;
					gr.add(c, r * lit, g * lit, b * lit);
				}
			}
		}
	}
}

void MoteKernel::light_grid_bake(Object *grid) {
	ERR_FAIL_NULL(grid);
	const GridNames &k = gn();
	const int64_t width = grid->get(k.atlas_width);
	const int64_t height = grid->get(k.atlas_height);
	Arr<PackedFloat32Array> rgb;
	Arr<PackedByteArray> bytes;
	rgb.load(grid, k.rgb);
	bytes.load(grid, k.bytes);
	const int64_t cells = width * height;
	ERR_FAIL_COND(rgb.n < cells * 3 || bytes.n < cells * 4);
	for (int64_t c = 0; c < cells; c++) {
		for (int64_t ch = 0; ch < 3; ch++) {
			bytes[c * 4 + ch] = (uint8_t)(int64_t)(minf((double)rgb[c * 3 + ch], 1.0) * 255.0 + 0.5);
		}
	}
}

void MoteKernel::free_grid_names() {
	if (grid_names != nullptr) {
		memdelete(grid_names);
		grid_names = nullptr;
	}
}
