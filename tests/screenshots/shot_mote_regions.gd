extends "res://tests/support/screenshot.gd"
## Screenshots of the motes drawn by room and the light read in each view (the performance pass's
## follow-up, the owner's decisions of 2026-11-20: gameplay/feel/mote_regions.gd, view_readers.gd):
## on the split test map (tests/support/biome_maps.gd: the nave, the antechamber west, the ossuary
## court east).
##  - `mote_regions_mouth`: one picture of the nave's east mouth, blasts thrown on the mouth and just
##    inside each room's edge, their motes in flight across the edge (drawn by each room's chunk, and
##    the mouth's by the crossers').
##  - `mote_regions_<dynamic|equal>_<2|3|4>`: two to four players parted into the rooms, a blast at a
##    wall beside each, the screen split (Dynamic: the Voronoi cells; Equal: the panes): each view's
##    blast lights its own floor (the first two views share the readers, the third and fourth have
##    copies) and its motes fly to the wall and past the room's edge.

const BiomeMaps := preload("res://tests/support/biome_maps.gd")

const TINTS: Array[Color] = [Color("e0592f"), Color("4fd6dc"), Color("9be05a"), Color("e0c84f")]


func take() -> void:
	if not need(["PlayerInput", "Flow", "Feel", "Registry"]):
		return
	settle_frames = 30
	var input: Node = root.get_node("PlayerInput")
	var flow: Node = root.get_node("Flow")
	var registry: Node = root.get_node("Registry")
	var feel: Node = root.get_node("Feel")
	var map: BiomeMap = BiomeMaps.split(registry)
	var west: Vector2 = BiomeMaps.socket_point(registry, map, 1, RoomSocket.Facing.EAST)
	var east: Vector2 = BiomeMaps.socket_point(registry, map, 2, RoomSocket.Facing.WEST)
	var nave_west: Vector2 = BiomeMaps.socket_point(registry, map, 0, RoomSocket.Facing.WEST)
	var nave_east: Vector2 = BiomeMaps.socket_point(registry, map, 0, RoomSocket.Facing.EAST)
	var nave: Vector2 = (nave_west + nave_east) * 0.5
	var apart: Array[Vector2] = [west - Vector2(120.0, 0.0), east + Vector2(120.0, 0.0), nave + Vector2(0.0, 40.0), nave_west + Vector2(60.0, -60.0)]
	# A blast beside each parted player, by a wall or a mouth, so its motes cross its room's edge.
	var blasts: Array[Vector2] = [west + Vector2(-6.0, 0.0), east + Vector2(6.0, 0.0), nave_east + Vector2(-10.0, 0.0), nave_west + Vector2(10.0, -40.0)]
	input.call("add_virtual_device", 0)
	# One picture at the nave's east mouth.
	if not flow.call("start_biome", 0, map, [RoomFight.new(), RoomFight.new(), RoomFight.new()] as Array[RoomFight]):
		fail("the biome did not start")
		return
	await settle(30)
	var one := flow.call("get_wizard", 0) as Node2D
	if one == null:
		fail("no wizard")
		return
	one.global_position = nave_east + Vector2(-70.0, 50.0)
	await settle(60)
	for spot: Vector2 in [nave_east, nave_east + Vector2(-24.0, -30.0), nave_east + Vector2(24.0, 30.0)]:
		feel.call("play_cue", &"blast", 0, spot, Vector2.RIGHT, 30.0, TINTS[0], 1 << 0)
		await settle(1)
	await settle(12)
	_report(feel, "mouth")
	await shot("mote_regions_mouth")
	for mode in [SplitScreenSetting.DYNAMIC, SplitScreenSetting.EQUAL]:
		feel.call("set_split_mode", mode)
		var word: String = "dynamic" if mode == SplitScreenSetting.DYNAMIC else "equal"
		for count in range(2, 5):
			if mode == SplitScreenSetting.DYNAMIC:
				input.call("add_virtual_device", count - 1)
			if not flow.call("start_biome", 0, map, [RoomFight.new(), RoomFight.new(), RoomFight.new()] as Array[RoomFight]):
				fail("the biome did not start for %d players" % count)
				return
			await settle(30)
			var wizards: Array[Node2D] = []
			for seat in 4:
				var wizard := flow.call("get_wizard", seat) as Node2D
				if wizard != null:
					wizards.append(wizard)
			if wizards.size() < count:
				fail("%d wizards for %d players" % [wizards.size(), count])
				return
			for seat in wizards.size():
				# The seats past `count` (the equal pass has all four) stand beside the first.
				wizards[seat].global_position = apart[seat] if seat < count else apart[0] + Vector2(20.0 * float(seat), 10.0)
			await settle(150)
			var split: Object = feel.get("split_screen")
			var views: int = int((split.get("camera") as Object).get("views").get("count")) if split != null else 0
			if views != count:
				fail("%s, %d players parted: %d views" % [word, count, views])
				return
			for seat in count:
				feel.call("play_cue", &"blast", 0, blasts[seat], Vector2.RIGHT, 30.0, TINTS[seat], 1 << (seat % 2))
			await settle(12)
			_report(feel, "%s %d" % [word, count])
			await shot("mote_regions_%s_%d" % [word, count])


## What draws the motes now: the rooms' chunks shown and each region's.
func _report(feel: Node, label: String) -> void:
	var spectacle: Object = feel.get("_spectacle")
	var pool: Object = spectacle.get("pool") if spectacle != null else null
	var regions: Object = pool.get("regions") if pool != null else null
	if regions == null:
		print("MOTE REGIONS %s: no pool" % label)
		return
	var shown: PackedInt32Array = PackedInt32Array()
	for c in int(regions.call("chunks_made")):
		var node: CanvasItem = regions.call("node_of", c)
		if node != null and node.visible:
			shown.append(int(regions.call("region_of_chunk", c)))
	print("MOTE REGIONS %s: by room %s, chunks shown by region %s" % [label, regions.call("is_on"), shown])
