extends "res://tests/support/suite.gd"
## Spawn styles as data (spawn styles AS1, docs/milestones/spawn-styles.md): every style file in
## content/spawn_styles has no problems (its id its folder's, its cue a cue of the game's) and the set none
## (no two styles name one biome); `rise` is `SpawnStyle.DEFAULT`'s numbers, and a field left out
## takes them; each problem `problems()` and `all_problems()` know is named. Which style an enemy
## spawns in (spawn styles AS2, `SpawnStyle.pick`): the enemy's own, else the first style by id that
## names the room's biome, else `rise`, else `DEFAULT`'s numbers; an id not found is passed over.

const RegistryScript := preload("res://core/registry/registry.gd")
const FOLDER: StringName = SpawnStyle.FOLDER


## Whether the game has a cue of id `cue`.
func _known_cue(cue: StringName) -> bool:
	return root.get_node("Registry").call("get_resource", &"cues", cue) != null


func _styles() -> Array[SpawnStyle]:
	var found: Array[SpawnStyle] = []
	for style: Resource in root.get_node("Registry").call("get_all", FOLDER):
		check(style is SpawnStyle, "%s is a style" % style.resource_path)
		if style is SpawnStyle:
			found.append(style as SpawnStyle)
	return found


## How many fixtures were read from a folder (each its own path: two resources can't share one).
var _paths: int = 0


## A style of `rise`'s numbers, its id `id`, as if read from its folder `folder` (none: made in code).
func _style(id: StringName = &"rise", folder: String = "") -> SpawnStyle:
	var style := SpawnStyle.from_default()
	style.id = id
	if folder != "":
		_paths += 1
		style.resource_path = "res://content/spawn_styles/%s/%s_%d.tres" % [folder, id, _paths]
	return style


func test_every_style_file_has_no_problems() -> void:
	var styles: Array[SpawnStyle] = _styles()
	check(not styles.is_empty(), "the registry finds the styles in content/spawn_styles")
	for style in styles:
		check_equal(style.problems(_known_cue), PackedStringArray(), "%s has no problems" % style.resource_path)
		check(style.resource_path.begins_with("res://content/spawn_styles/%s/" % style.id), "%s is in its own folder" % style.id)
	check_equal(SpawnStyle.all_problems(styles, _known_cue), PackedStringArray(), "and the set has none")


## `rise` is today's look: `DEFAULT`'s numbers, each written out in its file; a style made in code
## (a field left out) takes them too.
func test_rise_is_the_default() -> void:
	var rise := root.get_node("Registry").call("get_resource", FOLDER, SpawnStyle.DEFAULT["id"]) as SpawnStyle
	check(rise != null, "content/spawn_styles/rise is there")
	if rise == null:
		return
	var made := SpawnStyle.new()
	for field: String in SpawnStyle.DEFAULT:
		check_equal(rise.get(field), SpawnStyle.DEFAULT[field], "rise's %s is DEFAULT's" % field)
		if field != "id":
			check_equal(made.get(field), SpawnStyle.DEFAULT[field], "a new style's %s is DEFAULT's" % field)
	check_equal(SpawnStyle.from_default().id, &"rise", "the default is rise")
	check_equal(rise.biomes, [] as Array[StringName], "rise names no biome: every biome no style names spawns as it")
	check(rise.mark_strip == null, "and draws the ring, no strip")
	check(SpawnStyle.MOTIONS.has(rise.motion), "its motion is one of the motions")


func test_a_sound_style_has_no_problems() -> void:
	check_equal(_style(&"fixture", "fixture").problems(_known_cue), PackedStringArray(), "rise's numbers in a folder of its id")
	check_equal(_style().problems(), PackedStringArray(), "made in code, with no folder")
	var slow: SpawnStyle = _style()
	slow.seconds = 2.0
	slow.colours = &"stone"
	slow.biomes = [&"crypt"] as Array[StringName]
	check_equal(slow.problems(), PackedStringArray(), "the longest, a palette colour, a biome")


