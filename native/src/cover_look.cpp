// SPDX-FileCopyrightText: 2026 peterdk31 and Spellmerge contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//
// `BodyKernel.cover_look` (perf plan C3): a room's cover look, `CoverRoom.gd_look`
// (gameplay/cover/cover_room.gd) and the `CoverSight.open` and `mark` it calls (core/base/cover_sight.gd),
// line by line. tests/gameplay/cover/test_cover_look.gd compares the two to the bit.

#include "body_kernel.h"
#include "packed.h"

using namespace godot;

namespace {

// `CoverLayout.CELL`, `CoverSight.SIDE`, `CoverRoom.BITS`.
constexpr double COVER_CELL = 16.0;
constexpr int64_t SIDE = 9;
constexpr int64_t BITS = 32;

} // namespace

int64_t BodyKernel::cover_look(const PackedInt64Array &row_bits, const PackedInt64Array &column_bits, const PackedInt64Array &danger_bits, int64_t words,
		int64_t columns, int64_t rows, const Vector2 &origin, const Vector2 &at, double reach, const PackedByteArray &harms,
		const PackedInt32Array &window) const {
	ERR_FAIL_COND_V_MSG(harms.size() < SIDE * SIDE || window.size() < 5, -2, "BodyKernel.cover_look: the sight's arrays are too small");
	ERR_FAIL_COND_V_MSG(columns <= 0 || rows <= 0 || words <= 0 || danger_bits.size() < rows * words, -2, "BodyKernel.cover_look: the room's bits are too small");
	// `look`: `holds(at)`, as `CoverLayout.cell_of` works it out.
	const int64_t cx = floori(((double)at.x - (double)origin.x) / COVER_CELL);
	const int64_t cy = floori(((double)at.y - (double)origin.y) / COVER_CELL);
	if (cx < 0 || cy < 0 || cx >= columns || cy >= rows) {
		return -1;
	}
	// `CoverSight.open`: the point in room pixels (a Vector2's subtraction, in its own floats).
	const Vector2 local = at - origin;
	const int64_t half = SIDE / 2;
	const int64_t centre_x = floori((double)local.x / COVER_CELL);
	const int64_t centre_y = floori((double)local.y / COVER_CELL);
	int64_t x0 = maxi(floori(((double)local.x - reach) / COVER_CELL), centre_x - half);
	int64_t x1 = mini(floori(((double)local.x + reach) / COVER_CELL), centre_x + half);
	int64_t y0 = maxi(floori(((double)local.y - reach) / COVER_CELL), centre_y - half);
	int64_t y1 = mini(floori(((double)local.y + reach) / COVER_CELL), centre_y + half);
	x0 = maxi(x0, 0);
	y0 = maxi(y0, 0);
	x1 = mini(x1, columns - 1);
	y1 = mini(y1, rows - 1);
	if (x1 < x0 || y1 < y0) {
		return 0;
	}
	// The caller's arrays, written through their buffers (native/README.md, "The object's arrays").
	int32_t *out = const_cast<int32_t *>(window.ptr());
	uint8_t *marks = const_cast<uint8_t *>(harms.ptr());
	out[0] = (int32_t)x0;
	out[1] = (int32_t)y0;
	out[2] = (int32_t)(x1 - x0 + 1);
	out[3] = (int32_t)(y1 - y0 + 1);
	out[4] = 0;
	// The rows and columns of the window that hold danger, as `look` reads them (a word or two each).
	int64_t word = y0 / BITS;
	int64_t shift = y0 % BITS;
	const int64_t row_words = row_bits.size();
	const int64_t column_words = column_bits.size();
	ERR_FAIL_COND_V_MSG(word >= row_words || (y1 / BITS != word && word + 1 >= row_words), -2, "BodyKernel.cover_look: the row bits are too short");
	int64_t rows_seen = row_bits[word] >> shift;
	if (y1 / BITS != word) {
		rows_seen |= row_bits[word + 1] << (BITS - shift);
	}
	rows_seen &= ((int64_t)1 << (y1 - y0 + 1)) - 1;
	if (rows_seen == 0) {
		return 1;
	}
	word = x0 / BITS;
	shift = x0 % BITS;
	ERR_FAIL_COND_V_MSG(word >= column_words || (x1 / BITS != word && word + 1 >= column_words), -2, "BodyKernel.cover_look: the column bits are too short");
	int64_t columns_seen = column_bits[word] >> shift;
	if (x1 / BITS != word) {
		columns_seen |= column_bits[word + 1] << (BITS - shift);
	}
	if ((columns_seen & (((int64_t)1 << (x1 - x0 + 1)) - 1)) == 0) {
		return 1;
	}
	const int64_t first_word = x0 / BITS;
	const int64_t last_word = x1 / BITS;
	const int64_t *danger = danger_bits.ptr();
	int32_t count = 0;
	int64_t y = y0 - 1;
	while (rows_seen != 0) {
		y += 1;
		const bool seen = (rows_seen & 1) != 0;
		rows_seen >>= 1;
		if (!seen) {
			continue;
		}
		const int64_t base = y * words;
		for (int64_t at_word = first_word; at_word <= last_word; at_word++) {
			int64_t bits = danger[base + at_word];
			if (bits == 0) {
				continue;
			}
			const int64_t low = maxi(x0 - at_word * BITS, 0);
			const int64_t high = mini(x1 - at_word * BITS, BITS - 1);
			bits = (bits >> low) & (((int64_t)1 << (high - low + 1)) - 1);
			int64_t x = at_word * BITS + low;
			while (bits != 0) {
				if ((bits & 1) != 0) {
					// `CoverSight.mark`.
					const int64_t cell = (y - y0) * SIDE + (x - x0);
					if (marks[cell] == 0) {
						marks[cell] = 1;
						count += 1;
					}
				}
				bits >>= 1;
				x += 1;
			}
		}
	}
	out[4] = count;
	return 1;
}
