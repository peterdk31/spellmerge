extends "res://tests/support/screenshot.gd"
## Screenshots of the equal split screen (the owner, 2026-11-19; "Split screen: Equal",
## gameplay/feel/equal_panes.gd): on the split test map (tests/support/biome_maps.gd: the nave, the
## antechamber west, the ossuary court east), two, then three, then four players on this machine
## (virtual devices: with no real device here, the views hold every seat). For each count the
## players parted into the rooms and bridges, the screen in equal panes (`split_equal_N_split`:
## halves for two, quarters for three and four, the fourth quarter black with three), and the
## players together again in the nave, the one picture (`split_equal_N_joined`). And a strip of the
## three-player split forming (`split_equal_3_forming`: every 4th frame from the first frame split,
## the blank quarter growing in from its corner while the panes settle).

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
	var west: Vector2 = BiomeMaps.socket_point(registry, map, 1, RoomSocket.Facing.EAST)
	var east: Vector2 = BiomeMaps.socket_point(registry, map, 2, RoomSocket.Facing.WEST)
	var nave_west: Vector2 = BiomeMaps.socket_point(registry, map, 0, RoomSocket.Facing.WEST)
	var nave_east: Vector2 = BiomeMaps.socket_point(registry, map, 0, RoomSocket.Facing.EAST)
	var nave: Vector2 = (nave_west + nave_east) * 0.5
	# Where each seat stands parted: the antechamber, the court, the nave, and the nave's far side.
	var apart: Array[Vector2] = [west - Vector2(120.0, 0.0), east + Vector2(120.0, 0.0), nave + Vector2(0.0, 40.0), nave_west + Vector2(60.0, -60.0)]
	input.call("add_virtual_device", 0)
	for count in range(2, 5):
		input.call("add_virtual_device", count - 1)
		var fights: Array[RoomFight] = [RoomFight.new(), RoomFight.new(), RoomFight.new()]
		if not flow.call("start_biome", 0, map, fights):
			fail("the biome did not start for %d players" % count)
			return
		await settle(30)
		var wizards: Array[Node2D] = []
		for seat in count:
			var wizard := flow.call("get_wizard", seat) as Node2D
			if wizard == null:
				fail("no wizard for seat %d of %d" % [seat, count])
				return
			wizards.append(wizard)
		# Together in the nave first: one picture.
		for seat in count:
			wizards[seat].global_position = nave + Vector2(24.0 * float(seat), 0.0)
		await settle(90)
		await shot("split_equal_%d_joined" % count)
		# Parted: the panes.
		for seat in count:
			wizards[seat].global_position = apart[seat]
		if count == 3:
			var frames: Array[Image] = []
			for i in 8:
				var image: Image = await grab()
				image.resize(image.get_width() >> 1, image.get_height() >> 1, Image.INTERPOLATE_NEAREST)
				frames.append(image)
				await settle(4)
			var strip := Image.create(frames[0].get_width() * 4, frames[0].get_height() * 2, false, frames[0].get_format())
			for i in frames.size():
				strip.blit_rect(frames[i], Rect2i(Vector2i.ZERO, frames[i].get_size()), Vector2i(frames[0].get_width() * (i % 4), frames[0].get_height() * (i >> 2)))
			save(strip, "split_equal_3_forming")
		await settle(150)
		var split: Object = feel.get("split_screen")
		var views: int = int((split.get("camera") as Object).get("views").get("count")) if split != null else 0
		print("SPLIT EQUAL: %d players, %d views" % [count, views])
		if views != count:
			fail("%d players parted: %d views, not one a player" % [count, views])
			return
		await shot("split_equal_%d_split" % count)
