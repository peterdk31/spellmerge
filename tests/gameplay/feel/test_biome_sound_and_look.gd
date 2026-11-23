extends "res://tests/support/suite.gd"
## A biome's sound and look (connected biomes CB12, decisions 29 and 30), on the real autoloads: the
## split test map started by Flow (the nave the start room, the antechamber west and the ossuary
## court east, tests/support/biome_maps.gd), Feel's parts stepped by hand. Sound comes only from the
## rooms this machine's wizards are in (and the bridges touching them); the music follows the most
## intense of them; each mouth shimmers, flares where a shot stops and seals with bars dropping in
## and a rune, over frames; the unvisited rooms are the void, its motes drifting over them, and
## open by shrinking blocks a stage a frame; the void between the slabs is black with its own motes;
## a gather door's lamps are lit in their wizards' hat colours.
const FlowScript := preload("res://gameplay/flow/flow.gd")
const TickScript := preload("res://core/sim/tick.gd")
const BiomeMaps := preload("res://tests/support/biome_maps.gd")
const RoomHearingScript := preload("res://gameplay/feel/room_hearing.gd")
const MouthLooksScript := preload("res://gameplay/feel/mouth_looks.gd")
const UnseenDarkScript := preload("res://gameplay/feel/unseen_dark.gd")
const SplitScreenScript := preload("res://gameplay/feel/split_screen.gd")
const VoidBackdropScript := preload("res://gameplay/feel/void_backdrop.gd")
const GatherDoorLooksScript := preload("res://gameplay/feel/gather_door_looks.gd")
const AudioScript := preload("res://core/audio/audio.gd")
const ActorsScript := preload("res://core/actors/actors.gd")
const ScreenViewsScript := preload("res://core/display/screen_views.gd")
const ViewBoxesScript := preload("res://gameplay/feel/view_boxes.gd")
const AirMotesScript := preload("res://gameplay/feel/air_motes.gd")
const FoeMarkersScript := preload("res://gameplay/feel/foe_markers.gd")
const InputManagerScript := preload("res://core/input/input_manager.gd")
const MotesScript := preload("res://gameplay/feel/mote.gd")
const SpectacleScript := preload("res://gameplay/feel/spectacle.gd")
const UnseenRoomsScript := preload("res://gameplay/feel/unseen_rooms.gd")
const VoidEdgesScript := preload("res://gameplay/feel/void_edges.gd")
const DT: float = 1.0 / 60.0
const IMP: StringName = &"ember_imp"

var flow: FlowScript
var events: Node
var tick: TickScript
var input: Node
var frames: Node
var registry: Node
var projectiles: Node
var actors: ActorsScript
var feel: Node
var audio: AudioScript


func before_each() -> void:
	flow = root.get_node("Flow") as FlowScript
	events = root.get_node("Events")
	tick = root.get_node("Tick") as TickScript
	input = root.get_node("PlayerInput")
	frames = root.get_node("Frames")
	registry = root.get_node("Registry")
	projectiles = root.get_node("Projectiles")
	actors = root.get_node("Actors") as ActorsScript
	feel = root.get_node("Feel")
	audio = root.get_node("Audio") as AudioScript
	flow.world_parent = own(Node.new()) as Node
	root.add_child(flow.world_parent)


func after_each() -> void:
	flow.stop_run()
	flow.world_parent = null
	flow.mode = FlowScript.MODE_RUN
	for seat in 4:
		input.leave(seat)
	tick.begin_run()


## The split map started with `players` seats, the antechamber's fight `west`.
func _start(players: int, west: Array[StringName] = []) -> BiomeMap:
	var map: BiomeMap = BiomeMaps.split(registry)
	for seat in players:
		input.add_virtual_device(seat)
	var fights: Array[RoomFight] = [RoomFight.new(), RoomFight.of(west), RoomFight.new()]
	check(flow.start_biome(0, map, fights), "the biome starts")
	tick.run(DT)
	return map


func _grid() -> RoomGrid:
	return projectiles.call(&"grid") as RoomGrid


func _hearing() -> RoomHearingScript:
	return feel.call(&"room_hearing") as RoomHearingScript


func _wizard(seat: int) -> Actor:
	return flow.get_wizard(seat) as Actor


func _middle_of(room: int) -> Vector2:
	return flow.biome.room_rect(room).get_center()


## A point of room `room` `inside` pixels in from its socket facing `facing`.
func _by_socket(map: BiomeMap, room: int, facing: int, inside: float) -> Vector2:
	return BiomeMaps.socket_point(registry, map, room, facing) - RoomSocket.way(facing) * inside


func test_only_the_rooms_this_machines_wizards_are_in_are_heard() -> void:
	_start(1)
	var hearing: RoomHearingScript = _hearing()
	hearing.step(actors, 0, _grid())
	check(hearing.in_biome(), "a biome's places are heard by room")
	check(hearing.is_heard(0), "the start room, where the wizard stands, is heard")
	check(hearing.is_walkway(3) and hearing.is_heard(3) and hearing.is_heard(4), "and the bridges touching it")
	check(not hearing.is_heard(1) and not hearing.is_heard(2), "but not the rooms past them")
	check(hearing.hears(_middle_of(0)) and not hearing.hears(_middle_of(1)), "a point is heard by its place")
	check(audio.ears.heard.is_valid(), "Audio asks Feel's hearing")
	check(audio.play(&"hit", _middle_of(0)) >= 0, "a sound in the wizard's room plays")
	check_equal(audio.play(&"hit", _middle_of(1)), -1, "a sound in a room nobody here is in does not")
	check(audio.play(&"hit") >= 0, "a sound of no place (the middle of the picture) plays")


func test_a_teammate_on_another_machine_is_not_heard_from() -> void:
	var map: BiomeMap = _start(2)
	_wizard(1).global_position = _by_socket(map, 1, RoomSocket.Facing.EAST, 48.0)
	var hearing: RoomHearingScript = _hearing()
	hearing.step(actors, 0, _grid())
	check(hearing.is_heard(1), "both seats here: the antechamber, where seat 1 stands, is heard")
	hearing.step(actors, 1, _grid())
	check(not hearing.is_heard(1), "only seat 0 here: the antechamber, where the other machine's wizard stands, is not")
	check(hearing.is_heard(0), "the start room still is")


func test_the_music_follows_the_most_intense_room() -> void:
	var map: BiomeMap = _start(2, [IMP])
	var hearing: RoomHearingScript = _hearing()
	hearing.step(actors, 0, _grid())
	check_equal(hearing.followed(), 0, "the music follows the start room")
	check_equal(hearing.intensity_of(0), RoomHearingScript.INTENSE_QUIET, "a quiet room")
	_wizard(1).global_position = _by_socket(map, 1, RoomSocket.Facing.EAST, 24.0)
	tick.run(DT)
	check(_grid().is_sealed(1), "the antechamber's fight starts and seals it")
	hearing.step(actors, 0, _grid())
	check_equal(hearing.followed(), 1, "the music follows the sealed fight, the most intense")
	check_equal(hearing.intensity_of(1), RoomHearingScript.INTENSE_FIGHT, "a fight")
	hearing.step(actors, 1, _grid())
	check_equal(hearing.followed(), 0, "with only seat 0 here, its quiet room")
	var room: RoomBase = registry.get_resource(&"rooms", flow.biome.map.room_templates[0]) as RoomBase
	check(hearing.music() == room.music, "its track the room's own, its kind naming none")
	check(hearing.air() == room.ambience, "and its bed")


