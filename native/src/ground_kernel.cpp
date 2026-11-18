// SPDX-FileCopyrightText: 2026 peterdk31 and Spellmerge contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//
// See ground_kernel.h. Mirrors gameplay/feel/ground/ (ground_noise.gd, ground_geometry.gd,
// ground_material.gd, ground_walls.gd, ground_drawing.gd) line by line: a GDScript `float` is a
// double, a PackedFloat32Array single precision (the crack widths, `t`, the glow's sums: read as a
// double, stored rounded to a float), a JSON number a double. GDScript's `int()` truncates, `floori`
// floors, `%` on whole numbers truncates as C++ does, and `posmod`/`fposmod` are written out. The
// maths is the C library's (`std::sin`, `cos`, `atan2`, `pow`, `sqrt`), as the engine's GDScript calls
// it: the drawing is view only, so a platform's last digit may differ (native/README.md).

#include "ground_kernel.h"
#include "jobs.h"
#include "packed.h"

#include <cmath>
#include <cstdint>
#include <vector>

#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_string_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/string.hpp>

using namespace godot;

namespace {

constexpr double TURN = 6.283185307179586;
constexpr double HALF_TURN = 3.141592653589793;
constexpr int64_t CELL = 8;
constexpr double PIN_EASE = 12.0;
constexpr int64_t TRIM_ROUND = 5;
constexpr int64_t SIDE_REACH = 130;
constexpr int64_t STEP = 4;
// The rows a span of the per-pixel loops covers (jobs.h: each span writes its own rows only).
constexpr int64_t ROWS_A_SPAN = 8;

// -- GroundNoise --

inline uint64_t fnv(uint64_t x, int64_t v) { return ((x ^ ((uint64_t)v & 0xFFFFFFFFull)) * 16777619ull) & 0xFFFFFFFFull; }
inline int64_t finish(uint64_t x) {
	x ^= x >> 13;
	x = (x * 0x5BD1E995ull) & 0xFFFFFFFFull;
	return (int64_t)(x ^ (x >> 15));
}
inline int64_t hash2(int64_t a, int64_t b) { return finish(fnv(fnv(2166136261ull, a), b)); }
inline int64_t hash3(int64_t a, int64_t b, int64_t c) { return finish(fnv(fnv(fnv(2166136261ull, a), b), c)); }
inline int64_t hash4(int64_t a, int64_t b, int64_t c, int64_t d) { return finish(fnv(fnv(fnv(fnv(2166136261ull, a), b), c), d)); }
inline double unit2(int64_t a, int64_t b) { return (double)hash2(a, b) / 4294967296.0; }
inline double unit3(int64_t a, int64_t b, int64_t c) { return (double)hash3(a, b, c) / 4294967296.0; }
inline double unit4(int64_t a, int64_t b, int64_t c, int64_t d) { return (double)hash4(a, b, c, d) / 4294967296.0; }
inline double smooth(double t) { return t * t * (3.0 - 2.0 * t); }
inline int64_t posmod_i(int64_t x, int64_t y) {
	int64_t v = x % y;
	if ((v < 0 && y > 0) || (v > 0 && y < 0)) {
		v += y;
	}
	return v;
}
inline double fposmod_f(double x, double y) {
	double v = std::fmod(x, y);
	if ((v < 0 && y > 0) || (v > 0 && y < 0)) {
		v += y;
	}
	v += 0.0;
	return v;
}
inline double absf(double x) { return std::fabs(x); }
inline int64_t absi(int64_t x) { return x < 0 ? -x : x; }

double noise1(double s, int64_t seed, int64_t period = 0) {
	const int64_t i = floori(s);
	const double t = smooth(s - (double)i);
	int64_t a = i, b = i + 1;
	if (period > 0) {
		a = posmod_i(a, period);
		b = posmod_i(b, period);
	}
	return unit2(seed, a) * (1.0 - t) + unit2(seed, b) * t;
}

double noise2(double x, double y, double scale, int64_t seed) {
	const double fx = x / scale, fy = y / scale;
	const int64_t ix = floori(fx), iy = floori(fy);
	const double tx = smooth(fx - (double)ix), ty = smooth(fy - (double)iy);
	const double a = unit3(seed, ix, iy);
	const double b = unit3(seed, ix + 1, iy);
	const double c = unit3(seed, ix, iy + 1);
	const double d = unit3(seed, ix + 1, iy + 1);
	return (a * (1.0 - tx) + b * tx) * (1.0 - ty) + (c * (1.0 - tx) + d * tx) * ty;
}

double fbm2(double x, double y, const std::vector<double> &scales, int64_t seed) {
	double total = 0.0, weight = 0.0, amp = 1.0;
	for (size_t i = 0; i < scales.size(); i++) {
		total += noise2(x, y, scales[i], seed + (int64_t)i) * amp;
		weight += amp;
		amp *= 0.5;
	}
	return total / weight;
}

inline double length_of(double dx, double dy) { return std::sqrt(dx * dx + dy * dy); }

int64_t round_even(double x) {
	const double low = std::floor(x);
	const double part = x - low;
	if (part > 0.5) {
		return (int64_t)low + 1;
	}
	if (part < 0.5) {
		return (int64_t)low;
	}
	return posmod_i((int64_t)low, 2) == 0 ? (int64_t)low : (int64_t)low + 1;
}

int64_t mix(int64_t a, int64_t b, double t) {
	const int64_t ar = (a >> 16) & 0xFF, ag = (a >> 8) & 0xFF, ab = a & 0xFF;
	const int64_t r = round_even((double)ar + (double)(((b >> 16) & 0xFF) - ar) * t);
	const int64_t g = round_even((double)ag + (double)(((b >> 8) & 0xFF) - ag) * t);
	const int64_t bl = round_even((double)ab + (double)((b & 0xFF) - ab) * t);
	return (r << 16) | (g << 8) | bl;
}

// -- reading the spec (JSON: every number a double) --

inline double num(const Dictionary &d, const char *key, double fallback) {
	return d.has(key) ? (double)d[key] : fallback;
}
inline int64_t inum(const Dictionary &d, const char *key, int64_t fallback) {
	return d.has(key) ? (int64_t)(double)d[key] : fallback;
}
inline Dictionary dict(const Dictionary &d, const char *key) {
	if (!d.has(key)) {
		return Dictionary();
	}
	const Variant v = d[key];
	return v.get_type() == Variant::DICTIONARY ? (Dictionary)v : Dictionary();
}
inline Array arr(const Dictionary &d, const char *key) {
	if (!d.has(key)) {
		return Array();
	}
	const Variant v = d[key];
	return v.get_type() == Variant::ARRAY ? (Array)v : Array();
}
inline double at(const Array &a, int64_t i) { return (double)a[i]; }
std::vector<double> numbers(const Array &a) {
	std::vector<double> out;
	for (int64_t i = 0; i < a.size(); i++) {
		out.push_back((double)a[i]);
	}
	return out;
}

// `GroundNoise.colour`: `#rrggbb` or a palette material's shade.
int64_t colour(const String &spec, const Dictionary &palette) {
	if (spec.begins_with("#")) {
		return spec.substr(1).hex_to_int();
	}
	const String name = spec.get_slice(".", 0);
	const String shade_name = spec.get_slice(".", 1);
	const int64_t shade = shade_name == "shadow" ? 0 : (shade_name == "base" ? 1 : (shade_name == "light" ? 2 : -1));
	const PackedInt32Array shades = palette.has(name) ? (PackedInt32Array)palette[name] : PackedInt32Array();
	if (shade < 0 || shades.size() != 3 || spec.get_slice_count(".") != 2) {
		return -1;
	}
	return shades[shade];
}
inline int64_t colour_of(const Variant &spec, const Dictionary &palette) { return colour((String)spec, palette); }

inline void put(std::vector<uint8_t> &image, int64_t p, int64_t rgb, int64_t alpha = 255) {
	image[p * 4] = (uint8_t)((rgb >> 16) & 0xFF);
	image[p * 4 + 1] = (uint8_t)((rgb >> 8) & 0xFF);
	image[p * 4 + 2] = (uint8_t)(rgb & 0xFF);
	image[p * 4 + 3] = (uint8_t)alpha;
}

// The four ways a walk steps, in the order the GDScript tries them.
constexpr int64_t WAY_X[4] = { 1, -1, 0, 0 };
constexpr int64_t WAY_Y[4] = { 0, 0, 1, -1 };

// -- GroundGeometry --

std::vector<double> outline_points(const Dictionary &spec, double step = 2.0) {
	const Array centre = arr(spec, "centre");
	const Array radii = arr(spec, "radii");
	const double cx = at(centre, 0), cy = at(centre, 1), rx = at(radii, 0), ry = at(radii, 1);
	const int64_t seed = inum(spec, "seed", 0);
	const double mean = (rx + ry) * 0.5;
	const int64_t count = maxi(64, (int64_t)(TURN * mean / step));
	const Array waves = arr(spec, "waves");
	const Array rough = arr(spec, "rough");
	std::vector<int64_t> periods;
	for (int64_t j = 0; j < rough.size(); j++) {
		periods.push_back(maxi(1, round_even(TURN * mean / at((Array)rough[j], 0))));
	}
	std::vector<double> points((size_t)(count * 2));
	for (int64_t i = 0; i < count; i++) {
		const double a = (double)i / (double)count * TURN;
		double r = 1.0;
		for (int64_t k = 0; k < waves.size(); k++) {
			const Array wave = waves[k];
			r += at(wave, 1) * std::sin(at(wave, 0) * a + at(wave, 2));
		}
		for (int64_t j = 0; j < rough.size(); j++) {
			const int64_t period = periods[j];
			r += at((Array)rough[j], 1) * 2.0 * (noise1(a / TURN * (double)period, seed + 17 * j, period) - 0.5);
		}
		points[i * 2] = cx + std::cos(a) * rx * r;
		points[i * 2 + 1] = cy + std::sin(a) * ry * r;
	}
	return points;
}

void fill_polygon(std::vector<uint8_t> &mask, int64_t w, int64_t h, const std::vector<double> &points, uint8_t value) {
	const int64_t count = (int64_t)points.size() / 2;
	if (count == 0) {
		return;
	}
	double low = INFINITY, high = -INFINITY;
	for (int64_t i = 0; i < count; i++) {
		low = minf(low, points[i * 2 + 1]);
		high = maxf(high, points[i * 2 + 1]);
	}
	const int64_t top = maxi(0, (int64_t)low);
	const int64_t bottom = mini(h - 1, (int64_t)high + 1);
	std::vector<double> xs;
	for (int64_t y = top; y <= bottom; y++) {
		const double sy = (double)y + 0.5;
		xs.clear();
		for (int64_t i = 0; i < count; i++) {
			const double x1 = points[i * 2], y1 = points[i * 2 + 1];
			const int64_t k = (i + 1) % count;
			const double x2 = points[k * 2], y2 = points[k * 2 + 1];
			if ((y1 <= sy && sy < y2) || (y2 <= sy && sy < y1)) {
				xs.push_back(x1 + (sy - y1) * (x2 - x1) / (y2 - y1));
			}
		}
		// Sorted, as the GDScript's `sort` (equal numbers are the same number).
		for (size_t i = 1; i < xs.size(); i++) {
			const double v = xs[i];
			size_t j = i;
			while (j > 0 && xs[j - 1] > v) {
				xs[j] = xs[j - 1];
				j--;
			}
			xs[j] = v;
		}
		const int64_t row = y * w;
		for (int64_t k = 0; k + 1 < (int64_t)xs.size(); k += 2) {
			const int64_t start = maxi(0, ceili(xs[k] - 0.5));
			const int64_t end = mini(w - 1, floori(xs[k + 1] - 0.5));
			for (int64_t x = start; x <= end; x++) {
				mask[row + x] = value;
			}
		}
	}
}

struct Geometry {
	int64_t width = 0, height = 0;
	std::vector<uint8_t> land, material, pit, pit_side;
	std::vector<float> crack;
	Dictionary shape;
	std::vector<double> keep_clear;
	int64_t side = 0;
	int threads = 1;

