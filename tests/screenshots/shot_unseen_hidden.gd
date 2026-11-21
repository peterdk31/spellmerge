extends "res://tests/support/screenshot.gd"
## Screenshots of unvisited rooms holding foes and pickups (the owner, 2026-11-21, on #899: what
## stands in an unvisited room is hidden one by one, no cover over it, and it must look as before:
## the void with its motes drifting about until the room's reveal), on the split test map (the nave
## the start room, the antechamber west, the ossuary court east; tests/support/biome_maps.gd), played
## by the keyboard. Three imps, a card and a coin stand in the antechamber by its mouth, an imp in the
## court.
##
## Shots: the wizard on the nave's west bridge, the antechamber unvisited with all of it in it: only
## the void and its motes show there (unseen_hidden, a 4x crop over the room's edge,
## unseen_hidden_crop; it fails when more than a few of the room's pixels are lit); frozen mid-way
## through its reveal, the foes and the pickups coming in under the opening blocks
## (unseen_hidden_reveal, its crop); and the room revealed (unseen_hidden_revealed, its crop).

const BiomeMaps := preload("res://tests/support/biome_maps.gd")
const UnseenDarkScript := preload("res://gameplay/feel/unseen_dark.gd")
const WEST: int = 1
const EAST: int = 2
## The share of an unvisited room's pixels on screen that may be lit: the void's motes, no more.
const LIT_MOST: float = 0.01


func take() -> void:
	if not need(["PlayerInput", "Flow", "Feel", "Registry", "Projectiles", "Items", "Rewards"]):
		return
	settle_frames = 30
	var input: Node = root.get_node("PlayerInput")
	var flow: Node = root.get_node("Flow")
	var feel: Node = root.get_node("Feel")
	var registry: Node = root.get_node("Registry")
	input.call("join", int(input.get("KEYBOARD")))
	var map: BiomeMap = BiomeMaps.split(registry)
	var fights: Array[RoomFight] = [RoomFight.new(), RoomFight.new(), RoomFight.new()]
	if not flow.call("start_biome", 0, map, fights):
		fail("the biome did not start")
		return
	await settle()
	var wizard := flow.call("get_wizard", 0) as Node2D
	var grid := root.get_node("Projectiles").call("grid") as RoomGrid
	var west_mouth: Vector2 = BiomeMaps.socket_point(registry, map, 0, RoomSocket.Facing.WEST)
	var edge: Vector2 = BiomeMaps.socket_point(registry, map, WEST, RoomSocket.Facing.EAST)
	var world := flow.get("world") as Node2D
	var imp: EnemyBase = registry.call("get_resource", &"enemies", &"ember_imp") as EnemyBase
	for i in 3:
		_stand(world, imp, grid.nearest_ground(edge + Vector2(-60.0 - 30.0 * i, -20.0 + 20.0 * i), 10.0))
	_stand(world, imp, grid.nearest_ground(grid.place_rect(EAST).get_center(), 10.0))
	root.get_node("Items").call("lay", ItemStack.card(&"heavy"), grid.nearest_ground(edge + Vector2(-50.0, 30.0), 6.0))
	root.get_node("Rewards").call("lay_coin", grid.nearest_ground(edge + Vector2(-70.0, 40.0), 6.0))
	# On the nave's west bridge, by the antechamber's mouth, long enough for the void's motes to fill
	# the view (their life is 3 to 4 s).
	wizard.global_position = west_mouth + Vector2(-40.0, 0.0)
	await settle(300)
	var image: Image = await grab()
	var lit: float = _lit_share(image, grid.place_rect(WEST))
	print("SHOT: the unvisited antechamber's pixels lit: %.2f%%" % (lit * 100.0))
	if lit > LIT_MOST:
		save(image, "unseen_hidden_failed")
		fail("%.1f%% of the unvisited antechamber's pixels are lit: something in it is drawn" % (lit * 100.0))
		return
	save(image, "unseen_hidden")
	save_crop(image, on_screen(edge + Vector2(-40.0, 0.0)), "unseen_hidden_crop", Vector2i(80, 45))
	# Into the antechamber with Feel held, its dark stepped by hand to the reveal's middle stage.
	var dark := feel.call(&"unseen_dark") as UnseenDarkScript
	feel.process_mode = Node.PROCESS_MODE_DISABLED
	wizard.global_position = edge + Vector2(-24.0, 0.0)
	await settle(4)
	wizard.global_position = west_mouth + Vector2(-40.0, 0.0)
	dark.step(0.0, grid)
	dark.advance()
	dark.advance()
	if dark.stage_of(WEST) != 2:
		fail("the antechamber's dark is at stage %d, not mid-way" % dark.stage_of(WEST))
		return
	# Feel's frame by hand, twice and with no time (the dark's stage stays), so what stands there is
	# shown as the reveal has begun.
	feel.call(&"step", 0.0)
	feel.call(&"step", 0.0)
	await settle(2)
	image = await grab()
	save(image, "unseen_hidden_reveal")
	save_crop(image, on_screen(edge + Vector2(-40.0, 0.0)), "unseen_hidden_reveal_crop", Vector2i(80, 45))
	feel.process_mode = Node.PROCESS_MODE_INHERIT
	await settle(60)
	if dark.stage_of(WEST) != 0:
		fail("the antechamber is not revealed (%d)" % dark.stage_of(WEST))
		return
	image = await grab()
	if _lit_share(image, grid.place_rect(WEST)) <= LIT_MOST:
		fail("the revealed antechamber is still dark")
		return
	save(image, "unseen_hidden_revealed")
	save_crop(image, on_screen(edge + Vector2(-40.0, 0.0)), "unseen_hidden_revealed_crop", Vector2i(80, 45))


func _stand(world: Node2D, data: EnemyBase, at: Vector2) -> void:
	var enemy := data.scene.instantiate() as Actor
	enemy.data = data
	enemy.position = at
	world.add_child(enemy)


## The share of `room`'s pixels on screen (below the HUD's panel) that are not the void's black.
func _lit_share(image: Image, room: Rect2) -> float:
	var scale_to_image: Vector2 = Vector2(image.get_size()) / Vector2(root.get_visible_rect().size)
	var a := Vector2i((on_screen(room.position) * scale_to_image).floor())
	var b := Vector2i((on_screen(room.end) * scale_to_image).ceil())
	var top: int = int(70.0 * scale_to_image.y)
	var x0: int = clampi(a.x, 0, image.get_width())
	var x1: int = clampi(b.x, 0, image.get_width())
	var y0: int = clampi(maxi(a.y, top), 0, image.get_height())
	var y1: int = clampi(b.y, 0, image.get_height())
	var lit: int = 0
	var all: int = 0
	for y in range(y0, y1):
		for x in range(x0, x1):
			all += 1
			var pixel: Color = image.get_pixel(x, y)
			if pixel.r + pixel.g + pixel.b > 0.02:
				lit += 1
	return float(lit) / float(maxi(all, 1))
