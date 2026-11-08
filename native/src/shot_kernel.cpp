// SPDX-FileCopyrightText: 2026 peterdk31 and Spellmerge contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//
// See shot_kernel.h. A note on numbers, since the results must match the GDScript to the bit:
// a GDScript `float` variable is a double, while Vector2, PackedFloat32Array and the arithmetic
// of Vector2 are single precision. So every local below is typed as the GDScript one is (double
// for a `float` var, Vector2 for a Vector2), a Vector2 times a float multiplies by the float
// rounded to single precision (as Godot's Variant operator does), and Vector2 maths uses godot-cpp's
// Vector2, which is the engine's own formulas.

#include "shot_kernel.h"
#include "dmath.h"
#include "jobs.h"
#include "packed.h"

#include <cmath>
#include <vector>

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/math.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_int64_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/packed_vector4_array.hpp>
#include <godot_cpp/variant/packed_color_array.hpp>
#include <godot_cpp/variant/utility_functions.hpp>
#include <godot_cpp/variant/variant.hpp>
#include <godot_cpp/variant/vector2i.hpp>

using namespace godot;

namespace {

// --- The manager's constants (projectile_manager.gd); `check` compares them at start. ---------
// GDScript's PI and TAU (the engine's Math_PI and Math_TAU).
constexpr double PI_D = 3.1415926535897932384626433833;
constexpr double TAU_D = 6.2831853071795864769252867666;
constexpr int MOTION_STRAIGHT = 0;
constexpr int MOTION_STILL = 1;
constexpr int MOTION_ORBIT = 2;
constexpr int F_GHOST = 8;
constexpr int S_IDLE = 0;
constexpr int S_MOVING = 1;
constexpr int S_DONE = 4;
constexpr int S_STUCK = 5;
constexpr int S_EXPIRE = 6;
constexpr int S_FROZEN = 9;
constexpr double GRID_CELL = 64.0;
constexpr double WALL_CELL = 8.0;
constexpr int MAX_WALL_VISITS = 64;
constexpr int S_HELD = 2;
constexpr int S_RETURNING = 3;
constexpr int S_WAITING = 8;
constexpr int S_GONE = 7;
constexpr int F_TURNED = 64;
constexpr int F_WAVE = 128;
constexpr int F_DEFERRED = 256;
constexpr int CASTER_BODY = -1;
constexpr int CASTER_POINT = -2;
constexpr double SPIRAL_PERIOD = 0.5;
constexpr double RETURN_BEND = PI_D / 3.0;
// Homing (`_pass_homing`, `_home_pick`).
constexpr int B_GROWTH = 1;
constexpr int B_LINGER = 2;
constexpr int B_ORBIT = 3;
constexpr int B_RETURN = 4;
constexpr int B_CURVE = 5;
constexpr int B_HOMING = 6;
constexpr int B_SPIRAL = 7;
constexpr int B_MOVE = 8;
constexpr int AFTER_HITS = 9;
constexpr int HOMING_PERIOD = 4;
constexpr double HOMING_DRIFT = 24.0; // SpellLimits.HOMING_DRIFT
// The behaviours a waiting homing shot may also have for the native hit pass to catch it up itself:
// none of the passes after homing that run before the hits.
constexpr int64_t AFTER_HOMING_MASK = ((1 << AFTER_HITS) - 1) & ~((1 << (B_HOMING + 1)) - 1);
// Tails and drawing.
constexpr double TAIL_JUMP = 96.0;
// Tails as motes (the manager's SPARK_TAIL, `_lay_tail`) and a birth's numbers (SPARK_*).
constexpr int SPARK_BIRTH_STRIDE = 12;
constexpr int SPARK_X = 0;
constexpr int SPARK_Y = 1;
constexpr int SPARK_BACK_X = 2;
constexpr int SPARK_BACK_Y = 3;
constexpr int SPARK_KIND = 4;
constexpr int SPARK_RAMP = 5;
constexpr int SPARK_LOOK = 6;
constexpr int SPARK_CORE = 7;
constexpr int SPARK_TAG = 10;
constexpr int SPARK_TAG_BITS = 12;
constexpr int SPARK_TAIL = 60;
constexpr int TAIL_KINDS = 3;
constexpr double TAIL_SPACING = 2.0;
constexpr double TAIL_PLAYER_SHARE = 0.25;
constexpr double ORBIT_GROW = 0.25;
constexpr int HEAD_LIVE = 1;
constexpr int HEAD_ORBIT = 2;
constexpr int DRAW_STRIDE = 16;
constexpr int KIND_BOLT = 1;
constexpr int KIND_RUNE = 2;
constexpr double KIND_STEPS = 16.0;
constexpr double RUNE_TRACE = 0.25;
constexpr double TRACE_FROM = 0.02;
constexpr double TRACE_SPAN = 0.42;
constexpr int BATCH_BOLT = 0;
constexpr int BATCH_STILL = 1;
constexpr int BATCH_ORBIT = 2;
constexpr int BATCH_ENEMY = 3;
constexpr int BATCH_ENEMY_STILL = 4;
constexpr int BATCH_BODY_FIRST = 5;
// `_draw_out`: its totals first (DRAW_*), then each batch's rows written from DRAW_OUT_FIRST on; how
// many batches there are is the manager's `_batch_total`, which grows with the card bodies.
constexpr int DRAW_ASKED = 0;
constexpr int DRAW_SHOTS = 2;
constexpr int DRAW_ENEMY = 3;
constexpr int DRAW_BIRTHS = 4;
constexpr int DRAW_TAIL = 5;
constexpr int DRAW_OUT_FIRST = 6;
constexpr int LOOK_GRID = 24;
constexpr double LOOK_CELL_PER_RADIUS = 0.25;
constexpr int LOOK_ZOOM_MAX = 15;
constexpr double SPECK_RADIUS = 2.0;
constexpr int64_t LOOK_ENEMY_RAMP = 1 << 22;
constexpr int64_t EMITTING_MASK = ((1 << 21) - 1) & ~(1 << 10);
constexpr int PARTICLES_PER_SHOT_MAX = 12;
// core/actors: the first ramp that is not a hat's, and "no team".
constexpr int RAMP_ENEMY = 4;
constexpr int TEAM_NONE = -1;
// The threat grid.
constexpr int THREAT_SPAN_MAX = 16;
// The slots one task of a loop over every shot takes (jobs.h: fixed, whatever the threads).
constexpr int64_t SLOT_SPAN = 512;

// What `hits` hands back to GDScript for the shot it stopped at (its n x 2 plus one of these).
constexpr int64_t YIELD_WHOLE = 0; // the whole shot: its end, the bounds, a wall
constexpr int64_t YIELD_FOUND = 1; // its hits (`_cand_*`, `_cand_found` of them), then what it left
// What `hits` returns on an error (bad sizes) at its n-th shot: HANDED_ERROR - n. The manager then
// takes every shot from n on itself.
constexpr int64_t HANDED_ERROR = -2;

// Every member of the manager a kernel reads: its C++ name, the GDScript member and its type. One
// list, so `check_fields` sees each name the kernel uses (a renamed member fails there, not silently).
#define MANAGER_FIELDS(X) \
	X(alive, "_alive", PACKED_BYTE_ARRAY) \
	X(freeze, "_freeze", PACKED_FLOAT32_ARRAY) \
	X(life, "_life", PACKED_FLOAT32_ARRAY) \
	X(skip_on, "_skip_on", PACKED_FLOAT32_ARRAY) \
	X(skip_near, "_skip_near", PACKED_FLOAT32_ARRAY) \
	X(pos, "_pos", PACKED_VECTOR2_ARRAY) \
	X(prev, "_prev", PACKED_VECTOR2_ARRAY) \
	X(untested, "_untested", PACKED_VECTOR2_ARRAY) \
	X(state, "_state", PACKED_BYTE_ARRAY) \
	X(motion, "_motion", PACKED_BYTE_ARRAY) \
	X(vel, "_vel", PACKED_VECTOR2_ARRAY) \
	X(flags, "_flags", PACKED_INT32_ARRAY) \
	X(layers, "_layers", PACKED_INT32_ARRAY) \
	X(actor, "_actor", PACKED_INT32_ARRAY) \
	X(radius, "_radius", PACKED_FLOAT32_ARRAY) \
	X(skip_id, "_skip_id", PACKED_INT64_ARRAY) \
	X(mem_head, "_mem_head", PACKED_INT32_ARRAY) \
	X(target_pos, "_target_pos", PACKED_VECTOR2_ARRAY) \
	X(target_radius, "_target_radius", PACKED_FLOAT32_ARRAY) \
	X(target_owner, "_target_owner", PACKED_INT32_ARRAY) \
	X(target_layer, "_target_layer", PACKED_INT32_ARRAY) \
	X(target_id, "_target_id", PACKED_INT64_ARRAY) \
	X(target_key, "_target_key", PACKED_INT64_ARRAY) \
	X(target_next, "_target_next", PACKED_INT32_ARRAY) \
	X(target_mark, "_target_mark", PACKED_INT32_ARRAY) \
	X(target_entry, "_target_entry", PACKED_INT32_ARRAY) \
	X(cell_head, "_cell_head", PACKED_INT32_ARRAY) \
	X(cell_count, "_cell_count", PACKED_INT32_ARRAY) \
	X(cell_box, "_cell_box", PACKED_VECTOR4_ARRAY) \
	X(cell_filled, "_cell_filled", PACKED_INT32_ARRAY) \
	X(mem_id, "_mem_id", PACKED_INT64_ARRAY) \
	X(mem_target, "_mem_target", PACKED_INT32_ARRAY) \
	X(mem_seen, "_mem_seen", PACKED_INT32_ARRAY) \
	X(mem_next, "_mem_next", PACKED_INT32_ARRAY) \
	X(cand_target, "_cand_target", PACKED_INT32_ARRAY) \
	X(cand_along, "_cand_along", PACKED_FLOAT32_ARRAY) \
	X(cand_point, "_cand_point", PACKED_VECTOR2_ARRAY) \
	X(wall_cells, "_wall_cells", PACKED_BYTE_ARRAY) \
	X(wall_w, "_wall_w", INT) \
	X(wall_h, "_wall_h", INT) \
	X(has_walls, "_has_walls", BOOL) \
	X(bounds, "_bounds", RECT2) \
	X(grid_x, "_grid_x", FLOAT) \
	X(grid_y, "_grid_y", FLOAT) \
	X(grid_w, "_grid_w", INT) \
	X(grid_h, "_grid_h", INT) \
	X(max_target_radius, "_max_target_radius", FLOAT) \
	X(grid_fill, "_grid_fill", INT) \
	X(mem_step, "_mem_step", INT) \
	X(work_left, "_work_left", INT) \
	X(starved_at, "_starved_at", INT) \
	X(mark_stamp, "_mark_stamp", INT) \
	X(mem_free, "_mem_free", INT) \
	X(cand_found, "_cand_found", INT) \
	X(high, "_high", INT) \
	X(sim_time, "sim_time", FLOAT) \
	X(born, "_born", PACKED_FLOAT32_ARRAY) \
	X(body, "_body", PACKED_BYTE_ARRAY) \
	X(batch_total, "_batch_total", INT) \
	X(orbit_centre, "_orbit_centre", PACKED_VECTOR2_ARRAY) \
	X(seq, "_seq", PACKED_INT64_ARRAY) \
	X(drawn_seq, "_drawn_seq", PACKED_INT64_ARRAY) \
	X(drawn_radius, "_drawn_radius", PACKED_FLOAT32_ARRAY) \
	X(drawn_look, "_drawn_look", PACKED_INT32_ARRAY) \
	X(drawn_batch, "_drawn_batch", PACKED_BYTE_ARRAY) \
	X(drawn_color, "_drawn_color", PACKED_COLOR_ARRAY) \
	X(drawn_size, "_drawn_size", PACKED_FLOAT32_ARRAY) \
	X(drawn_particles, "_drawn_particles", PACKED_INT32_ARRAY) \
	X(look, "_look", PACKED_INT32_ARRAY) \
	X(ramp, "_ramp", PACKED_INT32_ARRAY) \
	X(core, "_core", PACKED_COLOR_ARRAY) \
	X(batch_counts, "_batch_counts", PACKED_INT32_ARRAY) \
	X(anchors, "_anchors", PACKED_VECTOR2_ARRAY) \
	X(draw_out, "_draw_out", PACKED_INT32_ARRAY) \
	X(rooms, "_rooms", PACKED_INT32_ARRAY) \
	X(tail_from, "_tail_from", PACKED_VECTOR2_ARRAY) \
	X(tail_carry, "_tail_carry", PACKED_FLOAT32_ARRAY) \
	X(tail_n, "_tail_n", PACKED_INT32_ARRAY) \
	X(tag, "_tag", PACKED_INT64_ARRAY) \
	X(spark_births, "spark_births", PACKED_FLOAT32_ARRAY) \
	X(tail_births_on, "tail_births_on", BOOL) \
	X(tail_births_cap, "tail_births_cap", INT) \
	X(tail_thin_most, "tail_thin_most", INT) \
	X(group, "_group", PACKED_INT32_ARRAY) \
	X(group_end, "_group_end", PACKED_INT32_ARRAY) \
	X(by_group, "_by_group", PACKED_INT32_ARRAY) \
	X(group_tail, "_group_tail", PACKED_FLOAT32_ARRAY) \
	X(group_ask, "_group_ask", PACKED_FLOAT32_ARRAY) \
	X(group_spacing, "_group_spacing", PACKED_FLOAT32_ARRAY) \
	X(team, "_team", PACKED_INT32_ARRAY) \
	X(threat_slot, "threat_slot", INT) \
	X(threat_away, "threat_away", VECTOR2) \
	X(threat_cell, "_threat_cell", FLOAT) \
	X(threat_x, "_threat_x", FLOAT) \
	X(threat_y, "_threat_y", FLOAT) \
	X(threat_w, "_threat_w", INT) \
	X(threat_h, "_threat_h", INT) \
	X(threat_head, "_threat_head", PACKED_INT32_ARRAY) \
	X(threat_slot_list, "_threat_slot", PACKED_INT32_ARRAY) \
	X(threat_next, "_threat_next", PACKED_INT32_ARRAY) \
	X(threat_over, "_threat_over", PACKED_INT32_ARRAY) \
	X(threat_over_count, "_threat_over_count", INT) \
	X(threat_seen, "_threat_seen", PACKED_INT32_ARRAY) \
	X(threat_stamp, "_threat_stamp", INT) \
	X(growth, "_growth", PACKED_FLOAT32_ARRAY) \
	X(curve_from, "_curve_from", PACKED_FLOAT32_ARRAY) \
	X(curve_to, "_curve_to", PACKED_FLOAT32_ARRAY) \
	X(curve_ease, "_curve_ease", PACKED_FLOAT32_ARRAY) \
	X(curve_speed, "_curve_speed", PACKED_FLOAT32_ARRAY) \
	X(radius0, "_radius0", PACKED_FLOAT32_ARRAY) \
	X(hold, "_hold", PACKED_FLOAT32_ARRAY) \
	X(linger, "_linger", PACKED_FLOAT32_ARRAY) \
	X(span, "_span", PACKED_FLOAT32_ARRAY) \
	X(caster_slot, "_caster_slot", PACKED_INT32_ARRAY) \
	X(caster_at, "_caster_at", PACKED_VECTOR2_ARRAY) \
	X(orbit_angle, "_orbit_angle", PACKED_FLOAT32_ARRAY) \
	X(orbit_speed, "_orbit_speed", PACKED_FLOAT32_ARRAY) \
	X(orbit_radius, "_orbit_radius", PACKED_FLOAT32_ARRAY) \
	X(wave, "_wave", PACKED_FLOAT32_ARRAY) \
	X(wave_age, "_wave_age", PACKED_FLOAT32_ARRAY) \
	X(base, "_base", PACKED_VECTOR2_ARRAY) \
	X(speed, "_speed", PACKED_FLOAT32_ARRAY) \
	X(members, "_members", PACKED_INT32_ARRAY) \
	X(step_index, "_step_index", INT) \
	X(home_at, "_home_at", PACKED_VECTOR2_ARRAY) \
	X(home_range, "_home_range", PACKED_FLOAT32_ARRAY) \
	X(home_target, "_home_target", PACKED_INT64_ARRAY) \
	X(turn, "_turn", PACKED_FLOAT32_ARRAY) \
	X(kinds, "_kinds", PACKED_INT32_ARRAY) \
	X(wait_state, "_wait_state", PACKED_BYTE_ARRAY) \
	X(wait_from, "_wait_from", PACKED_BYTE_ARRAY) \
	X(targets, "_targets", ARRAY) \
	X(target_team, "_target_team", PACKED_INT32_ARRAY)

struct Names {
#define SM_DECLARE(id, gd, type) StringName id;
	MANAGER_FIELDS(SM_DECLARE)
#undef SM_DECLARE
	Names() {
#define SM_INIT(id, gd, type) id = StringName(gd);
		MANAGER_FIELDS(SM_INIT)
#undef SM_INIT
	}
};

Names *names = nullptr;

// --- Homing ----------------------------------------------------------------------------------

// The arrays `_pass_homing` turns a shot with.
struct Steer {
	Arr<PackedVector2Array> home_at, vel;
	Arr<PackedFloat32Array> turn;
	void load(Object *m) {
		const Names &k = *names;
		home_at.load(m, k.home_at);
		vel.load(m, k.vel);
		turn.load(m, k.turn);
	}
	// `_pass_homing` after its search: turn the shot in `slot` toward `_home_at`.
	void steer(int64_t slot, Vector2 *pos, const Vector2 *prev, double delta) {
		const Vector2 goal = home_at[slot];
		if (!goal.is_finite()) {
			return;
		}
		const Vector2 want = goal - prev[slot];
		if (want.is_zero_approx()) {
			return;
		}
		const Vector2 velocity = vel[slot];
		if (velocity.is_zero_approx()) {
			pos[slot] = prev[slot] + want.limit_length((real_t)(HOMING_DRIFT * delta));
			return;
		}
		const double most = (double)turn[slot] * (double)velocity.length() * delta;
		vel[slot] = dmath::rotated(velocity, clampf(dmath::angle_to(velocity, want), -most, most));
		pos[slot] = prev[slot] + vmul(vel[slot], delta);
	}
};

// --- The hit pass ------------------------------------------------------------------------------

// Everything `_pass_hits` and `_hit_test` read, for one call.
struct HitPass {
	Arr<PackedByteArray> state, motion, wall_cells;
	Arr<PackedVector2Array> pos, prev, target_pos, cand_point, untested;
	Arr<PackedInt32Array> flags, layers, actor, mem_head;
	Arr<PackedFloat32Array> radius, skip_on, skip_near, target_radius, cand_along;
	// `target_id` finds a target's node (instance ids: equality only); `target_key` is its identity,
	// which the shots keep (online-ready N5).
	Arr<PackedInt64Array> skip_id, target_id, target_key, mem_id;
	Arr<PackedInt32Array> target_owner, target_layer, target_next, target_mark, target_entry;
	Arr<PackedInt32Array> cell_head, cell_count, cell_filled;
	Arr<PackedVector4Array> cell_box;
	Arr<PackedInt32Array> mem_target, mem_seen, mem_next, cand_target;
	int64_t wall_w = 0, wall_h = 0, grid_w = 0, grid_h = 0, grid_fill = 0, mem_step = 0;
	int64_t work_left = 0, starved_at = 0, mark_stamp = 0, mem_free = 0;
	bool has_walls = false;
	Rect2 bounds;
	double grid_x = 0.0, grid_y = 0.0, max_target_radius = 0.0;

