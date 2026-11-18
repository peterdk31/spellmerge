extends "res://tests/support/suite.gd"
## Spawn styles as data (spawn styles AS1, docs/milestones/spawn-styles.md): every style file in
## content/spawn_styles has no problems (its id its folder's, its cue a cue of the game's) and the set none
## (no two styles name one biome); `rise` is `SpawnStyle.DEFAULT`'s numbers, and a field left out
## takes them; each problem `problems()` and `all_problems()` know is named. Which style an enemy
## spawns in (spawn styles AS2, `SpawnStyle.pick`): the enemy's own, else the first style by id that
## names the room's biome, else `rise`, else `DEFAULT`'s numbers; an id not found is passed over.

const RegistryScript := preload("res://core/registry/registry.gd")
const FOLDER: StringName = SpawnStyle.FOLDER
const MarkStrips := preload("res://tests/support/mark_strips.gd")
## Where the strip tests write their fixture folders (each its own, as two resources can't share a path).
const STRIP_ROOT: String = "user://test_spawn_style_strips"


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
		check_equal(style.problems(_known_cue, MarkStrips.listed), PackedStringArray(), "%s has no problems" % style.resource_path)
		check(style.resource_path.begins_with("res://content/spawn_styles/%s/" % style.id), "%s is in its own folder" % style.id)
	check_equal(SpawnStyle.all_problems(styles, _known_cue, MarkStrips.listed), PackedStringArray(), "and the set has none")


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
		["a motion's stage too short for materialize (0.3 x 0.8 s x 60 = 14.4 < 17)", {"motion": &"materialize", "mark_end": 0.7, "close_from": 0.9}],
		["colours that are no palette material", {"colours": &"teal"}],
		["a player's colours", {"colours": &"player_1"}],
		["a mark strip that is no file of its folder", {"mark_strip": MarkStrips.strip(16, 4)}],
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


func after_each() -> void:
	if DirAccess.dir_exists_absolute(STRIP_ROOT):
		for folder: String in DirAccess.get_directories_at(STRIP_ROOT):
			MarkStrips.remove_folder(STRIP_ROOT.path_join(folder))
		DirAccess.remove_absolute(STRIP_ROOT)


## A mark strip (spawn styles AS4): square frames, at least `MIN_FRAMES` (and one more than
## `close_frames`), time in the mark stage at `CHECK_FPS` for each, frames `MAX_STRIP_SIDE` at most.
## Each made in code (no folder, so no listing is asked for).
func test_each_strip_problem_is_named() -> void:
	check_equal(MarkStrips.style(&"rooted", MarkStrips.strip(16, 4)).problems(), PackedStringArray(), "four frames of 16 in rise's numbers")
	check_equal(MarkStrips.style(&"rooted", MarkStrips.strip(SpawnStyle.MAX_STRIP_SIDE, 4)).problems(), PackedStringArray(), "frames as big as allowed")
	# Each case: what is wrong, the strip, the fields set, and a word of the line it is named by.
	var cases: Array = [
		["frames that are not square (50 wide, 16 high)", MarkStrips.strip(16, 3, 50, 16), {}, "square"],
		["a strip narrower than it is high", MarkStrips.strip(16, 1, 8, 16), {}, "square"],
		["two frames", MarkStrips.strip(16, 2), {}, "has 2 frames"],
		["three frames and rise's close of 3: the close would show one frame twice", MarkStrips.strip(16, 3), {}, "has 3 frames"],
		["no more frames than close_frames (4 frames, a close of 4)", MarkStrips.strip(16, 4), {"close_frames": 4, "seconds": 1.2}, "has 4 frames"],
		["a mark stage too short for its frames (0.4 x 0.8 s x 60 = 19.2 < 24)", MarkStrips.strip(8, 24), {}, "too short for its strip"],
		["frames over 64 px", MarkStrips.strip(80, 4), {}, "80 px"],
	]
	for case: Array in cases:
		var style: SpawnStyle = MarkStrips.style(&"rooted", case[1])
		var fields: Dictionary = case[2]
		for field: String in fields:
			style.set(field, fields[field])
		var found: PackedStringArray = style.problems()
		check(found.size() == 1 and found[0].contains(case[3]), "%s: %s" % [case[0], found])
	var slow: SpawnStyle = MarkStrips.style(&"rooted", MarkStrips.strip(8, 24))
	slow.seconds = 1.0
	check_equal(slow.problems(), PackedStringArray(), "24 frames fit a mark stage of 0.4 x 1 s x 60 = 24")


