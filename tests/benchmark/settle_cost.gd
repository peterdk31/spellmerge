extends SceneTree
## What settled motes cost the CPU (docs/milestones/spell-spectacle.md, P2b; the integration of
## P1c, P1d and P2b in docs/DECISIONS.md): a storm-like frame of chip bursts with and without a mark
## layer to settle into (the difference is SETTLE_ROWS' worth of settles), the trails' `give_off`
## per birth, and the mark layer's step per settled mote it stamps. Prints `BENCH: settle` lines.
## Not a unit test.
##
## godot --headless --path . --script res://tests/benchmark/settle_cost.gd

const MotesScript := preload("res://gameplay/feel/mote.gd")
const MarksScript := preload("res://gameplay/feel/marks.gd")
const RegistryScript := preload("res://core/registry/registry.gd")

const ROUNDS: int = 7


func _initialize() -> void:
	await process_frame
	var registry: RegistryScript = RegistryScript.new()
	registry.scan()
	var kinds: Array[MoteKind] = []
	for found: Resource in registry.get_all(&"motes"):
		if found is MoteKind:
			kinds.append(found as MoteKind)
	var mark_kinds: Array[MarkKind] = []
	for found: Resource in registry.get_all(&"marks"):
		if found is MarkKind:
			mark_kinds.append(found as MarkKind)
	var motes: MotesScript = MotesScript.new(MoteCap.STOPS[-1], 0, kinds)
	root.add_child(motes)
	var marks: MarksScript = MarksScript.new(-1, mark_kinds)
	root.add_child(marks)
	marks.enter(Rect2(0.0, 0.0, 1344.0, 784.0), null, 16.0)
	var chip: int = motes.kind_index(&"chip")
	for c in ceili(float(motes.cap()) / MotesScript.CHUNK):
		motes.step(0.0)
		motes.burst(chip, Vector2(200, 200), Vector2.RIGHT, MotesScript.CHUNK, Vector2(10.0, 50.0), 360.0, Vector2.ZERO, Vector2(0.2, 1.0), 0, Color.WHITE)
	var k: MoteKind = motes.kinds()[chip]
	var clock: float = 1.0
	for with_marks in [false, true]:
		motes.settle_into(marks if with_marks else null)
		var best: float = INF
		for round in ROUNDS:
			clock += 0.1
			marks.step(clock)
			motes.step(clock)
			var start: int = Time.get_ticks_usec()
			for n in 28:
				motes.burst(chip, Vector2(200, 200), Vector2.RIGHT, 10, k.speed, k.spread, k.up, k.life, 16, Color.WHITE, k.height)
			best = minf(best, float(Time.get_ticks_usec() - start))
		print("BENCH: settle: a frame of 28 bursts of 10 chips %s marks %.1f us (settling %d)" % ["with" if with_marks else "without", best, marks.settling()])
	# A frame of trail births (as give_off is handed them).
	var given := PackedFloat32Array()
	given.resize(64 * MotesScript.BIRTH_STRIDE)
	for n in 64:
		given[n * MotesScript.BIRTH_STRIDE + 2] = -1.0
		given[n * MotesScript.BIRTH_STRIDE + 4] = float(n % 6)
		given[n * MotesScript.BIRTH_STRIDE + 7] = 1.0
	var best_give: float = INF
	for round in ROUNDS:
		clock += 0.1
		motes.step(clock)
		var start: int = Time.get_ticks_usec()
		motes.give_off(given, 64)
		best_give = minf(best_give, float(Time.get_ticks_usec() - start) / 64.0)
	print("BENCH: settle: give_off %.3f us a birth" % best_give)
	# The mark layer's step: stamping what is due and drawing it.
	var best_step: float = INF
	for round in ROUNDS:
		marks.clear()
		marks.step(clock)
		for n in 28:
			motes.burst(chip, Vector2(200, 200), Vector2.RIGHT, 10, k.speed, k.spread, k.up, k.life, 16, Color.WHITE, k.height)
		var waiting: int = marks.settling()
		clock += 5.0
		var start: int = Time.get_ticks_usec()
		marks.step(clock)
		var took: float = float(Time.get_ticks_usec() - start)
		best_step = minf(best_step, took / maxf(1.0, float(waiting)))
		motes.step(clock)
	print("BENCH: settle: the mark layer's step %.3f us a settled mote" % best_step)
	motes.free()
	marks.free()
	registry.free()
	quit(0)
