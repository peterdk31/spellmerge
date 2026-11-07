extends "res://tests/support/suite.gd"
## The game's time and chance (core/sim/sim.gd, online-ready N3c): a roll is a hash of the run's
## seed and the name its caller gives it, so the same name rolls the same, any other name rolls
## anew, and no system's rolls shift another's. The Tick owns the game's sim: it keeps its tick and
## deals the run's seed at a run's start.

const TickScript := preload("res://core/sim/tick.gd")
const FramesScript := preload("res://core/sim/frames.gd")


func test_the_same_name_rolls_the_same() -> void:
	var a := Sim.seeded(42)
	var b := Sim.seeded(42)
	b.tick = 900
	check_equal(a.chance(&"scatter", 7, 3), b.chance(&"scatter", 7, 3), "the same seed and name, whatever the tick")
	check_equal(a.bits(&"scatter", 7, 3), a.bits(&"scatter", 7, 3), "and again")


func test_any_other_name_rolls_anew() -> void:
	var sim := Sim.seeded(42)
	var base: int = sim.bits(&"scatter", 7, 3)
	check(sim.bits(&"brain", 7, 3) != base, "another purpose")
	check(sim.bits(&"scatter", 8, 3) != base, "another key")
	check(sim.bits(&"scatter", 7, 4) != base, "another counter")
	check(Sim.seeded(43).bits(&"scatter", 7, 3) != base, "another run's seed")
	check(Sim.seeded(42 + (1 << 32)).bits(&"scatter", 7, 3) != base, "a seed that differs in its high bits")


## The formula is pinned, to the number: a roll changes only when this test does (every seeded
## outcome would), and an engine whose `hash` changed fails here first.
func test_the_formula_is_pinned() -> void:
	var sim := Sim.seeded(20261107)
	check_equal(hash(&"scatter"), 2251587099, "a purpose hashes by its text")
	check_equal(sim.bits(&"scatter", 1, 0), 2047479749, "murmur3 of the seed's low word, its high word and the purpose, the key and the counter")


func test_rolls_spread_evenly() -> void:
	var sim := Sim.seeded(5)
	var buckets: PackedInt32Array = PackedInt32Array()
	buckets.resize(10)
	var lowest: float = 1.0
	var highest: float = 0.0
	for n in 20000:
		var roll: float = sim.chance(&"spread", 0, n)
		lowest = minf(lowest, roll)
		highest = maxf(highest, roll)
		buckets[floori(roll * 10.0)] += 1
	check(lowest >= 0.0 and highest < 1.0, "in [0, 1): %f to %f" % [lowest, highest])
	for i in buckets.size():
		check(absi(buckets[i] - 2000) < 200, "bucket %d holds %d of 20000" % [i, buckets[i]])
	# Neighbouring keys too (a cast's key is its count): no pattern from key to key.
	var above: int = 0
	for key in 2000:
		if sim.chance(&"spread", key, 0) >= 0.5:
			above += 1
	check(absi(above - 1000) < 100, "over keys, %d of 2000 above a half" % above)


func test_whole_numbers_and_ranges() -> void:
	var sim := Sim.seeded(9)
	var seen: PackedInt32Array = PackedInt32Array()
	seen.resize(5)
	for n in 500:
		var pick: int = sim.chance_int(&"pick", 0, n, 5)
		check(pick >= 0 and pick < 5, "0 to 4: %d" % pick)
		if pick >= 0 and pick < 5:
			seen[pick] += 1
		var x: float = sim.chance_range(&"range", 0, n, -2.0, 3.0)
		check(x >= -2.0 and x < 3.0, "in [-2, 3): %f" % x)
	check(not seen.has(0), "every whole number comes up: %s" % seen)
	check_equal(sim.chance_int(&"pick", 0, 0, 1), 0, "one choice: 0")
	check_equal(sim.chance_int(&"pick", 0, 0, 0), 0, "none: 0")


func test_a_node_in_the_tree_finds_the_ticks_sim() -> void:
	var node := Node.new()
	check(Sim.found(node) != null and Sim.found(node).run_seed == 0, "out of the tree: a sim at seed 0")
	root.add_child(node)
	own(node)
	check(Sim.found(node) == root.get_node("Tick").get(&"sim"), "in the tree: the Tick's")
	check(Sim.found(null) != null, "none: still a sim")


func test_a_run_deals_its_seed_and_counts_from_zero() -> void:
	var tick: TickScript = TickScript.new()
	var frames: FramesScript = FramesScript.new()
	tick.frames = frames
	tick.run(TickScript.DT)
	tick.run(TickScript.DT)
	var sim: Sim = tick.sim
	check_equal(sim.tick, 1, "the sim's tick is the tick being run")
	var replay := Replay.new()
	replay.run_seed = 31
	frames.set(&"_tape", ReplayTape.playing(replay))
	tick.begin_run()
	var first: int = sim.run_seed
	check_equal(sim.tick, 0, "a run counts from 0")
	tick.run(TickScript.DT)
	check_equal(sim.tick, 0, "its first tick is 0")
	frames.set(&"_tape", ReplayTape.playing(replay))
	tick.begin_run()
	check_equal(sim.run_seed, first, "a replay's run takes the same seed")
	var other := Replay.new()
	other.run_seed = 32
	frames.set(&"_tape", ReplayTape.playing(other))
	tick.begin_run()
	check(sim.run_seed != first, "another replay's another")
	frames.free()
	tick.free()
