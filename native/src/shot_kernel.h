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
// tests/core/test_native_kernel.gd steps both side by side and compares every array. The kernel
// calls no script while it holds the arrays (a script writing one then would get its own copy).

#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/packed_string_array.hpp>
#include <godot_cpp/variant/rect2.hpp>
#include <godot_cpp/variant/string_name.hpp>

#include <vector>

namespace godot {

class ShotKernel : public RefCounted {
	GDCLASS(ShotKernel, RefCounted)

public:
	ShotKernel();
	~ShotKernel();

	// The threads a loop of the kernel runs on (jobs.h): 0 (and at first) the machine's cores less
	// one, 1 without threads (the web). Never changes a result (rule T2): tests compare 1 with several.
	void set_threads(int64_t threads);
	int64_t get_threads() const;

	// The manager's constants this code was written against, against `constants` (name to value:
	// the manager's constant map and a few from other scripts): one line for each the kernel holds
	// that is missing or different (none: they match; else the manager runs its GDScript).
	PackedStringArray check(const Dictionary &constants) const;
	// One line for each member of the manager the kernel reads that is missing or of another type.
	PackedStringArray check_fields(Object *manager) const;
	// At the module's end (register_types.cpp).
	static void free_names();
	// Pass 1 of the step (`_pass_common`).
	void pass_common(Object *manager, int64_t top, double delta);
	// Pass 3 of the step (`_pass_hits`), from its `n`-th shot on, as long as a shot needs nothing
	// of GDScript; see the .cpp.
	int64_t hits(Object *manager, int64_t n, int64_t top, int64_t resume, const Rect2 &limit, double delta, bool merge_first);
	// The behaviour passes that need nothing of GDScript (homing among them: the hit pass catches up
	// a homing shot that waited for its search); false for one it doesn't run.
	bool run_pass(Object *manager, int64_t kind, int64_t first, int64_t count, double delta);
	// The drawing (`_count_batches`, then `update_draw`'s writing into the buffers the kernel holds).
	void count_draw(Object *manager);
	void draw_shots(Object *manager, double fraction);
	PackedFloat32Array buffer(int64_t batch) const;
	// `threat`: its loop over every shot, the filling of its grid and an ask of the grid.
	double threat_scan(Object *manager, const Vector2 &point, double radius, int64_t team, int64_t own, double horizon);
	int64_t threat_fill(Object *manager, double horizon);
	double threat_query(Object *manager, const Vector2 &point, double radius, int64_t team, int64_t own, double horizon);
	// `nearest_target`'s search (sim-native SN3): the row of the nearest target on `layers` whose hit
	// shape overlaps the circle, by distance to its centre, skipping rows `skip` and `skip_also`, the
	// world's and, with a `team`, that team's; -1 for none. The grid must be ready (`_query_ready`).
	int64_t nearest_target(Object *manager, const Vector2 &point, double radius, int64_t layers, int64_t skip, int64_t skip_also, int64_t team);
	// `ProjectileRays.ray_walks`: many beams' rays between their hits, each as `ray_points` walks it
	// (no event), from ray `from` on; returns the first it hands back to GDScript, or `rays`.
	int64_t ray_walks(Object *manager, int64_t from, int64_t rays, const PackedInt32Array &actors, const PackedVector2Array &points, const PackedInt32Array &offsets,
			const PackedInt32Array &counts, const PackedFloat64Array &lengths, const PackedInt32Array &pierces, const PackedFloat64Array &widths,
			const PackedByteArray &ghosts, const PackedInt32Array &skips, int64_t layers, int64_t targets, bool stale, const PackedFloat64Array &got,
			const PackedVector2Array &ends, const PackedVector2Array &headings);
	// `shot_places`: which places hold a shot, from the room grid's whole squares (asks handed back).
	int64_t shot_places(Object *manager, int64_t from);
	// `_pass_trail`: the shots that trail and entered a new floor cell, handed back in `_trail_out`.
	int64_t trail_pass(Object *manager, int64_t top);
	// `_pass_fields`: the shots that came into a field this step, handed back in `_field_out`.
	int64_t field_pass(Object *manager, const PackedInt32Array &fields, int64_t count);
	// The draw regions' hand-out (`DrawRegions`: `_count`, `_write`): each region's rows counted, and
	// each row copied into its region's buffer, by the place its square lies in.
	void region_counts(Object *regions, const PackedFloat32Array &rows, int64_t count);
	void region_rows(Object *regions, const PackedFloat32Array &rows, int64_t count);

protected:
	static void _bind_methods();

private:
	// The threads a loop runs on (jobs.h).
	int _width = 1;
	// The kernel's own memory between calls (the .cpp): the drawing's counts and tail plans.
	struct Scratch;
	Scratch *_scratch = nullptr;

	void homing_pass(Object *manager, int64_t first, int64_t count, double delta);
	// The draw batches' instance data (BATCH_* of the manager, `_batch_total` of them, growing with
	// its card bodies), handed to the MultiMeshes.
	std::vector<PackedFloat32Array> _buffers;
};

} // namespace godot
