// SPDX-FileCopyrightText: 2026 peterdk31 and Spellmerge contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//
// What every kernel shares: reading an object's packed arrays for one call (`Arr`), and GDScript's
// helpers written as the engine writes them, so the numbers come out to the bit.

#pragma once

#include <cmath>
#include <type_traits>
#include <utility>

#include <godot_cpp/classes/object.hpp>
#include <godot_cpp/core/math.hpp>
#include <godot_cpp/variant/string_name.hpp>
#include <godot_cpp/variant/variant.hpp>
#include <godot_cpp/variant/vector2.hpp>

namespace {

using namespace godot;

// Reading an object's arrays: a packed array from it shares its buffer; writing through `ptr()` writes the object's
// member (`ptrw()` would copy it, as the object holds a reference too).
template <typename A>
struct Arr {
	A a;
	using T = std::remove_const_t<std::remove_pointer_t<decltype(std::declval<A>().ptr())>>;
	T *p = nullptr;
	int64_t n = 0;
	void load(Object *m, const StringName &name) {
		a = m->get(name);
		p = const_cast<T *>(a.ptr());
		n = a.size();
	}
	T &operator[](int64_t i) { return p[i]; }
};

// GDScript's helpers, as the engine writes them.
inline int64_t floori(double x) { return (int64_t)std::floor(x); }
inline int64_t clampi(int64_t v, int64_t lo, int64_t hi) { return v < lo ? lo : (v > hi ? hi : v); }
inline double clampf(double v, double lo, double hi) { return v < lo ? lo : (v > hi ? hi : v); }
inline Vector2 vmin(const Vector2 &a, const Vector2 &b) { return Vector2(MIN(a.x, b.x), MIN(a.y, b.y)); }
inline Vector2 vmax(const Vector2 &a, const Vector2 &b) { return Vector2(MAX(a.x, b.x), MAX(a.y, b.y)); }
// Vector2 * float in GDScript: the float is rounded to single precision first.
inline Vector2 vmul(const Vector2 &v, double f) { return v * (real_t)f; }

} // namespace
