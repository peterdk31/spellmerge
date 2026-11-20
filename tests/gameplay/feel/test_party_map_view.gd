extends "res://tests/support/suite.gd"
## The map as this machine draws it (connected biomes CB9): each bridge mouth's kind symbol, big and
## lit, rising in by rows as a wizard comes near (the owner, 2026-11-19); the held Y map, opening over frames inside its own player's view's
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
const EventsScript := preload("res://core/events/events.gd")
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


## The cleared look (the owner, 2026-11-20, #883): stepped, whole shades of the symbol's own
## palette, the check drawn a pixel a stage, and only for a kind with a fight.
func test_the_cleared_look_dims_the_symbol_and_draws_a_check_in_stages() -> void:
	check(KindSymbolScript.CLEARED_STAGES >= 3, "at least 3 frames between the two looks")
	var shades: PackedColorArray = KindSymbolScript.shades_of(registry.call(&"get_resource", &"room_kinds", &"fight") as RoomKind)
	check_equal(KindSymbolScript.colour_of(RoomKind.SYMBOL_LIT, shades, 0), shades[2], "uncleared: lit pixels in the light")
	check_equal(KindSymbolScript.colour_of(RoomKind.SYMBOL_BASE, shades, 0), shades[1], "and the base in the base")
	var last_lit: Color = shades[2]
	var last_base: Color = shades[1]
	for stage in range(1, KindSymbolScript.CLEARED_STAGES + 1):
		var lit: Color = KindSymbolScript.colour_of(RoomKind.SYMBOL_LIT, shades, stage)
		var base: Color = KindSymbolScript.colour_of(RoomKind.SYMBOL_BASE, shades, stage)
		check(shades.has(lit) and shades.has(base), "stage %d: the symbol's own shades, nothing blended" % stage)
		check(shades.find(last_lit) - shades.find(lit) <= 1 and shades.find(last_base) - shades.find(base) <= 1, "stage %d dims a shade at most" % stage)
		check_equal(KindSymbolScript.check_shown(stage) - KindSymbolScript.check_shown(stage - 1), 1, "stage %d draws one more pixel of the check" % stage)
		last_lit = lit
		last_base = base
	check_equal(last_lit, shades[0], "cleared: lit pixels in the shadow")
	check_equal(last_base, shades[0], "the base in the shadow")
	check_equal(KindSymbolScript.check_shown(KindSymbolScript.CLEARED_STAGES), KindSymbolScript.CHECK.size(), "the whole check at the end")
	for pixel: Vector2i in KindSymbolScript.CHECK:
		check(pixel.x >= 0 and pixel.x < RoomKind.SYMBOL_SIDE and pixel.y >= 0 and pixel.y < RoomKind.SYMBOL_SIDE, "the check is inside the symbol's box")
	for index in range(1, KindSymbolScript.CHECK.size()):
		var step: Vector2i = (KindSymbolScript.CHECK[index] - KindSymbolScript.CHECK[index - 1]).abs()
		check(step.x <= 1 and step.y <= 1, "the check is one stroke, a pixel beside the last")
	check(Palette.shades_of(&"leaf").has(KindSymbolScript.CHECK_COLOUR), "the check in a palette colour")
	# What makes each kind done (the owner, 2026-11-20, #883 and after #884; never a shop).
	var rules: Dictionary = {
		&"fight": KindSymbolScript.DONE_CLEARED, &"challenge": KindSymbolScript.DONE_CLEARED, &"boss": KindSymbolScript.DONE_CLEARED,
		&"treasure": KindSymbolScript.DONE_OPENED, &"fountain": KindSymbolScript.DONE_USED, &"reward": KindSymbolScript.DONE_TAKEN,
		&"secret": KindSymbolScript.DONE_NEVER, &"start": KindSymbolScript.DONE_NEVER, &"shop": KindSymbolScript.DONE_NEVER,
	}
	for id: StringName in rules:
		var kind: RoomKind = registry.call(&"get_resource", &"room_kinds", id) as RoomKind
		check_equal(KindSymbolScript.done_by(kind), int(rules[id]), "a %s room's done rule" % id)
		check_equal(KindSymbolScript.shows_done(kind), int(rules[id]) != KindSymbolScript.DONE_NEVER, "a %s room shows it done or not" % id)
	check_equal(KindSymbolScript.done_by(null), KindSymbolScript.DONE_NEVER, "no kind: never")


