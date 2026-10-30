extends Node
## The horde director (autoload `Horde`; docs/milestones/horde.md, part H3): runs a horde run's
## world from `horde_started(world)` until `horde_ended` or the next `horde_started` (a restart:
## it forgets the old world and starts over).
##
## - **Spawning:** who and how many comes from the curve (`horde_curve.tres`, a `HordeCurve`).
##   Enemies appear on a ring just outside the camera's view around the party's middle, clamped
##   inside the arena's floor (the room's walls, WALL_MARGIN in), never closer than
##   SPAWN_MIN_DISTANCE to a wizard, at most SPAWN_PER_FRAME a step. They are ordinary enemy
##   actors from the registry (`enemies`), added under one `Horde` Node2D in the world. An id
##   the registry does not have is skipped, with one warning.
## - **Kills and experience:** `enemy_died` of an enemy under the `Horde` node counts a kill and
##   drops a gem there (`horde_gems.gd`, one draw node). A standing wizard within PICKUP_RADIUS
##   pulls a gem in; its experience is the party's: one shared level, next at `xp_next(level)`.
## - **Level-up:** every joined seat gets its own `horde_picks_offered(seat, up to OFFER_SIZE
##   card ids)` from the spell cards (`spells`, `SpellComponent`) not yet in its bag. One open
##   offer per seat; a level-up while one is open waits behind it. `horde_pick_requested` puts
##   the card in the bag (`bag_set_requested`) and sends `horde_pick_taken`.
## - **Build break:** a level-up starts BUILD_BREAK seconds (`horde_break_changed`): the `Horde`
##   node is disabled (the horde stands frozen), nothing spawns, the shots in flight are
##   cleared; it ends on time (`horde_break_changed(0)`). A level-up in a break does not lengthen
##   it. The run's clock stands still in a break.
## - **Bags:** `bag_set_requested(seat, START_BAG)` for every wizard on start, and for a joiner on
##   the step after its `player_joined` (Flow adds its wizard in its own handler of that event).
## - **Status:** `horde_status` every STATUS_INTERVAL seconds.
## - **The end:** when every joined wizard is down, `horde_over` once; it is final until the next
##   `horde_started` (a revive or a join after it changes nothing), and nothing spawns after it.
##
## All timing is in `step(delta)` (`_process` calls it), so tests drive it with fixed deltas.
## Nothing is allocated in a step without a spawn, a kill or a level-up, and nothing in it
## grows with the number of enemies but the gem pass: the alive count is a counter, a death is
## checked by its parent, and nobody connects to an enemy.

const EventsScript := preload("res://core/events/events.gd")
const RegistryScript := preload("res://core/registry/registry.gd")
const ProjectileManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const ActorsScript := preload("res://core/actors/actors.gd")
const GemsScript := preload("res://gameplay/horde/horde_gems.gd")
const ShaderWarmupScript := preload("res://core/projectiles/shader_warmup.gd")
## The swarm's look's shader (swarm_look.gd), compiled before the first room with the rest.
const SwarmLookShader: Shader = preload("res://gameplay/horde/swarm_look.gdshader")
const DefaultCurve: HordeCurve = preload("res://gameplay/horde/horde_curve.tres")

