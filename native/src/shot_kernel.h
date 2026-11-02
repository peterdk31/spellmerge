// SPDX-FileCopyrightText: 2026 peterdk31 and Spellmerge contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//
// ShotKernel: the projectile manager's hot loops in native code (native/README.md).
//
// Each method takes the manager (core/projectiles/projectile_manager.gd) and works on its own
// packed arrays in place, for the length of that one call: it reads them with `get`, writes
// through their buffers (shared with the manager's members, never copied) and keeps no reference
// once it returns, so the manager's own writes never copy an array either. Every method does
// exactly what the GDScript it stands for does, to the bit: the manager's GDScript is the
// reference (and the fallback when this library is not built), and
// tests/core/test_native_kernel.gd steps both side by side and compares every array.

#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/rect2.hpp>
#include <godot_cpp/variant/string_name.hpp>

namespace godot {

class ShotKernel : public RefCounted {
	GDCLASS(ShotKernel, RefCounted)

public:
	ShotKernel();

	// The manager's constants this code was written against: true when every one of `constants`
	// (name to value) is what the kernel holds, else false (and the manager falls back to GDScript).
	bool check(const Dictionary &constants) const;
	// Pass 1 of the step (`_pass_common`).
	void pass_common(Object *manager, int64_t top, double delta);
	// Pass 3 of the step (`_pass_hits`), from its `n`-th shot on, as long as a shot needs nothing
	// of GDScript; see the .cpp.
	int64_t hits(Object *manager, int64_t n, int64_t top, int64_t resume, const Rect2 &limit, double delta);
	// The homing pass (`_pass_homing`); the hit pass catches up a shot that waited for its search.
	void homing_pass(Object *manager, int64_t first, int64_t count, double delta);
	// The other behaviour passes that need nothing of GDScript; false for one it doesn't run.
	bool run_pass(Object *manager, int64_t kind, int64_t first, int64_t count, double delta);
	// The trail points of every flying shot at a sample tick (`_sample_trails`, its first loop).
	bool sample_shots(Object *manager, double now);
	// The drawing (`_count_batches`, then `update_draw`'s writing into the buffers the kernel holds).
	void count_draw(Object *manager);
	void draw_shots(Object *manager, double fraction);
	PackedFloat32Array buffer(int64_t batch) const;
	// `threat`: its loop over every shot, the filling of its grid and an ask of the grid.
	double threat_scan(Object *manager, const Vector2 &point, double radius, int64_t team, int64_t own, double horizon);
	int64_t threat_fill(Object *manager, double horizon);
	double threat_query(Object *manager, const Vector2 &point, double radius, int64_t team, int64_t own, double horizon);
	int64_t version() const { return 1; }

protected:
	static void _bind_methods();

private:
	// The draw batches' instance data (BATCH_* of the manager), handed to the MultiMeshes.
	PackedFloat32Array _buffers[5];
};

} // namespace godot
