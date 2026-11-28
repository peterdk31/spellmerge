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
//
// And the motes drawn by room (the performance pass, 2026-11-20): `region_rows` copies the rows
// written since the last step into their rooms' chunks, as `MoteRegions._hand` does.

#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_string_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>

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
	// One line for each member of the motes' regions (`MoteRegions`) the hand-out reads that is
	// missing or of another type, and for its numbers when they are not the kernel's.
	PackedStringArray check_regions(Object *regions) const;
	// `MoteRegions._hand(motes, from, count, now)`: the ring's rows from `from` handed to their
	// rooms' chunks (gameplay/feel/mote_regions.gd). Returns how many rows were handed out.
	int64_t region_rows(Object *regions, Object *motes, int64_t from, int64_t count, double now);
	// At the module's end (register_types.cpp).
	static void free_names();

	// Feel's other per-frame loops (the performance pass, 2026-11-28), in feel_loops.cpp: the
	// flashes' rows, the world's stirs and a room's mist parting (see there). On this class, the one
	// Feel's native loops have (core/native/native.gd makes the listed classes alone).
	// The flashes' numbers (`FeelFlashes.set_native`); false when one is missing.
	bool configure_flashes(const Dictionary &config);
	// One line for each member of `flashes` the flash loops read that is missing or of another type.
	PackedStringArray check_flash_fields(Object *flashes) const;
	// `FeelFlashes._find_special(effect_slots)`: returns how many slots it listed in `_flash_special_slots`.
	int64_t find_special(Object *flashes, int64_t effect_slots);
	// `FeelFlashes._write_rows(real_delta, next_flash, effect_slots)`.
	void write_rows(Object *flashes, double real_delta, int64_t next_flash, int64_t effect_slots);
	// The stirs' numbers (`Stirs.set_native`); false when one is missing.
	bool configure_stirs(const Dictionary &config);
	// One line for each member of `stirs` the stir step reads that is missing or of another type.
	PackedStringArray check_stir_fields(Object *stirs) const;
	// `Stirs._read(births, count)` then `Stirs._ease(delta)`, the cells whose shown way changed listed
	// in `_changed` (in the live list's order); returns how many.
	int64_t stir_step(Object *stirs, const PackedFloat32Array &births, int64_t count, double delta);
	// The mist parting's numbers (`MistParting.set_native`); false when one is missing.
	bool configure_parting(const Dictionary &config);
	// One line for each member of `parting` the parting reads that is missing or of another type.
	PackedStringArray check_parting_fields(Object *parting) const;
	// `MistParting.work(delta, feet, count)`, the cells whose parting changed listed in `_changed`
	// (in the live list's order); returns how many.
	int64_t part_work(Object *parting, double delta, const PackedVector2Array &feet, int64_t count);

protected:
	static void _bind_feel_methods();
	static void _make_feel_names();
	static void _free_feel_names();


protected:
	static void _bind_methods();

private:
	bool _ready = false;
	int64_t _chunk = 0, _stride = 0, _birth_stride = 0, _settle_stride = 0;
	int64_t _row_vx = 0, _row_born = 0, _row_x = 0, _row_vy = 0, _row_vz = 0, _row_y = 0;
	int64_t _row_source = 0, _row_kind = 0, _row_life = 0, _row_height = 0, _row_core = 0, _row_seed = 0;
	int64_t _spark_x = 0, _spark_y = 0, _spark_back_x = 0, _spark_back_y = 0, _spark_kind = 0;
	int64_t _spark_ramp = 0, _spark_look = 0, _spark_core = 0, _spark_tag = 0, _spark_tag_bits = 0;
	int64_t _spark_flag_step = 0, _spark_flag_shift = 0;
	int64_t _spark_streak = 0, _pair_layers = 0;
	int64_t _enemy_source = 0, _exact_source = 0, _look_enemy_ramp = 0, _look_exact = 0;
	double _life_max = 0.0, _height_max = 0.0, _source_code = 0.0, _kind_code = 0.0, _trail_speed = 0.0;
	int64_t _look_layers = 0;
	// feel_loops.cpp's numbers.
	bool _flashes_ready = false;
	int64_t _flash_stride = 0, _kind_arc = 0, _kind_status = 0, _kind_shell = 0, _kind_fireball = 0;
	int64_t _table = 0, _table_code = 0;
	double _grid = 0.0, _blast_span = 0.0, _arc_across = 0.0, _arc_margin = 0.0, _from = 0.0, _span = 0.0;
	bool _stirs_ready = false;
	int64_t _field_w = 0, _field_h = 0, _births_read = 0, _stir_birth_stride = 0;
	int64_t _stir_spark_x = 0, _stir_spark_y = 0, _stir_back_x = 0, _stir_back_y = 0;
	bool _parting_ready = false;
	double _reach = 0.0, _reach_down = 0.0, _feet_drop = 0.0, _open_rate = 0.0, _close_rate = 0.0, _closed = 0.0;
	double _cell = 0.0, _pass_push = 0.0, _shown_rate = 0.0, _wake_half = 0.0, _faded = 0.0;
};

} // namespace godot
