// SPDX-FileCopyrightText: 2026 peterdk31 and Spellmerge contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//
// See body_kernel.h. Mirrors core/projectiles/wall_slide.gd line by line: a GDScript `float` is a
// double and a Vector2 single precision, so everything is worked out in doubles from the inputs and
// rounded to a Vector2 only at the end, as the GDScript does. sqrt is correctly rounded everywhere,
// and nothing here calls the C library's other maths.

#include "body_kernel.h"
#include "packed.h"

#include <cmath>

#include <godot_cpp/core/class_db.hpp>

using namespace godot;

namespace {

inline double minf(double a, double b) { return a < b ? a : b; }
inline double maxf(double a, double b) { return a > b ? a : b; }
inline int64_t mini(int64_t a, int64_t b) { return a < b ? a : b; }
inline int64_t maxi(int64_t a, int64_t b) { return a > b ? a : b; }
inline int64_t ceili(double x) { return (int64_t)std::ceil(x); }

// `WallSlide._near`.
bool near(const uint8_t *cells, int64_t w, int64_t h, double cell, double ox, double oy, double lx, double ly,
		double hx, double hy) {
	const int64_t x0 = maxi(floori((lx - ox) / cell), 0);
	const int64_t x1 = mini(floori((hx - ox) / cell), w - 1);
	const int64_t y0 = maxi(floori((ly - oy) / cell), 0);
	const int64_t y1 = mini(floori((hy - oy) / cell), h - 1);
	for (int64_t cy = y0; cy <= y1; cy++) {
		for (int64_t cx = x0; cx <= x1; cx++) {
			if (cells[cy * w + cx] != 0) {
				return true;
			}
		}
	}
	return false;
}

// `WallSlide._open`.
inline bool open(const uint8_t *cells, int64_t w, int64_t h, int64_t cx, int64_t cy) {
	return cx < 0 || cy < 0 || cx >= w || cy >= h || cells[cy * w + cx] == 0;
}

// WallSlide's sides.
constexpr int64_t NO_EXIT = -1, LEFT = 0, RIGHT = 1, UP = 2, DOWN = 3;

// `WallSlide._exit`.
int64_t exit_side(const uint8_t *cells, int64_t w, int64_t h, int64_t cx, int64_t cy, double left, double right,
		double up, double down) {
	int64_t side = NO_EXIT;
	double best = INFINITY;
	if (open(cells, w, h, cx - 1, cy) && left < best) {
		best = left;
		side = LEFT;
	}
	if (open(cells, w, h, cx + 1, cy) && right < best) {
		best = right;
		side = RIGHT;
	}
	if (open(cells, w, h, cx, cy - 1) && up < best) {
		best = up;
		side = UP;
	}
	if (open(cells, w, h, cx, cy + 1) && down < best) {
		side = DOWN;
	}
	return side;
}

// `WallSlide._gap`, `_way_x`, `_way_y`.
inline double gap(int64_t side, double left, double right, double up, double down) {
	return side == LEFT ? left : (side == RIGHT ? right : (side == UP ? up : down));
}
inline double way_x(int64_t side) { return side == LEFT ? -1.0 : (side == RIGHT ? 1.0 : 0.0); }
inline double way_y(int64_t side) { return side == UP ? -1.0 : (side == DOWN ? 1.0 : 0.0); }

} // namespace

bool BodyKernel::configure(const Dictionary &config) {
	_ready = config.has("ITERATIONS") && config.has("MIN_STRIDE");
	if (_ready) {
		_iterations = config["ITERATIONS"];
		_min_stride = config["MIN_STRIDE"];
	}
	return _ready;
}

