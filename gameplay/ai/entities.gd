extends Node2D
## Entities (staffs B5): the decoys and familiars that cards make. One autoload ("Entities")
## keeps them in a fixed pool, so a card spawning one allocates nothing.
##
##     Events.entity_spawn_requested.emit(0, &"decoy", at, 6.0, tag)     # core/spells sends it
##
## A **decoy** is a still copy of its caster's wizard (the `Sprite` and its `Hat`, copied at
## spawn, a little see-through). Enemy shots hit it (it is a `core/projectiles` target on
## LAYER_PLAYER, owned by its player, so that player's own shots pass it as they pass the
## wizard), and enemies within DECOY_LURE of a decoy chase it before any wizard (`lure`, asked by
## `ai.gd`). It ends after DECOY_HITS enemy hits or when its time runs out; where it ended is its
## end point.
##
## A **familiar** is a small orb circling its caster (FAMILIAR_ORBIT px): the wizard, or for a
## familiar a trigger made the shot that fired it (a `core/projectiles` slot, followed while it
## flies) or the point it was made at. Every FAMILIAR_INTERVAL seconds it looks for the nearest
## enemy within FAMILIAR_RANGE and, if there is one, sends `familiar_cast_requested` toward it;
## core/spells casts the familiar's payload. With its wizard gone it stays where it was; with its
## shot gone it circles where the shot was last.
##
## Each player has up to PER_PLAYER of each kind; one more ends their oldest of that kind. An
## entity whose `seconds` is INF, or 0 or less, lasts until `entity_end_requested` with its tag
## (a `hold` switched off). Every end (time, hits, the cap, a request) sends `entity_ended` once,
## for core/spells (a decoy's end point). A new room or the end of the run clears them all
## quietly: their end points are gone with the room.
##
## Swap (`target_move_requested`) is heard by each enemy itself (`ai.gd`), not here.
##
## Nothing here allocates per frame; drawing is one canvas item (this node) plus the pooled
## decoy nodes. All timing runs in step(delta), so tests drive it with fixed deltas.

const EventsScript := preload("res://core/events/events.gd")
const ProjectileManagerScript := preload("res://core/projectiles/projectile_manager.gd")

const DECOY: StringName = &"decoy"
const FAMILIAR: StringName = &"familiar"
const PLAYER_SLOTS: int = 4
## `entity_spawn_requested`'s caster when it is the wizard, and when it is the point it was made at.
const CASTER_WIZARD: int = -1
const CASTER_POINT: int = -2
## Live entities of one kind one player may have.
const PER_PLAYER: int = 4
## Rows in the pool: every kind for every player.
const POOL_SIZE: int = PLAYER_SLOTS * PER_PLAYER * 2
## The group every wizard is in (player.gd adds it).
const PLAYERS_GROUP: StringName = &"players"

## Enemy shots a decoy takes before it breaks.
const DECOY_HITS: int = 3
## The decoy's hit circle and where it sits from the feet: the wizard's own (Combat's numbers
## for a wizard, see flow.gd).
const DECOY_RADIUS: float = 8.0
const DECOY_OFFSET: Vector2 = Vector2(0.0, -12.0)
## An enemy this close to a decoy chases the decoy rather than any wizard.
const DECOY_LURE: float = 240.0
## How see-through the copy is, so it never reads as a second wizard.
const DECOY_ALPHA: float = 0.6

## The familiar circles this far from the wizard's body, this fast (radians a second).
const FAMILIAR_ORBIT: float = 20.0
const FAMILIAR_TURN: float = 2.5
const FAMILIAR_CENTRE: Vector2 = Vector2(0.0, -14.0)
## Seconds between casts, and before the first one.
const FAMILIAR_INTERVAL: float = 1.0
const FAMILIAR_FIRST: float = 0.5
## Enemies further than this are not cast at.
const FAMILIAR_RANGE: float = 200.0
## The orb: radius in pixels, outline and core.
const FAMILIAR_SIZE: float = 3.0
const OUTLINE_COLOR: Color = Color("14121f")
const CORE_COLOR: Color = Color("fff4d6")

## Above the room and the wizards, below the shots (`ProjectileManagerScript.DRAW_Z`): the
## autoload is drawn before the current scene, as the shots are.
const DRAW_Z: int = 40

