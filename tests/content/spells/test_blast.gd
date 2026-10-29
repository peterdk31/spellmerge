extends "res://tests/support/suite.gd"
## The Blast card (content/spells/modifiers/blast/, staffs C): the next carrier bursts at its end
## point and hurts everything in the circle, the caster too. Each of its combos does what it
## promises with the card and fails without it.
##
## godot --headless --path . --script res://tests/content/spells/test_blast.gd

const ArenaScript := preload("res://tests/content/spells/combo_arena.gd")
const ComboFiles := preload("res://tests/support/combo_files.gd")

const COMBOS: Array[String] = ["blast_rocket", "blast_wall_burst"]


func _card() -> ModifierBase:
	return load("res://content/spells/modifiers/blast/blast.tres") as ModifierBase


func _combo(id: String) -> Dictionary:
	for combo: Dictionary in ComboFiles.read_all():
		if combo["id"] == id:
			return combo
	return {}


## Plays `combo` without `drop`; returns each imp's lost health.
func _lost(combo: Dictionary, drop: String = "") -> Array[int]:
	var arena := ArenaScript.new(root)
	for at: Array in combo["imps"]:
		arena.add_imp(Vector2(float(at[0]), float(at[1])))
	for rect: Array in combo.get("walls", []):
		arena.add_wall(Rect2(float(rect[0]), float(rect[1]), float(rect[2]), float(rect[3])))
	var entry: Dictionary = combo["casts"][0]
	var cards: Array = []
	for id: Variant in entry["cards"]:
		if str(id) != drop:
			cards.append(id)
	arena.install_cards(0, int(entry["staff"]), cards)
	arena.cast(0, int(entry["staff"]))
	arena.run(float(combo["seconds"]))
	var out: Array[int] = []
	for imp in arena.imps:
		out.append(arena.lost(imp))
	arena.free_all()
	return out


func test_the_card_is_a_valid_modifier() -> void:
	var card: ModifierBase = _card()
	check(card != null, "blast.tres loads as a ModifierBase")
	if card == null:
		return
	check_equal(card.id, &"blast", "its id is its folder")
	check_equal(card.behaviour, ModifierBase.Behaviour.BLAST, "the blast behaviour")
	check(card.behaviour_strength > 0.0, "it has a radius")
	check(card.range_problems().is_empty(), "inside every range: %s" % [card.range_problems()])


func test_a_blast_bolt_carries_the_radius() -> void:
	var arena := ArenaScript.new(root)
	var staff: CompiledStaff = arena.install_cards(0, 0, ["blast", "bolt"])
	var spell: CompiledSpell = staff.casts[0].group.spells[0]
	check_equal(spell.behaviour(ModifierBase.Behaviour.BLAST), _card().behaviour_strength, "the card's radius")
	arena.free_all()


func test_the_combos_hold_with_the_card_and_fail_without_it() -> void:
	for id: String in COMBOS:
		var combo: Dictionary = _combo(id)
		check(not combo.is_empty(), "the combo %s exists" % id)
		if combo.is_empty():
			continue
		var with_card: Array[int] = _lost(combo)
		var without: Array[int] = _lost(combo, "blast")
		check(with_card.size() > 0 and with_card.min() > 0, "%s: every imp is hurt (%s)" % [id, with_card])
		check(without.size() > 0 and without.min() == 0, "%s: an imp is spared without Blast (%s)" % [id, without])


func test_a_blast_alone_hurts_the_caster() -> void:
	var arena := ArenaScript.new(root)
	var guard: Node2D = arena.add_guard(0, Vector2.ZERO)
	arena.install_cards(0, 0, ["blast"])
	arena.cast(0, 0)
	arena.run(0.5)
	check(arena.lost(guard) > 0, "the burst on the caster hurts them (%d)" % arena.lost(guard))
	arena.free_all()


func test_four_players_at_once() -> void:
	var arena := ArenaScript.new(root)
	var near: Array[Node2D] = []
	for player in 4:
		var at := Vector2(0.0, 250.0 * player)
		arena.place_caster(player, at)
		arena.add_imp(at + Vector2(100.0, 0.0))
		near.append(arena.add_imp(at + Vector2(100.0, 30.0)))
		arena.install_cards(player, 0, ["blast", "bolt"])
	for player in 4:
		check(arena.cast(player, 0), "player %d casts" % player)
	arena.run(1.5)
	for player in 4:
		check(arena.lost(near[player]) > 0, "player %d's blast hurts the imp beside the hit" % player)
	arena.free_all()
