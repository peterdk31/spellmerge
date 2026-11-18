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
	check_equal(_texel(image, Vector2(250, 80)).g, 0.0, "over the pit itself it is thickest")
	check(_texel(image, Vector2(228, 80)).g < _texel(image, Vector2(80, 80)).g, "nearer the pit, thicker")
	var in_wall: Color = _texel(image, Vector2(80, 24))
	check(in_wall.b > 0.0 and in_wall.r == 0.0, "a wall: none of it but its spill")
	var outer: Color = _texel(image, Vector2(4, 4))
	check(outer.b > in_wall.b, "the void outside the walls is wall, deeper still: no mist over the dark")
	check_equal(_texel(image, Vector2(80, 64)).b, 0.0, "open floor holds no spill")


func test_the_mask_of_a_room_open_to_its_edge_measures_from_the_edge() -> void:
	var image: Image = MistMaskScript.build(SIZE, [] as Array[Rect2], [] as Array[Rect2])
	check(_texel(image, Vector2(4, 80)).r < _texel(image, Vector2(80, 80)).r, "no walls: the room's own edge is its edge")
	check_equal(_texel(image, Vector2(4, 80)).b, 0.0, "and nothing is wall")


func test_a_big_room_is_masked_by_bigger_cells() -> void:
	check_equal(MistMaskScript.cell_of(Vector2(640, 384)), MistMaskScript.CELL, "a room of the crypt by CELL")
	var hub := Vector2(4000.0, 1000.0)
	var image: Image = MistMaskScript.build(hub, [] as Array[Rect2], [] as Array[Rect2])
	check(image.get_width() <= MistMaskScript.MOST_CELLS, "never more than MOST_CELLS a side")


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
	bus.room_built.emit(room.id, own(room.build(null)) as Node)
	bus.room_entered.emit(room.id)
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
	check_equal(spectacle._feet, feel.cover().bodies(), "one gathering of bodies, the cover's, read by the mist too")
	check_equal(spectacle._feet_count, feel.cover().body_count(), "as many as the cover found")