## A fight room cleared: every doorway sign into it steps to the cleared look a stage a frame, its
## light dimming with it, and the map's symbol shows it; the rooms not cleared keep their look.
func test_a_cleared_rooms_doorway_signs_and_map_symbol_show_it_cleared() -> void:
	var map: BiomeMap = _start(1)
	var mouths: MouthLooksScript = feel.call(&"mouth_looks") as MouthLooksScript
	var symbols: MouthSymbolsScript = feel.call(&"mouth_symbols") as MouthSymbolsScript
	var view: PartyMapViewScript = feel.call(&"party_map") as PartyMapViewScript
	mouths.step(0.0, _grid())
	symbols.step(0.0, actors, 1, _grid())
	for mouth in symbols.count():
		check_equal(symbols.cleared_of(mouth), 0, "mouth %d: nothing cleared yet" % mouth)
	check(not _hearing().is_cleared(WEST), "the antechamber not cleared")
	check(not _hearing().is_done(WEST), "nor done")
	_into(map, WEST, RoomSocket.Facing.EAST)
	check(_hearing().is_cleared(WEST), "its empty fight cleared as entered, told to the view")
	check(not _hearing().is_cleared(EAST), "the court not")
	# Back on its bridge, so its sign shows while it changes.
	var into_west: int = -1
	for mouth in mouths.mouths():
		if mouths.room_of(mouth) == WEST:
			into_west = mouth
	_wizard(0).global_position = Rect2(mouths.area_of(into_west)).get_center() + Vector2(40.0, 0.0)
	symbols.step(0.0, actors, 1, _grid())
	var stages: Array[int] = []
	var strengths: Array[float] = []
	while symbols.is_moving():
		symbols.advance()
		if stages.is_empty() or stages[stages.size() - 1] != symbols.cleared_of(into_west):
			stages.append(symbols.cleared_of(into_west))
		var light: Marker2D = symbols.light_of(into_west)
		strengths.append(LightSpot.strength_of(light) if light != null else 0.0)
	check_equal(stages, [1, 2, 3, 4, 5, 6, 7] as Array[int], "it steps to the cleared look a stage at a time, while its sign rises")
	check(is_equal_approx(strengths[strengths.size() - 1], MouthSymbolsScript.LIGHT_STRENGTH * MouthSymbolsScript.CLEARED_LIGHT), "its light dimmed (%s)" % [strengths])
	for i in range(1, strengths.size()):
		check(absf(strengths[i] - strengths[i - 1]) <= MouthSymbolsScript.LIGHT_STRENGTH / RoomKind.SYMBOL_SIDE + 0.0001, "and never jumps, up or down")
	for mouth in symbols.count():
		var room: int = mouths.room_of(mouth)
		check_equal(symbols.cleared_of(mouth), KindSymbolScript.CLEARED_STAGES if room == WEST else 0, "mouth %d into room %d" % [mouth, room])
	view.step(0.0, actors, 1, _grid(), _two_views())
	check_equal(view.cleared_of(WEST), KindSymbolScript.CLEARED_STAGES, "the shut map has the antechamber cleared as it stands")
	check_equal(view.cleared_of(EAST), 0, "the court not")
	check_equal(view.cleared_of(0), 0, "the start room tells nothing by it")
	# On an open map, the court cleared steps in a stage a frame.
	view.input = input as InputManagerScript
	input.call(&"send_virtual", 0, PartyMapViewScript.ACTION, 1.0)
	view.step(0.0, actors, 1, _grid(), _two_views())
	while view.is_moving():
		view.advance()
		view.step(0.0, actors, 1, _grid(), _two_views())
	_into(map, EAST, RoomSocket.Facing.WEST)
	view.step(0.0, actors, 1, _grid(), _two_views())
	var court: Array[int] = []
	while view.is_moving():
		view.advance()
		court.append(view.cleared_of(EAST))
	check_equal(court, [1, 2, 3, 4, 5, 6, 7] as Array[int], "open, the court's symbol steps to it a stage a frame")