	Geometry(const Dictionary &shape_data, const PackedFloat64Array &placed, const PackedFloat64Array &clear, int width_of_threads) {
		shape = shape_data;
		threads = width_of_threads;
		const Array size = arr(shape, "size");
		width = (int64_t)at(size, 0);
		height = (int64_t)at(size, 1);
		const int64_t n = width * height;
		land.assign(n, 0);
		crack.assign(n, 0.0f);
		material.assign(n, 0);
		pit.assign(n, 0);
		pit_side.assign(n, 0);
		const Array keep = arr(shape, "keep_clear");
		for (int64_t i = 0; i < keep.size(); i++) {
			const Array c = keep[i];
			keep_clear.push_back(at(c, 0));
			keep_clear.push_back(at(c, 1));
			keep_clear.push_back(at(c, 2));
		}
		for (int64_t i = 0; i < placed.size(); i++) {
			keep_clear.push_back(placed[i]);
		}
		const Array outlines = arr(shape, "outlines");
		for (int64_t i = 0; i < outlines.size(); i++) {
			fill_polygon(land, width, height, outline_points(outlines[i]), 1);
		}
		if (shape.has("frame")) {
			frame(dict(shape, "frame"), clear);
		}
		const Array areas = arr(shape, "areas");
		for (int64_t i = 0; i < areas.size(); i++) {
			std::vector<uint8_t> area_mask(n, 0);
			fill_polygon(area_mask, width, height, outline_points(areas[i], 3.0), 1);
			for (int64_t p = 0; p < n; p++) {
				if (area_mask[p] != 0 && land[p] != 0) {
					material[p] = (uint8_t)(i + 1);
				}
			}
		}
		const Array pits = arr(shape, "pits");
		for (int64_t i = 0; i < pits.size(); i++) {
			std::vector<uint8_t> mask(n, 0);
			fill_polygon(mask, width, height, outline_points(pits[i]), 1);
			for (int64_t p = 0; p < n; p++) {
				if (mask[p] != 0) {
					land[p] = 0;
					pit[p] = 1;
					pit_side[p] = 1;
				}
			}
		}
		const Array cracks = arr(shape, "cracks");
		for (int64_t i = 0; i < cracks.size(); i++) {
			const Dictionary spec = cracks[i];
			if (spec.has("pit")) {
				crack_from_pit(spec);
			} else {
				crack_from_outline(spec);
			}
		}
	}

	void frame(const Dictionary &spec, const PackedFloat64Array &clear) {
		const int64_t w = width, h = height;
		const double inset = num(spec, "inset", 0.0);
		const double corner = num(spec, "corner", 16.0);
		const Array wander = arr(spec, "wander");
		const double wander_in = at(wander, 0), wander_out = at(wander, 1);
		const std::vector<double> scales = spec.has("rough") ? numbers(arr(spec, "rough")) : std::vector<double>{ 40.0, 14.0, 5.0 };
		const int64_t seed = inum(spec, "seed", 0);
		std::vector<double> pins, bays;
		const Array pin_list = arr(spec, "pins");
		for (int64_t i = 0; i < pin_list.size(); i++) {
			const Array pin = pin_list[i];
			for (int64_t k = 0; k < 4; k++) {
				pins.push_back(at(pin, k));
			}
		}
		const Array bay_list = arr(spec, "bays");
		for (int64_t i = 0; i < bay_list.size(); i++) {
			const Array bay = bay_list[i];
			for (int64_t k = 0; k < 3; k++) {
				bays.push_back(at(bay, k));
			}
		}
		const std::vector<double> bay_scales{ 12.0, 5.0 };
		const double cx = (double)w / 2.0, cy = (double)h / 2.0;
		const double hw = (double)w / 2.0 - inset - corner, hh = (double)h / 2.0 - inset - corner;
		const double reach = maxf(wander_in, wander_out) + 2.0;
		const double *clear_p = clear.ptr();
		const int64_t clear_n = clear.size();
		uint8_t *out = land.data();
		jobs::for_spans(h, ROWS_A_SPAN, threads, [&](int64_t, int64_t y_from, int64_t y_to) {
			for (int64_t y = y_from; y < y_to; y++) {
				for (int64_t x = 0; x < w; x++) {
					const int64_t p = y * w + x;
					if (x < CELL || y < CELL || x >= w - CELL || y >= h - CELL) {
						out[p] = 0;
						continue;
					}
					const double px = (double)x + 0.5, py = (double)y + 0.5;
					const double qx = absf(px - cx) - hw, qy = absf(py - cy) - hh;
					const double inward = -(length_of(maxf(qx, 0.0), maxf(qy, 0.0)) + minf(maxf(qx, qy), 0.0) - corner);
					double pinned = 1.0;
					for (size_t k = 0; k < pins.size(); k += 4) {
						const double dx = maxf(maxf(pins[k] - px, 0.0), px - pins[k + 2]);
						const double dy = maxf(maxf(pins[k + 1] - py, 0.0), py - pins[k + 3]);
						pinned = minf(pinned, length_of(dx, dy) / PIN_EASE);
					}
					bool inside = inward > 0.0;
					if (absf(inward) < reach && pinned > 0.0) {
						const double n = maxf(-1.0, minf(1.0, (fbm2(px, py, scales, seed) - 0.5) * 2.6));
						inside = inward + (n > 0.0 ? n * wander_out : n * wander_in) * minf(1.0, pinned) > 0.0;
					}
					if (!inside && pinned >= 1.0) {
						for (size_t k = 0; k < bays.size(); k += 3) {
							const double br = bays[k + 2];
							if (length_of(px - bays[k], py - bays[k + 1]) + (fbm2(px, py, bay_scales, seed + 7) - 0.5) * br * 0.6 < br) {
								inside = true;
								break;
							}
						}
					}
					if (!inside && pinned >= 1.0) {
						for (int64_t k = 0; k + 2 < clear_n; k += 3) {
							if (length_of(px - clear_p[k], py - clear_p[k + 1]) < clear_p[k + 2]) {
								inside = true;
								break;
							}
						}
					}
					if (inside) {
						out[p] = 1;
					}
				}
			}
		});
	}