## The event bus and the projectile manager. Only tests set these, before adding the node;
## otherwise the "Events" and "Projectiles" autoloads.
var events: EventsScript = null
var projectiles: ProjectileManagerScript = null

## Per row. `_kind` is &"" for a free row.
var _kind: Array[StringName] = []
var _player: PackedInt32Array = PackedInt32Array()
var _tag: PackedInt32Array = PackedInt32Array()
var _left: PackedFloat32Array = PackedFloat32Array()
var _hits: PackedInt32Array = PackedInt32Array()
var _cast_left: PackedFloat32Array = PackedFloat32Array()
var _angle: PackedFloat32Array = PackedFloat32Array()
var _position: PackedVector2Array = PackedVector2Array()
## Spawn order, to find a player's oldest.
var _born: PackedInt64Array = PackedInt64Array()
## The familiar's wizard, or null.
var _caster: Array[Node2D] = []
## Without a wizard: the point a familiar circles (INF for none), and the slot and sequence number
## of the shot it follows (-1 for none).
var _centre_at: PackedVector2Array = PackedVector2Array()
var _centre_slot: PackedInt32Array = PackedInt32Array()
var _centre_seq: PackedInt64Array = PackedInt64Array()
## One pooled node per row, used when the row is a decoy.
var _decoys: Array[Decoy] = []
var _spawned: int = 0
var _live: int = 0


## A decoy as other code sees it: a Node2D that enemies may chase and shots may hit. It is
## "downed" while its row is free, so the AI drops it at once (`ai.gd`'s `_is_valid_target`).
class Decoy extends Node2D:
	var active: bool = false
	var sprite: Sprite2D = null
	var hat: Sprite2D = null

	func _init() -> void:
		sprite = Sprite2D.new()
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		add_child(sprite)
		hat = Sprite2D.new()
		hat.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		sprite.add_child(hat)
		visible = false

	func is_downed() -> bool:
		return not active

	## Look like `wizard` does now (its `Sprite` and `Sprite/Hat`); plain when it has none.
	func copy_look(wizard: Node2D) -> void:
		var from: Sprite2D = wizard.get_node_or_null("Sprite") as Sprite2D if wizard != null else null
		_copy(sprite, from)
		_copy(hat, from.get_node_or_null("Hat") as Sprite2D if from != null else null)

	func _copy(to: Sprite2D, from: Sprite2D) -> void:
		to.texture = from.texture if from != null else null
		if from == null:
			return
		to.hframes = from.hframes
		to.vframes = from.vframes
		to.frame = from.frame
		to.flip_h = from.flip_h
		to.position = from.position
		to.offset = from.offset
		to.centered = from.centered


func _init() -> void:
	z_index = DRAW_Z
	for row in POOL_SIZE:
		_kind.append(&"")
		_caster.append(null)
		_centre_at.append(Vector2.INF)
		_centre_slot.append(-1)
		_centre_seq.append(0)
		var decoy := Decoy.new()
		decoy.name = "Decoy%d" % row
		decoy.modulate.a = DECOY_ALPHA
		_decoys.append(decoy)
		add_child(decoy)
	_player.resize(POOL_SIZE)
	_tag.resize(POOL_SIZE)
	_left.resize(POOL_SIZE)
	_hits.resize(POOL_SIZE)
	_cast_left.resize(POOL_SIZE)
	_angle.resize(POOL_SIZE)
	_position.resize(POOL_SIZE)
	_born.resize(POOL_SIZE)


func _ready() -> void:
	if events == null:
		events = get_node_or_null("/root/Events") as EventsScript
	if projectiles == null:
		projectiles = get_node_or_null("/root/Projectiles") as ProjectileManagerScript
	if events == null:
		push_warning("Entities: the Events autoload is missing, so no decoy or familiar is ever made.")
		return
	events.entity_spawn_requested.connect(_on_spawn_requested)
	events.entity_end_requested.connect(_on_end_requested)
	events.projectile_hit.connect(_on_projectile_hit)
	events.room_entered.connect(_on_room_entered)
	events.run_ended.connect(_on_run_ended)


func _physics_process(delta: float) -> void:
	step(delta)