## After a restore the cleared look is drawn as it stands, either way, nothing played in.
func test_a_restore_draws_the_cleared_look_as_it_stands() -> void:
	var map: BiomeMap = _start(1)
	var symbols: MouthSymbolsScript = feel.call(&"mouth_symbols") as MouthSymbolsScript
	var mouths: MouthLooksScript = feel.call(&"mouth_looks") as MouthLooksScript
	var view: PartyMapViewScript = feel.call(&"party_map") as PartyMapViewScript
	var before := Snapshot.take(tick.state_areas(), root)
	_into(map, WEST, RoomSocket.Facing.EAST)
	var after := Snapshot.take(tick.state_areas(), root)
	check(before.restore(tick.state_areas(), root).is_empty(), "back to before the clear")
	mouths.step(0.0, _grid())
	symbols.step(0.0, actors, 1, _grid())
	view.step(0.0, actors, 1, _grid(), _two_views())
	check(not _hearing().is_cleared(WEST), "told: not cleared")
	for mouth in symbols.count():
		check_equal(symbols.cleared_of(mouth), 0, "mouth %d as it stands" % mouth)
	check(after.restore(tick.state_areas(), root).is_empty(), "into the cleared one")
	mouths.step(0.0, _grid())
	symbols.step(0.0, actors, 1, _grid())
	view.step(0.0, actors, 1, _grid(), _two_views())
	for mouth in symbols.count():
		check_equal(symbols.cleared_of(mouth), KindSymbolScript.CLEARED_STAGES if mouths.room_of(mouth) == WEST else 0, "mouth %d as it stands" % mouth)
	check_equal(view.cleared_of(WEST), KindSymbolScript.CLEARED_STAGES, "the map too")
	# A restore with the map held open: drawn as it stands, nothing stepped.
	check(before.restore(tick.state_areas(), root).is_empty(), "back again")
	view.input = input as InputManagerScript
	input.call(&"send_virtual", 0, PartyMapViewScript.ACTION, 1.0)
	view.step(0.0, actors, 1, _grid(), _two_views())
	while view.is_moving():
		view.advance()
		view.step(0.0, actors, 1, _grid(), _two_views())
	check(view.stage_of(0) > 0 and view.cleared_of(WEST) == 0, "open, the antechamber not cleared")
	check(after.restore(tick.state_areas(), root).is_empty(), "into the cleared one, the map open")
	view.step(0.0, actors, 1, _grid(), _two_views())
	check_equal(view.cleared_of(WEST), KindSymbolScript.CLEARED_STAGES, "cleared as it stands at once, on an open map too")
	flow.stop_run()
	check(not _hearing().is_cleared(WEST), "the biome gone, nothing cleared")


