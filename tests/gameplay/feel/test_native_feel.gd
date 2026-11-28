extends "res://tests/support/suite.gd"
## Feel's native loops (`MoteKernel`, native/src/feel_loops.cpp) against their GDScript. The
## flashes: two Feels' flashes with the same slots, one finding the special slots and writing the rows with the
## kernel and one without (`FeelFlashes.use_native`), are aged frame after frame with the same seeded flashes: every kind
## (the flare kinds, arcs, statuses, both explosions, table kinds on and off the floor), arcs'
## lengths, the floor's flag, slots aged already by the special step, slots ending, the ring's start
## anywhere. After every frame every array the loops write (the five batches, the ages, the seconds,
## the aged marks, the special list and the row counts) must be equal byte for byte. And the
## world's stirs and a room's mist parting (the tests below).
##
## Without the native module the test only says so (SPELLMERGE_NATIVE=required fails it).
const FeelScript := preload("res://gameplay/feel/feel.gd")
const NativeScript := preload("res://core/native/native.gd")
const StirsScript := preload("res://gameplay/feel/stirs.gd")
const MistPartingScript := preload("res://gameplay/feel/mist_parting.gd")
const ProjectilesScript := preload("res://core/projectiles/projectile_manager.gd")
const EventsScript := preload("res://core/events/events.gd")
const FeelPresetScript := preload("res://gameplay/feel/presets/feel_preset.gd")
const ActorSeats := preload("res://tests/support/actor_seats.gd")

const SLOTS: int = 256
const FRAMES: int = 40
## The arrays compared after every frame.
const WRITTEN: Array[StringName] = [&"_flash_buffer", &"_arc_buffer", &"_status_buffer", &"_floor_buffer", &"_blast_buffer", &"_flash_age", &"_flash_seconds", &"_flash_aged", &"_flash_row_counts"]


## A Feel (not in the tree: no batches) whose flash job runs the kernel or not, its slots' arrays
## sized in place (as `_size_flashes` sizes them).
func _side(native: bool) -> FeelFlashes:
	var feel: Node = own(FeelScript.new())
	var flashes: FeelFlashes = feel.get(&"_job_flashes") as FeelFlashes
	flashes.use_native(native)
	for buffer: PackedFloat32Array in [flashes._flash_buffer, flashes._arc_buffer, flashes._status_buffer, flashes._floor_buffer, flashes._blast_buffer]:
		buffer.resize(SLOTS * FeelScript.FLASH_STRIDE)
	for each: Variant in [flashes._flash_kind, flashes._flash_zoom, flashes._flash_special_slots, flashes._flash_age, flashes._flash_seconds,
			flashes._flash_length, flashes._flash_light, flashes._flash_floor, flashes._flash_aged, flashes._flash_special,
			flashes._flash_at, flashes._flash_dir, flashes._flash_core, flashes._flash_look_color]:
		each.resize(SLOTS)
	# Table rows 0 and 2 on the floor.
	flashes._table_floor.resize(4)
	flashes._table_floor[0] = 1
	flashes._table_floor[2] = 1
	return flashes


## Slot `slot` of both sides given the same new flash.
func _show(sides: Array[FeelFlashes], slot: int, rng: RandomNumberGenerator) -> void:
	var kinds: PackedInt32Array = PackedInt32Array([0, 3, 7, 13, FeelScript.KIND_ARC, FeelScript.KIND_STATUS, FeelScript.KIND_SHELL, FeelScript.KIND_FIREBALL, FeelScript.FLASH_TABLE, FeelScript.FLASH_TABLE + 1, FeelScript.FLASH_TABLE + 2])
	var kind: int = kinds[rng.randi_range(0, kinds.size() - 1)]
	var dir := Vector2.from_angle(rng.randf_range(-PI, PI))
	var at := Vector2(rng.randf_range(-900.0, 900.0), rng.randf_range(-600.0, 600.0)).round()
	var zoom: int = rng.randi_range(1, 40)
	var seconds: float = rng.randf_range(0.01, 0.9)
	var length: float = float(rng.randi_range(1, 50)) * 4.0 if kind == FeelScript.KIND_ARC or rng.randf() < 0.1 else 0.0
	var core := Color(rng.randf(), rng.randf(), rng.randf(), 1.0)
	var look := Color(rng.randf(), rng.randf(), rng.randf(), rng.randf())
	var light: float = rng.randf_range(0.0, 2.0) if rng.randf() < 0.5 else 0.0
	var on_floor: int = 1 if rng.randf() < 0.2 else 0
	var special: int = 1 if rng.randf() < 0.15 else 0
	var age: float = rng.randf_range(0.0, seconds) if rng.randf() < 0.3 else 0.0
	for side in sides:
		side._flash_kind[slot] = kind
		side._flash_dir[slot] = dir
		side._flash_at[slot] = at
		side._flash_zoom[slot] = zoom
		side._flash_seconds[slot] = seconds
		side._flash_age[slot] = age
		side._flash_length[slot] = length
		side._flash_light[slot] = light
		side._flash_core[slot] = core
		side._flash_look_color[slot] = look
		side._flash_floor[slot] = on_floor
		side._flash_special[slot] = special
		side._flash_aged[slot] = 0


