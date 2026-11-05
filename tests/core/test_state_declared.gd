extends "res://tests/support/suite.gd"
## The state is declared (online-ready N1, docs/milestones/online-ready.md, "State by default"):
## every member of a simulation script (StateWalk.FOLDERS) is state unless the script lists it in
## DERIVED or VIEW (REFS are state, walked as who they point at), and state must be something the
## walker can hash and save.
##
## - Statically, for every simulation script and every inner class of one: every listed name is a
##   member (a rename leaves none behind), and no state member is typed as something that cannot be
##   state: a node of the engine or of a script outside the simulation (a service, a sprite), a
##   view-only node, a Callable, a Signal or an RID.
## - Statically, what the walker cannot see: a static member belongs to no object, so it is listed
##   in DERIVED or VIEW (a cache, a test switch) and never holds state; and simulation code reads no
##   clock (`Time`, `OS.get_ticks_*`) and rolls no global dice (`randomize()`, `randf()`, `randi()`,
##   `seed()`): a seed nobody chose comes from `SimSeed.fresh()` (core/sim). View-only scripts
##   (`VIEW_ONLY`) may do both.
## - Live: the determinism tests' scenes (tests/core/sim_scenes.gd: a staffed fight, a spell storm,
##   a horde wave) are walked after two seconds, and every card of content/spells is cast in the card
##   rules' world (tests/support/card_rules_world.gd) and walked as it casts, flies and lands; the
##   walks must meet no problem (a reference to a node it does not own, an engine object). New cards
##   and carriers are walked the day they land, with no edit here.
##
## Each failure names the file, the member and the fix ("add it to DERIVED, it is set up again, not
## saved").

const SimScenes := preload("res://tests/core/sim_scenes.gd")
const CardWorld := preload("res://tests/support/card_rules_world.gd")
const RegistryScript := preload("res://core/registry/registry.gd")

const STEPS: int = 120
## The steps each card's world is walked at: as it casts, in flight, as it lands and after.
const CARD_WALKS: Array[int] = [1, 12, 40, 75]
## The card world's wizard is driven by the fixture's scripted controller (test code, an inner class
## of tests/gameplay/actor/actor_fixture.gd), standing in for a player's: not the game's, so its
## problems are not the game's either.
const FIXTURE_CONTROLLERS: Array[String] = ["wizard.controller holds a Node (Node)", "wizard.home_controller holds a Node (Node)"]
## How long each card's world runs (seconds); the wizard keeps casting, so channels, repeats and
## held carriers are live at every walk.
const CARD_SECONDS: float = 1.4
## Code a simulation script may not hold outside a comment (see the class doc), and why.
const FORBIDDEN: Dictionary = {
	"(^|[^\\w])randomize\\(": "seeds a generator by the clock; take `SimSeed.fresh()` (core/sim)",
	"(^|[^.\\w])(randf|randi|randf_range|randi_range|randfn|seed)\\(": "rolls the engine's global dice; use a generator of its own, seeded by the game",
	"(^|[^\\w])Time\\.": "reads the clock; the simulation runs on its own time (`delta`, `sim_time`)",
	"(^|[^\\w])OS\\.get_(ticks|unix)": "reads the clock; the simulation runs on its own time (`delta`, `sim_time`)",
}


func test_every_listed_name_is_a_member() -> void:
	for entry in _simulation_scripts():
		var script: Script = entry["script"]
		var members: PackedStringArray = StateWalk.declared(script) + _statics_of(script)
		for list: String in StateWalk.LISTS:
			for name in StateWalk.listed(script, list):
				check(members.has(name), "%s: %s lists %s, which is no member (renamed?); take it out" % [entry["name"], list, name])


