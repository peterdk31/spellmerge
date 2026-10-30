extends "res://tests/support/suite.gd"
## The Familiar card (content/spells/forms/familiar/, staffs C): a small helper that circles the
## caster and casts its payload at the nearest enemy. The engine side is tested in
## `tests/core/test_spells_payload_carriers.gd` and `tests/gameplay/ai/test_entities.gd`; here the
## card's data and the entity it asks for. The combo arena has no `ai`, so its combos only check
## the cast asks for a familiar and what the wizard's other staffs do beside it.
##
## godot --headless --path . --script res://tests/content/spells/test_familiar.gd

const ArenaScript := preload("res://tests/content/spells/combo_arena.gd")
const ComboFiles := preload("res://tests/support/combo_files.gd")

const COMBOS: Array[String] = ["familiar_bolt", "familiar_and_frost"]


func _card() -> FormBase:
	return load("res://content/spells/forms/familiar/familiar.tres") as FormBase


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
	check(card != null, "familiar.tres loads as a FormBase")
	if card == null:
		return
	check_equal(card.id, &"familiar", "its id is its folder")
	check_equal(card.kind(), &"form", "a carrier card")
	check_equal(card.carrier, &"familiar", "it is a familiar")
	check(not card.carries_payload(), "it has no payload of its own: it casts what its triggers give it (rules R4 F3)")
	check(card.lifetime > 0.0, "it lasts a while")
	check(card.range_problems().is_empty(), "inside every range: %s" % [card.range_problems()])


func test_the_combos_exist() -> void:
	for id: String in COMBOS:
		check(not _combo(id).is_empty(), "the combo %s exists" % id)


func test_a_cast_asks_for_one_familiar_at_the_caster() -> void:
	var spawns: Array = _spawns(["familiar", "bolt"])
	check_equal(spawns.size(), 1, "one familiar")
	if spawns.is_empty():
		return
	check_equal(spawns[0][1], &"familiar", "a familiar, not a decoy")
	var at: Vector2 = spawns[0][2]
	check(at.distance_to(Vector2(40, 20)) < 40.0, "near the caster (%s)" % [at])
	check_equal(_card().lifetime, 8.0, "the card lasts eight seconds")
	check_equal(spawns[0][3], 8.0, "and the familiar is asked for that long")


func test_a_cast_without_the_card_asks_for_none() -> void:
	check(_spawns(["fire", "bolt"]).is_empty(), "a bolt sends no familiar")


func test_four_players_send_their_own() -> void:
	for seat in 4:
		var spawns: Array = _spawns(["familiar", "bolt"], seat)
		check_equal(spawns.size(), 1, "player %d sends one familiar" % seat)
		if not spawns.is_empty():
			check_equal(spawns[0][0], seat, "player %d: the familiar is theirs" % seat)