func _compare(a: FeelFlashes, b: FeelFlashes, found_a: int, found_b: int, when: String) -> bool:
	var same: bool = found_a == found_b
	check(same, "%s: special slots found %d and %d" % [when, found_a, found_b])
	var listed_a: PackedInt32Array = a._flash_special_slots.slice(0, found_a)
	var listed_b: PackedInt32Array = b._flash_special_slots.slice(0, found_b)
	if listed_a != listed_b:
		check(false, "%s: the special slots differ" % when)
		same = false
	for name: StringName in WRITTEN:
		var bytes_a: PackedByteArray = var_to_bytes(a.get(name))
		var bytes_b: PackedByteArray = var_to_bytes(b.get(name))
		if bytes_a != bytes_b:
			check(false, "%s: %s differs" % [when, name])
			same = false
	return same


func test_the_kernel_writes_the_flashes_rows_as_the_gdscript_does() -> void:
	if not NativeScript.loaded():
		check(OS.get_environment("SPELLMERGE_NATIVE") != "required", "SPELLMERGE_NATIVE=required, but the native module is not loaded")
		return
	var a: FeelFlashes = _side(true)
	var b: FeelFlashes = _side(false)
	check(a.feel._flash_kernel != null, "the native side runs the kernel")
	check(b.feel._flash_kernel == null, "the other runs the GDScript")
	var sides: Array[FeelFlashes] = [a, b]
	var rng := RandomNumberGenerator.new()
	rng.seed = 2811
	for slot in SLOTS:
		if rng.randf() < 0.8:
			_show(sides, slot, rng)
	var rows: int = 0
	var ended: int = 0
	for frame in FRAMES:
		var delta: float = [1.0 / 60.0, 1.0 / 30.0, 0.0, 0.25, 1.0 / 144.0][frame % 5]
		var next_flash: int = rng.randi_range(0, SLOTS - 1)
		for n in rng.randi_range(0, 30):
			_show(sides, rng.randi_range(0, SLOTS - 1), rng)
		var found_a: int = int(a.feel._flash_kernel.call(&"find_special", a, SLOTS))
		var found_b: int = b._find_special(SLOTS)
		# The special step's part on the arrays (what the game says is GDScript's on both sides):
		# some slots aged already this frame.
		for k in found_b:
			var slot: int = b._flash_special_slots[k]
			if rng.randf() < 0.5:
				for side in sides:
					side._flash_age[slot] += delta
					side._flash_aged[slot] = 1
		var live_before: int = _live(b)
		a.feel._flash_kernel.call(&"write_rows", a, delta, next_flash, SLOTS)
		b._write_rows(delta, next_flash, SLOTS)
		ended += live_before - _live(b)
		var counts: PackedInt32Array = b._flash_row_counts
		rows += counts[0] + counts[1] + counts[2] + counts[3] + counts[4]
		if not _compare(a, b, found_a, found_b, "frame %d" % frame):
			return
	check(rows > 1000, "rows written: %d" % rows)
	check(ended > 50, "flashes ended: %d" % ended)
	var counts_seen: PackedInt32Array = b._flash_row_counts
	check(counts_seen[0] > 0 and counts_seen[1] > 0 and counts_seen[2] > 0 and counts_seen[3] > 0 and counts_seen[4] > 0, "every batch has rows: %s" % counts_seen)


func _live(flashes: FeelFlashes) -> int:
	var live: int = 0
	for seconds: float in flashes.get(&"_flash_seconds") as PackedFloat32Array:
		if seconds > 0.0:
			live += 1
	return live


