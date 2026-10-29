extends "res://tests/support/suite.gd"
## The Decoy card (content/spells/forms/decoy/, staffs C): a still copy of the wizard that
## enemies target. The engine side is tested in `tests/core/test_spells_payload_carriers.gd` and
## `tests/gameplay/ai/test_entities.gd`; here the card's data and the entity it asks for. The
## combo arena has no `ai`, so its combos only check what the wizard's other staffs do beside it.
##
## godot --headless --path . --script res://tests/content/spells/test_decoy.gd

const ArenaScript := preload("res://tests/content/spells/combo_arena.gd")
const ComboFiles := preload("res://tests/support/combo_files.gd")

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