func test_a_kinds_music_and_air_come_first() -> void:
	_start(1)
	var hearing: RoomHearingScript = _hearing()
	hearing.step(actors, 0, _grid())
	var kind: RoomKind = hearing.kind_of(0)
	check(kind != null, "the start room's kind is known: %s" % flow.biome.map.room_templates[0])
	var track := MusicTrack.new()
	track.layers = [&"crypt_halls"] as Array[StringName]
	var bed := Ambience.new()
	var music_before: MusicTrack = kind.music
	var air_before: Ambience = kind.air
	kind.music = track
	kind.air = bed
	check(hearing.music() == track, "the kind's music is played in place of the room's")
	check(hearing.air() == bed, "and its air")
	kind.music = music_before
	kind.air = air_before


func test_each_mouth_shimmers_and_flares_where_a_shot_stops() -> void:
	_start(1)
	var mouths: MouthLooksScript = feel.call(&"mouth_looks") as MouthLooksScript
	mouths.step(0.0, _grid())
	check_equal(mouths.mouths(), 4, "a mouth at each end of each bridge")
	var rooms: Array[int] = []
	for mouth in mouths.mouths():
		rooms.append(mouths.room_of(mouth))
		check_equal(mouths.area_of(mouth).size, Vector2i(8, 64), "mouth %d is a cell deep and a mouth wide" % mouth)
	rooms.sort()
	check_equal(rooms, [0, 0, 1, 2] as Array[int], "each leads into the room it meets")
	check_equal(mouths.glow_of(0), MouthLooksScript.GLOW_STAGES, "a world laid is drawn as it stands: the open mouths shimmer")
	check(not mouths.is_moving(), "nothing plays in")
	var middle: Vector2 = Rect2(mouths.area_of(0)).get_center()
	events.emit_signal(&"projectile_impact", 0, null, middle + Vector2(-3.0, 0.0), Vector2.RIGHT)
	var stages: Array[int] = [mouths.flare_of(0)]
	while mouths.is_moving():
		mouths.advance()
		stages.append(mouths.flare_of(0))
	check_equal(stages, [1, 2, 3, 2, 1, 0] as Array[int], "a shot stopping there flares it, a stage a frame")
	check(not mouths.flare(_middle_of(1)), "nowhere near a mouth, nothing flares")
	var area := Rect2(mouths.area_of(0))
	var beside: Vector2 = Vector2(area.get_center().x, area.position.y - 4.0) if area.size.y > area.size.x else Vector2(area.position.x - 4.0, area.get_center().y)
	check(not mouths.flare(beside), "a hit on the bridge's side beside the mouth does not flare it")


func test_a_seals_bars_drop_in_over_frames_then_its_rune_lights() -> void:
	var map: BiomeMap = _start(1, [IMP])
	var mouths: MouthLooksScript = feel.call(&"mouth_looks") as MouthLooksScript
	mouths.step(0.0, _grid())
	while mouths.is_moving():
		mouths.advance()
	var sealed: int = -1
	for mouth in mouths.mouths():
		if mouths.room_of(mouth) == 1:
			sealed = mouth
	_wizard(0).global_position = _by_socket(map, 1, RoomSocket.Facing.EAST, 24.0)
	tick.run(DT)
	check(_grid().is_sealed(1), "the antechamber seals")
	mouths.read(_grid())
	var steps: Array[int] = []
	while mouths.is_moving():
		mouths.advance()
		steps.append(mouths.seal_of(sealed))
	check_equal(steps.slice(0, MouthLooksScript.SEAL_FRAMES + MouthLooksScript.RUNE_STAGES), [1, 2, 3, 4, 5, 6, 7, 8] as Array[int], "its bars drop in a frame at a time, then its rune lights")
	check_equal(mouths.glow_of(sealed), 0, "a sealed mouth's shimmer has gone out, in stages")
	for mouth in mouths.mouths():
		if mouths.room_of(mouth) != 1:
			check_equal(mouths.seal_of(mouth), 0, "mouth %d into an open room is not sealed" % mouth)


func test_unvisited_rooms_are_dark_and_lighten_in_stages() -> void:
	var map: BiomeMap = _start(1)
	var dark: UnseenDarkScript = feel.call(&"unseen_dark") as UnseenDarkScript
	dark.step(0.0, _grid())
	var darkest: int = UnseenDarkScript.BLOCK_SIDES.size() - 1
	check_equal(dark.places(), 5, "every piece")
	check_equal(dark.stage_of(0), 0, "the start room, entered, is lit")
	check_equal(dark.stage_of(1), darkest, "the antechamber, unvisited, is dark")
	check_equal(dark.stage_of(2), darkest, "and the court")
	check_equal(dark.stage_of(3), 0, "a bridge is never dark")
	var block: int = UnseenDarkScript.BLOCK * UnseenDarkScript.BLOCK
	check_equal(dark.dark_of(1), block, "dark wholly, no dither")
	check_equal(dark.covered_of(1), _grid().place_rect(1), "the dark covers the whole unvisited room")
	check_equal(dark.covered_of(2), _grid().place_rect(2), "and the whole court")
	check_equal(dark.covered_of(0), Rect2(), "the start room is not covered")
	check_equal(UnseenDarkScript.DARK, VoidBackdropScript.COLOUR, "in the void's black")
	_wizard(0).global_position = _by_socket(map, 1, RoomSocket.Facing.EAST, 24.0)
	dark.step(0.0, _grid())
	check_equal(dark.stage_of(1), darkest, "a wizard standing there is not yet the party's map")
	tick.run(DT)
	dark.step(0.0, _grid())
	var stages: Array[int] = []
	while dark.is_moving():
		dark.advance()
		stages.append(dark.stage_of(1))
	check_equal(stages, [3, 2, 1, 0] as Array[int], "visited, it opens a stage a frame (Smooth: 3 frames between)")
	check_equal(dark.covered_of(1), Rect2(), "and is no longer covered")
	check(not dark.void_covers().has(_grid().place_rect(1)) and dark.void_covers().has(_grid().place_rect(2)), "it is no longer the void; the court still is")
	check_equal(dark.stage_of(2), darkest, "the court stays dark")


## The owner's secret ways (2026-11-20): a secret room standing wall to wall with the nave, joined by
## a seam: the seam is hidden as a secret room's bridge is (pure void, the nave's doorway its lip,
## never over the nave's slab), and once the cracked wall breaks it opens in stages, its end at the
## nave first.
func test_a_wall_to_wall_secret_rooms_seam_is_hidden_until_found_then_opens_in_stages() -> void:
	var map: BiomeMap = BiomeMaps.wall_secret(registry)
	input.add_virtual_device(0)
	check(flow.start_biome(0, map, [RoomFight.new(), RoomFight.new()] as Array[RoomFight]), "the biome starts")
	tick.run(DT)
	var dark: UnseenDarkScript = feel.call(&"unseen_dark") as UnseenDarkScript
	dark.step(0.0, _grid())
	var seam: int = map.rooms()
	var rect: Rect2 = dark.covered_of(seam)
	var west: Vector2 = BiomeMaps.socket_point(registry, map, 0, RoomSocket.Facing.WEST)
	check_equal(dark.build_of(seam), UnseenDarkScript.HIDDEN, "not found: hidden")
	check(rect.has_area() and rect.end.x <= west.x - UnseenDarkScript.LANDING, "covered in the void's black, short of the nave's landing")
	check(dark.void_covers().has(rect), "the hidden seam is the void: its motes drift over it")
	flow.locks.open(1, _grid())
	dark.step(0.0, _grid())
	var near := Vector2(rect.end.x - 4.0, rect.get_center().y)
	var stages: Array[int] = []
	while dark.is_moving():
		dark.advance()
		stages.append(dark.cell_stage_at(seam, near))
	check_equal(stages.slice(0, 4), [3, 2, 1, 0] as Array[int], "found: the doorway opens a stage a frame from the nave (Smooth)")
	check_equal(dark.covered_of(seam), Rect2(), "and is not covered once open")


