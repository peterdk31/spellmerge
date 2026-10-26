extends "res://tests/support/suite.gd"
## The combo catalogue in content/spells/combos.json (M2 part 14): every named combo is built
## from the real components, cast in the test arena (`combo_arena.gd`: real registry, spell
## runtime, projectile manager and combat, with imps) and must do what it promises. One
## data-driven test per check kind runs over every combo, so a new row in the JSON is covered
## without a new test.
##
## A combo row: `id`, `name`, `does` (plain words), `casts` (slot, recipe, optional `at`
## seconds, `player`), `imps` ([x, y] from the caster at (0, 0), aiming along +x), `seconds`
## and `checks`. Check kinds: `damaged` (imps), `status` (imps, status), `status_count`
## (status, min), `keeps_burning` (imp), `reaction` (reaction), `max_shots` (max).
##
## godot --headless --path . --script res://tests/content/spells/test_combos.gd

const ArenaScript := preload("res://tests/content/spells/combo_arena.gd")
const CATALOGUE: String = "res://content/spells/combos.json"
const MIN_COMBOS: int = 20
## Every shipped component; each must be in at least two combos. A new component is added here
## together with its rows (the spells README, "The combo row rule").
const COMPONENTS: Array[String] = [
	"bolt", "beam", "nova", "rune", "orbit",
	"fire", "frost", "storm", "void", "lightning",
	"split", "pierce", "homing", "chain", "bigger", "faster",
	"on_hit", "on_expire", "timer",
]
const CHECK_KINDS: Array[String] = ["damaged", "status", "status_count", "keeps_burning", "reaction", "max_shots"]

var _combos: Array = []


func before_each() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CATALOGUE))
	_combos = []
	if parsed is Dictionary and (parsed as Dictionary).get("combos") is Array:
		_combos = (parsed as Dictionary)["combos"] as Array


## Builds the arena for `combo`, casts it as the row says and runs it. The caller frees it.
## With `quiet`, a recipe that does not build or a cast that is refused is not a failure (the
## control runs below drop a component on purpose).
func _play(combo: Dictionary, quiet: bool = false) -> ArenaScript:
	var arena := ArenaScript.new(root)
	for at: Array in combo.get("imps", []):
		arena.add_imp(Vector2(float(at[0]), float(at[1])))
	var casts: Array = (combo.get("casts", []) as Array).duplicate()
	for entry: Dictionary in casts:
		var built: CompiledSpell = arena.install(int(entry.get("player", 0)), int(entry["slot"]), entry["recipe"] as Dictionary)
		if not quiet:
			check(built.valid, "%s: the recipe builds: %s" % [combo["id"], built.reason])
	casts.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.get("at", 0.0)) < float(b.get("at", 0.0)))
	var seconds: float = float(combo.get("seconds", 1.0))
	for entry: Dictionary in casts:
		var at: float = float(entry.get("at", 0.0))
		if at > arena.time:
			arena.run(at - arena.time)
		var made: bool = arena.cast(int(entry.get("player", 0)), int(entry["slot"]))
		if not quiet:
			check(made, "%s: the cast in slot %d is made" % [combo["id"], int(entry["slot"])])
	arena.run(maxf(seconds - arena.time, 0.0))
	return arena


## Every combo's failures for one check, as text; empty when it holds.
func _problem_with(arena: ArenaScript, check_row: Dictionary) -> String:
	var kind: String = check_row["kind"]
	match kind:
		"damaged":
			for index: int in check_row["imps"]:
				if arena.lost(arena.imps[index]) <= 0:
					return "imp %d was not hurt" % index
		"status":
			for index: int in check_row["imps"]:
				if not arena.was_given(arena.imps[index], StringName(check_row["status"])):
					return "imp %d never got %s" % [index, check_row["status"]]
		"status_count":
			var count: int = 0
			for imp in arena.imps:
				if arena.was_given(imp, StringName(check_row["status"])):
					count += 1
			if count < int(check_row["min"]):
				return "%d imps got %s, wanted %d" % [count, check_row["status"], int(check_row["min"])]
		"keeps_burning":
			var imp: Node2D = arena.imps[int(check_row["imp"])]
			var at_hit: int = arena.lost_when_given(imp, &"burn")
			if at_hit < 0:
				return "the imp never burned"
			if arena.lost(imp) <= at_hit:
				return "the imp lost nothing after the hit (%d)" % at_hit
		"reaction":
			if not arena.reaction_ids().has(StringName(check_row["reaction"])):
				return "no %s reaction, saw %s" % [check_row["reaction"], arena.reaction_ids()]
		"max_shots":
			if arena.peak_shots > int(check_row["max"]):
				return "%d shots at once, over %d" % [arena.peak_shots, int(check_row["max"])]
		_:
			return "unknown check kind %s" % kind
	return ""