## Move time on: lifetimes, familiar orbits and casts.
func step(delta: float) -> void:
	if _live == 0:
		return
	for row in POOL_SIZE:
		if _kind[row] == &"":
			continue
		_left[row] -= delta
		if _left[row] <= 0.0:
			_end(row, true)
			continue
		if _kind[row] == FAMILIAR:
			_step_familiar(row, delta)
	queue_redraw()


## How many entities are live, of `kind` (all kinds when empty) and `player` (all when -1).
func count(kind: StringName = &"", player: int = -1) -> int:
	var found: int = 0
	for row in POOL_SIZE:
		if _kind[row] != &"" and (kind == &"" or _kind[row] == kind) and (player < 0 or _player[row] == player):
			found += 1
	return found


## Where the live entities of `player` with `tag` are, the oldest first (tests and the sheets).
func positions_of(player: int, tag: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	for row in _rows_by_age():
		if _player[row] == player and _tag[row] == tag:
			out.append(_position[row])
	return out


## The nearest live decoy within DECOY_LURE of `point`, or null. `ai.gd` asks it when it
## looks for a target. Allocation-free.
func lure(point: Vector2) -> Node2D:
	var best: Node2D = null
	var best_sq: float = DECOY_LURE * DECOY_LURE
	for row in POOL_SIZE:
		if _kind[row] != DECOY:
			continue
		var d: float = point.distance_squared_to(_position[row])
		if d <= best_sq:
			best_sq = d
			best = _decoys[row]
	return best


## End every entity quietly (no `entity_ended`).
func clear() -> void:
	for row in POOL_SIZE:
		if _kind[row] != &"":
			_end(row, false)
	queue_redraw()


func _on_spawn_requested(player: int, kind: StringName, at: Vector2, seconds: float, tag: int, caster: int = CASTER_WIZARD) -> void:
	if player < 0 or player >= PLAYER_SLOTS or not at.is_finite() or is_nan(seconds):
		return
	if kind != DECOY and kind != FAMILIAR:
		push_warning("Entities: no entity of kind %s." % kind)
		return
	if count(kind, player) >= PER_PLAYER:
		_end(_oldest(kind, player), true)
	var row: int = _kind.find(&"")
	if row < 0:
		return
	_kind[row] = kind
	_player[row] = player
	_tag[row] = tag
	_left[row] = seconds if seconds > 0.0 else INF
	_hits[row] = DECOY_HITS
	_cast_left[row] = FAMILIAR_FIRST
	_angle[row] = 0.0
	_position[row] = at
	_born[row] = _spawned
	_spawned += 1
	_live += 1
	var wizard: Node2D = _wizard_of(player) if caster == CASTER_WIZARD or kind == DECOY else null
	_centre_at[row] = Vector2.INF
	_centre_slot[row] = -1
	if kind == FAMILIAR and caster != CASTER_WIZARD:
		# A trigger made it: it circles the shot that fired the trigger, or the point.
		_centre_at[row] = at
		if caster >= 0 and projectiles != null and projectiles.is_alive(caster):
			_centre_slot[row] = caster
			_centre_seq[row] = projectiles.get_seq_of(caster)
			_centre_at[row] = projectiles.get_position_of(caster)
	if kind == DECOY:
		var decoy: Decoy = _decoys[row]
		decoy.position = at
		decoy.copy_look(wizard)
		decoy.active = true
		decoy.visible = true
		if projectiles != null:
			projectiles.add_target(decoy, DECOY_RADIUS, ProjectileManagerScript.LAYER_PLAYER, player, DECOY_OFFSET)
	else:
		_caster[row] = wizard
		if wizard != null:
			# Start on the side of the wizard where the card put it.
			var from: Vector2 = at - _centre_of(wizard)
			_angle[row] = from.angle() if from != Vector2.ZERO else 0.0
			_position[row] = _orbit_point(row)
		elif _centre_at[row].is_finite():
			_position[row] = _orbit_point(row)
	queue_redraw()


func _on_end_requested(player: int, tag: int) -> void:
	for row in POOL_SIZE:
		if _kind[row] != &"" and _player[row] == player and _tag[row] == tag:
			_end(row, true)


## Only an enemy's shot (NO_PLAYER) wears a decoy down.
func _on_projectile_hit(player: int, target: Node, _position_hit: Vector2, _tag_hit: int) -> void:
	if player != EventsScript.NO_PLAYER or not target is Decoy:
		return
	var row: int = _decoys.find(target as Decoy)
	if row < 0 or _kind[row] != DECOY:
		return
	_hits[row] -= 1
	if _hits[row] <= 0:
		_end(row, true)


func _on_room_entered(_room_id: StringName) -> void:
	clear()


func _on_run_ended(_victory: bool) -> void:
	clear()


func _step_familiar(row: int, delta: float) -> void:
	_angle[row] = wrapf(_angle[row] + FAMILIAR_TURN * delta, -PI, PI)
	if not is_instance_valid(_caster[row]):
		_caster[row] = null
	_position[row] = _orbit_point(row)
	_cast_left[row] -= delta
	if _cast_left[row] > 0.0:
		return
	_cast_left[row] = FAMILIAR_INTERVAL
	if projectiles == null or events == null:
		return
	var enemy: Node2D = projectiles.nearest_target(_position[row], FAMILIAR_RANGE, ProjectileManagerScript.LAYER_ENEMY)
	if enemy == null:
		return
	var direction: Vector2 = _position[row].direction_to(projectiles.nearest_point)
	if direction == Vector2.ZERO:
		direction = Vector2.RIGHT
	events.familiar_cast_requested.emit(_player[row], _position[row], direction, _tag[row])


## Where familiar `row` is now: on its circle round the wizard, the shot or the point it circles,
## or where it was without any.
func _orbit_point(row: int) -> Vector2:
	var wizard: Node2D = _caster[row]
	if wizard != null:
		return _centre_of(wizard) + Vector2.from_angle(_angle[row]) * FAMILIAR_ORBIT
	var shot: int = _centre_slot[row]
	if shot >= 0:
		if projectiles != null and projectiles.is_alive(shot) and projectiles.get_seq_of(shot) == _centre_seq[row]:
			_centre_at[row] = projectiles.get_position_of(shot)
		else:
			_centre_slot[row] = -1
	if _centre_at[row].is_finite():
		return _centre_at[row] + Vector2.from_angle(_angle[row]) * FAMILIAR_ORBIT
	return _position[row]


func _end(row: int, announce: bool) -> void:
	if row < 0 or _kind[row] == &"":
		return
	var kind: StringName = _kind[row]
	_kind[row] = &""
	_caster[row] = null
	_live -= 1
	var decoy: Decoy = _decoys[row]
	if decoy.active:
		decoy.active = false
		decoy.visible = false
		if projectiles != null:
			projectiles.remove_target(decoy)
	if announce and events != null:
		events.entity_ended.emit(_player[row], kind, _position[row], _tag[row])
	queue_redraw()


func _oldest(kind: StringName, player: int) -> int:
	var best: int = -1
	for row in POOL_SIZE:
		if _kind[row] == kind and _player[row] == player and (best < 0 or _born[row] < _born[best]):
			best = row
	return best


func _rows_by_age() -> Array[int]:
	var rows: Array[int] = []
	for row in POOL_SIZE:
		if _kind[row] != &"":
			rows.append(row)
	rows.sort_custom(func(a: int, b: int) -> bool: return _born[a] < _born[b])
	return rows


## The wizard of `player` (in the `players` group, by its `index`), or null. Only at spawn.
func _wizard_of(player: int) -> Node2D:
	if not is_inside_tree():
		return null
	for node: Node in get_tree().get_nodes_in_group(PLAYERS_GROUP):
		if node is Node2D and node.get("index") == player:
			return node as Node2D
	return null


func _centre_of(wizard: Node2D) -> Vector2:
	return (wizard.global_position if wizard.is_inside_tree() else wizard.position) + FAMILIAR_CENTRE


func _draw() -> void:
	for row in POOL_SIZE:
		if _kind[row] != FAMILIAR:
			continue
		var at: Vector2 = _position[row].round()
		draw_circle(at, FAMILIAR_SIZE + 1.0, OUTLINE_COLOR)
		draw_circle(at, FAMILIAR_SIZE, ProjectileManagerScript.PLAYER_COLORS[_player[row]])
		draw_rect(Rect2(at - Vector2.ONE * 0.5, Vector2.ONE), CORE_COLOR)
