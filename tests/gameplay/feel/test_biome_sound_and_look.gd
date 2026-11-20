extends "res://tests/support/suite.gd"
## A biome's sound and look (connected biomes CB12, decisions 29 and 30), on the real autoloads: the
## split test map started by Flow (the nave the start room, the antechamber west and the ossuary
## court east, tests/support/biome_maps.gd), Feel's parts stepped by hand. Sound comes only from the
## rooms this machine's wizards are in (and the bridges touching them); the music follows the most
## intense of them; each mouth shimmers, flares where a shot stops and seals with bars dropping in
## and a rune, over frames; the unvisited rooms are wholly black and open by shrinking blocks a stage
## a frame; the void between the slabs is black with its own motes;
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
const AirMotesScript := preload("res://gameplay/feel/air_motes.gd")
const CloseFoesScript := preload("res://gameplay/feel/close_foes.gd")
const MotesScript := preload("res://gameplay/feel/mote.gd")
const SpectacleScript := preload("res://gameplay/feel/spectacle.gd")
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
	check_equal(dark.stage_of(2), darkest, "the court stays dark")


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
	var pool: MotesScript = spectacle.get(&"pool") as MotesScript
	check(pool != null, "the motes' pool")
	check(air.look != null and pool.kind_index(air.look.kind) >= 0, "its kind is a good mote kind")
	var given_before: int = air.given
	var view := Rect2(bounds.position, bounds.size)
	for i in 120:
		air.give_off(float(i) * 0.1, pool, view, Rect2(), SpectacleScript.VOID_SHARE, _grid())
	check(air.given > given_before, "the void gives off motes (%d)" % (air.given - given_before))
	check(air.look != null and not registry.call(&"get_resource", &"motes", air.look.kind).lit_only, "seen in the dark: not lit only")
	# None leaves from a room or a bridge.
	var seen: int = air.given
	air.given = 0
	for i in 200:
		air.give_off(12.0 + float(i) * 0.1, pool, Rect2(_grid().place_rect(0).get_center() - Vector2(32.0, 32.0), Vector2(64.0, 64.0)), Rect2(), SpectacleScript.VOID_SHARE, _grid())
	check_equal(air.given, 0, "none from inside a room (%d before)" % seen)
	flow.stop_run()
	feel.call(&"_step_rooms", 0.0, 1)
	check_equal(backdrop.rect(), Rect2(), "outside a biome, no void is drawn")


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
	for i in 120:
		spectacle.call(&"_give_off_void", float(i) * 0.1, Rect2())
	check_equal(air.given, 0, "no blank: no motes there")
	spectacle.call(&"set_void_blank", blank)
	for i in 120:
		spectacle.call(&"_give_off_void", 20.0 + float(i) * 0.1, Rect2())
	check(air.given > 0, "a blank: its void drifts with motes (%d)" % air.given)
	check(blank.grow(AirMotesScript.VIEW_MARGIN + 1.0).encloses(air.given_box), "given off over the void view (%s)" % air.given_box)
	spectacle.call(&"set_void_blank", Rect2())


## Enemies still spawning in count as close foes from the moment they start (the owner, 2026-11-19):
## the camera zooms out as they appear.
func test_spawning_foes_are_close_from_the_moment_they_start() -> void:
	var map: BiomeMap = _start(1, [IMP, IMP] as Array[StringName])
	_wizard(0).global_position = _by_socket(map, 1, RoomSocket.Facing.EAST, 40.0)
	var spawning: Actor = null
	for i in 240:
		tick.run(DT)
		var ids := PackedInt32Array()
		for n in actors.open_ids(ids):
			var body := actors.node_of(ids[n]) as Actor
			if body != null and actors.team_of(ids[n]) == ActorsScript.TEAM_ENEMIES and body.is_spawning():
				spawning = body
				break
		if spawning != null:
			break
	check(spawning != null, "an imp spawns in the sealed antechamber")
	if spawning == null:
		return
	var foes: CloseFoesScript = feel.get(&"close_foes") as CloseFoesScript
	foes.find(actors, _grid())
	var found: bool = false
	for i in foes.count:
		found = found or foes.at[i] == spawning.global_position
	check(found, "the imp still spawning in (share %.2f) is a close foe already" % spawning.spawn_share())


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
