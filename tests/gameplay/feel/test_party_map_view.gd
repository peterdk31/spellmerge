extends "res://tests/support/suite.gd"
## The map as this machine draws it (connected biomes CB9): each bridge mouth's kind symbol, big and
## lit, rising in by rows as a wizard comes near (the owner, 2026-11-19), turning over on a reroll; the held Y map, opening over frames inside its own player's view's
## cell only; and the party's map and the dark over the unvisited rooms right on a machine that joins
## mid-run (it hears only the restore). On the real autoloads with the split test map
## (tests/support/biome_maps.gd: the nave the start room, the antechamber west, the ossuary court
## east), Feel's parts stepped by hand.
const FlowScript := preload("res://gameplay/flow/flow.gd")
const TickScript := preload("res://core/sim/tick.gd")
const BiomeMaps := preload("res://tests/support/biome_maps.gd")
const MouthLooksScript := preload("res://gameplay/feel/mouth_looks.gd")
const MouthSymbolsScript := preload("res://gameplay/feel/mouth_symbols.gd")
const KindSymbolScript := preload("res://gameplay/feel/kind_symbol.gd")
const UnseenDarkScript := preload("res://gameplay/feel/unseen_dark.gd")
const PartyMapViewScript := preload("res://gameplay/feel/party_map_view.gd")
const RewardGlyphsScript := preload("res://gameplay/feel/reward_glyphs.gd")
const RoomHearingScript := preload("res://gameplay/feel/room_hearing.gd")
const ScreenViewsScript := preload("res://core/display/screen_views.gd")
const ActorsScript := preload("res://core/actors/actors.gd")
const InputManagerScript := preload("res://core/input/input_manager.gd")
const DT: float = 1.0 / 60.0
const WEST: int = 1
const EAST: int = 2
## The screen the tests split (the game's pixels).
const SCREEN := Vector2(640, 360)

var flow: FlowScript
var events: Node
var tick: TickScript
var input: Node
var registry: Node
var projectiles: Node
var actors: ActorsScript
var feel: Node


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


func after_each() -> void:
	flow.stop_run()
	flow.world_parent = null
	flow.mode = FlowScript.MODE_RUN
	for seat in 4:
		input.leave(seat)
	tick.begin_run()


func _start(players: int) -> BiomeMap:
	var map: BiomeMap = BiomeMaps.split(registry)
	for seat in players:
		input.add_virtual_device(seat)
	var fights: Array[RoomFight] = [RoomFight.new(), RoomFight.new(), RoomFight.new()]
	check(flow.start_biome(0, map, fights), "the biome starts")
	tick.run(DT)
	return map


func _grid() -> RoomGrid:
	return projectiles.call(&"grid") as RoomGrid


func _hearing() -> RoomHearingScript:
	return feel.call(&"room_hearing") as RoomHearingScript


func _wizard(seat: int) -> Actor:
	return flow.get_wizard(seat) as Actor


func _into(map: BiomeMap, room: int, facing: int) -> void:
	_wizard(0).global_position = BiomeMaps.socket_point(registry, map, room, facing) - RoomSocket.way(facing) * 24.0
	tick.run(DT)


## The screen split down its middle: seat 0's view on the left, seat 1's on the right.
static func _two_views() -> ScreenViewsScript:
	var views := ScreenViewsScript.new()
	views.screen = SCREEN
	views.count = 2
	var half: float = SCREEN.x * 0.5
	views.set_view(0, 1, Transform2D.IDENTITY, Vector2(half * 0.5, SCREEN.y * 0.5))
	views.set_view(1, 2, Transform2D.IDENTITY, Vector2(half * 1.5, SCREEN.y * 0.5))
	var corners: Array[PackedVector2Array] = [
		PackedVector2Array([Vector2.ZERO, Vector2(half, 0), Vector2(half, SCREEN.y), Vector2(0, SCREEN.y)]),
		PackedVector2Array([Vector2(half, 0), Vector2(SCREEN.x, 0), SCREEN, Vector2(half, SCREEN.y)]),
	]
	for view in 2:
		for at in 4:
			views.set_corner(view, at, corners[view][at])
		views.set_corners(view, 4)
	return views


