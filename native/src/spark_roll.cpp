// SPDX-FileCopyrightText: 2026 peterdk31 and Spellmerge contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//
// See spark_roll.h. The numbers match the GDScript to the bit: a GDScript `float` is a double, a
// Vector2 and a PackedFloat32Array single precision, and a Vector2 times a float multiplies by the
// float rounded to single precision (packed.h, `vmul`), as in shot_kernel.cpp.

#include "spark_roll.h"
#include "packed.h"

#include <cmath>
#include <cstdint>

#include <godot_cpp/core/error_macros.hpp>
#include <godot_cpp/variant/color.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_color_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_int64_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/vector2.hpp>

using namespace godot;

namespace {

// The engine's RandomNumberGenerator (core/math/random_pcg.h and thirdparty/misc/pcg.cpp): PCG32
// with the engine's default stream, which `seed` and `state` leave as it is.
constexpr uint64_t PCG_MULT = 6364136223846793005ULL;
constexpr uint64_t PCG_INC = (1442695040888963407ULL << 1u) | 1u;

struct Dice {
	uint64_t state;
	// `pcg32_random_r`.
	uint32_t next() {
		const uint64_t old = state;
		state = old * PCG_MULT + PCG_INC;
		const uint32_t shifted = (uint32_t)(((old >> 18u) ^ old) >> 27u);
		const uint32_t rot = (uint32_t)(old >> 59u);
		return (shifted >> rot) | (shifted << ((-rot) & 31u));
	}
	// `RandomPCG::randf`: the first roll picks the exponent (its leading zeros), the second the
	// significand.
	double randf() {
		const uint32_t proto = next();
		if (proto == 0) {
			return 0.0;
		}
		int zeros = 0;
		while ((proto & (0x80000000u >> zeros)) == 0) {
			zeros++;
		}
		return (double)std::ldexp((float)(next() | 0x80000001u), -32 - zeros);
	}
	// `RandomPCG::random(from, to)` with `from` 0 (`randi_range(0, to)`): no roll for one choice, else
	// `pcg32_boundedrand_r`.
	int64_t below_or(int64_t to) {
		if (to == 0) {
			return 0;
		}
		const uint32_t bound = (uint32_t)to + 1u;
		const uint32_t threshold = (0u - bound) % bound;
		for (;;) {
			const uint32_t r = next();
			if (r >= threshold) {
				return (int64_t)(r % bound);
			}
		}
	}
};

// `ProjectileDraw._bit_count` and `_nth_bit`.
inline int64_t bit_count(int64_t bits) {
	int64_t n = 0;
	while (bits != 0) {
		bits &= bits - 1;
		n += 1;
	}
	return n;
}

inline int64_t nth_bit(int64_t bits, int64_t n) {
	int64_t at = 0;
	while (bits != 0) {
		if ((bits & 1) == 1) {
			if (n == 0) {
				return at;
			}
			n -= 1;
		}
		bits >>= 1;
		at += 1;
	}
	return 0;
}

bool take(const Dictionary &config, const char *name, int64_t &into) {
	const Variant value = config.get(name, Variant());
	if (value.get_type() != Variant::INT) {
		return false;
	}
	into = value;
	return true;
}

} // namespace

bool SparkRoll::configure(const Dictionary &config) {
	_ready = false;
	const Variant rates = config.get("SPARK_RATES", Variant());
	const Variant grow = config.get("ORBIT_GROW", Variant());
	if (rates.get_type() != Variant::PACKED_FLOAT32_ARRAY || grow.get_type() != Variant::FLOAT) {
		return false;
	}
	_rates = rates;
	_orbit_grow = grow;
	_ready = take(config, "EMITTING_MASK", _emitting_mask) && take(config, "F_QUAD", _f_quad) && take(config, "MOTION_ORBIT", _motion_orbit) &&
			take(config, "SPARK_BIRTHS_MAX", _births_max) && take(config, "SPARK_TRIES_MOST", _tries_most) &&
			take(config, "SPARK_BIRTH_STRIDE", _stride) && take(config, "SPARK_X", _x) && take(config, "SPARK_Y", _y) &&
			take(config, "SPARK_BACK_X", _back_x) && take(config, "SPARK_BACK_Y", _back_y) && take(config, "SPARK_KIND", _kind) &&
			take(config, "SPARK_RAMP", _ramp) && take(config, "SPARK_LOOK", _look) && take(config, "SPARK_CORE", _core) &&
			take(config, "SPARK_TAG", _tag) && take(config, "SPARK_TAG_BITS", _tag_bits) && take(config, "SPARK_FLAG_STEP", _flag_step) &&
			take(config, "SPARK_FLAG_SHIFT", _flag_shift) && take(config, "SPARK_LAYER_MASK", _layer_mask);
	// Every kind's rate is read by its look bit + 1.
	_ready = _ready && _rates.size() > nth_bit(_emitting_mask, bit_count(_emitting_mask) - 1) + 1;
	return _ready;
}