## The room hearing tells each kind done by its own rule (the owner, 2026-11-20, after #884), from
## what each sender told: a fight cleared (Flow's `rooms_cleared`), a treasure room opened (Flow's
## `rooms_opened`), a fountain used (Rewards' `fountain_changed`: drawn on at all), a reward room
## entered with no reward left in it (Rewards' `rooms_rewards_left`); a shop never. Each told
## `again` changes `cleared_again`, so the looks draw it as it stands.
func test_the_room_hearing_tells_each_kind_done_by_its_own_rule() -> void:
	var bus := own(EventsScript.new()) as EventsScript
	var hearing := RoomHearingScript.new()
	hearing.registry = registry
	hearing.bind(bus)
	var kinds: Array[StringName] = [&"start", &"fight", &"treasure", &"fountain", &"reward", &"shop"]
	for number in kinds.size():
		var layout := own(Node.new()) as Node
		layout.set_meta(RoomKind.LAYOUT_META, String(kinds[number]))
		bus.room_built.emit(&"", number, layout)
	for room in kinds.size():
		check(not hearing.is_done(room), "%s: nothing done yet" % kinds[room])
	# Every room cleared (a reward room and a shop are cleared as they are entered).
	var all := PackedByteArray([1, 1, 1, 1, 1, 1])
	bus.rooms_cleared.emit(all, false)
	bus.rooms_rewards_left.emit(PackedByteArray([0, 1, 0, 0, 1]), false)
	check(hearing.is_done(1), "the fight: cleared")
	check(not hearing.is_done(2), "the treasure room: not opened yet")
	check(not hearing.is_done(3), "the fountain: not used yet")
	check(not hearing.is_done(4), "the reward room: entered, its reward still lying there")
	check(not hearing.is_done(0) and not hearing.is_done(5), "the start room and the shop never")
	bus.rooms_opened.emit(PackedByteArray([0, 0, 1]), false)
	check(hearing.is_done(2), "the treasure room: opened")
	bus.fountain_changed.emit(3, Rect2(), 120.0, 120.0)
	check(not hearing.is_done(3), "the fountain filled, nobody drew on it")
	bus.fountain_changed.emit(3, Rect2(), 100.0, 120.0)
	check(hearing.is_done(3), "drawn on: used")
	bus.fountain_changed.emit(-1, Rect2(), 0.0, 0.0)
	check(not hearing.is_done(3), "every fountain forgotten: not, until told again")
	bus.fountain_changed.emit(3, Rect2(), 0.0, 120.0)
	check(hearing.is_done(3), "told again, dry: used")
	bus.rooms_rewards_left.emit(PackedByteArray([0, 1]), false)
	check(hearing.is_done(4), "its reward taken: the reward room done (a shorter list holds none past its end)")
	bus.rooms_cleared.emit(PackedByteArray(), false)
	check(not hearing.is_done(4), "not entered (nothing cleared): a reward room is not done")
	var again: int = hearing.cleared_again()
	bus.rooms_opened.emit(PackedByteArray([0, 0, 1]), true)
	check_equal(hearing.cleared_again(), again + 1, "told the rooms opened again: drawn as they stand")
	bus.rooms_rewards_left.emit(PackedByteArray(), true)
	check_equal(hearing.cleared_again(), again + 2, "and the rewards left")
	bus.room_built.emit(&"", EventsScript.FIRST_ROOM, null)
	check(not hearing.is_done(2), "a new world: nothing opened")


## A treasure room once opened (the owner, 2026-11-20, after #884): every doorway sign into it and
## its map symbol step to the done look; the room past it does not.
func test_a_treasure_rooms_signs_show_it_done_once_opened() -> void:
	var map: BiomeMap = _start_kinds(1, &"treasure", &"boss")
	var symbols: MouthSymbolsScript = _laid_symbols()
	var key_at: Vector2 = flow.locks.key_at[0]
	check(not _hearing().is_done(WEST), "shut: not done")
	check_equal(_done_stages(symbols, WEST), [] as Array[int], "nothing changes while it is shut")
	_wizard(0).global_position = key_at
	tick.run(DT)
	_wizard(0).global_position = BiomeMaps.socket_point(registry, map, WEST, RoomSocket.Facing.EAST) + RoomSocket.way(RoomSocket.Facing.EAST) * 40.0
	tick.run(DT)
	tick.run(DT)
	check(flow.locks.is_open(WEST), "the key opened it")
	check(_hearing().is_done(WEST), "opened: done, before anyone went in")
	check_equal(_done_stages(symbols, WEST), [1, 2, 3, 4, 5, 6, 7] as Array[int], "its sign steps to the done look a stage a frame")
	_check_only_done(symbols, WEST)


## A fountain once used (the owner, 2026-11-20, after #884): drawn on at all by a hurt wizard.
func test_a_fountains_signs_show_it_done_once_used() -> void:
	var map: BiomeMap = _start_kinds(1, &"fountain", &"fight")
	var symbols: MouthSymbolsScript = _laid_symbols()
	_into(map, WEST, RoomSocket.Facing.EAST)
	check(not _hearing().is_done(WEST), "entered, its pool full: not used")
	check_equal(_done_stages(symbols, WEST), [] as Array[int], "its sign unchanged")
	var wizard: Actor = _wizard(0)
	wizard.health.health = wizard.health.max_health * 0.5
	wizard.global_position = flow.biome.room_rect(WEST).get_center()
	tick.run(DT)
	tick.run(DT)
	check(_hearing().is_done(WEST), "a hurt wizard drew on it: used")
	check_equal(_done_stages(symbols, WEST), [1, 2, 3, 4, 5, 6, 7] as Array[int], "its sign steps to the done look a stage a frame")
	_check_only_done(symbols, WEST)


