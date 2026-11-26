extends "res://tests/support/screenshot.gd"
## What a big oil fire costs (ART2, the owner's ask of 2026-11-26: the fire drawn mostly from motes;
## docs/milestones/oil-spill.md): in the crypt's first arena, a slick of oil SLICK_SIZE px across is
## laid round the room's middle and lit at five points, and once its fire has spread the frames are
## timed for MEASURE frames, with one player and with four (the screen split). It prints one `BENCH:
## oil fire` line each: the frame time (average and p95, the whole frame as drawn on this machine:
## compare runs on one machine only), the motes born a second (the pool's rows written), the mote
## chunks drawn and the floor's burning cells. Not a unit test; it gates nothing.
##
## xvfb-run -a godot --path . --fixed-fps 60 --script res://tests/benchmark/oil_fire.gd

const SLICK_SIZE := Vector2(320.0, 200.0)
const TOUCH_EVERY: float = 20.0
const SPREAD_FRAMES: int = 120
const MEASURE: int = 240


func _init() -> void:
	# It times the whole frame as drawn: the screen drawn every frame.
	draw_between = true


func take() -> void:
	if not need(["PlayerInput", "Flow", "Feel", "Events", "Cover"]):
		return
	for seats: int in [1, 4]:
		if not await _measure(seats):
			return
	print("OIL FIRE BENCH OK")


func _measure(seats: int) -> bool:
	var input: Node = root.get_node("PlayerInput")
	var flow: Node = root.get_node("Flow")
	var events: Node = root.get_node("Events")
	var feel: Node = root.get_node("Feel")
	flow.call("stop_run")
	await settle(5)
	for seat in seats:
		input.call("add_virtual_device", seat)
	if not flow.call("start_run", 0):
		fail("the run did not start")
		return false
	await settle(30)
	var wizard: Actor = flow.call("get_wizard", 0) as Actor
	if wizard == null:
		fail("no wizard")
		return false
	var middle: Vector2 = wizard.global_position + Vector2(120.0, 0.0)
	for seat in seats:
		var other: Actor = flow.call("get_wizard", seat) as Actor
		if other != null:
			Downed.of(other).protect(600.0)
	var y: float = -SLICK_SIZE.y * 0.5
	while y <= SLICK_SIZE.y * 0.5:
		var x: float = -SLICK_SIZE.x * 0.5
		while x <= SLICK_SIZE.x * 0.5:
			events.emit_signal("floor_touched", -1, &"oil", middle + Vector2(x, y), TOUCH_EVERY * 0.8, 0)
			x += TOUCH_EVERY
		y += TOUCH_EVERY
	await settle(30)
	for at: Vector2 in [Vector2.ZERO, Vector2(-120, -70), Vector2(120, -70), Vector2(-120, 70), Vector2(120, 70)]:
		events.emit_signal("floor_touched", -1, &"fire", middle + at, 0.0, 0)
	await settle(SPREAD_FRAMES)
	var pool: Object = (feel.call("spectacle") as Object).get("pool") as Object
	var cap: int = int(pool.call("cap"))
	var row: int = int(pool.call("next_row"))
	var born: int = 0
	var times := PackedFloat64Array()
	var chunks: int = 0
	var last: int = Time.get_ticks_usec()
	for frame in MEASURE:
		await process_frame
		var now: int = Time.get_ticks_usec()
		times.append(float(now - last) / 1000.0)
		last = now
		var next: int = int(pool.call("next_row"))
		born += posmod(next - row, cap)
		row = next
		chunks = maxi(chunks, int(pool.call("chunks_shown")))
	times.sort()
	var total: float = 0.0
	for t in times:
		total += t
	var burning: int = _burning_cells()
	print("BENCH: oil fire %dp: frame avg %.2f ms, p95 %.2f ms; motes born %.0f/s; chunks drawn %d; burning cells %d" % [seats, total / times.size(), times[int(times.size() * 0.95)], float(born) / (float(MEASURE) / 60.0), chunks, burning])
	await shot("oil_fire_bench_%dp" % seats)
	return true


## The floor's cells burning now (any state with fire's flat surface).
func _burning_cells() -> int:
	var cover: Node = root.get_node("Cover")
	var layout: CoverLayout = cover.get("layout") as CoverLayout
	if layout == null:
		return 0
	var count: int = 0
	for cell in layout.columns * layout.rows:
		var state: CoverState = cover.call("cover_state_at", cell)
		if state != null and state.state_id in [&"catching", &"burning"]:
			count += 1
	return count
