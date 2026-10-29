extends "res://tests/support/suite.gd"
## The Hold card (content/spells/modifiers/hold/, staffs C): the next carrier stays until its
## staff is cast again, and keeps its mana reserved while it does. Its combos hurt what they
## promise, outlive an unheld carrier, and end with the next cast.
##
## godot --headless --path . --script res://tests/content/spells/test_hold.gd

const ArenaScript := preload("res://tests/content/spells/combo_arena.gd")
const ComboFiles := preload("res://tests/support/combo_files.gd")

const COMBOS: Array[String] = ["hold_fire_orbit", "hold_shield_orbit"]
## Past an orbit's own lifetime (3 s).
const LONG: float = 4.0
## Just past an orbit's lifetime, where only a held shot is still alive.
const JUST_PAST: float = 3.5

## Shots alive at JUST_PAST in the last _play.
var _mid: int = 0


func _card() -> ModifierBase:
	return load("res://content/spells/modifiers/hold/hold.tres") as ModifierBase


func _combo(id: String) -> Dictionary:
	for combo: Dictionary in ComboFiles.read_all():
		if combo["id"] == id:
			return combo
	return {}


## Casts `combo` (without every copy of `drop`) and runs it for its seconds. Returns
## [shots still alive, whether the staff is holding, mana reserved for player 0] and, with
## `again`, casts the staff a second time and adds [shots, holding, reserved] after one more second.
func _play(combo: Dictionary, drop: String = "", again: bool = false) -> Array:
	var arena := ArenaScript.new(root)
	var reserved: Array[float] = [0.0]
	arena.bus.mana_reserved.connect(func(seat: int, amount: float) -> void:
		if seat == 0:
			reserved[0] = amount)
	for at: Array in combo["imps"]:
		arena.add_imp(Vector2(float(at[0]), float(at[1])))
	var entry: Dictionary = combo["casts"][0]
	var cards: Array = []
	for id: Variant in entry["cards"]:
		if str(id) != drop:
			cards.append(id)
	var staff: int = int(entry["staff"])
	arena.install_cards(0, staff, cards)
	arena.cast(0, staff)
	arena.run(JUST_PAST)
	_mid = arena.projectiles.get_count()
	arena.run(float(combo["seconds"]) - JUST_PAST)
	var result: Array = [arena.projectiles.get_count(), arena.spells.is_holding(0, staff), reserved[0]]
	if again:
		arena.cast(0, staff)
		arena.run(1.0)
		result.append_array([arena.projectiles.get_count(), arena.spells.is_holding(0, staff), reserved[0]])
	arena.free_all()
	return result


func test_the_card_is_a_valid_modifier() -> void:
	var card: ModifierBase = _card()
	check(card != null, "hold.tres loads as a ModifierBase")
	if card == null:
		return
	check_equal(card.id, &"hold", "its id is its folder")
	check_equal(card.kind(), &"modifier", "a modifier card")
	check_equal(card.behaviour, ModifierBase.Behaviour.HOLD, "the hold behaviour")
	check(card.behaviour_strength > 0.0, "with a strength")
	check_equal(card.look_layer, 12, "and glitters")
	check(card.range_problems().is_empty(), "inside every range: %s" % [card.range_problems()])


func test_the_combos_are_met_by_the_catalogue() -> void:
	for id: String in COMBOS:
		check(not _combo(id).is_empty(), "the combo %s exists" % id)


func test_the_carrier_outlives_its_lifetime_only_with_the_card() -> void:
	for id: String in COMBOS:
		var combo: Dictionary = _combo(id)
		if combo.is_empty():
			continue
		check(float(combo["seconds"]) >= LONG, "%s runs past an orbit's three seconds" % id)
		var held: Array = _play(combo)
		check(_mid > 0, "%s has a shot alive past the orbit's lifetime" % id)
		check((held[0] as int) > 0, "%s still has its shots after %s s" % [id, combo["seconds"]])
		check(held[1] as bool, "%s keeps the staff holding" % id)
		check((held[2] as float) > 0.0, "%s reserves mana (%s)" % [id, held[2]])
		var plain: Array = _play(combo, "hold")
		check_equal(_mid, 0, "%s has no shot past the orbit's lifetime without Hold" % id)
		check_equal(plain[0], 0, "%s has no shots left without Hold" % id)
		check(not (plain[1] as bool), "%s is not holding without Hold" % id)


func test_the_next_cast_switches_it_off_and_frees_the_mana() -> void:
	for id: String in COMBOS:
		var combo: Dictionary = _combo(id)
		if combo.is_empty():
			continue
		var result: Array = _play(combo, "", true)
		check_equal(result[3], 0, "%s: the next cast ends its shots" % id)
		check(not (result[4] as bool), "%s: and the staff holds nothing" % id)
		check_equal(result[5], 0.0, "%s: and the mana is free" % id)


func test_four_players_hold_each() -> void:
	var arena := ArenaScript.new(root)
	var reserved: Dictionary = {}
	arena.bus.mana_reserved.connect(func(seat: int, amount: float) -> void: reserved[seat] = amount)
	for player in 4:
		arena.place_caster(player, Vector2(0.0, 150.0 * player))
		arena.install_cards(player, 0, ["hold", "fire", "orbit"])
		check(arena.cast(player, 0), "player %d casts" % player)
	arena.run(LONG)
	for player in 4:
		check(arena.spells.is_holding(player, 0), "player %d is holding" % player)
		check(float(reserved.get(player, 0.0)) > 0.0, "player %d has mana reserved" % player)
	arena.free_all()