## A reward room once its rewards are taken (the owner, 2026-11-20, after #884): entering is not
## enough while a present player's item lies there; taken, the signs step to the done look. A player
## who was away finds its offer waiting anywhere (rule 4), and it keeps nothing in the room.
func test_a_reward_rooms_signs_show_it_done_once_its_rewards_are_taken() -> void:
	var map: BiomeMap = _start_kinds(2, &"fight", &"reward")
	var symbols: MouthSymbolsScript = _laid_symbols()
	_into(map, EAST, RoomSocket.Facing.WEST)
	tick.run(DT)
	check(_hearing().is_cleared(EAST), "entered: cleared")
	check(not _hearing().is_done(EAST), "its reward lies there: not done")
	check_equal(_done_stages(symbols, EAST), [] as Array[int], "its sign unchanged")
	var mine: Array = root.get_node("Rewards").call(&"waiting_of", 0)
	check(mine.size() == 1 and bool((mine[0] as Dictionary)["lying"]), "seat 0's item lies in the room")
	events.call(&"apply_command", &"reward_pick_requested", [0, int((mine[0] as Dictionary)["offer"]), 0])
	check(_hearing().is_done(EAST), "taken: done, though seat 1's offer still waits elsewhere")
	check_equal((root.get_node("Rewards").call(&"waiting_of", 1) as Array).size(), 1, "seat 1's offer waits")
	check_equal(_done_stages(symbols, EAST), [1, 2, 3, 4, 5, 6, 7] as Array[int], "its sign steps to the done look a stage a frame")
	_check_only_done(symbols, EAST)
	var view: PartyMapViewScript = feel.call(&"party_map") as PartyMapViewScript
	view.step(0.0, actors, 1, _grid(), _two_views())
	check_equal(view.cleared_of(EAST), KindSymbolScript.CLEARED_STAGES, "the map's symbol shows it done")


## After a restore each new kind's done look is drawn as it stands, either way, on the signs and
## the map, nothing played in (the owner, 2026-11-20, after #884).
func test_a_restore_draws_each_new_kinds_done_look_as_it_stands() -> void:
	var view: PartyMapViewScript = feel.call(&"party_map") as PartyMapViewScript
	for kind: StringName in [&"treasure", &"fountain", &"reward"]:
		flow.stop_run()
		var map: BiomeMap = _start_kinds(1, kind, &"boss" if kind == &"treasure" else &"fight")
		var symbols: MouthSymbolsScript = _laid_symbols()
		var wizard: Actor = _wizard(0)
		if kind == &"reward":
			_into(map, WEST, RoomSocket.Facing.EAST)
			tick.run(DT)
		var before := Snapshot.take(tick.state_areas(), root)
		if kind == &"treasure":
			wizard.global_position = flow.locks.key_at[0]
			tick.run(DT)
			wizard.global_position = BiomeMaps.socket_point(registry, map, WEST, RoomSocket.Facing.EAST) + RoomSocket.way(RoomSocket.Facing.EAST) * 40.0
			tick.run(DT)
			tick.run(DT)
		elif kind == &"fountain":
			_into(map, WEST, RoomSocket.Facing.EAST)
			wizard.health.health = wizard.health.max_health * 0.5
			wizard.global_position = flow.biome.room_rect(WEST).get_center()
			tick.run(DT)
			tick.run(DT)
		else:
			var mine: Array = root.get_node("Rewards").call(&"waiting_of", 0)
			events.call(&"apply_command", &"reward_pick_requested", [0, int((mine[0] as Dictionary)["offer"]), 0])
		check(_hearing().is_done(WEST), "%s: done" % kind)
		var after := Snapshot.take(tick.state_areas(), root)
		for way in 2:
			var into_done: bool = way == 0
			check((after if into_done else before).restore(tick.state_areas(), root).is_empty(), "%s: restored" % kind)
			symbols = _laid_symbols()
			view.step(0.0, actors, 1, _grid(), _two_views())
			var stage: int = KindSymbolScript.CLEARED_STAGES if into_done else 0
			if into_done:
				_check_only_done(symbols, WEST)
			for mouth in symbols.count():
				if (feel.call(&"mouth_looks") as MouthLooksScript).room_of(mouth) == WEST:
					check_equal(symbols.cleared_of(mouth), stage, "%s, restored %s: the sign as it stands" % [kind, "done" if into_done else "not done"])
			check_equal(view.cleared_of(WEST), stage, "%s, restored: the map as it stands" % kind)


