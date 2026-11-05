// SPDX-FileCopyrightText: 2026 peterdk31 and Spellmerge contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//
// The motes' trail births in native code (native/README.md): MoteKernel writes a frame's births
// (core/projectiles' `spark_births`) into the mote pool's SINGLES ring (S4, a burst a row: each
// birth a one-mote row), as `Motes.give_off` and the `_write` it calls do (gameplay/feel/mote.gd).
// As the other kernels, each method works on the pool's own packed arrays in place for one call,
// calls no script meanwhile, and does what the GDScript does, to the bit; the GDScript stays the
// reference and the fallback
// (tests/gameplay/feel/test_native_motes.gd runs both side by side).
//
// Two calls a frame: `key_births` names each birth's (spell tag, look kind) pair and lists the
// pairs once, so GDScript looks up the kinds of each pair once (`card_kinds.gd`, a script); then
// `give_off` picks a kind for each birth and writes its row. The settling motes' marks are handed
// back in a list (`_settle_out`), since the mark layer is a script.

#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_string_array.hpp>

namespace godot {

class MoteKernel : public RefCounted {
	GDCLASS(MoteKernel, RefCounted)

public:
	MoteKernel();
	// The pool's numbers (`Motes.native_config()`); false when one is missing.
	bool configure(const Dictionary &config);
	// One line for each member of `motes` this kernel reads that is missing or of another type.
	PackedStringArray check_fields(Object *motes) const;
	// The first `count` births of `given`: each one's pair in `_birth_pair`, and the pairs, once
	// each, in `_pair_key` (tag * PAIR_LAYERS + the kind + 1; the streak's kind is -1). Returns
	// how many pairs.
	int64_t key_births(Object *motes, const PackedFloat32Array &given, int64_t count);
	// `Motes.give_off(given, count)`, with the kinds of pair p at `_pair_kinds[_pair_from[p]]`, of
	// `_pair_size[p]`. Returns how many settles it handed back in `_settle_out`.
	int64_t give_off(Object *motes, const PackedFloat32Array &given, int64_t count, bool has_marks);
	// At the module's end (register_types.cpp).
	static void free_names();

protected:
	static void _bind_methods();

private:
	// `Motes.mote_hash` and `Motes._land` (see give_off).
	static int64_t _hash(int64_t x);
	bool _land(const float *o, int64_t kk, int64_t q, double gravity, double bounce, double drag, double wobble,
			double wobble_rate, float &x, float &y, float &z) const;

	bool _ready = false;
	int64_t _stride = 0, _birth_stride = 0, _settle_stride = 0, _singles = 0, _serial_bits = 0;
	int64_t _row_aim = 0, _row_born = 0, _row_seed = 0, _row_x = 0, _row_speed = 0, _row_up = 0, _row_life = 0, _row_y = 0;
	int64_t _row_source = 0, _row_kind = 0, _row_count = 0, _row_height = 0, _row_core = 0;
	int64_t _pack_half = 0, _pack_speed = 0, _pack_up = 0, _pack_life = 0, _pack_longest = 0, _pack_size = 0;
	int64_t _spark_x = 0, _spark_y = 0, _spark_back_x = 0, _spark_back_y = 0, _spark_kind = 0;
	int64_t _spark_ramp = 0, _spark_look = 0, _spark_core = 0, _spark_tag = 0, _spark_tag_bits = 0;
	int64_t _spark_streak = 0, _pair_layers = 0;
	int64_t _enemy_source = 0, _exact_source = 0, _look_enemy_ramp = 0, _look_exact = 0;
	double _height_max = 0.0, _source_code = 0.0, _kind_code = 0.0;
	double _aim_step = 0.0, _half_step = 0.0, _speed_step = 0.0, _up_low = 0.0, _life_step = 0.0;
};

} // namespace godot