func test_a_kind_symbol_is_a_whole_picture() -> void:
	for id: StringName in [&"fight", &"boss", &"start"]:
		var kind: RoomKind = registry.call(&"get_resource", &"room_kinds", id) as RoomKind
		check(kind != null and kind.problems().is_empty(), "%s is a good kind: %s" % [id, kind.problems() if kind != null else []])
		check_equal(kind.symbol_pixels().size(), RoomKind.SYMBOL_SIDE * RoomKind.SYMBOL_SIDE, "%s has a symbol of 7 rows of 7" % id)
	var bad := RoomKind.new()
	bad.id = &"bad"
	bad.symbol = "#..\n.#."
	check(not bad.problems().is_empty() and bad.symbol_pixels().is_empty(), "a symbol of the wrong size is named and drawn as none")
	var none := RoomKind.new()
	none.id = &"hidden"
	check(none.problems().is_empty() and none.symbol_pixels().is_empty(), "no symbol: nothing is told, and nothing is wrong")


## Every mouth's sign is big (SCALE px a symbol pixel), on its bridge outside the mouth and clear of
## its room; it rises in by rows, lit, as a wizard comes near and sinks back once none is (the owner,
## 2026-11-19).
func test_a_mouth_tells_the_kind_behind_it_big_and_lit_rising_as_a_wizard_comes_near() -> void:
	var map: BiomeMap = _start(1)
	var mouths: MouthLooksScript = feel.call(&"mouth_looks") as MouthLooksScript
	var symbols: MouthSymbolsScript = feel.call(&"mouth_symbols") as MouthSymbolsScript
	mouths.step(0.0, _grid())
	symbols.step(0.0, actors, 1, _grid())
	check_equal(symbols.count(), mouths.mouths(), "a symbol a mouth")
	check(MouthSymbolsScript.SCALE >= 3, "big: %d px a symbol pixel" % MouthSymbolsScript.SCALE)
	var side: float = RoomKind.SYMBOL_SIDE * MouthSymbolsScript.SCALE
	var into_west: int = -1
	for mouth in mouths.mouths():
		check(symbols.tells(mouth), "mouth %d tells its room's kind" % mouth)
		var area := Rect2(mouths.area_of(mouth))
		var box := Rect2(symbols.corner_of(mouth), Vector2.ONE * side)
		var on: int = _grid().place_at(box.get_center())
		check(not box.intersects(area) and _hearing().is_walkway(on), "mouth %d's symbol is on its bridge, outside the mouth" % mouth)
		check(not box.intersects(_grid().place_rect(mouths.room_of(mouth))), "clear of its room, which its dark covers until entered")
		check(box.get_center().distance_to(_grid().place_rect(mouths.room_of(mouth)).get_center()) > area.get_center().distance_to(_grid().place_rect(mouths.room_of(mouth)).get_center()), "on the side away from its room")
		check_equal(box.position, box.position.floor(), "in whole pixels")
		if mouths.room_of(mouth) == WEST:
			into_west = mouth
	check(into_west >= 0, "a mouth leads into the antechamber")
	# Far from it: nothing told yet, no light.
	_wizard(0).global_position = _grid().place_rect(EAST).get_center()
	symbols.step(0.0, actors, 1, _grid())
	while symbols.is_moving():
		symbols.advance()
	check_equal(symbols.rows_of(into_west), 0, "far from it, the antechamber's mouth tells nothing")
	check(symbols.light_of(into_west) == null, "and casts no light")
	# Near it: it rises a row a frame, its light brightening with it.
	_wizard(0).global_position = Rect2(mouths.area_of(into_west)).get_center() + Vector2(40.0, 0.0)
	symbols.step(0.0, actors, 1, _grid())
	var rows: Array[int] = []
	var strengths: Array[float] = []
	while symbols.is_moving():
		symbols.advance()
		rows.append(symbols.rows_of(into_west))
		var light: Marker2D = symbols.light_of(into_west)
		strengths.append(LightSpot.strength_of(light) if light != null else 0.0)
	check_equal(rows, [1, 2, 3, 4, 5, 6, 7] as Array[int], "near it, the symbol rises in a row a frame")
	for i in strengths.size():
		check(is_equal_approx(strengths[i], MouthSymbolsScript.LIGHT_STRENGTH * rows[i] / RoomKind.SYMBOL_SIDE), "its light brightens with its rows (%s)" % [strengths])
	var shown: Marker2D = symbols.light_of(into_west)
	check(shown != null and Rect2(symbols.corner_of(into_west), Vector2.ONE * side).has_point(shown.global_position), "lit, its light on it")
	if shown != null:
		check_equal(shown.get_meta(LightSpot.TINT), KindSymbolScript.shades_of(_hearing().kind_of(WEST))[1], "in its kind's light")
	symbols.step(0.0, actors, 0, _grid())
	check(not symbols.is_moving(), "with no seat played here (a recording), anyone's wizard near tells, as the camera holds everyone")
	symbols.step(0.0, actors, 0b0010, _grid())
	check(not symbols.is_moving(), "and with a seat here that has no wizard yet")
	# From inside the room it leads to: it tells nothing new and sinks a row a frame.
	_wizard(0).global_position = _grid().place_rect(WEST).get_center()
	symbols.step(0.0, actors, 1, _grid())
	rows.clear()
	while symbols.is_moving():
		symbols.advance()
		rows.append(symbols.rows_of(into_west))
	check_equal(rows, [6, 5, 4, 3, 2, 1, 0] as Array[int], "no wizard near: it sinks back the same way")
	check(symbols.light_of(into_west) == null, "its light out")
	check(map != null, "the map")