func test_each_problem_is_named() -> void:
	# Each case: what is wrong, and the fields set to make it so (on a sound style in its folder).
	var cases: Array = [
		["an id that is not its folder's", {"resource_path": "res://content/spawn_styles/frost/fixture_frost.tres"}],
		["no id", {"id": &""}],
		["a motion there is none of", {"motion": &"drop"}],
		["too short", {"seconds": 0.2, "close_from": 0.6}],
		["too long: it can't be hurt so long", {"seconds": 2.5}],
		["no number", {"seconds": NAN}],
		["the mark ending after the close starts", {"mark_end": 0.95}],
		["a mark ending at 0", {"mark_end": 0.0}],
		["a close starting at the end", {"close_from": 1.0}],
		["a close too short for its frames (0.08 x 0.5 s x 60 = 2.4)", {"seconds": 0.5}],
		["a mark too short for its frames (0.2 x 0.8 s x 60 = 9.6)", {"mark_frames": 16, "mark_end": 0.2}],
		["a mark in 2 frames", {"mark_frames": 2}],
		["a close in 2 frames", {"close_frames": 2}],
		["colours that are no palette material", {"colours": &"teal"}],
		["a player's colours", {"colours": &"player_1"}],
		["a mark strip (not drawn before AS4)", {"mark_strip": PlaceholderTexture2D.new()}],
		["a biome twice", {"biomes": [&"crypt", &"crypt"] as Array[StringName]}],
		["a cue there is none of", {"cue": &"no_such_cue"}],
	]
	for case: Array in cases:
		var style: SpawnStyle = _style(&"fixture", "fixture")
		var fields: Dictionary = case[1]
		for field: String in fields:
			style.set(field, fields[field])
		var found: PackedStringArray = style.problems(_known_cue)
		check_equal(found.size(), 1, "%s: %s" % [case[0], found])
	var silent: SpawnStyle = _style()
	silent.cue = &""
	check_equal(silent.problems(_known_cue), PackedStringArray(), "no cue is no problem: none plays")


## Across the styles: no two name one biome, so none wins by the order they are read in.
func test_two_styles_naming_one_biome_is_a_problem() -> void:
	var frost: SpawnStyle = _style(&"frost")
	frost.biomes = [&"crypt", &"glacier"] as Array[StringName]
	var rime: SpawnStyle = _style(&"rime")
	rime.biomes = [&"glacier"] as Array[StringName]
	var found: PackedStringArray = SpawnStyle.all_problems([frost, rime] as Array[SpawnStyle])
	check_equal(found.size(), 1, "one line: %s" % found)
	check(found.size() == 1 and found[0].contains("glacier") and found[0].contains("frost") and found[0].contains("rime"), "naming the biome and both styles")
	rime.biomes = [&"swamp"] as Array[StringName]
	check_equal(SpawnStyle.all_problems([frost, rime] as Array[SpawnStyle]), PackedStringArray(), "a biome each is fine")
	rime.seconds = 9.0
	check_equal(SpawnStyle.all_problems([frost, rime] as Array[SpawnStyle]).size(), 1, "each style's own problems too")


## A registry of its own holding `styles` (freed by the test), and an enemy naming `own` as its style.
func _registry_of(styles: Array[SpawnStyle]) -> RegistryScript:
	var registry := RegistryScript.new()
	for style in styles:
		check(registry.add(FOLDER, style), "%s added" % style.id)
	return registry


func _enemy(own: StringName = &"") -> EnemyBase:
	var enemy := EnemyBase.new()
	enemy.id = &"fixture_enemy"
	enemy.spawn_style = own
	return enemy


