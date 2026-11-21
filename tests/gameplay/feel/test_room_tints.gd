extends "res://tests/support/suite.gd"
## Each room's light and air by its kind (connected biomes CB12b), on the real autoloads: the split
## test map started by Flow (the nave the start room, the antechamber west and the ossuary court
## east, tests/support/biome_maps.gd; the court a fountain here), Feel's parts stepped by hand. A
## room's own light leans toward its kind's light (`RoomKind.light`, `light_tint`; drawn by the spell
## light's apply pass, by each room's world rectangle), coming in over STAGES frames as the room is
## entered; each kind's air motes drift over its own rooms alone. How it looks is checked by eye
## (tests/screenshots/shot_room_tints.gd): headless runs draw nothing.
const FlowScript := preload("res://gameplay/flow/flow.gd")
const TickScript := preload("res://core/sim/tick.gd")
const BiomeMaps := preload("res://tests/support/biome_maps.gd")
const RoomTintsScript := preload("res://gameplay/feel/room_tints.gd")
const KindAirScript := preload("res://gameplay/feel/kind_air.gd")
const RoomHearingScript := preload("res://gameplay/feel/room_hearing.gd")
const SpellLightScript := preload("res://gameplay/feel/spell_light.gd")
const MotesScript := preload("res://gameplay/feel/mote.gd")
const RampTableScript := preload("res://gameplay/feel/ramp_table.gd")
const ActorsScript := preload("res://core/actors/actors.gd")
const DT: float = 1.0 / 60.0
const FRAME: float = 1.0 / 12.0
## The crypt's kinds, every one with a tint and air motes (CB12b).
const KINDS: Array[StringName] = [&"fight", &"boss", &"start", &"reward", &"shop", &"fountain", &"treasure", &"secret", &"challenge"]

var flow: FlowScript
var events: Node
var tick: TickScript
var input: Node
var registry: Node
var projectiles: Node
var actors: ActorsScript
var feel: Node
var _light_was: bool = false


func before_each() -> void:
	flow = root.get_node("Flow") as FlowScript
	events = root.get_node("Events")
	tick = root.get_node("Tick") as TickScript
	input = root.get_node("PlayerInput")
	registry = root.get_node("Registry")
	projectiles = root.get_node("Projectiles")
	actors = root.get_node("Actors") as ActorsScript
	feel = root.get_node("Feel")
	flow.world_parent = own(Node.new()) as Node
	root.add_child(flow.world_parent)
	_light_was = _spectacle().light != null
	feel.call(&"set_spell_light", true)


func after_each() -> void:
	feel.call(&"set_spell_light", _light_was)
	flow.stop_run()
	flow.world_parent = null
	flow.mode = FlowScript.MODE_RUN
	for seat in 4:
		input.leave(seat)
	tick.begin_run()


## The split map started with `players` seats, the court a fountain.
func _start(players: int) -> BiomeMap:
	var map: BiomeMap = BiomeMaps.split(registry, [0, 0, 0] as Array[int], [BiomeMaps.FIRST, BiomeMaps.MIDDLE, BiomeMaps.LAST] as Array[StringName], [&"fight", &"start", &"fountain"] as Array[StringName])
	for seat in players:
		input.add_virtual_device(seat)
	var fights: Array[RoomFight] = [RoomFight.new(), RoomFight.new(), RoomFight.new()]
	check(flow.start_biome(0, map, fights), "the biome starts")
	tick.run(DT)
	_hearing().step(actors, 0, _grid())
	return map


func _grid() -> RoomGrid:
	return projectiles.call(&"grid") as RoomGrid


func _hearing() -> RoomHearingScript:
	return feel.call(&"room_hearing") as RoomHearingScript


func _tints() -> RoomTintsScript:
	return feel.call(&"room_tints") as RoomTintsScript


func _spectacle() -> Object:
	return feel.call(&"spectacle")


func _light() -> SpellLightScript:
	return _spectacle().get(&"light") as SpellLightScript


