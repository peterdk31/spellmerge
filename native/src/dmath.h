// SPDX-FileCopyrightText: 2026 peterdk31 and Spellmerge contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Deterministic maths (online-ready N7, docs/milestones/online-ready.md): sin, cos, tan, atan,
// atan2, asin, acos, exp, log and pow, and the Vector2 helpers the simulation turns by, built from
// + - * / and sqrt only (a range reduction, then a polynomial: Taylor series, whose coefficients are
// plain fractions), never the C library's. The C library's trig differs between Linux, Windows and
// the web by a unit in the last place now and then (N2b), and so would two machines' games. These
// give the same bits on every platform the module is built for, because every operation they use
// is one IEEE 754 rounds exactly the same way everywhere: + - * / and sqrt are correctly rounded,
// floor and fmod are exact. The build keeps the compiler from fusing a multiply and an add
// (`-ffp-contract=off` in native/SConstruct) and from fast-math.
//
// The GDScript twin (core/sim/dmath.gd, `DMath`) does the same operations in the same order, and
// `tests/core/test_dmath.gd` compares the two to the bit; change one and you change the other.
// Accuracy: within a few units in the last place of the true value for the angles and sizes the
// game uses (the test checks it against the engine's); the reduction keeps its full accuracy for
// |x| below about 2^20 (a million radians), and stays deterministic beyond.
//
// Everything is in doubles; a Vector2 helper rounds its result to the vector's floats once.

#ifndef SPELLMERGE_DMATH_H
#define SPELLMERGE_DMATH_H

#include <cmath>

#include <godot_cpp/variant/vector2.hpp>