## The owner, 2026-11-20: the bridge to a secret room is hidden until the secret is found: pure void,
## its doorway the room's lip (the rock stands there). Found, it builds out from the room it leaves
## a band a frame, each pixel stepping through the dark's stages, toward the secret room; a restore
## draws it as it stands, hidden or whole.
func test_a_secret_rooms_bridge_is_hidden_until_found_then_builds_out_in_stages() -> void:
	var map: BiomeMap = BiomeMaps.split(registry)
	map.room_kinds[1] = &"secret"
	input.add_virtual_device(0)
	check(flow.start_biome(0, map, [RoomFight.new(), RoomFight.new(), RoomFight.new()] as Array[RoomFight]), "the biome starts")
	tick.run(DT)
	var dark: UnseenDarkScript = feel.call(&"unseen_dark") as UnseenDarkScript
	dark.step(0.0, _grid())
	var to_secret: int = -1
	var other: int = -1
	for bridge in map.bridges():
		var place: int = map.rooms() + bridge
		if map.end_room(bridge, 0) == 1 or map.end_room(bridge, 1) == 1:
			to_secret = place
		else:
			other = place
	check(to_secret >= 0 and other >= 0, "a bridge to the secret room and one to the court")
	var bridge_rect: Rect2 = _grid().place_rect(to_secret)
	var west: Vector2 = BiomeMaps.socket_point(registry, map, 0, RoomSocket.Facing.WEST)
	var rect: Rect2 = dark.covered_of(to_secret)
	check_equal(dark.build_of(to_secret), UnseenDarkScript.HIDDEN, "not found: hidden")
	# The bridge's rectangle, short of the nave by its landing: the black never bites the nave's lip.
	check_equal(rect, Rect2(bridge_rect.position, Vector2(west.x - UnseenDarkScript.LANDING - bridge_rect.position.x, bridge_rect.size.y)), "covered in the void's black, from LANDING out of the nave's socket")
	check(not rect.intersects(_grid().place_rect(0).grow(-UnseenDarkScript.LANDING * 2.0)) and rect.end.x <= west.x - UnseenDarkScript.LANDING, "never over the nave's slab")
	check_equal(dark.covered_of(other), Rect2(), "another bridge is never dark")
	check(dark.void_covers().has(rect), "the hidden bridge is the void: its motes drift over it")
	var hidden := Snapshot.take(tick.state_areas(), root)
	# The bridge runs west from the start room: its east end leaves from it, its west end meets the
	# secret room.
	var near := Vector2(rect.end.x - 4.0, rect.get_center().y)
	var far := Vector2(rect.position.x + 4.0, rect.get_center().y)
	var last: int = UnseenDarkScript.BLOCK_SIDES.size() - 1
	check(dark.cell_stage_at(to_secret, near) == last and dark.cell_stage_at(to_secret, far) == last, "every cell dark")
	flow.locks.open(1, _grid())
	dark.step(0.0, _grid())
	check(dark.is_moving(), "found: it builds")
	var near_stages: Array[int] = []
	var far_stages: Array[int] = []
	var frames_built: int = 0
	while dark.is_moving():
		dark.advance()
		frames_built += 1
		near_stages.append(dark.cell_stage_at(to_secret, near))
		far_stages.append(dark.cell_stage_at(to_secret, far))
	check_equal(near_stages.slice(0, 4), [3, 2, 1, 0] as Array[int], "the end at the room it leaves shows first, a stage a frame (Smooth: 3 frames between)")
	var far_first: int = far_stages.find(last - 1)
	check(far_first > 0, "the far end later, as the causeway lays itself toward the secret room (its first step at frame %d)" % far_first)
	check_equal(far_stages.slice(far_first, far_first + 4), [3, 2, 1, 0] as Array[int], "it too a stage a frame")
	check_equal(frames_built, dark.built_at(to_secret), "built whole after a band a frame")
	check_equal(dark.covered_of(to_secret), Rect2(), "found and built: not covered")
	check(not dark.void_covers().has(rect), "nor the void's any more")
	var found := Snapshot.take(tick.state_areas(), root)
	check(hidden.restore(tick.state_areas(), root).is_empty(), "restored to before it was found")
	dark.step(0.0, _grid())
	check(dark.build_of(to_secret) == UnseenDarkScript.HIDDEN and not dark.is_moving(), "hidden again as it stands, nothing played")
	check(found.restore(tick.state_areas(), root).is_empty(), "restored to after")
	dark.step(0.0, _grid())
	check(dark.build_of(to_secret) == dark.built_at(to_secret) and not dark.is_moving(), "whole as it stands, nothing played")


## Regression (the review of 2026-11-20): the view found a bridge's rooms by what touched it, so a
## bridge laid beside a secret room it does not reach was hidden with it, and a secret bridge built
## from the wrong room. On crypt maps where a secret room abuts another bridge (seeds 73 and 120),
## a bridge is hidden exactly when one of its own ends is a secret room, and the Y map reads each
## bridge's own ends.
func test_only_a_bridge_that_reaches_a_secret_room_is_hidden() -> void:
	var crypt := registry.get_resource(&"runs", &"crypt") as RunDefinition
	var shapes: Dictionary = registry.piece_shapes(&"crypt")
	# The first two seeds whose map has the case (a bridge touching a secret room it does not reach).
	var seeds: Array[int] = []
	for seed_value in range(1, 300):
		var made: BiomeMap = BiomeGenerator.generate(crypt, registry.run_content(), shapes, Sim.seeded(seed_value))
		if _bridge_beside_a_secret(made, shapes):
			seeds.append(seed_value)
			if seeds.size() == 2:
				break
	check_equal(seeds.size(), 2, "maps with a bridge beside a secret room it does not reach")
	for seed_value: int in seeds:
		var map: BiomeMap = BiomeGenerator.generate(crypt, registry.run_content(), shapes, Sim.seeded(seed_value))
		var fights: Array[RoomFight] = []
		for room in map.rooms():
			fights.append(RoomFight.new())
		input.add_virtual_device(0)
		check(flow.start_biome(0, map, fights), "seed %d: the biome starts" % seed_value)
		tick.run(DT)
		var dark: UnseenDarkScript = feel.call(&"unseen_dark") as UnseenDarkScript
		dark.step(0.0, _grid())
		var hearing: RoomHearingScript = _hearing()
		var wrong := PackedStringArray()
		for bridge in map.bridges():
			var place: int = map.rooms() + bridge
			var secret: bool = map.room_kinds[map.end_room(bridge, 0)] == &"secret" or map.room_kinds[map.end_room(bridge, 1)] == &"secret"
			if (dark.build_of(place) == UnseenDarkScript.HIDDEN) != secret:
				wrong.append("bridge %d (%s to %s) %s" % [bridge, map.room_kinds[map.end_room(bridge, 0)], map.room_kinds[map.end_room(bridge, 1)], "hidden" if not secret else "shown"])
			for end in 2:
				if hearing.end_room(place, end) != map.end_room(bridge, end):
					wrong.append("bridge %d's end %d heard as room %d, not %d" % [bridge, end, hearing.end_room(place, end), map.end_room(bridge, end)])
		check_equal(wrong, PackedStringArray(), "seed %d: only the bridges to a secret room hidden, each by its own ends" % seed_value)
		# The case itself: a bridge touching a secret room it does not reach.
		var beside: bool = false
		for bridge in map.bridges():
			for room in map.rooms():
				if map.room_kinds[room] == &"secret" and map.end_room(bridge, 0) != room and map.end_room(bridge, 1) != room:
					beside = beside or flow.biome.bridge_rect(bridge).grow(RoomHearingScript.TOUCH).intersects(flow.biome.room_rect(room))
		check(beside, "seed %d: a bridge lies beside a secret room it does not reach" % seed_value)
		flow.stop_run()