const SEATS: int = 4
## The cards every wizard's bag holds at the start of a horde run (and a joiner's).
const START_BAG: Array[StringName] = [&"dash", &"fire", &"bolt"]
## Cards in one level-up offer.
const OFFER_SIZE: int = 3
## Seconds of the build break a level-up starts.
const BUILD_BREAK: float = 8.0
## At most this many enemies appear in one step, so a burst never hitches.
const SPAWN_PER_FRAME: int = 4
## No enemy appears closer than this to a wizard (pixels).
const SPAWN_MIN_DISTANCE: float = 160.0
## How far past the edge of the view an enemy appears (pixels).
const SPAWN_RING_MARGIN: float = 40.0
## Random directions tried for one spawn before it waits for the next step.
const SPAWN_TRIES: int = 8
## How far inside the room's outer edge the floor enemies stand on starts (pixels): one 32-pixel
## wall tile and a body's radius (12).
const WALL_MARGIN: float = 44.0
## The arena when the world shows no walls and no camera limits (the horde room's size).
const FALLBACK_ARENA: Rect2 = Rect2(0.0, 0.0, 1280.0, 720.0)
## A standing wizard this close to a gem pulls it in (pixels).
const PICKUP_RADIUS: float = 48.0
## Experience one kill's gem is worth.
const GEM_XP: int = 1
## Seconds between two `horde_status`.
const STATUS_INTERVAL: float = 0.25
## The registry folders it reads.
const ENEMY_FOLDER: StringName = &"enemies"
const CARD_FOLDER: StringName = &"spells"
const ROOM_FOLDER: StringName = &"rooms"
const ROOM_ID: StringName = &"horde"
## The node the horde's enemies stand under.
const HORDE_NODE_NAME: String = "Horde"
## A camera limit this wide or more counts as none (Godot's default is 10,000,000).
const NO_LIMIT: int = 1000000

## The services. Only tests set these, before adding the node; otherwise the autoloads are used.
var events: EventsScript = null
var registry: RegistryScript = null
var projectiles: ProjectileManagerScript = null
var actors: ActorsScript = null
## The curve the next start uses.
var curve: HordeCurve = DefaultCurve
## The size of the view in pixels. Only tests set this; otherwise the viewport's.
var view_size: Vector2 = Vector2.ZERO
## The randomness of spawns and offers. Tests seed it.
var rng: RandomNumberGenerator = RandomNumberGenerator.new()

## The world of the run, or null while no horde runs.
var world: Node2D = null
## Seconds the run has lasted (not counting build breaks), kills, the party's level and its
## experience towards the next.
var seconds: float = 0.0
var kills: int = 0
var level: int = 1
var xp: int = 0
## Horde enemies alive now.
var alive: int = 0
## True once every wizard was down: `horde_over` was sent and nothing spawns.
var over: bool = false
## How many "missing enemy" warnings were given (one at most); tests read it.
var missing_warnings: int = 0

var _horde: Node2D = null
var _gems: GemsScript = null
var _camera: Camera2D = null
## The floor enemies may appear on, in world pixels.
var _arena: Rect2 = FALLBACK_ARENA
## The curve's enemies, by `curve.ids` index (null for an id the registry lacks).
var _kinds: Array[EnemyBase] = []
## Every spell card id in the registry, read on start.
var _cards: Array[StringName] = []
var _spawn_debt: float = 0.0
var _break_left: float = 0.0
var _status_left: float = 0.0
## Per seat: joined this run, down, its bag, its open offer (empty: none) and how many offers
## wait behind it.
var _joined: Array[bool] = [false, false, false, false]
var _down: Array[bool] = [false, false, false, false]
var _bags: Array[Array] = [[], [], [], []]
var _offers: Array[Array] = [[], [], [], []]
var _queued: PackedInt32Array = PackedInt32Array([0, 0, 0, 0])
## Per seat: a joiner whose start bag goes out on the next step (its wizard is added by Flow's own
## `player_joined` handler, which may run after this one).
var _bag_due: Array[bool] = [false, false, false, false]
## The wizards' positions this step and whether each stands (1) or not (0), by seat.
var _wizard_at: PackedVector2Array = PackedVector2Array()
var _standing: PackedByteArray = PackedByteArray()
var _present: PackedByteArray = PackedByteArray()


func _init() -> void:
	_wizard_at.resize(SEATS)
	_standing.resize(SEATS)
	_present.resize(SEATS)
	rng.randomize()


func _ready() -> void:
	ShaderWarmupScript.want(SwarmLookShader, ShaderWarmupScript.BATCH)
	if events == null:
		events = get_node_or_null("/root/Events") as EventsScript
	if registry == null:
		registry = get_node_or_null("/root/Registry") as RegistryScript
	if projectiles == null:
		projectiles = get_node_or_null("/root/Projectiles") as ProjectileManagerScript
	if actors == null:
		actors = get_node_or_null("/root/Actors") as ActorsScript
	if events == null:
		push_warning("Horde: the Events autoload is missing, so no horde run can start.")
		return
	events.horde_started.connect(_on_horde_started)
	events.horde_ended.connect(stop)
	events.enemy_died.connect(_on_enemy_died)
	events.horde_pick_requested.connect(_on_pick_requested)
	events.player_downed.connect(_on_player_downed)
	events.player_revived.connect(_on_player_revived)
	events.player_joined.connect(_on_player_joined)
	events.player_left.connect(_on_player_left)


