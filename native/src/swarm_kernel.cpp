// SPDX-FileCopyrightText: 2026 peterdk31 and Spellmerge contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//
// See swarm_kernel.h, and shot_kernel.cpp for how the numbers are kept to the bit (a GDScript
// `float` is a double; Vector2 and PackedFloat32Array single precision).

#include "swarm_kernel.h"
#include "packed.h"

#include <godot_cpp/classes/node2d.hpp>
#include <godot_cpp/classes/random_number_generator.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_int64_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/rect2.hpp>

using namespace godot;

namespace {

constexpr double TAU_D = 6.2831853071795864769252867666;
constexpr double PI_D = 3.1415926535897932384626433833;

// The members the kernels read: C++ name, GDScript member, type (one list each, so `check_fields`
// sees every name a kernel uses). The look reads the swarm's rows through its `swarm`; those are in
// the swarm's list, checked by the swarm's kernel.
#define SWARM_FIELDS(X) \
	X(positions, "positions", PACKED_VECTOR2_ARRAY) \
	X(velocities, "velocities", PACKED_VECTOR2_ARRAY) \
	X(ran, "ran", PACKED_FLOAT64_ARRAY) \
	X(radius, "_radius", PACKED_FLOAT32_ARRAY) \
	X(give, "_give", PACKED_FLOAT32_ARRAY) \
	X(push, "_push", PACKED_VECTOR2_ARRAY) \
	X(next, "_next", PACKED_INT32_ARRAY) \
	X(cell_of, "_cell_of", PACKED_INT32_ARRAY) \
	X(cell_head, "_cell_head", PACKED_INT32_ARRAY) \
	X(seeds, "seeds", PACKED_INT32_ARRAY) \
	X(cell, "_cell", FLOAT) \
	X(grid_w, "_grid_w", INT) \
	X(grid_h, "_grid_h", INT) \
	X(arena, "_arena", RECT2) \
	X(spacing, "spacing", FLOAT) \
	X(moved, "moved", INT) \
	X(count, "count", INT) \
	X(nodes, "nodes", ARRAY) \
	X(has_walls, "_has_walls", BOOL) \
	X(walls, "_walls", PACKED_BYTE_ARRAY) \
	X(wall_w, "_wall_w", INT) \
	X(wall_h, "_wall_h", INT) \
	X(kinds, "kinds", PACKED_INT32_ARRAY) \
	X(aims, "aims", PACKED_VECTOR2_ARRAY) \
	X(down, "down", PACKED_BYTE_ARRAY)
#define LOOK_FIELDS(X) \
	X(hop_time, "_hop_time", PACKED_FLOAT64_ARRAY) \
	X(lift, "_lift", PACKED_FLOAT64_ARRAY) \
	X(hurt_left, "_hurt_left", PACKED_FLOAT64_ARRAY) \
	X(eye_point, "_eye_point", PACKED_VECTOR2_ARRAY) \
	X(brow_point, "_brow_point", PACKED_VECTOR2_ARRAY) \
	X(placed, "_placed", PACKED_BYTE_ARRAY) \
	X(mood_left, "_mood_left", PACKED_FLOAT64_ARRAY) \
	X(still_for, "_still_for", PACKED_FLOAT64_ARRAY) \
	X(blink_in, "_blink_in", PACKED_FLOAT64_ARRAY) \
	X(blink_left, "_blink_left", PACKED_FLOAT64_ARRAY) \
	X(glance_in, "_glance_in", PACKED_FLOAT64_ARRAY) \
	X(glance_left, "_glance_left", PACKED_FLOAT64_ARRAY) \
	X(glance_x, "_glance_x", PACKED_INT32_ARRAY) \
	X(raise_in, "_raise_in", PACKED_FLOAT64_ARRAY) \
	X(raise_left, "_raise_left", PACKED_FLOAT64_ARRAY) \
	X(rng_state, "_rng_state", PACKED_INT64_ARRAY) \
	X(eye_column, "_eye_column", PACKED_INT32_ARRAY) \
	X(brow_column, "_brow_column", PACKED_INT32_ARRAY) \
	X(eyes_at, "_eyes_at", PACKED_VECTOR2_ARRAY) \
	X(brows_at, "_brows_at", PACKED_VECTOR2_ARRAY) \
	X(hold_shown, "_hold_shown", PACKED_BYTE_ARRAY) \
	X(style, "_style", PACKED_INT32_ARRAY) \
	X(resting, "_resting", PACKED_INT32_ARRAY) \
	X(anchor, "_anchor", PACKED_VECTOR2_ARRAY) \
	X(rng, "_rng", OBJECT) \
	X(k_delta, "_k_delta", FLOAT) \
	X(k, "_k", FLOAT) \
	X(count_l, "_count", INT) \
	X(batches, "_batches", ARRAY) \
	X(buffers, "_buffers", ARRAY) \
	X(filled, "_filled", PACKED_INT32_ARRAY) \
	X(first, "_first", PACKED_INT32_ARRAY) \
	X(order, "_order", PACKED_INT32_ARRAY) \
	X(has_hurt, "_has_hurt", PACKED_BYTE_ARRAY) \
	X(flash_left, "_flash_left", PACKED_FLOAT32_ARRAY) \
	X(squash, "_squash", PACKED_FLOAT32_ARRAY)

struct SwarmNames {
#define SW_DECLARE(id, gd, type) StringName id;
	SWARM_FIELDS(SW_DECLARE)
	LOOK_FIELDS(SW_DECLARE)
#undef SW_DECLARE
	StringName swarm;
	SwarmNames() :
			swarm("swarm") {
#define SW_INIT(id, gd, type) id = StringName(gd);
		SWARM_FIELDS(SW_INIT)
		LOOK_FIELDS(SW_INIT)
#undef SW_INIT
	}
};

SwarmNames *swarm_names = nullptr;

const SwarmNames &sn() {
	if (swarm_names == nullptr) {
		swarm_names = new SwarmNames();
	}
	return *swarm_names;
}

#define SW_CHECK(id, gd, type)                                         \
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

} // namespace