## The split map with the antechamber of kind `west` and the court of `east`, `players` seats.
func _start_kinds(players: int, west: StringName, east: StringName) -> BiomeMap:
	var map: BiomeMap = BiomeMaps.split(registry)
	map.room_kinds[WEST] = west
	map.room_kinds[EAST] = east
	for seat in players:
		input.add_virtual_device(seat)
	var fights: Array[RoomFight] = [RoomFight.new(), RoomFight.new(), RoomFight.new()]
	check(flow.start_biome(0, map, fights), "the biome starts")
	tick.run(DT)
	return map


## The doorway signs laid for the world as it stands.
func _laid_symbols() -> MouthSymbolsScript:
	var mouths: MouthLooksScript = feel.call(&"mouth_looks") as MouthLooksScript
	var symbols: MouthSymbolsScript = feel.call(&"mouth_symbols") as MouthSymbolsScript
	mouths.step(0.0, _grid())
	symbols.step(0.0, actors, 1, _grid())
	return symbols


## The done look's stages a sign into `room` steps through, a frame at a time, until still.
func _done_stages(symbols: MouthSymbolsScript, room: int) -> Array[int]:
	var mouths: MouthLooksScript = feel.call(&"mouth_looks") as MouthLooksScript
	var into: int = -1
	for mouth in mouths.mouths():
		if mouths.room_of(mouth) == room:
			into = mouth
	symbols.step(0.0, actors, 1, _grid())
	var stages: Array[int] = []
	var frames: int = 0
	while symbols.is_moving() and frames < 60:
		symbols.advance()
		frames += 1
		var stage: int = symbols.cleared_of(into)
		if stage != (stages.back() if not stages.is_empty() else 0):
			stages.append(stage)
	return stages


## Every sign into `room` shows the whole done look and every other none.
func _check_only_done(symbols: MouthSymbolsScript, room: int) -> void:
	var mouths: MouthLooksScript = feel.call(&"mouth_looks") as MouthLooksScript
	for mouth in symbols.count():
		check_equal(symbols.cleared_of(mouth), KindSymbolScript.CLEARED_STAGES if mouths.room_of(mouth) == room else 0, "mouth %d into room %d" % [mouth, mouths.room_of(mouth)])


## A new world never shows an old biome's rooms cleared by number, even when nothing told the view
## the old map was gone (a restore into the hub, then a new biome).
func test_a_new_world_starts_with_nothing_cleared() -> void:
	var bus := own(EventsScript.new()) as EventsScript
	var hearing := RoomHearingScript.new()
	hearing.bind(bus)
	bus.room_built.emit(&"", EventsScript.FIRST_ROOM, null)
	bus.rooms_cleared.emit(PackedByteArray([1, 1, 0]), false)
	check(hearing.is_cleared(WEST), "the antechamber cleared")
	# The view hears a new world built, with no empty map told before it.
	bus.room_built.emit(&"", EventsScript.FIRST_ROOM, null)
	check(not hearing.is_cleared(WEST), "a new world: nothing cleared")


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
	# Its empty fight is cleared as it is entered: its symbol's cleared look steps with the shades and
	# goes on after them.
	check_equal(shades.slice(0, 3), [1, 2, 3] as Array[int], "entered while the map is open: it comes in a shade a frame")
	check_equal(view.cleared_of(WEST), KindSymbolScript.CLEARED_STAGES, "and, cleared, its symbol stepped to the cleared look")
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


# --- The map held while moving (the owner, 2026-11-19: it opened and closed in a loop) ---------

