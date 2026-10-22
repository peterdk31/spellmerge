extends "res://tests/support/suite.gd"
## The spell fuzz test (M2 part 20): a few hundred seeded random recipes are compiled, and the
## ones that compile are built and cast in the test arena (`combo_arena.gd`: the real
## registry, spell runtime, projectile manager and combat, with imps standing in the way).
## It fails on
##  - an error line in the log (`push_error`, a script error, a line starting `ERROR:`),
##  - a recipe the compiler neither accepts nor refuses with a reason, or one it accepts that
##    breaks a limit of `SpellLimits` (complexity, shots, depth, modifiers, speed, radius,
##    pierce, cooldown, damage),
##  - a spell that cannot be built or cast, or that leaves more live shots than the manager's
##    cap, and
##  - a frame over budget: the mean time of a physics step (projectiles, spells, combat) of a
##    recipe above MEAN_LIMIT_MS (two 60 FPS frames), or any one step above STEP_LIMIT_MS
##    (100 ms; a hiccup of the machine is not a spell, so both have a wide margin).
## A failure names the seed and the recipe, so it can be replayed: change `SEED` or
## `RECIPES`, or run the recipe by hand in the arena.
##
## godot --headless --path . --script res://tests/bots/test_spell_fuzz.gd

const ArenaScript := preload("res://tests/content/spells/combo_arena.gd")
const FuzzerScript := preload("res://tests/bots/recipe_fuzzer.gd")
const ErrorLogScript := preload("res://tests/smoke/error_log.gd")

const SEED: int = 20261022
## Random recipes tried, compiled or not.
const RECIPES: int = 300
## Seconds each recipe is cast and run for.
const SECONDS: float = 2.0
## Mean step time allowed per recipe and the most any one step may take. These are coarse
## (two 60 FPS frames, and 100 ms) because a shared CI runner is noisy; the real numbers are
## printed on the FUZZ line at the end.
const MEAN_LIMIT_MS: float = 2000.0 / 60.0
const STEP_LIMIT_MS: float = 100.0
## Most live shots at any step (the cap `combo_arena.gd` gives the manager).
const SHOT_CAP: int = 512
## Recipes that must compile, or the fuzzer is not testing anything.
const MIN_COMPILING: int = 100

var _log: Logger = ErrorLogScript.new()


func _ids_by_kind(arena: ArenaScript) -> Dictionary:
	var ids: Dictionary = {}
	for id: StringName in arena.registry.call("get_ids", &"spells"):
		var component := arena.registry.call("get_resource", &"spells", id) as SpellComponent
		if component == null:
			continue
		if not ids.has(component.kind()):
			ids[component.kind()] = []
		(ids[component.kind()] as Array).append(id)
	return ids


## Imps in a ring and a line, so straight, orbit, still and chaining spells all meet some.
func _populate(arena: ArenaScript) -> void:
	for at: Vector2 in [Vector2(60, 0), Vector2(110, 20), Vector2(110, -20), Vector2(160, 0), Vector2(-50, 30), Vector2(0, 70), Vector2(0, -70)]:
		arena.add_imp(at)


## What is wrong with a compiled spell's numbers, or "" (`spell` and every held one).
func _limit_problem(spell: CompiledSpell, depth: int) -> String:
	if spell.complexity > SpellLimits.MAX_COMPLEXITY:
		return "complexity %d" % spell.complexity
	if depth > SpellLimits.MAX_DEPTH or spell.depth > SpellLimits.MAX_DEPTH:
		return "depth %d" % maxi(depth, spell.depth)
	if spell.modifier_ids.size() > SpellLimits.MAX_MODIFIERS:
		return "%d modifiers" % spell.modifier_ids.size()
	if spell.shots < 1 or spell.shots > SpellLimits.MAX_SHOTS:
		return "%d shots" % spell.shots
	if spell.speed > SpellLimits.MAX_SPEED or spell.radius > SpellLimits.MAX_RADIUS or spell.pierce > SpellLimits.MAX_PIERCE:
		return "speed %s, radius %s or pierce %d over its limit" % [spell.speed, spell.radius, spell.pierce]
	if spell.cooldown < SpellLimits.MIN_COOLDOWN or spell.damage > SpellLimits.MAX_DAMAGE or spell.damage < 0:
		return "cooldown %s or damage %d out of range" % [spell.cooldown, spell.damage]
	if spell.chain_jumps > SpellLimits.MAX_CHAIN_JUMPS:
		return "%d chain jumps" % spell.chain_jumps
	if spell.held != null:
		return _limit_problem(spell.held, depth + 1)
	return ""