Vector2 BodyKernel::slide(const PackedByteArray &cells_array, int64_t w, int64_t h, double cell,
		const Vector2 &origin, const Vector2 &from, const Vector2 &motion, double radius) const {
	double px = from.x;
	double py = from.y;
	const double mx = motion.x;
	const double my = motion.y;
	const double r = maxf(radius, 0.0);
	const double ox = origin.x;
	const double oy = origin.y;
	ERR_FAIL_COND_V_MSG(!_ready, Vector2(px + mx, py + my), "BodyKernel: configure it first");
	const uint8_t *cells = cells_array.ptr();
	if (cells_array.size() < w * h ||
			!near(cells, w, h, cell, ox, oy, minf(px, px + mx) - r, minf(py, py + my) - r, maxf(px, px + mx) + r,
					maxf(py, py + my) + r)) {
		return Vector2(px + mx, py + my);
	}
	const double length = std::sqrt(mx * mx + my * my);
	const double stride = clampf(r * 0.5, _min_stride, cell * 0.5);
	const int64_t strides = maxi(ceili(length / stride), 1);
	const double sx = mx / (double)strides;
	const double sy = my / (double)strides;
	for (int64_t s = 0; s < strides; s++) {
		px += sx;
		py += sy;
		for (int64_t i = 0; i < _iterations; i++) {
			const int64_t ix = floori((px - ox) / cell);
			const int64_t iy = floori((py - oy) / cell);
			if (!open(cells, w, h, ix, iy)) {
				const double bx = ox + (double)ix * cell;
				const double by = oy + (double)iy * cell;
				const double left = px - bx;
				const double right = bx + cell - px;
				const double up = py - by;
				const double down = by + cell - py;
				const int64_t side = exit_side(cells, w, h, ix, iy, left, right, up, down);
				if (side == NO_EXIT) {
					break;
				}
				const double out = gap(side, left, right, up, down) + r;
				px += way_x(side) * out;
				py += way_y(side) * out;
				continue;
			}
			const int64_t x0 = maxi(floori((px - r - ox) / cell), 0);
			const int64_t x1 = mini(floori((px + r - ox) / cell), w - 1);
			const int64_t y0 = maxi(floori((py - r - oy) / cell), 0);
			const int64_t y1 = mini(floori((py + r - oy) / cell), h - 1);
			double best = 0.0;
			double bnx = 0.0;
			double bny = 0.0;
			for (int64_t cy = y0; cy <= y1; cy++) {
				for (int64_t cx = x0; cx <= x1; cx++) {
					if (cells[cy * w + cx] == 0) {
						continue;
					}
					const double bx0 = ox + (double)cx * cell;
					const double by0 = oy + (double)cy * cell;
					const double bx1 = bx0 + cell;
					const double by1 = by0 + cell;
					const double qx = clampf(px, bx0, bx1);
					const double qy = clampf(py, by0, by1);
					const double dx = px - qx;
					const double dy = py - qy;
					const double d2 = dx * dx + dy * dy;
					double depth = 0.0;
					double nx = 0.0;
					double ny = 0.0;
					if (d2 > 0.0) {
						if (d2 >= r * r) {
							continue;
						}
						const double d = std::sqrt(d2);
						depth = r - d;
						nx = dx / d;
						ny = dy / d;
					} else {
						// The centre is on the cell's edge (in an open cell beside it): out by that side.
						const double left = px - bx0;
						const double right = bx1 - px;
						const double up = py - by0;
						const double down = by1 - py;
						const int64_t side = exit_side(cells, w, h, cx, cy, left, right, up, down);
						if (side == NO_EXIT) {
							continue;
						}
						depth = gap(side, left, right, up, down) + r;
						nx = way_x(side);
						ny = way_y(side);
					}
					if (depth > best) {
						best = depth;
						bnx = nx;
						bny = ny;
					}
				}
			}
			if (best <= 0.0) {
				break;
			}
			px += bnx * best;
			py += bny * best;
		}
	}
	return Vector2(px, py);
}

void BodyKernel::_bind_methods() {
	ClassDB::bind_method(D_METHOD("configure", "config"), &BodyKernel::configure);
	ClassDB::bind_method(D_METHOD("slide", "cells", "w", "h", "cell", "origin", "from", "motion", "radius"),
			&BodyKernel::slide);
}