	bool targets_loaded = false;
	// `_untested`, read only for a deferred shot (`defer`, `scan`).
	bool untested_loaded = false;
	// For catching up a waiting homing shot (`load_homing`).
	bool homing_loaded = false;
	Steer steer;
	Arr<PackedInt32Array> kinds, team, target_team;
	Arr<PackedByteArray> wait_state, wait_from;
	Arr<PackedFloat32Array> home_range;
	Arr<PackedInt64Array> home_target, seq;
	int64_t step_index = 0;

	void load_homing(Object *m) {
		const Names &k = *names;
		homing_loaded = true;
		steer.load(m);
		kinds.load(m, k.kinds);
		team.load(m, k.team);
		target_team.load(m, k.target_team);
		wait_state.load(m, k.wait_state);
		wait_from.load(m, k.wait_from);
		home_range.load(m, k.home_range);
		home_target.load(m, k.home_target);
		seq.load(m, k.seq);
		step_index = m->get(k.step_index);
	}

	// `_home_pick` for the shot in `slot` (any way round).
	int64_t home_pick(int64_t slot, const Vector2 &origin) {
		const int64_t caster = actor[slot];
		const int64_t tm = team[slot];
		const int64_t lay = layers[slot];
		const double within = home_range[slot];
		const int64_t keep = home_target[slot];
		const int64_t pick_seed = seq[slot];
		const int64_t stamp = mark_memory(slot);
		int64_t pick = -1;
		int64_t seen = 0;
		// `_query_cells`.
		const Vector2 pad = vmul(Vector2(1, 1), MAX(within, 0.0) + max_target_radius);
		const Vector2 low = origin - pad;
		const Vector2 high = origin + pad;
		const int64_t x0 = clampi(floori(((double)low.x - (double)bounds.position.x) / GRID_CELL), 0, grid_w - 1);
		const int64_t y0 = clampi(floori(((double)low.y - (double)bounds.position.y) / GRID_CELL), 0, grid_h - 1);
		const int64_t x1 = clampi(floori(((double)high.x - (double)bounds.position.x) / GRID_CELL), 0, grid_w - 1);
		const int64_t y1 = clampi(floori(((double)high.y - (double)bounds.position.y) / GRID_CELL), 0, grid_h - 1);
		for (int64_t y = y0; y <= y1; y++) {
			for (int64_t x = x0; x <= x1; x++) {
				int64_t t = cell_head[y * grid_w + x];
				while (t >= 0) {
					work_left -= 1;
					// `is_instance_valid(_targets[t])`: the node of the id kept beside it still exists.
					if ((target_layer[t] & lay) != 0 && (caster < 0 || target_owner[t] != caster) &&
							(tm == TEAM_NONE || target_team[t] != tm) &&
							::godot::gdextension_interface::object_get_instance_from_id((GDObjectInstanceID)target_id[t]) != nullptr &&
							target_mark[t] != stamp) {
						const Vector2 to_target = target_pos[t] - origin;
						const double reach = within + (double)target_radius[t];
						if ((double)to_target.length_squared() <= reach * reach) {
							if (keep != 0 && target_key[t] == keep) {
								return t;
							}
							// Reservoir pick, with the engine's own hash.
							seen += 1;
							const int64_t h = UtilityFunctions::hash(Variant(Vector2i((int32_t)pick_seed, (int32_t)seen)));
							if (UtilityFunctions::posmod(h, seen) == 0) {
								pick = t;
							}
						}
					}
					t = target_next[t];
				}
			}
		}
		return pick;
	}

	// `_catch_up` of a shot that waited only for its homing search, with `_pass_homing` for it alone.
	void catch_up_homing(int64_t slot, double delta) {
		state[slot] = wait_state[slot];
		const int64_t st = state[slot];
		if (st != S_MOVING && st != S_RETURNING) {
			return;
		}
		if (((slot + step_index) % HOMING_PERIOD) == 0 && work_left > 0) {
			// `_homing_point`.
			const int64_t t = home_pick(slot, prev[slot]);
			home_target[slot] = t >= 0 ? target_key[t] : 0;
			steer.home_at[slot] = t >= 0 ? target_pos[t] : Vector2(INFINITY, INFINITY);
		}
		if (st == S_RETURNING) {
			return;
		}
		steer.steer(slot, pos.p, prev.p, delta);
	}

