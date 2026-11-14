extends "res://tests/support/suite.gd"
## The session rules (core/sim/session_rules.gd, online-ready N11): the platform's defaults, a copy
## that stands apart, the bytes a replay's header carries and the ranges its decoder holds them to,
## and which rules a run takes (a replay's while one is on the frames service's deck, else this
## machine's).

const ManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const FramesScript := preload("res://core/sim/frames.gd")


func test_the_defaults_are_the_platforms() -> void:
	var made: SessionRules = SessionRules.defaults()
	var web: bool = OS.has_feature("web")
	check_equal(made.shot_cap, ManagerScript.DEFAULT_CAP_WEB if web else ManagerScript.DEFAULT_CAP_DESKTOP, "the shot cap")
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


## Every rule is a row of FIELDS (its copy, comparison and bytes follow from it), and the header
## holds 32 bits a row: a member added without its row fails here.
func test_every_rule_is_a_row_of_the_fields() -> void:
	var rows: Array[StringName] = []
	for field: Array in SessionRules.FIELDS:
		rows.append(field[0])
	for property: Dictionary in (SessionRules as Script).get_script_property_list():
		if property["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE == 0 or String(property["name"]).begins_with("_"):
			continue
		check(rows.has(StringName(property["name"])), "%s is a rule: add its row to SessionRules.FIELDS" % property["name"])
	check_equal(SessionRules.BYTES, 4 * SessionRules.FIELDS.size(), "BYTES is 32 bits a rule")
	var changed := SessionRules.new()
	for field: Array in SessionRules.FIELDS:
		changed.set(field[0], (field[2] as int) + 1)
	var back := SessionRules.new()
	var bytes := PackedByteArray()
	changed.encode_into(bytes)
	check_equal(back.decode_at(bytes, 0), "", "every row read back")
	check(back.equals(changed) and changed.copy().equals(changed), "every row copied, compared and carried")


## Each bag of an inventory has its capacity among the rules (items I4), none at the start.
func test_every_bag_has_its_capacity_among_the_rules() -> void:
	var rules := SessionRules.new()
	var rows: Array[StringName] = []
	for field: Array in SessionRules.FIELDS:
		rows.append(field[0])
	for bag: StringName in ItemKinds.BAGS:
		check(rows.has(StringName(SessionRules.BAG_RULE + bag)), "the bag %s has a rule: add `bag_%s` to SessionRules" % [bag, bag])
		check_equal(rules.bag_capacity(bag), SessionRules.NO_LIMIT, "%s has no limit at the start" % bag)
	rules.bag_cards = 30
	check_equal(rules.bag_capacity(&"cards"), 30, "a rule set is the bag's capacity in copies")
	check_equal(rules.bag_capacity(&"staffs"), SessionRules.NO_LIMIT, "and no other bag's")
	check_equal(rules.bag_capacity(&"no_such_bag"), SessionRules.NO_LIMIT, "a bag no rule names has no limit")
	var bytes := PackedByteArray()
	rules.encode_into(bytes)
	var back := SessionRules.new()
	check(back.decode_at(bytes, 0) == "" and back.bag_capacity(&"cards") == 30, "it comes back from a header")
	bytes.encode_u32(4 * rows.find(&"bag_cards"), SessionRules.MAX_BAG + 1)
	check(SessionRules.new().decode_at(bytes, 0) != "", "a capacity past the most is refused")


## A run takes the frames service's rules: a copy of this machine's, or of a replay's while one is
## on its deck (core/sim/replay_tape.gd).
func test_a_run_takes_a_copy_of_the_machines_rules_or_a_replays() -> void:
	SessionRules.machine().shot_cap = 1500
	var frames: FramesScript = FramesScript.new()
	var run: SessionRules = frames.next_run_rules()
	check_equal(run.shot_cap, 1500, "this machine's")
	run.shot_cap = 4000
	check_equal(SessionRules.machine().shot_cap, 1500, "a run's copy changes not the machine's")
	var replay := Replay.new()
	replay.rules.shot_cap = 250
	frames.set(&"_tape", ReplayTape.playing(replay))
	check_equal(frames.next_run_rules().shot_cap, 250, "the replay's")
	frames.free()