func _kind(id: StringName) -> RoomKind:
	return registry.get_resource(&"room_kinds", id) as RoomKind


func _middle_of(room: int) -> Vector2:
	return flow.biome.room_rect(room).get_center()


func _step_tints(delta: float = 0.0) -> void:
	_tints().step(delta, _grid(), _light())


## The court entered: the wizard stood in it, a tick for the party's map.
func _enter_court(map: BiomeMap, seat: int = 0) -> void:
	var court: Vector2 = BiomeMaps.socket_point(registry, map, 2, RoomSocket.Facing.WEST)
	(flow.get_wizard(seat) as Actor).global_position = court + Vector2(48.0, 0.0)
	tick.run(DT)


# --- The data -------------------------------------------------------------------------------------

func test_every_kind_has_a_light_a_tint_and_air_motes_in_the_crypts_style() -> void:
	for id in KINDS:
		var kind: RoomKind = _kind(id)
		check(kind != null, "%s is a kind" % id)
		check(kind.problems().is_empty(), "%s: %s" % [id, "; ".join(kind.problems())])
		check(Palette.has(kind.light) and not Palette.OWNED.has(kind.light), "%s names a world light: %s" % [id, kind.light])
		check(kind.light_tint > 0.0 and kind.light_tint <= RoomKind.LIGHT_TINT_MOST, "%s tints its room a little: %.2f" % [id, kind.light_tint])
		check(kind.air_motes != null, "%s names its air motes" % id)
		check(registry.get_resource(&"motes", kind.air_motes.kind) is MoteKind, "%s's air motes are a mote kind there is" % id)
	check(_kind(&"fight").light_tint < _kind(&"boss").light_tint, "a fight's light barely leans, the boss's far more")
	check_equal(_kind(&"boss").light, &"fire", "the boss's light is the fire's")


func test_a_kind_with_a_wrong_tint_or_air_says_so() -> void:
	var kind := RoomKind.new()
	kind.id = &"wrong"
	kind.light_tint = 0.9
	kind.air_motes = MoteSource.new()
	var found: String = "; ".join(kind.problems())
	check(found.contains("light_tint"), "a tint past the most is named: %s" % found)
	check(found.contains("air motes"), "air motes naming no kind are named: %s" % found)


func test_a_hue_is_its_lights_base_shade_never_brighter() -> void:
	var hue: Color = RoomTintsScript.hue_of(_kind(&"fountain"))
	check(is_equal_approx(maxf(hue.r, maxf(hue.g, hue.b)), 1.0), "its brightest channel is 1")
	var water: Color = Palette.shades_of(&"water")[1]
	check(is_equal_approx(hue.g / hue.b, water.g / water.b), "in the water's base hue")
	var none := RoomKind.new()
	check(RoomTintsScript.hue_of(none).is_equal_approx(RoomTintsScript.hue_of(_kind(&"reward"))), "a kind naming no light leans toward the spark's")


# --- In the biome ---------------------------------------------------------------------------------

func test_a_rooms_tint_follows_its_kind() -> void:
	_start(1)
	_step_tints()
	var tints: RoomTintsScript = _tints()
	check_equal(tints.rooms(), 3, "every room of the map is tinted (each kind names a tint)")
	var nave: Color = tints.tint_at(_middle_of(0))
	check(Color(nave.r, nave.g, nave.b).is_equal_approx(RoomTintsScript.hue_of(_kind(&"start"))), "the nave leans toward its kind's light")
	check(is_equal_approx(nave.a, _kind(&"start").light_tint), "by its kind's share, entered: %.2f" % nave.a)
	check_equal(tints.tint_at(_middle_of(2)).a, 0.0, "the court, not yet entered, is not tinted yet")
	var bridge: Rect2 = _grid().place_rect(4)
	check(_hearing().is_walkway(4), "place 4 is a bridge")
	check_equal(tints.tint_at(bridge.get_center()).a, 0.0, "a bridge's middle is never tinted")
	check_equal(tints.tint_at(Vector2(-4096.0, -4096.0)).a, 0.0, "nor the void")
	var light: SpellLightScript = _light()
	check(light != null, "dynamic lighting on")
	check_equal(light.tint_count, 1, "the light is handed the nave's tint alone")
	var apply := light.apply.material as ShaderMaterial
	check_equal(int(apply.get_shader_parameter(&"tint_count")), 1, "and its apply pass reads it")
	var rects: PackedVector4Array = apply.get_shader_parameter(&"tint_rects")
	var rect: Rect2 = _grid().place_rect(0)
	check(rects[0].is_equal_approx(Vector4(rect.position.x, rect.position.y, rect.end.x, rect.end.y)), "by the nave's world rectangle")


