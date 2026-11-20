extends "res://tests/support/suite.gd"
## The room's low floor mist (docs/milestones/atmosphere.md, F): a room names it (`RoomBase.mist`, a
## `RoomMist`; none by default), checked with the room; Feel draws it (gameplay/feel/mist.gd) over the
## floor, the marks and the bodies' shadows and under every body and the spell light's apply rect,
## thin over the middle and thicker toward the room's edge and its pits (`mist_mask.gd`), parted by
## the bodies' feet (`mist_parting.gd`, opening and closing over frames), pushed by the world's stirs,
## lit by the light buffer, only while spell light is on; a frame makes no object. How it looks is
## checked by eye (tests/screenshots/shot_atmosphere_mist.gd): headless runs compile no shader.

const MistScript := preload("res://gameplay/feel/mist.gd")
const MistMaskScript := preload("res://gameplay/feel/mist_mask.gd")
const MistPartingScript := preload("res://gameplay/feel/mist_parting.gd")
const StirsScript := preload("res://gameplay/feel/stirs.gd")
const SpectacleScript := preload("res://gameplay/feel/spectacle.gd")
const SpellLightScript := preload("res://gameplay/feel/spell_light.gd")
const WarmupScript := preload("res://core/projectiles/shader_warmup.gd")
const EventsScript := preload("res://core/events/events.gd")
const FeelScript := preload("res://gameplay/feel/feel.gd")
const FeelPresetScript := preload("res://gameplay/feel/presets/feel_preset.gd")
const RegistryScript := preload("res://core/registry/registry.gd")
const ProjectilesScript := preload("res://core/projectiles/projectile_manager.gd")
const ActorSeats := preload("res://tests/support/actor_seats.gd")

const FRAME: float = 1.0 / 60.0
const CRYPT_ROOMS: Array[StringName] = [&"arena_01", &"arena_02", &"arena_03", &"arena_04", &"boss_broom"]
## A test room: 320 x 160, walled round by 16 px with the void outside them, a low wall in its middle
## and a pit by its right side.
const SIZE := Vector2(320.0, 160.0)

var registry: RegistryScript


func before_each() -> void:
	registry = own(RegistryScript.new()) as RegistryScript
	registry.scan()


## The test room's walls: a ring 16 px thick, 16 px in from its edge (the void outside it), and a low
## wall standing in its middle.
func _walls() -> Array[Rect2]:
	return [Rect2(16, 16, 288, 16), Rect2(16, 128, 288, 16), Rect2(16, 16, 16, 128), Rect2(288, 16, 16, 128), Rect2(144, 72, 32, 16)] as Array[Rect2]


func _holes() -> Array[Rect2]:
	return [Rect2(240, 64, 24, 32)] as Array[Rect2]


func _texel(image: Image, at: Vector2) -> Color:
	var cell: float = MistMaskScript.cell_of(SIZE)
	return image.get_pixel(floori(at.x / cell), floori(at.y / cell))


## A mist node laid in the test room with a mist, in the tree.
func _mist() -> MistScript:
	var mist: MistScript = own(MistScript.new(SpectacleScript.MARK_Z)) as MistScript
	root.add_child(mist)
	mist.lay(SIZE, _walls(), _holes())
	mist.use(RoomMist.new())
	return mist


# --- The data -------------------------------------------------------------------------------------

func test_a_room_has_no_mist_by_default_and_its_mist_is_checked() -> void:
	var room := RoomBase.new()
	room.id = &"test_room"
	check(room.mist == null, "a room has no mist by default: it is as it was")
	check_equal(room.template_problems([] as Array[StringName]), PackedStringArray(), "no mist, no problem")
	room.mist = RoomMist.new()
	check_equal(room.mist.problems("test_room"), PackedStringArray(), "the defaults are sound")
	check_equal(room.template_problems([] as Array[StringName]), PackedStringArray(), "a sound mist is no problem of the room's")
	for bad: Array in [["thickness", 0.0], ["thickness", 0.9], ["middle", 1.5], ["edge_reach", 400.0], ["pit_share", -1.0], ["spill", 90.0], ["scale", 4.0], ["drift", Vector2(90.0, 0.0)], ["lit", 3.0], ["in_dark", NAN]]:
		var mist := RoomMist.new()
		mist.set(bad[0] as String, bad[1])
		room.mist = mist
		check(" ".join(room.template_problems([] as Array[StringName])).contains("test_room's mist"), "a mist with %s %s is a problem of the room's" % bad)