func _process(delta: float) -> void:
	step(delta)


## True while a horde run is up.
func is_running() -> bool:
	return world != null


## Seconds of the build break left, or 0 when there is none.
func break_left() -> float:
	return _break_left


## The `Horde` node the enemies stand under, or null while no run is up.
func horde_node() -> Node2D:
	return _horde


## The gems' draw node, or null while no run is up.
func gems() -> GemsScript:
	return _gems


## The floor enemies appear on (world pixels).
func arena() -> Rect2:
	return _arena


## The card ids of `seat`'s open offer (empty: none).
func offer_of(seat: int) -> Array[StringName]:
	var out: Array[StringName] = []
	if seat >= 0 and seat < SEATS:
		out.assign(_offers[seat])
	return out


## The bag the director gave `seat`.
func bag_of(seat: int) -> Array[StringName]:
	var out: Array[StringName] = []
	if seat >= 0 and seat < SEATS:
		out.assign(_bags[seat])
	return out


## Offers waiting behind `seat`'s open one.
func queued_of(seat: int) -> int:
	return _queued[seat] if seat >= 0 and seat < SEATS else 0


## Experience from level `at` to the next: a slow curve (5, 10, 17, 26, 37, ...).
static func xp_next(at: int) -> int:
	var past: int = maxi(at, 1) - 1
	return 5 + 4 * past + past * past


## Starts the director on `new_world`, forgetting any run in progress.
func start(new_world: Node2D) -> void:
	stop()
	if new_world == null or not is_instance_valid(new_world):
		return
	world = new_world
	seconds = 0.0
	kills = 0
	level = 1
	xp = 0
	alive = 0
	over = false
	_spawn_debt = 0.0
	_break_left = 0.0
	_status_left = 0.0
	_horde = Node2D.new()
	_horde.name = HORDE_NODE_NAME
	world.add_child(_horde)
	_gems = GemsScript.new()
	world.add_child(_gems)
	# On the floor: drawn after the room, before the wizards and the horde.
	world.move_child(_gems, mini(1, world.get_child_count() - 1))
	_camera = _find_camera()
	_arena = _find_arena()
	_read_kinds()
	_read_cards()
	for seat in SEATS:
		_joined[seat] = _wizard_of(seat) != null
		_down[seat] = false
		_queued[seat] = 0
		_offers[seat].clear()
		if _joined[seat]:
			_give_start_bag(seat)
	_send_status()


## Stops the run in progress (if any): the open offers are dropped, a break ends, the director's
## nodes go and the world is forgotten.
func stop() -> void:
	if world == null:
		return
	for seat in SEATS:
		_drop_offer(seat)
		_joined[seat] = false
		_down[seat] = false
		_bag_due[seat] = false
	if _break_left > 0.0:
		_break_left = 0.0
		if events != null:
			events.horde_break_changed.emit(0.0)
	for node: Node in [_horde, _gems]:
		if node != null and is_instance_valid(node):
			var parent: Node = node.get_parent()
			if parent != null:
				parent.remove_child(node)
			node.queue_free()
	_horde = null
	_gems = null
	_camera = null
	world = null
	alive = 0


## Moves the run on by `delta` seconds: the break, the clock, spawning, the gems, the status.
func step(delta: float) -> void:
	if world == null:
		return
	if not is_instance_valid(world) or _horde == null or not is_instance_valid(_horde):
		# The world went without `horde_ended`: forget it.
		stop()
		return
	for seat in SEATS:
		if _bag_due[seat]:
			_bag_due[seat] = false
			if _joined[seat]:
				_give_start_bag(seat)
	_read_wizards()
	if _break_left > 0.0:
		_break_left -= delta
		if _break_left <= 0.0:
			_end_break()
	elif not over:
		seconds += delta
		_spawn(delta)
	if _gems != null:
		var picked: int = _gems.step(delta, _wizard_at, _standing, PICKUP_RADIUS)
		if picked > 0:
			_gain(picked)
	_status_left -= delta
	if _status_left <= 0.0:
		_send_status()


