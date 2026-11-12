extends "res://tests/support/suite.gd"
## The state of running games walks without a problem (online-ready N1, core/sim/README.md, "State
## by default"): what the static checks of tests/core/test_state_declared.gd cannot see from the
## types (an untyped member, what an array or a dictionary holds, a service typed as a simulation
## script) shows when the state is walked. A problem is a reference to a node it does not own, an
## engine object, a Callable or an object key, named by its path with the fix.
##
## - The determinism tests' scenes (tests/core/sim_scenes.gd: a staffed fight, a spell storm),
##   walked after two seconds.
## - Every card of content/spells, cast in the card rules' world (tests/support/card_rules_world.gd)
##   and walked as it casts, flies and lands. New cards and carriers are walked the day they land,
##   with no edit here.
## - An area hashed by parts (BY_ACTOR) is asked whether its parts still stand (`actor_part_problems`) at
##   every walk.

const SimScenes := preload("res://tests/core/sim_scenes.gd")
const CardWorld := preload("res://tests/support/card_rules_world.gd")
const ActorFixture := preload("res://tests/gameplay/actor/actor_fixture.gd")
const RegistryScript := preload("res://core/registry/registry.gd")

const STEPS: int = 120
## The steps each card's world is walked at: as it casts, in flight, as it lands and after.
const CARD_WALKS: Array[int] = [1, 12, 40, 75]
## How long each card's world runs (seconds); the wizard keeps casting, so channels, repeats and
## held carriers are live at every walk.
const CARD_SECONDS: float = 1.4


func test_a_staffed_fight_walks_without_problems() -> void:
	_check_scene(&"fight")


func test_a_spell_storm_walks_without_problems() -> void:
	_check_scene(&"storm")


## Every card of content/spells, cast alone (a carrier) or on
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
	staff.cooldown = 0.0
	var carrier_cards: Array[CarrierCard] = []
	var others: Array[SpellComponent] = []
	var payload: CarrierCard = null
	for card: Resource in registry.call("get_all", &"spells"):
		if card is CarrierCard:
			var carrier_card: CarrierCard = card
			carrier_cards.append(carrier_card)
			if carrier_card.carrier == &"atom" and (payload == null or carrier_card.shots > payload.shots):
				payload = carrier_card
		elif card is SpellComponent:
			others.append(card as SpellComponent)
	if payload == null:
		check(false, "a straight carrier to fire as a payload")
		return
	var casts: Array[Array] = []
	for carrier_card in carrier_cards:
		casts.append([carrier_card.id] as Array[StringName])
	for card in others:
		var cards: Array[StringName] = [card.id, payload.id]
		if card is TriggerBase:
			cards.append(payload.id)
		casts.append(cards)
	check(casts.size() == carrier_cards.size() + others.size() and carrier_cards.size() > 5, "every card is cast (%d carriers, %d others)" % [carrier_cards.size(), others.size()])
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
					if not problems.has(problem):
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
	_check_hash_modes(name, scene.areas())
	scene.free_all()


## The hash's two walks agree on every area (core/sim/sim_hash.gd): the quick one (no paths, the
## values appended by the walk itself, its short ways: plain members, packed arrays, idle rows, spare
## pools) and the desync report's (paths, every leaf handed over).
func _check_hash_modes(scene: StringName, named: Dictionary) -> void:
	# An area with parts as its parts (Spells' casters, props W3), as the hash takes them.
	var areas: Dictionary = SimHash.split_by_actor(named)
	for name: Variant in areas:
		var quick := StateWalk.new()
		quick.with_paths = false
		var report := StateWalk.new()
		var leaves: Array[int] = [0]
		var a: int = SimHash.area(quick, String(name), areas[name] as Object)
		var b: int = SimHash.area(report, String(name), areas[name] as Object, func(_path: String, _value: Variant) -> void: leaves[0] += 1)
		check(a == b and leaves[0] > 0, "%s: %s hashes the same with paths and without" % [scene, name])


## The problems one walk of `areas` meets (it must reach some state).
func _walk(areas: Dictionary) -> PackedStringArray:
	var walk := StateWalk.new()
	# A FROZEN object (a compiled build) must not have changed since it was made.
	walk.verify_frozen = true
	# The card world's bodies are driven by the fixture's scripted controller, which stands in for a
	# player's (a simulation script): walked as one.
	walk.also_simulation = [ActorFixture.Scripted]
	var leaves: Array[int] = [0]
	for name: Variant in areas:
		walk.walk(String(name), areas[name] as Object, func(_path: String, _value: Variant) -> void: leaves[0] += 1)
	if leaves[0] == 0:
		walk.problems.append("the walk reached no state")
	# An area hashed by parts checks what its parts stand on (BY_ACTOR, props W3: Spells' resting
	# casters skip their tables), so a writer that breaks it is named here, card by card.
	for name: Variant in areas:
		var area: Object = areas[name]
		if is_instance_valid(area) and StateWalk.has_by_actor(area.get_script() as Script):
			for problem: String in area.call(&"actor_part_problems"):
				walk.problems.append("%s parts: %s" % [name, problem])
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
