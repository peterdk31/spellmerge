// SPDX-FileCopyrightText: 2026 peterdk31 and Spellmerge contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//
// DMathKernel (dmath_kernel.h): dmath.h's functions, bound for GDScript.

#include "dmath_kernel.h"

#include <godot_cpp/core/class_db.hpp>

#include "dmath.h"

using namespace godot;

double DMathKernel::sin(double x) const {
	return dmath::sin(x);
}

double DMathKernel::cos(double x) const {
	return dmath::cos(x);
}

double DMathKernel::tan(double x) const {
	return dmath::tan(x);
}

double DMathKernel::atan(double x) const {
	return dmath::atan(x);
}

double DMathKernel::atan2(double y, double x) const {
	return dmath::atan2(y, x);
}

double DMathKernel::asin(double x) const {
	return dmath::asin(x);
}

double DMathKernel::acos(double x) const {
	return dmath::acos(x);
}

double DMathKernel::exp(double x) const {
	return dmath::exp(x);
}

double DMathKernel::log(double x) const {
	return dmath::log(x);
}

double DMathKernel::pow(double x, double y) const {
	return dmath::pow(x, y);
}

double DMathKernel::lerp_angle(double from, double to, double weight) const {
	return dmath::lerp_angle(from, to, weight);
}

Vector2 DMathKernel::from_angle(double angle) const {
	return dmath::from_angle(angle);
}

Vector2 DMathKernel::rotated(const Vector2 &v, double angle) const {
	return dmath::rotated(v, angle);
}

double DMathKernel::angle(const Vector2 &v) const {
	return dmath::angle(v);
}

double DMathKernel::angle_to(const Vector2 &from, const Vector2 &to) const {
	return dmath::angle_to(from, to);
}

void DMathKernel::_bind_methods() {
	ClassDB::bind_method(D_METHOD("sin", "x"), &DMathKernel::sin);
	ClassDB::bind_method(D_METHOD("cos", "x"), &DMathKernel::cos);
	ClassDB::bind_method(D_METHOD("tan", "x"), &DMathKernel::tan);
	ClassDB::bind_method(D_METHOD("atan", "x"), &DMathKernel::atan);
	ClassDB::bind_method(D_METHOD("atan2", "y", "x"), &DMathKernel::atan2);
	ClassDB::bind_method(D_METHOD("asin", "x"), &DMathKernel::asin);
	ClassDB::bind_method(D_METHOD("acos", "x"), &DMathKernel::acos);
	ClassDB::bind_method(D_METHOD("exp", "x"), &DMathKernel::exp);
	ClassDB::bind_method(D_METHOD("log", "x"), &DMathKernel::log);
	ClassDB::bind_method(D_METHOD("pow", "x", "y"), &DMathKernel::pow);
	ClassDB::bind_method(D_METHOD("lerp_angle", "from", "to", "weight"), &DMathKernel::lerp_angle);
	ClassDB::bind_method(D_METHOD("from_angle", "angle"), &DMathKernel::from_angle);
	ClassDB::bind_method(D_METHOD("rotated", "v", "angle"), &DMathKernel::rotated);
	ClassDB::bind_method(D_METHOD("angle", "v"), &DMathKernel::angle);
	ClassDB::bind_method(D_METHOD("angle_to", "from", "to"), &DMathKernel::angle_to);
}
