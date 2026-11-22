// SPDX-FileCopyrightText: 2026 peterdk31 and Spellmerge contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//
// The room grid's rays (core/projectiles/room_grid.gd), shared by the kernels that walk them: where
// a path first enters a wall (`RoomGrid.wall_hit`, the shots' hit pass and the long rays of an AI's
// sight and line of fire) or a wall, a body's ground or a hole (`RoomGrid._way_hit`, an AI's walk).
// Mirrored line by line, in its float types: the grid's coordinates are Vector2s (single precision),
// a GDScript float a double (native/README.md, "Same results"). Pure functions of the arrays handed.

#pragma once

#include "packed.h"

#include <cmath>
#include <cstdint>

namespace grid_ray {

using namespace godot;

// `RoomGrid.wall_hit` (the grid has walls): how far along `from`->`to` (0 to 1) the path first enters
// a cell not 0 in `cells` (`w` by `h` cells of `cell` pixels from `origin`), or -1.
inline double wall_hit(const uint8_t *cells, int64_t w, int64_t h, double cell, const Vector2 &origin, const Vector2 &from, const Vector2 &to) {
	const Vector2 start = (from - origin) / (real_t)cell;
	const Vector2 delta = (to - from) / (real_t)cell;
	int64_t cx = floori(start.x);
	int64_t cy = floori(start.y);
	// `start.x + delta.x` in GDScript adds two floats, which are doubles.
	const int64_t end_x = floori((double)start.x + (double)delta.x);
	const int64_t end_y = floori((double)start.y + (double)delta.y);
	if (cx == end_x && cy == end_y) {
		if (cx >= 0 && cx < w && cy >= 0 && cy < h && cells[cy * w + cx] != 0) {
			return 0.0;
		}
		return -1.0;
	}
	if (std::abs(end_x - cx) <= 1 && std::abs(end_y - cy) <= 1 && MIN(cx, end_x) >= 0 && MAX(cx, end_x) < w && MIN(cy, end_y) >= 0 &&
			MAX(cy, end_y) < h) {
		const int64_t row0 = cy * w;
		const int64_t row1 = end_y * w;
		if (cells[row0 + cx] == 0 && cells[row0 + end_x] == 0 && cells[row1 + cx] == 0 && cells[row1 + end_x] == 0) {
			return -1.0;
		}
	}
	const int64_t step_x = delta.x > 0.0f ? 1 : -1;
	const int64_t step_y = delta.y > 0.0f ? 1 : -1;
	double next_x = INFINITY;
	double next_y = INFINITY;
	double per_x = INFINITY;
	double per_y = INFINITY;
	if (delta.x != 0.0f) {
		per_x = std::abs(1.0 / (double)delta.x);
		next_x = ((double)(cx + (step_x > 0 ? 1 : 0)) - (double)start.x) / (double)delta.x;
	}
	if (delta.y != 0.0f) {
		per_y = std::abs(1.0 / (double)delta.y);
		next_y = ((double)(cy + (step_y > 0 ? 1 : 0)) - (double)start.y) / (double)delta.y;
	}
	double t = 0.0;
	const int64_t full = std::abs(end_x - cx) + std::abs(end_y - cy) + 1;
	for (int64_t v = 0; v < full; v++) {
		if (cx >= 0 && cx < w && cy >= 0 && cy < h && cells[cy * w + cx] != 0) {
			return t;
		}
		if (next_x < next_y) {
			t = next_x;
			next_x += per_x;
			cx += step_x;
		} else {
			t = next_y;
			next_y += per_y;
			cy += step_y;
		}
		if (t > 1.0) {
			return -1.0;
		}
	}
	return -1.0;
}

// `RoomGrid._way_hit` past its checks: the first cell on `from`->`to` that is not 0 in `ground` (with
// `with_ground`) or has a bit of `wall_mask` in `walls` (with `with_walls`), as t in [0, 1], or -1.
inline double way_hit(const uint8_t *walls, const uint8_t *ground, int64_t w, int64_t h, double cell, const Vector2 &origin, const Vector2 &from,
		const Vector2 &to, int64_t wall_mask, bool with_walls, bool with_ground) {
	const Vector2 start = (from - origin) / (real_t)cell;
	const Vector2 delta = (to - from) / (real_t)cell;
	int64_t cx = floori(start.x);
	int64_t cy = floori(start.y);
	const int64_t step_x = delta.x > 0.0f ? 1 : -1;
	const int64_t step_y = delta.y > 0.0f ? 1 : -1;
	double next_x = INFINITY;
	double next_y = INFINITY;
	double per_x = INFINITY;
	double per_y = INFINITY;
	if (delta.x != 0.0f) {
		per_x = std::abs(1.0 / (double)delta.x);
		next_x = ((double)(cx + (step_x > 0 ? 1 : 0)) - (double)start.x) / (double)delta.x;
	}
	if (delta.y != 0.0f) {
		per_y = std::abs(1.0 / (double)delta.y);
		next_y = ((double)(cy + (step_y > 0 ? 1 : 0)) - (double)start.y) / (double)delta.y;
	}
	double t = 0.0;
	const int64_t full = std::abs(floori((double)start.x + (double)delta.x) - cx) + std::abs(floori((double)start.y + (double)delta.y) - cy) + 1;
	for (int64_t v = 0; v < full; v++) {
		if (cx >= 0 && cx < w && cy >= 0 && cy < h) {
			const int64_t at = cy * w + cx;
			if ((with_ground && ground[at] != 0) || (with_walls && (walls[at] & wall_mask) != 0)) {
				return t;
			}
		}
		if (next_x < next_y) {
			t = next_x;
			next_x += per_x;
			cx += step_x;
		} else {
			t = next_y;
			next_y += per_y;
			cy += step_y;
		}
		if (t > 1.0) {
			return -1.0;
		}
	}
	return -1.0;
}

} // namespace grid_ray