func test_the_y_map_opens_over_frames_inside_its_own_players_view_only() -> void:
	var map: BiomeMap = _start(2)
	var view: PartyMapViewScript = feel.call(&"party_map") as PartyMapViewScript
	var views: ScreenViewsScript = _two_views()
	view.input = input as InputManagerScript
	input.call(&"send_virtual", 1, PartyMapViewScript.ACTION, 1.0)
	view.step(0.0, actors, 3, _grid(), views)
	check_equal(view.stage_of(1), 0, "a world drawn as it was: the map is still shut")
	var stages: Array[int] = []
	var tall: Array[int] = []
	while view.is_moving():
		view.advance()
		view.step(0.0, actors, 3, _grid(), views)
		stages.append(view.stage_of(1))
		tall.append(view.shown_rect(1).size.y)
	check_equal(stages, [1, 2, 3, 4] as Array[int], "held, it opens a stage a frame")
	check(tall[0] < tall[1] and tall[1] < tall[2] and tall[2] < tall[3], "from its middle row out: %s" % [tall])
	check_equal(view.stage_of(0), 0, "the other player's map stays shut: nobody else stops")
	check(view.shown_rect(0).size == Vector2i.ZERO, "and draws nothing")
	var frame: Rect2i = view.frame_of(1)
	var cell := Rect2(Vector2(SCREEN.x * 0.5, 0.0), Vector2(SCREEN.x * 0.5, SCREEN.y))
	check(cell.grow(-PartyMapViewScript.EDGE + 0.01).encloses(Rect2(frame)), "inside its own view's cell: %s" % frame)
	check(view.scale_of(1) >= 1, "a whole scale")
	# Seat 0 is played on another machine: its hold is not this machine's to draw.
	input.call(&"send_virtual", 0, PartyMapViewScript.ACTION, 1.0)
	view.step(0.0, actors, 2, _grid(), views)
	while view.is_moving():
		view.advance()
	check_equal(view.stage_of(0), 0, "a seat of another machine never opens a map here")
	# Let go: it closes the same way back.
	input.call(&"send_virtual", 1, PartyMapViewScript.ACTION, 0.0)
	view.step(0.0, actors, 3, _grid(), views)
	var closing: Array[int] = []
	while view.is_moving():
		view.advance()
		closing.append(view.stage_of(1))
	check_equal(closing, [3, 2, 1, 0] as Array[int], "let go, it closes a stage a frame")
	check(map != null, "the map")


func test_the_map_shows_the_rooms_seen_the_bridges_from_them_and_the_kinds_they_lead_to() -> void:
	var map: BiomeMap = _start(1)
	var view: PartyMapViewScript = feel.call(&"party_map") as PartyMapViewScript
	view.step(0.0, actors, 1, _grid(), _two_views())
	check_equal(view.places(), 5, "every piece")
	check(view.draws(0), "the start room, entered")
	check(not view.draws(WEST) and not view.draws(EAST), "the rooms not seen are not drawn")
	check(view.draws(3) and view.draws(4), "the bridges from the start room are")
	check(view.draws_symbol(WEST) and view.draws_symbol(EAST), "and the kinds they lead to, as their mouths tell")
	var floor: ImageTexture = PartyMapViewScript.floor_of(_grid(), 0)
	check(floor != null and floor.get_width() == ceili(_grid().place_rect(0).size.x / PartyMapViewScript.MAP_CELL), "a room's floor at a map pixel a MAP_CELL")
	_into(map, WEST, RoomSocket.Facing.EAST)
	view.step(0.0, actors, 1, _grid(), _two_views())
	check(view.draws(WEST), "entered, the antechamber is drawn")
	check_equal(view.shade_of(WEST), 3, "with every map shut, as it stands: the stone's light")