# --- Spawning -----------------------------------------------------------------------------------

func _spawn(delta: float) -> void:
	if curve == null or _kinds.is_empty():
		return
	var rate: float = curve.rate_at(seconds)
	var room: int = curve.cap_at(seconds) - alive
	_spawn_debt = minf(_spawn_debt + rate * delta, maxf(rate, float(SPAWN_PER_FRAME)))
	var count: int = mini(mini(floori(_spawn_debt), SPAWN_PER_FRAME), room)
	for n in count:
		var data: EnemyBase = _pick_kind()
		if data == null:
			return
		var at: Vector2 = spawn_point()
		if at == Vector2.INF:
			return
		if not _add_enemy(data, at):
			return
		_spawn_debt -= 1.0


## A weighted pick of the curve's enemies at the run's time (null when none weighs anything).
func _pick_kind() -> EnemyBase:
	var total: float = 0.0
	for i in _kinds.size():
		if _kinds[i] != null:
			total += curve.weight_at(seconds, i)
	if total <= 0.0:
		return null
	var roll: float = rng.randf() * total
	var last: EnemyBase = null
	for i in _kinds.size():
		if _kinds[i] == null:
			continue
		var weight: float = curve.weight_at(seconds, i)
		if weight <= 0.0:
			continue
		last = _kinds[i]
		roll -= weight
		if roll < 0.0:
			return last
	return last


func _add_enemy(data: EnemyBase, at: Vector2) -> bool:
	var node: Node = data.scene.instantiate()
	var body := node as Node2D
	if body == null:
		if node != null:
			node.free()
		return false
	var enemy := body as Actor
	if enemy != null:
		enemy.data = data
	body.position = at
	_horde.add_child(body)
	alive += 1
	return true


## Where the next enemy appears: on the ring just outside the view round the party's middle,
## clamped to the floor, at least SPAWN_MIN_DISTANCE from every wizard; outside the view if any
## try lands there. Vector2.INF when no try keeps its distance (it waits for the next step).
func spawn_point() -> Vector2:
	var view: Rect2 = view_rect()
	var middle: Vector2 = _party_middle(view)
	var best: Vector2 = Vector2.INF
	for attempt in SPAWN_TRIES:
		var direction: Vector2 = Vector2.from_angle(rng.randf() * TAU)
		var reach: float = _exit_distance(middle, direction, view) + SPAWN_RING_MARGIN
		var at: Vector2 = (middle + direction * reach).clamp(_arena.position, _arena.end)
		if not _clear_of_wizards(at):
			continue
		if not view.has_point(at):
			return at
		if best == Vector2.INF:
			best = at
	return best


## The part of the world the camera shows now (world pixels): the camera's position kept inside
## its limits, the view's size over its zoom. Without a camera, the arena.
func view_rect() -> Rect2:
	if _camera == null or not is_instance_valid(_camera):
		return _arena
	var zoom: float = maxf(_camera.zoom.x, 0.01)
	var size: Vector2 = _view_size() / zoom
	var centre: Vector2 = _camera.position
	var half: Vector2 = size * 0.5
	if _camera.limit_right - _camera.limit_left < NO_LIMIT:
		var low: float = float(_camera.limit_left) + half.x
		var high: float = float(_camera.limit_right) - half.x
		centre.x = clampf(centre.x, low, high) if low <= high else (low + high) * 0.5
	if _camera.limit_bottom - _camera.limit_top < NO_LIMIT:
		var low: float = float(_camera.limit_top) + half.y
		var high: float = float(_camera.limit_bottom) - half.y
		centre.y = clampf(centre.y, low, high) if low <= high else (low + high) * 0.5
	return Rect2(centre - half, size)


func _view_size() -> Vector2:
	if view_size != Vector2.ZERO:
		return view_size
	var viewport: Viewport = get_viewport()
	if viewport == null:
		return Vector2(640.0, 360.0)
	return viewport.get_visible_rect().size