## One view of a small screen (the map cut by it), its anchor at `anchor`.
static func _small_view(anchor: Vector2) -> ScreenViewsScript:
	var views := ScreenViewsScript.new()
	var screen := Vector2(100, 70)
	views.screen = screen
	views.count = 1
	views.set_view(0, 1, Transform2D.IDENTITY, anchor)
	var corners := PackedVector2Array([Vector2.ZERO, Vector2(screen.x, 0), screen, Vector2(0, screen.y)])
	for at in 4:
		views.set_corner(0, at, corners[at])
	views.set_corners(0, 4)
	return views


func test_a_held_map_stays_open_while_its_player_moves() -> void:
	_start(1)
	var view: PartyMapViewScript = feel.call(&"party_map") as PartyMapViewScript
	view.input = input as InputManagerScript
	input.call(&"send_virtual", 0, PartyMapViewScript.ACTION, 1.0)
	var anchor := Vector2(46, 33)
	view.step(0.0, actors, 1, _grid(), _small_view(anchor))
	while view.is_moving():
		view.advance()
		view.step(0.0, actors, 1, _grid(), _small_view(anchor))
	check_equal(view.stage_of(0), PartyMapViewScript.OPEN_STAGES, "held, it is open")
	var size: Vector2i = view.frame_of(0).size
	check(view.scale_of(0) == 1 and size.x < 100, "cut by its small cell (as a split's cell or a big biome's map is): %s" % size)
	# The player walks: its view's anchor and its wizard move a little every frame, as the camera
	# follows and zooms.
	var lowest: int = PartyMapViewScript.OPEN_STAGES
	for frame in 90:
		anchor += Vector2(0.13, -0.07) if frame < 45 else Vector2(-0.11, 0.06)
		_wizard(0).global_position += Vector2(1.5, 0.5)
		view.step(1.0 / 60.0, actors, 1, _grid(), _small_view(anchor))
		lowest = mini(lowest, view.stage_of(0))
	check_equal(lowest, PartyMapViewScript.OPEN_STAGES, "it never closes while held and moving")
	check_equal(view.frame_of(0).size, size, "its frame keeps its size")
	# A split that changes under it still closes it to open again at its new size (never a jump).
	view.step(0.0, actors, 1, _grid(), _two_views())
	check(view.is_moving() and view.stage_of(0) == PartyMapViewScript.OPEN_STAGES, "a new split: it closes first, at the size it has")
	view.advance()
	check_equal(view.stage_of(0), PartyMapViewScript.OPEN_STAGES - 1, "closing a stage a frame")


func test_the_picked_room_is_outlined_on_its_players_open_map_in_stages() -> void:
	_start(2)
	var view: PartyMapViewScript = feel.call(&"party_map") as PartyMapViewScript
	var views: ScreenViewsScript = _two_views()
	view.input = input as InputManagerScript
	input.call(&"send_virtual", 0, PartyMapViewScript.ACTION, 1.0)
	view.step(0.0, actors, 3, _grid(), views)
	while view.is_moving():
		view.advance()
		view.step(0.0, actors, 3, _grid(), views)
	events.map_pick_changed.emit(0, 0)
	check_equal(view.pick_of(0), 0, "seat 0 picked the start room")
	var stages: Array[int] = []
	while view.is_moving():
		view.advance()
		stages.append(view.pick_stage_of(0))
	check_equal(stages, [1, 2, 3] as Array[int], "its outline steps in a stage a frame (Smooth)")
	check_equal(view.pick_stage_of(1), 0, "nothing on the other player's map")
	events.map_pick_changed.emit(0, WEST)
	var turning: Array = []
	while view.is_moving():
		view.advance()
		turning.append([view.outlined_of(0), view.pick_stage_of(0)])
	check_equal(turning, [[0, 2], [0, 1], [0, 0], [WEST, 1], [WEST, 2], [WEST, 3]], "a new pick: the old outline steps out, then the new one in (never a jump)")
	events.map_pick_changed.emit(0, -1)
	var going: Array[int] = []
	while view.is_moving():
		view.advance()
		going.append(view.pick_stage_of(0))
	check_equal(going, [2, 1, 0] as Array[int], "no pick: the outline steps out")
