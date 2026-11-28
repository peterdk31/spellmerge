// SPDX-FileCopyrightText: 2026 peterdk31 and Spellmerge contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//
// SparkRoll: the particles the drawn shots give off each frame, rolled as births (the projectile
// manager's `spark_births`), in native code (the performance pass, 2026-11-28). It stands for
// `ProjectileDraw._give_off_sparks` and `_give_off_spark` (core/projectiles/projectile_draw.gd),
// which stay the reference and the fallback: the same births, in the same order, from the same
// dice. The dice are the manager's `RandomNumberGenerator` (`_spark_rng`): its state is handed in
// and the state after is read back (`state`), and its rolls (`randf`, `randi_range`) are the
// engine's PCG32, written here as the engine writes them. A pure function of its arguments: the
// arrays are handed in with each call (the births written in place, through the caller's buffer)
// and kept by nothing. The constants live in the GDScript and are handed over once (`configure`).
//
// The shot kernel holds one and binds it (`ShotKernel.spark_configure`, `give_off_sparks`,
// `spark_state`). tests/core/test_spark_roll.gd compares it with the GDScript to the bit.

#pragma once

#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>

#include <cstdint>

namespace godot {

class SparkRoll {
public:
	// The manager's numbers (`ProjectileDraw.spark_config`); false, and nothing rolls, when one is missing.
	bool configure(const Dictionary &config);
	// `_give_off_sparks` past its moments: `arrays` the manager's arrays in the order of
	// `ProjectileDraw.SPARK_ARRAYS`, `births` the frame's births with `count` taken, `state` the
	// dice's state. Returns the births taken after; the dice's state after is `state()`.
	int64_t give_off(const Array &arrays, const PackedFloat32Array &births, int64_t count, int64_t state, int64_t moments, double fraction,
			double span, double sim_time, int64_t live);
	int64_t state() const { return (int64_t)_state; }

private:
	bool _ready = false;
	uint64_t _state = 0;
	PackedFloat32Array _rates;
	int64_t _emitting_mask = 0;
	int64_t _f_quad = 0;
	int64_t _motion_orbit = 0;
	double _orbit_grow = 1.0;
	int64_t _births_max = 0;
	int64_t _tries_most = 0;
	int64_t _stride = 0;
	int64_t _x = 0, _y = 0, _back_x = 0, _back_y = 0, _kind = 0, _ramp = 0, _look = 0, _core = 0, _tag = 0;
	int64_t _tag_bits = 0, _flag_step = 0, _flag_shift = 0, _layer_mask = 0;
};

} // namespace godot
