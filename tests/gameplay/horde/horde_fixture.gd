extends RefCounted
## A small horde run for the director's tests: its own event bus, actor table, a stand-in
## registry (made-up enemies and cards), a director (`HordeScript`) wired to them in `root`
## (stepped only by hand, on the desktop cap), and a world
## out of the tree: a 1280x720 room walled 32 pixels thick, a camera in its middle, and a wizard
## per seat, registered as that seat's home body. Every event the director sends is recorded.
## `free_all()` frees everything.

const HordeScript := preload("res://gameplay/horde/horde.gd")
const EventsScript := preload("res://core/events/events.gd")
const ActorsScript := preload("res://core/actors/actors.gd")

## The room's size and the walls' thickness.
const ROOM: Vector2 = Vector2(1280.0, 720.0)
const WALL: float = 32.0
## The view the director is told about (the camera at zoom 1).
const VIEW: Vector2 = Vector2(640.0, 360.0)
## The made-up enemies and cards.
const ENEMY_A: StringName = &"test_swarmer"
const ENEMY_B: StringName = &"test_shooter"
const CARDS: Array[StringName] = [&"dash", &"fire", &"bolt", &"card_a", &"card_b", &"card_c", &"card_d", &"card_e"]
## A resource in the cards folder that is not a card (never offered).
const NOT_A_CARD: StringName = &"not_a_card"


## A registry stand-in with the two questions the director asks.
class FakeRegistry:
	extends "res://core/registry/registry.gd"
	var folders: Dictionary = {}

	func _ready() -> void:
		pass

	func get_resource(folder: StringName, id: StringName) -> Resource:
		var found: Dictionary = folders.get(folder, {})
		return found.get(id)

	func get_ids(folder: StringName) -> Array[StringName]:
		var out: Array[StringName] = []
		out.assign((folders.get(folder, {}) as Dictionary).keys())
		out.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
		return out


var bus: EventsScript
var actors: ActorsScript
var registry: FakeRegistry
var director: HordeScript
var world: Node2D
var camera: Camera2D
var wizards: Array[Node2D] = [null, null, null, null]

## What the director said.
var statuses: int = 0
var offers: Array[Array] = []
var taken: Array[Array] = []
var bags: Array[Array] = []
var breaks: Array[bool] = []
## Each `horde_ready_changed`, as [seat, ready].
var readies: Array[Array] = []
var overs: int = 0

var _root: Node


## A director in `root` and a world with a wizard for each of `seats`.
func _init(root: Node, seats: Array[int] = [0]) -> void:
	_root = root
	bus = EventsScript.new()
	actors = ActorsScript.new()
	registry = FakeRegistry.new()
	var enemies: Dictionary = {}
	for id: StringName in [ENEMY_A, ENEMY_B]:
		var body := Node2D.new()
		body.set_meta(&"kind", id)
		var scene := PackedScene.new()
		scene.pack(body)
		body.free()
		var data := EnemyBase.new()
		data.id = id
		data.scene = scene
		enemies[id] = data
	registry.folders[&"enemies"] = enemies
	var cards: Dictionary = {}
	for id: StringName in CARDS:
		var card := SpellComponent.new()
		card.id = id
		cards[id] = card
	cards[NOT_A_CARD] = Resource.new()
	registry.folders[&"spells"] = cards
	director = HordeScript.new()
	director.events = bus
	director.actors = actors
	director.registry = registry
	director.view_size = VIEW
	director.web = false
	director.curve = curve([[0.0, 4.0, 50]], {ENEMY_A: 1.0})
	director.rng.seed = 7
	root.add_child(director)
	director.set_process(false)
	world = make_world(seats)
	bus.horde_status.connect(func(_s: float, _k: int, _a: int, _l: int, _x: int, _n: int) -> void: statuses += 1)
	bus.horde_picks_offered.connect(func(seat: int, ids: Array[StringName]) -> void: offers.append([seat, ids]))
	bus.horde_pick_taken.connect(func(seat: int, id: StringName) -> void: taken.append([seat, id]))
	bus.bag_set_requested.connect(func(seat: int, bag: Array[StringName]) -> void: bags.append([seat, bag]))
	bus.horde_break_changed.connect(func(on: bool) -> void: breaks.append(on))
	bus.horde_ready_changed.connect(func(seat: int, on: bool) -> void: readies.append([seat, on]))
	bus.horde_over.connect(func(_s: float, _k: int, _l: int) -> void: overs += 1)


