extends "res://tests/support/suite.gd"
## The Barrier card (content/spells/modifiers/barrier/; owner, 2026-11-12): whatever its carrier
## hits, friend or foe, gets a barrier of one blocked hit per card for SpellLimits.BARRIER_SECONDS.
## It is part of the hit (`HitProfile.barrier`): Combat gives it after the hit's heal or damage, so
## it never blocks the hit that brings it, and it comes with a mend's heal too. Shield is another
## thing: it guards the carrier itself (and what a move moves). Its combos are in its folder's
## combos/ (test_combos.gd plays them).
##
## godot --headless --path . --script res://content/spells/modifiers/barrier/test_barrier.gd

const ArenaScript := preload("res://tests/content/spells/combo_arena.gd")

const ALLY_HURT: int = 40


func _card() -> ModifierBase:
	return load("res://content/spells/modifiers/barrier/barrier.tres") as ModifierBase


func _spell(cards: Array) -> CompiledSpell:
	var arena := ArenaScript.new(root)
	var staff: CompiledStaff = arena.install_cards(0, 0, cards)
	var spell: CompiledSpell = staff.casts[0].group.spells[0]
	arena.free_all()
	return spell


func test_the_card_is_a_valid_modifier() -> void:
	var card: ModifierBase = _card()
	check(card != null, "barrier.tres loads as a ModifierBase")
	if card == null:
		return
	check_equal(card.id, &"barrier", "its id is its folder")
	check_equal(card.behaviour, ModifierBase.Behaviour.BARRIER, "its behaviour is barrier")
	check_equal(card.behaviour_strength, 1.0, "one blocked hit a card")
	check(card.icon != null, "it has an icon")
	check(card.range_problems().is_empty(), "inside every range: %s" % [card.range_problems()])


func test_a_barrier_bolts_hit_carries_the_barrier_and_cards_add() -> void:
	var hit: HitProfile = _spell(["barrier", "bolt"]).hit
	check_equal(hit.barrier, 1, "one blocked hit")
	check_equal(hit.barrier_seconds, SpellLimits.BARRIER_SECONDS, "for its time")
	check_equal(_spell(["barrier", "barrier", "bolt"]).hit.barrier, 2, "two cards add (rule 3)")
	check_equal(_spell(["bolt"]).hit.barrier, 0, "a plain bolt gives none")
	check_equal(_spell(["barrier", "blast", "bolt"]).blast_hit.barrier, 1, "a blast strikes with it too")


func test_the_builder_says_what_it_gives() -> void:
	var arena := ArenaScript.new(root)
	check(arena.spells.component_stats(&"barrier").has("Barrier 1"), "the hub line: %s" % [arena.spells.component_stats(&"barrier")])
	arena.free_all()


## Friend or foe: an imp it hits takes the bolt's damage, then has the barrier (it does not block
## the hit that brings it).
func test_a_barrier_bolt_hurts_an_imp_then_shields_it() -> void:
	var arena := ArenaScript.new(root)
	var imp: Node2D = arena.add_imp(Vector2(80.0, 0.0))
	arena.install_cards(0, 0, ["barrier", "bolt"])
	arena.cast(0, 0)
	arena.run(1.0)
	check(arena.lost(imp) > 0, "the bolt hurt the imp (%d)" % arena.lost(imp))
	check_equal(arena.combat.shield(imp), 1, "and left a barrier on it")
	arena.free_all()


func test_a_mend_barrier_bolt_heals_a_teammate_and_shields_it() -> void:
	var arena := ArenaScript.new(root)
	var ally: Node2D = arena.add_guard(1, Vector2(60.0, 0.0))
	arena.hurt(ally, ALLY_HURT)
	arena.install_cards(0, 0, ["mend", "barrier", "bolt"])
	arena.cast(0, 0)
	arena.run(1.0)
	check(arena.lost(ally) < ALLY_HURT, "healed (%d of %d lacking)" % [arena.lost(ally), ALLY_HURT])
	check_equal(arena.combat.shield(ally), 1, "and shielded: the barrier comes with a heal")
	arena.free_all()


func test_the_barrier_runs_out_after_its_time() -> void:
	var arena := ArenaScript.new(root)
	var imp: Node2D = arena.add_imp(Vector2(80.0, 0.0))
	arena.install_cards(0, 0, ["barrier", "bolt"])
	arena.cast(0, 0)
	arena.run(0.6)
	check_equal(arena.combat.shield(imp), 1, "a barrier just after the hit")
	arena.run(SpellLimits.BARRIER_SECONDS + 0.5)
	check_equal(arena.combat.shield(imp), 0, "gone after BARRIER_SECONDS")
	arena.free_all()
