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
#include "packed.h"

#include <cmath>

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
constexpr int F_SELF = 1;
constexpr int F_SELF_LIVE = 2;
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
constexpr int CASTER_WIZARD = -1;
constexpr int CASTER_POINT = -2;
constexpr double SPIRAL_PERIOD = 0.5;
constexpr double RETURN_BEND = PI_D / 3.0;
// Homing (`_pass_homing`, `_home_pick`).
constexpr int B_GROWTH = 1;
constexpr int B_LINGER = 2;
constexpr int B_ORBIT = 3;
constexpr int B_RETURN = 4;
constexpr int B_HOMING = 5;
constexpr int B_SPIRAL = 6;
constexpr int B_MOVE = 7;
constexpr int AFTER_HITS = 8;
constexpr int HOMING_PERIOD = 4;
constexpr double HOMING_DRIFT = 24.0; // SpellLimits.HOMING_DRIFT
// The behaviours a waiting homing shot may also have for the native hit pass to catch it up itself:
// none of the passes after homing that run before the hits.
constexpr int64_t AFTER_HOMING_MASK = ((1 << AFTER_HITS) - 1) & ~((1 << (B_HOMING + 1)) - 1);
// Trails and drawing.
constexpr int TRAIL_SAMPLES = 32;
constexpr int TRAIL_STRIDE = TRAIL_SAMPLES * 4;
constexpr double TRAIL_JUMP = 96.0;
constexpr double ORBIT_GROW = 0.25;
constexpr int TRAIL_HEAD = 1;
constexpr int TRAIL_ORBIT = 2;
constexpr int TRAIL_COST = 4;
constexpr int ROW_CASTER = -3;
constexpr int DRAW_STRIDE = 16;
constexpr int KIND_BOLT = 1;
constexpr int KIND_RUNE = 2;
constexpr double KIND_STEPS = 16.0;
constexpr double RUNE_TRACE = 0.25;
constexpr double TRACE_FROM = 0.02;
constexpr double TRACE_SPAN = 0.42;
constexpr int BATCH_BOLT = 0;
constexpr int BATCH_RUNE = 1;
constexpr int BATCH_ORBIT = 2;
constexpr int BATCH_ENEMY = 3;
constexpr int BATCH_ENEMY_RUNE = 4;
constexpr int BATCHES = 5;
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

// What `hits` hands back to GDScript for the shot it stopped at (its n x 2 plus one of these).
constexpr int64_t YIELD_WHOLE = 0; // the whole shot: its end, the bounds, a wall
constexpr int64_t YIELD_FOUND = 1; // its hits (`_cand_*`, `_cand_found` of them), then what it left