	void crack_from_pit(const Dictionary &spec) {
		const Dictionary pit_spec = arr(shape, "pits")[(int64_t)num(spec, "pit", 0.0)];
		const Array centre = arr(pit_spec, "centre");
		const double a = num(spec, "angle", 0.0) * TURN;
		double x = at(centre, 0), y = at(centre, 1);
		while (x >= 0.0 && x < (double)width && y >= 0.0 && y < (double)height && land[(int64_t)y * width + (int64_t)x] == 0) {
			x += std::cos(a);
			y += std::sin(a);
		}
		const int64_t seed = inum(spec, "seed", 0);
		const double heading = a + (unit2(seed, 3) - 0.5) * 0.4;
		side = 1;
		walk(x - std::cos(a) * 4.0, y - std::sin(a) * 4.0, heading, num(spec, "width", 0.0), inum(spec, "length", 0), seed, 0);
		side = 0;
	}

	bool near_keep_clear(double x, double y) const {
		for (size_t k = 0; k + 2 < keep_clear.size(); k += 3) {
			if (length_of(x - keep_clear[k], y - keep_clear[k + 1]) < keep_clear[k + 2]) {
				return true;
			}
		}
		return false;
	}

	void crack_from_outline(const Dictionary &spec) {
		const Dictionary outline = arr(shape, "outlines")[inum(spec, "outline", 0)];
		const Array centre = arr(outline, "centre");
		const Array radii = arr(outline, "radii");
		const double rx = at(radii, 0), ry = at(radii, 1);
		const double a = num(spec, "angle", 0.0) * TURN;
		double x = at(centre, 0), y = at(centre, 1);
		while (x >= 0.0 && x < (double)width && y >= 0.0 && y < (double)height && land[(int64_t)y * width + (int64_t)x] != 0) {
			x += std::cos(a);
			y += std::sin(a) * ry / rx;
		}
		const int64_t seed = inum(spec, "seed", 0);
		const double heading = a + HALF_TURN + (unit2(seed, 3) - 0.5) * 0.4;
		walk(x - std::cos(a) * 4.0, y - std::sin(a) * 4.0, heading, num(spec, "width", 0.0), inum(spec, "length", 0), seed, 0);
	}

	void walk(double x, double y, double heading, double crack_width, int64_t steps, int64_t seed, int64_t depth) {
		for (int64_t i = 0; i < steps; i++) {
			heading += std::sin((double)i * 0.37 + (double)seed) * 0.22 + (unit2(seed, i) - 0.5) * 0.25;
			x += std::cos(heading) * 3.0;
			y += std::sin(heading) * 3.0;
			if (near_keep_clear(x, y) || !(x >= 0.0 && x < (double)width && y >= 0.0 && y < (double)height)) {
				return;
			}
			const int64_t here = (int64_t)y * width + (int64_t)x;
			if (i > 6 && land[here] == 0 && (double)crack[here] == 0.0) {
				return;
			}
			const double w = crack_width * std::pow(maxf(0.0, 1.0 - (double)i / (double)steps), 1.6);
			if (w < 1.5) {
				return;
			}
			stamp(x, y, w);
			if (depth < 2 && i > 4 && hash3(seed, i, 7) % 26 == 0) {
				const double turn = hash3(seed, i, 8) % 2 != 0 ? 0.7 : -0.7;
				walk(x, y, heading + turn, w * 0.9, (int64_t)((double)(steps - i) * 0.6), seed * 31 + i, depth + 1);
			}
		}
	}

	void stamp(double x, double y, double w) {
		const double r = w * 0.5;
		const int64_t reach = (int64_t)(r + 6.0);
		const int64_t seed = inum(shape, "seed", 0);
		static const std::vector<double> wide_scales{ 12.0, 6.0 };
		static const std::vector<double> fine_scales{ 4.0, 2.0 };
		for (int64_t py = maxi(0, (int64_t)y - reach); py < mini(height, (int64_t)y + reach + 1); py++) {
			for (int64_t px = maxi(0, (int64_t)x - reach); px < mini(width, (int64_t)x + reach + 1); px++) {
				const double d = length_of((double)px + 0.5 - x, (double)py + 0.5 - y);
				if (d > r + 5.0) {
					continue;
				}
				double edge = r;
				if (w > 6.0) {
					edge += minf(r * 0.9, 4.0) * 2.0 * (fbm2((double)px, (double)py, wide_scales, seed + 310) - 0.5);
					edge += 1.5 * (fbm2((double)px, (double)py, fine_scales, seed + 311) - 0.5);
				}
				if (d <= edge) {
					const int64_t p = py * width + px;
					if (land[p] != 0 || (double)crack[p] > 0.0) {
						land[p] = 0;
						if (w > (double)crack[p]) {
							crack[p] = (float)w;
						}
						if (side != 0) {
							pit_side[p] = 1;
						}
					}
				}
			}
		}
	}
};

// -- GroundMaterial --

struct Material {
	int64_t base = 0, cols = 0;
	std::vector<double> patch_map;
	bool has_patches = false;
	int64_t patch_colour = 0;
	double patch_above = 2.0;
	std::vector<int64_t> speckle_colours;
	std::vector<double> speckle_shares;
	int64_t seed = 0;
	bool has_slabs = false;
	double slab_size = 0.0, slab_jitter = 0.8, slab_squash = 1.0;
	int64_t slab_tone = 0;
	double slab_vary = 0.0;
	int64_t joint = 0;
	double joint_width = 1.2;
	bool has_light = false;
	int64_t light = 0;
	double light_width = 1.0;
	bool has_edge = false;
	int64_t edge_colour = 0;
	double edge_reach = 0.0, edge_most = 0.6;
	std::vector<double> edge_scales{ 10.0, 4.0 };
	bool has_strokes = false;
	int64_t stroke_colour = 0;
	double stroke_spacing = 10.0, stroke_share = 0.4, stroke_inner = 24.0;
	double centre_x = 0.0, centre_y = 0.0;

	Material(const Dictionary &spec, int64_t index, int64_t room_seed, int64_t w, int64_t h, double cx, double cy, const Dictionary &palette) {
		base = colour_of(spec["base"], palette);
		cols = w / STEP + 2;
		const int64_t rows = h / STEP + 2;
		if (spec.has("patches")) {
			const Dictionary patches = dict(spec, "patches");
			has_patches = true;
			const int64_t patch_seed = room_seed * 13 + index * 101 + inum(patches, "seed", 0);
			const std::vector<double> scales = numbers(arr(patches, "scales"));
			patch_map.assign(rows * cols, 0.0);
			for (int64_t y = 0; y < rows; y++) {
				for (int64_t x = 0; x < cols; x++) {
					patch_map[y * cols + x] = fbm2((double)(x * STEP), (double)(y * STEP), scales, patch_seed);
				}
			}
			patch_colour = colour_of(patches["colour"], palette);
			patch_above = num(patches, "above", 0.5);
		}
		const Array speckle = arr(spec, "speckle");
		for (int64_t i = 0; i < speckle.size(); i++) {
			const Array pair = speckle[i];
			speckle_colours.push_back(colour_of(pair[0], palette));
			speckle_shares.push_back(at(pair, 1));
		}
		seed = room_seed * 7 + index * 31;
		if (spec.has("slabs")) {
			const Dictionary slabs = dict(spec, "slabs");
			has_slabs = true;
			slab_size = num(slabs, "size", 0.0);
			slab_jitter = num(slabs, "jitter", 0.8);
			slab_squash = num(slabs, "squash", 1.0);
			slab_tone = slabs.has("tone") ? colour_of(slabs["tone"], palette) : base;
			slab_vary = num(slabs, "vary", 0.0);
			joint = colour_of(slabs["joint"], palette);
			joint_width = num(slabs, "joint_width", 1.2);
			has_light = slabs.has("light");
			light = has_light ? colour_of(slabs["light"], palette) : 0;
			light_width = num(slabs, "light_width", 1.0);
		}
		if (spec.has("toward_edge")) {
			const Dictionary edge = dict(spec, "toward_edge");
			has_edge = true;
			edge_colour = colour_of(edge["colour"], palette);
			edge_reach = num(edge, "reach", 0.0);
			edge_most = num(edge, "most", 0.6);
			if (edge.has("scales")) {
				edge_scales = numbers(arr(edge, "scales"));
			}
		}
		if (spec.has("strokes")) {
			const Dictionary strokes = dict(spec, "strokes");
			has_strokes = true;
			stroke_colour = colour_of(strokes["colour"], palette);
			stroke_spacing = num(strokes, "spacing", 10.0);
			stroke_share = num(strokes, "share", 0.4);
			stroke_inner = num(strokes, "inner", 24.0);
			centre_x = cx;
			centre_y = cy;
		}
	}

