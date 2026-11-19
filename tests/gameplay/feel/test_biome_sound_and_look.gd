extends "res://tests/support/suite.gd"
## A biome's sound and look (connected biomes CB12, decisions 29 and 30), on the real autoloads: the
## split test map started by Flow (the nave the start room, the antechamber west and the ossuary
## court east, tests/support/biome_maps.gd), Feel's parts stepped by hand. Sound comes only from the
## rooms this machine's wizards are in (and the bridges touching them); the music follows the most
## intense of them; each mouth shimmers, flares where a shot stops and seals with bars dropping in
## and a rune, over frames; the unvisited rooms are dark by a dither that lightens a stage a frame;
## a gather door's lamps are lit in their wizards' hat colours.
const FlowScript := preload("res://gameplay/flow/flow.gd")
const TickScript := preload("res://core/sim/tick.gd")
const BiomeMaps := preload("res://tests/support/biome_maps.gd")
const RoomHearingScript := preload("res://gameplay/feel/room_hearing.gd")
const MouthLooksScript := preload("res://gameplay/feel/mouth_looks.gd")
const UnseenDarkScript := preload("res://gameplay/feel/unseen_dark.gd")
const GatherDoorLooksScript := preload("res://gameplay/feel/gather_door_looks.gd")
const AudioScript := preload("res://core/audio/audio.gd")
const ActorsScript := preload("res://core/actors/actors.gd")
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
	var darkest: int = UnseenDarkScript.DARK_STAGES.size() - 1
	check_equal(dark.places(), 5, "every piece")
	check_equal(dark.stage_of(0), 0, "the start room, entered, is lit")
	check_equal(dark.stage_of(1), darkest, "the antechamber, unvisited, is dark")
	check_equal(dark.stage_of(2), darkest, "and the court")
	check_equal(dark.stage_of(3), 0, "a bridge is never dark")
	check(dark.dark_of(1) > 8 and dark.dark_of(1) < 16, "dark by a dither, not wholly: %d of 16" % dark.dark_of(1))
	_wizard(0).global_position = _by_socket(map, 1, RoomSocket.Facing.EAST, 24.0)
	dark.step(0.0, _grid())
	check_equal(dark.stage_of(1), darkest, "a wizard standing there is not yet the party's map")
	tick.run(DT)
	dark.step(0.0, _grid())
	var stages: Array[int] = []
	while dark.is_moving():
		dark.advance()
		stages.append(dark.stage_of(1))
	check_equal(stages, [3, 2, 1, 0] as Array[int], "visited, it lightens a stage a frame")
	check_equal(dark.stage_of(2), darkest, "the court stays dark")


func test_a_dither_stage_is_whole_pixels_of_the_voids_dark() -> void:
	for stage in UnseenDarkScript.DARK_STAGES.size():
		var count: int = UnseenDarkScript.DARK_STAGES[stage]
		var texture: ImageTexture = UnseenDarkScript._dither_texture(count)
		if count == 0:
			check(texture == null, "a lit stage draws nothing")
			continue
		var image: Image = texture.get_image()
		var dark: int = 0
		for y in image.get_height():
			for x in image.get_width():
				var pixel: Color = image.get_pixel(x, y)
				check(pixel.a == 0.0 or pixel.a == 1.0, "a pixel is wholly dark or wholly clear")
				dark += 1 if pixel.a == 1.0 else 0
		check_equal(dark, count, "stage %d darkens %d pixels of 16" % [stage, count])


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