## The picker's order: the enemy's own, then the first style by id that names the biome, then `rise`.
func test_pick_takes_the_enemys_then_the_biomes_then_rise() -> void:
	var rise: SpawnStyle = _style(&"rise")
	rise.seconds = 1.1
	var frost: SpawnStyle = _style(&"frost")
	frost.biomes = [&"glacier"] as Array[StringName]
	var storm: SpawnStyle = _style(&"storm")
	var registry := _registry_of([storm, rise, frost] as Array[SpawnStyle])
	check_equal(SpawnStyle.pick(registry, _enemy(&"storm"), &"glacier"), storm, "the enemy's own wins over its biome's")
	check_equal(SpawnStyle.pick(registry, _enemy(&"storm"), &"crypt"), storm, "and over rise")
	check_equal(SpawnStyle.pick(registry, _enemy(), &"glacier"), frost, "no style of its own: the biome's")
	check_equal(SpawnStyle.pick(registry, _enemy(), &"crypt"), rise, "a biome no style names: rise, the registry's")
	check_equal(SpawnStyle.pick(registry, _enemy(), &""), rise, "no biome: rise")
	check_equal(SpawnStyle.pick(registry, null, &"glacier"), frost, "no enemy data: the biome's")
	registry.free()


## Two styles naming one biome (a problem `all_problems` names, so content never has it): the first by
## id, never the order they were read or added in.
func test_pick_takes_the_first_by_id_of_two_naming_one_biome() -> void:
	var rime: SpawnStyle = _style(&"rime")
	rime.biomes = [&"glacier"] as Array[StringName]
	var frost: SpawnStyle = _style(&"frost")
	frost.biomes = [&"swamp", &"glacier"] as Array[StringName]
	check_equal(SpawnStyle.all_problems([rime, frost] as Array[SpawnStyle]).size(), 1, "a problem of the set")
	var registry := _registry_of([rime, frost, _style(&"rise")] as Array[SpawnStyle])
	check_equal(SpawnStyle.pick(registry, _enemy(), &"glacier"), frost, "frost before rime, though rime was added first")
	registry.free()


## A style the registry lacks (the enemy's own misnamed, or deleted) is passed over; with no `rise`
## either, or no registry, it is a style of `DEFAULT`'s numbers.
func test_pick_passes_over_a_missing_style() -> void:
	var frost: SpawnStyle = _style(&"frost")
	frost.biomes = [&"glacier"] as Array[StringName]
	var rise: SpawnStyle = _style(&"rise")
	var registry := _registry_of([frost, rise] as Array[SpawnStyle])
	check_equal(SpawnStyle.pick(registry, _enemy(&"no_such_style"), &"glacier"), frost, "its own not found: its biome's")
	check_equal(SpawnStyle.pick(registry, _enemy(&"no_such_style"), &"crypt"), rise, "nor a biome's: rise")
	registry.free()
	var bare := _registry_of([frost] as Array[SpawnStyle])
	var made: SpawnStyle = SpawnStyle.pick(bare, _enemy(&"no_such_style"), &"crypt")
	check(made != null and made != frost, "no rise: a style made of the default")
	for field: String in SpawnStyle.DEFAULT:
		check_equal(made.get(field), SpawnStyle.DEFAULT[field], "its %s is DEFAULT's" % field)
	bare.free()
	var none: SpawnStyle = SpawnStyle.pick(null, _enemy(&"frost"), &"glacier")
	check(none != null and none.id == SpawnStyle.DEFAULT["id"] and none.seconds == float(SpawnStyle.DEFAULT["seconds"]), "no registry: the default")


## Every style an enemy or boss names is one of the registry's, so a name mistyped is not silent
## (`pick` would pass over it).
func test_every_enemys_style_is_a_style() -> void:
	var registry: Node = root.get_node("Registry")
	for folder: StringName in EnemyBase.FOLDERS:
		for item: Resource in registry.call("get_all", folder):
			var enemy := item as EnemyBase
			if enemy != null and enemy.spawn_style != &"":
				check(registry.call("get_resource", FOLDER, enemy.spawn_style) != null, "%s: its spawn style '%s' is a style" % [enemy.id, enemy.spawn_style])