	int64_t colour_at(int64_t x, int64_t y, double edge_distance) const {
		int64_t rgb = base;
		if (has_slabs) {
			rgb = slab(x, y);
		}
		if (has_patches && bilinear((double)x / (double)STEP, (double)y / (double)STEP) > patch_above) {
			rgb = patch_colour;
		}
		if (has_strokes) {
			rgb = stroke(x, y, rgb);
		}
		double roll = unit3(x, y, 4041);
		for (size_t i = 0; i < speckle_shares.size(); i++) {
			if (roll < speckle_shares[i]) {
				rgb = speckle_colours[i];
				break;
			}
			roll -= speckle_shares[i];
		}
		if (has_edge && edge_distance < edge_reach) {
			const double near = 1.0 - edge_distance / edge_reach;
			const double grit = fbm2((double)x, (double)y, edge_scales, seed + 77);
			const double share = minf(edge_most, maxf(0.0, near * 1.6 * grit - 0.25));
			if (share > 0.08) {
				rgb = mix(rgb, edge_colour, share);
			}
		}
		return rgb;
	}

	int64_t slab(int64_t x, int64_t y) const {
		const double s = slab_size, sq = slab_squash;
		const double fx = ((double)x + 0.5) / s, fy = ((double)y + 0.5) / (s * sq);
		const int64_t cx0 = floori(fx), cy0 = floori(fy);
		double best = 1e18, second = 1e18, best_dy = 0.0;
		int64_t best_cx = 0, best_cy = 0;
		for (int64_t cy = cy0 - 1; cy < cy0 + 2; cy++) {
			const double shift = cy % 2 != 0 ? 0.5 : 0.0;
			for (int64_t cx = cx0 - 1; cx < cx0 + 2; cx++) {
				const double px = ((double)cx + shift + 0.5 + (unit4(seed, cx, cy, 1) - 0.5) * slab_jitter) * s;
				const double py = ((double)cy + 0.5 + (unit4(seed, cx, cy, 2) - 0.5) * slab_jitter) * s * sq;
				const double dx = (double)x + 0.5 - px;
				const double dy = ((double)y + 0.5 - py) / sq;
				const double d = dx * dx + dy * dy;
				if (d < best) {
					second = best;
					best = d;
					best_cx = cx;
					best_cy = cy;
					best_dy = dy;
				} else if (d < second) {
					second = d;
				}
			}
		}
		const double edge = std::sqrt(second) - std::sqrt(best);
		if (edge < joint_width) {
			return joint;
		}
		int64_t rgb = mix(base, slab_tone, unit4(seed, best_cx, best_cy, 3) * slab_vary);
		if (has_light && edge < joint_width + light_width && best_dy < 0.0) {
			rgb = light;
		}
		return rgb;
	}

	int64_t stroke(int64_t x, int64_t y, int64_t rgb) const {
		const double dx = (double)x + 0.5 - centre_x;
		const double dy = (double)y + 0.5 - centre_y;
		double r = std::sqrt(dx * dx + dy * dy);
		if (r < stroke_inner) {
			return rgb;
		}
		const double turn = fposmod_f(std::atan2(dy, dx) / TURN, 1.0);
		r += (noise1(turn * 6.0, seed + 9, 6) - 0.5) * stroke_spacing * 0.8;
		const int64_t ring = floori(r / stroke_spacing + 0.5);
		if (absf(r - (double)ring * stroke_spacing) >= 0.5) {
			return rgb;
		}
		const int64_t pieces = maxi(3, round_even(TURN * (double)ring * stroke_spacing / 40.0));
		if (noise1(turn * (double)pieces, seed + 31 * ring, pieces) < 1.0 - stroke_share) {
			return rgb;
		}
		return mix(rgb, stroke_colour, 0.5);
	}

	double bilinear(double fx, double fy) const {
		const int64_t ix = (int64_t)fx, iy = (int64_t)fy;
		const double tx = fx - (double)ix, ty = fy - (double)iy;
		const int64_t i = iy * cols + ix;
		return (patch_map[i] * (1.0 - tx) + patch_map[i + 1] * tx) * (1.0 - ty) + (patch_map[i + cols] * (1.0 - tx) + patch_map[i + cols + 1] * tx) * ty;
	}
};

// -- GroundWalls --

std::vector<uint8_t> walls_draw(int64_t w, int64_t h, const std::vector<uint8_t> &floor, const std::vector<uint8_t> &wall, const Dictionary &style,
		const Dictionary &palette, int64_t seed) {
	std::vector<uint8_t> image(w * h * 4, 0);
	const Dictionary top = dict(style, "top");
	const Dictionary face = dict(style, "face");
	if (top.is_empty() && face.is_empty()) {
		return image;
	}
	std::vector<uint8_t> rows(w * h, 0);
	if (!face.is_empty()) {
		const int64_t face_height = inum(face, "height", 0);
		for (int64_t p = w; p < w * h; p++) {
			if (floor[p] == 0 || wall[p - w] == 0) {
				continue;
			}
			const int64_t x = p % w, y = p / w;
			for (int64_t k = 1; k < face_height + 2; k++) {
				const int64_t yy = y - k;
				if (yy < 0 || wall[yy * w + x] == 0) {
					break;
				}
				rows[yy * w + x] = (uint8_t)k;
			}
		}
		const int64_t course = inum(face, "course", 1), block = inum(face, "block", 1);
		const Array shades = arr(face, "shades");
		const int64_t low = colour_of(shades[0], palette), high = colour_of(shades[1], palette);
		const int64_t joint = colour_of(face["joint"], palette), light = colour_of(face["light"], palette), cap = colour_of(face["cap"], palette);
		for (int64_t p = 0; p < w * h; p++) {
			const int64_t k = rows[p];
			if (k == 0) {
				continue;
			}
			const int64_t x = p % w;
			int64_t rgb;
			if (k == face_height + 1) {
				rgb = cap;
			} else if (k == face_height) {
				rgb = light;
			} else {
				const int64_t row = (k - 1) / course;
				if ((k - 1) % course == course - 1 || (x + row * (block / 2)) % block == 0) {
					rgb = joint;
				} else {
					const double n = noise2((double)(x / block * block + row * 7), (double)row, 3.0, seed + 41);
					rgb = mix(low, high, minf(1.0, (double)(k - 1) / (double)face_height * 0.8 + n * 0.3));
				}
			}
			put(image, p, rgb);
		}
	}
	if (!top.is_empty()) {
		const Array shades = arr(top, "shades");
		const int64_t dark = colour_of(shades[0], palette), stone = colour_of(shades[1], palette);
		const int64_t joint = colour_of(top["joint"], palette), rim = colour_of(top["rim"], palette), deep = colour_of(top["deep"], palette);
		const Array fade_range = arr(top, "fade");
		const double near = at(fade_range, 0), far = at(fade_range, 1);
		std::vector<int32_t> dist(w * h, 0);
		std::vector<int64_t> frontier, next;
		for (int64_t p = 0; p < w * h; p++) {
			const int64_t x = p % w, y = p / w;
			const bool touches = (x + 1 < w && floor[p + 1] != 0) || (x > 0 && floor[p - 1] != 0) || (y + 1 < h && floor[p + w] != 0) ||
					(y > 0 && floor[p - w] != 0);
			if (wall[p] != 0 && touches) {
				frontier.push_back(p);
				dist[p] = 1;
			}
		}
		int64_t d = 1;
		while (!frontier.empty() && (double)d < far + 2.0) {
			d++;
			next.clear();
			for (const int64_t q : frontier) {
				const int64_t x = q % w, y = q / w;
				for (int64_t way = 0; way < 4; way++) {
					const int64_t nx = x + WAY_X[way], ny = y + WAY_Y[way];
					if (nx >= 0 && nx < w && ny >= 0 && ny < h) {
						const int64_t r = ny * w + nx;
						if (wall[r] != 0 && dist[r] == 0) {
							dist[r] = (int32_t)d;
							next.push_back(r);
						}
					}
				}
			}
			frontier.swap(next);
		}
		for (int64_t p = 0; p < w * h; p++) {
			if (wall[p] == 0 || rows[p] != 0) {
				continue;
			}
			const int64_t x = p % w, y = p / w;
			const int64_t dd = dist[p] != 0 ? dist[p] : (int64_t)far + 2;
			int64_t rgb;
			if (dd == 1) {
				rgb = rim;
			} else {
				const double fine = noise2((double)x, (double)y, 3.0, seed + 51);
				const double rough = noise2((double)x, (double)y, 9.0, seed + 52);
				rgb = fine < 0.28 ? joint : mix(dark, stone, rough);
			}
			const double fade = minf(1.0, maxf(0.0, ((double)dd - near) / maxf(1.0, far - near)));
			put(image, p, mix(rgb, deep, fade));
		}
	}
	return image;
}

std::vector<float> box_blur(const std::vector<float> &src, int64_t bw, int64_t bh, int64_t radius, bool along_rows) {
	std::vector<float> out(bw * bh, 0.0f);
	const double span = (double)(2 * radius + 1);
	if (along_rows) {
		for (int64_t y = 0; y < bh; y++) {
			const int64_t row = y * bw;
			double total = 0.0;
			for (int64_t x = -radius; x < radius + 1; x++) {
				if (x >= 0 && x < bw) {
					total += (double)src[row + x];
				}
			}
			for (int64_t x = 0; x < bw; x++) {
				out[row + x] = (float)(total / span);
				if (x - radius >= 0) {
					total -= (double)src[row + x - radius];
				}
				if (x + radius + 1 < bw) {
					total += (double)src[row + x + radius + 1];
				}
			}
		}
	} else {
		for (int64_t x = 0; x < bw; x++) {
			double total = 0.0;
			for (int64_t y = -radius; y < radius + 1; y++) {
				if (y >= 0 && y < bh) {
					total += (double)src[y * bw + x];
				}
			}
			for (int64_t y = 0; y < bh; y++) {
				out[y * bw + x] = (float)(total / span);
				if (y - radius >= 0) {
					total -= (double)src[(y - radius) * bw + x];
				}
				if (y + radius + 1 < bh) {
					total += (double)src[(y + radius + 1) * bw + x];
				}
			}
		}
	}
	return out;
}

// -- GroundDrawing --

struct Drawing {
	int64_t w = 0, h = 0;
	Dictionary shape, palette;
	Dictionary styles[2];
	int64_t style_of_side[2] = { 0, 0 };
	int64_t deeps[2] = { 0, 0 };
	Array grounds;
	std::vector<uint8_t> land, land_before, material, pit, pit_side, solid, side;
	std::vector<float> crack, t;
	std::vector<uint8_t> floor_image, under, glow, wall_art;
	int64_t glow_w = 0, glow_h = 0;
	Array rims, drips;
	PackedInt32Array rim_sides, drip_sides;
	PackedStringArray drip_colours;
	std::vector<int32_t> band;
	std::vector<int64_t> seam;
	std::vector<std::vector<int64_t>> rim_paths;
	std::vector<int64_t> rim_every, rim_path_sides;
	bool mirror_x = false, mirror_y = false;
	int threads = 1;