func test_entered_a_rooms_tint_comes_in_over_frames() -> void:
	var map: BiomeMap = _start(1)
	_step_tints()
	var tints: RoomTintsScript = _tints()
	_enter_court(map)
	var stages: Array[int] = []
	var shares: Array[float] = []
	for frame in 5:
		_step_tints(FRAME)
		stages.append(tints.stage_of(2))
		shares.append(tints.tint_at(_middle_of(2)).a)
	check_equal(stages, [1, 2, 3, 3, 3] as Array[int], "a stage a frame at 12 fps, then held")
	check(shares[0] > 0.0 and shares[0] < shares[1] and shares[1] < shares[2], "each stage leans further: %s" % [shares])
	check(is_equal_approx(shares[2], _kind(&"fountain").light_tint), "to its kind's share")
	check(RoomTintsScript.STAGES >= 3, "at least 3 frames (Smooth)")


func test_two_rooms_of_different_kinds_side_by_side_are_each_their_own() -> void:
	var map: BiomeMap = _start(1)
	_enter_court(map)
	for frame in 4:
		_step_tints(FRAME)
	var tints: RoomTintsScript = _tints()
	var nave: Color = tints.tint_at(_middle_of(0))
	var court: Color = tints.tint_at(_middle_of(2))
	check(nave.a > 0.0 and court.a > 0.0, "both rooms tinted")
	check(not Color(nave.r, nave.g, nave.b).is_equal_approx(Color(court.r, court.g, court.b)), "each in its own kind's hue")
	# One view holding both (and the bridge between): every world pixel its own room's, so the view
	# moving over them changes no pixel's tint.
	var east: Rect2 = _grid().place_rect(0)
	var west: Rect2 = _grid().place_rect(2)
	var near_nave: Vector2 = Vector2(east.end.x - 1.0, east.get_center().y)
	var near_court: Vector2 = Vector2(west.position.x + 1.0, west.get_center().y)
	check(tints.tint_at(near_nave).is_equal_approx(nave), "the nave's edge is the nave's")
	check(tints.tint_at(near_court).is_equal_approx(court), "the court's edge is the court's")
	check_equal(tints.tint_at((near_nave + near_court) * 0.5).a, 0.0, "between them the bridge, untinted")
	# Its edge (the owner, 2026-11-19): stepped down onto the bridge in whole-pixel bands.
	var out_x: float = east.end.x
	var y: float = east.get_center().y
	check(is_equal_approx(tints.tint_at(Vector2(out_x + 0.5, y)).a, nave.a * 2.0 / 3.0), "the first band past the nave's edge: two thirds of its tint")
	check(is_equal_approx(tints.tint_at(Vector2(out_x + RoomTintsScript.EDGE_BAND - 0.5, y)).a, nave.a * 2.0 / 3.0), "the whole band alike (whole pixels)")
	check(is_equal_approx(tints.tint_at(Vector2(out_x + RoomTintsScript.EDGE_BAND + 0.5, y)).a, nave.a / 3.0), "the second band: a third")
	check_equal(tints.tint_at(Vector2(out_x + RoomTintsScript.EDGE_BAND * 2.0 + 0.5, y)).a, 0.0, "then none")
	check(Color(tints.tint_at(Vector2(out_x + 0.5, y)).r, tints.tint_at(Vector2(out_x + 0.5, y)).g, tints.tint_at(Vector2(out_x + 0.5, y)).b).is_equal_approx(Color(nave.r, nave.g, nave.b)), "in the nave's hue")
	check_equal(_light().tint_count, 2, "the light holds both")


