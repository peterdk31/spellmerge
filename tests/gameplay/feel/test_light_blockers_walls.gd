extends "res://tests/support/suite.gd"
## The light's standing walls at a run's start (#972, gameplay/feel/light_blockers.gd): a biome hands
## its world's walls over again with each piece it lays (Spectacle's `room_built`), all in one frame,
## and they are worked out once, when first read, as they stand after the last piece: the same walls
## as worked out from that last list at once, and quick (the walls of BIOME_PIECES pieces handed over
## piece by piece within `USUAL` times `SLACK` interpreted-GDScript references,
## tests/support/wall_clock.gd; working them out at each hand-over, as before, was ten times that
## here and more with a real biome's walls: about 290 ms at the web's start of a run).
# unit-test-alone
const LightBlockersScript := preload("res://gameplay/feel/light_blockers.gd")
const WallClock := preload("res://tests/support/wall_clock.gd")

## A crypt biome's pieces (rooms and walkways) and walls a piece: about what one lays (29 to 32
## pieces, up to 430 walls in all, 2026-11-27).
const BIOME_PIECES: int = 30
## The hand-overs of BIOME_PIECES pieces and the one read after, in GDScript references (measured on
## a quiet 4-core container, 2026-11-27: 0.24; worked out at each hand-over, as before #972, 2.6), and
## the slack.
const USUAL: float = 0.25
const SLACK: float = 1.5
const RUNS: int = 3


## Piece `at`'s walls: its edge (four walls round a 320x224 box) and four standing inside it, the
## pieces in a row of six a row.
func _piece_walls(at: int) -> Array[Rect2]:
	var corner := Vector2(float(at % 6) * 400.0, float(at / 6) * 300.0)
	var found: Array[Rect2] = []
	for rect: Rect2 in [Rect2(0, 0, 320, 16), Rect2(0, 208, 320, 16), Rect2(0, 0, 16, 224), Rect2(304, 0, 16, 224),
			Rect2(64, 64, 32, 16), Rect2(224, 64, 32, 16), Rect2(64, 144, 32, 16), Rect2(224, 144, 32, 16)]:
		found.append(Rect2(rect.position + corner, rect.size))
	return found


## The walls handed over as Spectacle hands a biome's: the world's so far, after each piece.
func _hand_over(blockers: LightBlockersScript) -> Array[Rect2]:
	var world: Array[Rect2] = []
	for at in BIOME_PIECES:
		world.append_array(_piece_walls(at))
		blockers.use_walls(world)
	return world


func test_the_walls_are_the_last_hand_overs() -> void:
	var blockers := LightBlockersScript.new()
	var world: Array[Rect2] = _hand_over(blockers)
	var want: Array[Rect2] = LightBlockersScript.standing(world)
	check_equal(blockers.walls, want, "the standing walls of the world as last handed over")
	check(want.size() >= BIOME_PIECES * 4, "four stand in each piece, at least")
	# The list handed over is the caller's: a wall added to it after is not the blockers'.
	var handed: Array[Rect2] = _piece_walls(0)
	blockers.use_walls(handed)
	handed.append(Rect2(150, 100, 8, 8))
	check_equal(blockers.walls, LightBlockersScript.standing(_piece_walls(0)), "a later hand-over replaces them, as handed")
	blockers.use_walls([] as Array[Rect2])
	check(blockers.walls.is_empty(), "no walls, none stand")


func test_a_biome_hands_its_walls_over_quickly() -> void:
	var timed: WallClock.Timed = WallClock.against(func() -> void:
		var blockers := LightBlockersScript.new()
		_hand_over(blockers)
		check(not blockers.walls.is_empty(), "the walls are worked out"), WallClock.gdscript_reference, RUNS)
	print("LIGHT WALLS %d pieces handed over: %.2f GDScript references (%.1f ms, a reference %.1f ms)" % [BIOME_PIECES, timed.multiple, timed.work_usec / 1000.0, timed.reference_usec / 1000.0])
	check(timed.multiple <= USUAL * SLACK, "a biome's walls handed over in %.2f GDScript references, within %.2f" % [timed.multiple, USUAL * SLACK])
