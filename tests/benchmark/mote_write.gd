extends SceneTree
## What the CPU pays for motes (docs/milestones/spell-spectacle.md, P1c): a pool of the real kinds
## (content/motes) at the desktop cap, timed on its own. Prints `BENCH: motes` lines: a shot's
## `shed` with rows left (per call and per mote written), a `shed` the frame's FRAME_ROWS cut to
## nothing, a plain `burst` per mote, a burst of each of the storm's sizes a call (S4), and `step`'s
## upload per chunk. Not a unit test.
##
## godot --headless --path . --script res://tests/benchmark/mote_write.gd

const MotesScript := preload("res://gameplay/feel/mote.gd")
const RegistryScript := preload("res://core/registry/registry.gd")
const TimedMotesScript := preload("res://tests/benchmark/timed_motes.gd")

## Calls timed per measure, and the rounds each is repeated (the best round is kept).
const CALLS: int = 2000
const ROUNDS: int = 5
## A shot's look: fire and lightning layers (two kinds shed), and the hat ramp of seat 0.
const LOOK: int = (1 << 0) | (1 << 4)


func _initialize() -> void:
	await process_frame
	var registry: RegistryScript = RegistryScript.new()
	registry.scan()
	var kinds: Array[MoteKind] = []
	for found: Resource in registry.get_all(&"motes"):
		if found is MoteKind:
			kinds.append(found as MoteKind)
	var motes: MotesScript = MotesScript.new(MoteCap.STOPS[-1], 0, kinds)
	root.add_child(motes)
	print("BENCH: motes: %d kinds, cap %d, FRAME_ROWS %d" % [motes.kinds().size(), motes.cap(), MotesScript.FRAME_ROWS])
	# Every chunk made once, so no first-use cost is timed.
	for c in ceili(float(motes.cap()) / MotesScript.CHUNK):
		motes.step(0.0)
		motes.burst(0, Vector2.ZERO, Vector2.RIGHT, MotesScript.CHUNK, Vector2(10.0, 50.0), 360.0, Vector2.ZERO, Vector2(0.2, 1.0), 0, Color.WHITE)
	motes.step(0.0)

	var best_shed: float = INF
	var rows_per_shed: float = 0.0
	for round in ROUNDS:
		var written: int = motes.written
		var usec: int = 0
		for n in CALLS:
			motes.step(0.0)
			var start: int = Time.get_ticks_usec()
			motes.shed(Vector2(100.0, 100.0), Vector2.RIGHT, Color(1.0, 0.6, 0.2), 0, LOOK, 0.5)
			usec += Time.get_ticks_usec() - start
		rows_per_shed = float(motes.written - written) / CALLS
		best_shed = minf(best_shed, float(usec) / CALLS)
	print("BENCH: motes: shed with rows left %.2f us a call, %.1f motes a call (%.2f us a mote)" % [best_shed, rows_per_shed, best_shed / maxf(rows_per_shed, 0.001)])

	var best_cut: float = INF
	for round in ROUNDS:
		motes.step(0.0)
		motes.burst(0, Vector2.ZERO, Vector2.RIGHT, MotesScript.FRAME_ROWS, Vector2(10.0, 50.0), 360.0, Vector2.ZERO, Vector2(0.2, 1.0), 0, Color.WHITE)
		var start: int = Time.get_ticks_usec()
		for n in CALLS:
			motes.shed(Vector2(100.0, 100.0), Vector2.RIGHT, Color(1.0, 0.6, 0.2), 0, LOOK, 0.5)
		best_cut = minf(best_cut, float(Time.get_ticks_usec() - start) / CALLS)
	print("BENCH: motes: shed with the frame's rows used up %.2f us a call" % best_cut)

	# The storm's timed pool (timed_motes.gd) adds its timer to every call: its own cost a call is
	# what it reads on a call that does next to nothing, less that call's cost here.
	var timed: TimedMotesScript = TimedMotesScript.new(MotesScript.CHUNK, 0, kinds)
	root.add_child(timed)
	timed.step(0.0)
	timed.burst(0, Vector2.ZERO, Vector2.RIGHT, MotesScript.FRAME_ROWS, Vector2(10.0, 50.0), 360.0, Vector2.ZERO, Vector2(0.2, 1.0), 0, Color.WHITE)
	var best_timer: float = INF
	for round in ROUNDS:
		var usec: int = timed.usec
		var calls: int = timed.calls
		for n in CALLS:
			timed.shed(Vector2(100.0, 100.0), Vector2.RIGHT, Color(1.0, 0.6, 0.2), 0, LOOK, 0.5)
		best_timer = minf(best_timer, float(timed.usec - usec) / float(timed.calls - calls))
	print("BENCH: motes: the storm's timed pool reads %.2f us a call on a shed with the frame's rows used up: its timer's own cost is about %.2f us a call" % [best_timer, best_timer - best_cut])
	timed.free()

	var best_row: float = INF
	for round in ROUNDS:
		motes.step(0.0)
		var start: int = Time.get_ticks_usec()
		motes.burst(1, Vector2.ZERO, Vector2.RIGHT, MotesScript.FRAME_ROWS, Vector2(10.0, 50.0), 360.0, Vector2(0.0, 20.0), Vector2(0.2, 1.0), 0, Color.WHITE)
		best_row = minf(best_row, float(Time.get_ticks_usec() - start) / MotesScript.FRAME_ROWS)
	print("BENCH: motes: burst %.3f us a mote" % best_row)

	# S4: a burst of each of the storm's sizes, a call (a row a mote on main; a row a burst of
	# BURST_QUADS with burst rows).
	var sizes: String = ""
	for size: int in [1, 3, 6, 10, 32, 100]:
		var best_size: float = INF
		for round in ROUNDS:
			var usec: int = 0
			for n in CALLS / 10:
				motes.step(0.0)
				var start: int = Time.get_ticks_usec()
				motes.burst(1, Vector2(100.0, 100.0), Vector2.RIGHT, size, Vector2(10.0, 50.0), 140.0, Vector2(0.0, 20.0), Vector2(0.2, 1.0), 0, Color.WHITE, 4.0)
				usec += Time.get_ticks_usec() - start
			best_size = minf(best_size, float(usec) / float(CALLS / 10))
		sizes += "%d: %.2f us, " % [size, best_size]
	print("BENCH: motes: a burst of n motes a call: %s" % sizes.trim_suffix(", "))

	var best_upload: float = INF
	for round in ROUNDS:
		motes.step(0.0)
		motes.burst(1, Vector2.ZERO, Vector2.RIGHT, MotesScript.FRAME_ROWS, Vector2(10.0, 50.0), 360.0, Vector2(0.0, 20.0), Vector2(0.2, 1.0), 0, Color.WHITE)
		var uploads: int = motes.uploads
		var start: int = Time.get_ticks_usec()
		motes.step(0.0)
		best_upload = minf(best_upload, float(Time.get_ticks_usec() - start) / maxf(1.0, float(motes.uploads - uploads)))
	print("BENCH: motes: step %.1f us a chunk uploaded (%d rows a chunk)" % [best_upload, MotesScript.CHUNK])
	motes.free()
	registry.free()
	quit(0)
