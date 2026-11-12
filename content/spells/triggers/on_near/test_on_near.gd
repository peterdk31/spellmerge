extends "res://tests/support/suite.gd"
## The On Near card (content/spells/triggers/on_near/; props W9b, owner 2026-11-12): while its
## carrier lives, a foe of its caster that comes within its payload's reach sets the payload off
## from the carrier, toward that foe, and again after the payload's wind-up while one is still
## near. A proximity fuse on a bolt, a mine on a rune. Its combos are in its folder's combos/
## (test_combos.gd plays them).
##
## godot --headless --path . --script res://content/spells/triggers/on_near/test_on_near.gd

const ArenaScript := preload("res://tests/content/spells/combo_arena.gd")


func _card() -> TriggerBase:
	return load("res://content/spells/triggers/on_near/on_near.tres") as TriggerBase


func _staff(cards: Array) -> CompiledStaff:
	var arena := ArenaScript.new(root)
	var staff: CompiledStaff = arena.install_cards(0, 0, cards)
	arena.free_all()
	return staff


func test_the_card_is_a_valid_trigger() -> void:
	var card: TriggerBase = _card()
	check(card != null, "on_near.tres loads as a TriggerBase")
	if card == null:
		return
	check_equal(card.id, &"on_near", "its id is its folder")
	check_equal(card.event, TriggerBase.Event.NEAR, "its event is near")
	check(card.wind_up > 0.0, "it has a wind-up of its own, so it never fires every step")
	check(card.icon != null, "it has an icon")
	check(card.range_problems().is_empty(), "inside every range: %s" % [card.range_problems()])
	check(TriggerBase.LIVE.has(TriggerBase.Event.NEAR), "it is a live trigger: it fires while its carrier lasts")


func test_its_reach_is_its_payloads() -> void:
	var spell: CompiledSpell = _staff(["on_near", "bolt", "fire", "pulse"]).casts[0].group.spells[0]
	check_equal(spell.triggers.size(), 1, "the bolt carries one trigger")
	if spell.triggers.is_empty():
		return
	var trigger: CompiledSpell.Trigger = spell.triggers[0]
	check_equal(trigger.event, TriggerBase.Event.NEAR, "on near")
	var ring: CompiledSpell = trigger.payload.spells[0]
	check(is_equal_approx(trigger.reach, CastSense.reach_of(trigger.payload)), "its reach is the payload's (%s)" % trigger.reach)
	check(trigger.reach >= ring.speed * ring.lifetime * 0.9, "a fire ring's: as far as it grows (%s)" % trigger.reach)
	check(trigger.interval >= _card().wind_up, "it waits at least its own wind-up between fires (%s)" % trigger.interval)


## The fuse: the bolt passes an imp beside its path without touching it, and bursts near it.
func test_a_bolt_bursts_near_a_foe_it_passes() -> void:
	var arena := ArenaScript.new(root)
	var imp: Node2D = arena.add_imp(Vector2(110.0, 34.0))
	arena.install_cards(0, 0, ["on_near", "bolt", "fire", "pulse"])
	arena.cast(0, 0)
	arena.run(1.5)
	check(arena.was_given(imp, &"burn"), "the fire ring burned the imp")
	arena.free_all()
	arena = ArenaScript.new(root)
	imp = arena.add_imp(Vector2(110.0, 34.0))
	arena.install_cards(0, 0, ["on_hit", "bolt", "fire", "pulse"])
	arena.cast(0, 0)
	arena.run(1.5)
	check(not arena.was_given(imp, &"burn"), "on hit does not: the bolt never touches it")
	arena.free_all()


func test_it_stays_quiet_with_no_foe_near() -> void:
	var arena := ArenaScript.new(root)
	var far: Node2D = arena.add_imp(Vector2(110.0, 140.0))
	arena.install_cards(0, 0, ["on_near", "bolt", "fire", "pulse"])
	arena.cast(0, 0)
	arena.run(1.5)
	check(not arena.was_given(far, &"burn"), "an imp out of the payload's reach is never burned")
	check_equal(arena.lost(far), 0, "or touched")
	arena.free_all()


## A rune lasts: with a foe beside it, it fires again and again, paced by the payload's wind-up.
func test_a_lasting_carrier_fires_again_paced() -> void:
	var arena := ArenaScript.new(root)
	var imp: Node2D = arena.add_imp(Vector2(30.0, 20.0), 500.0)
	var staff: CompiledStaff = arena.install_cards(0, 0, ["on_near", "rune", "pulse"])
	var interval: float = staff.casts[0].group.spells[0].triggers[0].interval
	arena.cast(0, 0)
	arena.run(2.0)
	var lost: int = roundi(500.0 - arena.combat.health_of(imp))
	var ring: float = staff.casts[0].group.spells[0].triggers[0].payload.spells[0].damage
	var fires: int = roundi(float(lost) / ring)
	check(fires >= 2, "it fired again while the imp stayed near (%d rings)" % fires)
	check(fires <= ceili(2.0 / interval) + 1, "but no more often than its interval allows (%d rings, %ss apart)" % [fires, interval])
	arena.free_all()