## The run stat `secret_sense` (the owner's answer of 2026-11-19): a secret room within that many
## pixels of a room the party entered shows on that player's own map only, worked out from the party's
## map and the seat's stat as told (`run_stats_told`).
func test_a_players_secret_sense_shows_a_secret_room_near_on_their_own_map_only() -> void:
	var map: BiomeMap = BiomeMaps.split(registry, [0, 0, 0] as Array[int], [BiomeMaps.FIRST, BiomeMaps.MIDDLE, BiomeMaps.LAST] as Array[StringName], [&"fight", &"start", &"secret"] as Array[StringName])
	for seat in 2:
		input.add_virtual_device(seat)
	check(flow.start_biome(0, map, [RoomFight.new(), RoomFight.new(), RoomFight.new()] as Array[RoomFight]), "the biome starts")
	tick.run(DT)
	var view: PartyMapViewScript = feel.call(&"party_map") as PartyMapViewScript
	view.step(0.0, actors, 3, _grid(), _two_views())
	check(not view.draws(EAST), "the secret room is not on the party's map")
	check(not view.senses(0, EAST) and view.sense_shade_of(0, EAST) == 0, "no sense (the base, 0): nobody's map shows it")
	var gap: float = PartyMapViewScript.gap_between(_grid().place_rect(EAST), _grid().place_rect(0))
	check(gap > 0.0, "the secret room lies a bridge away from the start room")
	events.run_stats_told.emit(0, {&"secret_sense": gap - 1.0})
	check(not view.senses(0, EAST), "a sense short of it shows nothing")
	events.run_stats_told.emit(0, {&"secret_sense": gap + 1.0})
	check(view.senses(0, EAST), "within the seat's sense of a room entered: sensed")
	check_equal(view.sense_shade_of(0, EAST), PartyMapViewScript.SENSED_STAGES, "drawn on that player's map in its own look, the void's faint light (every map shut: as it stands)")
	check(not view.senses(1, EAST) and view.sense_shade_of(1, EAST) == 0, "never on another player's map")
	check(not view.senses(0, WEST), "a room that is no secret one is never sensed")
	check(not view.draws(EAST), "the party's map is as it was")


## The owner, 2026-11-19: a sensed secret room reads as secret, in a faint void light of its own,
## not the stone's shadow of a room only shown; on an open map it comes in through its stages.
func test_a_sensed_secret_room_comes_in_through_its_own_void_light() -> void:
	var map: BiomeMap = BiomeMaps.split(registry, [0, 0, 0] as Array[int], [BiomeMaps.FIRST, BiomeMaps.MIDDLE, BiomeMaps.LAST] as Array[StringName], [&"fight", &"start", &"secret"] as Array[StringName])
	input.add_virtual_device(0)
	check(flow.start_biome(0, map, [RoomFight.new(), RoomFight.new(), RoomFight.new()] as Array[RoomFight]), "the biome starts")
	tick.run(DT)
	var view: PartyMapViewScript = feel.call(&"party_map") as PartyMapViewScript
	var views: ScreenViewsScript = _two_views()
	view.input = input as InputManagerScript
	input.call(&"send_virtual", 0, PartyMapViewScript.ACTION, 1.0)
	view.step(0.0, actors, 1, _grid(), views)
	while view.is_moving():
		view.advance()
		view.step(0.0, actors, 1, _grid(), views)
	check_equal(view.stage_of(0), PartyMapViewScript.OPEN_STAGES, "open")
	var gap: float = PartyMapViewScript.gap_between(_grid().place_rect(EAST), _grid().place_rect(0))
	events.run_stats_told.emit(0, {&"secret_sense": gap + 1.0})
	var stages: Array[int] = [view.sense_shade_of(0, EAST)]
	while view.is_moving():
		view.advance()
		view.step(0.0, actors, 1, _grid(), views)
		stages.append(view.sense_shade_of(0, EAST))
	check_equal(stages, [0, 1, 2, 3] as Array[int], "on an open map it comes in a stage a frame")
	check_equal(view.drawn_colour(0, EAST), Palette.shades_of(&"void")[1], "it rests in the void's faint light: it reads as secret")
	check_equal(view.drawn_colour(1, EAST), Color.TRANSPARENT, "not on another player's map")
	# The party's map takes it over (shown to all, as a seen room's neighbour is): it steps down
	# through the void's shadow to the stone's, never in one jump (the review's).
	var seen: PackedByteArray = flow.party_map.seen.duplicate()
	seen[EAST] = 1
	events.rooms_seen.emit(seen, false)
	var looks: Array[Color] = [view.drawn_colour(0, EAST)]
	while view.is_moving():
		view.advance()
		view.step(0.0, actors, 1, _grid(), views)
		if view.drawn_colour(0, EAST) != looks.back():
			looks.append(view.drawn_colour(0, EAST))
	var stone: PackedColorArray = Palette.shades_of(&"stone")
	var voids: PackedColorArray = Palette.shades_of(&"void")
	check_equal(looks, [voids[1], voids[0], stone[0]] as Array[Color], "void light, void shadow, then the stone's shadow of a room shown, a look a frame")


