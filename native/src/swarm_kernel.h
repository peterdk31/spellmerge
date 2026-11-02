// SPDX-FileCopyrightText: 2026 peterdk31 and Spellmerge contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//
// SwarmKernel: the horde swarm's hot loops in native code (native/README.md): the spacing and the
// move onto the floor (gameplay/horde/swarm.gd, `_space` and `_keep_in`), and its batched look's
// step and batch writing (gameplay/horde/swarm_look.gd, `step`'s loop over the rows and
// `draw_rows`). As ShotKernel, each method works on the object's own packed arrays in place for
// one call and does what the GDScript it stands for does, to the bit; the GDScript stays the
// reference and the fallback. tests/gameplay/horde/test_swarm_steps.gd runs both against its
// recording, test_native_swarm.gd side by side. The numbers the GDScript keeps as constants
// (Face's, CreatureLook's) are handed over once (`configure`), so they live in one place.

#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>

namespace godot {

class SwarmKernel : public RefCounted {
	GDCLASS(SwarmKernel, RefCounted)

public:
	// The GDScript's constants: the swarm's (`WALL_CELL`) or the look's (`SwarmLook._native_config`);
	// false when one the look needs is missing.
	bool configure(const Dictionary &config);
	// `Swarm._space()` then `Swarm._keep_in()`.
	void space_and_keep_in(Object *swarm);
	// `SwarmLook.step`'s loop over the rows (after `_take_kinds` and `_take_rows`).
	void look_step(Object *look, double delta);
	// `SwarmLook.draw_rows` up to the renderer: the rows sorted by kind and every batch's buffer
	// written (the caller hands them over and sets the instance counts).
	void draw_rows(Object *look);

protected:
	static void _bind_methods();

private:
	bool _swarm_ready = false;
	bool _look_ready = false;
	double _wall_cell = 8.0;
	double _hop_speed_sq = 0.0, _hop_rate = 0.0, _hop_height = 0.0, _hop_idle = 0.0;
	double _snap_sq = 0.0, _max_lag = 0.0, _lean = 0.0, _idle_after = 0.0, _lag = 0.0;
	double _glance_time = 0.0, _raise_time = 0.0, _flag_flash = 0.0, _flag_hurt = 0.0;
	int64_t _blink_column = 0, _worried = 0, _raised = 0, _stride = 16;
	PackedFloat32Array _blink_every, _blink_time, _glance_every, _raise_every;
};

} // namespace godot
