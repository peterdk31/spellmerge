extends "res://tests/support/suite.gd"
## What a beam split again and again costs (#972: "Performance is shit" with several Split cards on a
## beam): Split makes three of whatever it splits, so a beam with four is 81 beams, each walking its
## ray every step. A held beam with 1 to 4 Splits in the combo arena (Spells, the projectile manager,
## Combat), cast once toward an empty side of a room of imps (the rays walk the targets' grid and hit
## nothing), its runtime stepped through a whole round of its hits (`SpellLimits.BEAM_TICK`: the steps
## between its hits and one that hits) and timed against the GDScript reference
## (tests/support/wall_clock.gd). With four Splits the native round holds BUDGET_REFERENCES (the web
## build runs the module too); each count's multiple, and the GDScript fallback's, is printed (`BUDGET:` lines) for the PR. Real time is read here, in a test, never in the
## game. The beams between their hits walk together (`CarrierBeam.walk_together`, natively
## `ShotKernel.ray_walks`); before that each walked alone, in GDScript, and four Splits' round took
## about twice its usual (4.2 to 4.9 references), past the budget.
const ArenaScript := preload("res://tests/content/spells/combo_arena.gd")
const NativeScript := preload("res://core/native/native.gd")
const WallClock := preload("res://tests/support/wall_clock.gd")

const DT: float = 1.0 / 60.0
## A round of the beams' hits, in steps (BEAM_TICK is 9 steps).
const ROUND: int = 9
const REPEATS: int = 5
## Four Splits' round in GDScript references, measured on a 4-core container, 2026-11-27: 2.33 and
## 2.37 with the beams walking together natively (about 15 us a beam a step), 4.24 and 4.87 as each
## walked alone before (about 30 us); the usual times the slack (1.5).
const USUAL_REFERENCES: float = 2.35
const BUDGET_REFERENCES: float = USUAL_REFERENCES * 1.5


## The arena with a held beam of `splits` Splits on, cast toward the empty side, the projectile
## manager native or not; and its beams.
func _arena(splits: int, native: bool) -> Array:
	var arena := ArenaScript.new(root)
	arena.projectiles.native = native
	arena.projectiles.set_cap(4096)
	arena.projectiles.set_native_threads(1)
	for n in 12:
		arena.add_imp(Vector2(-60.0 - 20.0 * (n % 4), -90.0 + 16.0 * n), 1.0e9)
	var cards: Array = ["hold"]
	for n in splits:
		cards.append("split")
	cards.append("beam")
	arena.install_cards(0, 0, cards)
	check(arena.cast(0, 0, Vector2.RIGHT), "%d Splits: the beam is cast" % splits)
	arena.run(DT * 3.0)
	return [arena, CarrierBeam.of(arena.spells)]


## A round of `splits` Splits' beams, timed; checks they stay on.
func _round(splits: int, native: bool) -> WallClock.Timed:
	var made: Array = _arena(splits, native)
	var arena: ArenaScript = made[0]
	var beams: CarrierBeam = made[1]
	var wanted: int = 1
	for n in splits:
		wanted *= 3
	check_equal(beams.beam_count(), wanted, "%d Splits: %d beams on" % [splits, wanted])
	var spells: Node = arena.spells
	var cost: WallClock.Timed = WallClock.against(func() -> void:
		for step in ROUND:
			spells.step(DT), WallClock.gdscript_reference, REPEATS)
	check_equal(beams.beam_count(), wanted, "%d Splits: the beams stay on" % splits)
	print("BUDGET: a held beam with %d Splits (%d beams), %s: a round of %d steps %d us, %.1f us a beam a step (%.2f GDScript references)" % [splits, wanted, "native" if native else "GDScript", ROUND, cost.work_usec, float(cost.work_usec) / ROUND / wanted, cost.multiple])
	arena.free_all()
	return cost


func test_a_beam_split_four_times_is_within_its_budget() -> void:
	var native: bool = NativeScript.loaded()
	for splits in range(1, 5):
		_round(splits, false)
	if not native:
		check(OS.get_environment("SPELLMERGE_NATIVE") != "required", "SPELLMERGE_NATIVE=required, but the native module is not loaded")
		print("NOTE: the native module is not built; the budget is not held")
		return
	for splits in range(1, 5):
		var cost: WallClock.Timed = _round(splits, true)
		if splits == 4:
			check(cost.multiple <= BUDGET_REFERENCES, "four Splits' round within %.2f GDScript references (%.2f)" % [BUDGET_REFERENCES, cost.multiple])