## True when a bridge of `map` lies within RoomHearing's TOUCH of a secret room it does not reach.
func _bridge_beside_a_secret(map: BiomeMap, shapes: Dictionary) -> bool:
	for bridge in map.bridges():
		var rect: Rect2 = map.bridge_shape(bridge, shapes).rect_at(map.bridge_places[bridge]).grow(RoomHearingScript.TOUCH)
		for room in map.rooms():
			if map.room_kinds[room] == &"secret" and map.end_room(bridge, 0) != room and map.end_room(bridge, 1) != room and rect.intersects(map.room_shape(room, shapes).rect_at(map.room_places[room])):
				return true
	return false


## Each stage between covered and lit is a block of whole black pixels round a block's middle,
## shrinking stage by stage, so the room shows through a widening grid.
func test_a_dark_stage_is_a_shrinking_block_of_whole_black_pixels() -> void:
	var last: int = -1
	for stage in UnseenDarkScript.BLOCK_SIDES.size():
		var side: int = UnseenDarkScript.BLOCK_SIDES[stage]
		var texture: ImageTexture = UnseenDarkScript.block_texture(side)
		if side == 0 or side >= UnseenDarkScript.BLOCK:
			check(texture == null, "a lit stage and the solid one need no texture (stage %d)" % stage)
			continue
		var image: Image = texture.get_image()
		var dark: int = 0
		for y in image.get_height():
			for x in image.get_width():
				var pixel: Color = image.get_pixel(x, y)
				check(pixel.a == 0.0 or pixel == UnseenDarkScript.DARK, "a pixel is wholly black or wholly clear")
				dark += 1 if pixel.a == 1.0 else 0
		check_equal(dark, side * side, "stage %d is a %d px square" % [stage, side])
		check(image.get_pixel(UnseenDarkScript.BLOCK / 2, UnseenDarkScript.BLOCK / 2).a == 1.0 and image.get_pixel(0, 0).a == 0.0, "at the block's middle")
	for stage in UnseenDarkScript.BLOCK_SIDES.size():
		check(UnseenDarkScript.BLOCK_SIDES[stage] > last, "the blocks grow stage by stage")
		last = UnseenDarkScript.BLOCK_SIDES[stage]
	check_equal(UnseenDarkScript.BLOCK_SIDES[UnseenDarkScript.BLOCK_SIDES.size() - 1], UnseenDarkScript.BLOCK, "the last is solid")
	check(UnseenDarkScript.BLOCK_SIDES.size() - 2 >= 3, "at least 3 frames between covered and lit")


## Fine and quick (the owner, 2026-11-20, #883): 8 px blocks, opening over `reveal_seconds()` of real
## frames, still a stage a frame of FPS (stepped, never a fade).
func test_the_reveal_is_fine_and_quick_and_stepped() -> void:
	check_equal(UnseenDarkScript.BLOCK, 8, "8 px blocks")
	check(32 % UnseenDarkScript.BLOCK == 0, "a whole number of them on the 32 px grid")
	check(UnseenDarkScript.reveal_seconds() <= 0.2, "quick: %.3f s" % UnseenDarkScript.reveal_seconds())
	for stage in UnseenDarkScript.BLOCK_SIDES.size():
		check(UnseenDarkScript.BLOCK_SIDES[stage] % 2 == 0, "stage %d's square sits whole at the block's middle" % stage)
	var map: BiomeMap = _start(1)
	var dark: UnseenDarkScript = feel.call(&"unseen_dark") as UnseenDarkScript
	dark.step(0.0, _grid())
	_wizard(0).global_position = _by_socket(map, 1, RoomSocket.Facing.EAST, 24.0)
	tick.run(DT)
	var frame: float = 1.0 / 60.0
	var stages: Array[int] = [dark.stage_of(1)]
	var frames: int = 0
	while dark.stage_of(1) > 0 and frames < 120:
		dark.step(frame, _grid())
		frames += 1
		if dark.stage_of(1) != stages[stages.size() - 1]:
			stages.append(dark.stage_of(1))
	check_equal(stages, [4, 3, 2, 1, 0] as Array[int], "a stage at a time")
	check(absf(frames * frame - UnseenDarkScript.reveal_seconds()) <= frame * 1.5, "open in %d frames, about %.3f s" % [frames, UnseenDarkScript.reveal_seconds()])
	# A slow machine (10 fps): every stage is still drawn, one a frame.
	_wizard(0).global_position = _by_socket(map, 2, RoomSocket.Facing.WEST, 24.0)
	tick.run(DT)
	var slow: Array[int] = [dark.stage_of(2)]
	for i in 8:
		dark.step(0.1, _grid())
		slow.append(dark.stage_of(2))
	check_equal(slow.slice(0, 5), [4, 3, 2, 1, 0] as Array[int], "a slow frame skips no stage")


## The void between a biome's slabs is pure black under everything, over the biome and past it; its
## motes drift only outside the places; outside a biome there is neither.
func test_the_void_is_black_with_motes_outside_the_rooms() -> void:
	_start(1)
	feel.call(&"_step_rooms", 0.0, 1)
	var backdrop: VoidBackdropScript = feel.call(&"void_backdrop") as VoidBackdropScript
	check(backdrop != null, "Feel has the void")
	check_equal(VoidBackdropScript.COLOUR, Color(0.0, 0.0, 0.0, 1.0), "pure black")
	check_equal(backdrop.z_index, RenderingServer.CANVAS_ITEM_Z_MIN, "under everything")
	var bounds: Rect2 = projectiles.call(&"bounds") as Rect2
	check(backdrop.rect().encloses(bounds.grow(VoidBackdropScript.GROW - 1.0)), "over the biome and far past it")
	var spectacle: Node = feel.call(&"spectacle")
	var air: AirMotesScript = spectacle.get(&"void_air") as AirMotesScript
	var pool: MotesScript = spectacle.get(&"void_pool") as MotesScript
	check(pool != null, "the void's motes' pool")
	check(air.look != null and pool.kind_index(air.look.kind) >= 0, "its kind is a good mote kind")
	var given_before: int = air.given
	var view := Rect2(bounds.position, bounds.size)
	for i in 120:
		air.give_off(float(i) * 0.1, pool, view, Rect2(), SpectacleScript.VOID_POOL_SHARE, _grid())
	check(air.given > given_before, "the void gives off motes (%d)" % (air.given - given_before))
	check(air.look != null and not registry.call(&"get_resource", &"motes", air.look.kind).lit_only, "seen in the dark: not lit only")
	# None leaves from a room or a bridge.
	var seen: int = air.given
	air.given = 0
	for i in 200:
		air.give_off(12.0 + float(i) * 0.1, pool, Rect2(_grid().place_rect(0).get_center() - Vector2(32.0, 32.0), Vector2(64.0, 64.0)), Rect2(), SpectacleScript.VOID_POOL_SHARE, _grid())
	check_equal(air.given, 0, "none from inside a room entered (%d before)" % seen)
	flow.stop_run()
	feel.call(&"_step_rooms", 0.0, 1)
	check_equal(backdrop.rect(), Rect2(), "outside a biome, no void is drawn")