SwarmKernel::SwarmKernel() {
	sn();
}

void SwarmKernel::free_names() {
	delete swarm_names;
	swarm_names = nullptr;
}

bool SwarmKernel::configure(const Dictionary &config) {
	_ready = take(config, "WALL_CELL", _wall_cell);
	return _ready;
}

PackedStringArray SwarmKernel::check_fields(Object *object) const {
	PackedStringArray wrong;
	ERR_FAIL_NULL_V(object, wrong);
	const SwarmNames &k = sn();
	SWARM_FIELDS(SW_CHECK)
	return wrong;
}

SwarmLookKernel::SwarmLookKernel() {
	sn();
}

bool SwarmLookKernel::configure(const Dictionary &config) {
	double blink_column = 0.0, worried = 0.0, raised = 0.0, stride = 0.0;
	_ready = take(config, "HOP_SPEED_SQ", _hop_speed_sq) && take(config, "HOP_RATE", _hop_rate) &&
			take(config, "HOP_HEIGHT", _hop_height) && take(config, "HOP_IDLE", _hop_idle) &&
			take(config, "SNAP_SQ", _snap_sq) && take(config, "MAX_LAG", _max_lag) &&
			take(config, "LOOK_LEAN", _lean) && take(config, "IDLE_AFTER", _idle_after) &&
			take(config, "LAG", _lag) && take(config, "GLANCE_TIME", _glance_time) &&
			take(config, "RAISE_TIME", _raise_time) && take(config, "FLAG_FLASH", _flag_flash) &&
			take(config, "FLAG_HURT", _flag_hurt) && take(config, "BLINK_COLUMN", blink_column) &&
			take(config, "WORRIED", worried) && take(config, "RAISED", raised) && take(config, "STRIDE", stride) &&
			config.has("BLINK_EVERY") && config.has("BLINK_TIME") && config.has("GLANCE_EVERY") &&
			config.has("RAISE_EVERY");
	if (!_ready) {
		return false;
	}
	_blink_column = (int64_t)blink_column;
	_worried = (int64_t)worried;
	_raised = (int64_t)raised;
	_stride = (int64_t)stride;
	_blink_every = config["BLINK_EVERY"];
	_blink_time = config["BLINK_TIME"];
	_glance_every = config["GLANCE_EVERY"];
	_raise_every = config["RAISE_EVERY"];
	return true;
}