func test_no_state_member_is_typed_as_something_it_cannot_save() -> void:
	var classes: Dictionary[String, String] = {}
	for entry: Dictionary in ProjectSettings.get_global_class_list():
		classes[String(entry["class"])] = String(entry["path"])
	for entry in _simulation_scripts():
		var script: Script = entry["script"]
		if StateWalk.is_view_only(script):
			continue
		var skip: PackedStringArray = StateWalk.listed(script, "DERIVED") + StateWalk.listed(script, "VIEW") + StateWalk.listed(script, "REFS")
		var inherited: PackedStringArray = StateWalk.declared(script.get_base_script()) if script.get_base_script() != null else PackedStringArray()
		for info: Dictionary in script.get_script_property_list():
			var name: String = info["name"]
			if int(info["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE == 0 or skip.has(name) or inherited.has(name):
				continue
			var why: String = _cannot_hold(info, classes)
			check(why.is_empty(), "%s: %s holds %s; add it to DERIVED (a service, set up again), REFS (another body, state) or VIEW (only the drawing reads it)" % [entry["name"], name, why])


func test_no_static_member_holds_state() -> void:
	for entry in _simulation_scripts():
		var script: Script = entry["script"]
		if StateWalk.is_view_only(script):
			continue
		var listed: PackedStringArray = StateWalk.listed(script, "DERIVED") + StateWalk.listed(script, "VIEW")
		for name in _statics_of(script):
			check(listed.has(name), "%s: the static member %s belongs to no object, so no walk sees it; a cache or a switch goes in DERIVED, state goes in an object's member" % [entry["name"], name])


func test_simulation_code_reads_no_clock_and_rolls_no_global_dice() -> void:
	var patterns: Array[RegEx] = []
	for pattern: String in FORBIDDEN:
		patterns.append(RegEx.create_from_string(pattern))
	for entry in _simulation_scripts():
		var script: Script = entry["script"]
		var source: String = _source_of(script)
		if source.is_empty() or StateWalk.is_view_only(script):
			continue
		var lines: PackedStringArray = source.split("\n")
		for i in lines.size():
			var code: String = _code_of(lines[i])
			for p in patterns.size():
				if patterns[p].search(code) != null:
					check(false, "%s:%d %s: %s" % [entry["name"], i + 1, FORBIDDEN.values()[p], lines[i].strip_edges()])


func test_a_staffed_fight_walks_without_problems() -> void:
	_check_scene(&"fight")


func test_a_spell_storm_walks_without_problems() -> void:
	_check_scene(&"storm")


func test_a_horde_wave_walks_without_problems() -> void:
	_check_scene(&"horde")


## Every card of content/spells, cast alone (a carrier, with a payload when it carries one) or on
## the payload carrier (any other card; a trigger with a payload to fire), in the card rules' world
## with a teammate and two enemies, walked at CARD_WALKS.
func test_every_card_walks_without_problems() -> void:
	var registry := own(RegistryScript.new()) as Node
	registry.call("scan")
	var shelf := own(CardWorld.Shelf.new()) as CardWorld.Shelf
	shelf.base = registry
	var staff := StaffBase.new()
	staff.id = &"state_walk"
	staff.slots = 16
	staff.cast_delay = 0.0
	staff.recharge = 0.0
	var forms: Array[FormBase] = []
	var others: Array[SpellComponent] = []
	var payload: FormBase = null
	for card: Resource in registry.call("get_all", &"spells"):
		if card is FormBase:
			var form: FormBase = card
			forms.append(form)
			if form.carrier == &"atom" and (payload == null or form.shots > payload.shots):
				payload = form
		elif card is SpellComponent:
			others.append(card as SpellComponent)
	if payload == null:
		check(false, "a straight carrier to fire as a payload")
		return
	var casts: Array[Array] = []
	for form in forms:
		var cards: Array[StringName] = [form.id]
		if form.carries_payload():
			cards.append(payload.id)
		casts.append(cards)
	for card in others:
		var cards: Array[StringName] = [card.id, payload.id]
		if card is TriggerBase:
			cards.append(payload.id)
		casts.append(cards)
	check(casts.size() == forms.size() + others.size() and forms.size() > 5, "every card is cast (%d carriers, %d others)" % [forms.size(), others.size()])
	for cast: Array in casts:
		var cards: Array[StringName] = []
		cards.assign(cast)
		var world := CardWorld.new(root, shelf, staff)
		world.add_wizard(cards)
		world.add_ally(Vector2(-40.0, 40.0))
		var enemies: Array[Node2D] = [world.add_enemy(&"A", Vector2(90.0, 0.0)), world.add_enemy(&"B", Vector2(60.0, 30.0))]
		# An Array, not a PackedStringArray: a lambda holds a copy of a packed array.
		var problems: Array[String] = []
		for step in CARD_WALKS:
			world.at_step[step] = [func() -> void:
				for problem in _walk(_card_areas(world, enemies)):
					if not problems.has(problem) and not FIXTURE_CONTROLLERS.any(func(fixture: String) -> bool: return problem.begins_with(fixture)):
						problems.append(problem)]
		world.press(true)
		world.run(CARD_SECONDS, CARD_SECONDS)
		world.free_all()
		for problem in problems:
			check(false, "%s: %s" % [",".join(cards), problem])


## The scene (tests/core/sim_scenes.gd) played a few seconds, then walked.
func _check_scene(name: StringName) -> void:
	var scene := SimScenes.new(root, name)
	for i in STEPS:
		scene.step()
	for problem in _walk(scene.areas()):
		check(false, "%s: %s" % [name, problem])
	scene.free_all()


## The problems one walk of `areas` meets (it must reach some state).
func _walk(areas: Dictionary) -> PackedStringArray:
	var walk := StateWalk.new()
	var leaves: Array[int] = [0]
	for name: Variant in areas:
		walk.walk(String(name), areas[name] as Object, func(_path: String, _value: Variant) -> void: leaves[0] += 1)
	if leaves[0] == 0:
		walk.problems.append("the walk reached no state")
	return walk.problems


## A card world's areas: its services and every body still standing.
static func _card_areas(world: CardWorld, enemies: Array[Node2D]) -> Dictionary:
	var out: Dictionary = {"actors": world.table, "projectiles": world.projectiles, "spells": world.spells, "combat": world.combat, "entities": world.entities}
	if is_instance_valid(world.wizard):
		out["wizard"] = world.wizard
	for enemy in enemies:
		if is_instance_valid(enemy):
			out[String(enemy.name)] = enemy
	return out


## What a member typed by `info` holds that cannot be state, or "".
static func _cannot_hold(info: Dictionary, classes: Dictionary[String, String]) -> String:
	var type: int = info["type"]
	match type:
		TYPE_CALLABLE, TYPE_SIGNAL, TYPE_RID:
			return "a %s" % type_string(type)
		TYPE_OBJECT:
			return _cannot_be(String(info["class_name"]), classes)
		TYPE_ARRAY:
			if int(info["hint"]) == PROPERTY_HINT_ARRAY_TYPE:
				return _cannot_be(String(info["hint_string"]), classes)
		TYPE_DICTIONARY:
			if int(info["hint"]) == PROPERTY_HINT_DICTIONARY_TYPE:
				for part in String(info["hint_string"]).split(";"):
					var why: String = _cannot_be(part, classes)
					if not why.is_empty():
						return why
	return ""


## Why an object of class `name` (engine or global script class) cannot be state, or "".
static func _cannot_be(name: String, classes: Dictionary[String, String]) -> String:
	if name.is_empty():
		return ""
	if classes.has(name):
		var script: Script = load(classes[name]) as Script
		if not _is_node(script.get_instance_base_type()):
			return ""
		if not StateWalk.is_simulation(script):
			return "a node of %s, outside the simulation" % classes[name].get_file()
		if StateWalk.is_view_only(script):
			return "a view-only node (%s)" % classes[name].get_file()
		return ""
	if _is_node(StringName(name)):
		return "a %s" % name
	return ""


static func _is_node(native: StringName) -> bool:
	return ClassDB.class_exists(native) and (native == &"Node" or ClassDB.is_parent_class(native, &"Node"))


## Every simulation script, sorted, then its inner classes (an inner class has no path of its own:
## it is found among its file's constants), as {"name": "res://...gd" or "res://...gd::Inner",
## "script": the script}.
static func _simulation_scripts() -> Array[Dictionary]:
	var paths := PackedStringArray()
	for folder in StateWalk.FOLDERS:
		_collect(folder.trim_suffix("/"), paths)
	paths.sort()
	var out: Array[Dictionary] = []
	for path in paths:
		_add_with_inner(path, load(path) as Script, out)
	return out


static func _add_with_inner(name: String, script: Script, out: Array[Dictionary]) -> void:
	out.append({"name": name, "script": script})
	var constants: Dictionary = script.get_script_constant_map()
	for constant: String in constants:
		var value: Variant = constants[constant]
		if value is Script and (value as Script).resource_path.is_empty():
			_add_with_inner("%s::%s" % [name, constant], value as Script, out)


static func _collect(dir_path: String, out: PackedStringArray) -> void:
	for file in DirAccess.get_files_at(dir_path):
		if file.ends_with(".gd"):
			out.append(dir_path + "/" + file)
	for sub in DirAccess.get_directories_at(dir_path):
		_collect(dir_path + "/" + sub, out)


## A script's source ("" for an inner class: its lines are its file's, scanned with the file).
static func _source_of(script: Script) -> String:
	if script.resource_path.is_empty() or not script.resource_path.ends_with(".gd"):
		return ""
	return FileAccess.get_file_as_string(script.resource_path)


## The static members `script` and the scripts it extends declare (from their source; an inner
## class's are its file's).
static func _statics_of(script: Script) -> PackedStringArray:
	var out := PackedStringArray()
	var pattern := RegEx.create_from_string("^static var (\\w+)")
	var at: Script = script
	while at != null:
		for line in _source_of(at).split("\n"):
			var found: RegExMatch = pattern.search(line)
			if found != null:
				out.append(found.get_string(1))
		at = at.get_base_script()
	return out


## A line of GDScript without its comment (a `#` outside a string), and without its strings' text, so
## a doc line or a message that names `randf()` is not code that calls it.
static func _code_of(line: String) -> String:
	var out: String = ""
	var quote: String = ""
	var i: int = 0
	while i < line.length():
		var c: String = line[i]
		if quote.is_empty():
			if c == "#":
				break
			if c == "\"" or c == "'":
				quote = c
			out += c
		else:
			if c == "\\":
				i += 1
			elif c == quote:
				quote = ""
				out += c
		i += 1
	return out
