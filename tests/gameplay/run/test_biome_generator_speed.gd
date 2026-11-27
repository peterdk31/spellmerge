extends "res://tests/support/suite.gd"
## A crypt map's making is quick, and the same as before it was (#972: seed 4242's map took 2.3 s on
## the web, other seeds 0.11 to 0.14 s; gameplay/run/biome_generator.gd, `Growth._closable`). A style
## with a loop pull weighs every placement of every template off every room, tens of thousands a map,
## each by how many loops it leaves to close; that count looked each of the placement's sockets'
## crossings up in `free_at`, and now looks the socket up once among the crossings that reach a free
## socket (`Growth._loop_ends`), asking `_loop_keeps` once a room pair while the map stands as it is.
##
## - The count is the same: every placement weighed while seed 4242's and other crypt maps grow is
##   also counted the way it was before (`Checked._closable_before`: each crossing looked up, and
##   `_loop_keeps` asked afresh) and matches; the growth checked is `BiomeGenerator.generate`'s (its
##   tries and dice), so its map is the generator's.
## - Quick: seed 4242's map within `USUAL` times `SLACK` interpreted-GDScript references
##   (tests/support/wall_clock.gd); grown with the count worked out as before, it measures `BEFORE`.
# unit-test-alone
const WallClock := preload("res://tests/support/wall_clock.gd")

## The run the departure makes, and the seed whose map was the slowest (#974's measurements).
const RUN: StringName = &"crypt"
const SLOW_SEED: int = 4242
## Other crypt seeds whose growth is checked placement by placement (a few loop-pull styles among them).
const SEEDS: Array[int] = [1, 3, 7, 42, 100]
## Seed 4242's map in GDScript references (measured on a quiet 4-core container, 2026-11-27: 65 to
## 67; with the count worked out as before #972, `BEFORE`, 229 to 268), and the slack.
const USUAL: float = 66.0
const BEFORE: float = 245.0
const SLACK: float = 1.5
const RUNS: int = 3

var registry: Node = null


func before_each() -> void:
	super.before_each()
	registry = root.get_node("Registry")


## A growth that also counts every placement's loops the way it was counted before, and keeps
## whether the two counts ever differed; with `as_before`, it counts only that way.
class Checked:
	extends BiomeGenerator.Growth
	var counted: int = 0
	var differed: int = 0
	var as_before: bool = false

	func _closable(shape: PieceShape, place: Vector2, joined: int, parent: int, kind: StringName) -> int:
		var before: int = _closable_before(shape, place, joined, parent, kind)
		if as_before:
			return before
		var now: int = super._closable(shape, place, joined, parent, kind)
		counted += 1
		if now != before:
			differed += 1
		return now


	## The count as it was before #972, line for line: each crossing of each socket looked up in
	## `free_at`, and `_loop_keeps` asked afresh each time (no cache of this growth's read).
	func _closable_before(shape: PieceShape, place: Vector2, joined: int, parent: int, kind: StringName) -> int:
		var count: int = 0
		for socket in shape.sockets():
			if socket == joined:
				continue
			var at: Vector2 = place + shape.socket_at[socket]
			for crossing: BiomeGenerator.Crossing in crossings[shape.socket_facing[socket]]:
				var far: Vector2 = at + crossing.span
				var key := Vector3i(roundi(far.x), roundi(far.y), RoomSocket.opposite(crossing.far_facing))
				if not free_at.has(key):
					continue
				var other: int = (free_at[key] as Vector2i).x
				if other == parent or not _bridge_clear(Rect2(at - crossing.from_at, crossing.size), other, -1):
					continue
				if _loop_keeps(parent, kind, other):
					count += 1
		return count