	// What every shot's turn reads (a turn handed back to GDScript reads no more).
	void load(Object *m) {
		const Names &k = *names;
		state.load(m, k.state);
		motion.load(m, k.motion);
		wall_cells.load(m, k.wall_cells);
		pos.load(m, k.pos);
		prev.load(m, k.prev);
		flags.load(m, k.flags);
		layers.load(m, k.layers);
		target_id.load(m, k.target_id);
		target_key.load(m, k.target_key);
		wall_w = m->get(k.wall_w);
		wall_h = m->get(k.wall_h);
		work_left = m->get(k.work_left);
		starved_at = m->get(k.starved_at);
		has_walls = m->get(k.has_walls);
		bounds = m->get(k.bounds);
	}

	void load_untested(Object *m) {
		if (!untested_loaded) {
			untested_loaded = true;
			untested.load(m, names->untested);
		}
	}

	// `_defer`.
	void defer(Object *m, int64_t slot) {
		const int64_t flg = flags[slot];
		if ((flg & F_DEFERRED) == 0) {
			load_untested(m);
			flags[slot] = (int32_t)(flg | F_DEFERRED);
			untested[slot] = prev[slot];
		}
	}

	// What a hit test reads, the first time one runs in a call.
	void load_targets(Object *m) {
		const Names &k = *names;
		targets_loaded = true;
		load_untested(m);
		target_pos.load(m, k.target_pos);
		cand_point.load(m, k.cand_point);
		actor.load(m, k.actor);
		mem_head.load(m, k.mem_head);
		radius.load(m, k.radius);
		skip_on.load(m, k.skip_on);
		skip_near.load(m, k.skip_near);
		target_radius.load(m, k.target_radius);
		cand_along.load(m, k.cand_along);
		skip_id.load(m, k.skip_id);
		mem_id.load(m, k.mem_id);
		target_owner.load(m, k.target_owner);
		target_layer.load(m, k.target_layer);
		target_next.load(m, k.target_next);
		target_mark.load(m, k.target_mark);
		target_entry.load(m, k.target_entry);
		cell_head.load(m, k.cell_head);
		cell_count.load(m, k.cell_count);
		cell_filled.load(m, k.cell_filled);
		cell_box.load(m, k.cell_box);
		mem_target.load(m, k.mem_target);
		mem_seen.load(m, k.mem_seen);
		mem_next.load(m, k.mem_next);
		cand_target.load(m, k.cand_target);
		grid_w = m->get(k.grid_w);
		grid_h = m->get(k.grid_h);
		grid_fill = m->get(k.grid_fill);
		mem_step = m->get(k.mem_step);
		mark_stamp = m->get(k.mark_stamp);
		mem_free = m->get(k.mem_free);
		grid_x = m->get(k.grid_x);
		grid_y = m->get(k.grid_y);
		max_target_radius = m->get(k.max_target_radius);
	}

	// The counters back to the manager (only what this call could have changed).
	void save(Object *m, int64_t found, int64_t starved_before) const {
		const Names &k = *names;
		if (starved_at != starved_before) {
			m->set(k.starved_at, starved_at);
		}
		if (targets_loaded) {
			m->set(k.work_left, work_left);
			m->set(k.mark_stamp, mark_stamp);
			m->set(k.mem_free, mem_free);
		}
		if (found > 0) {
			m->set(k.cand_found, found);
		}
	}

	// `_wall_hit` with its default visits.
	double wall_hit(const Vector2 &from, const Vector2 &to) {
		if (!has_walls) {
			return -1.0;
		}
		const Vector2 start = (from - bounds.position) / (real_t)WALL_CELL;
		const Vector2 delta = (to - from) / (real_t)WALL_CELL;
		int64_t cx = floori(start.x);
		int64_t cy = floori(start.y);
		// `start.x + delta.x` in GDScript adds two floats, which are doubles.
		const int64_t end_x = floori((double)start.x + (double)delta.x);
		const int64_t end_y = floori((double)start.y + (double)delta.y);
		if (cx == end_x && cy == end_y) {
			if (cx >= 0 && cx < wall_w && cy >= 0 && cy < wall_h && wall_cells[cy * wall_w + cx] != 0) {
				return 0.0;
			}
			return -1.0;
		}
		if (std::abs(end_x - cx) <= 1 && std::abs(end_y - cy) <= 1 && MIN(cx, end_x) >= 0 && MAX(cx, end_x) < wall_w &&
				MIN(cy, end_y) >= 0 && MAX(cy, end_y) < wall_h) {
			const int64_t row0 = cy * wall_w;
			const int64_t row1 = end_y * wall_w;
			if (wall_cells[row0 + cx] == 0 && wall_cells[row0 + end_x] == 0 && wall_cells[row1 + cx] == 0 &&
					wall_cells[row1 + end_x] == 0) {
				return -1.0;
			}
		}
		const int64_t step_x = delta.x > 0.0f ? 1 : -1;
		const int64_t step_y = delta.y > 0.0f ? 1 : -1;
		double next_x = INFINITY;
		double next_y = INFINITY;
		double per_x = INFINITY;
		double per_y = INFINITY;
		if (delta.x != 0.0f) {
			per_x = std::abs(1.0 / (double)delta.x);
			next_x = ((double)(cx + (step_x > 0 ? 1 : 0)) - (double)start.x) / (double)delta.x;
		}
		if (delta.y != 0.0f) {
			per_y = std::abs(1.0 / (double)delta.y);
			next_y = ((double)(cy + (step_y > 0 ? 1 : 0)) - (double)start.y) / (double)delta.y;
		}
		double t = 0.0;
		const int64_t full = std::abs(end_x - cx) + std::abs(end_y - cy) + 1;
		const int64_t visits = MIN(full, (int64_t)MAX_WALL_VISITS);
		for (int64_t v = 0; v < visits; v++) {
			if (cx >= 0 && cx < wall_w && cy >= 0 && cy < wall_h && wall_cells[cy * wall_w + cx] != 0) {
				return t;
			}
			if (next_x < next_y) {
				t = next_x;
				next_x += per_x;
				cx += step_x;
			} else {
				t = next_y;
				next_y += per_y;
				cy += step_y;
			}
			if (t > 1.0) {
				return -1.0;
			}
		}
		return full > visits ? t : -1.0;
	}

	// `_cell_info`.
	void cell_info(int64_t cell) {
		cell_filled[cell] = (int32_t)grid_fill;
		int64_t count = 0;
		int64_t t = cell_head[cell];
		if (t < 0) {
			cell_count[cell] = 0;
			return;
		}
		Vector2 low = Vector2(INFINITY, INFINITY);
		Vector2 high = -Vector2(INFINITY, INFINITY);
		while (t >= 0) {
			const Vector2 centre = target_pos[t];
			const double r = target_radius[t];
			low = vmin(low, centre - Vector2((real_t)r, (real_t)r));
			high = vmax(high, centre + Vector2((real_t)r, (real_t)r));
			count += 1;
			t = target_next[t];
		}
		cell_count[cell] = (int32_t)count;
		cell_box[cell] = Vector4(low.x, low.y, high.x, high.y);
	}

	// `_mark_memory`.
	int64_t mark_memory(int64_t slot) {
		mark_stamp += 1;
		const int64_t targets = target_key.n;
		int64_t before = -1;
		int64_t at = mem_head[slot];
		while (at >= 0) {
			const int64_t next = mem_next[at];
			int64_t t = mem_target[at];
			if (t < 0 || t >= targets || target_key[t] != mem_id[at]) {
				t = -1;
				for (int64_t i = 0; i < targets; i++) {
					if (target_key[i] == mem_id[at]) {
						t = i;
						break;
					}
				}
				mem_target[at] = (int32_t)t;
			}
			if (t < 0) {
				if (before < 0) {
					mem_head[slot] = (int32_t)next;
				} else {
					mem_next[before] = (int32_t)next;
				}
				mem_next[at] = (int32_t)mem_free;
				mem_free = at;
			} else {
				target_mark[t] = (int32_t)mark_stamp;
				target_entry[t] = (int32_t)at;
				before = at;
			}
			at = next;
		}
		return mark_stamp;
	}

	// `_forget_left`.
	void forget_left(int64_t slot) {
		int64_t before = -1;
		int64_t at = mem_head[slot];
		while (at >= 0) {
			const int64_t next = mem_next[at];
			if (mem_seen[at] != mem_step) {
				if (before < 0) {
					mem_head[slot] = (int32_t)next;
				} else {
					mem_next[before] = (int32_t)next;
				}
				mem_next[at] = (int32_t)mem_free;
				mem_free = at;
			} else {
				before = at;
			}
			at = next;
		}
	}

	// `_keep_candidate` (the manager sized the arrays for every target).
	int64_t keep_candidate(int64_t found, int64_t t, double along, const Vector2 &closest) {
		int64_t at = found;
		while (at > 0 && (double)cand_along[at - 1] > along) {
			cand_target[at] = cand_target[at - 1];
			cand_along[at] = cand_along[at - 1];
			cand_point[at] = cand_point[at - 1];
			at -= 1;
		}
		cand_target[at] = (int32_t)t;
		cand_along[at] = (float)along;
		cand_point[at] = closest;
		return found + 1;
	}

	// `_hit_test` up to its hits (not for a solid shot): the candidates, nearest first; returns how many.
	int64_t scan(int64_t slot) {
		Vector2 from = prev[slot];
		const Vector2 to = pos[slot];
		// A shot the budget passed over sweeps its whole path since its last test (`_defer`).
		if ((flags[slot] & F_DEFERRED) != 0) {
			flags[slot] &= ~F_DEFERRED;
			from = untested[slot];
		}
		// Where the step starts: a payload still on the body that fired it there is not clear of it.
		const Vector2 start = from;
		const double rad = radius[slot];
		const Vector2 lowest = vmin(from, to);
		const Vector2 highest = vmax(from, to);
		const Vector2 pad = vmul(Vector2(1, 1), rad + max_target_radius);
		const Vector2 low = lowest - pad;
		const Vector2 high = highest + pad;
		const int64_t x0 = clampi(floori(((double)low.x - grid_x) / GRID_CELL), 0, grid_w - 1);
		const int64_t x1 = clampi(floori(((double)high.x - grid_x) / GRID_CELL), 0, grid_w - 1);
		const int64_t y0 = clampi(floori(((double)low.y - grid_y) / GRID_CELL), 0, grid_h - 1);
		const int64_t y1 = clampi(floori(((double)high.y - grid_y) / GRID_CELL), 0, grid_h - 1);
		const Vector2 margin = vmul(Vector2(1, 1), rad + 0.05);
		const Vector2 near_low = lowest - margin;
		const Vector2 near_high = highest + margin;
		bool looking = false;
		Vector2 path;
		double path_sq = 0.0;
		Vector2 middle;
		double half = 0.0;
		int64_t lay = 0;
		const bool spared = skip_on[slot] > 0.0f && still_spares(slot, start, to - start);
		int64_t stamp = 0;
		int64_t found = 0;
		for (int64_t y = y0; y <= y1; y++) {
			for (int64_t x = x0; x <= x1; x++) {
				const int64_t cell = y * grid_w + x;
				if (cell_filled[cell] != grid_fill) {
					cell_info(cell);
				}
				const int64_t in_cell = cell_count[cell];
				if (in_cell == 0) {
					continue;
				}
				work_left -= in_cell;
				const Vector4 box = cell_box[cell];
				if (box.x > near_high.x || box.y > near_high.y || box.z < near_low.x || box.w < near_low.y) {
					continue;
				}
				if (!looking) {
					looking = true;
					path = to - from;
					path_sq = path.length_squared();
					middle = (from + to) * (real_t)0.5;
					half = std::sqrt(path_sq) * 0.5 + 0.01;
					lay = layers[slot];
					stamp = mark_memory(slot);
				}
				int64_t t = cell_head[cell];
				while (t >= 0) {
					const Vector2 centre = target_pos[t];
					const double reach = rad + (double)target_radius[t];
					const double far = half + reach;
					if ((double)middle.distance_squared_to(centre) > far * far) {
						t = target_next[t];
						continue;
					}
					if ((target_layer[t] & lay) == 0) {
						t = target_next[t];
						continue;
					}
					double along = 0.0;
					if (path_sq > 0.0) {
						along = clampf((double)(centre - from).dot(path) / path_sq, 0.0, 1.0);
					}
					const Vector2 closest = from + vmul(path, along);
					if ((double)closest.distance_squared_to(centre) > reach * reach) {
						t = target_next[t];
						continue;
					}
					if (target_mark[t] == stamp) {
						mem_seen[target_entry[t]] = (int32_t)mem_step;
						t = target_next[t];
						continue;
					}
					if (spared && skip_id[slot] == target_key[t]) {
						t = target_next[t];
						continue;
					}
					found = keep_candidate(found, t, along, closest);
					t = target_next[t];
				}
			}
		}
		// Clear of the body it started on, and not coming back across it: it hits it from now.
		if (skip_on[slot] > 0.0f && !spared) {
			skip_on[slot] = 0.0f;
		}
		return found;
	}

