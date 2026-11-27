extends "res://tests/support/screenshot.gd"
## What live beams cost to draw (the owner, 2026-11-27; gameplay/feel/beam_union.gd): 1, 6, 16 and
## 46 beams held on (fans of +2 and +3 from up to eight hands, crossing), each count drawn for
## FRAMES frames after it settles. Prints, a count a line, `BENCH: beams N`: the beams on, Feel's
## milliseconds a frame (its whole step, `Feel.profile_parts`), the draw calls a frame
## (`RenderingServer`) and the GPU's milliseconds a frame (the viewport's measured render time). Not
## run in the build: it needs a display (a virtual one, llvmpipe, stands in, slower).
##
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --rendering-method gl_compatibility \
##     --script res://tests/benchmark/beam_cost.gd          the web's renderer (mobile: the desktop's)

const ActorSeats := preload("res://tests/support/actor_seats.gd")
const STARTER := preload("res://content/wizard/staffs/curl/curl.tres")
const COUNTS: Array[int] = [1, 6, 16, 46]
const FRAMES: int = 120
## The hands the casts come from (world pixels) and the point they all aim near.
const HANDS: Array[Vector2] = [Vector2(60, 60), Vector2(60, 300), Vector2(580, 60), Vector2(580, 300), Vector2(320, 20), Vector2(320, 340), Vector2(40, 180), Vector2(600, 180)]


func take() -> void:
	if not need(["Spells", "Projectiles", "Feel"]):
		return
	draw_between = true
	_set_drawing(true)
	var spells: Node = root.get_node("Spells")
	var feel: Node = root.get_node("Feel")
	root.get_node("Projectiles").call("set_bounds", Rect2(Vector2.ZERO, SCREEN))
	var actors: ActorSeats.ActorsScript = ActorSeats.autoload()
	var wizards: PackedInt32Array = ActorSeats.seat_wizards(actors, 4)
	var camera := Camera2D.new()
	camera.zoom = Vector2(2.0, 2.0)
	camera.position = SCREEN * 0.5
	root.add_child(camera)
	camera.make_current()
	var viewport: RID = root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(viewport, true)
	feel.call(&"profile_parts", Time.get_ticks_usec)
	for count: int in COUNTS:
		spells.call("clear")
		var casts: Array = _casts(count)
		for n in casts.size():
			var cards: Array[StringName] = []
			cards.assign(casts[n])
			spells.call("install_staff", wizards[n % 4], n / 4, spells.call("compile_staff", cards, STARTER))
		await settle(4)
		var feel_usec: int = 0
		var beams_usec: int = 0
		var calls: int = 0
		var gpu: float = 0.0
		var on: int = 0
		for frame in FRAMES + 20:
			# Held: every staff casts again whenever it may, so its beams stay on.
			for n in casts.size():
				var from: Vector2 = HANDS[n % HANDS.size()]
				spells.call("cast_staff", wizards[n % 4], n / 4, from, from.direction_to(SCREEN * 0.5 + Vector2(0, (n % 3 - 1) * 40)), 100.0)
			var profile: PackedInt64Array = feel.get(&"step_profile")
			profile.fill(0)
			feel.set(&"step_profile", profile)
			await RenderingServer.frame_post_draw
			if frame < 20:
				continue
			var parts: PackedInt64Array = feel.get(&"step_profile")
			for part: int in parts:
				feel_usec += part
			beams_usec += parts[1]
			calls += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
			gpu += RenderingServer.viewport_get_measured_render_time_gpu(viewport)
			on += CarrierBeam.of(spells).beam_count()
		print("BENCH: beams %d: on %.1f, feel %.3f ms (its beams, flashes and markers %.3f ms), draw calls %.1f, gpu %.3f ms" % [count, float(on) / FRAMES, feel_usec / 1000.0 / FRAMES, beams_usec / 1000.0 / FRAMES, float(calls) / FRAMES, gpu / FRAMES])


## The casts that make `count` beams: fans of +2 and +3 (six beams at most a cast), the cards each.
func _casts(count: int) -> Array:
	var casts: Array = []
	var left: int = count
	while left > 0:
		var beams: int = mini(left, 6)
		left -= beams
		var cards: Array[StringName] = [&"hold"]
		var extra: int = beams - 1
		while extra >= 3 and extra != 4:
			cards.append(&"plus_three")
			extra -= 3
		while extra >= 2:
			cards.append(&"plus_two")
			extra -= 2
		if extra == 1:
			# No +1: a fan of two is cast as two beams.
			casts.append([&"hold", &"beam"])
		cards.append(&"beam")
		casts.append(cards)
	return casts
