// SPDX-FileCopyrightText: 2026 peterdk31 and Spellmerge contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//
// The motes' trail births in native code (native/README.md): MoteKernel writes a frame's births
// (core/projectiles' `spark_births`) into the mote ring's rows, as `Motes.give_off` and the
// one-mote `burst` it calls do (gameplay/feel/mote.gd). As the other kernels, each method works on
// the pool's own packed arrays in place for one call, calls no script meanwhile, and does what the
// GDScript does, to the bit; the GDScript stays the reference and the fallback
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
	bool _ready = false;
	int64_t _chunk = 0, _stride = 0, _birth_stride = 0, _settle_stride = 0;
	int64_t _row_vx = 0, _row_born = 0, _row_x = 0, _row_vy = 0, _row_vz = 0, _row_y = 0;
	int64_t _row_source = 0, _row_kind = 0, _row_life = 0, _row_height = 0, _row_core = 0, _row_seed = 0;
	int64_t _spark_x = 0, _spark_y = 0, _spark_back_x = 0, _spark_back_y = 0, _spark_kind = 0;
	int64_t _spark_ramp = 0, _spark_look = 0, _spark_core = 0, _spark_tag = 0, _spark_tag_bits = 0;
	int64_t _spark_streak = 0, _pair_layers = 0;
	int64_t _enemy_source = 0, _exact_source = 0, _look_enemy_ramp = 0, _look_exact = 0;
	double _life_max = 0.0, _height_max = 0.0, _source_code = 0.0, _kind_code = 0.0, _trail_speed = 0.0;
	int64_t _look_layers = 0;
};

} // namespace godot
