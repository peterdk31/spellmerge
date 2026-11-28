// SPDX-FileCopyrightText: 2026 peterdk31 and Spellmerge contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Feel's other per-frame loops in native code (native/README.md; the performance pass, 2026-11-28),
// as methods of MoteKernel (mote_kernel.h). Each does what its GDScript does, to the bit, on the
// arrays of the object it is handed, in place, for one call, calling no script meanwhile; the
// GDScript stays the reference and the fallback (tests/gameplay/feel/test_native_feel.gd runs both
// side by side). See shot_kernel.cpp for how the numbers are kept to the bit (a GDScript `float` is
// a double; Vector2, Color and PackedFloat32Array single precision).
//
// - The flashes (gameplay/feel/feel_flashes.gd): `find_special` lists the live slots whose flashes
//   move or end by what the game says (`FeelFlashes._find_special`; GDScript then steps those,
//   asking the game), and `write_rows` ages every other live slot and writes every live slot's row
//   into its batch (`FeelFlashes._write_rows`).
// - The world's stirs (gameplay/feel/stirs.gd): `stir_step` reads a frame's shot births into the
//   wake and eases every live cell (`Stirs._read`, `Stirs._ease`), and lists the cells whose picture
//   changed, for GDScript to write into the stirs' image (an Image is no class of the module's).
// - A room's mist parted round the bodies' feet (gameplay/feel/mist_parting.gd): `part_work` is
//   `MistParting.work`, the cells whose picture changed listed for GDScript to write in the same way.
//   It may run on a worker thread (Feel's own, feel_jobs.gd), one grid a thread.

#include "mote_kernel.h"
#include "packed.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_color_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/vector2i.hpp>

#include <cmath>

using namespace godot;