func test_the_crypt_has_a_cool_mist_the_boss_hall_a_thicker_one() -> void:
	var shared: RoomMist = (registry.get_resource(&"rooms", &"arena_01") as RoomBase).mist
	check(shared != null, "the crypt's rooms have a mist")
	for id in CRYPT_ROOMS:
		var room := registry.get_resource(&"rooms", id) as RoomBase
		check(room.mist != null and room.mist.problems(String(id)).is_empty(), "%s's mist is sound" % id)
		if id != &"boss_broom":
			check(room.mist == shared, "%s shares the crypt's mist" % id)
	var boss: RoomMist = (registry.get_resource(&"rooms", &"boss_broom") as RoomBase).mist
	check(boss != shared and boss.thickness > shared.thickness, "the boss hall's mist is its own, thicker")
	check(shared.colour.b > shared.colour.r, "the crypt's mist is cool")
	check(shared.middle <= 0.25, "thin over the fight's middle (rule 6)")
	check((registry.get_resource(&"rooms", &"hub") as RoomBase).mist == null, "the hub has none")


# --- Where it lies --------------------------------------------------------------------------------

func test_the_mask_thickens_toward_the_edge_and_the_pit_not_a_low_wall() -> void:
	var image: Image = MistMaskScript.build(SIZE, _walls(), _holes())
	check_equal(image.get_format(), Image.FORMAT_RGBA8, "RGBA8: filtered on every renderer")
	var by_edge: Color = _texel(image, Vector2(80, 36))
	var inside: Color = _texel(image, Vector2(80, 64))
	check(by_edge.r < inside.r, "nearer the room's edge is nearer (red %.2f < %.2f)" % [by_edge.r, inside.r])
	var by_low_wall: Color = _texel(image, Vector2(160, 92))
	check(by_low_wall.r > by_edge.r * 2.0, "a low wall standing in the room is no edge: thin over the fight")
	check(_texel(image, Vector2(160, 80)).r > by_edge.r * 2.0, "nor its own cells")
	check_equal(_texel(image, Vector2(250, 80)).g, 0.0, "over the pit itself it is thickest")
	check(_texel(image, Vector2(228, 80)).g < _texel(image, Vector2(80, 80)).g, "nearer the pit, thicker")
	var in_wall: Color = _texel(image, Vector2(80, 24))
	check(in_wall.b > 0.0, "a wall: none of it but its spill")
	var outer: Color = _texel(image, Vector2(4, 4))
	check(outer.b > in_wall.b, "the void outside the walls is wall, deeper still: no mist over the dark")
	check_equal(_texel(image, Vector2(80, 64)).b, 0.0, "open floor holds no spill")


func test_a_low_walls_rim_is_read_as_thin_as_the_floor_round_it() -> void:
	var image: Image = MistMaskScript.build(SIZE, _walls(), _holes())
	var cell: float = MistMaskScript.cell_of(SIZE)
	# The low wall's top edge cell and the open cell above it: the shader reads between them.
	var in_block: Color = image.get_pixel(floori(160.0 / cell), floori(72.0 / cell))
	var above: Color = image.get_pixel(floori(160.0 / cell), floori(72.0 / cell) - 1)
	var between: float = (in_block.r + above.r) * 0.5
	check(in_block.r > 0.0, "a low wall's own cells hold how far they are from the edge, not 0")
	check(between > above.r * 0.85, "read between the wall and the floor it is as thin as the floor (%.2f, %.2f)" % [between, above.r])
	check_equal(_texel(image, Vector2(4, 4)).r, 0.0, "the void is the edge itself")


