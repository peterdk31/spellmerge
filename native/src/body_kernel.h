// SPDX-FileCopyrightText: 2026 peterdk31 and Spellmerge contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//
// BodyKernel (online-ready N6): a body's move against the wall grid and the ground grid (props W4:
// the ground of the bodies that cannot move; a cell is a wall when either is not 0, the wall grid read
// through a mask of the bits the body minds: connected biomes CB2, a mouth), a circle
// sliding along the walls it meets, the same to the bit on every platform. It stands for `WallSlide.gd_slide`
// (core/projectiles/wall_slide.gd); `WallSlide.slide` calls it when the module is loaded, and
// tests/core/test_wall_slide.gd compares the two to the bit. The grid is handed in with each call
// and kept by nothing: a pure function of its arguments. The constants live in the GDScript and are
// handed over once (`configure`).
//
// `walk` (sim-native SN1, docs/milestones/sim-native.md) is a body's whole walk over the room grid in
// one call: `Actor.move`'s grid work, the twin of `RoomGrid.gd_walk_body` (core/projectiles/room_grid.gd),
// which calls `RoomGrid.slide_body`, `is_hole` and `touches_hole` in the order this mirrors.
// tests/core/test_body_walk.gd compares the two to the bit.
//
// `places` (sim-native SN2) is Flow's room life's first pass in one call: every open body's place
// worked out from where its node stands (`RoomGrid.place_at`, mirrored) and set as its `room`, the
// twin of `RoomLife.gd_find_places` (gameplay/flow/room_life.gd); tests/gameplay/flow/test_room_life.gd
// compares the two.

#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_int64_array.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/vector2.hpp>
#include <godot_cpp/variant/rect2.hpp>
#include <godot_cpp/variant/vector3.hpp>

#include <vector>

namespace godot {

class BodyKernel : public RefCounted {
	GDCLASS(BodyKernel, RefCounted)

public:
	// WallSlide's numbers ({"ITERATIONS": ..., "MIN_STRIDE": ...}); false when one is missing.
	bool configure(const Dictionary &config);
	// `WallSlide.gd_slide(cells, ground, w, h, cell, origin, from, motion, radius, mask)`: a cell is a
	// wall where its bits in `mask` are set in `cells` (connected biomes CB2: a wizard's walk minds
	// all but a mouth's), or it is not 0 in `ground`.
	Vector2 slide(const PackedByteArray &cells, const PackedByteArray &ground, int64_t w, int64_t h, double cell, const Vector2 &origin,
			const Vector2 &from, const Vector2 &motion, double radius, int64_t mask) const;
	// `RoomGrid.gd_walk_body(from, motion, crossed, radius, through_mouths, reach)` on the grid's arrays:
	// `walls`, `walk` (holes and ground), `ground` and `holes`, each `w` by `h` cells of `cell` pixels from
	// `origin`; `flags` the grid's (`RoomGrid.WALK_*`: walls laid, footprints laid, holes), `mask` the
	// wall bits the body minds. Where it ends as x and y; z the hole flags at its end
	// (`RoomGrid.WALKED_OVER_HOLE`, `WALKED_NEAR_HOLE`: a circle of `reach` there touches a hole).
	Vector3 walk(const PackedByteArray &walls, const PackedByteArray &walk, const PackedByteArray &ground, const PackedByteArray &holes, int64_t w,
			int64_t h, double cell, const Vector2 &origin, int64_t flags, int64_t mask, const Vector2 &from, const Vector2 &motion,
			const Vector2 &crossed, double radius, double reach) const;

	// `RoomLife.gd_find_places` on the bodies: for each of the first `count` actor ids in `ids`, the body
	// whose instance id `nodes` keeps there; one in the tree that keeps `projectiles` (the manager whose
	// grid this is) has its `room` set to the place it stands in (`RoomGrid.place_at` on
	// the places: `rects`, the PLACE_CELL squares' `cells`, `over`, `mixed`, `touched`, `w` by `h` from
	// `origin`), and `places[n]` is its `room` after; a missing body's is NO_PLACE (-1), and one of another manager is
	// left to GDScript (-2, `RoomLife.ASK_GDSCRIPT`). `places` is the
	// caller's array, sized, written in place.
	// `RoomGrid.wall_hit` on `cells` (the grid has walls; sim-native SN4: the long rays of an AI's sight
	// and line of fire, `RoomGrid` hands over only paths past its fast ones), t in [0, 1] or -1.
	double wall_hit(const PackedByteArray &cells, int64_t w, int64_t h, double cell, const Vector2 &origin, const Vector2 &from, const Vector2 &to) const;
	// `RoomGrid._way_hit` past its checks (an AI's walk: `ground_clear`, `walk_clear`, `clear_run`, sight
	// past a mouth): `ground` the walking or the ground grid, `walls` minded by `wall_mask`.
	double way_hit(const PackedByteArray &walls, const PackedByteArray &ground, int64_t w, int64_t h, double cell, const Vector2 &origin, const Vector2 &from,
			const Vector2 &to, int64_t wall_mask, bool with_walls, bool with_ground) const;
	// False, with nothing written, when the arrays do not fit: the caller runs the GDScript.
	bool places(const PackedInt64Array &nodes, const PackedInt32Array &ids, int64_t count, Object *projectiles, const Array &rects,
			const PackedByteArray &cells, const PackedByteArray &over, const PackedByteArray &mixed, const PackedByteArray &touched, int64_t w,
			int64_t h, double cell, const Vector2 &origin, const PackedInt32Array &places) const;

protected:
	static void _bind_methods();

private:
	bool _ready = false;
	int64_t _iterations = 0;
	double _min_stride = 0.0;
	// `places`' copy of the places' rectangles, kept so a tick allocates nothing (numbers only).
	mutable std::vector<Rect2> _boxes;
};

} // namespace godot