namespace {

// The members the flash loops read and write: C++ name, GDScript member, type (one list, so
// `check_flash_fields` sees every name it uses).
#define FLASH_FIELDS(X) \
	X(flash_buffer, "_flash_buffer", PACKED_FLOAT32_ARRAY) \
	X(arc_buffer, "_arc_buffer", PACKED_FLOAT32_ARRAY) \
	X(status_buffer, "_status_buffer", PACKED_FLOAT32_ARRAY) \
	X(floor_buffer, "_floor_buffer", PACKED_FLOAT32_ARRAY) \
	X(blast_buffer, "_blast_buffer", PACKED_FLOAT32_ARRAY) \
	X(kind, "_flash_kind", PACKED_INT32_ARRAY) \
	X(at, "_flash_at", PACKED_VECTOR2_ARRAY) \
	X(dir, "_flash_dir", PACKED_VECTOR2_ARRAY) \
	X(core, "_flash_core", PACKED_COLOR_ARRAY) \
	X(zoom, "_flash_zoom", PACKED_INT32_ARRAY) \
	X(age, "_flash_age", PACKED_FLOAT32_ARRAY) \
	X(seconds, "_flash_seconds", PACKED_FLOAT32_ARRAY) \
	X(length, "_flash_length", PACKED_FLOAT32_ARRAY) \
	X(light, "_flash_light", PACKED_FLOAT32_ARRAY) \
	X(floor, "_flash_floor", PACKED_BYTE_ARRAY) \
	X(table_floor, "_table_floor", PACKED_BYTE_ARRAY) \
	X(look_color, "_flash_look_color", PACKED_COLOR_ARRAY) \
	X(special, "_flash_special", PACKED_BYTE_ARRAY) \
	X(aged, "_flash_aged", PACKED_BYTE_ARRAY) \
	X(special_out, "_flash_special_slots", PACKED_INT32_ARRAY) \
	X(row_counts, "_flash_row_counts", PACKED_INT32_ARRAY)

struct FlashNames {
#define FK_DECLARE(id, gd, type) StringName id;
	FLASH_FIELDS(FK_DECLARE)
#undef FK_DECLARE
	FlashNames() {
#define FK_INIT(id, gd, type) id = StringName(gd);
		FLASH_FIELDS(FK_INIT)
#undef FK_INIT
	}
};

FlashNames *flash_names = nullptr;

// The members the stir step reads and writes (`check_stir_fields` sees every one).
#define STIR_FIELDS(X) \
	X(wake, "_wake", PACKED_VECTOR2_ARRAY) \
	X(shown, "_shown", PACKED_VECTOR2_ARRAY) \
	X(live, "_live", PACKED_INT32_ARRAY) \
	X(is_live, "_is_live", PACKED_BYTE_ARRAY) \
	X(point_at, "_point_at", PACKED_VECTOR2_ARRAY) \
	X(point_way, "_point_way", PACKED_VECTOR2_ARRAY) \
	X(point_next, "_point_next", PACKED_INT32_ARRAY) \
	X(point_cell, "_point_cell", PACKED_INT32_ARRAY) \
	X(cell_first, "_cell_first", PACKED_INT32_ARRAY) \
	X(changed, "_changed", PACKED_INT32_ARRAY) \
	X(corner, "_corner", VECTOR2I) \
	X(points, "_points", INT) \
	X(live_count, "_live_count", INT) \
	X(read, "read", INT)

struct StirNames {
#define SK_DECLARE(id, gd, type) StringName id;
	STIR_FIELDS(SK_DECLARE)
#undef SK_DECLARE
	StirNames() {
#define SK_INIT(id, gd, type) id = StringName(gd);
		STIR_FIELDS(SK_INIT)
#undef SK_INIT
	}
};

StirNames *stir_names = nullptr;

const StirNames &sn() {
	if (stir_names == nullptr) {
		stir_names = new StirNames();
	}
	return *stir_names;
}

const FlashNames &fn() {
	if (flash_names == nullptr) {
		flash_names = new FlashNames();
	}
	return *flash_names;
}

// The members the mist parting reads and writes (`check_parting_fields` sees every one).
#define PARTING_FIELDS(X) \
	X(wanted, "_wanted", PACKED_FLOAT32_ARRAY) \
	X(shown, "_shown", PACKED_FLOAT32_ARRAY) \
	X(live, "_live", PACKED_INT32_ARRAY) \
	X(is_live, "_is_live", PACKED_BYTE_ARRAY) \
	X(changed, "_changed", PACKED_INT32_ARRAY) \
	X(live_count, "_live_count", INT) \
	X(width, "width", INT) \
	X(height, "height", INT) \
	X(cell, "cell", FLOAT) \
	X(origin, "origin", VECTOR2)

struct PartingNames {
#define PK_DECLARE(id, gd, type) StringName id;
	PARTING_FIELDS(PK_DECLARE)
#undef PK_DECLARE
	PartingNames() {
#define PK_INIT(id, gd, type) id = StringName(gd);
		PARTING_FIELDS(PK_INIT)
#undef PK_INIT
	}
};

PartingNames *parting_names = nullptr;

const PartingNames &pn() {
	if (parting_names == nullptr) {
		parting_names = new PartingNames();
	}
	return *parting_names;
}

bool take(const Dictionary &config, const char *key, double &out) {
	if (!config.has(key)) {
		return false;
	}
	out = config[key];
	return true;
}

bool take_int(const Dictionary &config, const char *key, int64_t &out) {
	if (!config.has(key)) {
		return false;
	}
	out = config[key];
	return true;
}

} // namespace

// Made on the main thread with the kernel (its constructor), so no thread makes them later.
void MoteKernel::_make_feel_names() {
	fn();
	sn();
	pn();
}

void MoteKernel::_free_feel_names() {
	delete flash_names;
	flash_names = nullptr;
	delete stir_names;
	stir_names = nullptr;
	delete parting_names;
	parting_names = nullptr;
}

bool MoteKernel::configure_flashes(const Dictionary &c) {
	_flashes_ready = take_int(c, "FLASH_STRIDE", _flash_stride) && take(c, "FLASH_GRID", _grid) &&
			take(c, "BLAST_SPAN", _blast_span) && take(c, "ARC_ACROSS", _arc_across) &&
			take(c, "ARC_MARGIN", _arc_margin) && take(c, "FLASH_FROM", _from) && take(c, "FLASH_SPAN", _span) &&
			take_int(c, "KIND_ARC", _kind_arc) && take_int(c, "KIND_STATUS", _kind_status) &&
			take_int(c, "KIND_SHELL", _kind_shell) && take_int(c, "KIND_FIREBALL", _kind_fireball) &&
			take_int(c, "FLASH_TABLE", _table) && take_int(c, "FLASH_TABLE_CODE", _table_code) && _flash_stride >= 16;
	return _flashes_ready;
}