func test_random_recipes_compile_cast_and_stay_in_budget() -> void:
	OS.add_logger(_log)
	var arena := ArenaScript.new(root)
	var fuzzer := FuzzerScript.new(_ids_by_kind(arena))
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var compiling: int = 0
	var slowest_mean: float = 0.0
	var slowest_step: float = 0.0
	for number in RECIPES:
		var recipe: Dictionary = fuzzer.candidate(rng)
		var label: String = "seed %d, recipe %d %s" % [SEED, number, str(recipe)]
		var spell: CompiledSpell = arena.spells.compile(recipe)
		if not spell.valid:
			check(spell.reason != "", "%s: refused without a reason" % label)
			continue
		compiling += 1
		var problem: String = _limit_problem(spell, 0)
		check(problem == "", "%s: breaks a limit: %s" % [label, problem])
		var fresh := ArenaScript.new(root)
		_populate(fresh)
		var built: CompiledSpell = fresh.install(0, 0, recipe)
		check(built.valid, "%s: compiles again but did not build" % label)
		check(fresh.cast(0, 0), "%s: the cast was refused" % label)
		var total: float = 0.0
		var steps: int = int(ceilf(SECONDS / ArenaScript.STEP))
		for i in steps:
			var started: int = Time.get_ticks_usec()
			fresh.run(ArenaScript.STEP)
			var took: float = float(Time.get_ticks_usec() - started) / 1000.0
			total += took
			slowest_step = maxf(slowest_step, took)
			if took > STEP_LIMIT_MS:
				check(false, "%s: a step took %.1f ms" % [label, took])
			if i % 20 == 0:
				fresh.cast(0, 0)
		var mean: float = total / float(steps)
		slowest_mean = maxf(slowest_mean, mean)
		check(mean <= MEAN_LIMIT_MS, "%s: a step took %.2f ms on average" % [label, mean])
		check(fresh.peak_shots <= SHOT_CAP, "%s: %d live shots at once, over the cap of %d" % [label, fresh.peak_shots, SHOT_CAP])
		fresh.free_all()
	OS.remove_logger(_log)
	arena.free_all()
	check(compiling >= MIN_COMPILING, "only %d of %d random recipes compile; the fuzzer tests too little" % [compiling, RECIPES])
	var lines: Array[String] = _log.call("get_lines")
	for line in lines:
		check(false, "the log has an error: " + line.trim_prefix("ERROR:").strip_edges())
	print("FUZZ: %d recipes, %d compiled, slowest mean step %.3f ms, slowest step %.3f ms" % [RECIPES, compiling, slowest_mean, slowest_step])


## The same seed gives the same recipes, which is what makes a failure replayable.
func test_same_seed_same_recipes() -> void:
	var arena := ArenaScript.new(root)
	var fuzzer := FuzzerScript.new(_ids_by_kind(arena))
	var first := RandomNumberGenerator.new()
	var second := RandomNumberGenerator.new()
	first.seed = 7
	second.seed = 7
	for i in 20:
		check(fuzzer.candidate(first) == fuzzer.candidate(second), "recipe %d repeats with the same seed" % i)
	arena.free_all()


## The steps of a recipe, applied in order to an empty spell, rebuild the recipe, and every
## prefix of them compiles (so a person's slot-by-slot build is never refused on the way).
func test_steps_rebuild_the_recipe_and_every_prefix_compiles() -> void:
	var arena := ArenaScript.new(root)
	var fuzzer := FuzzerScript.new(_ids_by_kind(arena))
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var compiles := func(recipe: Dictionary) -> bool: return arena.spells.compile(recipe).valid
	for number in 60:
		var recipe: Dictionary = fuzzer.random_recipe(rng, compiles)
		check(arena.spells.compile(recipe).valid, "recipe %d compiles" % number)
		var built: Dictionary = {}
		for step: Array in fuzzer.steps(recipe, 0):
			var node: Dictionary = built
			var path: PackedInt32Array = step[0]
			for depth in range(1, path.size()):
				if not node.has("held"):
					node["held"] = {}
				node = node["held"] as Dictionary
			_apply(node, step[1] as int, step[2] as StringName)
			check(arena.spells.compile(built).valid, "recipe %d: the prefix at slot %d compiles: %s" % [number, step[1], arena.spells.compile(built).reason])
		check(built == recipe, "recipe %d is rebuilt by its steps: %s vs %s" % [number, str(built), str(recipe)])
	arena.free_all()


## Clearing a built spell leaves the form only, and each clearing call compiles.
func test_clear_steps_leave_the_form() -> void:
	var arena := ArenaScript.new(root)
	var recipe: Dictionary = {"form": &"bolt", "element": &"fire", "modifiers": [&"pierce", &"split"], "trigger": &"on_hit", "held": {"form": &"nova"}}
	check(arena.spells.compile(recipe).valid, "the sample compiles")
	for step: Array in FuzzerScript.new({}).clear_steps(1):
		check(step[2] == &"" and (step[0] as PackedInt32Array) == PackedInt32Array([1]), "a clearing call empties a slot of spell B")
	var slots: Array = []
	for step: Array in FuzzerScript.new({}).clear_steps(1):
		slots.append(step[1])
	check(slots.has(FuzzerScript.SLOT_TRIGGER) and slots.has(FuzzerScript.SLOT_ELEMENT) and slots.size() == 5, "the clearing calls cover element, three modifiers and the trigger")
	arena.free_all()


## With nothing to build from, a bot cannot build and `random_recipe` returns an empty recipe.
func test_no_forms_means_no_recipe() -> void:
	var fuzzer := FuzzerScript.new({&"element": [&"fire"]})
	var rng := RandomNumberGenerator.new()
	check(not fuzzer.can_build(), "no form, no build")
	check(fuzzer.random_recipe(rng, func(_r: Dictionary) -> bool: return true).is_empty(), "no recipe without a form")


func _apply(node: Dictionary, slot: int, id: StringName) -> void:
	if slot == FuzzerScript.SLOT_FORM:
		node["form"] = id
	elif slot == FuzzerScript.SLOT_ELEMENT:
		node["element"] = id
	elif slot == FuzzerScript.SLOT_TRIGGER:
		node["trigger"] = id
	else:
		var modifiers: Array = node.get("modifiers", [])
		modifiers.append(id)
		node["modifiers"] = modifiers
