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

#include <godot_cpp/classes/node2d.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/object.hpp>
#include <godot_cpp/variant/rect2.hpp>
#include <vector>

using namespace godot;

namespace {

// `WallSlide._near`.
bool near(const uint8_t *cells, const uint8_t *ground, uint8_t mask, int64_t w, int64_t h, double cell, double ox, double oy, double lx, double ly,
		double hx, double hy) {
	const int64_t x0 = maxi(floori((lx - ox) / cell), 0);
	const int64_t x1 = mini(floori((hx - ox) / cell), w - 1);
	const int64_t y0 = maxi(floori((ly - oy) / cell), 0);
	const int64_t y1 = mini(floori((hy - oy) / cell), h - 1);
	for (int64_t cy = y0; cy <= y1; cy++) {
		for (int64_t cx = x0; cx <= x1; cx++) {
			if ((cells[cy * w + cx] & mask) != 0 || ground[cy * w + cx] != 0) {
				return true;
			}
		}
	}
	return false;
}

// `WallSlide._open`.
inline bool open(const uint8_t *cells, const uint8_t *ground, uint8_t mask, int64_t w, int64_t h, int64_t cx, int64_t cy) {
	return cx < 0 || cy < 0 || cx >= w || cy >= h || ((cells[cy * w + cx] & mask) == 0 && ground[cy * w + cx] == 0);
}

// WallSlide's sides.
constexpr int64_t NO_EXIT = -1, LEFT = 0, RIGHT = 1, UP = 2, DOWN = 3;

// `WallSlide._exit`.
int64_t exit_side(const uint8_t *cells, const uint8_t *ground, uint8_t mask, int64_t w, int64_t h, int64_t cx, int64_t cy, double left, double right,
		double up, double down) {
	int64_t side = NO_EXIT;
	double best = INFINITY;
	if (open(cells, ground, mask, w, h, cx - 1, cy) && left < best) {
		best = left;
		side = LEFT;
	}
	if (open(cells, ground, mask, w, h, cx + 1, cy) && right < best) {
		best = right;
		side = RIGHT;
	}
	if (open(cells, ground, mask, w, h, cx, cy - 1) && up < best) {
		best = up;
		side = UP;
	}
	if (open(cells, ground, mask, w, h, cx, cy + 1) && down < best) {
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

// `RoomGrid.WALK_*` and `WALKED_*` (checked by tests/core/test_body_walk.gd, which reaches every branch).
constexpr int64_t WALK_WALLS = 1, WALK_FOOTPRINTS = 2, WALK_HOLES = 4;
constexpr int64_t WALKED_OVER_HOLE = 1, WALKED_NEAR_HOLE = 2;

// `RoomGrid.is_hole` (the grid has holes): a point outside the grid is over the void.
bool is_hole(const uint8_t *holes, const uint8_t *walls, int64_t w, int64_t h, double cell, const Vector2 &origin, const Vector2 &point) {
	const int64_t cx = floori(((double)point.x - (double)origin.x) / cell);
	const int64_t cy = floori(((double)point.y - (double)origin.y) / cell);
	if (cx < 0 || cx >= w || cy < 0 || cy >= h) {
		return true;
	}
	const int64_t at = cy * w + cx;
	return holes[at] != 0 && walls[at] == 0;
}

// `RoomGrid.touches_hole` (the grid has holes): the cell's box in single precision, as the GDScript's
// Vector2s, its distance compared in doubles.
bool touches_hole(const uint8_t *holes, const uint8_t *walls, int64_t w, int64_t h, double cell, const Vector2 &origin, const Vector2 &center,
		double radius) {
	const double r = maxf(radius, 0.0);
	const int64_t x0 = maxi(floori(((double)center.x - r - (double)origin.x) / cell), 0);
	const int64_t x1 = mini(floori(((double)center.x + r - (double)origin.x) / cell), w - 1);
	const int64_t y0 = maxi(floori(((double)center.y - r - (double)origin.y) / cell), 0);
	const int64_t y1 = mini(floori(((double)center.y + r - (double)origin.y) / cell), h - 1);
	const Vector2 size((real_t)cell, (real_t)cell);
	for (int64_t cy = y0; cy <= y1; cy++) {
		for (int64_t cx = x0; cx <= x1; cx++) {
			const int64_t at = cy * w + cx;
			if (holes[at] == 0 || walls[at] != 0) {
				continue;
			}
			const Vector2 low = origin + Vector2((real_t)cx, (real_t)cy) * (real_t)cell;
			if ((double)center.distance_squared_to(center.clamp(low, low + size)) < r * r) {
				return true;
			}
		}
	}
	return false;
}

// `RoomGrid.NO_PLACE`, and `RoomLife.ASK_GDSCRIPT` (a body `places` leaves to GDScript).
constexpr int64_t NO_PLACE = -1, ASK_GDSCRIPT = -2;

// `RoomGrid.place_at`, the places' rectangles handed over as `Rect2`s (single precision, as theirs).
int64_t place_at(const std::vector<Rect2> &rects, const uint8_t *cells, const uint8_t *over, const uint8_t *mixed, const uint8_t *touched, int64_t w,
		int64_t h, double cell, const Vector2 &origin, const Vector2 &point) {
	const int64_t n = (int64_t)rects.size();
	if (n == 0) {
		return NO_PLACE;
	}
	const int64_t x = floori(((double)point.x - (double)origin.x) / cell);
	const int64_t y = floori(((double)point.y - (double)origin.y) / cell);
	if (x >= 0 && x < w && y >= 0 && y < h) {
		const int64_t at = y * w + x;
		if (mixed[at] != 0) {
			for (int64_t place = 0; place < n; place++) {
				if (over[place] != 0 && rects[place].has_point(point)) {
					return place;
				}
			}
		}
		const int64_t guess = (int64_t)cells[at] - 1;
		if (guess >= 0 && rects[guess].has_point(point)) {
			return guess;
		}
		if (touched[at] == 0) {
			return NO_PLACE;
		}
	}
	for (int64_t place = 0; place < n; place++) {
		if (over[place] != 0 && rects[place].has_point(point)) {
			return place;
		}
	}
	for (int64_t place = 0; place < n; place++) {
		if (rects[place].has_point(point)) {
			return place;
		}
	}
	return NO_PLACE;
}

} // namespace

bool BodyKernel::configure(const Dictionary &config) {
	_ready = config.has("ITERATIONS") && config.has("MIN_STRIDE");
	if (_ready) {
		_iterations = config["ITERATIONS"];
		_min_stride = config["MIN_STRIDE"];
	}
	return _ready;
}

Vector2 BodyKernel::slide(const PackedByteArray &cells_array, const PackedByteArray &ground_array, int64_t w, int64_t h, double cell,
		const Vector2 &origin, const Vector2 &from, const Vector2 &motion, double radius, int64_t mask_bits) const {
	// The bits of `cells` the body minds (`WallSlide.slide`'s `mask`): a byte, as the GDScript's `&`
	// on a byte of a PackedByteArray.
	const uint8_t mask = (uint8_t)(mask_bits & 0xFF);
	double px = from.x;
	double py = from.y;
	const double mx = motion.x;
	const double my = motion.y;
	const double r = maxf(radius, 0.0);
	const double ox = origin.x;
	const double oy = origin.y;
	ERR_FAIL_COND_V_MSG(!_ready, Vector2(px + mx, py + my), "BodyKernel: configure it first");
	const uint8_t *cells = cells_array.ptr();
	const uint8_t *ground = ground_array.ptr();
	if (cells_array.size() < w * h || ground_array.size() < w * h ||
			!near(cells, ground, mask, w, h, cell, ox, oy, minf(px, px + mx) - r, minf(py, py + my) - r, maxf(px, px + mx) + r,
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
			if (!open(cells, ground, mask, w, h, ix, iy)) {
				const double bx = ox + (double)ix * cell;
				const double by = oy + (double)iy * cell;
				const double left = px - bx;
				const double right = bx + cell - px;
				const double up = py - by;
				const double down = by + cell - py;
				const int64_t side = exit_side(cells, ground, mask, w, h, ix, iy, left, right, up, down);
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
					if ((cells[cy * w + cx] & mask) == 0 && ground[cy * w + cx] == 0) {
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
						const int64_t side = exit_side(cells, ground, mask, w, h, cx, cy, left, right, up, down);
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

Vector3 BodyKernel::walk(const PackedByteArray &walls, const PackedByteArray &walk, const PackedByteArray &ground, const PackedByteArray &holes,
		int64_t w, int64_t h, double cell, const Vector2 &origin, int64_t flags, int64_t mask, const Vector2 &from, const Vector2 &motion,
		const Vector2 &crossed, double radius, double reach) const {
	ERR_FAIL_COND_V_MSG(!_ready, Vector3(from.x, from.y, 0.0), "BodyKernel: configure it first");
	const bool has_holes = (flags & WALK_HOLES) != 0;
	// `RoomGrid.slide_body`: with holes the walk minds them (the walking grid) unless it crosses; with
	// nothing laid, the whole way.
	auto slide_on = [&](const Vector2 &at, const Vector2 &by, bool crossing) -> Vector2 {
		const bool minds_holes = has_holes && !crossing;
		if ((flags & (WALK_WALLS | WALK_FOOTPRINTS)) == 0 && !minds_holes) {
			return at + by;
		}
		return slide(walls, minds_holes ? walk : ground, w, h, cell, origin, at, by, radius, mask);
	};
	if (!has_holes) {
		const Vector2 to = slide_on(from, motion, false);
		return Vector3(to.x, to.y, 0.0);
	}
	ERR_FAIL_COND_V_MSG(holes.size() < w * h || walls.size() < w * h, Vector3(from.x, from.y, 0.0), "BodyKernel.walk: the grids are smaller than w * h");
	const uint8_t *hp = holes.ptr();
	const uint8_t *wp = walls.ptr();
	// Main's `Actor._move_over_holes`, now `RoomGrid.gd_walk_body`: what crosses first, then the walk.
	Vector2 at = from;
	if (crossed != Vector2()) {
		at = slide_on(from, crossed, true);
	}
	const Vector2 step = motion - crossed;
	Vector2 to;
	if (step == Vector2() && crossed != Vector2()) {
		to = at;
	} else if (is_hole(hp, wp, w, h, cell, origin, at)) {
		to = slide_on(at, step, true);
	} else if (crossed != Vector2() && touches_hole(hp, wp, w, h, cell, origin, at, radius)) {
		const Vector2 walked = slide_on(at, step, true);
		to = is_hole(hp, wp, w, h, cell, origin, walked) ? at : walked;
	} else {
		to = slide_on(at, step, false);
	}
	int64_t found = 0;
	if (is_hole(hp, wp, w, h, cell, origin, to)) {
		found = WALKED_OVER_HOLE;
	} else if (touches_hole(hp, wp, w, h, cell, origin, to, reach)) {
		found = WALKED_NEAR_HOLE;
	}
	return Vector3(to.x, to.y, (real_t)found);
}

void BodyKernel::places(const PackedInt64Array &nodes, const PackedInt32Array &ids, int64_t count, int64_t projectiles, const Array &rects,
		const PackedByteArray &cells, const PackedByteArray &over, const PackedByteArray &mixed, const PackedByteArray &touched, int64_t w,
		int64_t h, double cell, const Vector2 &origin, const PackedInt32Array &places) const {
	ERR_FAIL_COND_MSG(count > ids.size() || count > places.size(), "BodyKernel.places: the ids or the places are fewer than count");
	const int64_t n_rects = rects.size();
	ERR_FAIL_COND_MSG(n_rects > 0 && (over.size() < n_rects || cells.size() < w * h || mixed.size() < w * h || touched.size() < w * h),
			"BodyKernel.places: the places' grids are smaller than they say");
	std::vector<Rect2> boxes((size_t)n_rects);
	for (int64_t i = 0; i < n_rects; i++) {
		boxes[(size_t)i] = rects[i];
	}
	static const StringName ROOM("room");
	static const StringName PROJECTILES("projectiles");
	// The caller's array, written through its buffer (native/README.md, "The object's arrays").
	int32_t *out = const_cast<int32_t *>(places.ptr());
	const int32_t *id = ids.ptr();
	for (int64_t n = 0; n < count; n++) {
		const int64_t at = id[n];
		Object *object = (at >= 0 && at < nodes.size() && nodes[at] != 0) ? ObjectDB::get_instance((uint64_t)nodes[at]) : nullptr;
		Node2D *body = Object::cast_to<Node2D>(object);
		const Variant room = body != nullptr ? body->get(ROOM) : Variant();
		if (room.get_type() != Variant::INT) {
			// No body, or none of an actor (`as Actor` is null): no place.
			out[n] = (int32_t)NO_PLACE;
			continue;
		}
		if (!body->is_inside_tree()) {
			out[n] = (int32_t)(int64_t)room;
			continue;
		}
		// `Actor.find_room`: the place it stands in, by its own manager's grid (none without one).
		const Object *own = body->get(PROJECTILES);
		if (own != nullptr && (int64_t)own->get_instance_id() != projectiles) {
			// Another manager's body (a test's world beside the game's): GDScript finds its place.
			out[n] = (int32_t)ASK_GDSCRIPT;
			continue;
		}
		const int64_t place = (own != nullptr && n_rects > 0) ? place_at(boxes, cells.ptr(), over.ptr(), mixed.ptr(), touched.ptr(), w, h, cell, origin, body->get_global_position()) : NO_PLACE;
		if (place != (int64_t)room) {
			body->set(ROOM, place);
		}
		out[n] = (int32_t)place;
	}
}

void BodyKernel::_bind_methods() {
	ClassDB::bind_method(D_METHOD("configure", "config"), &BodyKernel::configure);
	ClassDB::bind_method(D_METHOD("slide", "cells", "ground", "w", "h", "cell", "origin", "from", "motion", "radius", "mask"),
			&BodyKernel::slide);
	ClassDB::bind_method(D_METHOD("walk", "walls", "walk", "ground", "holes", "w", "h", "cell", "origin", "flags", "mask", "from", "motion", "crossed",
								 "radius", "reach"),
			&BodyKernel::walk);
	ClassDB::bind_method(D_METHOD("places", "nodes", "ids", "count", "projectiles", "rects", "cells", "over", "mixed", "touched", "w", "h", "cell", "origin",
								 "places"),
			&BodyKernel::places);
}