# --- The catalogue ----------------------------------------------------------

func test_the_catalogue_has_twenty_combos() -> void:
	check(_combos.size() >= MIN_COMBOS, "at least %d combos (got %d)" % [MIN_COMBOS, _combos.size()])


func test_every_component_is_in_two_combos() -> void:
	var uses: Dictionary = {}
	for combo: Dictionary in _combos:
		var in_combo: Dictionary = {}
		for entry: Dictionary in combo["casts"]:
			for id: StringName in _recipe_ids(entry["recipe"] as Dictionary):
				in_combo[id] = true
		for id: StringName in in_combo:
			uses[id] = int(uses.get(id, 0)) + 1
	for component: String in COMPONENTS:
		var count: int = int(uses.get(StringName(component), 0))
		check(count >= 2, "%s is in at least two combos (got %d)" % [component, count])


func test_the_component_list_is_every_spell_component() -> void:
	var arena := ArenaScript.new(root)
	var known: Array[String] = []
	for id: StringName in arena.registry.call("get_ids", &"spells"):
		known.append(String(id))
	for id: String in known:
		check(COMPONENTS.has(id), "%s is a component: add it to COMPONENTS with its two combos" % id)
	for id: String in COMPONENTS:
		check(known.has(id), "%s in COMPONENTS is in the registry" % id)
	arena.free_all()


func test_every_row_has_its_fields_and_an_unseen_id() -> void:
	var seen: Dictionary = {}
	for combo: Dictionary in _combos:
		var id: String = combo.get("id", "")
		check(id != "", "a combo has an id")
		check(not seen.has(id), "%s: the id is used once" % id)
		seen[id] = true
		check(str(combo.get("name", "")) != "", "%s has a name" % id)
		check(str(combo.get("does", "")) != "", "%s says what it does" % id)
		check((combo.get("casts", []) as Array).size() > 0, "%s has a cast" % id)
		check((combo.get("checks", []) as Array).size() > 0, "%s has a check" % id)
		for row: Dictionary in combo.get("checks", []):
			check(CHECK_KINDS.has(str(row.get("kind", ""))), "%s: check kind %s is known" % [id, row.get("kind")])


func test_every_recipe_compiles_within_the_budget() -> void:
	var arena := ArenaScript.new(root)
	for combo: Dictionary in _combos:
		for entry: Dictionary in combo["casts"]:
			var spell: CompiledSpell = arena.spells.compile(entry["recipe"] as Dictionary)
			check(spell.valid, "%s: %s" % [combo["id"], spell.reason])
			check(spell.complexity <= SpellLimits.MAX_COMPLEXITY, "%s: complexity %d is over the budget" % [combo["id"], spell.complexity])
	arena.free_all()


func test_the_recipe_ids_are_real_components() -> void:
	var arena := ArenaScript.new(root)
	var ids: Array[StringName] = []
	for combo: Dictionary in _combos:
		for entry: Dictionary in combo["casts"]:
			ids.append_array(_recipe_ids(entry["recipe"] as Dictionary))
	for id in ids:
		check(arena.registry.call("get_resource", &"spells", id) != null, "the registry knows %s" % id)
	arena.free_all()


func _recipe_ids(recipe: Dictionary) -> Array[StringName]:
	var ids: Array[StringName] = []
	for key in ["form", "element", "trigger"]:
		if recipe.has(key):
			ids.append(StringName(recipe[key]))
	for id: String in recipe.get("modifiers", []):
		ids.append(StringName(id))
	if recipe.has("held"):
		ids.append_array(_recipe_ids(recipe["held"] as Dictionary))
	return ids


