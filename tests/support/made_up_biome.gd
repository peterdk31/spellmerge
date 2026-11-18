extends RefCounted
## Made-up content for a biome's map (connected biomes CB5, `BiomeGenerator`): the stand-in for the
## templates the crypt does not have yet (CB11 and CB13 add them). A cellar of every kind decision 1
## names, its templates' shapes made in code (`PieceShape`: a slab ringed by a 32 px wall, its sockets
## on the wall's inner face, on the 32 px grid), with no scenes (`MadeUpRoom`), so nothing is drawn or
## laid: the generator reads only the shapes. Bridges across (west to east) and down (north to
## south), 128 to 320 px long by 32 px (a loop closes where two free sockets line up a bridge's
## length apart: at a corner, one bridge's length lines a room up, another's spans to the next).
##
##     var biome := MadeUpBiome.new()
##     var map: BiomeMap = BiomeGenerator.generate(biome.run(), biome.content, biome.shapes, sim)

const MadeUpRoom := preload("res://tests/support/made_up_room.gd")

const BIOME: StringName = &"cellar"
## The kinds of decision 1 and the start room.
const KINDS: Dictionary = {
	&"start": RoomKind.FILL_NONE,
	&"fight": RoomKind.FILL_ENEMIES,
	&"boss": RoomKind.FILL_BOSS,
	&"reward": RoomKind.FILL_NONE,
	&"shop": RoomKind.FILL_NONE,
	&"secret": RoomKind.FILL_NONE,
	&"fountain": RoomKind.FILL_NONE,
	&"treasure": RoomKind.FILL_NONE,
	&"challenge": RoomKind.FILL_ENEMIES,
}
const N: int = 1 << RoomSocket.Facing.NORTH
const E: int = 1 << RoomSocket.Facing.EAST
const S: int = 1 << RoomSocket.Facing.SOUTH
const W: int = 1 << RoomSocket.Facing.WEST
## The templates: id, kinds, size, sockets (a bit for each facing).
const ROOMS: Array = [
	[&"porch", [&"start"], Vector2(256, 256), N | E | S | W],
	[&"hall_a", [&"fight"], Vector2(384, 320), N | E | S | W],
	[&"hall_b", [&"fight"], Vector2(448, 256), E | W],
	[&"hall_c", [&"fight"], Vector2(320, 384), N | S],
	[&"hall_d", [&"fight"], Vector2(512, 384), N | E | S | W],
	[&"hall_e", [&"fight"], Vector2(320, 320), N | E | W],
	[&"hall_f", [&"fight"], Vector2(384, 256), E | S | W],
	[&"hall_g", [&"fight"], Vector2(448, 448), N | E | S | W],
	[&"hall_h", [&"fight"], Vector2(256, 384), N | E | S],
	[&"hall_i", [&"fight"], Vector2(576, 320), N | E | S | W],
	[&"hall_j", [&"fight"], Vector2(320, 256), N | W],
	[&"hall_k", [&"fight", &"challenge"], Vector2(512, 448), N | E | S | W],
	[&"hall_l", [&"fight"], Vector2(384, 384), E | S],
	[&"hall_m", [&"fight", &"challenge"], Vector2(448, 320), N | E | S | W],
	[&"hall_n", [&"fight"], Vector2(256, 320), N | S | W],
	[&"throne_a", [&"boss"], Vector2(576, 448), S],
	[&"throne_b", [&"boss"], Vector2(512, 512), W | N],
	[&"altar_a", [&"reward"], Vector2(256, 256), N | E | S | W],
	[&"altar_b", [&"reward"], Vector2(320, 256), E | W],
	[&"stall_a", [&"shop"], Vector2(320, 320), N | E | S | W],
	[&"stall_b", [&"shop"], Vector2(256, 320), N | S],
	[&"nook_a", [&"secret"], Vector2(256, 256), N],
	[&"nook_b", [&"secret"], Vector2(256, 256), E],
	[&"nook_c", [&"secret"], Vector2(256, 256), S | W],
	[&"well", [&"fountain"], Vector2(320, 320), N | E | S | W],
	[&"vault", [&"treasure"], Vector2(256, 256), W | N],
]
## The bridges' lengths, and the shortest's ids.
const BRIDGE_LENGTHS: Array[int] = [96, 128, 160, 192, 224, 256, 288, 320, 352, 384]
const BRIDGE_ACROSS: StringName = &"plank_across_128"
const BRIDGE_DOWN: StringName = &"plank_down_128"

var content: RunContent = null
## Template id to its unmirrored shape.
var shapes: Dictionary = {}


func _init(rooms: Array = ROOMS) -> void:
	var kinds: Array[Resource] = []
	for id: StringName in KINDS:
		var kind := RoomKind.new()
		kind.id = id
		kind.fill = KINDS[id]
		kinds.append(kind)
	var templates: Array[Resource] = []
	for row: Array in rooms:
		templates.append(_template(row[0], row[1], false))
		shapes[row[0]] = room_shape(row[0], row[2], row[3])
	for length: int in BRIDGE_LENGTHS:
		for down: bool in [false, true]:
			var id := StringName("plank_%s_%d" % ["down" if down else "across", length])
			templates.append(_template(id, [], true))
			shapes[id] = bridge_shape(id, down, float(length))
	var enemies: Array[Resource] = [_enemy(&"rat", 1, 0), _enemy(&"wolf", 3, 1), _enemy(&"ogre", 7, 3), _enemy(&"king", 10, 0, true)]
	content = RunContent.gather(kinds, templates, enemies)