namespace dmath {

// pi/2 in three parts: the first two of 33 significant bits each, so k * part is exact for a
// quadrant count k below 2^20 (the reduction's x - k pi/2 then loses nothing), and the rest.
static constexpr double PIO2_HI = 0x1.921fb54400000p+0;
static constexpr double PIO2_MID = 0x1.0b4611a600000p-34;
static constexpr double PIO2_LO = 0x1.3198a2e037073p-69;
// pi/2 and pi, the doubles nearest them, and what each leaves out.
static constexpr double PIO2 = 0x1.921fb54442d18p+0;
static constexpr double PIO2_D_LO = 0x1.1a62633145c07p-54;
static constexpr double PI_HI = 0x1.921fb54442d18p+1;
static constexpr double PI_LO = 0x1.1a62633145c07p-53;
static constexpr double TAU = 0x1.921fb54442d18p+2;
static constexpr double TWO_OVER_PI = 0x1.45f306dc9c883p-1;
// ln 2: the first 32 significant bits (k * LN2_HI is exact for every k exp reaches) and the rest.
static constexpr double LN2_HI = 0x1.62e42fee00000p-1;
static constexpr double LN2_LO = 0x1.a39ef35793c76p-33;
static constexpr double INV_LN2 = 0x1.71547652b82fep+0;
static constexpr double SQRT2 = 0x1.6a09e667f3bcdp+0;

// 1/n!, each the double nearest it.
static constexpr double F2 = 0x1.0000000000000p-1;
static constexpr double F3 = 0x1.5555555555555p-3;
static constexpr double F4 = 0x1.5555555555555p-5;
static constexpr double F5 = 0x1.1111111111111p-7;
static constexpr double F6 = 0x1.6c16c16c16c17p-10;
static constexpr double F7 = 0x1.a01a01a01a01ap-13;
static constexpr double F8 = 0x1.a01a01a01a01ap-16;
static constexpr double F9 = 0x1.71de3a556c734p-19;
static constexpr double F10 = 0x1.27e4fb7789f5cp-22;
static constexpr double F11 = 0x1.ae64567f544e4p-26;
static constexpr double F12 = 0x1.1eed8eff8d898p-29;
static constexpr double F13 = 0x1.6124613a86d09p-33;
static constexpr double F14 = 0x1.93974a8c07c9dp-37;
static constexpr double F15 = 0x1.ae7f3e733b81fp-41;
static constexpr double F16 = 0x1.ae7f3e733b81fp-45;
static constexpr double F17 = 0x1.952c77030ad4ap-49;
static constexpr double F18 = 0x1.6827863b97d97p-53;
static constexpr double F19 = 0x1.2f49b46814157p-57;
static constexpr double F20 = 0x1.e542ba4020225p-62;
// 1/n for odd n, each the double nearest it.
static constexpr double I3 = 0x1.5555555555555p-2;
static constexpr double I5 = 0x1.999999999999ap-3;
static constexpr double I7 = 0x1.2492492492492p-3;
static constexpr double I9 = 0x1.c71c71c71c71cp-4;
static constexpr double I11 = 0x1.745d1745d1746p-4;
static constexpr double I13 = 0x1.3b13b13b13b14p-4;
static constexpr double I15 = 0x1.1111111111111p-4;
static constexpr double I17 = 0x1.e1e1e1e1e1e1ep-5;
static constexpr double I19 = 0x1.af286bca1af28p-5;
static constexpr double I21 = 0x1.8618618618618p-5;
static constexpr double I23 = 0x1.642c8590b2164p-5;
// atan(k/8) for k = 0..8: the double nearest it, and what that leaves out.
static constexpr double ATAN_HI[9] = { 0.0, 0x1.fd5ba9aac2f6ep-4, 0x1.f5b75f92c80ddp-3, 0x1.6f61941e4def1p-2,
	0x1.dac670561bb4fp-2, 0x1.1e00babdefeb4p-1, 0x1.4978fa3269ee1p-1, 0x1.700a7c5784634p-1, 0x1.921fb54442d18p-1 };
static constexpr double ATAN_LO[9] = { 0.0, -0x1.cd37686760c17p-59, 0x1.8ab6e3cf7afbdp-57, -0x1.c63aae6f6e918p-56,
	0x1.a2b7f222f65e2p-56, -0x1.928df287a668fp-58, 0x1.2419a87f2a458p-56, -0x1.8c34d25aadef6p-56, 0x1.1a62633145c07p-55 };

// sin and cos of r in about [-pi/4, pi/4]: their Taylor series to r^19 and r^20 (the next term is
// below a ten-thousandth of a unit in the last place there).
inline double sin_poly(double r) {
	const double z = r * r;
	return r + r * z * (-F3 + z * (F5 + z * (-F7 + z * (F9 + z * (-F11 + z * (F13 + z * (-F15 + z * (F17 + z * -F19))))))));
}

inline double cos_poly(double r) {
	const double z = r * r;
	return 1.0 + z * (-F2 + z * (F4 + z * (-F6 + z * (F8 + z * (-F10 + z * (F12 + z * (-F14 + z * (F16 + z * (-F18 + z * F20)))))))));
}

// x as r + q pi/2, r in about [-pi/4, pi/4]: returns r and sets `quadrant` to q mod 4 (0 to 3;
// NaN for a NaN or infinite x, which no branch takes).
inline double reduce(double x, double &quadrant) {
	const double k = std::floor(x * TWO_OVER_PI + 0.5);
	quadrant = k - 4.0 * std::floor(k * 0.25);
	return ((x - k * PIO2_HI) - k * PIO2_MID) - k * PIO2_LO;
}

inline void sincos(double x, double &s, double &c) {
	double q;
	const double r = reduce(x, q);
	const double sr = sin_poly(r);
	const double cr = cos_poly(r);
	if (q == 0.0) {
		s = sr;
		c = cr;
	} else if (q == 1.0) {
		s = cr;
		c = -sr;
	} else if (q == 2.0) {
		s = -sr;
		c = -cr;
	} else {
		s = -cr;
		c = sr;
	}
}

inline double sin(double x) {
	double q;
	const double r = reduce(x, q);
	if (q == 0.0) {
		return sin_poly(r);
	}
	if (q == 1.0) {
		return cos_poly(r);
	}
	if (q == 2.0) {
		return -sin_poly(r);
	}
	return -cos_poly(r);
}

inline double cos(double x) {
	double q;
	const double r = reduce(x, q);
	if (q == 0.0) {
		return cos_poly(r);
	}
	if (q == 1.0) {
		return -sin_poly(r);
	}
	if (q == 2.0) {
		return -cos_poly(r);
	}
	return sin_poly(r);
}

inline double tan(double x) {
	double q;
	const double r = reduce(x, q);
	if (q == 0.0 || q == 2.0) {
		return sin_poly(r) / cos_poly(r);
	}
	return -cos_poly(r) / sin_poly(r);
}

// atan of a in [0, 1]: atan(c) for the nearest c = k/8 from the table, plus atan of what is left,
// t = (a - c) / (1 + a c), |t| <= 1/16, by its series to t^15.
inline double atan_unit(double a) {
	const double k = std::floor(a * 8.0 + 0.5);
	double t = a;
	double hi = 0.0;
	double lo = 0.0;
	if (k > 0.0) {
		const double c = k * 0.125;
		t = (a - c) / (1.0 + a * c);
		const int i = (int)k;
		hi = ATAN_HI[i];
		lo = ATAN_LO[i];
	}
	const double z = t * t;
	const double p = t * z * (-I3 + z * (I5 + z * (-I7 + z * (I9 + z * (-I11 + z * (I13 + z * -I15))))));
	return hi + (t + (p + lo));
}

inline double atan(double x) {
	if (x != x) {
		return x;
	}
	const bool negative = x < 0.0;
	const double a = negative ? -x : x;
	double r;
	if (a > 1.0) {
		r = (PIO2 - atan_unit(1.0 / a)) + PIO2_D_LO;
	} else {
		r = atan_unit(a);
	}
	return negative ? -r : r;
}

// atan2 as the engine's, but for the sign of a zero: a zero y counts as +0 (0 for x >= 0, pi for
// x < 0), and atan2(0, 0) is 0.
inline double atan2(double y, double x) {
	if (x != x || y != y) {
		return x + y;
	}
	if (y == 0.0) {
		return x < 0.0 ? PI_HI : 0.0;
	}
	const double ax = x < 0.0 ? -x : x;
	const double ay = y < 0.0 ? -y : y;
	double a;
	if (ax == ay) {
		a = ATAN_HI[8];
	} else if (ay > ax) {
		a = (PIO2 - atan_unit(ax / ay)) + PIO2_D_LO;
	} else {
		a = atan_unit(ay / ax);
	}
	if (x < 0.0) {
		a = (PI_HI - a) + PI_LO;
	}
	return y < 0.0 ? -a : a;
}

// asin and acos clamp as the engine's do: below -1 counts as -1, above 1 as 1.
inline double asin(double x) {
	if (x != x) {
		return x;
	}
	if (x <= -1.0) {
		return -PIO2;
	}
	if (x >= 1.0) {
		return PIO2;
	}
	return atan2(x, std::sqrt((1.0 - x) * (1.0 + x)));
}

inline double acos(double x) {
	if (x != x) {
		return x;
	}
	if (x <= -1.0) {
		return PI_HI;
	}
	if (x >= 1.0) {
		return 0.0;
	}
	return atan2(std::sqrt((1.0 - x) * (1.0 + x)), x);
}

// 2^n for a whole n in [-1022, 1023], exactly (powers of two multiply exactly).
inline double pow2(double n) {
	double result = 1.0;
	double base = n < 0.0 ? 0.5 : 2.0;
	long long left = (long long)(n < 0.0 ? -n : n);
	while (left > 0) {
		if (left & 1) {
			result *= base;
		}
		left >>= 1;
		if (left > 0) {
			base *= base;
		}
	}
	return result;
}

// p * 2^k for a whole k, rounded once.
inline double scale2(double p, double k) {
	if (k > 1023.0) {
		return p * pow2(1023.0) * pow2(k - 1023.0);
	}
	if (k < -1022.0) {
		return p * pow2(k + 60.0) * pow2(-60.0);
	}
	return p * pow2(k);
}

// e^x: x = k ln 2 + r, |r| <= ln 2 / 2, and e^r by its series to r^15.
inline double exp(double x) {
	if (x != x) {
		return x;
	}
	const double k = std::floor(x * INV_LN2 + 0.5);
	if (k > 1024.0) {
		return HUGE_VAL;
	}
	if (k < -1080.0) {
		return 0.0;
	}
	const double r = (x - k * LN2_HI) - k * LN2_LO;
	const double p = 1.0 + r * (1.0 + r * (F2 + r * (F3 + r * (F4 + r * (F5 + r * (F6 + r * (F7 + r * (F8 + r * (F9 + r * (F10 + r * (F11 + r * (F12 + r * (F13 + r * (F14 + r * F15))))))))))))));
	return scale2(p, k);
}

// The natural log: x = m 2^e, m in (sqrt(1/2), sqrt(2)], and log m = 2 atanh(s), s = (m-1)/(m+1),
// by its series to s^23.
inline double log(double x) {
	if (x != x) {
		return x;
	}
	if (x < 0.0) {
		return NAN;
	}
	if (x == 0.0) {
		return -HUGE_VAL;
	}
	if (x == HUGE_VAL) {
		return x;
	}
	double m = x;
	double e = 0.0;
	if (m < pow2(-1022.0)) {
		m *= pow2(54.0);
		e = -54.0;
	}
	static constexpr double STEPS[10] = { 512.0, 256.0, 128.0, 64.0, 32.0, 16.0, 8.0, 4.0, 2.0, 1.0 };
	for (int i = 0; i < 10; i++) {
		const double p = STEPS[i];
		if (m >= pow2(p)) {
			m *= pow2(-p);
			e += p;
		}
	}
	for (int i = 0; i < 10; i++) {
		const double p = STEPS[i];
		if (m < pow2(1.0 - p)) {
			m *= pow2(p);
			e -= p;
		}
	}
	if (m > SQRT2) {
		m *= 0.5;
		e += 1.0;
	}
	const double s = (m - 1.0) / (m + 1.0);
	const double z = s * s;
	const double q = s * z * (I3 + z * (I5 + z * (I7 + z * (I9 + z * (I11 + z * (I13 + z * (I15 + z * (I17 + z * (I19 + z * (I21 + z * I23))))))))));
	const double logm = 2.0 * (s + q);
	return e * LN2_HI + (e * LN2_LO + logm);
}

// x^y: a whole y up to 64 by multiplying (squares of x, so x^2 is x * x and 2^10 is 1024 exactly),
// any other as e^(y log x); with the C library's special cases (a negative x takes only a whole y).
inline double pow(double x, double y) {
	if (y == 0.0 || x == 1.0) {
		return 1.0;
	}
	if (x != x || y != y) {
		return x + y;
	}
	if (y == 1.0) {
		return x;
	}
	if (y == 2.0) {
		return x * x;
	}
	if (x == 0.0) {
		return y > 0.0 ? 0.0 : HUGE_VAL;
	}
	const bool whole = std::floor(y) == y;
	if (whole && y >= -64.0 && y <= 64.0) {
		double result = 1.0;
		double base = x;
		long long left = (long long)(y < 0.0 ? -y : y);
		while (left > 0) {
			if (left & 1) {
				result *= base;
			}
			left >>= 1;
			if (left > 0) {
				base *= base;
			}
		}
		return y < 0.0 ? 1.0 / result : result;
	}
	bool negative = false;
	double a = x;
	if (x < 0.0) {
		if (!whole) {
			return NAN;
		}
		negative = std::fmod(y, 2.0) != 0.0;
		a = -x;
	}
	const double r = exp(y * log(a));
	return negative ? -r : r;
}

// The engine's lerp_angle (fmod is exact, so it is the same on every platform).
inline double lerp_angle(double from, double to, double weight) {
	const double difference = std::fmod(to - from, TAU);
	const double distance = std::fmod(2.0 * difference, TAU) - difference;
	return from + distance * weight;
}

// The Vector2 helpers, in place of the engine's: the sums in doubles, rounded to the vector's floats
// once at the end.
inline godot::Vector2 from_angle(double angle) {
	double s;
	double c;
	sincos(angle, s, c);
	return godot::Vector2((godot::real_t)c, (godot::real_t)s);
}

inline godot::Vector2 rotated(const godot::Vector2 &v, double angle) {
	double s;
	double c;
	sincos(angle, s, c);
	const double x = (double)v.x;
	const double y = (double)v.y;
	return godot::Vector2((godot::real_t)(x * c - y * s), (godot::real_t)(x * s + y * c));
}

inline double angle(const godot::Vector2 &v) {
	return atan2((double)v.y, (double)v.x);
}

inline double angle_to(const godot::Vector2 &from, const godot::Vector2 &to) {
	const double cross = (double)from.x * (double)to.y - (double)from.y * (double)to.x;
	const double dot = (double)from.x * (double)to.x + (double)from.y * (double)to.y;
	return atan2(cross, dot);
}

} // namespace dmath

#endif // SPELLMERGE_DMATH_H