func test_a_split_screen_with_two_views_in_different_rooms_tints_each_by_its_room() -> void:
	var map: BiomeMap = _start(2)
	_enter_court(map, 1)
	for frame in 4:
		_step_tints(FRAME)
	var light: SpellLightScript = _light()
	var views: Array[Viewport] = []
	for k in 2:
		var view := own(SubViewport.new()) as SubViewport
		view.size = Vector2i(320, 180)
		view.world_2d = root.get_viewport().world_2d
		root.add_child(view)
		views.append(view)
	light.use_views(views)
	_step_tints(FRAME)
	var apply := light.apply.material as ShaderMaterial
	check(light.readers.copy_of(light.apply, 1) == null, "two views share the apply rect, and so its tints")
	check_equal(int(apply.get_shader_parameter(&"tint_count")), 2, "which tints by the world, whichever view draws it")
	var tints: RoomTintsScript = _tints()
	var at_0: Vector2 = (flow.get_wizard(0) as Node2D).global_position
	var at_1: Vector2 = (flow.get_wizard(1) as Node2D).global_position
	check(Color(tints.tint_at(at_0).r, tints.tint_at(at_0).g, tints.tint_at(at_0).b).is_equal_approx(RoomTintsScript.hue_of(_kind(&"start"))), "seat 0's view, in the nave, the start's light")
	check(Color(tints.tint_at(at_1).r, tints.tint_at(at_1).g, tints.tint_at(at_1).b).is_equal_approx(RoomTintsScript.hue_of(_kind(&"fountain"))), "seat 1's, in the court, the fountain's")
	light.use_views([] as Array[Viewport])


func test_a_restore_draws_the_tints_as_they_stand_and_a_new_light_is_handed_them() -> void:
	_start(1)
	_step_tints()
	var tints: RoomTintsScript = _tints()
	var seen := PackedByteArray([2, 0, 2, 0, 0])
	events.emit_signal(&"rooms_seen", seen, true)
	_step_tints(0.0)
	check_equal(tints.stage_of(2), RoomTintsScript.STAGES, "told again after a restore: as it stands, never played in")
	check_equal(_light().tint_count, 2, "both handed over")
	feel.call(&"set_spell_light", false)
	_step_tints(0.0)
	feel.call(&"set_spell_light", true)
	_step_tints(0.0)
	check_equal(_light().tint_count, 2, "a light made anew is handed the tints at once")


func test_with_no_biome_nothing_is_tinted() -> void:
	var tints := RoomTintsScript.new()
	tints.step(FRAME, null, null)
	check_equal(tints.rooms(), 0, "no places, no tints")
	check_equal(tints.tint_at(Vector2.ZERO).a, 0.0, "nothing leans")


# --- Each kind's air ------------------------------------------------------------------------------

func _pool() -> MotesScript:
	var kinds: Array[MoteKind] = [registry.get_resource(&"motes", &"air_dust") as MoteKind, registry.get_resource(&"motes", &"air_glimmer") as MoteKind]
	var motes: MotesScript = own(MotesScript.new(8192, 0, kinds)) as MotesScript
	root.add_child(motes)
	return motes


func _kind_air() -> KindAirScript:
	var air := KindAirScript.new(RampTableScript.new())
	air.pieces = _hearing()
	air.lay(_grid())
	return air


func test_each_rooms_kind_air_stays_in_its_room() -> void:
	_start(1)
	var air: KindAirScript = _kind_air()
	check_equal(air.rooms(), 3, "a kind's air in each of its rooms, none on the bridges")
	var motes: MotesScript = _pool()
	var clock: float = 0.0
	for frame in 240:
		air.give_off(clock, motes, Rect2())
		motes.step(clock)
		clock += DT
	for i in air.rooms():
		var given: int = air.air_of(i).given
		check(given > 0, "room %d's air gives off: %d" % [air.place_of(i), given])
		check(air.rect_of(i).encloses(air.air_of(i).given_box), "room %d's motes all left from inside it: %s in %s" % [air.place_of(i), air.air_of(i).given_box, air.rect_of(i)])
		check(air.air_of(i).look == _hearing().kind_of(air.place_of(i)).air_motes, "its kind's own")