func _template(id: StringName, kinds: Array, walkway: bool) -> RoomBase:
	var room := MadeUpRoom.new()
	room.id = id
	room.biome = BIOME
	room.walkway = walkway
	var hosted: Array[StringName] = []
	hosted.assign(kinds)
	room.kinds = hosted
	return room


func _enemy(id: StringName, cost: int, min_depth: int, boss: bool = false) -> EnemyBase:
	var enemy := EnemyBase.new()
	enemy.id = id
	enemy.biomes = [BIOME] as Array[StringName]
	enemy.cost = cost
	enemy.min_depth = min_depth
	enemy.boss = boss
	return enemy


## A slab of `size` ringed by a 32 px wall, a socket on the wall's inner face in the middle of each
## side `sockets` names (a bit a facing), north first.
static func room_shape(id: StringName, size: Vector2, sockets: int) -> PieceShape:
	var shape := PieceShape.new()
	shape.id = id
	shape.size = size
	shape.walls = [Rect2(0, 0, size.x, 32), Rect2(0, size.y - 32, size.x, 32), Rect2(0, 0, 32, size.y), Rect2(size.x - 32, 0, 32, size.y)] as Array[Rect2]
	var middle: Vector2 = (size * 0.5 / PieceShape.GRID).floor() * PieceShape.GRID
	var at: Dictionary = {
		RoomSocket.Facing.NORTH: Vector2(middle.x, 32),
		RoomSocket.Facing.EAST: Vector2(size.x - 32, middle.y),
		RoomSocket.Facing.SOUTH: Vector2(middle.x, size.y - 32),
		RoomSocket.Facing.WEST: Vector2(32, middle.y),
	}
	for facing: int in [RoomSocket.Facing.NORTH, RoomSocket.Facing.EAST, RoomSocket.Facing.SOUTH, RoomSocket.Facing.WEST]:
		if (sockets & (1 << facing)) != 0:
			shape.socket_at.append(at[facing])
			shape.socket_facing.append(facing)
	return shape


## A bridge `length` px long and 64 px across, west to east (or north to south when `down`), its
## sockets at its ends.
static func bridge_shape(id: StringName, down: bool, length: float = 128.0) -> PieceShape:
	var shape := PieceShape.new()
	shape.id = id
	shape.walkway = true
	if down:
		shape.size = Vector2(64, length)
		shape.socket_at = PackedVector2Array([Vector2(32, 0), Vector2(32, length)])
		shape.socket_facing = PackedInt32Array([RoomSocket.Facing.NORTH, RoomSocket.Facing.SOUTH])
	else:
		shape.size = Vector2(length, 64)
		shape.socket_at = PackedVector2Array([Vector2(0, 32), Vector2(length, 32)])
		shape.socket_facing = PackedInt32Array([RoomSocket.Facing.WEST, RoomSocket.Facing.EAST])
	return shape


## The cellar's rules (decision 1): 8 to 12 rooms; the boss deepest; a reward room, a shop, a secret
## room and 4 fights in every biome; by chance a fountain, a treasure room, a second secret and a
## challenge room (from 2 bridges deep); the rest fights. In `styles` (default: the four).
static func rules(styles: Array[MapStyle] = []) -> MapRules:
	var made := MapRules.new()
	made.biome = BIOME
	made.room_budget = 9
	made.rooms_min = 8
	made.rooms_max = 12
	made.fights_on_way = 4
	made.scale_depth = 8
	made.styles = styles if not styles.is_empty() else four_styles()
	var boss := _line(&"boss", -1, -1, 1, 1, 0.0)
	boss.dead_end = true
	var fight := _line(&"fight", 0, -2, 4, 0, 0.0)
	var secret := _line(&"secret", 1, -2, 1, 2, 0.5)
	secret.dead_end = true
	var treasure := _line(&"treasure", 1, -2, 0, 1, 0.5)
	treasure.dead_end = true
	made.kinds = [fight, boss, _line(&"reward", 0, -2, 1, 1, 0.0), _line(&"shop", 0, -2, 1, 1, 0.0), secret, _line(&"fountain", 0, -2, 0, 1, 0.5), treasure, _line(&"challenge", 2, -2, 0, 1, 0.4)] as Array[KindRule]
	return made


## The four styles of decision 5 (the crypt's numbers, content/runs/crypt.tres).
static func four_styles() -> Array[MapStyle]:
	return [
		MapStyle.make(&"long", 0.75, 0.2),
		MapStyle.make(&"branching", 0.4, 0.6),
		MapStyle.make(&"loop", 0.45, 0.5, 0.0, 3, 5000.0),
		MapStyle.make(&"hub", 0.35, 0.05, 6.0),
	] as Array[MapStyle]


static func _line(kind: StringName, first: int, last: int, least: int, most: int, chance: float) -> KindRule:
	var rule := KindRule.make(kind, first, last)
	rule.least = least
	rule.max_per_run = most
	rule.chance = chance
	return rule


## A run of the cellar by `of_rules` (default: `rules()`), scaled with depth and players.
static func run(of_rules: MapRules = null) -> RunDefinition:
	var made := RunDefinition.new()
	made.id = &"cellar_run"
	made.biomes = [of_rules if of_rules != null else rules()] as Array[MapRules]
	made.scaling = RunScaling.new()
	made.scaling.per_depth = ScaleCurve.make(1.0, 2.0, 1.0)
	made.scaling.per_player = ScaleCurve.make(1.0, 1.5, 1.0)
	return made