	void run(const Dictionary &spec) {
		// How many threads the per-pixel loops run on: the spec's `threads`, else the machine's (jobs.h).
		const int64_t asked = spec.has("threads") ? (int64_t)spec["threads"] : 0;
		threads = asked > 0 ? (int)mini(asked, jobs::MAX_WIDTH) : jobs::default_width();
		shape = spec["shape"];
		palette = spec["palette"];
		const Array given = spec["styles"];
		styles[0] = given[0];
		styles[1] = given[1];
		style_of_side[1] = spec.has("pit_style") && (bool)spec["pit_style"] ? 1 : 0;
		for (int64_t i = 0; i < 2; i++) {
			deeps[i] = colour_of(styles[i]["deep"], palette);
		}
		grounds = spec["grounds"];
		const PackedFloat64Array placed = spec.has("placed") ? (PackedFloat64Array)spec["placed"] : PackedFloat64Array();
		const PackedFloat64Array clear = spec.has("clear") ? (PackedFloat64Array)spec["clear"] : PackedFloat64Array();
		Geometry geometry(shape, placed, clear, threads);
		w = geometry.width;
		h = geometry.height;
		land.swap(geometry.land);
		crack.swap(geometry.crack);
		material.swap(geometry.material);
		pit.swap(geometry.pit);
		pit_side.swap(geometry.pit_side);
		land_before = land;
		const int64_t n = w * h;
		solid.assign(n, 0);
		for (int64_t p = 0; p < n; p++) {
			if (land[p] != 0 || ((double)crack[p] > 0.0 && (double)crack[p] < (double)CELL)) {
				solid[p] = 1;
			}
		}
		drop_slivers();
		if (shape.has("frame")) {
			trim_to_reach();
			drop_slivers();
		}
		mirror(spec.has("mirror_x") && (bool)spec["mirror_x"], spec.has("mirror_y") && (bool)spec["mirror_y"]);
		sides();
		const double fulls[2] = { (double)styles[0]["full_width"], (double)styles[1]["full_width"] };
		std::vector<float> near(n, 0.0f);
		for (int64_t p = 0; p < n; p++) {
			const double cw = (double)crack[p];
			if (cw > 0.0) {
				const int64_t px = p % w, py = p / w;
				for (int64_t dy = -4; dy < 5; dy++) {
					for (int64_t dx = -4 + absi(dy); dx < 5 - absi(dy); dx++) {
						const int64_t x = px + dx, y = py + dy;
						if (x >= 0 && x < w && y >= 0 && y < h && (double)near[y * w + x] < cw) {
							near[y * w + x] = (float)cw;
						}
					}
				}
			}
		}
		t.assign(n, 1.0f);
		for (int64_t p = 0; p < n; p++) {
			if ((double)near[p] > 0.0) {
				const double full = fulls[side[p]];
				t[p] = (float)minf(1.0, maxf(0.0, ((double)near[p] - 1.5) / (full - 1.5)));
			}
		}
		floor_image.assign(n * 4, 0);
		under.assign(n * 4, 0);
		band.assign(n, -1);
		draw_floor();
		trace_rims();
		spread_bands();
		draw_edges();
		draw_under();
		draw_glow();
		draw_wall_art();
	}

	static std::vector<uint8_t> mirrored(const std::vector<uint8_t> &mask, int64_t w, int64_t h, bool along_x, bool along_y) {
		std::vector<uint8_t> out(w * h);
		for (int64_t y = 0; y < h; y++) {
			const int64_t from_y = along_y ? h - 1 - y : y;
			for (int64_t x = 0; x < w; x++) {
				out[y * w + x] = mask[from_y * w + (along_x ? w - 1 - x : x)];
			}
		}
		return out;
	}

	void mirror(bool along_x, bool along_y) {
		mirror_x = along_x;
		mirror_y = along_y;
		if (!along_x && !along_y) {
			return;
		}
		land = mirrored(land, w, h, along_x, along_y);
		land_before = mirrored(land_before, w, h, along_x, along_y);
		material = mirrored(material, w, h, along_x, along_y);
		pit = mirrored(pit, w, h, along_x, along_y);
		pit_side = mirrored(pit_side, w, h, along_x, along_y);
		solid = mirrored(solid, w, h, along_x, along_y);
		std::vector<float> flipped(w * h);
		for (int64_t y = 0; y < h; y++) {
			const int64_t from_y = along_y ? h - 1 - y : y;
			for (int64_t x = 0; x < w; x++) {
				flipped[y * w + x] = crack[from_y * w + (along_x ? w - 1 - x : x)];
			}
		}
		crack.swap(flipped);
	}

	void sides() {
		side = pit_side;
		bool any = false;
		for (const uint8_t v : pit_side) {
			if (v != 0) {
				any = true;
				break;
			}
		}
		if (!any) {
			return;
		}
		std::vector<uint8_t> seen(w * h, 0);
		std::vector<int64_t> frontier, next;
		for (int64_t p = 0; p < w * h; p++) {
			if (land_before[p] == 0) {
				seen[p] = 1;
				frontier.push_back(p);
			}
		}
		for (int64_t step = 0; step < SIDE_REACH; step++) {
			next.clear();
			for (const int64_t q : frontier) {
				const int64_t x = q % w, y = q / w;
				for (int64_t way = 0; way < 4; way++) {
					const int64_t nx = x + WAY_X[way], ny = y + WAY_Y[way];
					if (nx >= 0 && nx < w && ny >= 0 && ny < h) {
						const int64_t r = ny * w + nx;
						if (seen[r] == 0) {
							seen[r] = 1;
							side[r] = side[q];
							next.push_back(r);
						}
					}
				}
			}
			frontier.swap(next);
			if (frontier.empty()) {
				break;
			}
		}
	}

	void drop_slivers() {
		std::vector<uint8_t> seen(w * h, 0);
		std::vector<int64_t> piece;
		for (int64_t p0 = 0; p0 < w * h; p0++) {
			if (solid[p0] == 0 || seen[p0] != 0) {
				continue;
			}
			piece.clear();
			piece.push_back(p0);
			seen[p0] = 1;
			size_t k = 0;
			bool open_cell = false;
			while (k < piece.size()) {
				const int64_t q = piece[k];
				k++;
				const int64_t x = q % w, y = q / w;
				if (x % CELL == CELL / 2 && y % CELL == CELL / 2) {
					open_cell = true;
				}
				for (int64_t way = 0; way < 4; way++) {
					const int64_t nx = x + WAY_X[way], ny = y + WAY_Y[way];
					if (nx >= 0 && nx < w && ny >= 0 && ny < h) {
						const int64_t r = ny * w + nx;
						if (solid[r] != 0 && seen[r] == 0) {
							seen[r] = 1;
							piece.push_back(r);
						}
					}
				}
			}
			if (!open_cell) {
				for (const int64_t q : piece) {
					solid[q] = 0;
					land[q] = 0;
				}
			}
		}
	}

