extends "res://tests/support/screenshot.gd"
## Screenshots of the owner's three ways into a secret room (2026-11-20), each before and after it is
## found, on hand-made maps (tests/support/biome_maps.gd), P1 alone by the way in:
##
## - **A hidden bridge** (the split map, its antechamber the secret room): P1 at the nave's west
##   doorway, the bridge pure void and the cracked rock in the doorway (secret_bridge_hidden); its
##   element touches the rock: the bridge building out (secret_bridge_building), then whole
##   (secret_bridge_found).
## - **Wall to wall** (the secret room against the nave's west wall, the seam between): the cracked
##   wall in the doorway, nothing past it (secret_wall_hidden); broken, the doorway open straight into
##   the dark secret room (secret_wall_found), and P1 through it, the room lit (secret_wall_entered).
## - **A secret rune** (the secret room across the dark with no bridge): the faint crack in the nave's
##   floor, whole and cropped 4x (secret_rune_hidden, secret_rune_hidden_crop); its element touches it:
##   the rune drawn in (secret_rune_found, secret_rune_found_crop); P1 on it, teleported into the
##   secret room beside the rune leading back (secret_rune_arrived), and the held Y map showing the
##   found room with no bridge (secret_rune_map).

const BiomeMaps := preload("res://tests/support/biome_maps.gd")


func _key(input: Node, key: Key, down: bool) -> void:
	var press := InputEventKey.new()
	press.physical_keycode = key
	press.pressed = down
	input.call("handle_event", press)


func take() -> void:
	if not need(["PlayerInput", "Flow", "Feel", "Registry", "Events"]):
		return
	settle_frames = 30
	var input: Node = root.get_node("PlayerInput")
	input.call("join", int(input.get("KEYBOARD")))
	if not await _bridge():
		return
	if not await _wall():
		return
	await _rune(input)


func _begin(map: BiomeMap) -> bool:
	var flow: Node = root.get_node("Flow")
	flow.call("stop_run")
	var fights: Array[RoomFight] = []
	for room in map.rooms():
		fights.append(RoomFight.new())
	if not flow.call("start_biome", 0, map, fights):
		fail("the biome did not start")
		return false
	await settle()
	return true


func _touch(room: int, at: Vector2) -> void:
	var flow: Node = root.get_node("Flow")
	var element: StringName = (flow.get("locks") as LockDoors).element_of(room)
	root.get_node("Events").floor_touched.emit(0, element, at, 8.0, 0)


func _bridge() -> bool:
	var registry: Node = root.get_node("Registry")
	var flow: Node = root.get_node("Flow")
	var map: BiomeMap = BiomeMaps.split(registry)
	map.room_kinds[1] = &"secret"
	if not await _begin(map):
		return false
	var west: Vector2 = BiomeMaps.socket_point(registry, map, 0, RoomSocket.Facing.WEST)
	(flow.call("get_wizard", 0) as Node2D).global_position = west + Vector2(96.0, 0.0)
	await settle(40)
	await shot("secret_bridge_hidden")
	_touch(1, (flow.get("locks") as LockDoors).rock_of(0).get_center())
	await settle(4)
	save(await grab(), "secret_bridge_building")
	await settle(40)
	if not (flow.get("locks") as LockDoors).is_open(1):
		fail("the hidden bridge's rock did not break")
		return false
	await shot("secret_bridge_found")
	return true


func _wall() -> bool:
	var registry: Node = root.get_node("Registry")
	var flow: Node = root.get_node("Flow")
	var map: BiomeMap = BiomeMaps.wall_secret(registry)
	if not await _begin(map):
		return false
	var west: Vector2 = BiomeMaps.socket_point(registry, map, 0, RoomSocket.Facing.WEST)
	var wizard := flow.call("get_wizard", 0) as Node2D
	wizard.global_position = west + Vector2(96.0, 0.0)
	await settle(40)
	await shot("secret_wall_hidden")
	_touch(1, (flow.get("locks") as LockDoors).rock_of(0).get_center())
	await settle(40)
	if not (flow.get("locks") as LockDoors).is_open(1):
		fail("the cracked wall did not break")
		return false
	await shot("secret_wall_found")
	wizard.global_position = BiomeMaps.socket_point(registry, map, 1, RoomSocket.Facing.EAST) + Vector2(-48.0, 0.0)
	await settle(60)
	await shot("secret_wall_entered")
	return true


func _rune(input: Node) -> bool:
	var registry: Node = root.get_node("Registry")
	var flow: Node = root.get_node("Flow")
	var map: BiomeMap = BiomeMaps.rune_secret(registry)
	if not await _begin(map):
		return false
	var runes: SecretRunes = flow.get("runes") as SecretRunes
	var at: Vector2 = runes.spot_of(0, 0)
	var wizard := flow.call("get_wizard", 0) as Node2D
	wizard.global_position = at + Vector2(-56.0, 24.0)
	await settle(40)
	var image: Image = await grab()
	save(image, "secret_rune_hidden")
	save_crop(image, on_screen(at), "secret_rune_hidden_crop", Vector2i(24, 18))
	_touch(1, at)
	await settle(20)
	if not (flow.get("locks") as LockDoors).is_open(1):
		fail("the rune was not found")
		return false
	image = await grab()
	save(image, "secret_rune_found")
	save_crop(image, on_screen(at), "secret_rune_found_crop", Vector2i(24, 18))
	wizard.global_position = at
	await settle(60)
	if (wizard as Actor).room != 1:
		fail("the rune did not teleport the wizard")
		return false
	await shot("secret_rune_arrived")
	_key(input, KEY_M, true)
	await settle(20)
	await shot("secret_rune_map")
	_key(input, KEY_M, false)
	return true