## A style read from a file names a strip in its own folder, listed in the folder's assets.json.
func test_a_strip_must_be_a_listed_file_of_its_folder() -> void:
	var listed: SpawnStyle = _strip_in_folder("listed", true)
	check_equal(listed.problems(Callable(), MarkStrips.listed), PackedStringArray(), "in its folder and listed")
	var unlisted: SpawnStyle = _strip_in_folder("unlisted", false)
	var found: PackedStringArray = unlisted.problems(Callable(), MarkStrips.listed)
	check(found.size() == 1 and found[0].contains("not listed") and found[0].contains("assets.json"), "not listed: %s" % [found])
	check_equal(unlisted.problems(), PackedStringArray(), "with no lookup, no listing is asked for: problems() reads no file")
	var elsewhere: SpawnStyle = _strip_in_folder("elsewhere", true)
	elsewhere.resource_path = STRIP_ROOT.path_join("other/other.tres")
	found = elsewhere.problems(Callable(), MarkStrips.listed)
	check(found.size() == 1 and found[0].contains("not a .png or .svg file in its folder"), "a strip of another folder: %s" % [found])
	# Each: a strip whose path is not an image file of the style's folder.
	for path: String in ["", "made/made.tres::ImageTexture_x", "made/mark.tres", "made/mark.webp"]:
		var made: SpawnStyle = MarkStrips.style(&"made", MarkStrips.strip(16, 4))
		made.resource_path = STRIP_ROOT.path_join("made/made.tres")
		if path != "":
			made.mark_strip.resource_path = STRIP_ROOT.path_join(path)
		found = made.problems(Callable(), func(_file: String, _path: String) -> bool: return true)
		check(found.size() == 1 and found[0].contains("not a .png or .svg file in its folder"), "a strip at '%s' (made in code, embedded, a .tres, a .webp), even listed: %s" % [path, found])
	# The lookup the content test uses, on a repository path as an assets file writes it.
	var list: String = STRIP_ROOT.path_join("repo/assets.json")
	DirAccess.make_dir_recursive_absolute(list.get_base_dir())
	var file := FileAccess.open(list, FileAccess.WRITE)
	file.store_string(JSON.stringify({"assets": [{"path": "content/spawn_styles/roots/mark.png"}]}))
	file.close()
	check(MarkStrips.listed(list, "res://content/spawn_styles/roots/mark.png"), "a res:// strip is found by its path from the repository root")
	check(not MarkStrips.listed(list, "res://content/spawn_styles/roots/other.png"), "and another file is not")
	check(not MarkStrips.listed(STRIP_ROOT.path_join("none/assets.json"), "res://content/spawn_styles/none/mark.png"), "no list lists nothing")


## A style in the folder `name` under `STRIP_ROOT`, as if read from its file there, its strip's png
## written there and listed in its assets.json if `listed`.
func _strip_in_folder(name: String, listed: bool) -> SpawnStyle:
	var folder: String = STRIP_ROOT.path_join(name)
	var strip: ImageTexture = MarkStrips.strip(16, 4)
	MarkStrips.write_folder(folder, strip, listed)
	var style: SpawnStyle = MarkStrips.style(StringName(name), strip)
	style.resource_path = folder.path_join("%s.tres" % name)
	return style


## The frames a strip shows over a spawn: each in order over the mark stage, the last held, then the
## close's frames backwards down to the first; none before or after.
func test_a_strips_frames_hold_and_close() -> void:
	var style: SpawnStyle = SpawnStyle.from_default()
	var seen: Array = []
	for n in 401:
		var frame: int = SpawnStyle.strip_frame(4, float(n) / 400.0 * 0.9999, style)
		if seen.is_empty() or seen[-1] != frame:
			seen.append(frame)
	check_equal(seen, [0, 1, 2, 3, 2, 1, 0], "four frames up, three back down: rise's close of 3")
	check_equal(SpawnStyle.strip_frame(4, style.mark_end - 0.001, style), 3, "the last frame by the mark's end")
	check_equal(SpawnStyle.strip_frame(4, style.close_from - 0.001, style), 3, "held till the close")
	check_equal(SpawnStyle.strip_frame(4, style.close_from, style), 2, "the close's first look a step down, as the ring's")
	check_equal(SpawnStyle.strip_frame(4, 1.0, style), -1, "none once it stands")
	check_equal(SpawnStyle.strip_frame(4, -0.1, style), -1, "none before")
	check_equal(SpawnStyle.strip_frame(0, 0.5, style), -1, "none of no strip")
	var long: Array = []
	for n in 401:
		var frame: int = SpawnStyle.strip_frame(8, style.close_from + float(n) / 400.0 * (0.9999 - style.close_from), style)
		if long.is_empty() or long[-1] != frame:
			long.append(frame)
	check_equal(long, [5, 2, 0], "eight frames close in three looks, picked backwards, ending on the first")
	check_equal(SpawnStyle.strip_frames(MarkStrips.strip(16, 4)), 4, "the frames are its width over its height")
	check_equal(SpawnStyle.strip_frames(MarkStrips.strip(16, 3, 50, 16)), 0, "not square: none")
	check_equal(SpawnStyle.strip_frames(null), 0, "no strip: none")


## The scale a strip is drawn at: the whole number nearest the footprint's width over its side, 1 to 4.
func test_a_strips_scale_is_whole_and_fits_the_footprint() -> void:
	check_equal(SpawnStyle.strip_scale(16, 7.0), 1, "16 px under a footprint 14 wide: its own size")
	check_equal(SpawnStyle.strip_scale(16, 16.0), 2, "under one 32 wide: twice")
	check_equal(SpawnStyle.strip_scale(16, 2.0), 1, "never smaller than its own size")
	check_equal(SpawnStyle.strip_scale(8, 100.0), SpawnStyle.MAX_STRIP_SCALE, "never more than 4 times")
	check_equal(SpawnStyle.strip_scale(0, 7.0), 1, "no side: 1")


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
