// SPDX-FileCopyrightText: 2026 peterdk31 and Spellmerge contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//
// The horde swarm's hot loops in native code (native/README.md):
// - SwarmKernel: the spacing and the move onto the floor (gameplay/horde/swarm.gd, `_space` and
//   `_keep_in`);
// - SwarmLookKernel: its batched look's step over the rows and its batch writing
//   (gameplay/horde/swarm_look.gd, `step`'s loop and `draw_rows`).
// As ShotKernel, each method works on the object's own packed arrays in place for one call, calls
// no script meanwhile, and does what the GDScript it stands for does, to the bit; the GDScript stays
// the reference and the fallback. tests/gameplay/horde/test_swarm_steps.gd runs both against its
// recording, test_native_swarm.gd side by side. The numbers the GDScript keeps as constants (the
// swarm's wall cell, Face's and CreatureLook's) are handed over once (`configure`), so they live in
// GDScript only.

#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_string_array.hpp>

namespace godot {

class SwarmKernel : public RefCounted {
	GDCLASS(SwarmKernel, RefCounted)

public:
	SwarmKernel();
	// The swarm's numbers ({"WALL_CELL": ...}); false when one is missing.
	bool configure(const Dictionary &config);
	// One line for each member of `swarm` this kernel or the look's reads that is missing or of
	// another type (none: it matches).
	PackedStringArray check_fields(Object *swarm) const;
	// `Swarm._space()` then `Swarm._keep_in()`.
	void space_and_keep_in(Object *swarm);
	// At the module's end (register_types.cpp).
	static void free_names();

protected:
	static void _bind_methods();

private:
	bool _ready = false;
	double _wall_cell = 0.0;
};

class SwarmLookKernel : public RefCounted {
	GDCLASS(SwarmLookKernel, RefCounted)

public:
	SwarmLookKernel();
	// The look's numbers (`SwarmLook.set_native` hands them over); false when one is missing.
	bool configure(const Dictionary &config);
	// One line for each member of `look` this kernel reads that is missing or of another type.
	PackedStringArray check_fields(Object *look) const;
	// `SwarmLook.step`'s loop over the rows (after `_take_kinds` and `_take_rows`).
	void look_step(Object *look);
	// `SwarmLook.draw_rows` up to the renderer: the rows sorted by kind and every batch's buffer
	// written (the caller hands them over and sets the instance counts).
	void draw_rows(Object *look);

protected:
	static void _bind_methods();

private:
	bool _ready = false;
	double _hop_speed_sq = 0.0, _hop_rate = 0.0, _hop_height = 0.0, _hop_idle = 0.0;
	double _snap_sq = 0.0, _max_lag = 0.0, _lean = 0.0, _idle_after = 0.0, _lag = 0.0;
	double _glance_time = 0.0, _raise_time = 0.0, _flag_flash = 0.0, _flag_hurt = 0.0;
	int64_t _blink_column = 0, _worried = 0, _raised = 0, _stride = 0;
	PackedFloat32Array _blink_every, _blink_time, _glance_every, _raise_every;
};

} // namespace godot