# --- Each combo does what it promises ---------------------------------------

func test_every_combo_does_what_it_promises() -> void:
	for combo: Dictionary in _combos:
		var arena: ArenaScript = _play(combo)
		for row: Dictionary in combo["checks"]:
			var problem: String = _problem_with(arena, row)
			check(problem == "", "%s (%s): %s" % [combo["id"], combo["does"], problem])
		arena.free_all()


## Rows whose point is one component: with it dropped, some check of the row must fail.
const CONTROLS: Dictionary = {
	"storm_mine": "chain",
	"frost_carousel": "pierce",
	"quick_shock_ring": "faster",
	"seeking_frost_burst": "on_expire",
}


func _without(recipe: Dictionary, component: String) -> Dictionary:
	var out: Dictionary = recipe.duplicate(true)
	if out.get("trigger", "") == component:
		out.erase("trigger")
		out.erase("held")
	if out.has("modifiers"):
		(out["modifiers"] as Array).erase(component)
	if out.has("held"):
		out["held"] = _without(out["held"] as Dictionary, component)
	return out


func test_a_combo_row_fails_without_the_component_it_is_for() -> void:
	for combo: Dictionary in _combos:
		if not CONTROLS.has(combo["id"]):
			continue
		var plain: Dictionary = combo.duplicate(true)
		for entry: Dictionary in plain["casts"]:
			entry["recipe"] = _without(entry["recipe"] as Dictionary, CONTROLS[combo["id"]])
		var arena: ArenaScript = _play(plain, true)
		var failed: bool = false
		for row: Dictionary in combo["checks"]:
			failed = failed or _problem_with(arena, row) != ""
		check(failed, "%s: its checks fail without %s" % [combo["id"], CONTROLS[combo["id"]]])
		arena.free_all()
	for id: String in CONTROLS:
		var found: bool = false
		for combo: Dictionary in _combos:
			found = found or combo["id"] == id
		check(found, "the control row %s exists" % id)


func test_a_combo_check_that_fails_is_reported() -> void:
	# The checks themselves can fail: an imp no shot reaches is not hurt.
	var arena := ArenaScript.new(root)
	arena.add_imp(Vector2(100.0, 400.0))
	arena.install(0, 0, {"form": "bolt"})
	arena.cast(0, 0)
	arena.run(1.5)
	check(_problem_with(arena, {"kind": "damaged", "imps": [0]}) != "", "a missed imp fails the damaged check")
	check(_problem_with(arena, {"kind": "reaction", "reaction": "shatter"}) != "", "no reaction fails the reaction check")
	check(_problem_with(arena, {"kind": "frobnicate"}) != "", "an unknown check kind fails")
	arena.free_all()


func test_a_plain_fan_misses_what_the_homing_fan_reaches() -> void:
	var arena := ArenaScript.new(root)
	var up: Node2D = arena.add_imp(Vector2(110.0, -60.0))
	var down: Node2D = arena.add_imp(Vector2(110.0, 60.0))
	arena.install(0, 0, {"form": "bolt", "modifiers": ["split"]})
	check(arena.cast(0, 0), "the plain fan is cast")
	arena.run(1.5)
	check_equal(arena.lost(up) + arena.lost(down), 0, "without homing the fan flies past both imps")
	arena.free_all()


func test_two_players_cast_their_combos_at_the_same_time() -> void:
	var arena := ArenaScript.new(root)
	var left: Node2D = arena.add_imp(Vector2(-100.0, 0.0))
	var right: Node2D = arena.add_imp(Vector2(100.0, 0.0))
	arena.install(0, 0, {"form": "bolt", "element": "fire"})
	arena.install(1, 0, {"form": "bolt", "element": "frost"})
	check(arena.cast(0, 0, Vector2.RIGHT), "player 0 casts")
	check(arena.cast(1, 0, Vector2.LEFT), "player 1 casts")
	arena.run(1.0)
	check(arena.was_given(right, &"burn"), "player 0's fire reached the imp on the right")
	check(arena.was_given(left, &"chill"), "player 1's frost reached the imp on the left")
	check(not arena.was_given(left, &"burn") and not arena.was_given(right, &"chill"), "and nobody got the other player's element")
	arena.free_all()
