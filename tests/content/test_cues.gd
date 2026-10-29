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
	for id: StringName in [&"blast", &"fireball", &"quake", &"parry", &"deflect", &"enemy_death", &"boss_death", &"player_downed", &"self_hit", &"heal"]:
		check(registry.get_resource(&"cues", id) is CueBase, "%s" % id)


## Until a boss has a look of its own, its death is an enemy's and the game-wide stop.
func test_a_boss_death_is_a_death_that_stops_the_game() -> void:
	var death: CueBase = registry.get_resource(&"cues", &"enemy_death") as CueBase
	var boss: CueBase = registry.get_resource(&"cues", &"boss_death") as CueBase
	if death == null or boss == null:
		check(false, "both death cues are there")
		return
	check_equal(boss.parts, death.parts, "the same flashes")
	check(is_equal_approx(boss.shake, death.shake) and is_equal_approx(boss.hold, death.hold) and boss.hold_shot == death.hold_shot, "the same weight")
	check_equal(boss.sound, death.sound, "the same sound")
	check_equal(death.stop_game, 0.0, "an enemy's death stops nobody else")
	check(boss.stop_game > 0.0, "a boss's stops the whole game")


func test_problems_names_what_is_wrong() -> void:
	var cue := CueBase.new()
	cue.parts = [{"effect": &"sparkles"}, {"effect": &"burst", "colour": Color.RED}, {"effect": &"burst", "way": &"sideways"}, {"effect": &"burst", "zoom": 2, "reach": 1.0}, {"effect": &"burst", "seconds": 0.0}]
	cue.kick_way = &"left"
	var found: PackedStringArray = cue.problems()
	check_equal(found.size(), 7, "an id, the kick way and one a part: %s" % [found])
