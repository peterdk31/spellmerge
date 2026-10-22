extends "res://tests/support/suite.gd"
## Tests for the wizard on the spell runtime (M2 part 11): the two prepared spells and `swap`,
## the bag, `build_change_requested` checked with `Spells.compile` and applied or refused
## (`spell_changed`, `build_refused`), casting through `Spells.cast`, the orbit anchor, and four
## players building at once. It runs the real `Spells`, projectile manager and event bus, with
## components built in code behind a stand-in registry.
##
## godot --headless --path . --script res://tests/gameplay/player/test_player_build.gd

const PlayerScript := preload("res://gameplay/player/player.gd")
const InputManagerScript := preload("res://core/input/input_manager.gd")
const EventsScript := preload("res://core/events/events.gd")
const RegistryScript := preload("res://core/registry/registry.gd")
const SpellsScript := preload("res://core/spells/spells.gd")
const ManagerScript := preload("res://core/projectiles/projectile_manager.gd")

const STEP: float = 0.0625
const BOLT: Dictionary = {"form": &"bolt"}


## A registry that knows only the components a test puts in it.
class FakeRegistry:
	extends RegistryScript
	var items: Dictionary = {}

	func get_ids(folder: StringName) -> Array[StringName]:
		var ids: Array[StringName] = []
		if folder == &"spells":
			for id: StringName in items:
				ids.append(id)
		return ids

	func get_resource(folder: StringName, id: StringName) -> Resource:
		return items.get(id) if folder == &"spells" else null


var _registry: FakeRegistry
var _bus: EventsScript
var _input: InputManagerScript
var _mgr: ManagerScript
var _spells: SpellsScript
var _players: Array[PlayerScript] = []
## Every spell_changed as [player, path, description].
var _changed: Array = []
## Every build_refused as [player, reason].
var _refused: Array = []
var _cast_forms: Array[StringName] = []


func before_each() -> void:
	_registry = own(FakeRegistry.new()) as FakeRegistry
	_bus = own(EventsScript.new()) as EventsScript
	_input = own(InputManagerScript.new()) as InputManagerScript
	_input.events = _bus
	_mgr = own(ManagerScript.new()) as ManagerScript
	_mgr.events = _bus
	_mgr.set_cap(512)
	_spells = own(SpellsScript.new()) as SpellsScript
	_spells.registry = _registry
	_spells.bind(_mgr, _bus)
	_players.clear()
	_changed.clear()
	_refused.clear()
	_cast_forms.clear()
	_bus.spell_changed.connect(func(player: int, path: PackedInt32Array, text: String) -> void: _changed.append([player, path, text]))
	_bus.build_refused.connect(func(player: int, reason: String) -> void: _refused.append([player, reason]))
	_bus.spell_cast.connect(func(_p: int, form: StringName, _o: Vector2, _d: Vector2) -> void: _cast_forms.append(form))
	_component(FormBase.new(), &"bolt")
	var nova := _component(FormBase.new(), &"nova") as FormBase
	nova.shots = 8
	nova.spread = 360.0
	var orbit := _component(FormBase.new(), &"orbit") as FormBase
	orbit.motion = FormBase.Motion.ORBIT
	orbit.orbit_radius = 30.0
	orbit.lifetime = 5.0
	var fire := _component(ElementBase.new(), &"fire") as ElementBase
	fire.status_id = &"burn"
	fire.status_duration = 3.0
	_component(ElementBase.new(), &"frost")
	var split := _component(ModifierBase.new(), &"split") as ModifierBase
	split.shot_mult = 2
	_component(ModifierBase.new(), &"bigger")
	var heavy := _component(ModifierBase.new(), &"heavy") as ModifierBase
	heavy.complexity = 5
	_component(TriggerBase.new(), &"on_hit")


func _component(component: SpellComponent, id: StringName) -> SpellComponent:
	component.id = id
	component.display_name = String(id).capitalize()
	if component is FormBase:
		(component as FormBase).mana_cost = 5.0
		(component as FormBase).speed = 200.0
	_registry.items[id] = component
	return component


## A wizard outside the tree for player `index`, with the start recipes and a real device.
func _wizard(index: int, a: Dictionary = BOLT, b: Dictionary = {}) -> PlayerScript:
	_input.add_virtual_device(index)
	var player := own(PlayerScript.new()) as PlayerScript
	player.index = index
	player.input = _input
	player.events = _bus
	player.registry = _registry
	player.projectiles = _mgr
	player.spells = _spells
	player.start_recipe_a = a
	player.start_recipe_b = b
	player._ready()
	_players.append(player)
	return player