func test_on_an_open_map_a_room_comes_in_through_the_shades_and_a_new_size_reopens() -> void:
	var map: BiomeMap = _start(1)
	var view: PartyMapViewScript = feel.call(&"party_map") as PartyMapViewScript
	var views: ScreenViewsScript = _two_views()
	view.input = input as InputManagerScript
	input.call(&"send_virtual", 0, PartyMapViewScript.ACTION, 1.0)
	view.step(0.0, actors, 1, _grid(), views)
	while view.is_moving():
		view.advance()
		view.step(0.0, actors, 1, _grid(), views)
	check_equal(view.stage_of(0), PartyMapViewScript.OPEN_STAGES, "open")
	check_equal(view.shade_of(WEST), 0, "the antechamber not drawn")
	check_equal(view.symbol_rows_of(WEST), RoomKind.SYMBOL_SIDE, "but its symbol, as its bridge leads there")
	_into(map, WEST, RoomSocket.Facing.EAST)
	view.step(0.0, actors, 1, _grid(), views)
	var shades: Array[int] = []
	while view.is_moving():
		view.advance()
		shades.append(view.shade_of(WEST))
	check_equal(shades, [1, 2, 3] as Array[int], "entered while the map is open: it comes in a shade a frame")
	# The screen merges under it: one view of the whole screen, a bigger frame. It closes, then opens again.
	var frame: Rect2i = view.frame_of(0)
	var one := ScreenViewsScript.new()
	one.set_single(SCREEN, Transform2D.IDENTITY, 1)
	view.step(0.0, actors, 1, _grid(), one)
	check_equal(view.frame_of(0).size, frame.size, "no jump: the frame keeps its size this frame")
	var stages: Array[int] = []
	while view.is_moving():
		view.advance()
		view.step(0.0, actors, 1, _grid(), one)
		stages.append(view.stage_of(0))
	check_equal(stages, [3, 2, 1, 0, 1, 2, 3, 4] as Array[int], "it closes and opens again")
	check(view.frame_of(0).size != frame.size, "at its new size")


func test_the_map_stays_shut_while_a_menu_holds_the_player_or_no_view_holds_it() -> void:
	_start(2)
	var view: PartyMapViewScript = feel.call(&"party_map") as PartyMapViewScript
	view.input = input as InputManagerScript
	input.call(&"send_virtual", 0, PartyMapViewScript.ACTION, 1.0)
	input.call(&"set_captured", 0, true)
	view.step(0.0, actors, 1, _grid(), _two_views())
	check(not view.is_moving() and view.stage_of(0) == 0, "its builder open (Y is the builder's): no map")
	input.call(&"set_captured", 0, false)
	# Split, but no view holds seat 2: never over another player's view.
	input.call(&"add_virtual_device", 2)
	input.call(&"send_virtual", 2, PartyMapViewScript.ACTION, 1.0)
	view.step(0.0, actors, 4, _grid(), _two_views())
	view.advance()
	view.step(0.0, actors, 4, _grid(), _two_views())
	check(view.shown_rect(2).size == Vector2i.ZERO, "no map drawn for a seat no view holds")