	// `_still_spares`.
	bool still_spares(int64_t slot, const Vector2 &start, const Vector2 &way) {
		int64_t t = -1;
		for (int64_t i = 0; skip_id[slot] != 0 && i < target_key.n; i++) {
			if (target_key[i] == skip_id[slot]) {
				t = i;
				break;
			}
		}
		if (t < 0 || (target_layer[t] & layers[slot]) == 0) {
			return false;
		}
		const double reach = (double)radius[slot] + (double)target_radius[t];
		const Vector2 to_centre = target_pos[t] - start;
		const double apart_sq = (double)to_centre.length_squared();
		if (apart_sq <= reach * reach) {
			return true;
		}
		const double near = (double)skip_near[slot];
		if (near <= 0.0) {
			return false;
		}
		const double ahead = (double)to_centre.dot(way);
		const double within = reach + near;
		if (ahead <= 0.0 || (double)(to_centre - way).length_squared() > within * within) {
			return false;
		}
		// The square of how far the body's centre stands off the shot's line.
		return apart_sq - ahead * ahead / (double)way.length_squared() <= reach * reach;
	}
};

// A tail's first half (`plan_tail` in `draw_shots`): where the shot is drawn, how far it went, and
// the births its carry would lay to the end of its path.
struct TailPlan {
	Vector2 at;
	double d = 0.0;
	int64_t births = 0;
	bool in_reach = false;
};

} // namespace

// What the kernel keeps between its calls, for its own work only (no array of the manager's).
struct ShotKernel::Scratch {
	// What each span of a drawing loop counted: its shots per batch, turned into where its rows start.
	std::vector<int64_t> draw_counts;
	// Each batch's buffer to write, its room and its rows written (`draw_shots`), sized to the batches.
	std::vector<float *> out_buffer;
	std::vector<int64_t> room;
	std::vector<int64_t> used;
	// Each slot's tail plan.
	std::vector<TailPlan> tails;
};

ShotKernel::ShotKernel() :
		_width(jobs::default_width()), _scratch(new Scratch()) {
	if (names == nullptr) {
		names = new Names();
	}
}

ShotKernel::~ShotKernel() {
	delete _scratch;
}

void ShotKernel::set_threads(int64_t threads) {
	_width = threads <= 0 ? jobs::default_width() : (int)clampi(threads, 1, jobs::available() ? jobs::MAX_WIDTH : 1);
}

int64_t ShotKernel::get_threads() const {
	return _width;
}

void ShotKernel::free_names() {
	delete names;
	names = nullptr;
}

// Every constant above that the GDScript also holds, by its GDScript name (PI and TAU are
// GDScript's; HOMING_DRIFT, RAMP_ENEMY and TEAM_NONE come from other scripts, see `set_native`).
struct Constant {
	const char *name;
	double value;
};
const Constant CONSTANTS[] = {
	{ "PI", (double)PI_D },
	{ "TAU", (double)TAU_D },
	{ "MOTION_STRAIGHT", (double)MOTION_STRAIGHT },
	{ "MOTION_STILL", (double)MOTION_STILL },
	{ "MOTION_ORBIT", (double)MOTION_ORBIT },
	{ "F_GHOST", (double)F_GHOST },
	{ "S_IDLE", (double)S_IDLE },
	{ "S_MOVING", (double)S_MOVING },
	{ "S_DONE", (double)S_DONE },
	{ "S_STUCK", (double)S_STUCK },
	{ "S_EXPIRE", (double)S_EXPIRE },
	{ "S_FROZEN", (double)S_FROZEN },
	{ "GRID_CELL", (double)GRID_CELL },
	{ "WALL_CELL", (double)WALL_CELL },
	{ "MAX_WALL_VISITS", (double)MAX_WALL_VISITS },
	{ "S_HELD", (double)S_HELD },
	{ "S_RETURNING", (double)S_RETURNING },
	{ "S_WAITING", (double)S_WAITING },
	{ "S_GONE", (double)S_GONE },
	{ "F_TURNED", (double)F_TURNED },
	{ "F_WAVE", (double)F_WAVE },
	{ "F_DEFERRED", (double)F_DEFERRED },
	{ "CASTER_BODY", (double)CASTER_BODY },
	{ "CASTER_POINT", (double)CASTER_POINT },
	{ "SPIRAL_PERIOD", (double)SPIRAL_PERIOD },
	{ "RETURN_BEND", (double)RETURN_BEND },
	{ "B_GROWTH", (double)B_GROWTH },
	{ "B_LINGER", (double)B_LINGER },
	{ "B_ORBIT", (double)B_ORBIT },
	{ "B_RETURN", (double)B_RETURN },
	{ "B_CURVE", (double)B_CURVE },
	{ "B_HOMING", (double)B_HOMING },
	{ "B_SPIRAL", (double)B_SPIRAL },
	{ "B_MOVE", (double)B_MOVE },
	{ "AFTER_HITS", (double)AFTER_HITS },
	{ "HOMING_PERIOD", (double)HOMING_PERIOD },
	{ "HOMING_DRIFT", (double)HOMING_DRIFT },
	{ "AFTER_HOMING_MASK", (double)AFTER_HOMING_MASK },
	{ "TAIL_JUMP", (double)TAIL_JUMP },
	{ "SPARK_BIRTH_STRIDE", (double)SPARK_BIRTH_STRIDE },
	{ "SPARK_X", (double)SPARK_X },
	{ "SPARK_Y", (double)SPARK_Y },
	{ "SPARK_BACK_X", (double)SPARK_BACK_X },
	{ "SPARK_BACK_Y", (double)SPARK_BACK_Y },
	{ "SPARK_KIND", (double)SPARK_KIND },
	{ "SPARK_RAMP", (double)SPARK_RAMP },
	{ "SPARK_LOOK", (double)SPARK_LOOK },
	{ "SPARK_CORE", (double)SPARK_CORE },
	{ "SPARK_TAG", (double)SPARK_TAG },
	{ "SPARK_TAG_BITS", (double)SPARK_TAG_BITS },
	{ "SPARK_TAIL", (double)SPARK_TAIL },
	{ "TAIL_KINDS", (double)TAIL_KINDS },
	{ "TAIL_SPACING", (double)TAIL_SPACING },
	{ "TAIL_PLAYER_SHARE", (double)TAIL_PLAYER_SHARE },
	{ "ORBIT_GROW", (double)ORBIT_GROW },
	{ "HEAD_LIVE", (double)HEAD_LIVE },
	{ "HEAD_ORBIT", (double)HEAD_ORBIT },
	{ "DRAW_STRIDE", (double)DRAW_STRIDE },
	{ "KIND_BOLT", (double)KIND_BOLT },
	{ "KIND_RUNE", (double)KIND_RUNE },
	{ "KIND_STEPS", (double)KIND_STEPS },
	{ "RUNE_TRACE", (double)RUNE_TRACE },
	{ "TRACE_FROM", (double)TRACE_FROM },
	{ "TRACE_SPAN", (double)TRACE_SPAN },
	{ "BATCH_BOLT", (double)BATCH_BOLT },
	{ "BATCH_STILL", (double)BATCH_STILL },
	{ "BATCH_ORBIT", (double)BATCH_ORBIT },
	{ "BATCH_ENEMY", (double)BATCH_ENEMY },
	{ "BATCH_ENEMY_STILL", (double)BATCH_ENEMY_STILL },
	{ "BATCH_BODY_FIRST", (double)BATCH_BODY_FIRST },
	{ "DRAW_ASKED", (double)DRAW_ASKED },
	{ "DRAW_SHOTS", (double)DRAW_SHOTS },
	{ "DRAW_ENEMY", (double)DRAW_ENEMY },
	{ "DRAW_BIRTHS", (double)DRAW_BIRTHS },
	{ "DRAW_TAIL", (double)DRAW_TAIL },
	{ "DRAW_OUT_FIRST", (double)DRAW_OUT_FIRST },
	{ "LOOK_GRID", (double)LOOK_GRID },
	{ "LOOK_CELL_PER_RADIUS", (double)LOOK_CELL_PER_RADIUS },
	{ "LOOK_ZOOM_MAX", (double)LOOK_ZOOM_MAX },
	{ "SPECK_RADIUS", (double)SPECK_RADIUS },
	{ "LOOK_ENEMY_RAMP", (double)LOOK_ENEMY_RAMP },
	{ "EMITTING_MASK", (double)EMITTING_MASK },
	{ "PARTICLES_PER_SHOT_MAX", (double)PARTICLES_PER_SHOT_MAX },
	{ "RAMP_ENEMY", (double)RAMP_ENEMY },
	{ "TEAM_NONE", (double)TEAM_NONE },
	{ "THREAT_SPAN_MAX", (double)THREAT_SPAN_MAX }
};

PackedStringArray ShotKernel::check(const Dictionary &constants) const {
	PackedStringArray wrong;
	for (const Constant &c : CONSTANTS) {
		if (!constants.has(c.name)) {
			wrong.push_back(String("no constant ") + c.name);
		} else if ((double)constants[c.name] != c.value) {
			wrong.push_back(String(c.name) + " is " + String(constants[c.name]) + ", the kernel's " + String::num(c.value));
		}
	}
	return wrong;
}

