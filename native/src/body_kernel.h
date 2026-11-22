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

#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/vector2.hpp>
#include <godot_cpp/variant/vector3.hpp>

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

protected:
	static void _bind_methods();

private:
	bool _ready = false;
	int64_t _iterations = 0;
	double _min_stride = 0.0;
};

} // namespace godot
