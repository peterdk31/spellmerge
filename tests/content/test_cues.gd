extends "res://tests/support/suite.gd"
## The cues in `content/cues/` (CueBase): each is valid (no `problems()`), named for its file, and
## found by the registry; and `problems()` names what a broken one gets wrong.

const RegistryScript := preload("res://core/registry/registry.gd")

var registry: RegistryScript


func before_each() -> void:
	registry = own(RegistryScript.new()) as RegistryScript
	registry.scan()


func test_every_cue_is_valid_and_named_for_its_file() -> void:
	var ids: Array = registry.get_ids(&"cues")
	check(ids.size() >= 3, "the cues are found: %s" % [ids])
	for id: StringName in ids:
		var cue: CueBase = registry.get_resource(&"cues", id) as CueBase
		check(cue != null, "%s is a CueBase" % id)
		if cue == null:
			continue
		check_equal(cue.problems(), PackedStringArray(), "%s has no problems" % id)
		check_equal(cue.resource_path.get_file(), "%s.tres" % id, "%s is in its own file" % id)


func test_the_cues_the_game_names_are_there() -> void:
	for id: StringName in [&"blast", &"fireball", &"quake", &"slam", &"nova", &"telegraph", &"parry", &"deflect", &"enemy_death", &"boss_death", &"player_downed", &"self_hit", &"heal", &"expire"]:
		check(registry.get_resource(&"cues", id) is CueBase, "%s" % id)


## The flashes (not the motes) of `cue`'s parts, and how many motes its parts throw in all.
func _flashes(cue: CueBase) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for part in cue.parts:
		if not part.has("part"):
			found.append(part)
	return found


func _motes(cue: CueBase) -> int:
	var count: int = 0
	for part in cue.parts:
		if StringName(part.get("part", "")) == &"motes":
			count += int(part.get("count", 0))
	return count


## Until a boss has a look of its own, its death is an enemy's, with more motes, and the
## game-wide stop.
func test_a_boss_death_is_a_death_that_stops_the_game() -> void:
	var death: CueBase = registry.get_resource(&"cues", &"enemy_death") as CueBase
	var boss: CueBase = registry.get_resource(&"cues", &"boss_death") as CueBase
	if death == null or boss == null:
		check(false, "both death cues are there")
		return
	check_equal(_flashes(boss), _flashes(death), "the same flashes")
	check(_motes(boss) > _motes(death) and _motes(death) > 0, "more motes")
	check(is_equal_approx(boss.shake, death.shake) and is_equal_approx(boss.hold, death.hold) and boss.hold_shot == death.hold_shot, "the same weight")
	check_equal(boss.sound, death.sound, "the same sound")
	check_equal(death.stop_game, 0.0, "an enemy's death stops nobody else")
	check(boss.stop_game > 0.0, "a boss's stops the whole game")


func test_problems_names_what_is_wrong() -> void:
	var cue := CueBase.new()
	cue.parts = [{"flash": &"sparkles"}, {"flash": &"burst", "colour": Color.RED}, {"flash": &"burst", "way": &"sideways"}, {"flash": &"burst", "zoom": 2, "reach": 1.0}, {"flash": &"burst", "seconds": 0.0}, {"flash": &"ring_in", "lasts_size": true, "seconds": 0.5}]
	cue.kick_way = &"left"
	var found: PackedStringArray = cue.problems()
	check_equal(found.size(), 8, "an id, the kick way and one a part: %s" % [found])


func test_a_motes_part_names_what_is_wrong() -> void:
	var cue := CueBase.new()
	cue.id = &"test"
	cue.parts = [{"part": &"motes"}, {"part": &"motes", "kind": &"surface", "count": 40, "reach": 1.0, "spread": 360.0, "up": 1.5, "ring": true, "way": &"back"}]
	check_equal(cue.problems(), PackedStringArray(), "a motes part needs no flash, and takes its own keys")
	cue.parts = [{"part": &"motes", "zoom": 2}, {"part": &"motes", "way": &"sideways"}, {"part": &"motes", "count": 0}, {"part": &"motes", "spread": 400.0}, {"part": &"motes", "kind": &""}]
	check_equal(cue.problems().size(), 5, "one a part: %s" % [cue.problems()])


## A flash's colour is one of its own, plain, the caster's ramp alone (`bare`) or the body's own
## (`body`, S6: a death's puff).
func test_a_flash_takes_one_colour() -> void:
	var cue := CueBase.new()
	cue.id = &"test"
	cue.parts = [{"flash": &"puff", "body": true}]
	check_equal(cue.problems(), PackedStringArray(), "a flash in the body's colour")
	cue.parts = [{"flash": &"puff", "body": true, "plain": true}, {"flash": &"puff", "body": true, "color": Color.RED}]
	check_equal(cue.problems().size(), 2, "body beside another colour: %s" % [cue.problems()])


## A motes part with a `share` sheds (S6: a shot's end): a share above 0, and none of the keys that
## size a moment's burst (its count, reach, radius, ring), which a shed does not take.
func test_a_shed_share_takes_no_burst_keys() -> void:
	var cue := CueBase.new()
	cue.id = &"test"
	cue.parts = [{"part": &"motes", "share": 0.5, "spread": 90.0, "up": 0.5, "way": &"back", "color": Color.RED}]
	check_equal(cue.problems(), PackedStringArray(), "a share with the keys a shed takes")
	cue.parts = [{"part": &"motes", "share": 0.0}, {"part": &"motes", "share": 1.0, "count": 4, "ring": true}]
	check_equal(cue.problems().size(), 3, "a share of 0, and a count and a ring beside a share: %s" % [cue.problems()])


## A part's type is a row of CueBase.PART_TYPES (docs/milestones/spell-spectacle-2.md, S1): a type
## no row names is a problem, and a flash may say its type (`flash`) or leave it out.
func test_a_parts_type_is_one_of_the_part_types() -> void:
	var cue := CueBase.new()
	cue.id = &"test"
	cue.parts = [{"part": &"flash", "flash": &"burst"}, {"flash": &"burst"}]
	check_equal(cue.problems(), PackedStringArray(), "a flash, its type said or not")
	cue.parts = [{"part": &"sparkles", "flash": &"burst"}]
	check_equal(cue.problems().size(), 1, "an unknown type: %s" % [cue.problems()])
	for type: StringName in CueBase.PART_TYPES:
		check((CueBase.PART_TYPES[type] as Array).has("part"), "a %s part may say its type" % type)
