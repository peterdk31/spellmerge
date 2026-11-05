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

// GDScript's `roundi` and `lerpf`, as the engine writes them (doubles).
inline int64_t roundi(double x) { return (int64_t)std::round(x); }
inline double lerpf(double a, double b, double t) { return a + (b - a) * t; }

// The members the kernel reads: C++ name, GDScript member, type (one list, so `check_fields` sees
// every name it uses).
#define MOTE_FIELDS(X) \
	X(buffers, "_buffers", ARRAY) \
	X(dirty, "_dirty", PACKED_BYTE_ARRAY) \
	X(until, "_until", PACKED_FLOAT32_ARRAY) \
	X(rng, "_rng", OBJECT) \
	X(settle_marks, "_settle_marks", PACKED_INT32_ARRAY) \
	X(trail_packs, "_trail_packs", ARRAY) \
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
	X(ring_rows, "_ring_rows", PACKED_INT32_ARRAY) \
	X(ring_chunk, "_ring_chunk", PACKED_INT32_ARRAY) \
	X(ring_first, "_ring_first", PACKED_INT32_ARRAY) \
	X(ring_next, "_ring_next", PACKED_INT32_ARRAY) \
	X(ring_written, "_ring_written", PACKED_INT32_ARRAY) \
	X(now, "_now", FLOAT) \
	X(rows_left, "_rows_left", INT) \
	X(keep, "_keep", INT) \
	X(settles_left, "_settles_left", INT) \
	X(density, "density", FLOAT) \
	X(cut, "cut", INT) \
	X(births, "births", INT) \
	X(written, "written", INT) \
	X(settles, "settles", INT) \
	X(settles_skipped, "settles_skipped", INT)

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
}

bool MoteKernel::configure(const Dictionary &c) {
	_ready = take_int(c, "DRAW_STRIDE", _stride) && take_int(c, "BIRTH_STRIDE", _birth_stride) &&
			take_int(c, "SETTLE_STRIDE", _settle_stride) && take_int(c, "SINGLES", _singles) &&
			take_int(c, "SERIAL_BITS", _serial_bits) &&
			take_int(c, "ROW_AIM", _row_aim) && take_int(c, "ROW_BORN", _row_born) && take_int(c, "ROW_SEED", _row_seed) &&
			take_int(c, "ROW_X", _row_x) && take_int(c, "ROW_SPEED", _row_speed) && take_int(c, "ROW_UP", _row_up) &&
			take_int(c, "ROW_LIFE", _row_life) && take_int(c, "ROW_Y", _row_y) &&
			take_int(c, "ROW_SOURCE", _row_source) && take_int(c, "ROW_KIND", _row_kind) &&
			take_int(c, "ROW_COUNT", _row_count) && take_int(c, "ROW_HEIGHT", _row_height) &&
			take_int(c, "ROW_CORE", _row_core) &&
			take_int(c, "PACK_HALF", _pack_half) && take_int(c, "PACK_SPEED", _pack_speed) &&
			take_int(c, "PACK_UP", _pack_up) && take_int(c, "PACK_LIFE", _pack_life) &&
			take_int(c, "PACK_LONGEST", _pack_longest) && take_int(c, "PACK_SIZE", _pack_size) &&
			take_int(c, "SPARK_X", _spark_x) && take_int(c, "SPARK_Y", _spark_y) &&
			take_int(c, "SPARK_BACK_X", _spark_back_x) && take_int(c, "SPARK_BACK_Y", _spark_back_y) &&
			take_int(c, "SPARK_KIND", _spark_kind) && take_int(c, "SPARK_RAMP", _spark_ramp) &&
			take_int(c, "SPARK_LOOK", _spark_look) && take_int(c, "SPARK_CORE", _spark_core) &&
			take_int(c, "SPARK_TAG", _spark_tag) && take_int(c, "SPARK_TAG_BITS", _spark_tag_bits) &&
			take_int(c, "SPARK_STREAK", _spark_streak) && take_int(c, "PAIR_LAYERS", _pair_layers) &&
			take_int(c, "ENEMY_SOURCE", _enemy_source) && take_int(c, "EXACT_SOURCE", _exact_source) &&
			take_int(c, "LOOK_ENEMY_RAMP", _look_enemy_ramp) && take_int(c, "LOOK_EXACT", _look_exact) &&
			take(c, "HEIGHT_MAX", _height_max) && take(c, "SOURCE_CODE", _source_code) &&
			take(c, "KIND_CODE", _kind_code) && take(c, "AIM_STEP", _aim_step) &&
			take(c, "HALF_STEP", _half_step) && take(c, "SPEED_STEP", _speed_step) &&
			take(c, "UP_LOW", _up_low) && take(c, "LIFE_STEP", _life_step);
	return _ready;
}