## How far from `from` along `direction` the ray leaves `rect` (0 when it never does, from
## outside).
static func _exit_distance(from: Vector2, direction: Vector2, rect: Rect2) -> float:
	var reach: float = INF
	if direction.x > 0.0001:
		reach = minf(reach, (rect.end.x - from.x) / direction.x)
	elif direction.x < -0.0001:
		reach = minf(reach, (rect.position.x - from.x) / direction.x)
	if direction.y > 0.0001:
		reach = minf(reach, (rect.end.y - from.y) / direction.y)
	elif direction.y < -0.0001:
		reach = minf(reach, (rect.position.y - from.y) / direction.y)
	return maxf(reach, 0.0) if reach != INF else 0.0


## The middle of the standing wizards (of every wizard when none stands), or the view's centre.
func _party_middle(view: Rect2) -> Vector2:
	var sum: Vector2 = Vector2.ZERO
	var found: int = 0
	for only_standing: bool in [true, false]:
		for seat in SEATS:
			if _present[seat] != 0 and (not only_standing or _standing[seat] != 0):
				sum += _wizard_at[seat]
				found += 1
		if found > 0:
			return sum / float(found)
	return view.get_center()


func _clear_of_wizards(at: Vector2) -> bool:
	var keep: float = SPAWN_MIN_DISTANCE * SPAWN_MIN_DISTANCE
	for seat in SEATS:
		if _present[seat] != 0 and at.distance_squared_to(_wizard_at[seat]) < keep:
			return false
	return true


# --- Kills, gems and levels ---------------------------------------------------------------------

func _on_enemy_died(_killer: int, enemy: Node, at: Vector2, _shot: int) -> void:
	if world == null or _horde == null or enemy == null or not is_instance_valid(enemy):
		return
	# After `horde_over` the summary's numbers stand: a death in the last seconds counts for nothing.
	if over or enemy.get_parent() != _horde:
		return
	kills += 1
	alive = maxi(alive - 1, 0)
	if _gems != null:
		# `at` is a global position; the gems lie in the world's space.
		_gems.add(world.to_local(at) if world.is_inside_tree() else at, GEM_XP)


func _gain(amount: int) -> void:
	xp += amount
	while xp >= xp_next(level):
		xp -= xp_next(level)
		level += 1
		_level_up()


## A level-up: an offer for every joined seat (or one more waiting behind its open one), and a
## build break unless one is on.
func _level_up() -> void:
	for seat in SEATS:
		if not _joined[seat]:
			continue
		if not _offers[seat].is_empty():
			_queued[seat] += 1
		else:
			_offer(seat)
	if _break_left <= 0.0 and not over:
		_start_break()


## Opens a new offer for `seat` from the cards not in its bag; with every card owned, none.
func _offer(seat: int) -> bool:
	var choices: Array[StringName] = []
	var bag: Array = _bags[seat]
	for id: StringName in _cards:
		if not bag.has(id):
			choices.append(id)
	if choices.is_empty():
		_queued[seat] = 0
		return false
	var take: int = mini(OFFER_SIZE, choices.size())
	for i in take:
		var j: int = i + rng.randi_range(0, choices.size() - 1 - i)
		var swap: StringName = choices[i]
		choices[i] = choices[j]
		choices[j] = swap
	choices.resize(take)
	_offers[seat].assign(choices)
	if events != null:
		events.horde_picks_offered.emit(seat, choices.duplicate())
	return true


func _on_pick_requested(seat: int, choice: int) -> void:
	if world == null or seat < 0 or seat >= SEATS:
		return
	var offer: Array = _offers[seat]
	if choice < 0 or choice >= offer.size():
		return
	var card: StringName = offer[choice]
	offer.clear()
	if not _bags[seat].has(card):
		_bags[seat].append(card)
	if events != null:
		events.bag_set_requested.emit(seat, bag_of(seat))
		events.horde_pick_taken.emit(seat, card)
	if _queued[seat] > 0:
		_queued[seat] -= 1
		_offer(seat)