	void trim_to_reach() {
		const int64_t cols = w / CELL, rows = h / CELL;
		const int64_t r2 = TRIM_ROUND * TRIM_ROUND;
		std::vector<uint8_t> open(cols * rows, 0), fits(cols * rows, 0);
		while (true) {
			for (int64_t r = 0; r < rows; r++) {
				for (int64_t c = 0; c < cols; c++) {
					open[r * cols + c] = solid[(r * CELL + CELL / 2) * w + c * CELL + CELL / 2];
				}
			}
			for (int64_t r = 0; r < rows; r++) {
				for (int64_t c = 0; c < cols; c++) {
					uint8_t all = 1;
					for (int64_t dr = -1; dr < 2; dr++) {
						for (int64_t dc = -1; dc < 2; dc++) {
							const int64_t rr = r + dr, cc = c + dc;
							if (rr < 0 || rr >= rows || cc < 0 || cc >= cols || open[rr * cols + cc] == 0) {
								all = 0;
							}
						}
					}
					fits[r * cols + c] = all;
				}
			}
			int64_t trimmed = 0;
			for (int64_t r = 0; r < rows; r++) {
				for (int64_t c = 0; c < cols; c++) {
					if (open[r * cols + c] == 0) {
						continue;
					}
					bool near_fit = false;
					for (int64_t dr = -1; dr < 2; dr++) {
						for (int64_t dc = -1; dc < 2; dc++) {
							const int64_t rr = r + dr, cc = c + dc;
							if (rr >= 0 && rr < rows && cc >= 0 && cc < cols && fits[rr * cols + cc] != 0) {
								near_fit = true;
							}
						}
					}
					if (near_fit) {
						continue;
					}
					trimmed++;
					const int64_t mx = c * CELL + CELL / 2, my = r * CELL + CELL / 2;
					for (int64_t y = maxi(0, my - TRIM_ROUND); y < mini(h, my + TRIM_ROUND + 1); y++) {
						for (int64_t x = maxi(0, mx - TRIM_ROUND); x < mini(w, mx + TRIM_ROUND + 1); x++) {
							if ((x - mx) * (x - mx) + (y - my) * (y - my) <= r2) {
								solid[y * w + x] = 0;
								land[y * w + x] = 0;
							}
						}
					}
				}
			}
			if (trimmed == 0) {
				return;
			}
		}
	}

	bool is_edge(int64_t p) const {
		if (land[p] == 0) {
			return false;
		}
		const int64_t x = p % w, y = p / w;
		return x + 1 >= w || land[p + 1] == 0 || x == 0 || land[p - 1] == 0 || y + 1 >= h || land[p + w] == 0 || y == 0 || land[p - w] == 0;
	}

	void draw_floor() {
		const int64_t seed = inum(shape, "seed", 0);
		std::vector<double> centres{ (double)w / 2.0, (double)h / 2.0 };
		const Array areas = arr(shape, "areas");
		for (int64_t i = 0; i < areas.size(); i++) {
			const Array centre = arr(areas[i], "centre");
			const double x = at(centre, 0), y = at(centre, 1);
			centres.push_back(mirror_x ? (double)w - x : x);
			centres.push_back(mirror_y ? (double)h - y : y);
		}
		std::vector<Material> mats;
		int64_t reach = 0;
		for (int64_t k = 0; k < grounds.size(); k++) {
			mats.emplace_back((Dictionary)grounds[k], k, seed, w, h, centres[k * 2], centres[k * 2 + 1], palette);
			if (mats.back().has_edge) {
				reach = maxi(reach, (int64_t)mats.back().edge_reach);
			}
		}
		std::vector<int32_t> edge_distance;
		if (reach > 0) {
			edge_distance.assign(w * h, (int32_t)(reach + 1));
			std::vector<int64_t> frontier, next;
			for (int64_t p = 0; p < w * h; p++) {
				if (is_edge(p)) {
					frontier.push_back(p);
					edge_distance[p] = 0;
				}
			}
			for (int64_t d = 1; d < reach + 1; d++) {
				next.clear();
				for (const int64_t q : frontier) {
					const int64_t x = q % w, y = q / w;
					for (int64_t way = 0; way < 4; way++) {
						const int64_t nx = x + WAY_X[way], ny = y + WAY_Y[way];
						if (nx >= 0 && nx < w && ny >= 0 && ny < h) {
							const int64_t r = ny * w + nx;
							if (land[r] != 0 && edge_distance[r] > d) {
								edge_distance[r] = (int32_t)d;
								next.push_back(r);
							}
						}
					}
				}
				frontier.swap(next);
			}
		}
		jobs::for_spans(h, ROWS_A_SPAN, threads, [&](int64_t, int64_t y_from, int64_t y_to) {
			for (int64_t p = y_from * w; p < y_to * w; p++) {
				if (solid[p] == 0) {
					continue;
				}
				if (land[p] == 0) {
					put(floor_image, p, deeps[side[p]]);
					continue;
				}
				const double ed = edge_distance.empty() ? 1e9 : (double)edge_distance[p];
				put(floor_image, p, mats[material[p]].colour_at(p % w, p / w, ed));
			}
		});
	}

	std::vector<int64_t> moore(int64_t sx, int64_t sy) const {
		static const int64_t ways_x[8] = { 1, 1, 0, -1, -1, -1, 0, 1 };
		static const int64_t ways_y[8] = { 0, 1, 1, 1, 0, -1, -1, -1 };
		const int64_t start = sy * w + sx;
		std::vector<int64_t> path{ start };
		int64_t x = sx, y = sy, back = 6, first = -1;
		for (int64_t i = 0; i < w * h * 2; i++) {
			int64_t step = -1;
			for (int64_t k = 0; k < 8; k++) {
				const int64_t d = (back + 1 + k) % 8;
				const int64_t nx = x + ways_x[d], ny = y + ways_y[d];
				if (nx >= 0 && nx < w && ny >= 0 && ny < h && solid[ny * w + nx] != 0) {
					step = d;
					break;
				}
			}
			if (step < 0) {
				break;
			}
			if (y * w + x == start && step == first) {
				break;
			}
			if (first < 0) {
				first = step;
			}
			back = (step + 4) % 8;
			x += ways_x[step];
			y += ways_y[step];
			if (y * w + x != start) {
				path.push_back(y * w + x);
			}
		}
		return path;
	}

	void trace_rims() {
		std::vector<uint8_t> seen(w * h, 0);
		for (int64_t p = 0; p < w * h; p++) {
			if (solid[p] == 0 || seen[p] != 0) {
				continue;
			}
			const int64_t y = p / w;
			if (y > 0 && solid[p - w] != 0) {
				continue;
			}
			std::vector<int64_t> path = moore(p % w, y);
			for (const int64_t q : path) {
				seen[q] = 1;
			}
			if (path.size() < 16) {
				continue;
			}
			int64_t area = 0;
			for (size_t i = 0; i < path.size(); i++) {
				const int64_t a = path[i], b = path[(i + 1) % path.size()];
				area += (a % w) * (b / w) - (b % w) * (a / w);
			}
			const int64_t at_side = y > 0 ? side[p - w] : 0;
			if (!((area > 0 && at_side == 0) || (area < 0 && at_side == 1))) {
				continue;
			}
			const Dictionary &style = styles[at_side];
			const int64_t every = inum(dict(style, "rim"), "every", 4);
			if (style.has("rim")) {
				PackedVector2Array points;
				for (size_t i = 0; i < path.size(); i += (size_t)every) {
					points.push_back(Vector2((real_t)((double)(path[i] % w) + 0.5), (real_t)((double)(path[i] / w) + 0.5)));
				}
				rims.push_back(points);
				rim_sides.push_back((int32_t)at_side);
			}
			rim_paths.push_back(std::move(path));
			rim_every.push_back(every);
			rim_path_sides.push_back(at_side);
		}
	}

	void spread_bands() {
		std::vector<int64_t> frontier, next;
		int64_t reach = 0;
		for (size_t k = 0; k < rim_paths.size(); k++) {
			const std::vector<int64_t> &path = rim_paths[k];
			const int64_t every = rim_every[k];
			const Dictionary seam_spec = dict(styles[rim_path_sides[k]], "seam");
			if (seam_spec.is_empty()) {
				continue;
			}
			const double length = num(seam_spec, "band_length", 0.0);
			const int64_t count = arr(seam_spec, "colours").size();
			reach = maxi(reach, inum(seam_spec, "reach", 120));
			double run = 0.0, last_x = 0.0, last_y = 0.0;
			bool has_last = false;
			std::vector<double> marks;
			for (size_t i = 0; i < path.size(); i += (size_t)every) {
				const int64_t q = path[i];
				const double here_x = (double)(q % w) + 0.5, here_y = (double)(q / w) + 0.5;
				if (has_last) {
					run += length_of(here_x - last_x, here_y - last_y);
				}
				marks.push_back(run);
				has_last = true;
				last_x = here_x;
				last_y = here_y;
			}
			for (size_t i = 0; i < path.size(); i++) {
				const int64_t q = path[i];
				const int64_t b = (int64_t)(marks[(size_t)mini((int64_t)i / every, (int64_t)marks.size() - 1)] / length) % count;
				if (band[q] < 0) {
					band[q] = (int32_t)b;
					frontier.push_back(q);
				}
			}
		}
		for (int64_t step = 0; step < reach; step++) {
			next.clear();
			for (const int64_t q : frontier) {
				const int64_t x = q % w, y = q / w;
				const int32_t b = band[q];
				for (int64_t way = 0; way < 4; way++) {
					const int64_t nx = x + WAY_X[way], ny = y + WAY_Y[way];
					if (nx >= 0 && nx < w && ny >= 0 && ny < h) {
						const int64_t r = ny * w + nx;
						if (band[r] < 0 && side[r] == side[q]) {
							band[r] = b;
							next.push_back(r);
						}
					}
				}
			}
			frontier.swap(next);
			if (frontier.empty()) {
				break;
			}
		}
	}