func test_a_kinds_air_is_given_off_only_near_the_view_within_its_share() -> void:
	_start(1)
	var air: KindAirScript = _kind_air()
	var motes: MotesScript = _pool()
	var nave: Rect2 = _grid().place_rect(0)
	var view := Rect2(nave.get_center() - Vector2(80.0, 45.0), Vector2(160.0, 90.0))
	var clock: float = 0.0
	for frame in 120:
		air.give_off(clock, motes, view)
		motes.step(clock)
		clock += DT
	for i in air.rooms():
		if air.place_of(i) == 0:
			check(air.air_of(i).given > 0, "the nave, in view, gives off")
		else:
			check_equal(air.air_of(i).given, 0, "room %d, out of view, gives off nothing" % air.place_of(i))
	var big := KindAirScript.new(RampTableScript.new())
	big.pieces = _hearing()
	big.lay(_grid())
	var rich := MoteSource.new()
	rich.kind = &"air_dust"
	rich.rate = 2000.0
	rich.colours = [&"bone"] as Array[StringName]
	for i in big.rooms():
		big.air_of(i).use(rich)
	clock = 0.0
	for frame in 210:
		big.give_off(clock, motes, Rect2())
		clock += DT
	var total: int = 0
	for i in big.rooms():
		total += big.air_of(i).given
	# air_dust lives 3.5 s on average: at most SHARE of the ring given off over three and a half seconds.
	var most: float = float(motes.cap()) * KindAirScript.SHARE
	check(float(total) <= most + 3.0, "together never more than their share of the ring: %d of %d" % [total, int(most)])


func test_a_frame_of_kind_air_allocates_nothing() -> void:
	_start(1)
	var air: KindAirScript = _kind_air()
	var motes: MotesScript = _pool()
	var clock: float = 0.0
	for frame in 30:
		air.give_off(clock, motes, Rect2())
		motes.step(clock)
		clock += DT
	var objects: float = Performance.get_monitor(Performance.OBJECT_COUNT)
	for frame in 100:
		air.lay(_grid())
		air.give_off(clock, motes, Rect2())
		motes.step(clock)
		clock += DT
	check_equal(Performance.get_monitor(Performance.OBJECT_COUNT), objects, "100 frames make no object")


func test_the_spectacle_lays_each_kinds_air_from_the_biome() -> void:
	_start(1)
	_spectacle().call(&"step", 0.0)
	var air: KindAirScript = _spectacle().get(&"kind_air") as KindAirScript
	check_equal(air.rooms(), 3, "the spectacle lays its kind air from the grid before giving off")
	flow.stop_run()
	_spectacle().call(&"step", 0.1)
	check_equal(air.rooms(), 0, "and lets it go with the biome")


func test_the_apply_pass_holds_as_many_tints_as_the_light_hands_it_by_world_place() -> void:
	var source: String = (load("res://gameplay/feel/light_apply.gdshader") as Shader).code
	# The factor (the tints among it) is worked out in an include, shared with its pass at the light's resolution.
	var factor: String = (load("res://gameplay/feel/light_apply.gdshaderinc") as ShaderInclude).code
	check(factor.contains("#define MAX_TINTS %d" % SpellLightScript.MAX_TINTS), "the shader's MAX_TINTS is SpellLight's")
	check(SpellLightScript.FACTOR_SHADER.code.contains("world_at = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy"), "its pass finds a pixel's room by its world place too")
	check(source.contains("world_at = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy"), "a pixel's room found by its world place, the same in every view")
	# MapRules.rooms_max is at most 32 (its export range), and the start room besides.
	check(SpellLightScript.MAX_TINTS >= 33, "every room of the biggest biome can be tinted")