## A frame's shot births (as the projectile manager's `spark_births`): `count` of them round the
## view's middle, some standing still (no way back), some outside the window.
func _births(rng: RandomNumberGenerator, middle: Vector2, count: int) -> PackedFloat32Array:
	var stride: int = ProjectilesScript.SPARK_BIRTH_STRIDE
	var births := PackedFloat32Array()
	births.resize(count * stride)
	for n in count:
		var i: int = n * stride
		var at: Vector2 = middle + Vector2(rng.randf_range(-900.0, 900.0), rng.randf_range(-600.0, 600.0))
		var back: Vector2 = Vector2.from_angle(rng.randf_range(-PI, PI)) * rng.randf_range(0.0, 12.0) if rng.randf() < 0.9 else Vector2(0.1, 0.2)
		births[i + ProjectilesScript.SPARK_X] = at.x
		births[i + ProjectilesScript.SPARK_Y] = at.y
		births[i + ProjectilesScript.SPARK_BACK_X] = back.x
		births[i + ProjectilesScript.SPARK_BACK_Y] = back.y
	return births


## The world's stirs' kernel against its GDScript (`Stirs.native`): two fields given the same births
## frame after frame (more than BIRTHS_READ, fewer, none, and with the setting off), a view moving
## by whole cells and more, and several frame lengths; after every frame every array, counter and
## the picture must be equal byte for byte.
func test_the_kernel_steps_the_stirs_as_the_gdscript_does() -> void:
	if not NativeScript.loaded():
		check(OS.get_environment("SPELLMERGE_NATIVE") != "required", "SPELLMERGE_NATIVE=required, but the native module is not loaded")
		return
	var a := StirsScript.new()
	var b := StirsScript.new()
	b.native = false
	check(a.get(&"_kernel") != null, "the native side runs the kernel")
	check(b.get(&"_kernel") == null, "the other runs the GDScript")
	var rng := RandomNumberGenerator.new()
	rng.seed = 2812
	var middle := Vector2(300.0, 200.0)
	var now: float = 1.0
	var most_live: int = 0
	for frame in 60:
		now += [1.0 / 60.0, 1.0 / 30.0, 0.0, 0.25, 1.0 / 144.0][frame % 5]
		middle += Vector2(rng.randf_range(-40.0, 40.0), rng.randf_range(-30.0, 30.0)) if frame % 7 != 3 else Vector2(900.0, 0.0)
		var count: int = [600, 120, 0, 256, 40][frame % 5]
		var births: PackedFloat32Array = _births(rng, middle, count)
		var on: bool = frame < 40 or frame % 3 != 0
		a.enabled = on
		b.enabled = on
		var view := Rect2(middle - Vector2(640.0, 360.0), Vector2(1280.0, 720.0))
		a.step(now, births, count, view)
		b.step(now, births, count, view)
		most_live = maxi(most_live, b.live_cells())
		for name: StringName in [&"_wake", &"_shown", &"_is_live", &"_point_at", &"_point_way", &"_point_next", &"_point_cell", &"_cell_first", &"_points", &"_live_count", &"read", &"_corner", &"origin", &"version", &"_image_dirty"]:
			if var_to_bytes(a.get(name)) != var_to_bytes(b.get(name)):
				check(false, "frame %d: %s differs" % [frame, name])
				return
		var live_a: PackedInt32Array = (a.get(&"_live") as PackedInt32Array).slice(0, a.live_cells())
		var live_b: PackedInt32Array = (b.get(&"_live") as PackedInt32Array).slice(0, b.live_cells())
		check(live_a == live_b, "frame %d: the live cells' list" % frame)
		check((a.get(&"_image") as Image).get_data() == (b.get(&"_image") as Image).get_data(), "frame %d: the picture" % frame)
	check(most_live > 100, "cells stirred: %d at most" % most_live)