## The map of seed `seed_value` grown as `generate` grows it (its tries, its dice), by `Checked`
## growths; `growths` gets each try's.
func _grown(seed_value: int, growths: Array[Checked], as_before: bool = false) -> BiomeMap:
	var definition := registry.get_resource(&"runs", RUN) as RunDefinition
	var rules: MapRules = definition.biomes[0]
	var content: RunContent = registry.run_content()
	var shapes: Dictionary = registry.run_shapes(definition)
	for attempt in BiomeGenerator.ATTEMPTS:
		var growth := Checked.new(rules, content, shapes, MapDice.new(Sim.seeded(seed_value), BiomeGenerator.PURPOSE, attempt, BiomeGenerator.Step.size()))
		growth.as_before = as_before
		growth.secret_dice = MapDice.new(Sim.seeded(seed_value), BiomeGenerator.SECRET_PURPOSE, attempt, 1)
		growths.append(growth)
		if growth.grow() == "":
			return growth.to_map()
	return null


func _generated(seed_value: int) -> BiomeMap:
	var definition := registry.get_resource(&"runs", RUN) as RunDefinition
	return BiomeGenerator.generate(definition, registry.run_content(), registry.run_shapes(definition), Sim.seeded(seed_value))


func test_every_placement_counts_its_loops_as_before() -> void:
	var slow_weighed: int = 0
	for seed_value: int in [SLOW_SEED] + SEEDS:
		var growths: Array[Checked] = []
		var grown: BiomeMap = _grown(seed_value, growths)
		if seed_value == SLOW_SEED and not growths.is_empty():
			slow_weighed = growths[-1].counted
		check(grown != null, "seed %d: a map grown" % seed_value)
		var counted: int = 0
		var differed: int = 0
		for growth: Checked in growths:
			counted += growth.counted
			differed += growth.differed
		check_equal(differed, 0, "seed %d: of %d placements weighed, none counts its loops otherwise" % [seed_value, counted])
		if grown != null:
			# The checked growth takes `generate`'s tries and dice (the rooms' fights and rewards are
			# rolled after the growth: its rooms and bridges are compared).
			var made: BiomeMap = _generated(seed_value)
			check_equal(grown.room_templates, made.room_templates, "seed %d: the generator's rooms" % seed_value)
			check_equal(grown.room_places, made.room_places, "seed %d: where they stand" % seed_value)
			check_equal(grown.room_mirrors, made.room_mirrors, "seed %d: their mirrorings" % seed_value)
			check_equal(grown.bridge_ends, made.bridge_ends, "seed %d: its bridges' ends" % seed_value)
	# Seed 4242 weighs the most (a loop-pull style): the check covers the case that was slow.
	check(slow_weighed > 10000, "seed %d weighs tens of thousands of placements (%d)" % [SLOW_SEED, slow_weighed])


func test_the_slow_seeds_map_is_made_quickly() -> void:
	var timed: WallClock.Timed = WallClock.against(func() -> void:
		check(_generated(SLOW_SEED).is_made(), "the map is made"), WallClock.gdscript_reference, RUNS)
	print("BENCH: crypt seed %d's map: %.1f GDScript references (%d us; a reference %d us)" % [SLOW_SEED, timed.multiple, timed.work_usec, timed.reference_usec])
	check(timed.multiple <= USUAL * SLACK, "seed %d's map in %.1f GDScript references, within %.1f" % [SLOW_SEED, timed.multiple, USUAL * SLACK])


## The budget catches the slowness it holds off: the count worked out as before is over it.
func test_the_count_as_before_is_over_the_budget() -> void:
	var timed: WallClock.Timed = WallClock.against(func() -> void:
		var growths: Array[Checked] = []
		check(_grown(SLOW_SEED, growths, true) != null, "the map is grown"), WallClock.gdscript_reference, 1)
	print("BENCH: crypt seed %d's map, counted as before: %.1f GDScript references" % [SLOW_SEED, timed.multiple])
	check(timed.multiple > USUAL * SLACK, "counted as before, %.1f references, over the budget of %.1f" % [timed.multiple, USUAL * SLACK])
