extends "res://tests/support/suite.gd"
## Every shot's default motion (SpellLimits.SHOT_SPEED_*; owner, 2026-11-05: what the Drag card
## did, now every shot's): a flying shot bursts out fast and eases down as its life runs out, yet
## goes as far as its speed x life says. It strikes near things sooner than a shot that kept its
## speed, its `on expire` goes off where a shot of that speed and life would end, a card's speed
## numbers multiply the default, and four players' shots all move this way at once.
##
## godot --headless --path . --script res://tests/core/test_shot_speed_curve.gd

const ArenaScript := preload("res://tests/content/spells/combo_arena.gd")


func test_the_default_bursts_out_and_slows_without_stopping() -> void:
	check(SpellLimits.SHOT_SPEED_START > 1.0, "it leaves faster than its speed")
	check(SpellLimits.SHOT_SPEED_END > 0.0 and SpellLimits.SHOT_SPEED_END < 1.0, "and ends slower, still drifting")
	check(SpellLimits.SHOT_SPEED_EASE > 1.0, "most of the slowing comes early")
	# The share of speed x life it flies: the curve's mean, start + (end - start) x ease / (ease + 1).
	var ease_share: float = SpellLimits.SHOT_SPEED_EASE / (SpellLimits.SHOT_SPEED_EASE + 1.0)
	var mean: float = SpellLimits.SHOT_SPEED_START + (SpellLimits.SHOT_SPEED_END - SpellLimits.SHOT_SPEED_START) * ease_share
	check(is_equal_approx(mean, 1.0), "it goes as far as its speed x life says (%f of it)" % mean)


func test_every_compiled_spell_takes_it() -> void:
	var arena := ArenaScript.new(root)
	var staff: CompiledStaff = arena.install_cards(0, 0, ["bolt"])
	var spell: CompiledSpell = staff.casts[0].group.spells[0]
	arena.free_all()
	check(spell.has_speed_curve(), "a bolt with no cards has the curve")
	check_equal(spell.speed_start, SpellLimits.SHOT_SPEED_START, "its start")
	check_equal(spell.speed_end, SpellLimits.SHOT_SPEED_END, "its end")
	check_equal(spell.speed_ease, SpellLimits.SHOT_SPEED_EASE, "its ease")


## A card's speed numbers multiply the default, and two such cards each other (`StaffCompiler`).
## No card in the box sets them today, so this one is made here.
func test_a_cards_numbers_multiply_the_default() -> void:
	var bolt: FormBase = load("res://content/spells/forms/bolt/bolt.tres") as FormBase
	var card := ModifierBase.new()
	card.id = &"test_curve"
	card.speed_start = 1.5
	card.speed_end = 0.5
	card.speed_ease = 2.0
	var cards: Dictionary = {&"bolt": bolt, &"test_curve": card}
	var compiler := StaffCompiler.new(func(id: StringName) -> SpellComponent: return cards.get(id))
	var ids: Array[StringName] = [&"test_curve", &"test_curve", &"bolt"]
	var staff: CompiledStaff = compiler.compile(ids, null)
	var spell: CompiledSpell = staff.casts[0].group.spells[0]
	check_equal(spell.speed_start, SpellLimits.SHOT_SPEED_START * 1.5 * 1.5, "the start")
	check_equal(spell.speed_end, SpellLimits.SHOT_SPEED_END * 0.5 * 0.5, "the end")
	check_equal(spell.speed_ease, SpellLimits.SHOT_SPEED_EASE * 2.0 * 2.0, "the ease")
	check(not staff.wasted.has(0), "and the card is not wasted on a bolt")


## Health an imp at `at` loses to one cast of `cards` in `seconds`.
func _lost(cards: Array, at: Vector2, seconds: float) -> int:
	var arena := ArenaScript.new(root)
	var imp: Node2D = arena.add_imp(at)
	arena.install_cards(0, 0, cards)
	arena.cast(0, 0)
	arena.run(seconds)
	var lost: int = arena.lost(imp)
	arena.free_all()
	return lost


func test_it_strikes_sooner_than_a_steady_shot() -> void:
	# A bolt that kept its 220 px/s would be 110 px out after 0.5 s, short of an imp at 150 px
	# (its edge at 140 px); one that bursts out is past 170 px.
	check(_lost(["bolt"], Vector2(150.0, 0.0), 0.5) > 0, "a bolt reaches an imp at 150 px in half a second")


func test_it_goes_as_far_as_its_speed_and_life() -> void:
	# A bolt flies 220 px/s for 1.2 s: 264 px. Its nova goes off where it ends.
	var cards: Array = ["on_expire", "bolt", "nova"]
	check(_lost(cards, Vector2(262.0, 30.0), 1.8) > 0, "it ends where speed x life says")
	check_equal(_lost(cards, Vector2(140.0, 30.0), 1.8), 0, "not short of it")


func test_four_players_shots_burst_at_once() -> void:
	var arena := ArenaScript.new(root)
	var imps: Array[Node2D] = []
	for player in 4:
		var at := Vector2(0.0, 150.0 * player)
		arena.place_caster(player, at)
		imps.append(arena.add_imp(at + Vector2(150.0, 0.0)))
		arena.install_cards(player, 0, ["bolt"])
	for player in 4:
		check(arena.cast(player, 0), "player %d casts" % player)
	arena.run(0.5)
	for player in 4:
		check(arena.lost(imps[player]) > 0, "player %d's bolt bursts out to its imp" % player)
	arena.free_all()