	// The seam's three shades at `p`; false where it has none.
	bool seam_colour(int64_t p, PackedInt32Array &ramp) const {
		const int32_t b = band[p];
		const Dictionary seam_spec = dict(styles[side[p]], "seam");
		if (b < 0 || seam_spec.is_empty()) {
			return false;
		}
		ramp = palette[arr(seam_spec, "colours")[b]];
		return true;
	}

	void draw_edges() {
		PackedInt32Array lip_colours[2];
		int64_t lip_widths[2];
		for (int64_t i = 0; i < 2; i++) {
			const Dictionary lip = dict(styles[i], "lip");
			const Array shades = arr(lip, "shades");
			for (int64_t k = 0; k < shades.size(); k++) {
				lip_colours[i].push_back((int32_t)colour_of(shades[k], palette));
			}
			lip_widths[i] = inum(lip, "width", 0);
		}
		const int64_t lip_most = maxi(lip_widths[0], lip_widths[1]);
		std::vector<uint8_t> dist(w * h, 0);
		std::vector<int64_t> frontier, next;
		for (int64_t p = 0; p < w * h; p++) {
			if (is_edge(p)) {
				frontier.push_back(p);
				dist[p] = 1;
			}
		}
		for (int64_t d = 2; d < lip_most + 2; d++) {
			next.clear();
			for (const int64_t q : frontier) {
				const int64_t x = q % w, y = q / w;
				for (int64_t way = 0; way < 4; way++) {
					const int64_t nx = x + WAY_X[way], ny = y + WAY_Y[way];
					if (nx >= 0 && nx < w && ny >= 0 && ny < h) {
						const int64_t r = ny * w + nx;
						if (land[r] != 0 && dist[r] == 0) {
							dist[r] = (uint8_t)d;
							next.push_back(r);
						}
					}
				}
			}
			frontier.swap(next);
		}
		std::vector<int64_t> edge_pixels;
		PackedInt32Array ramp;
		for (int64_t p = 0; p < w * h; p++) {
			const int64_t d = dist[p];
			if (d == 0) {
				continue;
			}
			const int64_t at_side = side[p];
			const double tp = (double)t[p];
			const double roll = unit3(p % w, p / w, 5051);
			if (d == 1) {
				edge_pixels.push_back(p);
			}
			if (d == 1 && styles[at_side].has("seam")) {
				if (!seam_colour(p, ramp)) {
					continue;
				}
				int64_t rgb;
				if (roll < tp * 0.5) {
					rgb = ramp[2];
				} else if (roll < 0.25 + tp * 0.75) {
					rgb = ramp[1];
				} else {
					rgb = ramp[0];
				}
				put(floor_image, p, rgb);
				seam.push_back(p);
			} else if ((double)(d - 1) <= (double)lip_widths[at_side] * tp + 0.2 && tp > 0.2) {
				put(floor_image, p, roll < 0.3 ? lip_colours[at_side][1] : lip_colours[at_side][0]);
			}
		}
		for (int64_t at_side = 0; at_side < 2; at_side++) {
			const Dictionary &style = styles[at_side];
			const Dictionary lip = dict(style, "lip");
			const Dictionary pebbles = dict(lip, "pebbles");
			if (!pebbles.is_empty()) {
				std::vector<int64_t> mine;
				for (const int64_t p : seam) {
					if (side[p] == at_side) {
						mine.push_back(p);
					}
				}
				draw_pebbles(pebbles, mine);
			}
			const Dictionary rubble = dict(lip, "rubble");
			if (!rubble.is_empty()) {
				std::vector<int64_t> mine;
				for (const int64_t p : edge_pixels) {
					if (side[p] == at_side) {
						mine.push_back(p);
					}
				}
				draw_rubble(rubble, mine);
			}
			const Dictionary face = dict(style, "face");
			if (!face.is_empty() && face.has("foot") && at_side == 0) {
				draw_foot(arr(face, "foot"));
			}
		}
	}

	void draw_pebbles(const Dictionary &pebbles, const std::vector<int64_t> &along) {
		const Array shade_list = arr(pebbles, "shades");
		int64_t shades[3];
		for (int64_t k = 0; k < 3; k++) {
			shades[k] = colour_of(shade_list[k], palette);
		}
		const int64_t every = inum(pebbles, "every", 1);
		for (const int64_t p : along) {
			if ((double)t[p] < 0.9 || hash2(p, 6061) % every != 0) {
				continue;
			}
			const int64_t x = p % w, y = p / w;
			for (int64_t dy = -6; dy < -3; dy++) {
				for (int64_t dx = -2; dx < 2; dx++) {
					const int64_t q = (y + dy) * w + x + dx;
					if (y + dy >= 0 && y + dy < h && x + dx >= 0 && x + dx < w && land[q] != 0) {
						const bool inner = dy >= -5 && dy <= -4 && dx >= -1 && dx <= 0;
						put(floor_image, q, (inner && dx == -1 && dy == -5) ? shades[2] : (inner ? shades[1] : shades[0]));
					}
				}
			}
		}
	}

	void draw_rubble(const Dictionary &rubble, const std::vector<int64_t> &edge) {
		const Array shades = arr(rubble, "shades");
		const int64_t dark = colour_of(shades[0], palette), base = colour_of(shades[1], palette), light = colour_of(shades[2], palette);
		const Array sizes = arr(rubble, "sizes");
		const int64_t lo = (int64_t)at(sizes, 0), hi = (int64_t)at(sizes, 1);
		const int64_t every = inum(rubble, "every", 1);
		for (const int64_t p : edge) {
			if ((double)t[p] < 0.6 || hash2(p, 7071) % every != 0) {
				continue;
			}
			const int64_t size = lo + hash2(p, 7072) % (hi - lo + 1);
			int64_t x = p % w, y = p / w;
			const int64_t steps_x[4] = { x, x + 1, x - 1, x };
			const int64_t steps_y[4] = { y + 1, y, y, y - 1 };
			for (int64_t k = 0; k < 4; k++) {
				const int64_t nx = steps_x[k], ny = steps_y[k];
				if (nx >= 0 && nx < w && ny >= 0 && ny < h && land[ny * w + nx] != 0 && !is_edge(ny * w + nx)) {
					x = nx;
					y = ny;
					break;
				}
			}
			for (int64_t dy = 0; dy < size + 1; dy++) {
				for (int64_t dx = 0; dx < size + 1; dx++) {
					const int64_t xx = x + dx, yy = y + dy;
					if (xx < 0 || xx >= w || yy < 0 || yy >= h || land[yy * w + xx] == 0) {
						continue;
					}
					const int64_t rgb = dy == size ? dark : ((dy == 0 && size > 1) ? light : base);
					if (dx == size && dy < size) {
						continue;
					}
					put(floor_image, yy * w + xx, rgb);
				}
			}
		}
	}

	void draw_foot(const Array &foot) {
		const int64_t shade = colour_of(foot[0], palette);
		const int64_t rows = (int64_t)at(foot, 1);
		for (int64_t p = w; p < w * h; p++) {
			if (land[p] == 0 || land[p - w] != 0 || pit[p - w] != 0 || (double)crack[p - w] > 0.0) {
				continue;
			}
			for (int64_t k = 0; k < rows; k++) {
				const int64_t q = p + k * w;
				if (q >= w * h || land[q] == 0) {
					break;
				}
				const int64_t old = ((int64_t)floor_image[q * 4] << 16) | ((int64_t)floor_image[q * 4 + 1] << 8) | (int64_t)floor_image[q * 4 + 2];
				put(floor_image, q, mix(old, shade, (double)(rows - k) / (double)(rows + 1)));
			}
		}
	}

