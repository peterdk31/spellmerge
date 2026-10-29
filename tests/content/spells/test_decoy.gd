extends "res://tests/support/suite.gd"
## The Decoy card (content/spells/forms/decoy/, staffs C): a still copy of the wizard that
## enemies target. The engine side is tested in `tests/core/test_spells_payload_carriers.gd` and
## `tests/gameplay/ai/test_entities.gd`; here the card's data and the entity it asks for. The
## combo arena has no `ai`, so its combos only check what the wizard's other staffs do beside it.
##
## godot --headless --path . --script res://tests/content/spells/test_decoy.gd

const ArenaScript := preload("res://tests/content/spells/combo_arena.gd")
const ComboFiles := preload("res://tests/support/combo_files.gd")
const World := preload("res://tests/support/card_rules_world.gd")
const RegistryScript := preload("res://core/registry/registry.gd")

const COMBOS: Array[String] = ["decoy_and_fire", "decoy_frost_cover"]


func _card() -> FormBase:
	return load("res://content/spells/forms/decoy/decoy.tres") as FormBase


func _combo(id: String) -> Dictionary:
	for combo: Dictionary in ComboFiles.read_all():
		if combo["id"] == id:
			return combo
	return {}


## Casts `cards` from `seat` and returns every entity asked for as [actor, kind, position, seconds].
func _spawns(cards: Array, seat: int = 0) -> Array:
	var arena := ArenaScript.new(root)
	var spawns: Array = []
	arena.bus.entity_spawn_requested.connect(func(actor: int, kind: StringName, at: Vector2, seconds: float, _tag: int, _caster: int) -> void:
		spawns.append([actor, kind, at, seconds]))
	arena.place_caster(seat, Vector2(40, 20))
	arena.install_cards(seat, 0, cards)
	arena.cast(seat, 0)
	arena.run(0.5)
	arena.free_all()
	return spawns


func test_the_card_is_a_valid_carrier() -> void:
	var card: FormBase = _card()
	check(card != null, "decoy.tres loads as a FormBase")
	if card == null:
		return
	check_equal(card.id, &"decoy", "its id is its folder")
	check_equal(card.kind(), &"form", "a carrier card")
	check_equal(card.motion, FormBase.Motion.DECOY, "it is a decoy")
	check(card.lifetime > 0.0, "it lasts a while")
	check(card.range_problems().is_empty(), "inside every range: %s" % [card.range_problems()])


func test_the_combos_exist() -> void:
	for id: String in COMBOS:
		check(not _combo(id).is_empty(), "the combo %s exists" % id)


func test_a_cast_asks_for_one_decoy_where_the_caster_stands() -> void:
	var spawns: Array = _spawns(["decoy"])
	check_equal(spawns.size(), 1, "one decoy")
	if spawns.is_empty():
		return
	check_equal(spawns[0][1], &"decoy", "a decoy, not a familiar")
	var at: Vector2 = spawns[0][2]
	check(at.distance_to(Vector2(40, 20)) < 1.0, "at the caster's feet (%s)" % [at])
	check_equal(spawns[0][3], _card().lifetime, "for the card's lifetime")


func test_a_cast_without_the_card_asks_for_none() -> void:
	check(_spawns(["fire", "bolt"]).is_empty(), "a bolt leaves no decoy")


func test_four_players_leave_their_own() -> void:
	for seat in 4:
		var spawns: Array = _spawns(["decoy"], seat)
		check_equal(spawns.size(), 1, "player %d leaves one decoy" % seat)
		if not spawns.is_empty():
			check_equal(spawns[0][0], seat, "player %d: the decoy is theirs" % seat)


## Casts `cards` once while an enemy past the aim shoots bolts at the wizard all along, and counts
## the wizard's blocks and deflects by the decoy's card (its node), and the payloads fired.
func _guarded(cards: Array[StringName]) -> Dictionary:
	var registry: Node = own(RegistryScript.new()) as Node
	registry.call("scan")
	var shelf := own(World.Shelf.new()) as World.Shelf
	shelf.base = registry
	var staff := StaffBase.new()
	staff.id = &"decoy_guard"
	staff.slots = 16
	staff.cast_delay = 0.0
	staff.recharge = 0.0
	var world := World.new(root, shelf, staff)
	var wizard: Actor = world.add_wizard(cards)
	world.add_enemy(&"E", Vector2(140.0, 0.0), World.HEALTH, [&"bolt"], Vector2.LEFT, true)
	var got: Dictionary = {"blocked": 0, "deflected": 0, "fired": 0}
	var me: int = wizard.caster_number()
	world.bus.shot_blocked.connect(func(caster: int, _at: Vector2, tag: int) -> void:
		if caster == me and SpellTag.node_of(tag) == 0:
			got["blocked"] += 1)
	world.bus.shot_deflected.connect(func(caster: int, _at: Vector2, tag: int) -> void:
		if caster == me and SpellTag.node_of(tag) == 0:
			got["deflected"] += 1)
	world.press()
	world.run(2.0, 2.0)
	got["fired"] = world.spells.fires_made
	world.free_all()
	return got


func test_a_shielded_decoy_blocks_shots_that_touch_it() -> void:
	# Rules R4g: a shield on a decoy stops the other teams' shots at it, one charge each.
	check_equal(_guarded([&"decoy"])["blocked"], 0, "a plain decoy blocks nothing")
	var shield: ModifierBase = load("res://content/spells/modifiers/shield/shield.tres") as ModifierBase
	var got: Dictionary = _guarded([&"shield", &"decoy"])
	check_equal(got["blocked"], roundi(shield.behaviour_strength), "a shielded one blocks as many as its charges")


func test_a_deflecting_decoy_turns_shots_away() -> void:
	var got: Dictionary = _guarded([&"deflect", &"decoy"])
	check(got["deflected"] > 1, "it turns every shot that reaches it (%d)" % got["deflected"])
	check_equal(got["blocked"], 0, "and stops none")


func test_on_block_fires_from_a_decoy() -> void:
	var got: Dictionary = _guarded([&"on_block", &"shield", &"decoy", &"bolt"])
	check(got["blocked"] > 0, "it blocks")
	check_equal(got["fired"], got["blocked"], "and each block fires its payload")
