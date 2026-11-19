extends "res://tests/support/suite.gd"
## The crypt's set of fight rooms (connected biomes CB13, docs/milestones/connected-biomes.md, and the
## owner's answer of 2026-11-19: "keeps growing the crypt's templates toward 12 to 16 fights"), each
## template found by folder: every one in the crypt rework's style (drawn from its shape, its floor
## colours named, lit by candle clusters and the shaft, cobwebs in its corners), of mixed sizes about 1
## to 2 screens (decision 1), and most with a third socket, so a way through a room leaves a socket
## free for a branch or a loop (a way uses two). Each template's own rules (sockets on the lip, every
## socket reaching every other, spawns clear, the 32 px rule, all four mirrorings) are
## test_room_sockets.gd's and test_template_layout.gd's.

const RegistryScript := preload("res://core/registry/registry.gd")
## A screen (docs/DESIGN.md: 640×360), in square pixels.
const SCREEN: float = 640.0 * 360.0

var _fights: Array[RoomBase] = []


func before_each() -> void:
	super.before_each()
	var registry := own(RegistryScript.new()) as RegistryScript
	registry.scan()
	_fights.clear()
	for item: Resource in registry.get_all(&"rooms"):
		var room := item as RoomBase
		if room != null and room.biome == &"crypt" and room.kinds.has(&"fight"):
			_fights.append(room)


func test_the_crypt_has_twelve_fight_rooms_at_least() -> void:
	check(_fights.size() >= 12, "12 to 16 fights: %d" % _fights.size())


func test_every_fight_room_is_of_the_crypt_s_style() -> void:
	for room: RoomBase in _fights:
		check(room.ground_shape != null, "%s is drawn from its shape" % room.id)
		check(not room.floor_mark_colors.is_empty() and not room.debris_colors.is_empty(), "%s names its floor-mark and debris colours" % room.id)
		var layout: Node = own(room.scene.instantiate())
		var candles: int = 0
		var beams: int = 0
		for node: Node in layout.find_children("*", "Node2D", true, false):
			if node.scene_file_path.ends_with("decals/candles.tscn"):
				candles += 1
			elif node.scene_file_path.ends_with("decor/beam.tscn"):
				beams += 1
		check(candles >= 4, "%s is lit by four candle clusters at least: %d" % [room.id, candles])
		check_equal(beams, 1, "%s has the shaft of light" % room.id)
		var webs: int = 0
		for field: Node in layout.find_children("*", "CoverField", true, false):
			webs += 1 if (field as CoverField).kind == &"cobweb" else 0
		check(webs >= 1, "%s has cobwebs in a corner" % room.id)


func test_the_sizes_are_mixed_and_about_one_to_two_screens() -> void:
	var sizes: Dictionary = {}
	for room: RoomBase in _fights:
		var size: Vector2 = room.places().size
		var screens: float = size.x * size.y / SCREEN
		check(screens >= 1.0 and screens <= 2.0, "%s is %.2f screens" % [room.id, screens])
		sizes[size] = true
	check(sizes.size() >= 8, "the sizes are mixed: %d sizes of %d rooms" % [sizes.size(), _fights.size()])


func test_most_fight_rooms_leave_a_socket_free_on_a_way() -> void:
	var third: int = 0
	for room: RoomBase in _fights:
		var sockets: int = room.places().socket_at.size()
		check(sockets >= 2, "%s joins a way: %d sockets" % [room.id, sockets])
		third += 1 if sockets >= 3 else 0
	check(third * 2 > _fights.size(), "most fight rooms have a third socket: %d of %d" % [third, _fights.size()])