func _build(player: int, path: Array[int], slot: int, id: StringName) -> void:
	_bus.build_change_requested.emit(player, PackedInt32Array(path), slot, id)


func test_the_bag_holds_every_component_in_the_registry() -> void:
	var player := _wizard(0)
	check_equal(player.bag.size(), _registry.items.size(), "the bag has every component")
	check(player.bag.has(&"bolt") and player.bag.has(&"on_hit"), "forms and triggers are in the bag")


func test_start_recipes_are_built_and_announced() -> void:
	var player := _wizard(0, {"form": &"bolt", "element": &"fire"}, BOLT)
	check(player.has_spell(), "spell A is built")
	check_equal(player.recipe_of(0), {"form": &"bolt", "element": &"fire"}, "recipe A")
	check_equal(player.recipe_of(1), BOLT, "recipe B")
	check_equal(_changed.size(), 2, "one spell_changed per start spell")
	check_equal(_changed[0][1], PackedInt32Array([0]), "the first is spell A")
	check_equal(_changed[1][1], PackedInt32Array([1]), "the second is spell B")
	check(String(_changed[0][2]) != "", "the description is not empty")
	check(_refused.is_empty(), "nothing was refused")


func test_a_wizard_without_recipes_has_no_spell() -> void:
	var player := _wizard(0, {}, {})
	check(not player.has_spell(), "no spell")
	check(not player.cast(), "and no cast")
	check(_changed.is_empty(), "nothing is announced")


func test_a_cast_spawns_shots_and_sends_the_form_id() -> void:
	var player := _wizard(0, {"form": &"nova"})
	check(player.cast(), "the cast fires")
	check_equal(_mgr.get_count(), 8, "the nova made its ring through the runtime")
	check_equal(_cast_forms, [&"nova"] as Array[StringName], "spell_cast names the form")
	check(player.mana < PlayerScript.MAX_MANA, "the cast took mana")


func test_swap_switches_the_active_spell_and_each_has_its_own_cooldown() -> void:
	var player := _wizard(0, {"form": &"nova"}, BOLT)
	check(player.cast(), "spell A casts")
	check(not player.cast(), "spell A is cooling down")
	_bus.spell_swap_requested.emit(0)
	check_equal(player.active_slot, 1, "the swap made B active")
	check(player.cast(), "spell B casts at once: its cooldown is its own")
	check_equal(_cast_forms, [&"nova", &"bolt"] as Array[StringName], "B is a bolt")
	_bus.spell_swap_requested.emit(0)
	check_equal(player.active_slot, 0, "swapping again goes back to A")


func test_swap_for_another_player_changes_nothing() -> void:
	var one := _wizard(0, BOLT, BOLT)
	var two := _wizard(1, BOLT, BOLT)
	_bus.spell_swap_requested.emit(1)
	check_equal(one.active_slot, 0, "player 0 stays on A")
	check_equal(two.active_slot, 1, "player 1 swapped")


func test_swap_needs_a_second_spell_and_a_standing_wizard() -> void:
	var player := _wizard(0, BOLT, {})
	check(not player.swap(), "no swap to an empty slot")
	check_equal(player.active_slot, 0, "still A")
	var other := _wizard(1, BOLT, BOLT)
	_bus.damage_dealt.emit(-1, other, 1000, Vector2.ZERO)
	check(not other.swap(), "a downed wizard does not swap")


func test_a_build_request_changes_the_spell_and_is_announced() -> void:
	var player := _wizard(0)
	_changed.clear()
	_build(0, [0], PlayerScript.SLOT_ELEMENT, &"fire")
	check_equal(player.recipe_of(0), {"form": &"bolt", "element": &"fire"}, "the element is in")
	check_equal(_changed.size(), 1, "one spell_changed")
	check_equal(_changed[0][0], 0, "for player 0")
	check_equal(_changed[0][1], PackedInt32Array([0]), "for spell A")
	check(String(_changed[0][2]).to_lower().contains("fire") or String(_changed[0][2]).to_lower().contains("burn"), "the description tells about the fire: " + String(_changed[0][2]))
	check(_refused.is_empty(), "nothing refused")