int64_t SparkRoll::give_off(const Array &arrays, const PackedFloat32Array &births_array, int64_t count, int64_t state, int64_t moments,
		double fraction, double span, double sim_time, int64_t live) {
	_state = (uint64_t)state;
	ERR_FAIL_COND_V(!_ready || arrays.size() != 17 || count < 0, count);
	// The order of `ProjectileDraw.SPARK_ARRAYS`.
	const PackedInt32Array groups = arrays[0];
	const PackedInt32Array group_start = arrays[1];
	const PackedInt32Array group_end = arrays[2];
	const PackedFloat32Array group_share = arrays[3];
	const PackedInt32Array by_group = arrays[4];
	const PackedByteArray alive = arrays[5];
	const PackedInt32Array flags = arrays[6];
	const PackedInt32Array look = arrays[7];
	const PackedByteArray motion = arrays[8];
	const PackedVector2Array pos = arrays[9];
	const PackedVector2Array prev = arrays[10];
	const PackedVector2Array vel = arrays[11];
	const PackedInt32Array ramp = arrays[12];
	const PackedColorArray core = arrays[13];
	const PackedInt64Array tag = arrays[14];
	const PackedFloat32Array born = arrays[15];
	const PackedVector2Array orbit_centre = arrays[16];
	const int64_t slots = alive.size();
	ERR_FAIL_COND_V(live > groups.size() || births_array.size() < _births_max * _stride || flags.size() < slots || look.size() < slots ||
					motion.size() < slots || pos.size() < slots || prev.size() < slots || vel.size() < slots || ramp.size() < slots ||
					core.size() < slots || tag.size() < slots || born.size() < slots || orbit_centre.size() < slots,
			count);
	const int64_t group_n = group_start.size();
	ERR_FAIL_COND_V(group_end.size() != group_n || group_share.size() != group_n, count);
	// Written through the caller's buffer (packed.h, `Arr`: the caller holds a reference too).
	float *births = const_cast<float *>(births_array.ptr());
	const float *rates = _rates.ptr();
	const int64_t rate_n = _rates.size();
	Dice dice{ (uint64_t)state };
	int64_t tries_left = _tries_most;
	for (int64_t i = 0; i < live; i++) {
		const int64_t group = groups[i];
		ERR_FAIL_INDEX_V(group, group_n, count);
		const int64_t first = group_start[group];
		const int64_t shots = (int64_t)group_end[group] - first;
		if (shots == 0) {
			continue;
		}
		ERR_FAIL_COND_V(first < 0 || first + shots > by_group.size(), count);
		const int64_t tries = mini(floori((double)(shots * moments) * (double)group_share[group] + dice.randf()), tries_left);
		tries_left -= tries;
		for (int64_t n = 0; n < tries; n++) {
			// `_give_off_spark`.
			const int64_t slot = by_group[first + dice.below_or(shots - 1)];
			ERR_FAIL_INDEX_V(slot, slots, count);
			if (alive[slot] == 0 || (flags[slot] & _f_quad) != 0) {
				continue;
			}
			const int64_t lk = look[slot];
			const int64_t bits = lk & _emitting_mask;
			int64_t kind = 0;
			if (bits != 0) {
				kind = nth_bit(bits, dice.below_or(bit_count(bits) - 1)) + 1;
			}
			ERR_FAIL_INDEX_V(kind, rate_n, count);
			if (dice.randf() >= (double)rates[kind]) {
				continue;
			}
			const Vector2 step = pos[slot] - prev[slot];
			Vector2 at = prev[slot] + vmul(step, fraction - dice.randf() * span);
			Vector2 back = -step;
			if (motion[slot] == _motion_orbit) {
				// `ProjectileMoves._drawn_at`.
				const double out = (sim_time - (double)born[slot]) / _orbit_grow;
				const Vector2 centre = orbit_centre[slot];
				if (!(out >= 1.0 || !centre.is_finite())) {
					at = centre.lerp(at, (real_t)maxf(out, 0.0));
				}
				back = -vel[slot];
			}
			back = back.normalized();
			// `_add_birth` and `_put_birth` (the births are full before any try once `count` reaches the most).
			ERR_FAIL_COND_V(count >= _births_max, count);
			const Color cr = core[slot];
			const int64_t tg = tag[slot];
			float *b = births + count * _stride;
			b[_x] = at.x;
			b[_y] = at.y;
			b[_back_x] = back.x;
			b[_back_y] = back.y;
			b[_kind] = (float)(double)kind;
			b[_ramp] = (float)(double)((int64_t)ramp[slot] + _flag_step * (lk >> _flag_shift));
			b[_look] = (float)(double)(lk & _layer_mask);
			b[_core] = cr.r;
			b[_core + 1] = cr.g;
			b[_core + 2] = cr.b;
			b[_tag] = (float)(double)(tg & ((1ll << _tag_bits) - 1));
			b[_tag + 1] = (float)(double)(tg >> _tag_bits);
			count += 1;
			if (count >= _births_max) {
				_state = dice.state;
				return count;
			}
		}
	}
	_state = dice.state;
	return count;
}