struct Names {
	StringName alive, freeze, life, skip_left, pos, prev, state, motion, vel;
	StringName flags, layers, actor, radius, skip_id, mem_head;
	StringName target_pos, target_radius, target_owner, target_layer, target_id, target_next, target_mark, target_entry;
	StringName cell_head, cell_count, cell_box, cell_filled;
	StringName mem_id, mem_target, mem_seen, mem_next;
	StringName cand_target, cand_along, cand_point;
	StringName wall_cells, wall_w, wall_h, has_walls, bounds, grid_x, grid_y, grid_w, grid_h;
	StringName max_target_radius, grid_fill, mem_step, work_left, starved_at, mark_stamp, mem_free, cand_found;
	StringName high, sim_time, trail, born, orbit_centre, trail_kept, trail_last, trail_odo, trail_newest, trail_data;
	StringName seq, drawn_seq, drawn_radius, drawn_look, drawn_batch, drawn_color, drawn_size, drawn_particles;
	StringName look, ramp, core, batch_counts, loose, loose_count, trail_ramp, trail_caster, trail_flags, trail_holder;
	StringName trail_color, trail_core, anchors, draw_out, draw_room, rune_room, orbit_room, enemy_room, enemy_rune_room;
	StringName team, threat_slot, threat_away, threat_cell, threat_x, threat_y, threat_w, threat_h, threat_head;
	StringName threat_slot_list, threat_next, threat_over, threat_over_count, threat_seen, threat_stamp;
	StringName growth, radius0, hold, linger, span, caster_slot, caster_at, orbit_angle, orbit_speed, orbit_radius;
	StringName wave, wave_age, base, speed, mem_head_n;
	StringName members, step_index, home_at, home_range, home_target, turn, kinds, wait_state, wait_from, targets, target_team;
	Names() :
			alive("_alive"), freeze("_freeze"), life("_life"), skip_left("_skip_left"), pos("_pos"), prev("_prev"),
			state("_state"), motion("_motion"), vel("_vel"),
			flags("_flags"), layers("_layers"), actor("_actor"), radius("_radius"), skip_id("_skip_id"), mem_head("_mem_head"),
			target_pos("_target_pos"), target_radius("_target_radius"), target_owner("_target_owner"),
			target_layer("_target_layer"), target_id("_target_id"), target_next("_target_next"),
			target_mark("_target_mark"), target_entry("_target_entry"),
			cell_head("_cell_head"), cell_count("_cell_count"), cell_box("_cell_box"), cell_filled("_cell_filled"),
			mem_id("_mem_id"), mem_target("_mem_target"), mem_seen("_mem_seen"), mem_next("_mem_next"),
			cand_target("_cand_target"), cand_along("_cand_along"), cand_point("_cand_point"),
			wall_cells("_wall_cells"), wall_w("_wall_w"), wall_h("_wall_h"), has_walls("_has_walls"), bounds("_bounds"),
			grid_x("_grid_x"), grid_y("_grid_y"), grid_w("_grid_w"), grid_h("_grid_h"),
			max_target_radius("_max_target_radius"), grid_fill("_grid_fill"), mem_step("_mem_step"),
			work_left("_work_left"), starved_at("_starved_at"), mark_stamp("_mark_stamp"), mem_free("_mem_free"),
			cand_found("_cand_found"),
			high("_high"), sim_time("sim_time"), trail("_trail"), born("_born"), orbit_centre("_orbit_centre"),
			trail_kept("_trail_kept"), trail_last("_trail_last"), trail_odo("_trail_odo"), trail_newest("_trail_newest"),
			trail_data("_trail_data"),
			seq("_seq"), drawn_seq("_drawn_seq"), drawn_radius("_drawn_radius"), drawn_look("_drawn_look"),
			drawn_batch("_drawn_batch"), drawn_color("_drawn_color"), drawn_size("_drawn_size"),
			drawn_particles("_drawn_particles"),
			look("_look"), ramp("_ramp"), core("_core"), batch_counts("_batch_counts"), loose("_loose"),
			loose_count("_loose_count"), trail_ramp("_trail_ramp"), trail_caster("_trail_caster"),
			trail_flags("_trail_flags"), trail_holder("_trail_holder"),
			trail_color("_trail_color"), trail_core("_trail_core"), anchors("_anchors"), draw_out("_draw_out"),
			draw_room("_draw_room"), rune_room("_rune_room"), orbit_room("_orbit_room"), enemy_room("_enemy_room"),
			enemy_rune_room("_enemy_rune_room"),
			team("_team"), threat_slot("threat_slot"), threat_away("threat_away"), threat_cell("_threat_cell"),
			threat_x("_threat_x"), threat_y("_threat_y"), threat_w("_threat_w"), threat_h("_threat_h"),
			threat_head("_threat_head"), threat_slot_list("_threat_slot"), threat_next("_threat_next"),
			threat_over("_threat_over"), threat_over_count("_threat_over_count"), threat_seen("_threat_seen"),
			threat_stamp("_threat_stamp"),
			growth("_growth"), radius0("_radius0"), hold("_hold"), linger("_linger"), span("_span"),
			caster_slot("_caster_slot"), caster_at("_caster_at"), orbit_angle("_orbit_angle"),
			orbit_speed("_orbit_speed"), orbit_radius("_orbit_radius"), wave("_wave"), wave_age("_wave_age"),
			base("_base"), speed("_speed"), mem_head_n("_mem_head"),
			members("_members"), step_index("_step_index"), home_at("_home_at"), home_range("_home_range"),
			home_target("_home_target"), turn("_turn"), kinds("_kinds"), wait_state("_wait_state"),
			wait_from("_wait_from"), targets("_targets"), target_team("_target_team") {}
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
		vel[slot] = velocity.rotated((real_t)clampf((double)velocity.angle_to(want), -most, most));
		pos[slot] = prev[slot] + vmul(vel[slot], delta);
	}
};

// --- The hit pass ------------------------------------------------------------------------------