func test_the_hubs_sea_of_holes_is_void_not_a_pit() -> void:
	# An island in a sea of holes (the hub's), with a pit inside it.
	var sea: Array[Rect2] = [Rect2(0, 0, 320, 24), Rect2(0, 136, 320, 24), Rect2(0, 0, 24, 160), Rect2(296, 0, 24, 160), Rect2(150, 70, 20, 20)]
	var image: Image = MistMaskScript.build(SIZE, [] as Array[Rect2], sea)
	var over_sea: Color = _texel(image, Vector2(8, 80))
	check(over_sea.b > 0.0, "the sea round the island is void: none of the mist but its spill")
	check(over_sea.g > 0.0, "and no pit for the mist to pour into")
	check_equal(_texel(image, Vector2(160, 80)).g, 0.0, "a pit inside the island stays a pit")
	check(_texel(image, Vector2(32, 80)).r < _texel(image, Vector2(80, 80)).r, "the island's edge is its edge")


func test_every_crypt_room_and_the_hub_have_a_void_round_them() -> void:
	var rooms: Array[StringName] = CRYPT_ROOMS.duplicate()
	rooms.append(&"hub")
	for id in rooms:
		var room := registry.get_resource(&"rooms", id) as RoomBase
		var layout: Node = own(room.build(null)) as Node
		var places: RoomPlaces = RoomPlaces.read(layout)
		var image: Image = MistMaskScript.build(places.size, RoomPlaces.wall_rects(layout), places.holes)
		check(image.get_pixel(0, 0).b > 0.0, "%s: the dark outside its slab is void (the flood ran)" % id)
		var deepest: float = 0.0
		for y in image.get_height():
			for x in image.get_width():
				var texel: Color = image.get_pixel(x, y)
				if texel.b > 0.0:
					deepest = maxf(deepest, texel.r)
		if id in [&"arena_02", &"arena_03", &"arena_04"]:
			check(deepest > 0.3, "%s: its low walls are no edge (%.2f from it)" % [id, deepest])
		if id in [&"arena_02", &"arena_04"]:
			var box: Rect2 = places.holes[0]
			for hole in places.holes:
				box = box.merge(hole)
			var cell: float = MistMaskScript.cell_of(places.size)
			check_equal(image.get_pixel(floori(box.get_center().x / cell), floori(box.get_center().y / cell)).g, 0.0, "%s: its pit stays a pit" % id)


## Most of the crypt's templates draw their slab's dark as walls out to their rectangle's edge (no
## open cell or hole at the edge): their void is the walls joined to the edge, and a low wall standing
## free in the room is still no edge (playtest, 2026-11-20: 11 templates warned on every run and their
## mist thickened round every pillar).
func test_a_room_walled_to_its_edge_finds_its_void_in_its_rim() -> void:
	var walls: Array[Rect2] = [Rect2(0, 0, 320, 32), Rect2(0, 128, 320, 32), Rect2(0, 0, 32, 160), Rect2(288, 0, 32, 160), Rect2(144, 72, 32, 16)]
	check(MistMaskScript.finds_void(SIZE, walls, [] as Array[Rect2]), "the rim joined to the edge is its void")
	var image: Image = MistMaskScript.build(SIZE, walls, [] as Array[Rect2], true)
	var by_edge: Color = _texel(image, Vector2(80, 36))
	check(_texel(image, Vector2(160, 92)).r > by_edge.r * 2.0, "a low wall standing in the room is no edge: thin over the fight")
	check(_texel(image, Vector2(160, 80)).r > by_edge.r * 2.0, "nor its own cells")
	check_equal(_texel(image, Vector2(4, 4)).r, 0.0, "the rim is the edge itself")


func test_every_room_with_a_mist_finds_its_void_in_every_mirroring() -> void:
	var checked: int = 0
	for item: Resource in registry.get_all(&"rooms"):
		var room := item as RoomBase
		if room == null or room.walkway or room.scene == null or room.mist == null:
			continue
		var size: Vector2 = room.places().size
		for mirror in 4:
			var shape: PieceShape = PieceShape.of_room(room, mirror)
			check(MistMaskScript.finds_void(size, shape.walls, shape.holes), "%s (mirrored %d): its mist finds the void round its slab" % [room.id, mirror])
		checked += 1
	check(checked > CRYPT_ROOMS.size(), "the crypt's rooms with a mist are checked (%d)" % checked)


func test_the_mask_of_a_room_open_to_its_edge_measures_from_the_edge() -> void:
	var image: Image = MistMaskScript.build(SIZE, [] as Array[Rect2], [] as Array[Rect2])
	check(_texel(image, Vector2(4, 80)).r < _texel(image, Vector2(80, 80)).r, "no walls: the room's own edge is its edge")
	check_equal(_texel(image, Vector2(4, 80)).b, 0.0, "and nothing is wall")