func _drop_offer(seat: int) -> void:
	_queued[seat] = 0
	if _offers[seat].is_empty():
		return
	_offers[seat].clear()
	if events != null:
		events.horde_pick_taken.emit(seat, &"")


func _give_start_bag(seat: int) -> void:
	_bags[seat].assign(START_BAG)
	if events != null:
		events.bag_set_requested.emit(seat, bag_of(seat))


# --- The build break ----------------------------------------------------------------------------

func _start_break() -> void:
	_break_left = BUILD_BREAK
	if _horde != null:
		_horde.process_mode = Node.PROCESS_MODE_DISABLED
	if projectiles != null:
		projectiles.clear()
	if events != null:
		events.horde_break_changed.emit(BUILD_BREAK)


func _end_break() -> void:
	_break_left = 0.0
	if _horde != null and is_instance_valid(_horde):
		_horde.process_mode = Node.PROCESS_MODE_INHERIT
	if events != null:
		events.horde_break_changed.emit(0.0)


# --- Players ------------------------------------------------------------------------------------

func _on_player_joined(seat: int) -> void:
	if world == null or seat < 0 or seat >= SEATS:
		return
	_joined[seat] = true
	_down[seat] = false
	_drop_offer(seat)
	# Its bag goes out on the next step, when Flow has surely added its wizard.
	_bag_due[seat] = true
	_bags[seat].assign(START_BAG)


func _on_player_left(seat: int) -> void:
	if world == null or seat < 0 or seat >= SEATS:
		return
	_joined[seat] = false
	_down[seat] = false
	_bag_due[seat] = false
	_drop_offer(seat)
	_check_over()


func _on_player_downed(seat: int) -> void:
	if world == null or seat < 0 or seat >= SEATS:
		return
	_down[seat] = true
	_check_over()


func _on_player_revived(seat: int, _reviver: int) -> void:
	if world == null or seat < 0 or seat >= SEATS:
		return
	_down[seat] = false


## Every joined wizard down: `horde_over` once, and nothing spawns after it.
func _check_over() -> void:
	if over:
		return
	var any: bool = false
	for seat in SEATS:
		if _joined[seat]:
			any = true
			if not _down[seat]:
				return
	if not any:
		return
	over = true
	if _break_left > 0.0:
		_end_break()
	if events != null:
		events.horde_over.emit(seconds, kills, level)
	_send_status()


# --- Reading the world --------------------------------------------------------------------------

## Seat `seat`'s own wizard in this world (its home body), or null.
func _wizard_of(seat: int) -> Node2D:
	if actors == null or world == null:
		return null
	var node := actors.node_of(actors.home_of_seat(seat)) as Node2D
	if node == null or not _in_world(node):
		return null
	return node


## True when `node` is below the world (walked up by hand: it holds out of the tree too).
func _in_world(node: Node) -> bool:
	var at: Node = node.get_parent()
	while at != null:
		if at == world:
			return true
		at = at.get_parent()
	return false


## Where each seat's wizard is this step, and whether it stands.
func _read_wizards() -> void:
	for seat in SEATS:
		var wizard: Node2D = _wizard_of(seat) if _joined[seat] else null
		_present[seat] = 1 if wizard != null else 0
		_standing[seat] = 1 if wizard != null and not _down[seat] else 0
		if wizard != null:
			_wizard_at[seat] = _to_world(wizard).origin


## The world's camera: the viewport's current one when it is in the world, else the first in it.
func _find_camera() -> Camera2D:
	if world.is_inside_tree():
		var current: Camera2D = world.get_viewport().get_camera_2d()
		if current != null and _in_world(current):
			return current
	var found: Array[Node] = world.find_children("*", "Camera2D", true, false)
	return found[0] as Camera2D if not found.is_empty() else null


