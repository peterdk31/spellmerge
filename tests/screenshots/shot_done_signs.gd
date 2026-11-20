extends "res://tests/support/screenshot.gd"
## Screenshots of the done look on more room kinds (the owner, 2026-11-20, after #884): a treasure
## room, a reward room and a secret room once everything in them is taken, and a fountain once drawn dry
## (the owner's answers on #888), on every
## doorway sign into it and its Y map symbol; a shop never. On the split test map (the nave the
## start room, the antechamber west, the ossuary court east; tests/support/biome_maps.gd), played by
## the keyboard.
##
## Shots: the first biome, the antechamber a treasure room and the court a fountain: the fountain's
## sign before (fountain_before_crop), drawn on with healing left, not done
## (fountain_drawn_on_not_done_crop) and drawn dry (fountain_done_crop); the treasure room's sign shut
## (treasure_before_crop), opened and entered with its chest lying (treasure_opened_not_done_crop) and
## its chest taken (treasure_done_crop); the map held open (map_done_treasure_fountain). The second,
## a shop west and a reward room east: the reward room's sign entered with its reward lying
## (reward_before_crop) and taken (reward_done_crop), the shop's after it was entered
## (shop_never_crop); the map (map_done_reward_shop). The third, a secret room west: no sign beside
## its rock (secret_unfound_crop), its sign once found (secret_found_crop) and done once its reward is
## taken (secret_done_crop); the map (map_done_secret).

const BiomeMaps := preload("res://tests/support/biome_maps.gd")
const MouthSymbolsScript := preload("res://gameplay/feel/mouth_symbols.gd")
const MouthLooksScript := preload("res://gameplay/feel/mouth_looks.gd")
const KindSymbolLook := preload("res://gameplay/feel/kind_symbol.gd")
const WEST: int = 1
const EAST: int = 2

var input: Node
var flow: Node
var feel: Node
var registry: Node
var map: BiomeMap
var wizard: Actor


func take() -> void:
	if not need(["PlayerInput", "Flow", "Feel", "Registry", "Projectiles", "Rewards", "Events"]):
		return
	settle_frames = 30
	input = root.get_node("PlayerInput")
	flow = root.get_node("Flow")
	feel = root.get_node("Feel")
	registry = root.get_node("Registry")
	input.call("join", int(input.get("KEYBOARD")))
	if not await _biome(&"treasure", &"fountain"):
		return
	# The fountain: its sign by the nave's east mouth; drawn on with healing left (not done); drawn dry.
	await _at_mouth(EAST)
	await _sign(EAST, "fountain_before_crop")
	_into(EAST)
	await settle(4)
	wizard.health.health = wizard.health.max_health - 10.0
	wizard.global_position = flow.get(&"biome").call(&"room_rect", EAST).get_center()
	await settle(20)
	await _at_mouth(EAST)
	await _sign(EAST, "fountain_drawn_on_not_done_crop")
	wizard.global_position = flow.get(&"biome").call(&"room_rect", EAST).get_center()
	for i in 600:
		if float(root.get_node("Rewards").call(&"pool_left", EAST)) <= 0.0:
			break
		wizard.health.health = 1.0
		await settle(1)
	await _at_mouth(EAST)
	if not await _done(EAST):
		return
	await _sign(EAST, "fountain_done_crop")
	# The treasure room: its key (in the nave or the court, by the run's chance) taken, its door opened,
	# then entered (its chest lying: not done) and its chest taken.
	var locks: LockDoors = flow.get(&"locks") as LockDoors
	if locks.key_states.is_empty() or locks.key_states[0] != LockDoors.KEY_LYING:
		fail("the key does not lie anywhere")
		return
	await _at_mouth(WEST)
	await _sign(WEST, "treasure_before_crop")
	wizard.global_position = locks.key_at[0]
	await settle(4)
	wizard.global_position = BiomeMaps.socket_point(registry, map, WEST, RoomSocket.Facing.EAST) + RoomSocket.way(RoomSocket.Facing.EAST) * 40.0
	await settle(4)
	_into(WEST)
	await settle(10)
	await _at_mouth(WEST)
	await _sign(WEST, "treasure_opened_not_done_crop")
	if not _take():
		return
	if not await _done(WEST):
		return
	await _sign(WEST, "treasure_done_crop")
	await _map("map_done_treasure_fountain")
	# The second biome: a shop and a reward room.
	if not await _biome(&"shop", &"reward"):
		return
	_into(WEST)
	await settle(10)
	_into(EAST)
	await settle(10)
	await _at_mouth(EAST)
	await _sign(EAST, "reward_before_crop")
	if not _take():
		return
	if not await _done(EAST):
		return
	await _sign(EAST, "reward_done_crop")
	await _at_mouth(WEST)
	await _sign(WEST, "shop_never_crop")
	await _map("map_done_reward_shop")
	# The third: a secret room west, unmarked beside its rock, its sign up once found, done once taken.
	if not await _biome(&"secret", &"fight"):
		return
	await _at_mouth(WEST)
	await _sign(WEST, "secret_unfound_crop")
	(flow.get(&"locks") as LockDoors).open(WEST, root.get_node("Projectiles").call("grid") as RoomGrid)
	await settle(20)
	await _sign(WEST, "secret_found_crop")
	_into(WEST)
	await settle(10)
	if not _take():
		return
	await _at_mouth(WEST)
	if not await _done(WEST):
		return
	await _sign(WEST, "secret_done_crop")
	await _map("map_done_secret")