	void draw_under() {
		struct Rock {
			bool has = false;
			int64_t shades[2] = { 0, 0 };
			int64_t strata = 0, roots = 0;
			double lo = 0.0, hi = 0.0;
		} rocks[2];
		for (int64_t i = 0; i < 2; i++) {
			const Dictionary rock = dict(styles[i], "rock");
			if (rock.is_empty()) {
				continue;
			}
			rocks[i].has = true;
			const Array shades = arr(rock, "shades");
			rocks[i].shades[0] = colour_of(shades[0], palette);
			rocks[i].shades[1] = colour_of(shades[1], palette);
			rocks[i].strata = colour_of(rock["strata"], palette);
			rocks[i].roots = colour_of(rock["roots"], palette);
			const Array depth = arr(rock, "depth");
			rocks[i].lo = at(depth, 0);
			rocks[i].hi = at(depth, 1);
		}
		const int64_t seed = inum(shape, "seed", 0) + 21;
		// The rock's bottoms in the order the GDScript sorts them (column by column, top down),
		// which is the order they are found in: each lies below the last in its column.
		struct Bottom {
			int64_t x, y, edge;
		};
		std::vector<Bottom> bottoms;
		for (int64_t x = 0; x < w; x++) {
			for (int64_t y = 0; y < h - 1; y++) {
				const int64_t p = y * w + x;
				if (solid[p] == 0 || solid[p + w] != 0) {
					continue;
				}
				const int64_t below_side = side[p + w];
				const Rock &rock = rocks[below_side];
				if (!rock.has) {
					continue;
				}
				const int64_t deep = deeps[below_side];
				const double tp = (double)t[p];
				const int64_t depth = (int64_t)((rock.lo + (rock.hi - rock.lo) * std::pow(noise1((double)x / 14.0, seed), 1.8)) * tp);
				int64_t bottom = y;
				for (int64_t d = 1; d < depth + 1; d++) {
					const int64_t yy = y + d;
					if (yy >= h) {
						break;
					}
					const int64_t q = yy * w + x;
					if (solid[q] != 0) {
						break;
					}
					const double k = noise2((double)x, (double)yy, 7.0, seed + 1);
					int64_t rgb = k > 0.55 ? rock.shades[1] : rock.shades[0];
					if (std::sin(((double)yy + noise1((double)x / 9.0, seed + 2) * 18.0) / 5.0) > 0.85) {
						rgb = rock.strata;
					}
					rgb = mix(deep, rgb, tp);
					put(under, q, rgb);
					bottom = yy;
				}
				if (bottom > y && tp > 0.6) {
					put(under, bottom * w + x, rock.strata);
					bottoms.push_back(Bottom{ x, bottom, p });
					if (hash3(x, y, seed) % 7 == 0) {
						const int64_t length = 6 + hash4(x, y, seed, 2) % 30;
						for (int64_t d = 1; d < length; d++) {
							const int64_t yy = bottom + d;
							if (yy < h && solid[yy * w + x] == 0) {
								put(under, yy * w + x, rock.roots);
							}
						}
					}
				}
			}
		}
		std::vector<PackedVector2Array> runs;
		std::vector<int64_t> run_bands, run_sides;
		bool has_last = false;
		int64_t last[4] = { 0, 0, 0, 0 };
		for (const Bottom &b : bottoms) {
			const int64_t at_band = band[b.edge];
			const int64_t at_side = side[b.edge + w];
			const Vector2 point((real_t)((double)b.x + 0.5), (real_t)((double)b.y + 1.0));
			if (has_last && b.x == last[0] + 1 && absi(b.y - last[1]) <= 6 && at_band == last[2] && at_side == last[3]) {
				runs.back().push_back(point);
			} else {
				PackedVector2Array run;
				run.push_back(point);
				runs.push_back(run);
				run_bands.push_back(at_band);
				run_sides.push_back(at_side);
			}
			has_last = true;
			last[0] = b.x;
			last[1] = b.y;
			last[2] = at_band;
			last[3] = at_side;
		}
		for (size_t i = 0; i < runs.size(); i++) {
			const PackedVector2Array &run = runs[i];
			const Dictionary &style = styles[run_sides[i]];
			if (run.size() < 12 || run_bands[i] < 0 || !style.has("drip") || !style.has("seam")) {
				continue;
			}
			const int64_t every = inum(dict(style, "rim"), "every", 4);
			PackedVector2Array points;
			for (int64_t k = 0; k < run.size(); k += every) {
				points.push_back(run[k]);
			}
			if ((run.size() - 1) % every != 0) {
				points.push_back(run[run.size() - 1]);
			}
			points.reverse();
			drips.push_back(points);
			drip_colours.push_back((String)arr(dict(style, "seam"), "colours")[run_bands[i]]);
			drip_sides.push_back((int32_t)run_sides[i]);
		}
	}

	void draw_glow() {
		glow_w = w / 2;
		glow_h = h / 2;
		const int64_t size = glow_w * glow_h;
		std::vector<float> out[3];
		for (int64_t c = 0; c < 3; c++) {
			out[c].assign(size, 0.0f);
		}
		PackedInt32Array ramp;
		for (int64_t at_side = 0; at_side < 2; at_side++) {
			const Dictionary spec = dict(styles[at_side], "glow");
			if (spec.is_empty() || (at_side == 1 && style_of_side[1] == style_of_side[0])) {
				continue;
			}
			std::vector<float> acc[3];
			for (int64_t c = 0; c < 3; c++) {
				acc[c].assign(size, 0.0f);
			}
			for (const int64_t p : seam) {
				if (style_of_side[side[p]] != style_of_side[at_side]) {
					continue;
				}
				if (!seam_colour(p, ramp)) {
					continue;
				}
				const double k = std::pow((double)t[p], 1.5);
				const int64_t q = ((p / w) / 2) * glow_w + (p % w) / 2;
				const int64_t base = ramp[1];
				acc[0][q] = (float)((double)acc[0][q] + (double)((base >> 16) & 0xFF) * k / 255.0 * 0.25);
				acc[1][q] = (float)((double)acc[1][q] + (double)((base >> 8) & 0xFF) * k / 255.0 * 0.25);
				acc[2][q] = (float)((double)acc[2][q] + (double)(base & 0xFF) * k / 255.0 * 0.25);
			}
			const Array blurs = arr(spec, "blurs");
			for (int64_t i = 0; i < blurs.size(); i++) {
				const Array blur = blurs[i];
				const int64_t radius = (int64_t)at(blur, 0);
				const double strength = at(blur, 1);
				for (int64_t c = 0; c < 3; c++) {
					const std::vector<float> blurred = box_blur(box_blur(acc[c], glow_w, glow_h, radius, true), glow_w, glow_h, radius, false);
					for (int64_t q = 0; q < size; q++) {
						out[c][q] = (float)((double)out[c][q] + (double)blurred[q] * strength);
					}
				}
			}
		}
		glow.assign(size * 4, 0);
		for (int64_t q = 0; q < size; q++) {
			const double r = out[0][q], g = out[1][q], b = out[2][q];
			const double a = minf(1.0, maxf(r, maxf(g, b)));
			if (a < 1.0 / 255.0) {
				continue;
			}
			glow[q * 4] = (uint8_t)mini(255, round_even(r / a * 255.0));
			glow[q * 4 + 1] = (uint8_t)mini(255, round_even(g / a * 255.0));
			glow[q * 4 + 2] = (uint8_t)mini(255, round_even(b / a * 255.0));
			glow[q * 4 + 3] = (uint8_t)round_even(a * 255.0);
		}
	}

	void draw_wall_art() {
		const Dictionary &style = styles[0];
		const String void_kind = shape.has("void") ? (String)shape["void"] : String("wall");
		if (void_kind == "hole" || !(style.has("top") || style.has("face"))) {
			return;
		}
		std::vector<uint8_t> wall(w * h, 0);
		for (int64_t p = 0; p < w * h; p++) {
			if (solid[p] == 0 && (double)crack[p] == 0.0 && pit[p] == 0) {
				wall[p] = 1;
			}
		}
		wall_art = walls_draw(w, h, solid, wall, style, palette, inum(shape, "seed", 0) + 61);
	}
};

PackedByteArray bytes(const std::vector<uint8_t> &from) {
	PackedByteArray out;
	out.resize((int64_t)from.size());
	uint8_t *to = out.ptrw();
	for (size_t i = 0; i < from.size(); i++) {
		to[i] = from[i];
	}
	return out;
}

} // namespace

Dictionary godot::ground::draw(const Dictionary &spec) {
	Drawing drawing;
	drawing.run(spec);
	Dictionary out;
	out["width"] = drawing.w;
	out["height"] = drawing.h;
	out["solid"] = bytes(drawing.solid);
	out["floor"] = bytes(drawing.floor_image);
	out["under"] = bytes(drawing.under);
	out["glow_width"] = drawing.glow_w;
	out["glow_height"] = drawing.glow_h;
	out["glow"] = bytes(drawing.glow);
	out["wall"] = bytes(drawing.wall_art);
	out["rims"] = drawing.rims;
	out["rim_sides"] = drawing.rim_sides;
	out["drips"] = drawing.drips;
	out["drip_sides"] = drawing.drip_sides;
	out["drip_colours"] = drawing.drip_colours;
	return out;
}
