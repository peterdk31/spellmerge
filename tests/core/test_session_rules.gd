extends "res://tests/support/suite.gd"
## The session rules (core/sim/session_rules.gd, online-ready N11): the platform's defaults, a copy
## that stands apart, the bytes a replay's header carries and the ranges its decoder holds them to,
## and which rules a run takes (a replay's while one deals, else this machine's).

const ManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const HordeScript := preload("res://gameplay/horde/horde.gd")


func test_the_defaults_are_the_platforms() -> void:
	var made: SessionRules = SessionRules.defaults()
	var web: bool = OS.has_feature("web")
	check_equal(made.shot_cap, ManagerScript.DEFAULT_CAP_WEB if web else ManagerScript.DEFAULT_CAP_DESKTOP, "the shot cap")
	check_equal(made.horde_alive, HordeScript.MAX_ALIVE_WEB if web else HordeScript.MAX_ALIVE_DESKTOP, "the horde's cap")
	check_equal(made.hit_work, ManagerScript.WORK_PER_STEP, "the hit work")
	check_equal(made.fire_shots, SpellLimits.FIRE_SHOTS_PER_STEP, "the fire pacing")
	check(SessionRules.machine().equals(made), "this machine's start as them")


func test_a_copy_stands_apart() -> void:
	var rules: SessionRules = SessionRules.defaults()
	var other: SessionRules = rules.copy()
	check(other.equals(rules), "equal")
	other.shot_cap = 250
	check(not other.equals(rules) and rules.shot_cap != 250, "a change to the copy leaves the first")


func test_the_bytes_come_back_and_bad_ones_are_refused() -> void:
	var rules := SessionRules.new()
	rules.shot_cap = 50000
	rules.horde_alive = 150
	rules.hit_work = 0x7fff_ffff
	rules.fire_shots = 0
	var bytes := PackedByteArray([7])
	rules.encode_into(bytes)
	check_equal(bytes.size(), 1 + SessionRules.BYTES, "BYTES bytes after what was there")
	var back := SessionRules.new()
	check_equal(back.decode_at(bytes, 1), "", "read back")
	check(back.equals(rules), "the same rules")
	check(back.decode_at(bytes, 2) != "", "cut short")
	var bad: PackedByteArray = bytes.duplicate()
	bad.encode_u32(1, 0)
	var kept := SessionRules.new()
	check(kept.decode_at(bad, 1) != "" and kept.equals(SessionRules.new()), "a cap of 0 is refused, and nothing is changed")


func test_a_run_takes_a_replays_rules_while_it_deals_them() -> void:
	SessionRules.machine().shot_cap = 1500
	check_equal(SessionRules.for_run().shot_cap, 1500, "this machine's")
	var dealt := SessionRules.new()
	dealt.shot_cap = 250
	SessionRules.begin(dealt)
	dealt.shot_cap = 500
	var run: SessionRules = SessionRules.for_run()
	check_equal(run.shot_cap, 250, "the replay's, as they were dealt")
	run.shot_cap = 4000
	check_equal(SessionRules.for_run().shot_cap, 250, "a run's copy changes no other run's")
	SessionRules.end()
	check_equal(SessionRules.for_run().shot_cap, 1500, "this machine's again")