PackedStringArray SwarmLookKernel::check_fields(Object *object) const {
	PackedStringArray wrong;
	ERR_FAIL_NULL_V(object, wrong);
	const SwarmNames &k = sn();
	LOOK_FIELDS(SW_CHECK)
	return wrong;
}

// `Swarm._space()` and `Swarm._keep_in()`, in that order.
void SwarmKernel::space_and_keep_in(Object *s) {
	ERR_FAIL_COND(!_ready);
	const SwarmNames &k = sn();
	Arr<PackedVector2Array> positions, velocities, push;
	Arr<PackedFloat64Array> ran;
	Arr<PackedFloat32Array> radius, give;
	Arr<PackedInt32Array> next, cell_of, cell_head, seeds;
	Arr<PackedByteArray> walls;
	positions.load(s, k.positions);
	velocities.load(s, k.velocities);
	push.load(s, k.push);
	ran.load(s, k.ran);
	radius.load(s, k.radius);
	give.load(s, k.give);
	next.load(s, k.next);
	cell_of.load(s, k.cell_of);
	cell_head.load(s, k.cell_head);
	seeds.load(s, k.seeds);
	walls.load(s, k.walls);
	const int64_t count = s->get(k.count);
	const Rect2 arena = s->get(k.arena);
	const double cell_size = s->get(k.cell);
	const int64_t gw = s->get(k.grid_w);
	const int64_t gh = s->get(k.grid_h);
	const double spacing = s->get(k.spacing);
	const int64_t moved = s->get(k.moved);
	ERR_FAIL_COND(count > positions.n || count > push.n || count > ran.n || cell_head.n < gw * gh);

	// `_space`.
	for (int64_t c = 0; c < cell_head.n; c++) {
		cell_head[c] = -1;
	}
	for (int64_t i = 0; i < push.n; i++) {
		push[i] = Vector2();
	}
	const double inv = 1.0 / cell_size;
	const double ox = arena.position.x;
	const double oy = arena.position.y;
	for (int64_t i = 0; i < count; i++) {
		const Vector2 p = positions[i] + vmul(velocities[i], ran[i]);
		positions[i] = p;
		const int64_t cy = clampi((int64_t)(((double)p.y - oy) * inv), 0, gh - 1);
		const int64_t cx = clampi((int64_t)(((double)p.x - ox) * inv), 0, gw - 1);
		const int64_t cell = cy * gw + cx;
		next[i] = cell_head[cell];
		cell_head[cell] = (int32_t)i;
		cell_of[i] = (int32_t)cell;
	}
	const double share = MIN(spacing * 2.0, 1.0);
	const int64_t first = share > 0.0 ? (moved & 1) : count;
	for (int64_t i = first; i < count; i += 2) {
		const int64_t cell = cell_of[i];
		const int64_t cy = cell / gw;
		const int64_t cx = cell - cy * gw;
		const bool right = cx + 1 < gw;
		const bool has_below = cy + 1 < gh;
		const int64_t below = cell + gw;
		int64_t j = next[i];
		const int64_t h1 = right ? cell_head[cell + 1] : -1;
		const int64_t h2 = has_below ? cell_head[below] : -1;
		const int64_t h3 = has_below && cx > 0 ? cell_head[below - 1] : -1;
		const int64_t h4 = has_below && right ? cell_head[below + 1] : -1;
		if (j < 0 && h1 < 0 && h2 < 0 && h3 < 0 && h4 < 0) {
			continue;
		}
		const Vector2 p = positions[i];
		const double r = radius[i];
		const double gi = give[i];
		Vector2 push_i = push[i];
		int64_t step = 0;
		while (true) {
			while (j >= 0) {
				const Vector2 d = positions[j] - p;
				const double reach = r + (double)radius[j];
				const double far_sq = d.length_squared();
				if (far_sq < reach * reach) {
					const double gj = give[j];
					const double gv = gi + gj;
					if (gv > 0.0) {
						const double far = std::sqrt(far_sq);
						Vector2 normal;
						if (far > 0.0001) {
							normal = d / (real_t)far;
						} else {
							normal = Vector2::from_angle((real_t)((double)((seeds[i] ^ seeds[j]) & 1023) * (TAU_D / 1024.0)));
						}
						const Vector2 shift = vmul(normal, (reach - far) * share / gv);
						push_i -= vmul(shift, gi);
						push[j] += vmul(shift, gj);
					}
				}
				j = next[j];
			}
			step += 1;
			if (step == 1) {
				j = h1;
			} else if (step == 2) {
				j = h2;
			} else if (step == 3) {
				j = h3;
			} else if (step == 4) {
				j = h4;
			} else {
				break;
			}
		}
		push[i] = push_i;
	}

	// `_keep_in`.
	const Array nodes = s->get(k.nodes);
	const Vector2 low = arena.position;
	const Vector2 high = arena.get_end();
	const double ax = arena.position.x;
	const double ay = arena.position.y;
	const bool has_walls = s->get(k.has_walls);
	const int64_t wall_w = s->get(k.wall_w);
	const int64_t wall_h = s->get(k.wall_h);
	auto walled = [&](const Vector2 &q) {
		const int64_t cx = (int64_t)(((double)q.x - (double)arena.position.x) / _wall_cell);
		const int64_t cy = (int64_t)(((double)q.y - (double)arena.position.y) / _wall_cell);
		if (cx < 0 || cy < 0 || cx >= wall_w || cy >= wall_h) {
			return false;
		}
		return walls[cy * wall_w + cx] != 0;
	};
	ERR_FAIL_COND(nodes.size() < count);
	for (int64_t i = 0; i < count; i++) {
		Vector2 p = positions[i];
		const Vector2 pu = push[i];
		if (pu != Vector2()) {
			p += pu;
		}
		p = p.clamp(low, high);
		Node2D *node = Object::cast_to<Node2D>((Object *)nodes[i]);
		ERR_CONTINUE(node == nullptr);
		if (has_walls) {
			const int64_t cx = (int64_t)(((double)p.x - ax) / _wall_cell);
			const int64_t cy = (int64_t)(((double)p.y - ay) / _wall_cell);
			if (cx >= 0 && cy >= 0 && cx < wall_w && cy < wall_h && walls[cy * wall_w + cx] != 0) {
				const Vector2 was = node->get_position();
				if (!walled(Vector2(p.x, was.y))) {
					p = Vector2(p.x, was.y);
				} else if (!walled(Vector2(was.x, p.y))) {
					p = Vector2(was.x, p.y);
				} else {
					p = was;
				}
			}
		}
		positions[i] = p;
		node->set_position(p);
	}
}