## A room's mist parting's kernel against its GDScript (`MistParting.native`): two grids of a room
## (one wider than MOST_CELLS cells, so its cells are bigger) parted round the same feet frame after
## frame (walking, standing, leaving, one at no place), several frame lengths; after every frame
## every array, the live list and the picture must be equal byte for byte.
func test_the_kernel_parts_the_mist_as_the_gdscript_does() -> void:
	if not NativeScript.loaded():
		check(OS.get_environment("SPELLMERGE_NATIVE") != "required", "SPELLMERGE_NATIVE=required, but the native module is not loaded")
		return
	for size: Vector2 in [Vector2(640.0, 400.0), Vector2(2600.0, 900.0)]:
		var a := MistPartingScript.new()
		var b := MistPartingScript.new()
		b.native = false
		check(a.get(&"_kernel") != null, "the native side runs the kernel")
		check(b.get(&"_kernel") == null, "the other runs the GDScript")
		a.lay(size, Vector2(-120.0, 64.0))
		b.lay(size, Vector2(-120.0, 64.0))
		var rng := RandomNumberGenerator.new()
		rng.seed = 2813
		var feet := PackedVector2Array()
		feet.resize(24)
		for k in feet.size():
			feet[k] = Vector2(rng.randf_range(-150.0, size.x), rng.randf_range(40.0, size.y + 80.0))
		feet[5] = Vector2.INF
		var most_live: int = 0
		for frame in 80:
			for k in feet.size():
				if k != 5 and k % 3 != 0:
					feet[k] += Vector2(rng.randf_range(-6.0, 6.0), rng.randf_range(-4.0, 4.0))
			var delta: float = [1.0 / 60.0, 1.0 / 30.0, 0.0, 0.4, 1.0 / 144.0][frame % 5]
			var count: int = feet.size() if frame < 50 else 3
			a.work(delta, feet, count)
			b.work(delta, feet, count)
			most_live = maxi(most_live, b.live_cells())
			var same: bool = true
			for name: StringName in [&"_wanted", &"_shown", &"_is_live", &"_live_count", &"_dirty"]:
				if var_to_bytes(a.get(name)) != var_to_bytes(b.get(name)):
					check(false, "%s, frame %d: %s differs" % [size, frame, name])
					same = false
			var live_a: PackedInt32Array = (a.get(&"_live") as PackedInt32Array).slice(0, a.live_cells())
			var live_b: PackedInt32Array = (b.get(&"_live") as PackedInt32Array).slice(0, b.live_cells())
			if live_a != live_b or a.picture_data() != b.picture_data():
				check(false, "%s, frame %d: the live list or the picture differs" % [size, frame])
				same = false
			if not same:
				return
		check(most_live > 50, "%s: cells parted: %d at most" % [size, most_live])


## A flash shown in a Feel takes its look's instance colour once (`_flash_look_color`, as
## `ProjectileManager.look_color` of its ramp, zoom and look; an arc's after its zoom is its length),
## and is special only when it follows a body; resizing the slots clears what a slot held.
func test_a_shown_flash_takes_its_look_colour_once() -> void:
	var bus := EventsScript.new()
	var actors: Node = ActorSeats.table()
	var feel: Node = FeelScript.new()
	feel.set(&"events", bus)
	feel.set(&"actors", actors)
	feel.set(&"drive_engine", false)
	feel.set(&"preset", FeelPresetScript.new())
	root.add_child(feel)
	var flashes: FeelFlashes = feel.get(&"_job_flashes") as FeelFlashes
	var body := Node2D.new()
	root.add_child(body)
	var shown: Array[int] = [
		flashes._show_flash(0, Vector2(10.0, 20.0), Vector2.RIGHT, Color.WHITE, 2, 5, 3, 0.5),
		flashes._show_flash(FeelScript.KIND_ARC, Vector2(10.0, 20.0), Vector2.UP, Color.WHITE, 1, 0, 1, 0.5, 37.0),
		flashes._show_flash(FeelScript.KIND_STATUS, Vector2(0.0, 0.0), Vector2.RIGHT, Color.WHITE, 3, 9, 2, 0.5, 0.0, body),
	]
	for slot in shown:
		check(slot >= 0, "shown")
		var want: Color = ProjectilesScript.look_color(flashes._flash_ramp[slot], flashes._flash_zoom[slot], flashes._flash_look[slot])
		check_equal(flashes._flash_look_color[slot], want, "slot %d's look colour" % slot)
	check_equal(flashes._flash_special[shown[0]], 0, "a plain flash is not special")
	check_equal(flashes._flash_special[shown[2]], 1, "a followed one is")
	feel.step(1.0 / 60.0)
	check(flashes._flash_row_counts[FeelFlashes.ROWS_ARCS] == 1 and flashes._flash_row_counts[FeelFlashes.ROWS_STATUSES] == 1, "drawn: %s" % flashes._flash_row_counts)
	body.free()
	feel.step(1.0 / 60.0)
	check_equal(flashes._flash_row_counts[FeelFlashes.ROWS_STATUSES], 0, "a flash whose body is gone ends")
	feel.call(&"set_effect_slots", 64)
	check_equal(flashes._flash_special.count(1), 0, "new slots hold nothing special")
	check_equal(flashes._flash_aged.count(1), 0, "nor anything aged")
	feel.free()
	actors.free()
	bus.free()