func test_a_machine_that_joins_mid_run_has_the_map_and_the_dark_right() -> void:
	var map: BiomeMap = _start(1)
	_into(map, WEST, RoomSocket.Facing.EAST)
	var snapshot := Snapshot.take(tick.state_areas(), root)
	# A joining machine's view: it heard nothing of the run but the restore.
	var dark := UnseenDarkScript.new()
	dark.pieces = _hearing()
	own(dark)
	root.add_child(dark)
	dark.bind(events)
	var view := PartyMapViewScript.new()
	view.pieces = _hearing()
	own(view)
	root.add_child(view)
	view.bind(events)
	check(snapshot.restore(tick.state_areas(), root).is_empty(), "restored")
	dark.step(0.0, _grid())
	view.step(0.0, actors, 1, _grid(), _two_views())
	var darkest: int = UnseenDarkScript.BLOCK_SIDES.size() - 1
	check_equal(dark.stage_of(0), 0, "the start room lit")
	check_equal(dark.stage_of(WEST), 0, "the antechamber, entered before the join, lit at once")
	check_equal(dark.stage_of(EAST), darkest, "the court dark")
	check(not dark.is_moving(), "drawn as it stands, nothing played in")
	check(view.draws(0) and view.draws(WEST) and not view.draws(EAST), "the joiner's map: the rooms entered before it came")


func test_a_restore_into_the_world_shown_draws_the_dark_as_it_stands() -> void:
	var map: BiomeMap = _start(1)
	var dark: UnseenDarkScript = feel.call(&"unseen_dark") as UnseenDarkScript
	dark.step(0.0, _grid())
	var later_entered := Snapshot.take(tick.state_areas(), root)
	var darkest: int = UnseenDarkScript.BLOCK_SIDES.size() - 1
	_into(map, WEST, RoomSocket.Facing.EAST)
	_into(map, EAST, RoomSocket.Facing.WEST)
	var both := Snapshot.take(tick.state_areas(), root)
	check(later_entered.restore(tick.state_areas(), root).is_empty(), "back to the start")
	dark.step(0.0, _grid())
	while dark.is_moving():
		dark.advance()
	check_equal(dark.stage_of(EAST), darkest, "the court dark")
	check(both.restore(tick.state_areas(), root).is_empty(), "a restore into the same world, both rooms entered")
	dark.step(0.0, _grid())
	check_equal(dark.stage_of(WEST), 0, "the antechamber lit at once")
	check_equal(dark.stage_of(EAST), 0, "the court too")
	check(not dark.is_moving(), "nothing played in")