## The owner, 2026-11-23 ("the real background" round a room's or a bridge's edge, not one of its
## own): off its slab, inside its own rectangle, an entered piece shows the void, and the void's
## motes are given off there as between the pieces; never over its floor, a wall standing on it (the
## nave's sarcophagus) or a mouth.
func test_the_void_and_its_motes_reach_a_pieces_slab_inside_its_rectangle() -> void:
	var map: BiomeMap = _start(1)
	feel.call(&"_step_rooms", 0.0, 1)
	var spectacle: Node = feel.call(&"spectacle")
	var edges: VoidEdgesScript = spectacle.get(&"void_edges") as VoidEdgesScript
	var grid: RoomGrid = _grid()
	var room: Rect2 = grid.place_rect(0)
	var corner: Vector2 = room.position + Vector2(4.0, 4.0)
	check(edges.count(0) > 0 and edges.shows(corner, 0, grid), "the nave's corner lies off its slab (%d edge walls)" % edges.count(0))
	check(not edges.shows(_wizard(0).global_position, 0, grid), "its floor does not")
	# Every wall cell and mouth of the nave: a wall standing on its floor (its sarcophagus) and a
	# mouth are never the void.
	var standing: int = 0
	var mouths: int = 0
	var wrong: int = 0
	for y in range(4, int(room.size.y), int(RoomGrid.WALL_CELL)):
		for x in range(4, int(room.size.x), int(RoomGrid.WALL_CELL)):
			var at: Vector2 = room.position + Vector2(x, y)
			var cell: int = grid.cell_at(at)
			var shown: bool = edges.shows(at, 0, grid)
			mouths += int((cell & RoomGrid.MOUTH_CELL) != 0)
			standing += int((cell & RoomGrid.ROOM_CELL) != 0 and not shown)
			wrong += int(shown and ((cell & RoomGrid.ROOM_CELL) == 0 or (cell & RoomGrid.MOUTH_CELL) != 0))
	check(standing > 0, "the nave's sarcophagus stands on its floor: walls that are not the void (%d cells)" % standing)
	check_equal(wrong, 0, "no open cell and no mouth is the void (%d mouth cells in the nave)" % mouths)
	var bridges: int = 0
	for place in range(map.room_templates.size(), grid.places()):
		var bridge: Rect2 = grid.place_rect(place)
		bridges += 1
		check(edges.shows(bridge.position + Vector2(4.0, 4.0), place, grid) and not edges.shows(bridge.get_center(), place, grid), "bridge %d: its corner is the void, its walkway is not" % place)
	check(bridges > 0, "the map's bridges are laid (%d)" % bridges)
	check(AirMotesScript.is_void(corner, grid, [], edges) and not AirMotesScript.is_void(corner, grid, []), "the air asks the edges")
	# The void's motes leave from the strip off the slab, none from the floor beside it.
	var air: AirMotesScript = spectacle.get(&"void_air") as AirMotesScript
	var void_pool: MotesScript = spectacle.get(&"void_pool") as MotesScript
	var seen := ViewBoxesScript.new()
	seen.set_one(Rect2(room.position, Vector2(96.0, 96.0)))
	air.given = 0
	var now: float = spectacle.get(&"_clock")
	for i in 400:
		now += 0.1
		void_pool.step(now)
		spectacle.call(&"_give_off_void", now, seen)
	check(air.given > 0, "the void's motes are given off round the corner of the nave (%d)" % air.given)
	seen.set_one(Rect2(room.get_center() - Vector2(8.0, 8.0), Vector2(16.0, 16.0)))
	air.given = 0
	for i in 200:
		now += 0.1
		spectacle.call(&"_give_off_void", now, seen)
	check_equal(air.given, 0, "none over the middle of its floor")
	# A wall of a room's own against its rim is no edge of its slab (the ossuary gallery's walls of
	# bones, arena_14), and a new world forgets the last one's pieces.
	var gallery: Node2D = own((registry.call(&"get_resource", &"rooms", &"arena_14") as RoomBase).scene.instantiate()) as Node2D
	var ground: Array[Rect2] = PieceShape.laid_ground_walls(gallery)
	var block: CollisionShape2D = gallery.get_node("Walls/Block1") as CollisionShape2D
	var bones := Rect2(block.position - (block.shape as RectangleShape2D).size * 0.5, (block.shape as RectangleShape2D).size)
	check(not ground.is_empty() and PieceShape.laid_walls(gallery).has(bones) and not ground.has(bones), "arena_14's wall of bones is a wall, not its ground's edge")
	edges.lay_piece(0, gallery, true)
	check(edges.count(0) == ground.size() and edges.count(1) == 0, "a new world's first piece alone is kept")