func test_a_big_room_is_masked_by_bigger_cells() -> void:
	check_equal(MistMaskScript.cell_of(Vector2(640, 384)), MistMaskScript.CELL, "a room of the crypt by CELL")
	var hub := Vector2(4000.0, 1000.0)
	var image: Image = MistMaskScript.build(hub, [] as Array[Rect2], [] as Array[Rect2])
	check(image.get_width() <= MistMaskScript.MOST_CELLS, "never more than MOST_CELLS a side")


## A biome's room stands at its place, often mirrored (connected biomes; the mirrored art's fix, #851):
## the mist lies over it there, its mask of the walls and holes as mirrored where they stand, and the
## bodies part it where they walk.
func test_a_room_laid_away_from_the_origin_and_mirrored_has_its_mist_where_it_stands() -> void:
	var made: Array = _feel()
	var bus: EventsScript = made[0]
	var feel: FeelScript = made[1]
	var spectacle: SpectacleScript = feel.spectacle()
	var room := registry.get_resource(&"rooms", &"arena_04") as RoomBase
	var place := Vector2(640.0, 352.0)
	var layout := own(room.build(null)) as Node2D
	layout.position = place
	layout.set_meta(PieceShape.GROUND_MIRROR_META, Vector2i(1, 1))
	bus.spell_light_changed.emit(true)
	bus.room_built.emit(room.id, 0, layout)
	bus.room_entered.emit(room.id, 0)
	var mist: MistScript = spectacle.mist
	check(mist != null, "spell light on: the mist is made")
	if mist == null:
		return
	check_equal(mist.position, place, "the mist lies at the room's place")
	check_equal(mist.room_origin, place, "its origin the room's")
	check_equal((mist.material as ShaderMaterial).get_shader_parameter(&"origin"), place, "and the shader reads its mask from there")
	var size: Vector2 = room.places().size
	var shape: PieceShape = PieceShape.of_room(room, PieceShape.MIRROR_X | PieceShape.MIRROR_Y)
	var mirrored: Image = MistMaskScript.build(size, shape.walls, shape.holes, true)
	check(mist.mask.get_image().get_data() == mirrored.get_data(), "its mask is of the walls and holes mirrored as the room stands (in its own px)")
	var unmirrored: PieceShape = PieceShape.of_room(room)
	check(MistMaskScript.build(size, unmirrored.walls, unmirrored.holes, true).get_data() != mirrored.get_data(), "(the template's own mask differs: the room is not symmetric)")
	var foot: Vector2 = place + size * 0.5
	for frame in 12:
		spectacle.hand_bodies(PackedVector2Array([foot]), 1)
		spectacle.step(10.0 + float(frame) * FRAME)
	check(mist.parting.parted_at(foot + Vector2(0.0, MistPartingScript.FEET_DROP)) > 0.5, "a body parts it where it stands in the world")
	check_equal(mist.parting.parted_at(size * 0.5 + Vector2(0.0, MistPartingScript.FEET_DROP)), 0.0, "not at the world's origin")