// Everything `_pass_hits` and `_hit_test` read, for one call.
struct HitPass {
	Arr<PackedByteArray> state, motion, wall_cells;
	Arr<PackedVector2Array> pos, prev, target_pos, cand_point;
	Arr<PackedInt32Array> flags, layers, actor, mem_head;
	Arr<PackedFloat32Array> radius, skip_left, target_radius, cand_along;
	Arr<PackedInt64Array> skip_id, target_id, mem_id;
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

	// `_home_pick` for the shot in `slot` (any way round, nothing avoided).
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
							if (keep != 0 && target_id[t] == keep) {
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
			home_target[slot] = t >= 0 ? target_id[t] : 0;
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
		wall_w = m->get(k.wall_w);
		wall_h = m->get(k.wall_h);
		work_left = m->get(k.work_left);
		starved_at = m->get(k.starved_at);
		has_walls = m->get(k.has_walls);
		bounds = m->get(k.bounds);
	}

	// What a hit test reads, the first time one runs in a call.
	void load_targets(Object *m) {
		const Names &k = *names;
		targets_loaded = true;
		target_pos.load(m, k.target_pos);
		cand_point.load(m, k.cand_point);
		actor.load(m, k.actor);
		mem_head.load(m, k.mem_head);
		radius.load(m, k.radius);
		skip_left.load(m, k.skip_left);
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
		const int64_t targets = target_id.n;
		int64_t before = -1;
		int64_t at = mem_head[slot];
		while (at >= 0) {
			const int64_t next = mem_next[at];
			int64_t t = mem_target[at];
			if (t < 0 || t >= targets || target_id[t] != mem_id[at]) {
				t = -1;
				for (int64_t i = 0; i < targets; i++) {
					if (target_id[i] == mem_id[at]) {
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
		const Vector2 from = prev[slot];
		const Vector2 to = pos[slot];
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
		int64_t shooter = 0;
		const int64_t flg = flags[slot];
		bool skip = false;
		int64_t stamp = 0;
		int64_t found = 0;
		bool inside = false;
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
					shooter = actor[slot];
					skip = skip_left[slot] > 0.0f;
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
					if (shooter >= 0 && target_owner[t] == shooter) {
						if ((flg & F_SELF) == 0) {
							t = target_next[t];
							continue;
						}
						if ((flg & F_SELF_LIVE) == 0) {
							if ((double)to.distance_squared_to(centre) <= reach * reach) {
								inside = true;
							}
							t = target_next[t];
							continue;
						}
					} else if ((target_layer[t] & lay) == 0) {
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
					if (skip && skip_id[slot] == target_id[t]) {
						t = target_next[t];
						continue;
					}
					found = keep_candidate(found, t, along, closest);
					t = target_next[t];
				}
			}
		}
		if ((flg & F_SELF) != 0 && (flg & F_SELF_LIVE) == 0 && !inside) {
			flags[slot] |= F_SELF_LIVE;
		}
		return found;
	}
};

} // namespace

ShotKernel::ShotKernel() {
	if (names == nullptr) {
		names = new Names();
	}
}

bool ShotKernel::check(const Dictionary &constants) const {
	Dictionary mine;
	mine["MOTION_STRAIGHT"] = MOTION_STRAIGHT;
	mine["MOTION_STILL"] = MOTION_STILL;
	mine["MOTION_ORBIT"] = MOTION_ORBIT;
	mine["F_SELF"] = F_SELF;
	mine["F_SELF_LIVE"] = F_SELF_LIVE;
	mine["F_GHOST"] = F_GHOST;
	mine["S_IDLE"] = S_IDLE;
	mine["S_MOVING"] = S_MOVING;
	mine["S_DONE"] = S_DONE;
	mine["S_STUCK"] = S_STUCK;
	mine["S_EXPIRE"] = S_EXPIRE;
	mine["S_FROZEN"] = S_FROZEN;
	mine["GRID_CELL"] = GRID_CELL;
	mine["WALL_CELL"] = WALL_CELL;
	mine["MAX_WALL_VISITS"] = MAX_WALL_VISITS;
	mine["S_HELD"] = S_HELD;
	mine["S_RETURNING"] = S_RETURNING;
	mine["S_WAITING"] = S_WAITING;
	mine["B_HOMING"] = B_HOMING;
	mine["B_SPIRAL"] = B_SPIRAL;
	mine["B_MOVE"] = B_MOVE;
	mine["AFTER_HITS"] = AFTER_HITS;
	mine["HOMING_PERIOD"] = HOMING_PERIOD;
	mine["HOMING_DRIFT"] = HOMING_DRIFT;
	mine["S_GONE"] = S_GONE;
	mine["F_TURNED"] = F_TURNED;
	mine["F_WAVE"] = F_WAVE;
	mine["CASTER_WIZARD"] = CASTER_WIZARD;
	mine["CASTER_POINT"] = CASTER_POINT;
	mine["SPIRAL_PERIOD"] = SPIRAL_PERIOD;
	mine["RETURN_BEND"] = RETURN_BEND;
	mine["B_GROWTH"] = B_GROWTH;
	mine["B_LINGER"] = B_LINGER;
	mine["B_ORBIT"] = B_ORBIT;
	mine["B_RETURN"] = B_RETURN;
	const Array keys = mine.keys();
	for (int64_t i = 0; i < keys.size(); i++) {
		const Variant key = keys[i];
		if (!constants.has(key) || constants[key] != mine[key]) {
			return false;
		}
	}
	return true;
}

// `_pass_common`.
void ShotKernel::pass_common(Object *m, int64_t top, double delta) {
	const Names &k = *names;
	Arr<PackedByteArray> alive, state, motion;
	Arr<PackedFloat32Array> freeze, life, skip_left;
	Arr<PackedVector2Array> pos, prev, vel;
	alive.load(m, k.alive);
	state.load(m, k.state);
	motion.load(m, k.motion);
	freeze.load(m, k.freeze);
	life.load(m, k.life);
	skip_left.load(m, k.skip_left);
	pos.load(m, k.pos);
	prev.load(m, k.prev);
	vel.load(m, k.vel);
	ERR_FAIL_COND(top > alive.n || top > pos.n);
	for (int64_t slot = 0; slot < top; slot++) {
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
		if (skip_left[slot] > 0.0f) {
			skip_left[slot] = (float)((double)skip_left[slot] - delta);
		}
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
}

// `_pass_hits` from its `n`-th shot on (slot n + resume, wrapped at `top`): every shot that needs
// no GDScript is done here (its state set to S_DONE, its hits looked for, what it left forgotten,
// the hit work charged). The first that needs GDScript stops the walk and is returned as
// n x 2 + YIELD_WHOLE (GDScript does all of that shot: its end, the bounds, a wall) or
// n x 2 + YIELD_FOUND (it found `_cand_found` targets in `_cand_*`: GDScript hits them). -1 when
// every shot is done. The manager calls again from n + 1. Not for a pass with solid shots.
int64_t ShotKernel::hits(Object *m, int64_t n, int64_t top, int64_t resume, const Rect2 &limit, double delta) {
	HitPass h;
	h.load(m);
	ERR_FAIL_COND_V(top > h.state.n || top > h.pos.n, -1);
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
				ERR_FAIL_COND_V(h.cand_target.n < h.target_id.n || h.target_mark.n < h.target_id.n, -1);
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
				if (h.starved_at < 0) {
					h.starved_at = slot;
				}
				continue;
			}
			if (!h.targets_loaded) {
				h.load_targets(m);
				ERR_FAIL_COND_V(h.cand_target.n < h.target_id.n || h.target_mark.n < h.target_id.n, -1);
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

// --- Trails and drawing ------------------------------------------------------------------------

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

} // namespace

// `_sample_trails`, its loop over the flying shots (the caller does the tick and the loose rows):
// returns true when a row took a point (the trails need sending).
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
	for (int64_t n = first; n < first + count; n++) {
		const int64_t slot = members[n];
		const int64_t st = state[slot];
		if (st != S_MOVING && st != S_RETURNING) {
			continue;
		}
		if (((slot + step_index) % HOMING_PERIOD) == 0) {
			wait_state[slot] = state[slot];
			wait_from[slot] = B_HOMING;
			state[slot] = S_WAITING;
			continue;
		}
		if (st == S_RETURNING) {
			continue;
		}
		steer.steer(slot, pos.p, prev.p, delta);
	}
}

// The behaviour passes that need nothing of GDScript (`_pass_growth`, `_pass_linger`, `_pass_orbit`,
// `_pass_return`, `_pass_homing`, `_pass_spiral`), over the shots `_members[first ..
// first + count - 1]`, not catching up: a shot whose caster is another shot waits for its turn
// (`_wait`), as in GDScript, and GDScript catches it up. Returns false for another kind.
bool ShotKernel::run_pass(Object *m, int64_t kind, int64_t first, int64_t count, double delta) {
	if (kind == B_HOMING) {
		homing_pass(m, first, count, delta);
		return true;
	}
	if (kind != B_GROWTH && kind != B_LINGER && kind != B_ORBIT && kind != B_RETURN && kind != B_SPIRAL) {
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
	// `_wait`.
	Arr<PackedByteArray> wait_state, wait_from;
	auto wait = [&](int64_t slot) {
		if (wait_state.p == nullptr) {
			wait_state.load(m, k.wait_state);
			wait_from.load(m, k.wait_from);
		}
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
		for (int64_t n = first; n < first + count; n++) {
			const int64_t slot = members[n];
			if (state[slot] == S_MOVING) {
				radius[slot] = (float)MIN((double)radius[slot] * std::pow((double)growth[slot], delta), MAX(room, (double)radius0[slot]));
			}
		}
	} else if (kind == B_LINGER) {
		Arr<PackedFloat32Array> hold, life, span, linger;
		hold.load(m, k.hold);
		life.load(m, k.life);
		span.load(m, k.span);
		linger.load(m, k.linger);
		for (int64_t n = first; n < first + count; n++) {
			const int64_t slot = members[n];
			if (state[slot] != S_MOVING) {
				continue;
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
		}
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
		for (int64_t n = first; n < first + count; n++) {
			const int64_t slot = members[n];
			const int64_t st = state[slot];
			if (st != S_MOVING && st != S_HELD) {
				continue;
			}
			const int64_t caster = caster_slot[slot];
			Vector2 centre = caster_at[slot];
			if (caster == CASTER_WIZARD) {
				centre = actor[slot] >= 0 ? anchors[actor[slot]] : Vector2(INFINITY, INFINITY);
			} else if (caster >= 0) {
				wait(slot);
				continue;
			}
			if (!centre.is_finite()) {
				state[slot] = S_GONE;
				continue;
			}
			if (st == S_MOVING) {
				orbit_angle[slot] = (float)UtilityFunctions::wrapf((double)orbit_angle[slot] + (double)orbit_speed[slot] * delta, -PI_D, PI_D);
				wave_age[slot] = (float)((double)wave_age[slot] + delta);
			}
			const Vector2 away = Vector2::from_angle(orbit_angle[slot]);
			const double reach = (double)orbit_radius[slot] + (double)wave[slot] * std::sin(TAU_D * (double)wave_age[slot] / SPIRAL_PERIOD);
			pos[slot] = centre + vmul(away, reach);
			vel[slot] = vmul(Vector2(-away.y, away.x), (double)orbit_radius[slot] * (double)orbit_speed[slot]);
			orbit_centre[slot] = centre;
		}
	} else if (kind == B_SPIRAL) {
		Arr<PackedVector2Array> base;
		Arr<PackedFloat32Array> wave, wave_age;
		base.load(m, k.base);
		wave.load(m, k.wave);
		wave_age.load(m, k.wave_age);
		for (int64_t n = first; n < first + count; n++) {
			const int64_t slot = members[n];
			const int64_t st = state[slot];
			if (st != S_MOVING && st != S_RETURNING) {
				continue;
			}
			const Vector2 velocity = vel[slot];
			base[slot] = base[slot] + vmul(velocity, delta);
			wave_age[slot] = (float)((double)wave_age[slot] + delta);
			const Vector2 side = Vector2(-velocity.y, velocity.x).normalized();
			pos[slot] = base[slot] + vmul(side, (double)wave[slot] * std::sin(TAU_D * (double)wave_age[slot] / SPIRAL_PERIOD));
		}
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
			const Vector2 anchor = caster_slot[slot] == CASTER_WIZARD
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
				const double bend = turned ? 0.0 : clampf((double)heading.angle_to(vel[slot]), -RETURN_BEND, RETURN_BEND);
				const Vector2 goal = home_at[slot];
				double want = 0.0;
				if (goal.is_finite() && !goal.is_equal_approx(here)) {
					want = clampf((double)heading.angle_to(goal - here), -RETURN_BEND, RETURN_BEND);
				}
				heading = heading.rotated((real_t)UtilityFunctions::move_toward(bend, want, (double)turn[slot] * (double)speed[slot] * delta));
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

bool ShotKernel::sample_shots(Object *m, double now) {
	const Names &k = *names;
	Arr<PackedInt32Array> trail, trail_kept, trail_newest;
	Arr<PackedByteArray> alive, motion;
	Arr<PackedVector2Array> pos, orbit_centre, trail_last;
	Arr<PackedFloat32Array> born, trail_odo, trail_data;
	trail.load(m, k.trail);
	trail_kept.load(m, k.trail_kept);
	trail_newest.load(m, k.trail_newest);
	alive.load(m, k.alive);
	motion.load(m, k.motion);
	pos.load(m, k.pos);
	orbit_centre.load(m, k.orbit_centre);
	trail_last.load(m, k.trail_last);
	born.load(m, k.born);
	trail_odo.load(m, k.trail_odo);
	trail_data.load(m, k.trail_data);
	const int64_t high = m->get(k.high);
	const double sim_time = m->get(k.sim_time);
	ERR_FAIL_COND_V(high > trail.n || high > pos.n, false);
	bool dirty = false;
	for (int64_t slot = 0; slot < high; slot++) {
		const int64_t row = trail[slot];
		if (row < 0 || alive[slot] == 0) {
			continue;
		}
		Vector2 at = pos[slot];
		if (motion[slot] == MOTION_ORBIT) {
			at = drawn_at(MOTION_ORBIT, sim_time, born[slot], orbit_centre[slot], at);
		}
		int64_t kept = trail_kept[row];
		if (kept > 0) {
			const double moved = at.distance_to(trail_last[row]);
			if (moved > TRAIL_JUMP) {
				kept = 0;
			} else {
				trail_odo[row] = (float)((double)trail_odo[row] + moved);
			}
		}
		const int64_t newest = trail_newest[row] + 1;
		const int64_t i = row * TRAIL_STRIDE + (newest % TRAIL_SAMPLES) * 4;
		ERR_FAIL_COND_V(i + 3 >= trail_data.n, dirty);
		trail_data[i] = at.x;
		trail_data[i + 1] = at.y;
		trail_data[i + 2] = trail_odo[row];
		trail_data[i + 3] = (float)now;
		trail_newest[row] = (int32_t)newest;
		trail_kept[row] = (int32_t)MIN(kept + 1, (int64_t)TRAIL_SAMPLES);
		trail_last[row] = at;
		dirty = true;
	}
	return dirty;
}

// `_count_batches` (no solid shots): `_batch_counts` and every live shot's drawn data.
void ShotKernel::count_draw(Object *m) {
	const Names &k = *names;
	Arr<PackedByteArray> alive, motion, drawn_batch;
	Arr<PackedInt64Array> seq, drawn_seq;
	Arr<PackedFloat32Array> radius, drawn_radius, drawn_size;
	Arr<PackedInt32Array> look, drawn_look, drawn_particles, ramp, batch_counts, loose, trail_ramp;
	Arr<PackedColorArray> drawn_color;
	alive.load(m, k.alive);
	motion.load(m, k.motion);
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
	loose.load(m, k.loose);
	trail_ramp.load(m, k.trail_ramp);
	drawn_color.load(m, k.drawn_color);
	const int64_t high = m->get(k.high);
	const int64_t loose_count = m->get(k.loose_count);
	ERR_FAIL_COND(high > alive.n || high > drawn_seq.n || batch_counts.n < BATCHES || loose_count > loose.n);
	for (int64_t b = 0; b < BATCHES; b++) {
		batch_counts[b] = 0;
	}
	for (int64_t slot = 0; slot < high; slot++) {
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
			int64_t batch = BATCH_BOLT;
			if (!is_hat_ramp(rmp)) {
				batch = mot == MOTION_STILL ? BATCH_ENEMY_RUNE : BATCH_ENEMY;
			} else if (mot == MOTION_STILL) {
				batch = BATCH_RUNE;
			} else if (mot == MOTION_ORBIT) {
				batch = BATCH_ORBIT;
			}
			drawn_batch[slot] = (uint8_t)batch;
			drawn_color[slot] = look_color(rmp, look_core_zoom(r), look[slot]);
			drawn_size[slot] = (float)look_size(r);
			drawn_particles[slot] = (int32_t)particles_of(look[slot]);
		}
		batch_counts[drawn_batch[slot]] += 1;
	}
	for (int64_t n = 0; n < loose_count; n++) {
		const int64_t rmp = trail_ramp[loose[n]];
		batch_counts[is_hat_ramp(rmp) ? BATCH_BOLT : BATCH_ENEMY] += 1;
	}
}

// `update_draw`'s writing (no solid shots): every live shot and every loose trail into the batches'
// buffers, which the kernel holds (`buffer`), sized to the manager's rooms; `_draw_out` gets the
// instances written per batch (BATCH_*), the particles asked for and the trail cost.
void ShotKernel::draw_shots(Object *m, double fraction) {
	const Names &k = *names;
	Arr<PackedByteArray> alive, motion, drawn_batch;
	Arr<PackedVector2Array> prev, pos, vel, orbit_centre, trail_last, anchors;
	Arr<PackedFloat32Array> drawn_size, born;
	Arr<PackedInt32Array> drawn_particles, trail, trail_kept, trail_newest, loose, trail_caster, trail_flags;
	Arr<PackedInt32Array> trail_holder, trail_ramp, draw_out;
	Arr<PackedColorArray> drawn_color, core, trail_color, trail_core;
	alive.load(m, k.alive);
	motion.load(m, k.motion);
	drawn_batch.load(m, k.drawn_batch);
	prev.load(m, k.prev);
	pos.load(m, k.pos);
	vel.load(m, k.vel);
	orbit_centre.load(m, k.orbit_centre);
	trail_last.load(m, k.trail_last);
	anchors.load(m, k.anchors);
	drawn_size.load(m, k.drawn_size);
	born.load(m, k.born);
	drawn_particles.load(m, k.drawn_particles);
	trail.load(m, k.trail);
	trail_kept.load(m, k.trail_kept);
	trail_newest.load(m, k.trail_newest);
	loose.load(m, k.loose);
	trail_caster.load(m, k.trail_caster);
	trail_flags.load(m, k.trail_flags);
	trail_holder.load(m, k.trail_holder);
	trail_ramp.load(m, k.trail_ramp);
	draw_out.load(m, k.draw_out);
	drawn_color.load(m, k.drawn_color);
	core.load(m, k.core);
	trail_color.load(m, k.trail_color);
	trail_core.load(m, k.trail_core);
	const int64_t high = m->get(k.high);
	const int64_t loose_count = m->get(k.loose_count);
	const double sim_time = m->get(k.sim_time);
	ERR_FAIL_COND(high > alive.n || draw_out.n < BATCHES + 4 || loose_count > loose.n);
	const int64_t rooms[BATCHES] = { m->get(k.draw_room), m->get(k.rune_room), m->get(k.orbit_room),
		m->get(k.enemy_room), m->get(k.enemy_rune_room) };
	float *out_buffer[BATCHES];
	int64_t room[BATCHES];
	int64_t used[BATCHES] = { 0, 0, 0, 0, 0 };
	for (int64_t b = 0; b < BATCHES; b++) {
		if (_buffers[b].size() != rooms[b] * DRAW_STRIDE) {
			_buffers[b].resize(rooms[b] * DRAW_STRIDE);
		}
		// `ptrw`: a copy only if the renderer still holds last frame's buffer.
		out_buffer[b] = _buffers[b].ptrw();
		room[b] = rooms[b];
	}
	// `_write_trail` into batch `b`, or nothing past its room (the GDScript would fail there).
	auto write_trail = [&](int64_t b, int64_t row, const Vector2 &at, int64_t flags, const Color &color, const Color &cr) {
		if (used[b] >= room[b]) {
			return;
		}
		float *buf = out_buffer[b] + used[b] * DRAW_STRIDE;
		used[b] += 1;
		buf[0] = (float)row;
		buf[1] = row >= 0 ? (float)trail_kept[row] : 0.0f;
		buf[2] = 0.0f;
		buf[3] = at.x;
		buf[4] = row >= 0 ? (float)trail_newest[row] : 0.0f;
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
	int64_t asked = 0;
	int64_t trails = 0;
	for (int64_t slot = 0; slot < high; slot++) {
		if (alive[slot] == 0) {
			continue;
		}
		const int64_t mot = motion[slot];
		Vector2 at = prev[slot].lerp(pos[slot], (real_t)fraction);
		if (mot == MOTION_ORBIT) {
			at = drawn_at(mot, sim_time, born[slot], orbit_centre[slot], at);
		}
		const int64_t batch = drawn_batch[slot];
		const double size = drawn_size[slot];
		const Color look_data = drawn_color[slot];
		asked += drawn_particles[slot];
		const bool rune = mot == MOTION_STILL;
		Vector2 dir = Vector2(1, 0);
		if (rune) {
			if (vel[slot].length_squared() > 0.0f) {
				dir = vel[slot].normalized();
			}
		} else {
			trails += TRAIL_COST;
		}
		const int64_t flags = TRAIL_HEAD | (mot == MOTION_ORBIT ? TRAIL_ORBIT : 0);
		if (batch == BATCH_ENEMY_RUNE || batch == BATCH_RUNE) {
			// `_write_stones` for a shot that is not solid: one stone.
			if (used[batch] < room[batch]) {
				write_quad(out_buffer[batch] + used[batch] * DRAW_STRIDE, dir, size, at, look_data, core[slot], KIND_RUNE,
						trace_code(sim_time - (double)born[slot]));
				used[batch] += 1;
			}
		} else if (batch == BATCH_ENEMY || batch == BATCH_ORBIT) {
			write_trail(batch, trail[slot], at, flags, look_data, core[slot]);
		} else {
			write_trail(BATCH_BOLT, trail[slot], at, flags, look_data, core[slot]);
		}
	}
	const int64_t shots = used[0] + used[1] + used[2] + used[3] + used[4];
	const int64_t enemy_shots = used[BATCH_ENEMY] + used[BATCH_ENEMY_RUNE];
	for (int64_t n = 0; n < loose_count; n++) {
		const int64_t row = loose[n];
		const int64_t caster = trail_caster[row];
		Vector2 head = trail_last[row];
		int64_t flags = trail_flags[row];
		if (trail_holder[row] == ROW_CASTER) {
			flags |= TRAIL_HEAD;
			if (anchors[caster].is_finite()) {
				head = anchors[caster];
			}
		}
		write_trail(is_hat_ramp(trail_ramp[row]) ? BATCH_BOLT : BATCH_ENEMY, row, head, flags, trail_color[row], trail_core[row]);
	}
	for (int64_t b = 0; b < BATCHES; b++) {
		draw_out[b] = (int32_t)used[b];
	}
	draw_out[BATCHES] = (int32_t)asked;
	draw_out[BATCHES + 1] = (int32_t)trails;
	draw_out[BATCHES + 2] = (int32_t)shots;
	draw_out[BATCHES + 3] = (int32_t)enemy_shots;
}

PackedFloat32Array ShotKernel::buffer(int64_t batch) const {
	ERR_FAIL_INDEX_V(batch, BATCHES, PackedFloat32Array());
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
	ClassDB::bind_method(D_METHOD("pass_common", "manager", "top", "delta"), &ShotKernel::pass_common);
	ClassDB::bind_method(D_METHOD("hits", "manager", "n", "top", "resume", "limit", "delta"), &ShotKernel::hits);
	ClassDB::bind_method(D_METHOD("homing_pass", "manager", "first", "count", "delta"), &ShotKernel::homing_pass);
	ClassDB::bind_method(D_METHOD("run_pass", "manager", "kind", "first", "count", "delta"), &ShotKernel::run_pass);
	ClassDB::bind_method(D_METHOD("sample_shots", "manager", "now"), &ShotKernel::sample_shots);
	ClassDB::bind_method(D_METHOD("count_draw", "manager"), &ShotKernel::count_draw);
	ClassDB::bind_method(D_METHOD("draw_shots", "manager", "fraction"), &ShotKernel::draw_shots);
	ClassDB::bind_method(D_METHOD("buffer", "batch"), &ShotKernel::buffer);
	ClassDB::bind_method(D_METHOD("threat_scan", "manager", "point", "radius", "team", "own", "horizon"), &ShotKernel::threat_scan);
	ClassDB::bind_method(D_METHOD("threat_fill", "manager", "horizon"), &ShotKernel::threat_fill);
	ClassDB::bind_method(D_METHOD("threat_query", "manager", "point", "radius", "team", "own", "horizon"), &ShotKernel::threat_query);
	ClassDB::bind_method(D_METHOD("version"), &ShotKernel::version);
}
