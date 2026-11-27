extends "res://tests/support/suite.gd"
## What many shots cost (#972: "Performance is shit" with several Split cards on a beam). +2 and +3
## add shots (the owner's decision of 2026-11-27); stacked late in a run they make dozens: 1, 6 (+2
## +3), 16 (five +3) and 46 (fifteen +3) shots. In the combo arena (Spells, the projectile manager,
## Combat), with a room of imps off to one side:
## - **a held beam** of that many beams, fanned from the caster, cast once toward
##   the empty side (the rays walk the targets' grid and hit nothing), its runtime stepped through a
##   whole round of its hits (`SpellLimits.BEAM_TICK`: the steps between and one that hits);
## - **a bolt** of that many shots, cast and flown for ROUND steps (the runtime and the manager).
## Each timed against the GDScript reference (tests/support/wall_clock.gd); with 46 beams, natively,
## the round holds BUDGET_REFERENCES (the web build runs the module too). Every multiple is printed
## (`BUDGET:` lines), the GDScript fallback's too. Real time is read here, in a test, never in the
## game. The beams between their hits walk together (`CarrierBeam.walk_together`, natively
## `ShotKernel.ray_walks`); before, each walked alone in GDScript, at about twice the cost.
const ArenaScript := preload("res://tests/content/spells/combo_arena.gd")
const NativeScript := preload("res://core/native/native.gd")
const WallClock := preload("res://tests/support/wall_clock.gd")

const DT: float = 1.0 / 60.0
## A round of the beams' hits, in steps (BEAM_TICK is 9 steps).
const ROUND: int = 9
const REPEATS: int = 5
## The mana a bolt is cast with.
const MANA: float = 10000.0
## Each build: its shots and the cards that add them.
const BUILDS: Array[Array] = [
	[1, []],
	[6, ["plus_two", "plus_three"]],
	[16, ["plus_three", "plus_three", "plus_three", "plus_three", "plus_three"]],
	[46, ["plus_three", "plus_three", "plus_three", "plus_three", "plus_three", "plus_three", "plus_three", "plus_three", "plus_three", "plus_three", "plus_three", "plus_three", "plus_three", "plus_three", "plus_three"]],
]
## 46 beams' round in GDScript references, measured on a 4-core container, 2026-11-27 (see the BUDGET
## lines; each beam walking alone, as before, cost about twice as much a beam); the usual times the
## slack (1.5).
const USUAL_REFERENCES: float = 1.5
const BUDGET_REFERENCES: float = USUAL_REFERENCES * 1.5


## The arena with the imps off to one side, the projectile manager native or not.
func _arena(native: bool) -> ArenaScript:
	var arena := ArenaScript.new(root)
	arena.projectiles.native = native
	arena.projectiles.set_cap(4096)
	arena.projectiles.set_native_threads(1)
	for n in 12:
		arena.add_imp(Vector2(-60.0 - 20.0 * (n % 4), -90.0 + 16.0 * n), 1.0e9)
	return arena


## A round of a held beam with `cards` before it (`shots` beams), timed.
func _beam_round(shots: int, cards: Array, native: bool) -> WallClock.Timed:
	var arena: ArenaScript = _arena(native)
	arena.install_cards(0, 0, ["hold"] + cards + ["beam"])
	check(arena.cast(0, 0, Vector2.RIGHT), "%d beams: cast" % shots)
	arena.run(DT * 3.0)
	var beams: CarrierBeam = CarrierBeam.of(arena.spells)
	var rows: int = shots
	check_equal(beams.beam_count(), rows, "%d beams: %d rows on" % [shots, rows])
	var spells: Node = arena.spells
	var cost: WallClock.Timed = WallClock.against(func() -> void:
		for step in ROUND:
			spells.step(DT), WallClock.gdscript_reference, REPEATS)
	check_equal(beams.beam_count(), rows, "%d beams: they stay on" % shots)
	print("BUDGET: a held beam of %d beams, %s: a round of %d steps %d us, %.1f us a row a step (%.2f GDScript references)" % [shots, "native" if native else "GDScript", ROUND, cost.work_usec, float(cost.work_usec) / ROUND / rows, cost.multiple])
	arena.free_all()
	return cost


## A bolt of `shots` shots cast and flown ROUND steps, timed.
func _bolt_round(shots: int, cards: Array, native: bool) -> WallClock.Timed:
	var arena: ArenaScript = _arena(native)
	arena.install_cards(0, 0, cards + ["bolt"])
	var spells: Node = arena.spells
	var projectiles: Node = arena.projectiles
	var made: Array[int] = [0]
	var cost: WallClock.Timed = WallClock.against(func() -> void:
		# Mana enough for 46 shots (the arena's own cast holds MANA).
		spells.press_staff(0, 0, Vector2.ZERO, Vector2.RIGHT, MANA)
		made[0] = maxi(made[0], arena.projectiles.get_count())
		for step in ROUND:
			projectiles.step(DT)
			spells.step(DT), WallClock.gdscript_reference, REPEATS)
	check(made[0] >= shots, "%d shots flew (%d)" % [shots, made[0]])
	print("BUDGET: a bolt of %d shots, %s: cast and flown %d steps %d us (%.2f GDScript references)" % [shots, "native" if native else "GDScript", ROUND, cost.work_usec, cost.multiple])
	arena.free_all()
	return cost


func test_many_beams_and_shots_are_within_their_budget() -> void:
	var native: bool = NativeScript.loaded()
	for build: Array in BUILDS:
		_beam_round(build[0], build[1], false)
		_bolt_round(build[0], build[1], false)
	if not native:
		check(OS.get_environment("SPELLMERGE_NATIVE") != "required", "SPELLMERGE_NATIVE=required, but the native module is not loaded")
		print("NOTE: the native module is not built; the budget is not held")
		return
	for build: Array in BUILDS:
		var cost: WallClock.Timed = _beam_round(build[0], build[1], true)
		_bolt_round(build[0], build[1], true)
		if build[0] == 46:
			check(cost.multiple <= BUDGET_REFERENCES, "46 beams' round within %.2f GDScript references (%.2f)" % [BUDGET_REFERENCES, cost.multiple])