PackedStringArray MoteKernel::check_fields(Object *object) const {
	PackedStringArray wrong;
	ERR_FAIL_NULL_V(object, wrong);
	const MoteNames &k = mn();
	MOTE_FIELDS(MO_CHECK)
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

// `Motes.give_off`: each birth a one-mote `_write` into the SINGLES ring (a row a mote: S4, a burst
// a row), its kind's trail numbers packed (`_trail_packs`), and the settle `_land` works out.
int64_t MoteKernel::give_off(Object *m, const PackedFloat32Array &given, int64_t count, bool has_marks) {
	ERR_FAIL_COND_V(!_ready, 0);
	const MoteNames &k = mn();
	RandomNumberGenerator *rng = Object::cast_to<RandomNumberGenerator>((Object *)m->get(k.rng));
	ERR_FAIL_NULL_V(rng, 0);
	Arr<PackedByteArray> dirty;
	Arr<PackedFloat32Array> until;
	Arr<PackedInt32Array> settle_marks, birth_pair, pair_from, pair_size, pair_kinds;
	Arr<PackedInt32Array> ring_rows, ring_chunk, ring_first, ring_next, ring_written;
	Arr<PackedFloat64Array> k_height, k_gravity, k_bounce, k_drag, k_wobble, k_wobble_rate, settle_out;
	dirty.load(m, k.dirty);
	until.load(m, k.until);
	settle_marks.load(m, k.settle_marks);
	birth_pair.load(m, k.birth_pair);
	pair_from.load(m, k.pair_from);
	pair_size.load(m, k.pair_size);
	pair_kinds.load(m, k.pair_kinds);
	ring_rows.load(m, k.ring_rows);
	ring_chunk.load(m, k.ring_chunk);
	ring_first.load(m, k.ring_first);
	ring_next.load(m, k.ring_next);
	ring_written.load(m, k.ring_written);
	k_height.load(m, k.k_height);
	k_gravity.load(m, k.k_gravity);
	k_bounce.load(m, k.k_bounce);
	k_drag.load(m, k.k_drag);
	k_wobble.load(m, k.k_wobble);
	k_wobble_rate.load(m, k.k_wobble_rate);
	settle_out.load(m, k.settle_out);
	Array buffers = m->get(k.buffers);
	Array trail_packs = m->get(k.trail_packs);
	const int64_t kinds = trail_packs.size();
	ERR_FAIL_COND_V(k_height.n < kinds || k_gravity.n < kinds || k_bounce.n < kinds || k_drag.n < kinds ||
					k_wobble.n < kinds || k_wobble_rate.n < kinds,
			0);
	const int64_t ring = _singles;
	ERR_FAIL_COND_V(ring < 0 || ring >= ring_rows.n || ring >= ring_chunk.n || ring >= ring_first.n ||
					ring >= ring_next.n || ring >= ring_written.n,
			0);
	const int64_t rows_of_ring = ring_rows[ring];
	const int64_t chunk_rows = ring_chunk[ring];
	const int64_t first = ring_first[ring];
	ERR_FAIL_COND_V(rows_of_ring <= 0 || chunk_rows <= 0, 0);
	const double now = m->get(k.now);
	int64_t rows_left = m->get(k.rows_left);
	const int64_t keep = m->get(k.keep);
	int64_t settles_left = m->get(k.settles_left);
	const double density = m->get(k.density);
	int64_t cut = m->get(k.cut);
	int64_t births = m->get(k.births);
	int64_t written = m->get(k.written);
	int64_t settles = m->get(k.settles);
	int64_t settles_skipped = m->get(k.settles_skipped);
	ERR_FAIL_COND_V(dirty.n < buffers.size() || until.n < buffers.size(), 0);

	// `give_off`'s first line.
	count = MIN(count, given.size() / _birth_stride);
	ERR_FAIL_COND_V(count > birth_pair.n, 0);
	const float *g = given.ptr();
	int64_t handed = 0;
	const int64_t handed_most = settle_out.n / _settle_stride;

	// The chunk being written: taken out of the list while written (`ptrw` then copies the buffer
	// only if the renderer still holds it).
	int64_t chunk = -1;
	PackedFloat32Array buffer;
	float *buf = nullptr;
	auto put_back = [&]() {
		if (chunk >= 0) {
			buffers[chunk] = buffer;
			buffer = PackedFloat32Array();
			buf = nullptr;
			chunk = -1;
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
		const PackedFloat32Array pack = trail_packs[kk];
		ERR_BREAK(pack.size() < _pack_size);

		// `_write(k, at, dir, 1, _trail_packs[k], source, core, height)`.
		const Vector2 at((real_t)g[b + _spark_x], (real_t)g[b + _spark_y]);
		const Vector2 dir((real_t)g[b + _spark_back_x], (real_t)g[b + _spark_back_y]);
		const int64_t ramp = (int64_t)(double)g[b + _spark_ramp];
		const int64_t look = (int64_t)(double)g[b + _spark_look];
		const int64_t who = ramp >= 0 && ramp < _enemy_source && (look & _look_enemy_ramp) == 0 ? ramp : _enemy_source;
		const int64_t source = who + ((look & _look_exact) != 0 ? _exact_source : 0);
		const float core_r = g[b + _spark_core], core_g = g[b + _spark_core + 1], core_b = g[b + _spark_core + 2];
		double height = k_height[kk];

		int64_t one = 1;
		if (density != 1.0) {
			one = floori((double)one * density + rng->randf());
		}
		if (one <= 0 || !at.is_finite() || source < 0) {
			continue;
		}
		// One mote, so one row of the SINGLES ring (fewer than SPLIT motes).
		int64_t rows = one;
		const int64_t room = rows_left - keep;
		if (rows > room) {
			cut += 1;
			rows = room;
			if (rows <= 0) {
				continue;
			}
			one = MIN(one, rows);
		}
		const int64_t mark = has_marks && kk < settle_marks.n ? settle_marks[kk] : -1;
		int64_t settling = 0;
		if (mark >= 0) {
			settling = MIN(MIN(one, settles_left), room - rows);
			settles_left -= settling;
			settles += settling;
			settles_skipped += one - settling;
		}
		rows_left -= rows + settling;
		written += one;
		const double coded_height = std::round(clampf(height, 0.0, _height_max) / _height_max * 255.0) / 255.0;
		height = coded_height * _height_max;
		const double coded_aim = (double)(((roundi((double)dir.angle() / _aim_step) & 4095) << 12) | (int64_t)(double)pack[_pack_half]);
		const float coded_speed = pack[_pack_speed];
		const float coded_up = pack[_pack_up];
		const float coded_life = pack[_pack_life];
		const double coded_source = (double)source / _source_code;
		const double coded_kind = (double)kk / _kind_code;
		const double until_time = now + (double)pack[_pack_longest] + _life_step;
		const int64_t per = one / rows;
		const int64_t extra = one - per * rows;
		int64_t settled = 0;
		bool failed = false;
		for (int64_t r = 0; r < rows; r++) {
			const int64_t row = ring_next[ring];
			ring_next[ring] = (int32_t)((row + 1) % rows_of_ring);
			ring_written[ring] += 1;
			const int64_t c = first + row / chunk_rows;
			if (c != chunk) {
				put_back();
				buffer = buffers[c];
				const int64_t chunk_has = MIN(chunk_rows, rows_of_ring - (c - first) * chunk_rows);
				if (buffer.size() < chunk_has * _stride) {
					// A chunk GDScript did not make (`_ready_chunks`): stop, nothing half written.
					ERR_PRINT("MoteKernel: a chunk is missing or short");
					buffer = PackedFloat32Array();
					failed = true;
					break;
				}
				chunk = c;
				buffers[c] = PackedFloat32Array();
				buf = buffer.ptrw();
				dirty[c] = 1;
				until[c] = (float)MAX((double)until[c], until_time);
			}
			float *o = buf + (row % chunk_rows) * _stride;
			const int64_t q_count = per + (r < extra ? 1 : 0);
			const int64_t seed = (int64_t)rng->randi() & 0xFFFFFF;
			o[_row_aim] = (float)coded_aim;
			o[_row_born] = (float)now;
			o[_row_seed] = (float)(double)seed;
			o[_row_x] = at.x;
			o[_row_speed] = coded_speed;
			o[_row_up] = coded_up;
			o[_row_life] = coded_life;
			o[_row_y] = (float)((double)at.y + height);
			o[_row_source] = (float)coded_source;
			o[_row_kind] = (float)coded_kind;
			o[_row_count] = (float)((double)q_count / 255.0);
			o[_row_height] = (float)coded_height;
			o[_row_core] = core_r;
			o[_row_core + 1] = core_g;
			o[_row_core + 2] = core_b;
			int64_t q = 0;
			while (settled < settling && q < q_count) {
				float lx = 0.0f, ly = 0.0f, lz = 0.0f;
				if (_land(o, kk, q, k_gravity[kk], k_bounce[kk], k_drag[kk], k_wobble[kk], k_wobble_rate[kk], lx, ly, lz) &&
						handed < handed_most) {
					double *s = settle_out.p + handed * _settle_stride;
					s[0] = (double)mark;
					s[1] = (double)std::floor(lx);
					s[2] = (double)std::floor(ly);
					s[3] = (double)lz;
					s[4] = (double)source;
					s[5] = (double)core_r;
					s[6] = (double)core_g;
					s[7] = (double)core_b;
					s[8] = (double)((ring << _serial_bits) | ((int64_t)ring_written[ring] - 1));
					handed += 1;
				}
				settled += 1;
				q += 1;
			}
		}
		if (failed) {
			break;
		}
	}
	put_back();

	m->set(k.rows_left, rows_left);
	m->set(k.settles_left, settles_left);
	m->set(k.cut, cut);
	m->set(k.births, births);
	m->set(k.written, written);
	m->set(k.settles, settles);
	m->set(k.settles_skipped, settles_skipped);
	return handed;
}

// `Motes.mote_hash`: 32-bit, as both the script and the shader work it.
int64_t MoteKernel::_hash(int64_t x) {
	x &= 0xFFFFFFFFll;
	x ^= x >> 16;
	x = (x * 2146121005ll) & 0xFFFFFFFFll;
	x ^= x >> 15;
	x = (x * 739982445ll) & 0xFFFFFFFFll;
	x ^= x >> 12;
	x = (x * 695872825ll) & 0xFFFFFFFFll;
	x ^= x >> 15;
	return x;
}

// `Motes._land` of mote `q` of the row at `o`: where (x, y) and when (z) it rests, as its Vector3
// (single precision) holds them; false for INF (it never rests in its life).
bool MoteKernel::_land(const float *o, int64_t kk, int64_t q, double gravity, double bounce, double drag,
		double wobble, double wobble_rate, float &x, float &y, float &z) const {
	if (gravity <= 0.0) {
		return false;
	}
	const int64_t h1 = _hash((int64_t)(double)o[_row_seed] * 16 + q);
	const int64_t h2 = _hash(h1);
	const int64_t u = (int64_t)(double)o[_row_up];
	const double vz = lerpf((double)(u >> 12) * _speed_step + _up_low, (double)(u & 4095) * _speed_step + _up_low, (double)(h2 >> 20) / 4096.0);
	const double h0 = (double)o[_row_height] * _height_max;
	const double land = (vz + std::sqrt(vz * vz + 2.0 * gravity * MAX(h0, 0.0))) / gravity;
	const double rebound = (gravity * land - vz) * bounce;
	const double rest = land + 2.0 * rebound / gravity;
	const int64_t l = (int64_t)(double)o[_row_life];
	if (rest >= lerpf((double)(l >> 12) * _life_step, (double)(l & 4095) * _life_step, (double)((h2 >> 8) & 4095) / 4096.0)) {
		return false;
	}
	const int64_t aim = (int64_t)(double)o[_row_aim];
	const double way = (double)(aim >> 12) * _aim_step + ((double)(h1 >> 20) / 4096.0 * 2.0 - 1.0) * (double)(aim & 4095) * _half_step;
	const int64_t sp = (int64_t)(double)o[_row_speed];
	const double speed = lerpf((double)(sp >> 12) * _speed_step, (double)(sp & 4095) * _speed_step, (double)((h1 >> 8) & 4095) / 4096.0);
	const double along = (drag > 0.0 ? (1.0 - std::exp(-drag * rest)) / drag : rest) * speed;
	const double phase = (double)(((h1 & 255) << 8) | (h2 & 255)) / 65536.0 * 6.2832;
	x = (float)((double)o[_row_x] + std::cos(way) * along + wobble * (std::sin(rest * wobble_rate + phase) - std::sin(phase)));
	y = (float)((double)o[_row_y] + std::sin(way) * along);
	z = (float)((double)o[_row_born] + rest);
	return std::isfinite(z);
}

void MoteKernel::_bind_methods() {
	ClassDB::bind_method(D_METHOD("configure", "config"), &MoteKernel::configure);
	ClassDB::bind_method(D_METHOD("check_fields", "motes"), &MoteKernel::check_fields);
	ClassDB::bind_method(D_METHOD("key_births", "motes", "given", "count"), &MoteKernel::key_births);
	ClassDB::bind_method(D_METHOD("give_off", "motes", "given", "count", "has_marks"), &MoteKernel::give_off);
}