PackedStringArray MoteKernel::check_flash_fields(Object *object) const {
	PackedStringArray wrong;
	ERR_FAIL_NULL_V(object, wrong);
	const FlashNames &k = fn();
#define FK_CHECK(id, gd, type)                                             \
	if (object->get(k.id).get_type() != Variant::type) {                   \
		wrong.push_back(String("member ") + gd + " missing or not " #type); \
	}
	FLASH_FIELDS(FK_CHECK)
#undef FK_CHECK
	return wrong;
}

int64_t MoteKernel::find_special(Object *object, int64_t effect_slots) {
	ERR_FAIL_NULL_V(object, 0);
	const FlashNames &k = fn();
	Arr<PackedByteArray> special;
	special.load(object, k.special);
	Arr<PackedFloat32Array> seconds;
	seconds.load(object, k.seconds);
	Arr<PackedInt32Array> out;
	out.load(object, k.special_out);
	const int64_t slots = mini(mini(effect_slots, special.n), mini(seconds.n, out.n));
	int64_t found = 0;
	for (int64_t slot = 0; slot < slots; slot++) {
		if (special[slot] != 0 && seconds[slot] > 0.0f) {
			out[found] = (int32_t)slot;
			found++;
		}
	}
	return found;
}

void MoteKernel::write_rows(Object *object, double real_delta, int64_t next_flash, int64_t effect_slots) {
	ERR_FAIL_NULL(object);
	ERR_FAIL_COND(!_flashes_ready);
	const FlashNames &k = fn();
	Arr<PackedFloat32Array> flash_buffer, arc_buffer, status_buffer, floor_buffer, blast_buffer;
	flash_buffer.load(object, k.flash_buffer);
	arc_buffer.load(object, k.arc_buffer);
	status_buffer.load(object, k.status_buffer);
	floor_buffer.load(object, k.floor_buffer);
	blast_buffer.load(object, k.blast_buffer);
	Arr<PackedInt32Array> kinds, zooms, counts;
	kinds.load(object, k.kind);
	zooms.load(object, k.zoom);
	counts.load(object, k.row_counts);
	Arr<PackedVector2Array> ats, dirs;
	ats.load(object, k.at);
	dirs.load(object, k.dir);
	Arr<PackedColorArray> cores, looks;
	cores.load(object, k.core);
	looks.load(object, k.look_color);
	Arr<PackedFloat32Array> ages, seconds, lengths, lights;
	ages.load(object, k.age);
	seconds.load(object, k.seconds);
	lengths.load(object, k.length);
	lights.load(object, k.light);
	Arr<PackedByteArray> floors_of, table_floor, aged;
	floors_of.load(object, k.floor);
	table_floor.load(object, k.table_floor);
	aged.load(object, k.aged);
	ERR_FAIL_COND(counts.n < 5 || effect_slots <= 0);
	const int64_t slots = effect_slots;
	// Every per-slot array holds the slots, and every batch a row a slot (as `_size_flashes` sizes them).
	ERR_FAIL_COND(kinds.n < slots || zooms.n < slots || ats.n < slots || dirs.n < slots || cores.n < slots ||
			looks.n < slots || ages.n < slots || seconds.n < slots || lengths.n < slots || lights.n < slots ||
			floors_of.n < slots || aged.n < slots);
	const int64_t room = slots * _flash_stride;
	ERR_FAIL_COND(flash_buffer.n < room || arc_buffer.n < room || status_buffer.n < room || floor_buffer.n < room ||
			blast_buffer.n < room);
	int64_t out = 0, arcs = 0, floors = 0, blasts = 0, statuses = 0;
	for (int64_t n = 0; n < slots; n++) {
		const int64_t slot = (next_flash + n) % slots;
		if (seconds[slot] <= 0.0f) {
			continue;
		}
		if (aged[slot] != 0) {
			aged[slot] = 0;
		} else {
			ages[slot] = (float)((double)ages[slot] + real_delta);
			if ((double)ages[slot] / (double)seconds[slot] >= 1.0) {
				seconds[slot] = 0.0f;
				continue;
			}
		}
		const double through = (double)ages[slot] / (double)seconds[slot];
		const int64_t kind = kinds[slot];
		const bool blast = kind == _kind_shell || kind == _kind_fireball;
		const int64_t row = kind >= _table ? kind - _table : 0;
		const int64_t code = kind >= _table ? _table_code : (blast ? kind - _kind_shell : kind);
		float *buffer = flash_buffer.p;
		int64_t i = out * _flash_stride;
		if (kind == _kind_arc) {
			buffer = arc_buffer.p;
			i = arcs * _flash_stride;
			arcs++;
		} else if (kind == _kind_status) {
			buffer = status_buffer.p;
			i = statuses * _flash_stride;
			statuses++;
		} else if (blast) {
			buffer = blast_buffer.p;
			i = blasts * _flash_stride;
			blasts++;
		} else if ((row >= 0 && row < table_floor.n && table_floor[row] != 0) || floors_of[slot] != 0) {
			buffer = floor_buffer.p;
			i = floors * _flash_stride;
			floors++;
		} else {
			out++;
		}
		double d = _grid * (double)zooms[slot];
		double along = d;
		const Vector2 dir = dirs[slot];
		Vector2 at = ats[slot];
		if (blast) {
			d = (double)zooms[slot] * 4.0 * _blast_span;
			along = d;
		}
		if (lengths[slot] > 0.0f) {
			d = _arc_across;
			along = (double)lengths[slot] + 2.0 * _arc_margin;
			at += vmul(vmul(dir, (double)lengths[slot]), 0.5);
		}
		buffer[i] = (float)((double)dir.x * along);
		buffer[i + 1] = (float)((double)dir.y * d);
		buffer[i + 2] = (float)(double)row;
		buffer[i + 3] = at.x;
		buffer[i + 4] = (float)((double)dir.y * along);
		buffer[i + 5] = (float)(-(double)dir.x * d);
		buffer[i + 6] = lights[slot];
		buffer[i + 7] = at.y;
		const Color data = looks[slot];
		buffer[i + 8] = data.r;
		buffer[i + 9] = data.g;
		buffer[i + 10] = data.b;
		buffer[i + 11] = data.a;
		const Color core = cores[slot];
		buffer[i + 12] = core.r;
		buffer[i + 13] = core.g;
		buffer[i + 14] = core.b;
		buffer[i + 15] = (float)(1.0 - ((double)code + _from + _span * through) / 16.0);
	}
	counts[0] = (int32_t)out;
	counts[1] = (int32_t)arcs;
	counts[2] = (int32_t)statuses;
	counts[3] = (int32_t)floors;
	counts[4] = (int32_t)blasts;
}

bool MoteKernel::configure_stirs(const Dictionary &c) {
	_stirs_ready = take_int(c, "FIELD_W", _field_w) && take_int(c, "FIELD_H", _field_h) &&
			take_int(c, "BIRTHS_READ", _births_read) && take(c, "CELL", _cell) && take(c, "PASS_PUSH", _pass_push) &&
			take(c, "SHOWN_RATE", _shown_rate) && take(c, "WAKE_HALF", _wake_half) && take(c, "FADED", _faded) &&
			take_int(c, "SPARK_BIRTH_STRIDE", _stir_birth_stride) && take_int(c, "SPARK_X", _stir_spark_x) &&
			take_int(c, "SPARK_Y", _stir_spark_y) && take_int(c, "SPARK_BACK_X", _stir_back_x) &&
			take_int(c, "SPARK_BACK_Y", _stir_back_y) && _field_w > 0 && _field_h > 0 && _stir_birth_stride > 0 &&
			_cell > 0.0;
	return _stirs_ready;
}

PackedStringArray MoteKernel::check_stir_fields(Object *object) const {
	PackedStringArray wrong;
	ERR_FAIL_NULL_V(object, wrong);
	const StirNames &k = sn();
#define SK_CHECK(id, gd, type)                                             \
	if (object->get(k.id).get_type() != Variant::type) {                   \
		wrong.push_back(String("member ") + gd + " missing or not " #type); \
	}
	STIR_FIELDS(SK_CHECK)
#undef SK_CHECK
	return wrong;
}

int64_t MoteKernel::stir_step(Object *object, const PackedFloat32Array &births, int64_t count, double delta) {
	ERR_FAIL_NULL_V(object, 0);
	ERR_FAIL_COND_V(!_stirs_ready, 0);
	const StirNames &k = sn();
	Arr<PackedVector2Array> wake, shown, point_at, point_way;
	wake.load(object, k.wake);
	shown.load(object, k.shown);
	point_at.load(object, k.point_at);
	point_way.load(object, k.point_way);
	Arr<PackedInt32Array> live, point_next, point_cell, cell_first, changed;
	live.load(object, k.live);
	point_next.load(object, k.point_next);
	point_cell.load(object, k.point_cell);
	cell_first.load(object, k.cell_first);
	changed.load(object, k.changed);
	Arr<PackedByteArray> is_live;
	is_live.load(object, k.is_live);
	const int64_t cells = _field_w * _field_h;
	ERR_FAIL_COND_V(wake.n < cells || shown.n < cells || live.n < cells || is_live.n < cells || cell_first.n < cells ||
			changed.n < cells || point_at.n < _births_read || point_way.n < _births_read ||
			point_next.n < _births_read || point_cell.n < _births_read, 0);
	const Vector2i corner = object->get(k.corner);
	int64_t points = object->get(k.points);
	int64_t live_count = object->get(k.live_count);
	ERR_FAIL_COND_V(points < 0 || points > _births_read || live_count < 0 || live_count > cells, 0);

	// `_read`: the births drag the wake, filed by cell.
	for (int64_t n = 0; n < points; n++) {
		cell_first[point_cell[n]] = -1;
	}
	points = 0;
	count = mini(count, births.size() / _stir_birth_stride);
	const float *given = births.ptr();
	const int64_t stride = maxi(ceili((double)count / (double)_births_read), 1);
	const double push = _pass_push * (double)stride;
	int64_t n = 0;
	while (n < count) {
		const int64_t i = n * _stir_birth_stride;
		n += stride;
		Vector2 way(-given[i + _stir_back_x], -given[i + _stir_back_y]);
		if ((double)way.length_squared() < 0.25) {
			continue;
		}
		const Vector2 at(given[i + _stir_spark_x], given[i + _stir_spark_y]);
		const int64_t x = floori((double)at.x / _cell) - corner.x;
		const int64_t y = floori((double)at.y / _cell) - corner.y;
		if (x < 0 || x >= _field_w || y < 0 || y >= _field_h) {
			continue;
		}
		const int64_t cell = y * _field_w + x;
		way = way.normalized();
		wake[cell] = (wake[cell] + vmul(way, push)).limit_length(1.0);
		if (is_live[cell] == 0) {
			is_live[cell] = 1;
			live[live_count] = (int32_t)cell;
			live_count++;
		}
		point_at[points] = at;
		point_way[points] = way;
		point_next[points] = cell_first[cell];
		point_cell[points] = (int32_t)cell;
		cell_first[cell] = (int32_t)points;
		points++;
		if (points >= _births_read) {
			break;
		}
	}
	object->set(k.points, points);
	object->set(k.read, points);

	// `_ease`: every live cell's drag dying away and what it shows following it.
	int64_t found = 0;
	if (live_count > 0) {
		const double fade = std::pow(0.5, delta / _wake_half);
		const double most = _shown_rate * delta;
		const double faded_sq = _faded * _faded;
		int64_t kept = 0;
		for (int64_t m = 0; m < live_count; m++) {
			const int64_t cell = live[m];
			Vector2 now_shown = shown[cell].move_toward(wake[cell], (real_t)most);
			Vector2 now_wake = vmul(wake[cell], fade);
			if ((double)now_wake.length_squared() < faded_sq && (double)now_shown.length_squared() < faded_sq) {
				now_wake = Vector2();
				now_shown = Vector2();
				is_live[cell] = 0;
			} else {
				live[kept] = (int32_t)cell;
				kept++;
			}
			wake[cell] = now_wake;
			if (now_shown != shown[cell]) {
				shown[cell] = now_shown;
				changed[found] = (int32_t)cell;
				found++;
			}
		}
		live_count = kept;
	}
	object->set(k.live_count, live_count);
	return found;
}

bool MoteKernel::configure_parting(const Dictionary &c) {
	_parting_ready = take(c, "REACH", _reach) && take(c, "REACH_DOWN", _reach_down) && take(c, "FEET_DROP", _feet_drop) &&
			take(c, "OPEN_RATE", _open_rate) && take(c, "CLOSE_RATE", _close_rate) && take(c, "CLOSED", _closed) &&
			_reach > 0.0 && _reach_down > 0.0;
	return _parting_ready;
}

PackedStringArray MoteKernel::check_parting_fields(Object *object) const {
	PackedStringArray wrong;
	ERR_FAIL_NULL_V(object, wrong);
	const PartingNames &k = pn();
#define PK_CHECK(id, gd, type)                                             \
	if (object->get(k.id).get_type() != Variant::type) {                   \
		wrong.push_back(String("member ") + gd + " missing or not " #type); \
	}
	PARTING_FIELDS(PK_CHECK)
#undef PK_CHECK
	return wrong;
}

int64_t MoteKernel::part_work(Object *object, double delta, const PackedVector2Array &feet, int64_t count) {
	ERR_FAIL_NULL_V(object, 0);
	ERR_FAIL_COND_V(!_parting_ready, 0);
	const PartingNames &k = pn();
	Arr<PackedFloat32Array> wanted, shown;
	wanted.load(object, k.wanted);
	shown.load(object, k.shown);
	Arr<PackedInt32Array> live, changed;
	live.load(object, k.live);
	changed.load(object, k.changed);
	Arr<PackedByteArray> is_live;
	is_live.load(object, k.is_live);
	const int64_t width = object->get(k.width);
	const int64_t height = object->get(k.height);
	const double cell = object->get(k.cell);
	const Vector2 origin = object->get(k.origin);
	int64_t live_count = object->get(k.live_count);
	const int64_t cells = width * height;
	ERR_FAIL_COND_V(width <= 0 || height <= 0 || cell <= 0.0 || wanted.n < cells || shown.n < cells || live.n < cells ||
			is_live.n < cells || changed.n < cells || live_count < 0 || live_count > cells, 0);
	delta = clampf(delta, 0.0, 0.25);
	for (int64_t n = 0; n < live_count; n++) {
		wanted[live[n]] = 0.0f;
	}
	const Vector2 *given = feet.ptr();
	const int64_t feet_count = mini(count, feet.size());
	for (int64_t f = 0; f < feet_count; f++) {
		// `_part`: every cell within REACH of the foot wants to be parted as much as it is near.
		const Vector2 foot = given[f] + Vector2(0.0f, (real_t)_feet_drop) - origin;
		if (!foot.is_finite()) {
			continue;
		}
		const int64_t x0 = maxi(floori(((double)foot.x - _reach) / cell), 0);
		const int64_t x1 = mini(floori(((double)foot.x + _reach) / cell), width - 1);
		const int64_t y0 = maxi(floori(((double)foot.y - _reach_down) / cell), 0);
		const int64_t y1 = mini(floori(((double)foot.y + _reach_down) / cell), height - 1);
		for (int64_t y = y0; y <= y1; y++) {
			for (int64_t x = x0; x <= x1; x++) {
				const Vector2 off((real_t)(((double)x + 0.5) * cell - (double)foot.x),
						(real_t)((((double)y + 0.5) * cell - (double)foot.y) * _reach / _reach_down));
				double near = 1.0 - (double)off.length() / _reach;
				if (near <= 0.0) {
					continue;
				}
				const int64_t at = y * width + x;
				near = minf(near * 2.0, 1.0);
				wanted[at] = (float)maxf((double)wanted[at], near);
				if (is_live[at] == 0) {
					is_live[at] = 1;
					live[live_count] = (int32_t)at;
					live_count++;
				}
			}
		}
	}
	const double opens = _open_rate * delta;
	const double closes = _close_rate * delta;
	int64_t kept = 0;
	int64_t found = 0;
	for (int64_t n = 0; n < live_count; n++) {
		const int64_t at = live[n];
		const double was = shown[at];
		const double want = wanted[at];
		double now = want > was ? minf(was + opens, want) : maxf(was - closes, want);
		if (now < _closed && want <= 0.0) {
			now = 0.0;
			is_live[at] = 0;
		} else {
			live[kept] = (int32_t)at;
			kept++;
		}
		if (now != was) {
			shown[at] = (float)now;
			changed[found] = (int32_t)at;
			found++;
		}
	}
	object->set(k.live_count, kept);
	return found;
}

void MoteKernel::_bind_feel_methods() {
	ClassDB::bind_method(D_METHOD("configure_parting", "config"), &MoteKernel::configure_parting);
	ClassDB::bind_method(D_METHOD("check_parting_fields", "parting"), &MoteKernel::check_parting_fields);
	ClassDB::bind_method(D_METHOD("part_work", "parting", "delta", "feet", "count"), &MoteKernel::part_work);
	ClassDB::bind_method(D_METHOD("configure_stirs", "config"), &MoteKernel::configure_stirs);
	ClassDB::bind_method(D_METHOD("check_stir_fields", "stirs"), &MoteKernel::check_stir_fields);
	ClassDB::bind_method(D_METHOD("stir_step", "stirs", "births", "count", "delta"), &MoteKernel::stir_step);
	ClassDB::bind_method(D_METHOD("configure_flashes", "config"), &MoteKernel::configure_flashes);
	ClassDB::bind_method(D_METHOD("check_flash_fields", "flashes"), &MoteKernel::check_flash_fields);
	ClassDB::bind_method(D_METHOD("find_special", "flashes", "effect_slots"), &MoteKernel::find_special);
	ClassDB::bind_method(D_METHOD("write_rows", "flashes", "real_delta", "next_flash", "effect_slots"), &MoteKernel::write_rows);
}
