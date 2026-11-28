// SPDX-FileCopyrightText: 2026 peterdk31 and Spellmerge contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//
// The bodies' looks a drawn frame in one call each (perf plan F4, docs/milestones/perf-plan.md):
// `BodyKernel.looks_due`, which bodies' looks step this frame and for how long (mirrors
// `Actor.gd_looks_due`), and `BodyKernel.pose_looks`, every listed body's staff animation read into
// the looks' table (mirrors `StaffPoses.gd_read_looks`). Both are view only: nothing the game plays
// by. A GDScript `float` is a double and a Vector2 single precision; each number is worked out in
// the type its GDScript works it out in, so the bytes are the same (tests/gameplay/actor/
// test_looks_kernel.gd).

#include "body_kernel.h"
#include "packed.h"

#include <cmath>

#include <godot_cpp/classes/node2d.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/object.hpp>

using namespace godot;

namespace {

// `ScreenViews.cell_holds`: the screen point inside view `view`'s cell, `margin` pixels outside it at most.
bool cell_holds(const Vector2 *cell_points, const int32_t *cell_counts, int64_t corners_most, int64_t view, const Vector2 &point, double margin) {
	const int64_t n = cell_counts[view];
	if (n < 3) {
		return false;
	}
	const int64_t base = view * corners_most;
	for (int64_t i = 0; i < n; i++) {
		const Vector2 a = cell_points[base + i];
		const Vector2 b = cell_points[base + (i + 1) % n];
		const Vector2 edge = b - a;
		const double length = edge.length();
		if (length <= 0.0) {
			continue;
		}
		if ((double)edge.cross(point - a) / length < -margin) {
			return false;
		}
	}
	return true;
}

// `StaffPoses.pose_ease`.
double pose_ease(double x, int64_t ease) {
	switch (ease) {
		case 1:
			return 1.0 - (1.0 - x) * (1.0 - x);
		case 2:
			return x * x;
		case 3:
			return x * x * x * x;
		default:
			// `CarrierSwing.swing_ease`.
			return x < 0.5 ? 2.0 * x * x : 1.0 - 2.0 * (1.0 - x) * (1.0 - x);
	}
}

int64_t roundi(double x) {
	return (int64_t)std::round(x);
}

// The layout `pose_looks` is handed (`StaffPoses.LOOKS_LAYOUT`), in order.
enum Layout { L_STRIDE, L_PHASE, L_AT, L_CHANNELS, L_EASE, L_MOOD, L_POSE_CHANNELS, L_HOLD, L_LOOK_SIZE, L_SIZE };
// `StaffPoses.Look`'s order.
enum Look { DIR_X, DIR_Y, TURN, LIFT, PUSH, GLOW, STRETCH, SHAKE, MOOD, TINT_R, TINT_G, TINT_B, TINT_A, LOOK_SIZE };
constexpr int64_t CHANNELS_MOST = 16;

struct Pose {
	const float *keys;
	int64_t stride, k_phase, k_at, k_channels, k_ease, k_mood, channels;
	const float *from;
	float *out;
	int64_t mood = 0;

	// `StaffPoses._mood_of`.
	int64_t mood_of(int64_t k, int64_t was) const {
		const int64_t own = roundi(keys[k * stride + k_mood]);
		return own > 0 ? own : was;
	}

	// `StaffPoses._pose_between`.
	bool between(int64_t from_key, int64_t to, double x, int64_t with_mood) {
		const double eased = pose_ease(x, roundi(keys[to * stride + k_ease]));
		for (int64_t c = 0; c < channels; c++) {
			const double a = from_key < 0 ? (double)from[c] : (double)keys[from_key * stride + k_channels + c];
			const double b = keys[to * stride + k_channels + c];
			out[c] = (float)(a + (b - a) * eased);
		}
		mood = with_mood;
		return true;
	}
};

} // namespace

