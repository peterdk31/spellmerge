extends "res://tests/support/screenshot.gd"
## Screenshots of each room kind's light and air (connected biomes CB12b): the split test map (the
## nave in the middle, the antechamber west and the ossuary court east; tests/support/biome_maps.gd),
## the nave (the start room) given each kind's look in turn (its light, tint and air motes lent to the
## start kind for the shot, so the boss's intro or a door's rules stage nothing), its own light
## leaning toward the kind's light and the kind's air motes drifting in it, the wizard in its middle
## with dynamic lighting on.
##
## Shots: room_tint_<kind> for each of the crypt's kinds; room_tint_side_by_side, the wizard on the
## bridge from the nave (the start room) to the court (a fountain), both rooms in one view, each in
## its own light.

const BiomeMaps := preload("res://tests/support/biome_maps.gd")
const KINDS: Array[StringName] = [&"fight", &"boss", &"start", &"reward", &"shop", &"fountain", &"treasure", &"secret", &"challenge"]


func take() -> void:
	if not need(["PlayerInput", "Flow", "Feel", "Registry"]):
		return
	settle_frames = 30
	var input: Node = root.get_node("PlayerInput")
	var flow: Node = root.get_node("Flow")
	var registry: Node = root.get_node("Registry")
	var feel: Node = root.get_node("Feel")
	feel.call("set_spell_light", true)
	input.call("add_virtual_device", 0)
	var start: RoomKind = registry.call("get_resource", &"room_kinds", &"start") as RoomKind
	var own_look: Array = [start.light, start.light_tint, start.air_motes]
	for kind in KINDS:
		var look: RoomKind = registry.call("get_resource", &"room_kinds", kind) as RoomKind
		start.light = look.light
		start.light_tint = look.light_tint
		start.air_motes = look.air_motes
		var staged: bool = await _stage(flow, registry, feel, [&"fight", &"start", &"fight"] as Array[StringName], look)
		if staged:
			await shot("room_tint_%s" % kind)
		start.light = own_look[0]
		start.light_tint = own_look[1]
		start.air_motes = own_look[2]
		if not staged:
			return
	if not await _stage(flow, registry, feel, [&"fight", &"start", &"fountain"] as Array[StringName], start):
		return
	var map: BiomeMap = BiomeMaps.split(registry)
	var wizard := flow.call("get_wizard", 0) as Node2D
	var court: Vector2 = BiomeMaps.socket_point(registry, map, 2, RoomSocket.Facing.WEST)
	# Into the court a moment, so it is entered (lit and tinted), then back onto the bridge.
	wizard.global_position = court + Vector2(48.0, 0.0)
	await settle(30)
	wizard.global_position = court - Vector2(40.0, 0.0)
	await shot("room_tint_side_by_side")


## The split map started with `kinds` (west, middle, east), the wizard in the nave's middle; false
## (and the shot failed) when it is not tinted as `kind` says.
func _stage(flow: Node, registry: Node, feel: Node, kinds: Array[StringName], kind: RoomKind) -> bool:
	flow.call("stop_run")
	var map: BiomeMap = BiomeMaps.split(registry, [0, 0, 0] as Array[int], [BiomeMaps.FIRST, BiomeMaps.MIDDLE, BiomeMaps.LAST] as Array[StringName], kinds)
	var fights: Array[RoomFight] = [RoomFight.new(), RoomFight.new(), RoomFight.new()]
	if not flow.call("start_biome", 0, map, fights):
		fail("the biome did not start for %s" % kind.id)
		return false
	await settle()
	var wizard := flow.call("get_wizard", 0) as Node2D
	var middle: Vector2 = (flow.get("biome") as BiomeWorld).room_rect(0).get_center()
	wizard.global_position = middle
	await settle(45)
	var tints: Object = feel.call("room_tints")
	var tint: Color = tints.call("tint_at", middle)
	var want: float = kind.light_tint
	if not is_equal_approx(tint.a, want):
		fail("the nave is not tinted as a %s room (%.2f, not %.2f)" % [kind.id, tint.a, want])
		return false
	return true
