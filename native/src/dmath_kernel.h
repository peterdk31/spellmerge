// SPDX-FileCopyrightText: 2026 peterdk31 and Spellmerge contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//
// DMathKernel (online-ready N7): the deterministic maths of dmath.h for GDScript. `DMath`
// (core/sim/dmath.gd) calls it when the module is loaded, else its own twin of each function, the
// same operations in the same order (tests/core/test_dmath.gd compares them to the bit).

#ifndef SPELLMERGE_DMATH_KERNEL_H
#define SPELLMERGE_DMATH_KERNEL_H

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/vector2.hpp>

namespace godot {

class DMathKernel : public RefCounted {
	GDCLASS(DMathKernel, RefCounted)

protected:
	static void _bind_methods();

public:
	double sin(double x) const;
	double cos(double x) const;
	double tan(double x) const;
	double atan(double x) const;
	double atan2(double y, double x) const;
	double asin(double x) const;
	double acos(double x) const;
	double exp(double x) const;
	double log(double x) const;
	double pow(double x, double y) const;
	double lerp_angle(double from, double to, double weight) const;
	Vector2 from_angle(double angle) const;
	Vector2 rotated(const Vector2 &v, double angle) const;
	double angle(const Vector2 &v) const;
	double angle_to(const Vector2 &from, const Vector2 &to) const;
};

} // namespace godot

#endif // SPELLMERGE_DMATH_KERNEL_H