int64_t BodyKernel::looks_due(const PackedInt64Array &nodes, const PackedInt32Array &ids, int64_t count, const RID &canvas, bool split,
		const Rect2 &screen, const Array &to_screen, int64_t view_count, const PackedVector2Array &cell_points, const PackedInt32Array &cell_counts,
		int64_t corners_most, double margin, double most, const PackedInt32Array &due, const PackedFloat64Array &seconds) const {
	ERR_FAIL_COND_V_MSG(count > ids.size() || due.size() < count || seconds.size() < count, -1, "BodyKernel.looks_due: the arrays are shorter than count");
	static const StringName LOOK_TIME("_look_time");
	const int64_t views = split ? view_count : 0;
	ERR_FAIL_COND_V_MSG(views > 16 || views > to_screen.size() || (split && (cell_counts.size() < views || cell_points.size() < views * corners_most)), -1,
			"BodyKernel.looks_due: the views' cells are short");
	Transform2D view_to_screen[16];
	for (int64_t v = 0; v < views; v++) {
		view_to_screen[v] = to_screen[v];
	}
	// The caller's arrays, written through their buffers (native/README.md, "The object's arrays").
	int32_t *out_id = const_cast<int32_t *>(due.ptr());
	double *out_seconds = const_cast<double *>(seconds.ptr());
	const int32_t *id = ids.ptr();
	int64_t listed = 0;
	for (int64_t n = 0; n < count; n++) {
		const int64_t at = id[n];
		Object *object = (at >= 0 && at < nodes.size() && nodes[at] != 0) ? ObjectDB::get_instance((uint64_t)nodes[at]) : nullptr;
		Node2D *body = Object::cast_to<Node2D>(object);
		if (body == nullptr || !body->is_inside_tree()) {
			continue;
		}
		// An actor's body only (its `_look_time` a float).
		const Variant time = body->get(LOOK_TIME);
		if (time.get_type() != Variant::FLOAT) {
			continue;
		}
		double left = time;
		if (left <= 0.0) {
			continue;
		}
		out_id[listed] = (int32_t)at;
		// Drawn on another canvas (another viewport's world, a layer): it asks the screen itself.
		if (body->get_canvas() != canvas) {
			out_seconds[listed] = -1.0;
			listed++;
			continue;
		}
		const double held = minf(left, most);
		bool on = false;
		if (split) {
			const Vector2 world = body->get_global_position();
			for (int64_t v = 0; v < views && !on; v++) {
				on = cell_holds(cell_points.ptr(), cell_counts.ptr(), corners_most, v, view_to_screen[v].xform(world), margin);
			}
		} else {
			on = screen.has_point(body->get_global_transform_with_canvas().get_origin());
		}
		if (on) {
			body->set(LOOK_TIME, 0.0);
			out_seconds[listed] = held;
			listed++;
		} else if (held != left) {
			body->set(LOOK_TIME, held);
		}
	}
	return listed;
}