## The owner, 2026-11-19: every room of a biome draws its own mist, where it stands and mirrored as it
## is; made and freed with the first room's (spell light and "Fog"), gone with a new world.
func test_every_room_of_a_biome_draws_its_own_mist_where_it_stands() -> void:
	var made: Array = _feel()
	var bus: EventsScript = made[0]
	var feel: FeelScript = made[1]
	var spectacle: SpectacleScript = feel.spectacle()
	var first := registry.get_resource(&"rooms", &"arena_04") as RoomBase
	var later := registry.get_resource(&"rooms", &"arena_01") as RoomBase
	bus.spell_light_changed.emit(true)
	bus.room_built.emit(first.id, 0, own(first.build(null)) as Node)
	bus.room_entered.emit(first.id, 0)
	var place := Vector2(960.0, 320.0)
	var layout := own(later.build(null)) as Node2D
	layout.position = place
	layout.set_meta(PieceShape.GROUND_MIRROR_META, Vector2i(1, 0))
	bus.room_built.emit(later.id, 3, layout)
	check_equal(spectacle.room_mists.size(), 1, "the later room's own mist")
	if spectacle.room_mists.is_empty():
		return
	var own_mist: MistScript = spectacle.room_mists[0]
	check(own_mist.visible and own_mist.mist == later.mist, "drawn, with its room's mist")
	check_equal(own_mist.position, place, "where the room stands")
	var shape: PieceShape = PieceShape.of_room(later, PieceShape.MIRROR_X)
	check(own_mist.mask.get_image().get_data() == MistMaskScript.build(later.places().size, shape.walls, shape.holes, true).get_data(), "its mask the room's as mirrored")
	var children: Array[Node] = spectacle.get_children()
	check(children.find(own_mist) > children.find(spectacle.shadows), "over the shadows, as the first room's")
	var walkway: RoomBase = null
	for item: Resource in registry.get_all(&"rooms"):
		var room := item as RoomBase
		if room != null and room.walkway and room.scene != null:
			walkway = room
			break
	if walkway != null:
		bus.room_built.emit(walkway.id, 4, own(walkway.build(null)) as Node)
		check_equal(spectacle.room_mists.size(), 1, "a bridge draws none")
	bus.spell_light_changed.emit(false)
	check(spectacle.room_mists.is_empty(), "spell light off: freed with the first room's")
	bus.spell_light_changed.emit(true)
	check_equal(spectacle.room_mists.size(), 1, "on again: made again as laid")
	check_equal(spectacle.room_mists[0].position if not spectacle.room_mists.is_empty() else Vector2.ZERO, place, "at its place")
	bus.room_built.emit(first.id, 0, own(first.build(null)) as Node)
	check(spectacle.room_mists.is_empty(), "a new world: the later rooms' mists go")


# --- Parted by bodies -----------------------------------------------------------------------------

func test_a_body_parts_the_mist_over_frames_and_it_closes_behind() -> void:
	var parting := MistPartingScript.new()
	parting.lay(SIZE)
	var feet := PackedVector2Array([Vector2(100, 80)])
	var last: float = 0.0
	for frame in 10:
		parting.step(FRAME, feet, 1)
		var now: float = parting.parted_at(Vector2(100, 82))
		check(now - last <= MistPartingScript.OPEN_RATE * FRAME + 0.001, "it opens a frame's share at a time (frame %d)" % frame)
		last = now
	check(last > 0.9, "parted at the feet, %.2f" % last)
	check_equal(parting.parted_at(Vector2(160, 80)), 0.0, "not far from them")
	check_equal(parting.parted_at(Vector2(100, 82)), last, "")
	# The body walks on: behind it the mist closes slowly.
	feet[0] = Vector2(200, 80)
	parting.step(FRAME, feet, 1)
	var behind: float = parting.parted_at(Vector2(100, 82))
	check(behind < last and behind > last - MistPartingScript.CLOSE_RATE * FRAME - 0.001, "it closes a frame's share at a time")
	for frame in 120:
		parting.step(FRAME, feet, 1)
	check_equal(parting.parted_at(Vector2(100, 82)), 0.0, "closed again after its close")
	check(parting.parted_at(Vector2(200, 82)) > 0.9, "and parted where the body stands")
	parting.step(FRAME, feet, 0)
	check(parting.parted_at(Vector2(200, 82)) < 1.0, "only the first `count` feet part it")


func test_the_parting_is_cleared_and_laid_anew() -> void:
	var parting := MistPartingScript.new()
	parting.lay(SIZE)
	parting.step(FRAME, PackedVector2Array([Vector2(100, 80)]), 1)
	check(parting.live_cells() > 0, "cells parted")
	parting.clear()
	check_equal(parting.live_cells(), 0, "a new room: closed")
	check_equal(parting.texture.get_format(), Image.FORMAT_R8, "R8: filtered on every renderer")
	check_equal(parting.size(), Vector2(320, 160), "covers the room")


# --- The pass -------------------------------------------------------------------------------------