// `SwarmLook.step`'s loop over the rows, with `_blink`, `_idle_habits` and `_wait` (the look's
// own generator, its state kept per row).
void SwarmLookKernel::look_step(Object *l) {
	ERR_FAIL_COND(!_ready);
	const SwarmNames &k = sn();
	Object *s = l->get(k.swarm);
	ERR_FAIL_NULL(s);
	RandomNumberGenerator *rng = Object::cast_to<RandomNumberGenerator>((Object *)l->get(k.rng));
	ERR_FAIL_NULL(rng);
	Arr<PackedVector2Array> positions, velocities, aims, eye_point, brow_point, anchor, eyes_at, brows_at;
	Arr<PackedInt32Array> kinds, glance_x, eye_column, brow_column, style, resting;
	Arr<PackedFloat64Array> ran, hop_time, lift, hurt_left, mood_left, still_for, blink_in, blink_left;
	Arr<PackedFloat64Array> glance_in, glance_left, raise_in, raise_left;
	Arr<PackedByteArray> down, placed, hold_shown;
	Arr<PackedInt64Array> rng_state;
	positions.load(s, k.positions);
	velocities.load(s, k.velocities);
	aims.load(s, k.aims);
	kinds.load(s, k.kinds);
	// The swarm always has `ran` and `down` (the look asks, for the full actors' tests).
	ran.load(s, k.ran);
	down.load(s, k.down);
	eye_point.load(l, k.eye_point);
	brow_point.load(l, k.brow_point);
	anchor.load(l, k.anchor);
	eyes_at.load(l, k.eyes_at);
	brows_at.load(l, k.brows_at);
	glance_x.load(l, k.glance_x);
	eye_column.load(l, k.eye_column);
	brow_column.load(l, k.brow_column);
	style.load(l, k.style);
	resting.load(l, k.resting);
	hop_time.load(l, k.hop_time);
	lift.load(l, k.lift);
	hurt_left.load(l, k.hurt_left);
	mood_left.load(l, k.mood_left);
	still_for.load(l, k.still_for);
	blink_in.load(l, k.blink_in);
	blink_left.load(l, k.blink_left);
	glance_in.load(l, k.glance_in);
	glance_left.load(l, k.glance_left);
	raise_in.load(l, k.raise_in);
	raise_left.load(l, k.raise_left);
	placed.load(l, k.placed);
	hold_shown.load(l, k.hold_shown);
	rng_state.load(l, k.rng_state);
	const int64_t count = l->get(k.count_l);
	double k_delta = l->get(k.k_delta);
	double kk = l->get(k.k);
	ERR_FAIL_COND(count > positions.n || count > ran.n || count > hop_time.n || count > rng_state.n);

	// `_wait` with the shared generator.
	auto wait = [&](const PackedFloat32Array &every_by_style, int64_t st) -> double {
		const double every = every_by_style[st];
		if (every <= 0.0) {
			return INFINITY;
		}
		return every * rng->randf_range(0.7, 1.3);
	};
	for (int64_t row = 0; row < count; row++) {
		// The swarm's `ran`: the seconds the row really stepped (the step's, or less round a local stop).
		double seconds = ran[row];
		Vector2 velocity = velocities[row];
		if (seconds <= 0.0) {
			if (hold_shown[row] != 0) {
				continue;
			}
			hold_shown[row] = 1;
			seconds = 0.0;
			velocity = Vector2();
		} else {
			hold_shown[row] = 0;
		}
		const bool is_down = down[row] != 0;
		const int64_t kind = kinds[row];
		if (hurt_left[row] > 0.0) {
			hurt_left[row] = MAX(hurt_left[row] - seconds, 0.0);
		}
		const double hop = hop_time[row] + seconds;
		hop_time[row] = hop;
		const bool walking = (double)velocity.length_squared() > _hop_speed_sq;
		double up = 0.0;
		if (walking) {
			up = -std::round(std::abs(std::sin(hop * _hop_rate * PI_D)) * _hop_height);
		} else {
			up = -std::round((std::sin(hop * _hop_rate) * 0.5 + 0.5) * _hop_idle);
		}
		lift[row] = up;
		if (mood_left[row] > 0.0) {
			mood_left[row] = MAX(mood_left[row] - seconds, 0.0);
		}
		const int64_t st = style[kind];
		double blink_l = MAX(blink_left[row] - seconds, 0.0);
		const double blink_i = blink_in[row] - seconds;
		blink_in[row] = blink_i;
		if (blink_i <= 0.0) {
			// `_blink`.
			rng->set_state(rng_state[row]);
			blink_in[row] = wait(_blink_every, st);
			rng_state[row] = rng->get_state();
			blink_l = _blink_time[st];
		}
		blink_left[row] = blink_l;
		const double still = !walking ? still_for[row] + seconds : 0.0;
		still_for[row] = still;
		if (still >= _idle_after) {
			// `_idle_habits`.
			glance_left[row] = MAX(glance_left[row] - seconds, 0.0);
			raise_left[row] = MAX(raise_left[row] - seconds, 0.0);
			glance_in[row] -= seconds;
			if (glance_in[row] <= 0.0) {
				rng->set_state(rng_state[row]);
				glance_left[row] = _glance_time;
				glance_x[row] = rng->randf() < 0.5 ? -1 : 1;
				glance_in[row] = wait(_glance_every, st);
				rng_state[row] = rng->get_state();
			}
			raise_in[row] -= seconds;
			if (raise_in[row] <= 0.0) {
				rng->set_state(rng_state[row]);
				raise_left[row] = _raise_time;
				raise_in[row] = wait(_raise_every, st);
				rng_state[row] = rng->get_state();
			}
		} else {
			glance_left[row] = 0.0;
			raise_left[row] = 0.0;
		}
		Vector2 body = positions[row];
		body.y = (real_t)((double)body.y + up);
		Vector2 eye = eye_point[row];
		Vector2 brow = brow_point[row];
		if (placed[row] == 0 || (double)eye.distance_squared_to(body) > _snap_sq) {
			eye = body;
			brow = body;
			placed[row] = 1;
		}
		if (seconds != k_delta) {
			k_delta = seconds;
			kk = 1.0 - std::exp(-seconds / _lag);
		}
		eye += vmul(body - eye, kk);
		brow += vmul(eye - brow, kk);
		eye_point[row] = eye;
		brow_point[row] = brow;
		Vector2 eyes = anchor[kind] + (eye - body).clampf((real_t)-_max_lag, (real_t)_max_lag).round();
		eyes.y = (real_t)((double)eyes.y + up);
		eyes_at[row] = eyes;
		brows_at[row] = eyes + (brow - eye).clampf((real_t)-_max_lag, (real_t)_max_lag).round();
		int64_t column = _blink_column;
		if (blink_l <= 0.0 && !is_down) {
			int64_t look_x = 0;
			int64_t look_y = 0;
			if (glance_left[row] > 0.0) {
				look_x = glance_x[row];
			} else {
				const Vector2 aim = aims[row];
				look_x = (double)aim.x > _lean ? 1 : ((double)aim.x < -_lean ? -1 : 0);
				look_y = (double)aim.y > _lean ? 1 : ((double)aim.y < -_lean ? -1 : 0);
			}
			column = (look_y + 1) * 3 + look_x + 1;
		}
		eye_column[row] = (int32_t)column;
		int64_t mood = resting[kind];
		if (is_down || mood_left[row] > 0.0) {
			mood = _worried;
		} else if (raise_left[row] > 0.0) {
			mood = _raised;
		}
		brow_column[row] = (int32_t)mood;
	}
	l->set(k.k_delta, k_delta);
	l->set(k.k, kk);
}

