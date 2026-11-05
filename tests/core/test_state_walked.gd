extends "res://tests/support/suite.gd"
## The state of running games walks without a problem (online-ready N1, core/sim/README.md, "State
## by default"): what the static checks of tests/core/test_state_declared.gd cannot see from the
## types (an untyped member, what an array or a dictionary holds, a service typed as a simulation
## script) shows when the state is walked. A problem is a reference to a node it does not own, an
## engine object, a Callable or an object key, named by its path with the fix.
##
## - The determinism tests' scenes (tests/core/sim_scenes.gd: a staffed fight, a spell storm, a horde
##   wave), walked after two seconds.
## - Every card of content/spells, cast in the card rules' world (tests/support/card_rules_world.gd)
##   and walked as it casts, flies and lands. New cards and carriers are walked the day they land,
##   with no edit here.

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
	scene.free_all()


## The problems one walk of `areas` meets (it must reach some state).
func _walk(areas: Dictionary) -> PackedStringArray:
	var walk := StateWalk.new()
	# The card world's bodies are driven by the fixture's scripted controller, which stands in for a
	# player's (a simulation script): walked as one.
	walk.also_simulation = [ActorFixture.Scripted]
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