## The owner, 2026-11-21: an unvisited room is not black, it looks like the void round it, the void's
## motes drifting over it, until it is revealed. Nothing is drawn over it (what it holds is hidden one
## by one: test_unseen_hidden.gd); the void's motes are given off over the rooms the dark covers whole
## as over the void (into a pool of their own, at the motes' z, so they cross a room's edge without
## stopping), never over a room entered; the void's motes over a hidden room are drawn by that room's
## chunk of the void's pool (#892), none in the room's chunks of the motes' pool; and the reveal still
## opens a stage a frame, the void's motes given off there no more once it begins.
func test_an_unvisited_room_is_the_void_with_its_motes_drifting_over_it() -> void:
	var map: BiomeMap = _start(1)
	feel.call(&"_step_rooms", 0.0, 1)
	var dark: UnseenDarkScript = feel.call(&"unseen_dark") as UnseenDarkScript
	var spectacle: Node = feel.call(&"spectacle")
	var room: Rect2 = _grid().place_rect(1)
	check_equal(UnseenDarkScript.DARK, VoidBackdropScript.COLOUR, "the cover is the void's own colour")
	var covers: Array[Rect2] = spectacle.get(&"void_covers")
	check(is_same(covers, dark.void_covers()), "Feel hands the spectacle what the dark covers (the one array)")
	check(covers.has(room) and covers.has(_grid().place_rect(2)) and not covers.has(_grid().place_rect(0)), "the unvisited rooms, not the start room")
	var void_pool: MotesScript = spectacle.get(&"void_pool") as MotesScript
	var pool: MotesScript = spectacle.get(&"pool") as MotesScript
	check(void_pool != null and void_pool != pool, "the void's motes have a pool of their own")
	var air: AirMotesScript = spectacle.get(&"void_air") as AirMotesScript
	check(void_pool.kind_index(air.look.kind) >= 0, "the void's pool has the void's kind")
	var inside := Rect2(room.get_center() - Vector2(48.0, 48.0), Vector2(96.0, 96.0))
	var seen := ViewBoxesScript.new()
	seen.set_one(inside)
	var rows_before: int = pool.next_row()
	air.given = 0
	var now: float = spectacle.get(&"_clock")
	for i in 200:
		now += 0.1
		void_pool.step(now)
		spectacle.call(&"_give_off_void", now, seen)
	check(air.given > 0, "the void's motes are given off over the unvisited room (%d)" % air.given)
	check(room.encloses(air.given_box), "from points inside it (%s)" % air.given_box)
	check_equal(pool.next_row(), rows_before, "none into the motes' pool")
	# Drawn by the room's own chunk of the void's pool (#892), none by the motes' pool's for it.
	void_pool.use_places(_grid())
	void_pool.step(now)
	var in_room: int = 0
	var newest: int = posmod(void_pool.next_row() - 1, void_pool.cap())
	for back in mini(air.given, void_pool.cap()):
		var row: int = posmod(newest - back, void_pool.cap())
		var chunk: int = void_pool.regions.chunk_of_row(row)
		if void_pool.regions.region_of_chunk(chunk) == 2:
			in_room += 1
			check_equal(void_pool.regions.node_of(chunk).z_index, SpectacleScript.MOTE_Z, "its chunk is drawn at the motes' z, no layer of its own (#897's 21 is gone)")
			break
	check(in_room > 0, "the void's motes over the room are drawn by its chunk of the void's pool")
	# Entered: the reveal begins, and from its first stage the room is the void no more.
	_wizard(0).global_position = _by_socket(map, 1, RoomSocket.Facing.EAST, 24.0)
	tick.run(DT)
	dark.step(0.0, _grid())
	dark.advance()
	check_equal(dark.stage_of(1), UnseenDarkScript.BLOCK_SIDES.size() - 2, "a stage into the reveal")
	feel.call(&"_step_rooms", 0.0, 1)
	var under: int = 0
	for c in void_pool.regions.chunks_made():
		if void_pool.regions.region_of_chunk(c) == 2:
			under += 1
			check_equal(void_pool.regions.node_of(c).z_index, SpectacleScript.MOTE_Z, "under its opening blocks, then under its telegraphs")
	check(under > 0, "its chunk is there")
	air.given = 0
	for i in 200:
		now += 0.1
		void_pool.step(now)
		spectacle.call(&"_give_off_void", now, seen)
	check_equal(air.given, 0, "no void's motes are given off over a room being revealed")
	var stages: Array[int] = []
	while dark.is_moving():
		dark.advance()
		stages.append(dark.stage_of(1))
	check_equal(stages, [2, 1, 0] as Array[int], "the reveal still opens a stage a frame")


## A room nobody has entered draws nothing of its own under its dark (the owner, 2026-11-21, after
## the report of worse performance): its layout, its floor marks' layer, its motes' chunks and its
## ground cover are switched off, the start room's and the bridges' never; from its reveal's first
## stage all of it is drawn again, under the opening blocks.
func test_an_unvisited_room_draws_nothing_of_its_own_until_its_reveal() -> void:
	var map: BiomeMap = _start(1)
	var spectacle: Node = feel.call(&"spectacle")
	var pool: MotesScript = spectacle.get(&"pool") as MotesScript
	pool.use_places(_grid())
	feel.call(&"_step_rooms", 0.0, 1)
	var rooms: UnseenRoomsScript = feel.call(&"unseen_rooms") as UnseenRoomsScript
	var dark: UnseenDarkScript = feel.call(&"unseen_dark") as UnseenDarkScript
	var marks: Object = spectacle.get(&"marks")
	var cover: Object = feel.get(&"_cover_rooms")
	var bridge: int = map.rooms()
	check(dark.covers_whole(1) and dark.covers_whole(2) and not dark.covers_whole(0), "the unvisited rooms are covered whole, the start room not")
	check(not dark.covers_whole(bridge), "nor a bridge")
	for place: int in [0, 1, 2, bridge]:
		var off: bool = place == 1 or place == 2
		check_equal(rooms.is_hidden(place), off, "place %d switched %s" % [place, "off" if off else "on"])
		var layout := flow.biome.room_layout(place) as CanvasItem if place < map.rooms() else null
		check(layout != null or place >= map.rooms(), "room %d has a layout" % place)
		if layout != null:
			check_equal(layout.visible, not off, "place %d's layout drawn: %s" % [place, not off])
		check_equal(pool.regions.region_shown(place + 1), not off, "place %d's motes drawn: %s" % [place, not off])
		if marks != null and int(marks.call(&"layer_count")) > place:
			check_equal(bool(marks.call(&"layer_shown", place)), not off, "place %d's marks drawn: %s" % [place, not off])
		var room_cover: Object = cover.call(&"view_of", place) if cover != null else null
		if room_cover is CanvasItem:
			check_equal((room_cover as CanvasItem).visible, not off, "place %d's cover drawn: %s" % [place, not off])
	# A mote of the hidden room is still copied to its chunk, which is not drawn.
	var inside: Vector2 = _grid().place_rect(1).get_center()
	pool.throw_part(0, inside, Vector2.RIGHT, 0, Color.WHITE, 4, 2.0, 0.0, 0.0, false)
	var now: float = spectacle.get(&"_clock") + 0.01
	pool.step(now)
	var drawn: int = 0
	var copied: int = 0
	for c in pool.regions.chunks_made():
		if pool.regions.region_of_chunk(c) == 2:
			copied += 1
			if pool.regions.node_of(c).visible:
				drawn += 1
	check(copied > 0, "the hidden room's motes are copied to its chunk (%d)" % copied)
	check_equal(drawn, 0, "and not drawn")
	# Entered: from the reveal's first stage its drawing is on again, the court's still off.
	_wizard(0).global_position = _by_socket(map, 1, RoomSocket.Facing.EAST, 24.0)
	tick.run(DT)
	dark.step(0.0, _grid())
	dark.advance()
	check(not dark.covers_whole(1), "a stage into the reveal it is not covered whole")
	feel.call(&"_step_rooms", 0.0, 1)
	check(not rooms.is_hidden(1) and rooms.is_hidden(2), "its drawing on, the court's off")
	check((flow.biome.room_layout(1) as CanvasItem).visible, "its layout drawn under the opening blocks")
	check(pool.regions.region_shown(2), "its motes drawn")
	var shown: int = 0
	for c in pool.regions.chunks_made():
		if pool.regions.region_of_chunk(c) == 2 and pool.regions.node_of(c).visible:
			shown += 1
	check(shown > 0, "its chunk drawn again as it stands")