// `SwarmLook.draw_rows` up to the renderer (see the header).
void SwarmLookKernel::draw_rows(Object *l) {
	ERR_FAIL_COND(!_ready);
	const SwarmNames &k = sn();
	Object *s = l->get(k.swarm);
	ERR_FAIL_NULL(s);
	Arr<PackedVector2Array> positions, eyes_at, brows_at;
	Arr<PackedInt32Array> kinds, filled, first, order, brow_column, eye_column;
	Arr<PackedFloat32Array> flash_left, squash;
	Arr<PackedFloat64Array> hurt_left, lift;
	Arr<PackedByteArray> has_hurt;
	positions.load(s, k.positions);
	kinds.load(s, k.kinds);
	eyes_at.load(l, k.eyes_at);
	brows_at.load(l, k.brows_at);
	filled.load(l, k.filled);
	first.load(l, k.first);
	order.load(l, k.order);
	brow_column.load(l, k.brow_column);
	eye_column.load(l, k.eye_column);
	flash_left.load(l, k.flash_left);
	squash.load(l, k.squash);
	hurt_left.load(l, k.hurt_left);
	lift.load(l, k.lift);
	has_hurt.load(l, k.has_hurt);
	const int64_t count = l->get(k.count_l);
	const Array batches = l->get(k.batches);
	Array buffers = l->get(k.buffers);
	const int64_t kinds_made = batches.size();
	ERR_FAIL_COND(filled.n < kinds_made || first.n < kinds_made || order.n < count || buffers.size() < kinds_made);
	for (int64_t i = 0; i < filled.n; i++) {
		filled[i] = 0;
	}
	for (int64_t row = 0; row < count; row++) {
		const int64_t kind = kinds[row];
		if (kind >= 0 && kind < kinds_made) {
			filled[kind] += 1;
		}
	}
	int64_t start = 0;
	for (int64_t kind = 0; kind < kinds_made; kind++) {
		const int64_t rows_of_kind = filled[kind];
		first[kind] = (int32_t)start;
		filled[kind] = (int32_t)start;
		start += rows_of_kind;
	}
	for (int64_t row = 0; row < count; row++) {
		const int64_t kind = kinds[row];
		if (kind >= 0 && kind < kinds_made) {
			order[filled[kind]] = (int32_t)row;
			filled[kind] += 1;
		}
	}
	for (int64_t kind = 0; kind < kinds_made; kind++) {
		const int64_t f = first[kind];
		const int64_t shown = filled[kind] - f;
		// Taken out of the list while written, as the GDScript does: `ptrw` then copies the buffer
		// only if the renderer still holds it.
		PackedFloat32Array buffer = buffers[kind];
		buffers[kind] = PackedFloat32Array();
		ERR_CONTINUE(buffer.size() < shown * _stride);
		float *b = buffer.ptrw();
		const bool hurt = has_hurt[kind] != 0;
		for (int64_t slot = 0; slot < shown; slot++) {
			const int64_t row = order[f + slot];
			float *at = b + slot * _stride;
			const Vector2 place = positions[row];
			double flags = (double)brow_column[row];
			if (flash_left[row] > 0.0f) {
				flags += _flag_flash;
			}
			if (hurt && hurt_left[row] > 0.0) {
				flags += _flag_hurt;
			}
			const Vector2 eyes = eyes_at[row];
			const Vector2 brows = brows_at[row];
			at[3] = place.x;
			at[7] = place.y;
			at[8] = (float)lift[row];
			at[9] = squash[row];
			at[10] = (float)eye_column[row];
			at[11] = (float)flags;
			at[12] = eyes.x;
			at[13] = eyes.y;
			at[14] = brows.x;
			at[15] = brows.y;
		}
		buffers[kind] = buffer;
	}
}

void SwarmKernel::_bind_methods() {
	ClassDB::bind_method(D_METHOD("configure", "config"), &SwarmKernel::configure);
	ClassDB::bind_method(D_METHOD("check_fields", "swarm"), &SwarmKernel::check_fields);
	ClassDB::bind_method(D_METHOD("space_and_keep_in", "swarm"), &SwarmKernel::space_and_keep_in);
}

void SwarmLookKernel::_bind_methods() {
	ClassDB::bind_method(D_METHOD("configure", "config"), &SwarmLookKernel::configure);
	ClassDB::bind_method(D_METHOD("check_fields", "look"), &SwarmLookKernel::check_fields);
	ClassDB::bind_method(D_METHOD("look_step", "look"), &SwarmLookKernel::look_step);
	ClassDB::bind_method(D_METHOD("draw_rows", "look"), &SwarmLookKernel::draw_rows);
}