func test_modifiers_fill_in_order_and_clear() -> void:
	var player := _wizard(0)
	_build(0, [0], PlayerScript.SLOT_FIRST_MODIFIER, &"split")
	_build(0, [0], PlayerScript.SLOT_FIRST_MODIFIER + 1, &"bigger")
	check_equal(player.recipe_of(0).get("modifiers"), [&"split", &"bigger"], "two modifiers")
	_build(0, [0], PlayerScript.SLOT_FIRST_MODIFIER + 2, &"bigger")
	_build(0, [0], PlayerScript.SLOT_FIRST_MODIFIER + 1, &"")
	check_equal(player.recipe_of(0).get("modifiers"), [&"split", &"bigger"], "clearing the middle one closes the gap")
	_build(0, [0], PlayerScript.SLOT_FIRST_MODIFIER, &"")
	_build(0, [0], PlayerScript.SLOT_FIRST_MODIFIER, &"")
	check(not player.recipe_of(0).has("modifiers"), "no modifiers left")
	check(_refused.is_empty(), "nothing refused: " + str(_refused))


func test_a_trigger_holds_a_spell_through_a_path() -> void:
	var player := _wizard(0)
	_build(0, [0], PlayerScript.SLOT_TRIGGER, &"on_hit")
	_build(0, [0, 0], PlayerScript.SLOT_FORM, &"nova")
	_build(0, [0, 0], PlayerScript.SLOT_ELEMENT, &"frost")
	check_equal(player.recipe_of(0), {"form": &"bolt", "trigger": &"on_hit", "held": {"form": &"nova", "element": &"frost"}}, "the held spell is built")
	check(_refused.is_empty(), "nothing refused: " + str(_refused))
	check_equal(_changed[_changed.size() - 1][1], PackedInt32Array([0]), "a change below announces the prepared spell it belongs to")
	_build(0, [0], PlayerScript.SLOT_TRIGGER, &"")
	check_equal(player.recipe_of(0), BOLT, "clearing the trigger drops the held spell")


func test_a_refusal_says_why_and_changes_nothing() -> void:
	var player := _wizard(0)
	_changed.clear()
	_build(0, [0], PlayerScript.SLOT_FORM, &"")
	check_equal(_refused.size(), 1, "taking the form out is refused")
	check(String(_refused[0][1]).to_lower().contains("form"), "the reason names the form: " + str(_refused))
	check_equal(_refused[0][0], 0, "for player 0")
	check_equal(player.recipe_of(0), BOLT, "the spell is as it was")
	check(_changed.is_empty(), "and nothing was announced")
	check(player.has_spell(), "it can still cast")


func test_a_spell_over_the_budget_is_refused() -> void:
	var player := _wizard(0)
	_build(0, [0], PlayerScript.SLOT_FIRST_MODIFIER, &"heavy")
	_build(0, [0], PlayerScript.SLOT_FIRST_MODIFIER + 1, &"heavy")
	check(_refused.is_empty(), "two heavy modifiers fit: " + str(_refused))
	_build(0, [0], PlayerScript.SLOT_FIRST_MODIFIER + 2, &"heavy")
	check_equal(_refused.size(), 1, "the third goes over the complexity budget")
	check(String(_refused[0][1]).to_lower().contains("complex"), "the reason says too complex: " + str(_refused))
	check_equal(player.recipe_of(0).get("modifiers"), [&"heavy", &"heavy"], "the spell keeps its two")


func test_a_wrong_request_is_refused() -> void:
	var player := _wizard(0)
	_build(0, [0], PlayerScript.SLOT_ELEMENT, &"split")
	_build(0, [0], PlayerScript.SLOT_ELEMENT, &"no_such_component")
	_build(0, [0], 9, &"fire")
	_build(0, [0], -1, &"fire")
	_build(0, [2], PlayerScript.SLOT_ELEMENT, &"fire")
	_build(0, [], PlayerScript.SLOT_ELEMENT, &"fire")
	_build(0, [0, 1], PlayerScript.SLOT_FORM, &"nova")
	check_equal(_refused.size(), 7, "every one of the seven is refused: " + str(_refused))
	check_equal(player.recipe_of(0), BOLT, "the spell did not change")


func test_a_held_spell_without_a_trigger_is_refused() -> void:
	var player := _wizard(0)
	_build(0, [0, 0], PlayerScript.SLOT_FORM, &"nova")
	check_equal(_refused.size(), 1, "a held spell needs a trigger")
	check_equal(player.recipe_of(0), BOLT, "unchanged")