bool BodyKernel::pose_looks(const PackedInt32Array &ids, int64_t count, double clock, const PackedInt32Array &layout, const Array &keys,
		const PackedFloat64Array &start, const PackedFloat32Array &wind, const PackedFloat32Array &strike, const PackedFloat32Array &lead,
		const PackedInt32Array &blow, const PackedFloat32Array &from, const PackedInt32Array &side, const PackedFloat32Array &turned,
		const PackedVector2Array &dir, const PackedColorArray &tint, const PackedByteArray &ended, const PackedFloat32Array &rows,
		const PackedByteArray &state) const {
	ERR_FAIL_COND_V_MSG(layout.size() < L_SIZE || layout[L_LOOK_SIZE] != LOOK_SIZE || layout[L_POSE_CHANNELS] > CHANNELS_MOST, false,
			"BodyKernel.pose_looks: not the layout it knows");
	const int64_t actors = start.size();
	const int64_t channels = layout[L_POSE_CHANNELS];
	ERR_FAIL_COND_V_MSG(count > ids.size() || keys.size() < actors || wind.size() < actors || strike.size() < actors || lead.size() < actors ||
					blow.size() < actors || side.size() < actors || turned.size() < actors || dir.size() < actors || tint.size() < actors ||
					ended.size() < actors || state.size() < actors || from.size() < actors * channels || rows.size() < actors * LOOK_SIZE,
			false, "BodyKernel.pose_looks: the arrays are shorter than the actors");
	const int64_t stride = layout[L_STRIDE];
	const int64_t hold = layout[L_HOLD];
	uint8_t *is_ended = const_cast<uint8_t *>(ended.ptr());
	uint8_t *out_state = const_cast<uint8_t *>(state.ptr());
	float *out_rows = const_cast<float *>(rows.ptr());
	const int32_t *id = ids.ptr();
	float out[CHANNELS_MOST];
	for (int64_t n = 0; n < count; n++) {
		const int64_t actor = id[n];
		if (actor < 0 || actor >= actors) {
			continue;
		}
		out_state[actor] = 1;
		// `StaffPoses._pose_now`, written out.
		if (!std::isfinite(start[actor]) || is_ended[actor] != 0) {
			continue;
		}
		const PackedFloat32Array actor_keys = keys[actor];
		Pose pose{ actor_keys.ptr(), stride, layout[L_PHASE], layout[L_AT], layout[L_CHANNELS], layout[L_EASE], layout[L_MOOD], channels,
			from.ptr() + actor * channels, out };
		const int64_t key_count = stride > 0 ? actor_keys.size() / stride : 0;
		const double s = clock - start[actor];
		const double wind_s = wind[actor];
		const double strike_s = strike[actor];
		int64_t from_key = -1;
		double from_t = 0.0;
		int64_t mood = 0;
		bool playing = false;
		bool done = false;
		int64_t k = 0;
		while (k < key_count && !done) {
			const int64_t phase = roundi(pose.keys[k * stride + pose.k_phase]);
			if (phase == hold) {
				const int64_t first = k;
				while (k < key_count && roundi(pose.keys[k * stride + pose.k_phase]) == phase) {
					k++;
				}
				const int64_t last = k - 1;
				const double period = pose.keys[last * stride + pose.k_at];
				if (s < wind_s && strike_s > 0.0) {
					playing = pose.between(from_key, first, 0.0, mood);
					done = true;
					break;
				}
				if (s >= wind_s && s < wind_s + strike_s && period > 0.0) {
					const double into = s - wind_s;
					const int64_t round_n = floori(into / period);
					const double u = into - (double)round_n * period;
					int64_t h_from = round_n == 0 ? from_key : last;
					double h_t = 0.0;
					bool found = false;
					for (int64_t h = first; h < last + 1; h++) {
						const double t = pose.keys[h * stride + pose.k_at];
						if (u < t) {
							playing = pose.between(h_from, h, t > h_t ? clampf((u - h_t) / (t - h_t), 0.0, 1.0) : 1.0, mood);
							found = true;
							break;
						}
						h_from = h;
						h_t = t;
						mood = pose.mood_of(h, mood);
					}
					if (!found) {
						playing = pose.between(h_from, h_from, 1.0, mood);
					}
					done = true;
					break;
				}
				if (s >= wind_s + strike_s || strike_s <= 0.0) {
					from_key = strike_s > 0.0 ? last : from_key;
					from_t = wind_s + strike_s;
				}
				continue;
			}
			const double at_key = pose.keys[k * stride + pose.k_at];
			const double t = phase == 0 ? at_key * (k < blow[actor] ? (double)lead[actor] : wind_s)
										: (phase == 1 ? wind_s + at_key * strike_s : wind_s + strike_s + at_key);
			if (s < t) {
				playing = pose.between(from_key, k, t > from_t ? clampf((s - from_t) / (t - from_t), 0.0, 1.0) : 1.0, mood);
				done = true;
				break;
			}
			from_key = k;
			from_t = t;
			mood = pose.mood_of(k, mood);
			k++;
		}
		if (!done) {
			// Past its last key: known over.
			is_ended[actor] = 1;
			continue;
		}
		if (!playing) {
			continue;
		}
		// `StaffPoses._read_look_into`, but the live aim (the caller's, after).
		float *row = out_rows + actor * LOOK_SIZE;
		const Vector2 d = dir[actor];
		row[DIR_X] = d.x;
		row[DIR_Y] = d.y;
		row[TURN] = (float)(Math::deg_to_rad((double)out[0]) * (double)side[actor] + (double)turned[actor]);
		row[LIFT] = out[1];
		row[PUSH] = out[2];
		row[GLOW] = out[3];
		row[STRETCH] = out[4];
		row[SHAKE] = out[5];
		row[MOOD] = (float)(pose.mood > 0 ? pose.mood : 0);
		const Color c = tint[actor];
		row[TINT_R] = c.r;
		row[TINT_G] = c.g;
		row[TINT_B] = c.b;
		row[TINT_A] = c.a;
		out_state[actor] = 2;
	}
	return true;
}