## A place out of every view draws nothing of its own either (the owner, 2026-11-21: "also hide rooms
## out of view"), a margin past the view's box still counting as in it; a split's every view counts,
## and with no view box none is out of view.
func test_a_place_out_of_every_view_draws_nothing_of_its_own() -> void:
	var map: BiomeMap = _start(1)
	var spectacle: Node = feel.call(&"spectacle")
	var pool: MotesScript = spectacle.get(&"pool") as MotesScript
	pool.use_places(_grid())
	feel.call(&"_step_rooms", 0.0, 1)
	var rooms: UnseenRoomsScript = feel.call(&"unseen_rooms") as UnseenRoomsScript
	var dark: UnseenDarkScript = feel.call(&"unseen_dark") as UnseenDarkScript
	var marks: Object = spectacle.get(&"marks")
	var cover: Object = feel.get(&"_cover_rooms")
	var bridge: int = map.rooms()
	var start: Rect2 = _grid().place_rect(0)
	var seen := ViewBoxesScript.new()
	var far := Rect2(_grid().place_rect(bridge).end + Vector2(10000.0, 10000.0), Vector2(64.0, 64.0))
	seen.set_one(far)
	rooms.step(dark, _grid(), seen, marks, pool.regions, cover)
	check(rooms.is_hidden(0) and rooms.is_hidden(bridge), "with the view far off, the start room and the bridge are off")
	check(not (flow.biome.room_layout(0) as CanvasItem).visible, "the start room's layout not drawn")
	check(not pool.regions.region_shown(1), "nor its motes")
	# Just past the margin, still off; within it, on.
	seen.set_one(Rect2(start.end + Vector2(UnseenRoomsScript.MARGIN + 8.0, UnseenRoomsScript.MARGIN + 8.0), Vector2(64.0, 64.0)))
	rooms.step(dark, _grid(), seen, marks, pool.regions, cover)
	check(rooms.is_hidden(0), "a box past the margin leaves the start room off")
	seen.set_one(Rect2(start.end + Vector2(UnseenRoomsScript.MARGIN - 8.0, UnseenRoomsScript.MARGIN - 8.0), Vector2(64.0, 64.0)))
	rooms.step(dark, _grid(), seen, marks, pool.regions, cover)
	check(not rooms.is_hidden(0), "within the margin it is on")
	check((flow.biome.room_layout(0) as CanvasItem).visible and pool.regions.region_shown(1), "its layout and motes drawn again")
	# A split: any view showing a place keeps it on; an unvisited room in view stays off.
	seen.count = 2
	seen.boxes[0] = far
	seen.boxes[1] = _grid().place_rect(1)
	rooms.step(dark, _grid(), seen, marks, pool.regions, cover)
	var near_second: bool = _grid().place_rect(1).grow(UnseenRoomsScript.MARGIN).intersects(start)
	check_equal(rooms.is_hidden(0), not near_second, "the start room is on only if the second view reaches it")
	check(rooms.is_hidden(1), "the unvisited room in the second view stays off (its dark)")
	check(not rooms.is_hidden(bridge) or not _grid().place_rect(bridge).grow(UnseenRoomsScript.MARGIN).intersects(_grid().place_rect(1)), "a bridge by the second view is on")
	seen.set_one(Rect2())
	rooms.step(dark, _grid(), seen, marks, pool.regions, cover)
	check(not rooms.is_hidden(0) and not rooms.is_hidden(bridge) and rooms.is_hidden(1), "with no view box none is out of view")


## What counts as on screen for that follows the party camera as it was moved this frame, not the
## viewport's canvas transform, which follows a frame late (the review's: on a long pan a room at
## the leading edge came in a frame after its place on screen).
func test_the_view_rooms_are_switched_by_is_where_the_camera_is_this_frame() -> void:
	_start(1)
	tick.run(DT)
	var camera := Camera2D.new()
	root.add_child(camera)
	camera.make_current()
	(feel.get(&"party_camera") as Object).call(&"follow", camera)
	var before: Rect2 = (feel.get_viewport().get_canvas_transform().affine_inverse() * feel.get_viewport().get_visible_rect())
	camera.position += Vector2(3000.0, 0.0)
	var seen: Object = feel.call(&"_rooms_seen")
	var box: Rect2 = (seen.get(&"boxes") as Array)[0]
	var wanted: Rect2 = (feel.get(&"party_camera") as Object).call(&"visible_rect")
	check(box.is_equal_approx(wanted), "the box is the camera's picture as it stands now (%s, %s)" % [box, wanted])
	check(not box.is_equal_approx(before), "not the canvas transform's of the frame before")
	camera.queue_free()


## The void's pool is made and freed with the motes' pool (the "Particles" setting's cap: VOID_SHARE of
## it, twice over; none with no motes) and follows the particle amount and the split's share.
func test_the_void_pool_follows_the_motes_settings() -> void:
	_start(1)
	var spectacle: Node = feel.call(&"spectacle")
	var cap_before: int = spectacle.get(&"mote_cap")
	var density_before: float = spectacle.get(&"mote_density")
	var top: int = MoteCap.STOPS[-1]
	spectacle.call(&"set_mote_cap", top)
	var void_pool: MotesScript = spectacle.get(&"void_pool") as MotesScript
	check(void_pool != null and void_pool.cap() == SpectacleScript.void_cap_of(top), "remade with the cap (%d)" % (void_pool.cap() if void_pool != null else -1))
	check_equal(SpectacleScript.void_cap_of(top), ceili(float(top) / 16.0), "VOID_SHARE of the ring, twice over")
	spectacle.call(&"set_mote_density", 0.5)
	check_equal((spectacle.get(&"void_pool") as MotesScript).density, (spectacle.get(&"pool") as MotesScript).density, "the particle amount reaches it")
	spectacle.call(&"use_motes", null)
	check(spectacle.get(&"void_pool") == null, "no motes: no void pool")
	spectacle.call(&"set_mote_density", density_before)
	spectacle.call(&"set_mote_cap", cap_before)
	check(spectacle.get(&"void_pool") != null, "made again with the motes")


## The equal split's blank quarter shows the void (the owner, 2026-11-20): the spectacle gives the
## void's motes off over the world the split screen's void view shows (`set_void_blank`), and none
## while there is no blank.
func test_the_blank_quarters_void_gets_its_own_drifting_motes() -> void:
	_start(1)
	feel.call(&"_step_rooms", 0.0, 1)
	var spectacle: Node = feel.call(&"spectacle")
	var air: AirMotesScript = spectacle.get(&"void_blank_air") as AirMotesScript
	check(air != null and air.look != null, "the blank's void air uses the void's motes")
	var bounds: Rect2 = projectiles.call(&"bounds") as Rect2
	var blank := Rect2(bounds.position - Vector2.ONE * SplitScreenScript.VOID_AWAY - Vector2(320.0, 180.0), Vector2(640.0, 360.0))
	check(not blank.intersects(bounds), "the void view looks past the biome")
	check(bounds.grow(VoidBackdropScript.GROW).encloses(blank), "inside the void's black")
	air.given = 0
	var no_view := ViewBoxesScript.new()
	for i in 120:
		spectacle.call(&"_give_off_void", float(i) * 0.1, no_view)
	check_equal(air.given, 0, "no blank: no motes there")
	spectacle.call(&"set_void_blank", blank)
	for i in 120:
		spectacle.call(&"_give_off_void", 20.0 + float(i) * 0.1, no_view)
	check(air.given > 0, "a blank: its void drifts with motes (%d)" % air.given)
	check(blank.grow(AirMotesScript.VIEW_MARGIN + 1.0).encloses(air.given_box), "given off over the void view (%s)" % air.given_box)
	spectacle.call(&"set_void_blank", Rect2())


