// SPDX-FileCopyrightText: 2026 peterdk31 and Spellmerge contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//
// See mote_kernel.h, and shot_kernel.cpp for how the numbers are kept to the bit (a GDScript
// `float` is a double; Vector2, Color and PackedFloat32Array single precision).

#include "mote_kernel.h"
#include "packed.h"

#include <godot_cpp/classes/random_number_generator.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_int64_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>

using namespace godot;

namespace {

constexpr double PI_D = 3.1415926535897932384626433833;

// The members the kernel reads: C++ name, GDScript member, type (one list, so `check_fields` sees
// every name it uses).
#define MOTE_FIELDS(X) \
	X(buffers, "_buffers", ARRAY) \
	X(dirty, "_dirty", PACKED_BYTE_ARRAY) \
	X(until, "_until", PACKED_FLOAT32_ARRAY) \
	X(rng, "_rng", OBJECT) \
	X(settle_marks, "_settle_marks", PACKED_INT32_ARRAY) \
	X(k_speed, "_k_speed", PACKED_VECTOR2_ARRAY) \
	X(k_up, "_k_up", PACKED_VECTOR2_ARRAY) \
	X(k_life, "_k_life", PACKED_VECTOR2_ARRAY) \
	X(k_spread, "_k_spread", PACKED_FLOAT64_ARRAY) \
	X(k_height, "_k_height", PACKED_FLOAT64_ARRAY) \
	X(k_gravity, "_k_gravity", PACKED_FLOAT64_ARRAY) \
	X(k_bounce, "_k_bounce", PACKED_FLOAT64_ARRAY) \
	X(k_drag, "_k_drag", PACKED_FLOAT64_ARRAY) \
	X(k_wobble, "_k_wobble", PACKED_FLOAT64_ARRAY) \
	X(k_wobble_rate, "_k_wobble_rate", PACKED_FLOAT64_ARRAY) \
	X(birth_pair, "_birth_pair", PACKED_INT32_ARRAY) \
	X(pair_key, "_pair_key", PACKED_INT64_ARRAY) \
	X(pair_from, "_pair_from", PACKED_INT32_ARRAY) \
	X(pair_size, "_pair_size", PACKED_INT32_ARRAY) \
	X(pair_kinds, "_pair_kinds", PACKED_INT32_ARRAY) \
	X(settle_out, "_settle_out", PACKED_FLOAT64_ARRAY) \
	X(cap, "_cap", INT) \
	X(next, "_next", INT) \
	X(now, "_now", FLOAT) \
	X(rows_left, "_rows_left", INT) \
	X(settles_left, "_settles_left", INT) \
	X(serial, "_serial", INT) \
	X(density, "density", FLOAT) \
	X(cut, "cut", INT) \
	X(births, "births", INT) \
	X(written, "written", INT) \
	X(settles, "settles", INT) \
	X(settles_skipped, "settles_skipped", INT) \
	X(infusion_rgb, "_infusion_rgb", PACKED_FLOAT32_ARRAY) \
	X(infusion_mask, "_infusion_mask", INT) \
	X(infusion_turn, "_infusion_turn", INT)

struct MoteNames {
#define MO_DECLARE(id, gd, type) StringName id;
	MOTE_FIELDS(MO_DECLARE)
#undef MO_DECLARE
	MoteNames() {
#define MO_INIT(id, gd, type) id = StringName(gd);
		MOTE_FIELDS(MO_INIT)
#undef MO_INIT
	}
};

MoteNames *mote_names = nullptr;

// Every member of the motes' regions (`MoteRegions`, gameplay/feel/mote_regions.gd; the
// performance pass, 2026-11-20) the hand-out reads and writes, and the pool's members it reads.
// Checked by `check_fields` on the regions.
#define MOTE_REGION_FIELDS(X) \
	X(places, "places", INT) \
	X(whole, "_whole", PACKED_BYTE_ARRAY) \
	X(columns, "_columns", INT) \
	X(lines, "_lines", INT) \
	X(origin, "_origin", VECTOR2) \
	X(bounds, "_bounds", PACKED_FLOAT64_ARRAY) \
	X(slot_of, "_slot_of", PACKED_INT32_ARRAY) \
	X(row_of_slot, "_row_of_slot", PACKED_INT32_ARRAY) \
	X(buffers, "_buffers", ARRAY) \
	X(fill, "_fill", PACKED_INT32_ARRAY) \
	X(live, "_live", PACKED_INT32_ARRAY) \
	X(until, "_until", PACKED_FLOAT64_ARRAY) \
	X(dirty, "_dirty", PACKED_BYTE_ARRAY) \
	X(region, "_region", PACKED_INT32_ARRAY) \
	X(open, "_open", PACKED_INT32_ARRAY) \
	X(free, "_free", PACKED_INT32_ARRAY) \
	X(free_count, "_free_count", INT) \
	X(ring_rows, "_ring_rows", INT)

struct RegionNames {
#define MR_DECLARE(id, gd, type) StringName id;
	MOTE_REGION_FIELDS(MR_DECLARE)
#undef MR_DECLARE
	RegionNames() {
#define MR_INIT(id, gd, type) id = StringName(gd);
		MOTE_REGION_FIELDS(MR_INIT)
#undef MR_INIT
	}
};

RegionNames *region_names = nullptr;

const RegionNames &rn() {
	if (region_names == nullptr) {
		region_names = new RegionNames();
	}
	return *region_names;
}

// `MoteRegions`' numbers (its constants, here as the kernel's own: `check_regions` compares them).
constexpr int64_t REGION_ROWS = 512;
constexpr int64_t REGION_PLACE_ASK = 255;
constexpr double REGION_PLACE_CELL = 32.0;
constexpr double REGION_PAD = 24.0;
constexpr int64_t REGION_MAX_KINDS = 256;

const MoteNames &mn() {
	if (mote_names == nullptr) {
		mote_names = new MoteNames();
	}
	return *mote_names;
}

#define MO_CHECK(id, gd, type)                                         \
	if (object->get(k.id).get_type() != Variant::type) {               \
		wrong.push_back(String("member ") + gd + " missing or not " #type); \
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

MoteKernel::MoteKernel() {
	mn();
}

void MoteKernel::free_names() {
	delete mote_names;
	mote_names = nullptr;
	delete region_names;
	region_names = nullptr;
}

bool MoteKernel::configure(const Dictionary &c) {
	_ready = take_int(c, "CHUNK", _chunk) && take_int(c, "DRAW_STRIDE", _stride) &&
			take_int(c, "BIRTH_STRIDE", _birth_stride) && take_int(c, "SETTLE_STRIDE", _settle_stride) &&
			take_int(c, "ROW_VX", _row_vx) && take_int(c, "ROW_BORN", _row_born) && take_int(c, "ROW_X", _row_x) &&
			take_int(c, "ROW_VY", _row_vy) && take_int(c, "ROW_VZ", _row_vz) && take_int(c, "ROW_Y", _row_y) &&
			take_int(c, "ROW_SOURCE", _row_source) && take_int(c, "ROW_KIND", _row_kind) &&
			take_int(c, "ROW_LIFE", _row_life) && take_int(c, "ROW_HEIGHT", _row_height) &&
			take_int(c, "ROW_CORE", _row_core) && take_int(c, "ROW_SEED", _row_seed) &&
			take_int(c, "SPARK_X", _spark_x) && take_int(c, "SPARK_Y", _spark_y) &&
			take_int(c, "SPARK_BACK_X", _spark_back_x) && take_int(c, "SPARK_BACK_Y", _spark_back_y) &&
			take_int(c, "SPARK_KIND", _spark_kind) && take_int(c, "SPARK_RAMP", _spark_ramp) &&
			take_int(c, "SPARK_LOOK", _spark_look) && take_int(c, "SPARK_CORE", _spark_core) &&
			take_int(c, "SPARK_TAG", _spark_tag) && take_int(c, "SPARK_TAG_BITS", _spark_tag_bits) &&
			take_int(c, "SPARK_STREAK", _spark_streak) && take_int(c, "PAIR_LAYERS", _pair_layers) &&
			take_int(c, "ENEMY_SOURCE", _enemy_source) && take_int(c, "EXACT_SOURCE", _exact_source) &&
			take_int(c, "LOOK_ENEMY_RAMP", _look_enemy_ramp) && take_int(c, "LOOK_EXACT", _look_exact) &&
			take(c, "LIFE_MAX", _life_max) && take(c, "HEIGHT_MAX", _height_max) &&
			take(c, "SOURCE_CODE", _source_code) && take(c, "KIND_CODE", _kind_code) &&
			take(c, "TRAIL_SPEED", _trail_speed) && take_int(c, "LOOK_LAYERS", _look_layers);
	return _ready;
}

PackedStringArray MoteKernel::check_fields(Object *object) const {
	PackedStringArray wrong;
	ERR_FAIL_NULL_V(object, wrong);
	const MoteNames &k = mn();
	MOTE_FIELDS(MO_CHECK)
	return wrong;
}

PackedStringArray MoteKernel::check_regions(Object *object) const {
	PackedStringArray wrong;
	ERR_FAIL_NULL_V(object, wrong);
	const RegionNames &k = rn();
	MOTE_REGION_FIELDS(MO_CHECK)
	const int64_t rows = object->get("ROWS");
	const int64_t ask = object->get("PLACE_ASK");
	const double cell = object->get("PLACE_CELL");
	const double pad = object->get("PAD");
	const int64_t most_kinds = object->get("MAX_KINDS");
	if (rows != REGION_ROWS || ask != REGION_PLACE_ASK || cell != REGION_PLACE_CELL || pad != REGION_PAD || most_kinds != REGION_MAX_KINDS) {
		wrong.push_back("the regions' numbers");
	}
	return wrong;
}

// The pairs of the births' (tag, kind), first seen first. A small open table finds a pair seen
// before (a frame's births come from few spells).
int64_t MoteKernel::key_births(Object *m, const PackedFloat32Array &given, int64_t count) {
	ERR_FAIL_COND_V(!_ready, 0);
	const MoteNames &k = mn();
	Arr<PackedInt32Array> birth_pair;
	Arr<PackedInt64Array> pair_key;
	birth_pair.load(m, k.birth_pair);
	pair_key.load(m, k.pair_key);
	count = MIN(count, given.size() / _birth_stride);
	ERR_FAIL_COND_V(count > birth_pair.n || count > pair_key.n, 0);
	const float *g = given.ptr();
	constexpr int64_t TABLE = 2048;
	int32_t slot_of[TABLE];
	for (int64_t i = 0; i < TABLE; i++) {
		slot_of[i] = -1;
	}
	int64_t pairs = 0;
	for (int64_t n = 0; n < count; n++) {
		const int64_t b = n * _birth_stride;
		const int64_t kind = (int64_t)(double)g[b + _spark_kind];
		const int64_t tag = (int64_t)(double)g[b + _spark_tag] | ((int64_t)(double)g[b + _spark_tag + 1] << _spark_tag_bits);
		const int64_t key = tag * _pair_layers + kind + 1;
		uint64_t h = (uint64_t)key * 0x9E3779B97F4A7C15ull;
		int64_t at = (int64_t)(h >> 53) & (TABLE - 1);
		while (slot_of[at] >= 0 && pair_key[slot_of[at]] != key) {
			at = (at + 1) & (TABLE - 1);
		}
		if (slot_of[at] < 0) {
			slot_of[at] = (int32_t)pairs;
			pair_key[pairs] = key;
			pairs += 1;
		}
		birth_pair[n] = slot_of[at];
	}
	return pairs;
}

int64_t MoteKernel::give_off(Object *m, const PackedFloat32Array &given, int64_t count, bool has_marks) {
	ERR_FAIL_COND_V(!_ready, 0);
	const MoteNames &k = mn();
	RandomNumberGenerator *rng = Object::cast_to<RandomNumberGenerator>((Object *)m->get(k.rng));
	ERR_FAIL_NULL_V(rng, 0);
	Arr<PackedByteArray> dirty;
	Arr<PackedFloat32Array> until;
	Arr<PackedInt32Array> settle_marks, birth_pair, pair_from, pair_size, pair_kinds;
	Arr<PackedVector2Array> k_speed, k_up, k_life;
	Arr<PackedFloat64Array> k_spread, k_height, k_gravity, k_bounce, k_drag, k_wobble, k_wobble_rate, settle_out;
	Arr<PackedFloat32Array> infusion_rgb;
	dirty.load(m, k.dirty);
	until.load(m, k.until);
	settle_marks.load(m, k.settle_marks);
	birth_pair.load(m, k.birth_pair);
	pair_from.load(m, k.pair_from);
	pair_size.load(m, k.pair_size);
	pair_kinds.load(m, k.pair_kinds);
	k_speed.load(m, k.k_speed);
	k_up.load(m, k.k_up);
	k_life.load(m, k.k_life);
	k_spread.load(m, k.k_spread);
	k_height.load(m, k.k_height);
	k_gravity.load(m, k.k_gravity);
	k_bounce.load(m, k.k_bounce);
	k_drag.load(m, k.k_drag);
	k_wobble.load(m, k.k_wobble);
	k_wobble_rate.load(m, k.k_wobble_rate);
	settle_out.load(m, k.settle_out);
	infusion_rgb.load(m, k.infusion_rgb);
	Array buffers = m->get(k.buffers);
	const int64_t kinds = k_speed.n;
	ERR_FAIL_COND_V(k_up.n < kinds || k_life.n < kinds || k_spread.n < kinds || k_height.n < kinds ||
					k_gravity.n < kinds || k_bounce.n < kinds || k_drag.n < kinds || k_wobble.n < kinds ||
					k_wobble_rate.n < kinds,
			0);
	const int64_t cap = m->get(k.cap);
	int64_t next = m->get(k.next);
	const double now = m->get(k.now);
	int64_t rows_left = m->get(k.rows_left);
	int64_t settles_left = m->get(k.settles_left);
	int64_t serial = m->get(k.serial);
	const double density = m->get(k.density);
	int64_t cut = m->get(k.cut);
	int64_t births = m->get(k.births);
	int64_t written = m->get(k.written);
	int64_t settles = m->get(k.settles);
	int64_t settles_skipped = m->get(k.settles_skipped);
	const int64_t infusion_mask = m->get(k.infusion_mask);
	int64_t infusion_turn = m->get(k.infusion_turn);
	ERR_FAIL_COND_V(cap <= 0 || dirty.n < buffers.size() || until.n < buffers.size(), 0);

	// `give_off`'s first line.
	count = MIN(count, given.size() / _birth_stride);
	ERR_FAIL_COND_V(count > birth_pair.n, 0);
	const float *g = given.ptr();
	int64_t handed = 0;
	const int64_t handed_most = settle_out.n / _settle_stride;

	// The chunk being written: taken out of the list while written (`ptrw` then copies the buffer
	// only if the renderer still holds it).
	int64_t chunk = -1;
	bool failed = false;
	PackedFloat32Array buffer;
	float *buf = nullptr;
	auto put_back = [&]() {
		if (chunk >= 0) {
			buffers[chunk] = buffer;
			buffer = PackedFloat32Array();
			buf = nullptr;
		}
	};

	for (int64_t n = 0; n < count; n++) {
		if (rows_left <= 0) {
			cut += count - n;
			break;
		}
		const int64_t b = n * _birth_stride;
		const int64_t p = birth_pair[n];
		ERR_BREAK(p < 0 || p >= pair_size.n || p >= pair_from.n);
		const int64_t size = pair_size[p];
		if (size <= 0) {
			continue;
		}
		const int64_t from = pair_from[p];
		ERR_BREAK(from + size > pair_kinds.n);
		const int64_t kk = size == 1 ? pair_kinds[from] : pair_kinds[from + rng->randi_range(0, (int32_t)(size - 1))];
		ERR_BREAK(kk < 0 || kk >= kinds);
		births += 1;

		// The one-mote `burst` give_off calls.
		const Vector2 at((real_t)g[b + _spark_x], (real_t)g[b + _spark_y]);
		const Vector2 dir((real_t)g[b + _spark_back_x], (real_t)g[b + _spark_back_y]);
		const Vector2 speed = vmul(k_speed[kk], _trail_speed);
		const double spread = k_spread[kk];
		const Vector2 up = vmul(k_up[kk], _trail_speed);
		const Vector2 life = k_life[kk];
		const int64_t ramp = (int64_t)(double)g[b + _spark_ramp];
		const int64_t look = (int64_t)(double)g[b + _spark_look];
		const int64_t who = ramp >= 0 && ramp < _enemy_source && (look & _look_enemy_ramp) == 0 ? ramp : _enemy_source;
		const int64_t source = who + ((look & _look_exact) != 0 ? _exact_source : 0);
		float core_r = g[b + _spark_core], core_g = g[b + _spark_core + 1], core_b = g[b + _spark_core + 2];
		// `infusions_of`: a birth of an infusion's layer is in its colours; any other of a spell of
		// several (a tail, a splash) takes the next infusion (`_next_infusion`).
		const int64_t present = look & infusion_mask;
		if ((present & (present - 1)) != 0) {
			const int64_t layer = (int64_t)(double)g[b + _spark_kind];
			int64_t bits = layer >= 1 && layer <= _look_layers ? present & ((int64_t)1 << (layer - 1)) : 0;
			if (bits == 0) {
				int64_t count = 0;
				for (int64_t left = present; left != 0; left &= left - 1) {
					count++;
				}
				const int64_t pick = infusion_turn % count;
				infusion_turn += 1;
				bits = present;
				for (int64_t i = 0; i < pick; i++) {
					bits &= bits - 1;
				}
			}
			int64_t lowest = 1;
			while (((bits >> (lowest - 1)) & 1) == 0) {
				lowest++;
			}
			ERR_BREAK(lowest * 3 + 2 >= infusion_rgb.n);
			core_r = infusion_rgb[lowest * 3];
			core_g = infusion_rgb[lowest * 3 + 1];
			core_b = infusion_rgb[lowest * 3 + 2];
		}
		double height = k_height[kk];

		int64_t one = 1;
		if (density != 1.0) {
			one = floori((double)one * density + rng->randf());
		}
		if (one <= 0 || !at.is_finite() || source < 0) {
			continue;
		}
		const int64_t room = rows_left;
		if (one > room) {
			cut += 1;
			one = room;
			if (one <= 0) {
				continue;
			}
		}
		const int64_t mark = has_marks && kk < settle_marks.n ? settle_marks[kk] : -1;
		int64_t settling = 0;
		if (mark >= 0) {
			settling = MIN(MIN(one, settles_left), room - one);
			settles_left -= settling;
			settles += settling;
			settles_skipped += one - settling;
		}
		rows_left -= one + settling;
		written += one;
		const double aim = dir != Vector2() ? (double)dir.angle() : 0.0;
		const double half = clampf(spread, 0.0, 360.0) * (PI_D / 180.0) * 0.5;
		height = std::round(clampf(height, 0.0, _height_max) / _height_max * 255.0) / 255.0 * _height_max;
		const Vector2 ground = at + Vector2(0.0f, (real_t)height);
		const double coded_source = (double)source / _source_code;
		const double coded_kind = (double)kk / _kind_code;
		const double coded_height = height / _height_max;
		const double shortest = clampf((double)life.x, 0.02, _life_max);
		const double longest = clampf((double)life.y, 0.02, _life_max);
		for (int64_t i = 0; i < one; i++) {
			const int64_t row = next;
			next = (next + 1) % cap;
			const int64_t c = row / _chunk;
			if (c != chunk) {
				put_back();
				chunk = c;
				buffer = buffers[c];
				if (buffer.size() < MIN(_chunk, cap - c * _chunk) * _stride) {
					// A chunk GDScript did not make (`_ready_chunks`): stop, nothing half written.
					ERR_PRINT("MoteKernel: a chunk is missing or short");
					buffer = PackedFloat32Array();
					chunk = -1;
					failed = true;
					break;
				}
				buffers[c] = PackedFloat32Array();
				buf = buffer.ptrw();
				dirty[c] = 1;
				until[c] = (float)MAX((double)until[c], now + longest + _life_max / 255.0);
			}
			const double turn = aim + rng->randf_range(-half, half);
			const Vector2 way = Vector2::from_angle((real_t)turn);
			const Vector2 v = vmul(way, rng->randf_range(speed.x, speed.y));
			float *r = buf + (row - c * _chunk) * _stride;
			r[_row_vx] = v.x;
			r[_row_born] = (float)now;
			r[_row_x] = ground.x;
			r[_row_vy] = v.y;
			r[_row_vz] = (float)rng->randf_range(up.x, up.y);
			r[_row_y] = ground.y;
			r[_row_source] = (float)coded_source;
			r[_row_kind] = (float)coded_kind;
			r[_row_life] = (float)(std::round(rng->randf_range(shortest, longest) / _life_max * 255.0) / 255.0);
			r[_row_height] = (float)coded_height;
			r[_row_core] = core_r;
			r[_row_core + 1] = core_g;
			r[_row_core + 2] = core_b;
			r[_row_seed] = (float)rng->randf();
			if (i < settling) {
				// `_land`: where and when it rests, as Vector3 (single precision) holds it.
				const double gravity = k_gravity[kk];
				if (gravity <= 0.0) {
					continue;
				}
				const double h0 = (double)r[_row_height] * _height_max;
				const double vz = (double)r[_row_vz];
				const double land = (vz + std::sqrt(vz * vz + 2.0 * gravity * MAX(h0, 0.0))) / gravity;
				const double rebound = (gravity * land - vz) * k_bounce[kk];
				const double rest = land + 2.0 * rebound / gravity;
				if (rest >= (double)r[_row_life] * _life_max) {
					continue;
				}
				const double drag = k_drag[kk];
				const double along = drag > 0.0 ? (1.0 - std::exp(-drag * rest)) / drag : rest;
				const double phase = (double)r[_row_seed] * 6.2832;
				const float lx = (float)((double)r[_row_x] + (double)r[_row_vx] * along +
						k_wobble[kk] * (std::sin(rest * k_wobble_rate[kk] + phase) - std::sin(phase)));
				const float ly = (float)((double)r[_row_y] + (double)r[_row_vy] * along);
				const float lz = (float)((double)r[_row_born] + rest);
				if (!std::isfinite(lz) || handed >= handed_most) {
					continue;
				}
				double *o = settle_out.p + handed * _settle_stride;
				o[0] = (double)mark;
				o[1] = (double)std::floor(lx);
				o[2] = (double)std::floor(ly);
				o[3] = (double)lz;
				o[4] = (double)source;
				o[5] = (double)core_r;
				o[6] = (double)core_g;
				o[7] = (double)core_b;
				o[8] = (double)(serial + i);
				handed += 1;
			}
		}
		if (failed) {
			break;
		}
		serial += one;
	}
	put_back();

	m->set(k.next, next);
	m->set(k.rows_left, rows_left);
	m->set(k.settles_left, settles_left);
	m->set(k.serial, serial);
	m->set(k.cut, cut);
	m->set(k.births, births);
	m->set(k.written, written);
	m->set(k.settles, settles);
	m->set(k.settles_skipped, settles_skipped);
	m->set(k.infusion_turn, infusion_turn);
	return handed;
}

// `MoteRegions._hand`: the rows of the ring from `from` handed to their regions' chunks, each
// one's earlier copy folded away; stops at a row whose region needs a chunk while none is free.
int64_t MoteKernel::region_rows(Object *regions, Object *m, int64_t from, int64_t count, double now) {
	ERR_FAIL_COND_V(!_ready, 0);
	ERR_FAIL_NULL_V(regions, 0);
	ERR_FAIL_NULL_V(m, 0);
	const RegionNames &r = rn();
	const MoteNames &k = mn();
	Arr<PackedByteArray> whole, dirty;
	Arr<PackedFloat64Array> bounds, until, k_gravity, k_drag, k_bounce, k_wobble;
	Arr<PackedInt32Array> slot_of, row_of_slot, fill, live, region, open, free;
	whole.load(regions, r.whole);
	dirty.load(regions, r.dirty);
	bounds.load(regions, r.bounds);
	until.load(regions, r.until);
	slot_of.load(regions, r.slot_of);
	row_of_slot.load(regions, r.row_of_slot);
	fill.load(regions, r.fill);
	live.load(regions, r.live);
	region.load(regions, r.region);
	open.load(regions, r.open);
	free.load(regions, r.free);
	k_gravity.load(m, k.k_gravity);
	k_drag.load(m, k.k_drag);
	k_bounce.load(m, k.k_bounce);
	k_wobble.load(m, k.k_wobble);
	Array chunks = regions->get(r.buffers);
	Array ring = m->get(k.buffers);
	const int64_t places = regions->get(r.places);
	const int64_t columns = regions->get(r.columns);
	const int64_t lines = regions->get(r.lines);
	const Vector2 origin = regions->get(r.origin);
	const int64_t ring_rows = regions->get(r.ring_rows);
	int64_t free_count = regions->get(r.free_count);
	const int64_t cap = slot_of.n;
	const int64_t made = fill.n;
	const int64_t kinds = k_gravity.n;
	ERR_FAIL_COND_V(cap <= 0 || ring_rows <= 0 || whole.n < columns * lines || bounds.n < places * 4 || open.n <= places, 0);
	ERR_FAIL_COND_V(chunks.size() < made || live.n < made || until.n < made || dirty.n < made || region.n < made ||
					row_of_slot.n < made * REGION_ROWS || free_count > free.n,
			0);
	ERR_FAIL_COND_V(k_drag.n < kinds || k_bounce.n < kinds || k_wobble.n < kinds, 0);

	// The chunk written and the one folded in: taken out of the list while written (`ptrw` then
	// copies the buffer only if the renderer still holds it) and put back after.
	int64_t into_c = -1, fold_c = -1;
	PackedFloat32Array into_buf, fold_buf;
	float *into = nullptr, *fold = nullptr;
	auto take = [&](int64_t c, int64_t &held, PackedFloat32Array &buf, float *&p) {
		if (held == c) {
			return;
		}
		if (held >= 0) {
			chunks[held] = buf;
		}
		held = c;
		buf = chunks[c];
		chunks[c] = PackedFloat32Array();
		p = buf.ptrw();
	};
	auto put_back = [&]() {
		if (into_c >= 0) {
			chunks[into_c] = into_buf;
		}
		if (fold_c >= 0) {
			chunks[fold_c] = fold_buf;
		}
		into_c = -1;
		fold_c = -1;
	};
	// One chunk taken out at a time: a chunk wanted by the other cursor is put back first.
	auto hold_into = [&](int64_t c) {
		if (fold_c == c) {
			chunks[fold_c] = fold_buf;
			fold_c = -1;
		}
		take(c, into_c, into_buf, into);
	};
	auto hold_fold = [&](int64_t c) {
		if (into_c == c) {
			chunks[into_c] = into_buf;
			into_c = -1;
		}
		take(c, fold_c, fold_buf, fold);
	};

	// The ring's chunk read, as the pool holds it (read only).
	int64_t ring_c = -1;
	PackedFloat32Array ring_buf;
	const float *src = nullptr;
	int64_t handed = count;
	for (int64_t n = 0; n < count; n++) {
		const int64_t row = (from + n) % cap;
		const int64_t old = slot_of[row];
		if (old >= 0) {
			const int64_t oc = old / REGION_ROWS;
			const int64_t oi = old % REGION_ROWS;
			if (oc < made && oi < fill[oc] && row_of_slot[old] == row) {
				hold_fold(oc);
				fold[oi * _stride + _row_life] = 0.0f;
				live[oc] -= 1;
				dirty[oc] = 1;
				row_of_slot[old] = -1;
			}
			slot_of[row] = -1;
		}
		const int64_t c_ring = row / ring_rows;
		if (c_ring != ring_c) {
			ring_c = c_ring;
			ring_buf = ring[c_ring];
			src = ring_buf.ptr();
		}
		const int64_t i = (row % ring_rows) * _stride;
		if (i + _stride > ring_buf.size()) {
			continue;
		}
		const float *row_p = src + i;
		// `region_of`.
		const double life = (double)row_p[_row_life] * _life_max;
		const double born = (double)row_p[_row_born];
		if (life <= 0.0 || born + life <= now) {
			continue;
		}
		int64_t code = 0;
		const double x = (double)row_p[_row_x];
		const double y = (double)row_p[_row_y];
		const int64_t cx = floori((x - (double)origin.x) / REGION_PLACE_CELL);
		const int64_t cy = floori((y - (double)origin.y) / REGION_PLACE_CELL);
		if (cx >= 0 && cx < columns && cy >= 0 && cy < lines) {
			code = whole[cy * columns + cx];
			if (code == REGION_PLACE_ASK || code > places) {
				code = 0;
			}
		}
		if (code > 0) {
			const int64_t kk = clampi((int64_t)std::round((double)row_p[_row_kind] * _kind_code), 0, REGION_MAX_KINDS - 1);
			if (kk >= kinds) {
				code = 0;
			} else {
				// `reach_of`, rounded to single precision as its Vector2 is.
				const double vx = (double)row_p[_row_vx];
				const double vy = (double)row_p[_row_vy];
				const double vz = (double)row_p[_row_vz];
				const double h0 = maxf((double)row_p[_row_height] * _height_max, 0.0);
				const double drag = k_drag[kk];
				const double gravity = k_gravity[kk];
				const double bounce = k_bounce[kk];
				const double along = drag > 0.0 ? (1.0 - std::exp(-drag * life)) / drag : life;
				const double spread = std::sqrt(vx * vx + vy * vy) * along + 2.0 * std::abs(k_wobble[kk]) + REGION_PAD;
				double rise;
				if (gravity > 0.0) {
					rise = (h0 + vz * vz / (2.0 * gravity)) * maxf(bounce * bounce, 1.0);
				} else {
					rise = h0 + maxf(vz, 0.0) * life - 0.5 * gravity * life * life;
				}
				const double rx = (double)(float)spread;
				const double ry = (double)(float)rise;
				const double *b = bounds.p + (code - 1) * 4;
				if (x - rx < b[0] || x + rx > b[2] || y - rx - ry < b[1] || y + rx > b[3]) {
					code = 0;
				}
			}
		}
		int64_t c = open[code];
		if (c < 0 || fill[c] >= REGION_ROWS) {
			if (free_count == 0) {
				handed = n;
				break;
			}
			free_count -= 1;
			c = free[free_count];
			open[code] = (int32_t)c;
			region[c] = (int32_t)code;
			fill[c] = 0;
			live[c] = 0;
			until[c] = 0.0;
		}
		const int64_t at = fill[c];
		fill[c] = (int32_t)(at + 1);
		hold_into(c);
		float *to = into + at * _stride;
		for (int64_t f = 0; f < _stride; f++) {
			to[f] = row_p[f];
		}
		const int64_t slot = c * REGION_ROWS + at;
		slot_of[row] = (int32_t)slot;
		row_of_slot[slot] = (int32_t)row;
		live[c] += 1;
		until[c] = maxf(until[c], (double)row_p[_row_born] + (double)row_p[_row_life] * _life_max);
		dirty[c] = 1;
	}
	put_back();
	regions->set(r.free_count, free_count);
	return handed;
}

void MoteKernel::_bind_methods() {
	ClassDB::bind_method(D_METHOD("configure", "config"), &MoteKernel::configure);
	ClassDB::bind_method(D_METHOD("check_fields", "motes"), &MoteKernel::check_fields);
	ClassDB::bind_method(D_METHOD("key_births", "motes", "given", "count"), &MoteKernel::key_births);
	ClassDB::bind_method(D_METHOD("give_off", "motes", "given", "count", "has_marks"), &MoteKernel::give_off);
	ClassDB::bind_method(D_METHOD("check_regions", "regions"), &MoteKernel::check_regions);
	ClassDB::bind_method(D_METHOD("region_rows", "regions", "motes", "from", "count", "now"), &MoteKernel::region_rows);
}
