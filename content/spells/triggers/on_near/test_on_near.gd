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


## Where a rune cast along +x from the origin lies (it stays there).
const RUNE_AT: Vector2 = Vector2(28.0, 0.0)
## Health of a body no test here kills, so what it lost is all counted.
const BIG: float = 500.0


## A rune lasts: with a foe beside it (inside its payload ring's reach, outside the rune's own
## strike), it fires again and again, one ring each interval.
func test_a_lasting_carrier_fires_again_once_each_interval() -> void:
	var arena := ArenaScript.new(root)
	var imp: Node2D = arena.add_imp(RUNE_AT + Vector2(0.0, 40.0), BIG)
	var staff: CompiledStaff = arena.install_cards(0, 0, ["on_near", "rune", "pulse"])
	var trigger: CompiledSpell.Trigger = staff.casts[0].group.spells[0].triggers[0]
	var ring: float = trigger.payload.spells[0].damage
	arena.cast(0, 0)
	var seconds: float = 3.0
	arena.run(seconds)
	var fires: float = (BIG - arena.combat.health_of(imp)) / ring
	var expected: float = seconds / trigger.interval
	check(is_equal_approx(fires, roundf(fires)), "only rings hurt it, the rune never struck it (%s rings)" % fires)
	check(fires >= expected - 2.0 and fires <= expected + 1.0, "about one ring every %ss: %s in %ss (%s expected)" % [trigger.interval, fires, seconds, expected])
	arena.free_all()


## Only foes count: a teammate beside the rune sets nothing off.
func test_a_teammate_near_sets_nothing_off() -> void:
	var arena := ArenaScript.new(root)
	var mate: Node2D = arena.add_guard(1, RUNE_AT + Vector2(0.0, 30.0))
	var health: float = arena.combat.health_of(mate)
	arena.install_cards(0, 0, ["on_near", "rune", "pulse"])
	arena.cast(0, 0)
	arena.run(1.5)
	check_equal(arena.combat.health_of(mate), health, "no ring went off at the teammate")
	arena.free_all()


## Its foes are its caster's team's, and stay so after that caster is gone (review, 2026-11-12: a
## dead imp's mine turned on its pack).
func test_a_gone_casters_carrier_keeps_its_foes() -> void:
	var arena := ArenaScript.new(root)
	var mate: Node2D = arena.add_guard(1, RUNE_AT + Vector2(0.0, 30.0))
	var health: float = arena.combat.health_of(mate)
	arena.install_cards(0, 0, ["on_near", "rune", "pulse"])
	arena.cast(0, 0)
	arena.run(0.1)
	arena.projectiles.actors.close(0)
	arena.run(1.5)
	check_equal(arena.combat.health_of(mate), health, "its caster closed, the rune still spares the teammate")
	arena.free_all()


## The rune sentry with its caster standing beside it: the bolt goes down at the imp, not through
## the caster (the combo on_near_rune_sentry, with the caster's own health read).
func test_a_rune_sentry_shoots_the_foe_and_spares_its_caster() -> void:
	var arena := ArenaScript.new(root)
	var wizard: Node2D = arena.add_guard(0, Vector2.ZERO)
	var health: float = arena.combat.health_of(wizard)
	var imp: Node2D = arena.add_imp(RUNE_AT + Vector2(0.0, 100.0))
	arena.install_cards(0, 0, ["on_near", "rune", "bolt"])
	arena.cast(0, 0)
	arena.run(1.5)
	check(arena.lost(imp) > 0, "the bolt hit the imp below the rune")
	check_equal(arena.combat.health_of(wizard), health, "and not its caster")
	arena.free_all()