func test_the_mist_lies_under_the_bodies_over_the_floor_and_under_the_light() -> void:
	var mist: MistScript = _mist()
	check_equal(mist.z_index, SpectacleScript.MARK_Z, "at the marks' z: over the floor")
	check(mist.z_index < 0, "under every body (z 0)")
	check(mist.z_index > RoomBase.FLOOR_Z, "over the floor sprite")
	check(mist.z_index < SpectacleScript.LIGHT_Z, "under the spell light's apply rect: darkened and lit as the floor")
	check(mist.visible and mist.size == SIZE and mist.top_level, "one rect over the room")
	mist.use(null)
	check(not mist.visible, "no mist: nothing drawn")
	mist.use(RoomMist.new())
	mist.lay(Vector2.ZERO, [] as Array[Rect2], [] as Array[Rect2])
	check(not mist.visible, "no room: nothing drawn")


func test_the_shader_is_warmed_and_its_numbers_are_the_scripts() -> void:
	check(WarmupScript.shaders().has(MistScript.SHADER), "the mist's shader is warmed (the spectacle wants it)")
	var code: String = MistScript.SHADER.code
	check(code.contains("#include \"res://gameplay/feel/stir.gdshaderinc\""), "it reads the world's stirs")
	check(code.contains("SCREEN_UV"), "it reads the light buffer under each pixel, as the apply rect does")
	for pair: Array in [["STIR_SHOT_PIXELS", MistScript.STIR_SHOT_PIXELS], ["STIR_BLAST_PIXELS", MistScript.STIR_BLAST_PIXELS], ["STIR_THIN", MistScript.STIR_THIN], ["PART_PIXELS", MistScript.PART_PIXELS], ["PART_THIN", MistScript.PART_THIN], ["THICKEST_DRAWN", MistScript.THICKEST_DRAWN]]:
		check(code.contains("const float %s = %s;" % [pair[0], String.num(pair[1] as float, 1) if fmod(pair[1] as float, 1.0) == 0.0 else str(pair[1])]), "the shader's %s is the script's" % pair[0])
	var shading := _mist().material as ShaderMaterial
	check_equal(shading.get_shader_parameter(&"bright_from"), SpellLightScript.BRIGHT_FROM, "brought out at the floor's bright step")


func test_the_stirs_and_the_bodies_are_handed_to_it() -> void:
	var mist: MistScript = _mist()
	var stirs := StirsScript.new()
	stirs.blast(Vector2(100, 80), 16.0, 0.0)
	mist.step(0.0, PackedVector2Array([Vector2(60, 80)]), 1, stirs.version, stirs.hand_to)
	var shading := mist.material as ShaderMaterial
	check(shading.get_shader_parameter(&"stir_field") == stirs.texture, "the stirs' wake handed over")
	check((shading.get_shader_parameter(&"stir_strength") as PackedFloat32Array)[0] > 0.0, "and the blast")
	check(mist.parting.live_cells() > 0, "the feet handed over part it")
	check(shading.get_shader_parameter(&"parted") == mist.parting.texture, "the parting handed over")
	check(shading.get_shader_parameter(&"mask") == mist.mask, "the mask handed over")
	shading.set_shader_parameter(&"stir_field", null)
	mist.step(FRAME, PackedVector2Array(), 0, stirs.version, stirs.hand_to)
	check(shading.get_shader_parameter(&"stir_field") == null, "the stirs handed again only when they changed")
	check_equal(shading.get_shader_parameter(&"view_time"), FRAME, "Feel's clock handed each frame")


func test_a_frame_makes_no_object() -> void:
	var mist: MistScript = _mist()
	var stirs := StirsScript.new()
	var feet := PackedVector2Array([Vector2(60, 80), Vector2(200, 60)])
	var clock: float = 0.0
	var frames := func(count: int) -> void:
		for frame in count:
			feet[0] = Vector2(60.0 + clock * 40.0, 80.0)
			stirs.step(clock, PackedFloat32Array(), 0, Rect2(0, 0, 320, 160))
			mist.step(clock, feet, 2, stirs.version, stirs.hand_to)
			clock += FRAME
	frames.call(30)
	var objects: float = Performance.get_monitor(Performance.OBJECT_COUNT)
	frames.call(100)
	check(mist.parting.live_cells() > 0, "it was parted")
	check_equal(Performance.get_monitor(Performance.OBJECT_COUNT), objects, "100 frames of mist make no object")


# --- In Feel --------------------------------------------------------------------------------------