func test_a_component_outside_the_bag_is_refused() -> void:
	var player := _wizard(0)
	player.bag.erase(&"fire")
	_build(0, [0], PlayerScript.SLOT_ELEMENT, &"fire")
	check_equal(_refused.size(), 1, "the bag decides what a player may build with")
	check_equal(player.recipe_of(0), BOLT, "unchanged")


func test_a_request_for_another_player_is_ignored() -> void:
	var one := _wizard(0)
	var two := _wizard(1)
	_changed.clear()
	_build(1, [0], PlayerScript.SLOT_ELEMENT, &"frost")
	check_equal(one.recipe_of(0), BOLT, "player 0 is untouched")
	check_equal(two.recipe_of(0), {"form": &"bolt", "element": &"frost"}, "player 1 built")
	check_equal(_changed.size(), 1, "only player 1 announced")
	check_equal(_changed[0][0], 1, "as player 1")
	check(_refused.is_empty(), "and nobody refused")


func test_a_refusal_goes_only_to_the_asker() -> void:
	_wizard(0)
	_wizard(1)
	_build(2, [0], PlayerScript.SLOT_ELEMENT, &"fire")
	check(_refused.is_empty(), "a request for a player with no wizard is not answered by the others")
	_build(1, [0], PlayerScript.SLOT_FORM, &"")
	check_equal(_refused.size(), 1, "one refusal")
	check_equal(_refused[0][0], 1, "for player 1")


func test_four_players_build_different_spells_at_once() -> void:
	var elements: Array[StringName] = [&"fire", &"frost", &"", &"fire"]
	var forms: Array[StringName] = [&"bolt", &"bolt", &"nova", &"orbit"]
	for index in 4:
		_wizard(index, {"form": forms[index]})
	for index in 4:
		_build(index, [0], PlayerScript.SLOT_ELEMENT, elements[index])
		_build(index, [1], PlayerScript.SLOT_FORM, &"nova")
	check(_refused.is_empty(), "nothing refused: " + str(_refused))
	for index in 4:
		var recipe: Dictionary = _players[index].recipe_of(0)
		check_equal(recipe.get("form"), forms[index], "player %d keeps their form" % index)
		check_equal(recipe.get("element", &""), elements[index], "player %d has their element" % index)
		check_equal(_players[index].recipe_of(1), {"form": &"nova"}, "player %d built spell B" % index)
	for index in 4:
		check(_players[index].swap(), "player %d swaps" % index)
	check(_players[0].cast() and _players[1].cast() and _players[2].cast() and _players[3].cast(), "all four cast their B spell")
	check_equal(_mgr.get_count(), 32, "four rings of eight")


func test_a_rebuild_leaves_the_shots_in_the_air() -> void:
	var player := _wizard(0, {"form": &"nova"})
	check(player.cast(), "the cast fires")
	var before: int = _mgr.get_count()
	_build(0, [0], PlayerScript.SLOT_ELEMENT, &"fire")
	check_equal(_mgr.get_count(), before, "the shots already flying are not taken back")
	for i in 10:  # past the 0.5 s cooldown, which a rebuild does not reset
		_mgr.step(STEP)
		_spells.step(STEP)
	check(player.cast(), "the new build casts")


func test_the_orbit_anchor_follows_the_wizard_and_goes_when_it_falls() -> void:
	var player := _wizard(0, {"form": &"orbit"})
	player.global_position = Vector2(100.0, 80.0)
	player.step(STEP)
	check_equal(_mgr.get_anchor(0), Vector2(100.0, 80.0) + PlayerScript.ORBIT_ANCHOR_OFFSET, "the anchor sits on the body")
	check(player.cast(), "the orbit casts")
	check(_mgr.get_count() > 0, "the orbit made a shot")
	_bus.damage_dealt.emit(-1, player, 1000, Vector2.ZERO)
	player.step(STEP)
	check(not _mgr.get_anchor(0).is_finite(), "a downed wizard has no anchor")
	check_equal(_mgr.get_anchor(1), Vector2.INF, "and the others never had one")


func test_leaving_the_tree_clears_the_anchor_and_stops_listening() -> void:
	var player := _wizard(0)
	root.add_child(player)
	player.step(STEP)
	check(_mgr.get_anchor(0).is_finite(), "the anchor is set")
	root.remove_child(player)
	check(not _mgr.get_anchor(0).is_finite(), "leaving the tree clears the anchor")
	_changed.clear()
	_build(0, [0], PlayerScript.SLOT_ELEMENT, &"fire")
	check(_changed.is_empty() and _refused.is_empty(), "a wizard that left no longer answers build requests")