## The floor enemies may appear on: the box round the room's walls (every wall-layer body's
## shapes in the world), else the camera's limits, else the registry room's spawns, else
## FALLBACK_ARENA; then WALL_MARGIN in.
func _find_arena() -> Rect2:
	var outer: Rect2 = _walls_box()
	if outer.size == Vector2.ZERO and _camera != null and _camera.limit_right - _camera.limit_left < NO_LIMIT and _camera.limit_bottom - _camera.limit_top < NO_LIMIT:
		outer = Rect2(Vector2(_camera.limit_left, _camera.limit_top), Vector2(_camera.limit_right - _camera.limit_left, _camera.limit_bottom - _camera.limit_top))
	if outer.size == Vector2.ZERO:
		outer = _room_spawns_box()
	if outer.size == Vector2.ZERO:
		outer = FALLBACK_ARENA
	var floor_rect: Rect2 = outer.grow(-WALL_MARGIN)
	if floor_rect.size.x <= 0.0 or floor_rect.size.y <= 0.0:
		return outer
	return floor_rect


## The box round every shape of the world's wall bodies (static bodies on layer 1), in world
## pixels; empty when there are none.
func _walls_box() -> Rect2:
	var box: Rect2 = Rect2()
	var found: bool = false
	for node: Node in world.find_children("*", "StaticBody2D", true, false):
		var body := node as StaticBody2D
		if (body.collision_layer & 1) == 0:
			continue
		for child: Node in body.get_children():
			var piece: Rect2 = _shape_box(child)
			if piece.size == Vector2.ZERO:
				continue
			box = piece if not found else box.merge(piece)
			found = true
	return box


## One collision shape's box in world pixels (empty for anything else).
func _shape_box(node: Node) -> Rect2:
	var local: Rect2 = Rect2()
	var shape_node := node as CollisionShape2D
	if shape_node != null and shape_node.shape != null:
		local = shape_node.shape.get_rect()
	var polygon_node := node as CollisionPolygon2D
	if polygon_node != null and polygon_node.polygon.size() > 0:
		local = Rect2(polygon_node.polygon[0], Vector2.ZERO)
		for point: Vector2 in polygon_node.polygon:
			local = local.expand(point)
	if local.size == Vector2.ZERO:
		return Rect2()
	return _to_world(node as Node2D) * local


## The transform from `node`'s space to the world's.
func _to_world(node: Node2D) -> Transform2D:
	var out: Transform2D = Transform2D.IDENTITY
	var at: Node = node
	while at != null and at != world:
		var step_node := at as Node2D
		if step_node != null:
			out = step_node.transform * out
		at = at.get_parent()
	return out


## The registry's horde room, measured by its spawns as Flow does (a tile past the furthest).
func _room_spawns_box() -> Rect2:
	var room: RoomBase = registry.get_resource(ROOM_FOLDER, ROOM_ID) as RoomBase if registry != null else null
	if room == null:
		return Rect2()
	var size := Vector2.ZERO
	for points: PackedVector2Array in [room.player_spawns, room.enemy_spawns, room.doors]:
		for point: Vector2 in points:
			size = size.max(point + Vector2(32.0, 32.0))
	return Rect2(Vector2.ZERO, size) if size.x > 0.0 and size.y > 0.0 else Rect2()


## The curve's enemies from the registry; the missing ones are skipped, with one warning ever.
func _read_kinds() -> void:
	_kinds.clear()
	if curve == null:
		return
	curve.prepare()
	var missing: PackedStringArray = PackedStringArray()
	for id: StringName in curve.ids:
		var data: EnemyBase = registry.get_resource(ENEMY_FOLDER, id) as EnemyBase if registry != null else null
		if data != null and data.scene == null:
			data = null
		if data == null:
			missing.append(String(id))
		_kinds.append(data)
	if not missing.is_empty() and missing_warnings == 0:
		missing_warnings += 1
		push_warning("Horde: the enemies %s are missing from the registry, so the horde runs without them." % ", ".join(missing))


func _read_cards() -> void:
	_cards.clear()
	if registry == null:
		return
	for id: StringName in registry.get_ids(CARD_FOLDER):
		if registry.get_resource(CARD_FOLDER, id) is SpellComponent:
			_cards.append(id)


func _send_status() -> void:
	_status_left = STATUS_INTERVAL
	if events != null:
		events.horde_status.emit(seconds, kills, alive, level, xp, xp_next(level))


func _on_horde_started(new_world: Node2D) -> void:
	start(new_world)