## A curve of `rows` ([seconds, spawns per second, cap alive]), every point with `weights`.
static func curve(rows: Array, weights: Dictionary) -> HordeCurve:
	var made := HordeCurve.new()
	for row: Array in rows:
		var point := HordeCurvePoint.new()
		point.seconds = row[0]
		point.spawns_per_second = row[1]
		point.cap_alive = row[2]
		for id: StringName in weights:
			point.weights[id] = weights[id]
		made.points.append(point)
	return made


## A walled room with a camera in the middle and a wizard for each of `seats`, side by side in
## the middle, out of the tree.
func make_world(seats: Array[int]) -> Node2D:
	var made := Node2D.new()
	made.name = "World"
	var walls := StaticBody2D.new()
	walls.collision_layer = 1
	for piece: Rect2 in [Rect2(0.0, 0.0, ROOM.x, WALL), Rect2(0.0, ROOM.y - WALL, ROOM.x, WALL),
			Rect2(0.0, 0.0, WALL, ROOM.y), Rect2(ROOM.x - WALL, 0.0, WALL, ROOM.y)]:
		var shape := CollisionShape2D.new()
		var box := RectangleShape2D.new()
		box.size = piece.size
		shape.shape = box
		shape.position = piece.get_center()
		walls.add_child(shape)
	made.add_child(walls)
	camera = Camera2D.new()
	camera.position = ROOM * 0.5
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = int(ROOM.x)
	camera.limit_bottom = int(ROOM.y)
	made.add_child(camera)
	for seat: int in seats:
		add_wizard(made, seat, ROOM * 0.5 + Vector2(40.0 * seat, 0.0))
	return made


## A wizard for `seat` in `parent` at `at`, registered as the seat's home body.
func add_wizard(parent: Node2D, seat: int, at: Vector2) -> Node2D:
	var wizard := Node2D.new()
	wizard.name = "Wizard%d" % seat
	wizard.position = at
	parent.add_child(wizard)
	var id: int = actors.open(ActorsScript.TEAM_WIZARDS, seat, seat)
	actors.set_node(id, wizard)
	actors.set_home(id, seat)
	wizards[seat] = wizard
	return wizard


func start() -> void:
	bus.horde_started.emit(world)


## `seconds` of steps of 1/60 s.
func run(seconds: float) -> void:
	for i in roundi(seconds * 60.0):
		director.step(1.0 / 60.0)


## The horde's enemies now (not counting one already freed).
func enemies() -> Array[Node2D]:
	var out: Array[Node2D] = []
	var horde: Node2D = director.horde_node()
	if horde == null:
		return out
	for child: Node in horde.get_children():
		if not child.is_queued_for_deletion():
			out.append(child as Node2D)
	return out


## Kills a horde enemy at `at` as Combat would: `enemy_died`, then it goes.
func kill(enemy: Node2D, at: Vector2) -> void:
	bus.enemy_died.emit(0, enemy, at, -1)
	enemy.get_parent().remove_child(enemy)
	enemy.free()


## Kills `count` horde enemies (spawning them first if needed) beside the wizard of `seat`, so
## their gems are pulled in at once.
func kill_beside(count: int, seat: int = 0) -> void:
	var at: Vector2 = wizards[seat].position + Vector2(20.0, 0.0)
	for i in count:
		var list: Array[Node2D] = enemies()
		if list.is_empty():
			var extra := Node2D.new()
			director.horde_node().add_child(extra)
			director.alive += 1
			list.append(extra)
		kill(list[0], at)


## Kills enough beside seat 0's wizard for one level-up, and lets the gems come in. In a build
## break (the game paused: nothing dies, no gem comes in) the experience is given directly.
func level_up() -> void:
	var need: int = HordeScript.xp_next(director.level) - director.xp
	var goal: int = director.level + 1
	if director.in_break():
		director._gain(need)
		return
	kill_beside(need)
	for i in 60:
		director.step(1.0 / 60.0)
		if director.level >= goal:
			break


## Takes every offer of `seat` (its open one and those queued behind it), the first card each.
func take_all(seat: int) -> void:
	while not director.offer_of(seat).is_empty():
		bus.horde_pick_requested.emit(seat, 0)


## Every joined seat takes its offers and says it is ready.
func all_ready() -> void:
	for seat in 4:
		take_all(seat)
		bus.horde_ready_requested.emit(seat)


func free_all() -> void:
	director.stop()
	if is_instance_valid(director):
		_root.remove_child(director)
		director.free()
	if is_instance_valid(world):
		world.free()
	for node: Node in [bus, actors, registry]:
		if is_instance_valid(node):
			node.free()