PackedStringArray ShotKernel::check_fields(Object *manager) const {
	PackedStringArray wrong;
	ERR_FAIL_NULL_V(manager, wrong);
#define SM_CHECK(id, gd, type)                                       \
	if (manager->get(names->id).get_type() != Variant::type) {       \
		wrong.push_back(String("member ") + gd + " missing or not " #type); \
	}
	MANAGER_FIELDS(SM_CHECK)
#undef SM_CHECK
	return wrong;
}

// `_pass_common`.
void ShotKernel::pass_common(Object *m, int64_t top, double delta) {
	const Names &k = *names;
	Arr<PackedByteArray> alive, state, motion;
	Arr<PackedFloat32Array> freeze, life;
	Arr<PackedVector2Array> pos, prev, vel;
	alive.load(m, k.alive);
	state.load(m, k.state);
	motion.load(m, k.motion);
	freeze.load(m, k.freeze);
	life.load(m, k.life);
	pos.load(m, k.pos);
	prev.load(m, k.prev);
	vel.load(m, k.vel);
	ERR_FAIL_COND(top > alive.n || top > pos.n);
	// Every shot alone: spread over the threads.
	jobs::for_spans(top, SLOT_SPAN, _width, [&](int64_t, int64_t begin, int64_t end) {
		for (int64_t slot = begin; slot < end; slot++) {
			if (alive[slot] == 0) {
				continue;
			}
			if (freeze[slot] > 0.0f) {
				freeze[slot] = (float)((double)freeze[slot] - delta);
				prev[slot] = pos[slot];
				state[slot] = S_FROZEN;
				continue;
			}
			life[slot] = (float)((double)life[slot] - delta);
			const Vector2 at = pos[slot];
			prev[slot] = at;
			if (life[slot] <= 0.0f) {
				state[slot] = S_EXPIRE;
				continue;
			}
			state[slot] = S_MOVING;
			if (motion[slot] == MOTION_STRAIGHT) {
				pos[slot] = at + vmul(vel[slot], delta);
			}
		}
	});
}

// `_pass_hits` from its `n`-th shot on (slot n + resume, wrapped at `top`): every shot that needs
// no GDScript is done here (its state set to S_DONE, its hits looked for, what it left forgotten,
// the hit work charged). The first that needs GDScript stops the walk and is returned as
// n x 2 + YIELD_WHOLE (GDScript does all of that shot: its end, the bounds, a wall) or
// n x 2 + YIELD_FOUND (it found `_cand_found` targets in `_cand_*`: GDScript hits them). -1 when
// every shot is done, HANDED_ERROR - n on an error (the manager does the rest). The manager calls
// again from n + 1. Not for a pass with solid shots.
int64_t ShotKernel::hits(Object *m, int64_t n, int64_t top, int64_t resume, const Rect2 &limit, double delta) {
	HitPass h;
	h.load(m);
	ERR_FAIL_COND_V(top > h.state.n || top > h.pos.n, HANDED_ERROR - n);
	const int64_t starved_before = h.starved_at;
	const bool any_targets = h.target_id.n > 0;
	for (; n < top; n++) {
		int64_t slot = n + resume;
		if (slot >= top) {
			slot -= top;
		}
		int64_t st = h.state[slot];
		if (st == S_IDLE) {
			continue;
		}
		if (st == S_WAITING) {
			// A homing shot that waited for its turn to search: caught up here when homing is all it
			// waited for (else GDScript runs its passes), then on as any shot.
			if (!h.homing_loaded) {
				h.load_homing(m);
			}
			if (h.wait_from[slot] != B_HOMING || (h.kinds[slot] & AFTER_HOMING_MASK) != 0) {
				h.save(m, 0, starved_before);
				return n * 2 + YIELD_WHOLE;
			}
			if (!h.targets_loaded) {
				h.load_targets(m);
				ERR_FAIL_COND_V(h.cand_target.n < h.target_id.n || h.target_mark.n < h.target_id.n, HANDED_ERROR - n);
			}
			h.catch_up_homing(slot, delta);
			// As `_hit_slot` after `_catch_up`: the shot is done whatever comes next (a hand-back
			// below finds it so and goes on from the bounds).
			st = h.state[slot];
			h.state[slot] = S_DONE;
		}
		if (st >= S_STUCK || !limit.has_point(h.pos[slot])) {
			h.save(m, 0, starved_before);
			return n * 2 + YIELD_WHOLE;
		}
		if (h.has_walls && h.motion[slot] != MOTION_ORBIT && (h.flags[slot] & F_GHOST) == 0 &&
				h.wall_hit(h.prev[slot], h.pos[slot]) >= 0.0) {
			h.save(m, 0, starved_before);
			return n * 2 + YIELD_WHOLE;
		}
		h.state[slot] = S_DONE;
		if (h.layers[slot] != 0 && any_targets) {
			if (h.work_left <= 0) {
				h.defer(m, slot);
				if (h.starved_at < 0) {
					h.starved_at = slot;
				}
				continue;
			}
			if (!h.targets_loaded) {
				h.load_targets(m);
				ERR_FAIL_COND_V(h.cand_target.n < h.target_id.n || h.target_mark.n < h.target_id.n, HANDED_ERROR - n);
			}
			const int64_t found = h.scan(slot);
			if (found > 0) {
				h.save(m, found, starved_before);
				return n * 2 + YIELD_FOUND;
			}
			h.forget_left(slot);
		}
	}
	h.save(m, 0, starved_before);
	return -1;
}

// --- Tails and drawing -------------------------------------------------------------------------

namespace {

// `_drawn_at`.
inline Vector2 drawn_at(int64_t motion, double sim_time, float born, const Vector2 &centre, const Vector2 &at) {
	if (motion != MOTION_ORBIT) {
		return at;
	}
	const double out = (sim_time - (double)born) / ORBIT_GROW;
	if (out >= 1.0 || !centre.is_finite()) {
		return at;
	}
	return centre.lerp(at, (real_t)MAX(out, 0.0));
}

inline bool is_hat_ramp(int64_t ramp) { return ramp >= 0 && ramp < RAMP_ENEMY; }

// `look_zoom`, `look_core_zoom`, `look_size`, `particles_of`, `look_color` (static in the manager).
inline int64_t look_zoom(double radius) {
	return clampi((int64_t)std::round(radius * LOOK_CELL_PER_RADIUS), 1, LOOK_ZOOM_MAX);
}
inline int64_t look_core_zoom(double radius) { return radius < SPECK_RADIUS ? 0 : look_zoom(radius); }
inline double look_size(double radius) { return (double)(LOOK_GRID * look_zoom(radius)); }
inline int64_t particles_of(int64_t look) {
	if (look == 0) {
		return 0;
	}
	int64_t bits = look & EMITTING_MASK;
	int64_t kinds = 0;
	while (bits != 0) {
		bits &= bits - 1;
		kinds += 1;
	}
	if (kinds == 0) {
		return 0;
	}
	return MIN(4 + 2 * kinds, (int64_t)PARTICLES_PER_SHOT_MAX);
}
inline Color look_color(int64_t ramp, int64_t zoom, int64_t look) {
	const bool hat = is_hat_ramp(ramp);
	const int64_t bits = hat ? (look & ~LOOK_ENEMY_RAMP) : (look | LOOK_ENEMY_RAMP);
	const int64_t red = (hat ? ramp : 0) + clampi(zoom, 0, 63) * 4;
	return Color((float)((double)red / 255.0), (float)((double)(bits & 255) / 255.0),
			(float)((double)((bits >> 8) & 255) / 255.0), (float)((double)((bits >> 16) & 255) / 255.0));
}
// `trace_code`.
inline double trace_code(double age) {
	if (age >= RUNE_TRACE || age < 0.0) {
		return 0.0;
	}
	return TRACE_FROM + TRACE_SPAN * age / RUNE_TRACE;
}

// `_write_quad` for a square quad (length 0): every rune.
inline void write_quad(float *b, const Vector2 &dir, double diameter, const Vector2 &at, const Color &color,
		const Color &core, int64_t kind, double code) {
	const double along = diameter;
	b[0] = (float)((double)dir.x * along);
	b[1] = (float)((double)dir.y * diameter);
	b[2] = 0.0f;
	b[3] = at.x;
	b[4] = (float)((double)dir.y * along);
	b[5] = (float)(-(double)dir.x * diameter);
	b[6] = 0.0f;
	b[7] = at.y;
	b[8] = color.r;
	b[9] = color.g;
	b[10] = color.b;
	b[11] = color.a;
	b[12] = core.r;
	b[13] = core.g;
	b[14] = core.b;
	b[15] = (float)(1.0 - ((double)kind + code) / KIND_STEPS);
}

// `body(n)` for every member n of a behaviour from `first` (`count` of them), spread over the
// threads: each member is a shot of its own, and a pass writes only its shot's arrays.
template <typename F>
void each_member(int64_t first, int64_t count, int width, F &&body) {
	jobs::for_spans(count, SLOT_SPAN, width, [&](int64_t, int64_t begin, int64_t end) {
		for (int64_t n = first + begin; n < first + end; n++) {
			body(n);
		}
	});
}

} // namespace

// `_pass_homing` (not catching up): turn every homing shot, and let each whose search is due wait
// for its turn in the hit pass (`_wait`), where the search sees what the hits before it changed.
void ShotKernel::homing_pass(Object *m, int64_t first, int64_t count, double delta) {
	const Names &k = *names;
	Arr<PackedInt32Array> members;
	Arr<PackedByteArray> state, wait_state, wait_from;
	Arr<PackedVector2Array> pos, prev;
	Steer steer;
	members.load(m, k.members);
	state.load(m, k.state);
	wait_state.load(m, k.wait_state);
	wait_from.load(m, k.wait_from);
	pos.load(m, k.pos);
	prev.load(m, k.prev);
	steer.load(m);
	const int64_t step_index = m->get(k.step_index);
	ERR_FAIL_COND(first + count > members.n);
	each_member(first, count, _width, [&](int64_t n) {
		const int64_t slot = members[n];
		const int64_t st = state[slot];
		if (st != S_MOVING && st != S_RETURNING) {
			return;
		}
		if (((slot + step_index) % HOMING_PERIOD) == 0) {
			wait_state[slot] = state[slot];
			wait_from[slot] = B_HOMING;
			state[slot] = S_WAITING;
			return;
		}
		if (st == S_RETURNING) {
			return;
		}
		steer.steer(slot, pos.p, prev.p, delta);
	});
}

// The behaviour passes that need nothing of GDScript (`_pass_growth`, `_pass_linger`, `_pass_orbit`,
// `_pass_return`, `_pass_curve`, `_pass_homing`, `_pass_spiral`), over the shots `_members[first ..
// first + count - 1]`, not catching up: a shot whose caster is another shot waits for its turn
// (`_wait`), as in GDScript, and GDScript catches it up. Returns false for another kind.
bool ShotKernel::run_pass(Object *m, int64_t kind, int64_t first, int64_t count, double delta) {
	if (kind == B_HOMING) {
		homing_pass(m, first, count, delta);
		return true;
	}
	if (kind != B_GROWTH && kind != B_LINGER && kind != B_ORBIT && kind != B_RETURN && kind != B_CURVE && kind != B_SPIRAL) {
		return false;
	}
	const Names &k = *names;
	Arr<PackedInt32Array> members, flags;
	Arr<PackedByteArray> state;
	Arr<PackedVector2Array> pos, prev, vel;
	members.load(m, k.members);
	state.load(m, k.state);
	pos.load(m, k.pos);
	prev.load(m, k.prev);
	vel.load(m, k.vel);
	ERR_FAIL_COND_V(first + count > members.n, true);
	// `_wait` (for the passes whose shot may circle or return to another shot). Its arrays are
	// read before the loop, which may run on several threads.
	Arr<PackedByteArray> wait_state, wait_from;
	if (kind == B_ORBIT || kind == B_RETURN) {
		wait_state.load(m, k.wait_state);
		wait_from.load(m, k.wait_from);
	}
	auto wait = [&](int64_t slot) {
		wait_state[slot] = state[slot];
		wait_from[slot] = (uint8_t)kind;
		state[slot] = S_WAITING;
	};
	if (kind == B_GROWTH) {
		Arr<PackedFloat32Array> radius, growth, radius0;
		radius.load(m, k.radius);
		growth.load(m, k.growth);
		radius0.load(m, k.radius0);
		const Rect2 bounds = m->get(k.bounds);
		const double room = MAX((double)bounds.size.x, (double)bounds.size.y);
		each_member(first, count, _width, [&](int64_t n) {
			const int64_t slot = members[n];
			if (state[slot] == S_MOVING) {
				radius[slot] = (float)MIN((double)radius[slot] * dmath::pow((double)growth[slot], delta), MAX(room, (double)radius0[slot]));
			}
		});
	} else if (kind == B_LINGER) {
		Arr<PackedFloat32Array> hold, life, span, linger;
		hold.load(m, k.hold);
		life.load(m, k.life);
		span.load(m, k.span);
		linger.load(m, k.linger);
		each_member(first, count, _width, [&](int64_t n) {
			const int64_t slot = members[n];
			if (state[slot] != S_MOVING) {
				return;
			}
			if (hold[slot] < 0.0f && (double)life[slot] <= (double)span[slot] * 0.5) {
				hold[slot] = linger[slot];
				life[slot] = (float)((double)life[slot] + (double)linger[slot]);
			}
			if (hold[slot] > 0.0f) {
				hold[slot] = (float)MAX((double)hold[slot] - delta, 0.0);
				pos[slot] = prev[slot];
				state[slot] = S_HELD;
			}
		});
	} else if (kind == B_ORBIT) {
		Arr<PackedInt32Array> caster_slot, actor;
		Arr<PackedVector2Array> caster_at, anchors, orbit_centre;
		Arr<PackedFloat32Array> orbit_angle, orbit_speed, orbit_radius, wave, wave_age;
		caster_slot.load(m, k.caster_slot);
		actor.load(m, k.actor);
		caster_at.load(m, k.caster_at);
		anchors.load(m, k.anchors);
		orbit_centre.load(m, k.orbit_centre);
		orbit_angle.load(m, k.orbit_angle);
		orbit_speed.load(m, k.orbit_speed);
		orbit_radius.load(m, k.orbit_radius);
		wave.load(m, k.wave);
		wave_age.load(m, k.wave_age);
		each_member(first, count, _width, [&](int64_t n) {
			const int64_t slot = members[n];
			const int64_t st = state[slot];
			if (st != S_MOVING && st != S_HELD) {
				return;
			}
			const int64_t caster = caster_slot[slot];
			Vector2 centre = caster_at[slot];
			if (caster == CASTER_BODY) {
				centre = actor[slot] >= 0 ? anchors[actor[slot]] : Vector2(INFINITY, INFINITY);
			} else if (caster >= 0) {
				wait(slot);
				return;
			}
			if (!centre.is_finite()) {
				state[slot] = S_GONE;
				return;
			}
			if (st == S_MOVING) {
				orbit_angle[slot] = (float)UtilityFunctions::wrapf((double)orbit_angle[slot] + (double)orbit_speed[slot] * delta, -PI_D, PI_D);
				wave_age[slot] = (float)((double)wave_age[slot] + delta);
			}
			const Vector2 away = dmath::from_angle((double)orbit_angle[slot]);
			const double reach = (double)orbit_radius[slot] + (double)wave[slot] * dmath::sin(TAU_D * (double)wave_age[slot] / SPIRAL_PERIOD);
			pos[slot] = centre + vmul(away, reach);
			vel[slot] = vmul(Vector2(-away.y, away.x), (double)orbit_radius[slot] * (double)orbit_speed[slot]);
			orbit_centre[slot] = centre;
		});
	} else if (kind == B_CURVE) {
		Arr<PackedFloat32Array> life, span, curve_from, curve_to, curve_ease, curve_speed;
		life.load(m, k.life);
		span.load(m, k.span);
		curve_from.load(m, k.curve_from);
		curve_to.load(m, k.curve_to);
		curve_ease.load(m, k.curve_ease);
		curve_speed.load(m, k.curve_speed);
		each_member(first, count, _width, [&](int64_t n) {
			const int64_t slot = members[n];
			if (state[slot] != S_MOVING) {
				return;
			}
			// At the middle of the step, as `_pass_curve`.
			const double left = clampf(((double)life[slot] + delta * 0.5) / (double)span[slot], 0.0, 1.0);
			const double from = (double)curve_from[slot];
			const double factor = from + ((double)curve_to[slot] - from) * (1.0 - dmath::pow(left, (double)curve_ease[slot]));
			vel[slot] = vmul(vel[slot].normalized(), (double)curve_speed[slot] * factor);
			pos[slot] = prev[slot] + vmul(vel[slot], delta);
		});
	} else if (kind == B_SPIRAL) {
		Arr<PackedVector2Array> base;
		Arr<PackedFloat32Array> wave, wave_age;
		base.load(m, k.base);
		wave.load(m, k.wave);
		wave_age.load(m, k.wave_age);
		each_member(first, count, _width, [&](int64_t n) {
			const int64_t slot = members[n];
			const int64_t st = state[slot];
			if (st != S_MOVING && st != S_RETURNING) {
				return;
			}
			const Vector2 velocity = vel[slot];
			base[slot] = base[slot] + vmul(velocity, delta);
			wave_age[slot] = (float)((double)wave_age[slot] + delta);
			const Vector2 side = Vector2(-velocity.y, velocity.x).normalized();
			pos[slot] = base[slot] + vmul(side, (double)wave[slot] * dmath::sin(TAU_D * (double)wave_age[slot] / SPIRAL_PERIOD));
		});
	} else if (kind == B_RETURN) {
		Arr<PackedInt32Array> caster_slot, actor, mem_head, mem_next;
		Arr<PackedVector2Array> caster_at, anchors, base, home_at;
		Arr<PackedFloat32Array> life, span, speed, radius, turn;
		caster_slot.load(m, k.caster_slot);
		actor.load(m, k.actor);
		mem_head.load(m, k.mem_head);
		mem_next.load(m, k.mem_next);
		caster_at.load(m, k.caster_at);
		anchors.load(m, k.anchors);
		base.load(m, k.base);
		home_at.load(m, k.home_at);
		life.load(m, k.life);
		span.load(m, k.span);
		speed.load(m, k.speed);
		radius.load(m, k.radius);
		turn.load(m, k.turn);
		flags.load(m, k.flags);
		int64_t mem_free = m->get(k.mem_free);
		const int64_t mem_free_before = mem_free;
		for (int64_t n = first; n < first + count; n++) {
			const int64_t slot = members[n];
			if (state[slot] != S_MOVING || (double)life[slot] > (double)span[slot] * 0.5) {
				continue;
			}
			if (caster_slot[slot] >= 0) {
				wait(slot);
				continue;
			}
			life[slot] = (float)((double)life[slot] + delta);
			const int64_t flg = flags[slot];
			const bool turned = (flg & F_TURNED) == 0;
			if (turned) {
				flags[slot] |= F_TURNED;
				speed[slot] = vel[slot].length();
				// `_forget_all`.
				int64_t at = mem_head[slot];
				while (at >= 0) {
					const int64_t next = mem_next[at];
					mem_next[at] = (int32_t)mem_free;
					mem_free = at;
					at = next;
				}
				mem_head[slot] = -1;
			}
			// `_caster_position` of a wizard or a point.
			const Vector2 anchor = caster_slot[slot] == CASTER_BODY
					? (actor[slot] >= 0 ? anchors[actor[slot]] : Vector2(INFINITY, INFINITY))
					: caster_at[slot];
			if (!anchor.is_finite()) {
				pos[slot] = prev[slot];
				state[slot] = S_GONE;
				continue;
			}
			const Vector2 here = (flg & F_WAVE) != 0 ? base[slot] : prev[slot];
			const Vector2 way = anchor - here;
			if ((double)way.length() <= (double)speed[slot] * delta + (double)radius[slot]) {
				pos[slot] = anchor;
				state[slot] = S_EXPIRE;
				continue;
			}
			Vector2 heading = way.normalized();
			if (turn[slot] > 0.0f) {
				const double bend = turned ? 0.0 : clampf(dmath::angle_to(heading, vel[slot]), -RETURN_BEND, RETURN_BEND);
				const Vector2 goal = home_at[slot];
				double want = 0.0;
				if (goal.is_finite() && !goal.is_equal_approx(here)) {
					want = clampf(dmath::angle_to(heading, goal - here), -RETURN_BEND, RETURN_BEND);
				}
				heading = dmath::rotated(heading, UtilityFunctions::move_toward(bend, want, (double)turn[slot] * (double)speed[slot] * delta));
			}
			vel[slot] = vmul(heading, (double)speed[slot]);
			pos[slot] = prev[slot] + vmul(vel[slot], delta);
			state[slot] = S_RETURNING;
		}
		if (mem_free != mem_free_before) {
			m->set(k.mem_free, mem_free);
		}
	}
	return true;
}

// `_count_batches` (no solid shots): `_batch_counts` and every live shot's drawn data.
void ShotKernel::count_draw(Object *m) {
	const Names &k = *names;
	Arr<PackedByteArray> alive, motion, drawn_batch, body;
	Arr<PackedInt64Array> seq, drawn_seq;
	Arr<PackedFloat32Array> radius, drawn_radius, drawn_size;
	Arr<PackedInt32Array> look, drawn_look, drawn_particles, ramp, batch_counts;
	Arr<PackedColorArray> drawn_color;
	alive.load(m, k.alive);
	motion.load(m, k.motion);
	body.load(m, k.body);
	drawn_batch.load(m, k.drawn_batch);
	seq.load(m, k.seq);
	drawn_seq.load(m, k.drawn_seq);
	radius.load(m, k.radius);
	drawn_radius.load(m, k.drawn_radius);
	drawn_size.load(m, k.drawn_size);
	look.load(m, k.look);
	drawn_look.load(m, k.drawn_look);
	drawn_particles.load(m, k.drawn_particles);
	ramp.load(m, k.ramp);
	batch_counts.load(m, k.batch_counts);
	drawn_color.load(m, k.drawn_color);
	const int64_t high = m->get(k.high);
	const int64_t batches = m->get(k.batch_total);
	ERR_FAIL_COND(high > alive.n || high > drawn_seq.n || high > body.n || batches < BATCH_BODY_FIRST || batch_counts.n < batches);
	// Each span counts its own batches (`_scratch->draw_counts`), added up after in span order.
	const int64_t spans = jobs::spans_of(high, SLOT_SPAN);
	_scratch->draw_counts.assign(spans * batches, 0);
	jobs::for_spans(high, SLOT_SPAN, _width, [&](int64_t span, int64_t begin, int64_t end) {
		int64_t *counts = _scratch->draw_counts.data() + span * batches;
		for (int64_t slot = begin; slot < end; slot++) {
			if (alive[slot] == 0) {
				continue;
			}
			if (drawn_seq[slot] != seq[slot] || drawn_radius[slot] != radius[slot] || drawn_look[slot] != look[slot]) {
				// `_remember_drawn`.
				const double r = radius[slot];
				const int64_t rmp = ramp[slot];
				const int64_t mot = motion[slot];
				drawn_seq[slot] = seq[slot];
				drawn_radius[slot] = radius[slot];
				drawn_look[slot] = look[slot];
				// `_batch_of`: a still shot of a card body draws in its body's pair (`body_batch`).
				int64_t batch = BATCH_BOLT;
				if (mot == MOTION_STILL && body[slot] > 0) {
					batch = BATCH_BODY_FIRST + 2 * ((int64_t)body[slot] - 1) + (is_hat_ramp(rmp) ? 0 : 1);
				} else if (!is_hat_ramp(rmp)) {
					batch = mot == MOTION_STILL ? BATCH_ENEMY_STILL : BATCH_ENEMY;
				} else if (mot == MOTION_STILL) {
					batch = BATCH_STILL;
				} else if (mot == MOTION_ORBIT) {
					batch = BATCH_ORBIT;
				}
				drawn_batch[slot] = (uint8_t)batch;
				drawn_color[slot] = look_color(rmp, look_core_zoom(r), look[slot]);
				drawn_size[slot] = (float)look_size(r);
				drawn_particles[slot] = (int32_t)particles_of(look[slot]);
			}
			counts[drawn_batch[slot]] += 1;
		}
	});
	for (int64_t b = 0; b < batches; b++) {
		int64_t count = 0;
		for (int64_t span = 0; span < spans; span++) {
			count += _scratch->draw_counts[span * batches + b];
		}
		batch_counts[b] = (int32_t)count;
	}
}

// `update_draw`'s writing (no solid shots): every live shot into the batches' buffers, which the
// kernel holds (`buffer`), sized to the manager's rooms; `_draw_out` gets the instances written per
// batch (BATCH_*), the particles asked for, the shots, the tail births laid and the tail asked.
namespace {

// The manager's `tail_hash`: a number from 0 up to 1 for the pair (a, b), every product below 2^63
// there, so the two agree.
inline double tail_hash(int64_t a, int64_t b) {
	uint64_t h = (((uint64_t)a & 0xFFFFFFFFull) * 374761393ull + ((uint64_t)b & 0xFFFFFFFFull) * 668265263ull) & 0xFFFFFFFFull;
	h = ((h ^ (h >> 16)) * 0x45D9F3Bull) & 0xFFFFFFFFull;
	h = ((h ^ (h >> 16)) * 0x45D9F3Bull) & 0xFFFFFFFFull;
	h = h ^ (h >> 16);
	return (double)(h & 0xFFFFFFull) / 16777216.0;
}

// The manager's `tail_code`: the shot's tail kind, SPARK_TAIL + 0 to TAIL_KINDS - 1, from its
// sequence alone.
inline int64_t tail_code(int64_t seq) {
	const int64_t v = (int64_t)std::floor(tail_hash(seq, -1) * (double)TAIL_KINDS);
	return SPARK_TAIL + (v < TAIL_KINDS - 1 ? v : TAIL_KINDS - 1);
}

} // namespace

void ShotKernel::draw_shots(Object *m, double fraction) {
	const Names &k = *names;
	Arr<PackedByteArray> alive, motion, drawn_batch, body;
	Arr<PackedVector2Array> prev, pos, vel, orbit_centre;
	Arr<PackedFloat32Array> drawn_size, born;
	Arr<PackedInt32Array> drawn_particles, draw_out, rooms;
	Arr<PackedColorArray> drawn_color, core;
	alive.load(m, k.alive);
	motion.load(m, k.motion);
	drawn_batch.load(m, k.drawn_batch);
	prev.load(m, k.prev);
	pos.load(m, k.pos);
	vel.load(m, k.vel);
	orbit_centre.load(m, k.orbit_centre);
	drawn_size.load(m, k.drawn_size);
	born.load(m, k.born);
	body.load(m, k.body);
	drawn_particles.load(m, k.drawn_particles);
	draw_out.load(m, k.draw_out);
	rooms.load(m, k.rooms);
	drawn_color.load(m, k.drawn_color);
	core.load(m, k.core);
	const int64_t high = m->get(k.high);
	const double sim_time = m->get(k.sim_time);
	const int64_t batches = m->get(k.batch_total);
	ERR_FAIL_COND(high > alive.n || high > body.n || batches < BATCH_BODY_FIRST || draw_out.n < DRAW_OUT_FIRST + batches || rooms.n < batches);
	// The groups (the manager's GROUPS, `_plan_groups`): each drawn slot is placed with its group's
	// in `_by_group`, and its particles and tail asked for are added to its group's.
	Arr<PackedInt32Array> group, group_end, by_group;
	Arr<PackedFloat32Array> group_tail, group_ask, group_spacing;
	group.load(m, k.group);
	group_end.load(m, k.group_end);
	by_group.load(m, k.by_group);
	group_tail.load(m, k.group_tail);
	group_ask.load(m, k.group_ask);
	group_spacing.load(m, k.group_spacing);
	ERR_FAIL_COND(high > group.n || high > by_group.n || group_end.n != group_ask.n || group_end.n != group_tail.n || group_end.n != group_spacing.n);
	// Tails as motes (`_lay_tail`).
	const bool tails_on = m->get(k.tail_births_on);
	const int64_t tail_cap = m->get(k.tail_births_cap);
	const int64_t thin_most = m->get(k.tail_thin_most);
	Arr<PackedVector2Array> tail_from;
	Arr<PackedFloat32Array> tail_carry, births;
	Arr<PackedInt32Array> tail_n, ramp, look;
	Arr<PackedInt64Array> seq, tag;
	if (tails_on) {
		tail_from.load(m, k.tail_from);
		tail_carry.load(m, k.tail_carry);
		births.load(m, k.spark_births);
		tail_n.load(m, k.tail_n);
		ramp.load(m, k.ramp);
		look.load(m, k.look);
		seq.load(m, k.seq);
		tag.load(m, k.tag);
		ERR_FAIL_COND(high > tail_from.n || high > tail_carry.n || high > tail_n.n || high > tag.n || high > seq.n || births.n < tail_cap * SPARK_BIRTH_STRIDE);
	}
	int64_t tail_count = 0;
	int64_t thin_count = 0;
	double tail_wanted = 0.0;
	// A tail in two halves (`_lay_tail`): `plan_tail` reads only, so it runs with the heads on any
	// thread: the shot's carry run on to the end of its path as if no cap stopped it. `lay_tail`
	// runs in slot order: it adds up what the tail asked for (floats, in the GDScript's order), lays
	// the births the caps leave room for and keeps where the carry ended (at the path's end where a
	// cap stopped it).
	auto plan_tail = [&](int64_t slot, const Vector2 &at, TailPlan &plan) {
		plan.at = at;
		plan.d = (at - tail_from[slot]).length();
		plan.in_reach = plan.d > 0.0 && plan.d <= TAIL_JUMP;
		plan.births = 0;
		if (!plan.in_reach) {
			return;
		}
		const double spacing = (double)group_spacing[group[slot]];
		const int64_t sq = seq[slot];
		double carry = tail_carry[slot];
		int64_t n = tail_n[slot];
		while (carry < plan.d) {
			carry += spacing * (0.5 + tail_hash(sq, n * 2 + 1));
			n += 1;
			plan.births += 1;
		}
	};
	auto lay_tail = [&](int64_t slot, const TailPlan &plan) {
		const Vector2 from = tail_from[slot];
		const Vector2 at = plan.at;
		tail_from[slot] = at;
		if (!plan.in_reach) {
			return;
		}
		const Vector2 way = at - from;
		const double d = plan.d;
		tail_wanted += d / TAIL_SPACING;
		const int64_t g = group[slot];
		group_tail[g] = (float)((double)group_tail[g] + d / TAIL_SPACING);
		const double spacing = (double)group_spacing[g];
		const bool thinned = spacing > TAIL_SPACING;
		int64_t room_left = tail_cap - tail_count;
		if (thinned) {
			room_left = MIN(room_left, thin_most - thin_count);
		}
		const int64_t laid = MAX(MIN(plan.births, room_left), (int64_t)0);
		double carry = tail_carry[slot];
		int64_t n = tail_n[slot];
		const int64_t sq = seq[slot];
		const Color cr = core[slot];
		const bool mixed = !((double)cr.r > 0.99 && (double)cr.g > 0.99 && (double)cr.b > 0.99);
		const Vector2 back = way / (real_t)(-d);
		const int64_t tg = tag[slot];
		const double code = (double)tail_code(sq);
		for (int64_t i = 0; i < laid; i++) {
			Color colour = cr;
			if (mixed && tail_hash(sq, n * 2) < TAIL_PLAYER_SHARE) {
				colour = Color(1, 1, 1, 1);
			}
			// `_add_birth`.
			const Vector2 p = from.lerp(at, (real_t)(carry / d));
			float *b = births.p + tail_count * SPARK_BIRTH_STRIDE;
			b[SPARK_X] = p.x;
			b[SPARK_Y] = p.y;
			b[SPARK_BACK_X] = back.x;
			b[SPARK_BACK_Y] = back.y;
			b[SPARK_KIND] = (float)code;
			b[SPARK_RAMP] = (float)(double)ramp[slot];
			b[SPARK_LOOK] = (float)(double)look[slot];
			b[SPARK_CORE] = colour.r;
			b[SPARK_CORE + 1] = colour.g;
			b[SPARK_CORE + 2] = colour.b;
			b[SPARK_TAG] = (float)(double)(tg & ((1ll << SPARK_TAG_BITS) - 1));
			b[SPARK_TAG + 1] = (float)(double)(tg >> SPARK_TAG_BITS);
			tail_count += 1;
			thin_count += thinned ? 1 : 0;
			carry += spacing * (0.5 + tail_hash(sq, n * 2 + 1));
			n += 1;
		}
		// A cap stopped it: the rest of its path lays nothing.
		if (laid < plan.births) {
			carry = d;
		}
		tail_carry[slot] = (float)(carry - d);
		tail_n[slot] = (int32_t)n;
	};
	if ((int64_t)_buffers.size() < batches) {
		_buffers.resize(batches);
	}
	std::vector<float *> &out_buffer = _scratch->out_buffer;
	std::vector<int64_t> &room = _scratch->room;
	std::vector<int64_t> &used = _scratch->used;
	out_buffer.resize(batches);
	room.resize(batches);
	used.assign(batches, 0);
	for (int64_t b = 0; b < batches; b++) {
		if (_buffers[b].size() != rooms[b] * DRAW_STRIDE) {
			_buffers[b].resize(rooms[b] * DRAW_STRIDE);
		}
		// `ptrw`: a copy only if the renderer still holds last frame's buffer.
		out_buffer[b] = _buffers[b].ptrw();
		room[b] = rooms[b];
	}
	// `_write_head` into the row at `buf`: no path (-1), and the way it flies, `way`.
	auto write_head = [](float *buf, const Vector2 &at, int64_t flags, const Color &color, const Color &cr, const Vector2 &way) {
		buf[0] = -1.0f;
		buf[1] = (float)way.x;
		buf[2] = 0.0f;
		buf[3] = at.x;
		buf[4] = (float)way.y;
		buf[5] = (float)flags;
		buf[6] = 0.0f;
		buf[7] = at.y;
		buf[8] = color.r;
		buf[9] = color.g;
		buf[10] = color.b;
		buf[11] = color.a;
		buf[12] = cr.r;
		buf[13] = cr.g;
		buf[14] = cr.b;
		buf[15] = (float)(1.0 - (double)KIND_BOLT / KIND_STEPS);
	};
	// A shot that lays a tail: a head, not a stone, and not a rune.
	auto is_tail = [](int64_t mot, int64_t batch) {
		return mot != MOTION_STILL;
	};
	std::vector<TailPlan> &tails = _scratch->tails;
	if (tails_on && (int64_t)tails.size() < high) {
		tails.resize(high);
	}
	// Where a live shot is drawn, `prev` to `pos` by the fraction (`_drawn_at` for an orbit).
	auto drawn_point = [&](int64_t slot, int64_t mot) {
		const Vector2 at = prev[slot].lerp(pos[slot], (real_t)fraction);
		return mot == MOTION_ORBIT ? drawn_at(mot, sim_time, born[slot], orbit_centre[slot], at) : at;
	};
	// The heads and stones, spread over the threads: each span counts its shots per batch first, so
	// it knows where its rows start (the shots before it, in slot order); rows past a batch's room
	// are not written, as in the GDScript.
	const int64_t spans = jobs::spans_of(high, SLOT_SPAN);
	_scratch->draw_counts.assign(spans * batches, 0);
	jobs::for_spans(high, SLOT_SPAN, _width, [&](int64_t span, int64_t begin, int64_t end) {
		int64_t *counts = _scratch->draw_counts.data() + span * batches;
		for (int64_t slot = begin; slot < end; slot++) {
			if (alive[slot] != 0) {
				counts[drawn_batch[slot]] += 1;
			}
		}
	});
	for (int64_t b = 0; b < batches; b++) {
		int64_t before = 0;
		for (int64_t span = 0; span < spans; span++) {
			const int64_t count = _scratch->draw_counts[span * batches + b];
			_scratch->draw_counts[span * batches + b] = before;
			before += count;
		}
		used[b] = MIN(before, room[b]);
	}
	jobs::for_spans(high, SLOT_SPAN, _width, [&](int64_t span, int64_t begin, int64_t end) {
		int64_t *row = _scratch->draw_counts.data() + span * batches;
		for (int64_t slot = begin; slot < end; slot++) {
			if (alive[slot] == 0) {
				continue;
			}
			const int64_t mot = motion[slot];
			const Vector2 at = drawn_point(slot, mot);
			const int64_t batch = drawn_batch[slot];
			if (tails_on && is_tail(mot, batch)) {
				plan_tail(slot, at, tails[slot]);
			}
			const int64_t index = row[batch];
			row[batch] += 1;
			if (index >= room[batch]) {
				continue;
			}
			float *b = out_buffer[batch] + index * DRAW_STRIDE;
			const double size = drawn_size[slot];
			const Color look_data = drawn_color[slot];
			if (mot == MOTION_STILL) {
				// `_write_stones` for a shot that is not solid: one quad, a rune's or a card body's
				// (its batch's shader draws it).
				Vector2 dir = Vector2(1, 0);
				if (vel[slot].length_squared() > 0.0f) {
					dir = vel[slot].normalized();
				}
				write_quad(b, dir, size, at, look_data, core[slot], KIND_RUNE, trace_code(sim_time - (double)born[slot]));
			} else {
				write_head(b, at, HEAD_LIVE | (mot == MOTION_ORBIT ? HEAD_ORBIT : 0), look_data, core[slot], pos[slot] - prev[slot]);
			}
		}
	});
	// In slot order, on this thread: what adds up (the particles asked for, each group's shots and
	// asks; floats, so in the GDScript's order) and the tails, whose births run until the cap.
	int64_t asked = 0;
	for (int64_t slot = 0; slot < high; slot++) {
		if (alive[slot] == 0) {
			continue;
		}
		asked += drawn_particles[slot];
		const int64_t g = group[slot];
		const int64_t particles = drawn_particles[slot];
		group_ask[g] = (float)((double)group_ask[g] + (double)(particles > 1 ? particles : 1));
		by_group[group_end[g]] = (int32_t)slot;
		group_end[g] += 1;
		if (tails_on && is_tail(motion[slot], drawn_batch[slot])) {
			lay_tail(slot, tails[slot]);
		}
	}
	int64_t shots = 0;
	for (int64_t b = 0; b < batches; b++) {
		shots += used[b];
	}
	// The batches on the enemy ramp's layer (`batch_on_enemy_layer`): its shots, runes and bodies.
	int64_t enemy_shots = used[BATCH_ENEMY] + used[BATCH_ENEMY_STILL];
	for (int64_t b = BATCH_BODY_FIRST + 1; b < batches; b += 2) {
		enemy_shots += used[b];
	}
	for (int64_t b = 0; b < batches; b++) {
		draw_out[DRAW_OUT_FIRST + b] = (int32_t)used[b];
	}
	draw_out[DRAW_ASKED] = (int32_t)asked;
	draw_out[DRAW_ASKED + 1] = 0;
	draw_out[DRAW_SHOTS] = (int32_t)shots;
	draw_out[DRAW_ENEMY] = (int32_t)enemy_shots;
	draw_out[DRAW_BIRTHS] = (int32_t)tail_count;
	draw_out[DRAW_TAIL] = (int32_t)(int64_t)tail_wanted;
}

PackedFloat32Array ShotKernel::buffer(int64_t batch) const {
	ERR_FAIL_INDEX_V(batch, (int64_t)_buffers.size(), PackedFloat32Array());
	return _buffers[batch];
}

// --- The threat grid ---------------------------------------------------------------------------

namespace {

struct Threat {
	Arr<PackedByteArray> alive, motion, state;
	Arr<PackedInt32Array> team, actor;
	Arr<PackedVector2Array> pos, vel;
	Arr<PackedFloat32Array> radius, life;
	int64_t slot = -1;
	Vector2 away;

	void load(Object *m) {
		const Names &k = *names;
		alive.load(m, k.alive);
		motion.load(m, k.motion);
		state.load(m, k.state);
		team.load(m, k.team);
		actor.load(m, k.actor);
		pos.load(m, k.pos);
		vel.load(m, k.vel);
		radius.load(m, k.radius);
		life.load(m, k.life);
	}

	// The shared part of `threat`'s loop and `_threat_try`: when the shot in `s` comes within
	// `rad` of `point` (-1 for never or not a threat), and whether it is still.
	double when(int64_t s, const Vector2 &point, double rad, int64_t tm, int64_t own, double horizon, bool &still, Vector2 &rel) {
		if (alive[s] == 0 || (team[s] == tm && tm != TEAM_NONE) || (actor[s] == own && own >= 0)) {
			return -2.0;
		}
		if (motion[s] == MOTION_ORBIT) {
			return -2.0;
		}
		const double reach = rad + (double)radius[s];
		rel = point - pos[s];
		const Vector2 v = vel[s];
		const int64_t st = state[s];
		still = motion[s] == MOTION_STILL || st == S_STUCK || st == S_FROZEN || st == S_HELD || v.length_squared() < 1.0f;
		if ((double)rel.length_squared() <= reach * reach) {
			return 0.0;
		}
		if (still) {
			return -1.0;
		}
		const double along = (double)rel.dot(v) / (double)v.length_squared();
		if (along <= 0.0 || along > MIN(horizon, (double)life[s])) {
			return -2.0;
		}
		if ((double)(rel - vmul(v, along)).length_squared() > reach * reach) {
			return -2.0;
		}
		return along;
	}

	Vector2 away_from(int64_t s, bool still, const Vector2 &rel) {
		if (still) {
			return rel != Vector2() ? rel.normalized() : Vector2(1, 0);
		}
		const Vector2 v = vel[s];
		const Vector2 side = rel - vmul(v, (double)rel.dot(v) / (double)v.length_squared());
		return (double)side.length_squared() > 0.01 ? side.normalized() : v.orthogonal().normalized();
	}

	// `_threat_try`.
	double attempt(int64_t s, const Vector2 &point, double rad, int64_t tm, int64_t own, double horizon, double best) {
		bool still = false;
		Vector2 rel;
		const double w = when(s, point, rad, tm, own, horizon, still, rel);
		if (w < 0.0 || w > best || (w == best && s > slot)) {
			return best;
		}
		slot = s;
		away = away_from(s, still, rel);
		return w;
	}
};

} // namespace

// `threat`'s loop over every shot (fewer shots than THREAT_GRID_FROM, or too few asks for the grid):
// sets `threat_slot` and `threat_away`, returns what `threat` returns.
double ShotKernel::threat_scan(Object *m, const Vector2 &point, double radius, int64_t team, int64_t own, double horizon) {
	Threat t;
	t.load(m);
	const int64_t high = m->get(names->high);
	ERR_FAIL_COND_V(high > t.alive.n, -1.0);
	double best = INFINITY;
	Vector2 best_away;
	for (int64_t s = 0; s < high; s++) {
		bool still = false;
		Vector2 rel;
		const double w = t.when(s, point, radius, team, own, horizon, still, rel);
		// Slots run upward, so of two as soon the first one stays.
		if (w < 0.0 || w >= best) {
			continue;
		}
		best = w;
		t.slot = s;
		best_away = t.away_from(s, still, rel);
	}
	m->set(names->threat_slot, t.slot);
	m->set(names->threat_away, best_away);
	return t.slot >= 0 ? best : -1.0;
}

// `_build_threat_grid`'s filling, once the manager set the grid's size and arrays: returns the
// entries used, or -1 when they would not fit `_threat_slot` (the manager then fills it itself).
int64_t ShotKernel::threat_fill(Object *m, double horizon) {
	const Names &k = *names;
	Threat t;
	t.load(m);
	Arr<PackedInt32Array> head, slots, next, over;
	head.load(m, k.threat_head);
	slots.load(m, k.threat_slot_list);
	next.load(m, k.threat_next);
	over.load(m, k.threat_over);
	const int64_t high = m->get(k.high);
	const double size = m->get(k.threat_cell);
	const double x_at = m->get(k.threat_x);
	const double y_at = m->get(k.threat_y);
	const int64_t w = m->get(k.threat_w);
	const int64_t h = m->get(k.threat_h);
	ERR_FAIL_COND_V(high > t.alive.n || head.n < w * h || over.n < high, -1);
	const int64_t w1 = w - 1;
	const int64_t h1 = h - 1;
	for (int64_t c = 0; c < w * h; c++) {
		head[c] = -1;
	}
	int64_t over_count = 0;
	int64_t used = 0;
	const int64_t room = slots.n;
	for (int64_t s = 0; s < high; s++) {
		if (t.alive[s] == 0 || t.motion[s] == MOTION_ORBIT) {
			continue;
		}
		const Vector2 at = t.pos[s];
		Vector2 to = at;
		const int64_t st = t.state[s];
		if (t.motion[s] != MOTION_STILL && st != S_STUCK && st != S_FROZEN && st != S_HELD) {
			to = at + vmul(t.vel[s], MIN(horizon, MAX((double)t.life[s], 0.0)));
		}
		const double r = t.radius[s];
		const int64_t x0 = clampi(floori((MIN((double)at.x, (double)to.x) - r - x_at) / size), 0, w1);
		const int64_t x1 = clampi(floori((MAX((double)at.x, (double)to.x) + r - x_at) / size), 0, w1);
		const int64_t y0 = clampi(floori((MIN((double)at.y, (double)to.y) - r - y_at) / size), 0, h1);
		const int64_t y1 = clampi(floori((MAX((double)at.y, (double)to.y) + r - y_at) / size), 0, h1);
		const int64_t span = (x1 - x0 + 1) * (y1 - y0 + 1);
		if (span > THREAT_SPAN_MAX) {
			over[over_count] = (int32_t)s;
			over_count += 1;
			continue;
		}
		if (used + span > room) {
			return -1;
		}
		for (int64_t y = y0; y <= y1; y++) {
			const int64_t row = y * w;
			for (int64_t x = x0; x <= x1; x++) {
				slots[used] = (int32_t)s;
				next[used] = head[row + x];
				head[row + x] = (int32_t)used;
				used += 1;
			}
		}
	}
	m->set(k.threat_over_count, over_count);
	return used;
}

// `threat`'s ask of the grid (once it is built): sets `threat_slot` and `threat_away`, returns what
// `threat` returns.
double ShotKernel::threat_query(Object *m, const Vector2 &point, double radius, int64_t team, int64_t own, double horizon) {
	const Names &k = *names;
	Threat t;
	t.load(m);
	Arr<PackedInt32Array> head, slots, next, over, seen;
	head.load(m, k.threat_head);
	slots.load(m, k.threat_slot_list);
	next.load(m, k.threat_next);
	over.load(m, k.threat_over);
	seen.load(m, k.threat_seen);
	const int64_t over_count = m->get(k.threat_over_count);
	const double size = m->get(k.threat_cell);
	const double x_at = m->get(k.threat_x);
	const double y_at = m->get(k.threat_y);
	const int64_t w = m->get(k.threat_w);
	const int64_t h = m->get(k.threat_h);
	const int64_t stamp = (int64_t)m->get(k.threat_stamp) + 1;
	ERR_FAIL_COND_V(head.n < w * h || over_count > over.n, -1.0);
	double best = INFINITY;
	for (int64_t n = 0; n < over_count; n++) {
		best = t.attempt(over[n], point, radius, team, own, horizon, best);
	}
	const int64_t x0 = clampi(floori(((double)point.x - radius - x_at) / size), 0, w - 1);
	const int64_t x1 = clampi(floori(((double)point.x + radius - x_at) / size), 0, w - 1);
	const int64_t y0 = clampi(floori(((double)point.y - radius - y_at) / size), 0, h - 1);
	const int64_t y1 = clampi(floori(((double)point.y + radius - y_at) / size), 0, h - 1);
	for (int64_t y = y0; y <= y1; y++) {
		for (int64_t x = x0; x <= x1; x++) {
			int64_t entry = head[y * w + x];
			while (entry >= 0) {
				const int64_t s = slots[entry];
				entry = next[entry];
				if (seen[s] == stamp) {
					continue;
				}
				seen[s] = (int32_t)stamp;
				best = t.attempt(s, point, radius, team, own, horizon, best);
			}
		}
	}
	m->set(k.threat_stamp, stamp);
	m->set(k.threat_slot, t.slot);
	m->set(k.threat_away, t.away);
	return t.slot >= 0 ? best : -1.0;
}

void ShotKernel::_bind_methods() {
	ClassDB::bind_method(D_METHOD("check", "constants"), &ShotKernel::check);
	ClassDB::bind_method(D_METHOD("set_threads", "threads"), &ShotKernel::set_threads);
	ClassDB::bind_method(D_METHOD("get_threads"), &ShotKernel::get_threads);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "threads"), "set_threads", "get_threads");
	ClassDB::bind_method(D_METHOD("check_fields", "manager"), &ShotKernel::check_fields);
	ClassDB::bind_method(D_METHOD("pass_common", "manager", "top", "delta"), &ShotKernel::pass_common);
	ClassDB::bind_method(D_METHOD("hits", "manager", "n", "top", "resume", "limit", "delta"), &ShotKernel::hits);
	ClassDB::bind_method(D_METHOD("run_pass", "manager", "kind", "first", "count", "delta"), &ShotKernel::run_pass);
	ClassDB::bind_method(D_METHOD("count_draw", "manager"), &ShotKernel::count_draw);
	ClassDB::bind_method(D_METHOD("draw_shots", "manager", "fraction"), &ShotKernel::draw_shots);
	ClassDB::bind_method(D_METHOD("buffer", "batch"), &ShotKernel::buffer);
	ClassDB::bind_method(D_METHOD("threat_scan", "manager", "point", "radius", "team", "own", "horizon"), &ShotKernel::threat_scan);
	ClassDB::bind_method(D_METHOD("threat_fill", "manager", "horizon"), &ShotKernel::threat_fill);
	ClassDB::bind_method(D_METHOD("threat_query", "manager", "point", "radius", "team", "own", "horizon"), &ShotKernel::threat_query);
}