## A Feel with its own bus and a projectile manager in the tree. Returns [bus, feel].
func _feel() -> Array:
	var bus: EventsScript = own(EventsScript.new()) as EventsScript
	var table: Node = own(ActorSeats.table()) as Node
	var manager: ProjectilesScript = own(ProjectilesScript.new()) as ProjectilesScript
	manager.events = bus
	manager.actors = table
	root.add_child(manager)
	var feel: FeelScript = own(FeelScript.new()) as FeelScript
	var preset := FeelPresetScript.new()
	preset.hit_sound = &""
	feel.events = bus
	feel.registry = registry
	feel.actors = table
	feel.projectiles = manager
	feel.drive_engine = false
	feel.preset = preset
	root.add_child(feel)
	return [bus, feel]


func test_a_room_names_feel_its_mist_drawn_only_with_spell_light() -> void:
	var made: Array = _feel()
	var bus: EventsScript = made[0]
	var feel: FeelScript = made[1]
	var spectacle: SpectacleScript = feel.spectacle()
	var room := registry.get_resource(&"rooms", &"arena_04") as RoomBase
	bus.spell_light_changed.emit(true)
	bus.room_built.emit(room.id, 0, own(room.build(null)) as Node)
	bus.room_entered.emit(room.id, 0)
	var mist: MistScript = spectacle.mist
	check(mist != null, "spell light on: the mist is made")
	check(mist.mist == room.mist and mist.visible, "the room's mist is drawn")
	check_equal(mist.room_size, room.places().size, "laid in the room built")
	check(mist.mask != null and mist.mask.get_image().get_pixel(0, 0).b > 0.0, "its mask from the room's walls")
	var children: Array[Node] = spectacle.get_children()
	check(children.find(mist) > children.find(spectacle.shadows), "after the bodies' shadows at their z: over them")
	if spectacle.marks != null:
		check(children.find(mist) > children.find(spectacle.marks), "and over the marks")
	spectacle.set_floor_marks(false)
	spectacle.set_floor_marks(true)
	children = spectacle.get_children()
	check(children.find(mist) > children.find(spectacle.marks), "still over the marks made again")
	for frame in 10:
		feel._process(FRAME)
	check((mist.material as ShaderMaterial).get_shader_parameter(&"stir_field") == spectacle.stirs.texture, "Feel's stirs handed over")
	spectacle.hand_bodies(PackedVector2Array([room.places().size * 0.5]), 1)
	spectacle.step(1.0)
	check(mist.parting.live_cells() > 0, "the bodies handed to the spectacle part it")
	bus.spell_light_changed.emit(false)
	check(spectacle.mist == null, "spell light off: no mist (it would be a flat veil without the light)")
	bus.spell_light_changed.emit(true)
	check(spectacle.mist != null and spectacle.mist.mist == room.mist and spectacle.mist.room_size == mist.room_size, "on again: made with the room's mist and room")
	var bare := RoomBase.new()
	bare.id = &"test_bare_room"
	spectacle.use_room(bare)
	check(not spectacle.mist.visible, "a room with no mist: none drawn")


func test_feel_hands_the_covers_bodies_to_the_spectacle() -> void:
	var made: Array = _feel()
	var feel: FeelScript = made[1]
	var spectacle: SpectacleScript = feel.spectacle()
	spectacle.hand_bodies(PackedVector2Array([Vector2(1, 2)]), 1)
	feel._process(FRAME)
	check_equal(spectacle._feet_count, feel.cover().body_count(), "one gathering of bodies, the cover's, read by the mist too")
	for k in spectacle._feet_count:
		check_equal(spectacle._feet[k], feel.cover().bodies()[k], "body %d the cover's" % k)


func test_the_bodies_handed_over_are_copied() -> void:
	var spectacle: SpectacleScript = own(SpectacleScript.new()) as SpectacleScript
	var feet := PackedVector2Array([Vector2(10, 20), Vector2(30, 40)])
	spectacle.hand_bodies(feet, 2)
	feet[0] = Vector2(99, 99)
	check_equal(spectacle._feet[0], Vector2(10, 20), "written again by whoever handed them, the spectacle's are as handed")
	check_equal(spectacle._feet_count, 2, "")
	spectacle.hand_bodies(feet, 5)
	check_equal(spectacle._feet_count, 2, "never more than were handed")