## A reward room's type (the owner's ask of 2026-11-19, `RewardType`): its mouth's sign tells it
## beside the kind symbol (its item kind, card kind and element, a glyph each), rising with it by
## rows in whole pixels; the held map shows it under the room's symbol; a room of no type tells only
## its kind.
func test_a_reward_rooms_mouth_and_the_map_tell_its_type() -> void:
	var map: BiomeMap = BiomeMaps.split(registry, [0, 0, 0] as Array[int], [BiomeMaps.FIRST, BiomeMaps.MIDDLE, BiomeMaps.LAST] as Array[StringName], [&"reward", &"start", &"fight"] as Array[StringName])
	map.type_room(WEST, RewardType.make(ItemKinds.CARD, &"element", &"fire"))
	input.add_virtual_device(0)
	var fights: Array[RoomFight] = [RoomFight.new(), RoomFight.new(), RoomFight.new()]
	check(flow.start_biome(0, map, fights), "the biome starts")
	tick.run(DT)
	var mouths: MouthLooksScript = feel.call(&"mouth_looks") as MouthLooksScript
	var symbols: MouthSymbolsScript = feel.call(&"mouth_symbols") as MouthSymbolsScript
	mouths.step(0.0, _grid())
	symbols.step(0.0, actors, 1, _grid())
	check(_hearing().type_of(WEST) != null and _hearing().type_of(WEST).same_as(map.reward_type_of(WEST)), "the view hears the reward room's type from its layout")
	check(_hearing().type_of(EAST) == null, "a fight room has none")
	var into_west: int = -1
	for mouth in mouths.mouths():
		if mouths.room_of(mouth) == WEST:
			into_west = mouth
			check_equal(symbols.glyphs_of(mouth), 3, "the reward room's mouth tells its item kind, card kind and element")
			var corner: Vector2 = symbols.glyph_corner_of(mouth)
			check_equal(corner, corner.floor(), "in whole pixels")
			var scale: int = MouthSymbolsScript.SCALE
			var glyphs := Rect2(corner, Vector2(RewardGlyphsScript.row_width(3), RewardGlyphsScript.SIDE) * scale) if Rect2(mouths.area_of(mouth)).size.x > Rect2(mouths.area_of(mouth)).size.y else Rect2(corner, Vector2(RewardGlyphsScript.SIDE, RewardGlyphsScript.row_width(3)) * scale)
			check(not glyphs.intersects(Rect2(mouths.area_of(mouth))), "beside the symbol, outside the mouth")
			check(not glyphs.intersects(Rect2(symbols.corner_of(mouth), Vector2.ONE * RoomKind.SYMBOL_SIDE * scale)), "and clear of the symbol")
		else:
			check_equal(symbols.glyphs_of(mouth), 0, "a mouth into a room of no type tells only its kind")
	check(into_west >= 0, "a mouth leads into the reward room")
	_wizard(0).global_position = Rect2(mouths.area_of(into_west)).get_center() + Vector2(40.0, 0.0)
	symbols.step(0.0, actors, 1, _grid())
	var frames: int = 0
	while symbols.is_moving():
		symbols.advance()
		frames += 1
	check(frames >= 3, "the sign rises over at least 3 frames (Smooth): %d" % frames)
	var view: PartyMapViewScript = feel.call(&"party_map") as PartyMapViewScript
	view.step(0.0, actors, 1, _grid(), _two_views())
	check(view.draws_symbol(WEST), "the map shows the reward room led to")
	check_equal(view.glyphs_of(WEST), 3, "with its type")
	check_equal(view.glyphs_of(EAST), 0, "a fight room with none")
	var corner: Vector2 = PartyMapViewScript.glyphs_corner(Vector2(41, 30), 3, 2)
	check_equal(corner, corner.floor(), "the map's glyphs in whole pixels")
	check(corner.y >= 30.0 + RoomKind.SYMBOL_SIDE, "under the room's symbol")


## The glyphs a type makes: one a level it names, each a whole SIDE-square picture; an element in the
## palette light nearest its tint, never a player's.
func test_a_reward_types_glyphs() -> void:
	var pixels: Array[PackedByteArray] = []
	var shades: Array[PackedColorArray] = []
	RewardGlyphsScript.glyphs_of(RewardType.make(ItemKinds.POTION), null, pixels, shades)
	check_equal(pixels.size(), 1, "a potion room: its item kind alone")
	RewardGlyphsScript.glyphs_of(RewardType.make(ItemKinds.CARD, &"modifier"), null, pixels, shades)
	check_equal(pixels.size(), 2, "a modifier room: a card and its kind")
	RewardGlyphsScript.glyphs_of(RewardType.new(), null, pixels, shades)
	check_equal(pixels.size(), 0, "no type: nothing")
	for picture: String in RewardGlyphsScript.ITEM_PICTURES.values() + RewardGlyphsScript.KIND_PICTURES.values() + [RewardGlyphsScript.ELEMENT_PICTURE, RewardGlyphsScript.UNKNOWN]:
		var lines: PackedStringArray = picture.split("\n")
		check(lines.size() == RewardGlyphsScript.SIDE and Array(lines).all(func(line: String) -> bool: return line.length() == RewardGlyphsScript.SIDE), "a glyph is %d rows of %d: %s" % [RewardGlyphsScript.SIDE, RewardGlyphsScript.SIDE, picture])
	var fire := registry.call(&"get_resource", &"spells", &"fire") as ElementBase
	check_equal(RewardGlyphsScript.element_shades(fire), Palette.shades_of(&"fire"), "fire in the fire's light")
	for id: StringName in [&"fire", &"frost", &"lightning", &"mend", &"storm", &"void", &"water"]:
		var element := registry.call(&"get_resource", &"spells", id) as ElementBase
		var light: PackedColorArray = RewardGlyphsScript.element_shades(element)
		check(light.size() == 3, "%s has a light" % id)
		for owned: StringName in Palette.OWNED:
			check(light != Palette.shades_of(owned), "%s is in no owned colour" % id)