## A fight's foe out of view gets a marker at the picture's edge (the owner, 2026-11-23), one still
## spawning in from the moment it starts: with the game's own actors, grid and sealed room, and a
## picture that looks away from the room.
func test_a_spawning_foe_out_of_view_gets_a_marker_from_the_moment_it_starts() -> void:
	var map: BiomeMap = _start(1, [IMP, IMP] as Array[StringName])
	_wizard(0).global_position = _by_socket(map, 1, RoomSocket.Facing.EAST, 40.0)
	var spawning: Actor = null
	var spawning_id: int = ActorsScript.NONE
	for i in 240:
		tick.run(DT)
		var ids := PackedInt32Array()
		for n in actors.open_ids(ids):
			var body := actors.node_of(ids[n]) as Actor
			if body != null and actors.team_of(ids[n]) == ActorsScript.TEAM_ENEMIES and body.is_spawning():
				spawning = body
				spawning_id = ids[n]
				break
		if spawning != null:
			break
	check(spawning != null, "an imp spawns in the sealed antechamber")
	if spawning == null:
		return
	var markers: FoeMarkersScript = feel.call(&"foe_markers") as FoeMarkersScript
	check(markers != null and markers.is_inside_tree(), "Feel made the foe markers")
	if markers == null:
		return
	# A picture far from the room: the imp is out of it.
	var away := ScreenViewsScript.new()
	away.set_single(Vector2(640.0, 360.0), Transform2D(0.0, Vector2.ONE, 0.0, -(spawning.global_position + Vector2(4000.0, 0.0))), 0b0001)
	markers.step(1.0, actors, _grid(), 0b0001, away)
	var found: bool = false
	for i in markers.count:
		found = found or markers.foe_of(i) == spawning_id
	check(found, "the imp still spawning in (share %.2f) has a marker already (%d markers)" % [spawning.spawn_share(), markers.count])


## The wiring, through Feel's own step: a seat played on this machine (the keyboard's) in a sealed
## fight, a foe put out of its picture, and Feel's step marks it (the room grid, the seats here and
## the picture are Feel's own).
func test_feels_step_marks_a_fights_foe_out_of_the_picture() -> void:
	var map: BiomeMap = BiomeMaps.split(registry)
	check_equal(input.call(&"join_as", InputManagerScript.KEYBOARD, 0), 0, "the keyboard joined seat 0")
	var fights: Array[RoomFight] = [RoomFight.new(), RoomFight.of([IMP, IMP] as Array[StringName]), RoomFight.new()]
	check(flow.start_biome(0, map, fights), "the biome starts")
	tick.run(DT)
	_wizard(0).global_position = _by_socket(map, 1, RoomSocket.Facing.EAST, 40.0)
	var grid: RoomGrid = _grid()
	var foe: Actor = null
	for i in 240:
		tick.run(DT)
		var ids := PackedInt32Array()
		for n in actors.open_ids(ids):
			if actors.team_of(ids[n]) == ActorsScript.TEAM_ENEMIES and actors.node_of(ids[n]) is Actor:
				foe = actors.node_of(ids[n]) as Actor
				break
		if foe != null and grid.sealed_at(_wizard(0).global_position):
			break
	check(foe != null and grid.sealed_at(_wizard(0).global_position), "the antechamber's fight is under way, sealed")
	if foe == null:
		return
	var markers: FoeMarkersScript = feel.call(&"foe_markers") as FoeMarkersScript
	# The wizard in one corner of the room, every foe beside it: all in the picture.
	var room: Rect2 = grid.place_rect(grid.place_at(_wizard(0).global_position))
	_wizard(0).global_position = room.end - Vector2(56.0, 56.0)
	var ids := PackedInt32Array()
	for n in actors.open_ids(ids):
		if actors.team_of(ids[n]) == ActorsScript.TEAM_ENEMIES and actors.node_of(ids[n]) is Node2D:
			(actors.node_of(ids[n]) as Node2D).global_position = room.end - Vector2(96.0, 96.0)
	for i in 90:
		feel.call(&"step", DT)
	check_equal(markers.count, 0, "every foe beside the wizard, in the picture: no marker")
	var party: Object = feel.get(&"party_camera") as Object
	var camera: Camera2D = party.get(&"camera") as Camera2D
	var looked: Transform2D = Transform2D(0.0, camera.zoom, 0.0, camera.position)
	# One foe to the far corner, out of the picture at the default zoom.
	foe.global_position = room.position + Vector2(56.0, 56.0)
	for i in 30:
		feel.call(&"step", DT)
	check(Transform2D(0.0, camera.zoom, 0.0, camera.position).is_equal_approx(looked), "Feel's camera did not move or zoom for the foe of the sealed fight (%s, %s)" % [camera.position, camera.zoom])
	check_equal(markers.count, 1, "the foe in the far corner of the %s room: Feel's step marks it" % room.size)
	if markers.count == 1:
		check_equal(actors.node_of(markers.foe_of(0)), foe, "that foe")
		check(markers.way_of(0).x < 0.0 and markers.way_of(0).y < 0.0, "pointing up and left, at it (%s)" % markers.way_of(0))


func test_a_gather_doors_lamps_are_lit_in_their_wizards_hat_colours() -> void:
	var map: BiomeMap = _start(2)
	var looks: GatherDoorLooksScript = feel.call(&"gather_doors") as GatherDoorLooksScript
	var door := Rect2(_by_socket(map, 1, RoomSocket.Facing.EAST, -8.0) - Vector2(4.0, 32.0), Vector2(8.0, 64.0))
	_wizard(1).global_position = door.get_center() + Vector2(16.0, 0.0)
	looks.see(actors)
	events.emit_signal(&"gather_door_shown", 0, RoomKind.DOOR_GATHER, door, 1, 2, false, false)
	var shades: Array[PackedInt32Array] = []
	while looks.is_moving():
		looks.advance()
		shades.append(looks.lamps_of(0))
	check_equal(looks.lamps_of(0), PackedInt32Array([1, 3]), "the lamp of seat 1, at the door, is lit; seat 0's is not")
	check(shades.size() >= 3, "it lit over frames: %s" % [shades])
	check_equal(looks.lamp_ramp_of(0, 1), actors.ramp_of(_wizard(1).id), "in seat 1's hat colour")
	check_equal(looks.lamp_ramp_of(0, 0), actors.ramp_of(_wizard(0).id), "and seat 0's lamp in seat 0's")
	# Seat 1 walks off and seat 0 comes: seat 1's lamp goes out, seat 0's lights.
	_wizard(1).global_position = _middle_of(0) + Vector2(0.0, 40.0)
	_wizard(0).global_position = door.get_center() + Vector2(16.0, 0.0)
	looks.see(actors)
	while looks.is_moving():
		looks.advance()
	check_equal(looks.lamps_of(0), PackedInt32Array([3, 1]), "the lit lamp follows who is at the door")


func test_with_no_wizard_of_this_machine_in_a_place_the_last_places_stay_heard() -> void:
	_start(1)
	var hearing: RoomHearingScript = _hearing()
	hearing.step(actors, 0, _grid())
	check(hearing.is_heard(0) and not hearing.is_heard(1), "the start room heard")
	_wizard(0).global_position = Vector2(-5000.0, -5000.0)
	hearing.step(actors, 0, _grid())
	check(hearing.is_heard(0), "the wizard in no place (falling, not stood): the start room still heard, the biome never silent")
	check(not hearing.is_heard(1), "and the rest still not")
	hearing.step(null, 0, _grid())
	check(hearing.is_heard(0), "no actor table: the same")