## Seat 0 takes the first choice of its reward lying in the room (as its A at the chest would).
func _take() -> bool:
	var mine: Array = root.get_node("Rewards").call(&"waiting_of", 0)
	if mine.size() != 1:
		fail("no reward lies in the room")
		return false
	root.get_node("Events").emit_signal(&"reward_pick_requested", 0, int((mine[0] as Dictionary)["offer"]), 0)
	return true


## A new biome with the antechamber of kind `west` and the court of `east`, the wizard in the nave.
func _biome(west: StringName, east: StringName) -> bool:
	flow.call("stop_run")
	await settle(4)
	map = BiomeMaps.split(registry)
	map.room_kinds[WEST] = west
	map.room_kinds[EAST] = east
	var fights: Array[RoomFight] = [RoomFight.new(), RoomFight.new(), RoomFight.new()]
	if not flow.call("start_biome", 0, map, fights):
		fail("the biome did not start")
		return false
	await settle()
	wizard = flow.call("get_wizard", 0) as Actor
	return true


## The wizard just inside `room` by its socket facing the nave.
func _into(room: int) -> void:
	var facing: int = RoomSocket.Facing.EAST if room == WEST else RoomSocket.Facing.WEST
	wizard.global_position = BiomeMaps.socket_point(registry, map, room, facing) - RoomSocket.way(facing) * 24.0


## The wizard on the nave's bridge toward `room`, its sign risen.
func _at_mouth(room: int) -> void:
	var facing: int = RoomSocket.Facing.WEST if room == WEST else RoomSocket.Facing.EAST
	wizard.global_position = BiomeMaps.socket_point(registry, map, 0, facing) + RoomSocket.way(facing) * 40.0
	await settle(30)


func _mouth_into(room: int) -> int:
	var mouths := feel.call(&"mouth_looks") as MouthLooksScript
	for mouth in mouths.mouths():
		if mouths.room_of(mouth) == room:
			return mouth
	return -1


## Waits for the sign into `room` to show the whole done look.
func _done(room: int) -> bool:
	var symbols := feel.call(&"mouth_symbols") as MouthSymbolsScript
	var mouth: int = _mouth_into(room)
	if not await wait_for(func() -> bool: return symbols.done_of(mouth) == KindSymbolLook.DONE_STAGES, 90):
		fail("the sign into room %d is not done (%d)" % [room, symbols.done_of(mouth)])
		return false
	await settle(4)
	return true


func _sign(room: int, shot_name: String) -> void:
	var symbols := feel.call(&"mouth_symbols") as MouthSymbolsScript
	var at: Vector2 = symbols.corner_of(_mouth_into(room)) + Vector2.ONE * (RoomKind.SYMBOL_SIDE * MouthSymbolsScript.SCALE * 0.5)
	var image: Image = await grab()
	save_crop(image, on_screen(at), shot_name, Vector2i(24, 24))


## The map held open (M), shot, and let go.
func _map(shot_name: String) -> void:
	wizard.global_position = flow.get(&"biome").call(&"room_rect", 0).get_center()
	await settle(10)
	var press := InputEventKey.new()
	press.physical_keycode = KEY_M
	press.pressed = true
	input.call("handle_event", press)
	await shot(shot_name)
	var release := InputEventKey.new()
	release.physical_keycode = KEY_M
	release.pressed = false
	input.call("handle_event", release)
	await settle(20)