# --- A room reroll (the owner, 2026-11-19): the signs and the open map turn over, Smooth ---------

## The split map as the world has it, its west room a fountain (a reroll's answer).
func _rerolled_west() -> BiomeMap:
	var made: BiomeMap = flow.biome.map.copy()
	made.room_kinds[WEST] = &"fountain"
	return made


func test_a_rerolled_rooms_sign_sinks_out_and_its_new_one_rises() -> void:
	var map: BiomeMap = _start(1)
	var mouths: MouthLooksScript = feel.call(&"mouth_looks") as MouthLooksScript
	var symbols: MouthSymbolsScript = feel.call(&"mouth_symbols") as MouthSymbolsScript
	mouths.step(0.0, _grid())
	symbols.step(0.0, actors, 1, _grid())
	var into_west: int = -1
	for mouth in mouths.mouths():
		if mouths.room_of(mouth) == WEST:
			into_west = mouth
	_wizard(0).global_position = Rect2(mouths.area_of(into_west)).get_center() + Vector2(40.0, 0.0)
	symbols.step(0.0, actors, 1, _grid())
	while symbols.is_moving():
		symbols.advance()
	check_equal(symbols.rows_of(into_west), RoomKind.SYMBOL_SIDE, "the fight's sign shown")
	var old_light: Marker2D = symbols.light_of(into_west)
	flow.call(&"_reroll_room", WEST, _rerolled_west(), RoomFight.new())
	mouths.step(0.0, _grid())
	symbols.step(0.0, actors, 1, _grid())
	check(symbols.is_turning(into_west), "the sign turns over")
	check_equal(symbols.rows_of(into_west), RoomKind.SYMBOL_SIDE, "no jump: the old sign still shows")
	var rows: Array[int] = []
	var strengths: Array[float] = []
	while symbols.is_moving():
		symbols.advance()
		rows.append(symbols.rows_of(into_west))
		var light: Marker2D = symbols.light_of(into_west)
		strengths.append(LightSpot.strength_of(light) if light != null else 0.0)
	check_equal(rows, [6, 5, 4, 3, 2, 1, 0, 1, 2, 3, 4, 5, 6, 7] as Array[int], "it sinks out a row a frame and the new one rises")
	for i in strengths.size():
		check(is_equal_approx(strengths[i], MouthSymbolsScript.LIGHT_STRENGTH * rows[i] / RoomKind.SYMBOL_SIDE), "its light follows its rows, never a jump (%s)" % [strengths])
	check(not symbols.is_turning(into_west), "turned")
	check(symbols.light_of(into_west) != old_light and symbols.light_of(into_west).get_meta(LightSpot.TINT) == KindSymbolScript.shades_of(_hearing().kind_of(WEST))[1], "its light is the new kind's")
	check(map != null, "the map")


func test_an_open_map_stays_open_over_a_reroll_and_the_room_comes_in_again() -> void:
	_start(1)
	var view: PartyMapViewScript = feel.call(&"party_map") as PartyMapViewScript
	var views: ScreenViewsScript = _two_views()
	view.input = input as InputManagerScript
	input.call(&"send_virtual", 0, PartyMapViewScript.ACTION, 1.0)
	view.step(0.0, actors, 1, _grid(), views)
	while view.is_moving():
		view.advance()
		view.step(0.0, actors, 1, _grid(), views)
	check_equal(view.stage_of(0), PartyMapViewScript.OPEN_STAGES, "open")
	check_equal(view.symbol_rows_of(WEST), RoomKind.SYMBOL_SIDE, "the antechamber's symbol drawn")
	flow.call(&"_reroll_room", WEST, _rerolled_west(), RoomFight.new())
	view.step(0.0, actors, 1, _grid(), views)
	check_equal(view.stage_of(0), PartyMapViewScript.OPEN_STAGES, "still open: a reroll closes nothing")
	check_equal(view.symbol_rows_of(WEST), 0, "the rerolled room's symbol comes in again")
	var rows: Array[int] = []
	while view.is_moving():
		view.advance()
		rows.append(view.symbol_rows_of(WEST))
	check_equal(rows, [1, 2, 3, 4, 5, 6, 7] as Array[int], "a row a frame")
	input.call(&"send_virtual", 0, PartyMapViewScript.ACTION, 0.0)
