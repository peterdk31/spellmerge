extends "res://tests/support/screenshot.gd"
## Screenshots of the equal split's grouped panes (the owner, 2026-11-20; gameplay/feel/equal_panes.gd,
## hud/panels/seat_corners.gd), on the split test map (tests/support/biome_maps.gd: the nave, the
## antechamber west, the ossuary court east), players on this machine's virtual devices:
## - `split_equal_groups_p1_p3`: P1 and P3 alone, parted: the left and right halves, P3's corner
##   panel moved to the bottom right, inside its own pane.
## - `split_equal_groups_3_two_close`: three players, P1 and P3 close in the antechamber, P2 in the
##   court: two panes, the halves, the pair sharing one (P1's panel moved into its half).
## - `split_equal_groups_void`: the three apart: three quarters, the fourth the void with its
##   drifting motes; `split_equal_groups_void_quarter` that quarter alone, twice the size.
## - `split_equal_groups_4_pairs`: four players in two pairs: the halves, each panel keeping its row.
## - `split_equal_groups_4_pair_half`: a pair and two alone: the pair the left half (its bottom
##   quarter its twin, the same picture), the two alone the right half's quarters; no void.

const BiomeMaps := preload("res://tests/support/biome_maps.gd")


func take() -> void:
	if not need(["PlayerInput", "Flow", "Feel", "Registry"]):
		return
	settle_frames = 30
	var input: Node = root.get_node("PlayerInput")
	var flow: Node = root.get_node("Flow")
	var registry: Node = root.get_node("Registry")
	var feel: Node = root.get_node("Feel")
	feel.call("set_split_mode", SplitScreenSetting.EQUAL)
	var map: BiomeMap = BiomeMaps.split(registry)
	var west: Vector2 = BiomeMaps.socket_point(registry, map, 1, RoomSocket.Facing.EAST) - Vector2(120.0, 0.0)
	var east: Vector2 = BiomeMaps.socket_point(registry, map, 2, RoomSocket.Facing.WEST) + Vector2(120.0, 0.0)
	var nave_west: Vector2 = BiomeMaps.socket_point(registry, map, 0, RoomSocket.Facing.WEST)
	var nave_east: Vector2 = BiomeMaps.socket_point(registry, map, 0, RoomSocket.Facing.EAST)
	var nave: Vector2 = (nave_west + nave_east) * 0.5
	# P1 and P3.
	input.call("add_virtual_device", 0)
	input.call("add_virtual_device", 2)
	if not await _start(flow, map):
		return
	_wizard(flow, 0).global_position = west
	_wizard(flow, 2).global_position = east
	await settle(240)
	if not _views_are(feel, 2, "P1 and P3"):
		return
	await shot("split_equal_groups_p1_p3")
	# Three: P1 and P3 close, P2 far.
	input.call("add_virtual_device", 1)
	if not await _start(flow, map):
		return
	_wizard(flow, 0).global_position = west
	_wizard(flow, 2).global_position = west + Vector2(40.0, 24.0)
	_wizard(flow, 1).global_position = east
	await settle(240)
	if not _views_are(feel, 2, "three, two close"):
		return
	await shot("split_equal_groups_3_two_close")
	# The three apart: the fourth quarter the void.
	_wizard(flow, 2).global_position = nave + Vector2(0.0, 40.0)
	await settle(300)
	if not _views_are(feel, 3, "three apart"):
		return
	await shot("split_equal_groups_void")
	var image: Image = await grab()
	var half := Vector2i(image.get_width() >> 1, image.get_height() >> 1)
	var quarter: Image = image.get_region(Rect2i(half, half))
	quarter.resize(half.x * 2, half.y * 2, Image.INTERPOLATE_NEAREST)
	save(quarter, "split_equal_groups_void_quarter")
	# Four: two pairs, then a pair and two alone.
	input.call("add_virtual_device", 3)
	if not await _start(flow, map):
		return
	_wizard(flow, 0).global_position = west
	_wizard(flow, 1).global_position = west + Vector2(40.0, 24.0)
	_wizard(flow, 2).global_position = east
	_wizard(flow, 3).global_position = east + Vector2(-40.0, 24.0)
	await settle(240)
	if not _views_are(feel, 2, "two pairs"):
		return
	await shot("split_equal_groups_4_pairs")
	_wizard(flow, 3).global_position = nave + Vector2(0.0, 40.0)
	await settle(300)
	if not _views_are(feel, 3, "a pair and two alone"):
		return
	await shot("split_equal_groups_4_pair_half")


func _start(flow: Node, map: BiomeMap) -> bool:
	var fights: Array[RoomFight] = [RoomFight.new(), RoomFight.new(), RoomFight.new()]
	if not flow.call("start_biome", 0, map, fights):
		fail("the biome did not start")
		return false
	await settle(30)
	return true


func _wizard(flow: Node, seat: int) -> Node2D:
	return flow.call("get_wizard", seat) as Node2D


func _views_are(feel: Node, want: int, what: String) -> bool:
	var split: Object = feel.get("split_screen")
	var views: int = int((split.get("camera") as Object).get("views").get("count")) if split != null else 0
	print("SPLIT EQUAL GROUPS: %s, %d views" % [what, views])
	if views != want:
		fail("%s: %d views, not %d" % [what, views, want])
		return false
	return true
