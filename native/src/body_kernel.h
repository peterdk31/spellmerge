// SPDX-FileCopyrightText: 2026 peterdk31 and Spellmerge contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//
// BodyKernel (online-ready N6): a body's move against the wall grid, a circle sliding along the
// walls it meets, the same to the bit on every platform. It stands for `WallSlide.slide`
// (core/projectiles/wall_slide.gd), which the projectile manager calls for a body when the module is
// not loaded (`ProjectileManager.slide_body`); tests/core/test_wall_slide.gd compares the two to
// the bit. The grid is handed in with each call and kept by nothing: a pure function of its
// arguments. The constants live in the GDScript and are handed over once (`configure`).

#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/vector2.hpp>

namespace godot {

class BodyKernel : public RefCounted {
	GDCLASS(BodyKernel, RefCounted)

public:
	// WallSlide's numbers ({"ITERATIONS": ..., "MIN_STRIDE": ...}); false when one is missing.
	bool configure(const Dictionary &config);
	// `WallSlide.slide(cells, w, h, cell, origin, from, motion, radius)`.
	Vector2 slide(const PackedByteArray &cells, int64_t w, int64_t h, double cell, const Vector2 &origin,
			const Vector2 &from, const Vector2 &motion, double radius) const;

protected:
	static void _bind_methods();

private:
	bool _ready = false;
	int64_t _iterations = 0;
	double _min_stride = 0.0;
};

} // namespace godot
