// SPDX-FileCopyrightText: 2026 peterdk31 and Spellmerge contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Grid lighting (the owner's decision of 2026-11-21; docs/milestones/connected-biomes.md, "Grid
// lighting"): the spell light worked out at each cell of a grid of world cells, on a LightGrid's
// arrays in place (gameplay/feel/light_grid.gd, line by line, to the bit; light_grid.cpp). It keeps
// nothing between calls but the names it reads members by (made once, `check_light_grid`), so each
// grid can be filled on its own thread. View only, so it keeps `std::` maths, as MoteKernel does;
// tests/gameplay/feel/test_light_grid.gd compares it with the GDScript byte for byte.

#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/color.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_string_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>

namespace godot {

class LightKernel : public RefCounted {
	GDCLASS(LightKernel, RefCounted)

protected:
	static void _bind_methods();

public:
	// One line for each member or number of `grid` (a LightGrid) that is not the kernel's.
	PackedStringArray check_light_grid(Object *grid) const;
	// LightGrid's `add_rows`, `add_beam` and `bake` on its arrays in place.
	void light_grid_rows(Object *grid, const PackedFloat32Array &rows, int64_t count, int64_t kind, double reach, double pad, double now, bool blocked, int64_t first_view,
			int64_t views);
	void light_grid_beam(Object *grid, const PackedVector3Array &path, int64_t points, double beam_reach, const Color &colour, int64_t first_view, int64_t views);
	void light_grid_bake(Object *grid);
	// At the module's end (register_types.cpp).
	static void free_names();
};

} // namespace godot
