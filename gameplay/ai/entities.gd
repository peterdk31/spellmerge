extends Node2D
## Entities (staffs B5): the decoys and familiars that cards make. One autoload ("Entities")
## keeps them in a fixed pool, so a card spawning one allocates nothing.
##
##     Events.entity_spawn_requested.emit(caster, &"decoy", at, 6.0, tag, -1)     # core/spells sends it
##
## Every entity belongs to the actor that cast it, its `owner` (the event's `caster`, an actor
## id; actors G3b). Whether that actor is seated (`Actors.seat_of`: a human drives it) or not
## sorts it into the pool's two parts; its team says whom a familiar casts at; its ramp colours
## both; its body (`Actors.node_of`) is what a decoy copies and a familiar circles.
##
## A **decoy** is a still copy of its caster's body (the `Sprite` and its `Hat`, copied at
## spawn, a little see-through). Every shot but its owner's hits it and wears it down (G3c: it is
## a `core/projectiles` target owned by its owner, so the owner's own shots pass it as they pass
## its body: on LAYER_PLAYER for a seated owner, LAYER_ENEMY for another), and enemies within
## DECOY_LURE of a seated owner's decoy chase it before any wizard (`lure`, asked by `ai.gd`). It
## ends after DECOY_HITS hits or when its time runs out; where it ended is its end point. A decoy
## whose card has a shield or deflect guards itself (rules R4g): every step Spells turns away
## (`Spells.guard_decoy`) the other teams' shots within DECOY_GUARD of its body, deflecting them
## or stopping them while its shield charges last, as a swing's guard does; each is a block.
##
## A **familiar** is a small orb circling its caster (FAMILIAR_ORBIT px): the wizard, or for a
## familiar a trigger made the shot that fired it (a `core/projectiles` slot, followed while it
## flies) or the point it was made at, starting on the side where the card put it. It casts
## nothing itself: core/spells fires what its triggers give it (rules R4 F3), from the orb: every
## step Entities tells Spells where it is (`Spells.familiar_at`, by the key Spells gave it, rules
## R4 F8). With its wizard gone it stays where it was; with its shot gone it circles where the
## shot was last.
##
## An **enemy's** decoy and familiar (staffs F8d: an enemy that casts a staff with those cards)
## are the same in the enemy ramp: the decoy copies the enemy's `Sprite` and the familiar circles
## the enemy. Enemies never chase an unseated owner's decoy (`lure`). The AI names its node for
## its actor (`set_enemy`) and, when it dies or leaves, ends its entities where they are
## (`enemy_gone`), so not even a `hold` one outlives it.
##
## Each seated owner has up to PER_PLAYER of each kind, and each other owner PER_ENEMY; one more
## ends their oldest of that kind. The unseated owners share ENEMY_ROWS rows of their own, so a
## crowd never takes a seat's; with those full, a new one ends the oldest of their part. An
## entity whose `seconds` is INF, or 0 or less, lasts until `entity_end_requested` with its tag
## (a `hold` switched off). Every end (time, hits, the cap, a request) sends `entity_ended` once,
## for core/spells (a decoy's end point). A new room or the end of the run clears them all
## quietly: their end points are gone with the room.
##
## Swap (`target_move_requested`) is heard by each enemy itself (`ai.gd`), not here.
##
## Nothing here allocates per frame; drawing is the pooled decoy nodes and one batch of the
## familiars, drawn by the shots' shader as orbit shots (the glow look, 2026-10-27): a small
## white-hot core in its owner's ramp and a tail that bends round its circle. All timing runs in step(delta), so tests drive it with fixed deltas.

const EventsScript := preload("res://core/events/events.gd")
const ProjectileManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const ActorsScript := preload("res://core/actors/actors.gd")
const SpellsScript := preload("res://core/spells/spells.gd")

const DECOY: StringName = &"decoy"
const FAMILIAR: StringName = &"familiar"
const PLAYER_SLOTS: int = 4
## `entity_spawn_requested`'s anchor when it is the caster's body, and when it is the point it was made at.
const CASTER_WIZARD: int = -1
const CASTER_POINT: int = -2
## Live entities of one kind a seated owner, or another owner, may have.
const PER_PLAYER: int = 4
const PER_ENEMY: int = 2
## Rows in the pool: every kind for every seat first, then the rows all unseated owners share.
const PLAYER_ROWS: int = PLAYER_SLOTS * PER_PLAYER * 2
const ENEMY_ROWS: int = 32
const POOL_SIZE: int = PLAYER_ROWS + ENEMY_ROWS
## Every owner there is: the actor ids.
const ACTORS: int = ActorsScript.ACTORS

## Hits a decoy takes before it breaks.
const DECOY_HITS: int = 3
## The decoy's hit circle and where it sits from the feet: the wizard's own (Combat's numbers
## for a wizard, see flow.gd).
const DECOY_RADIUS: float = 8.0
const DECOY_OFFSET: Vector2 = Vector2(0.0, -12.0)
## How far from its body's centre a guarding decoy turns shots away: twice its hit circle, so a
## shot is met a step before it would hit.
const DECOY_GUARD: float = DECOY_RADIUS * 2.0
## An enemy this close to a decoy chases the decoy rather than any wizard.
const DECOY_LURE: float = 240.0
## How far the copy has fallen apart (`shot_sprite.gdshader`'s dissolve: its pixels in its player's
## colour, part of them gone, with a glow), so it never reads as a second wizard; never
## see-through (the glow look, 2026-10-27).
const DECOY_DISSOLVE: float = 0.3
const DECOY_GLOW: float = 0.6

## The familiar circles this far from the wizard's body, this fast (radians a second).
const FAMILIAR_ORBIT: float = 20.0
const FAMILIAR_TURN: float = 2.5
const FAMILIAR_CENTRE: Vector2 = Vector2(0.0, -14.0)
## The orb: radius in pixels, outline and core.
## A familiar is drawn as an orbit shot of this hit radius (its zoom, see `look_zoom`).
const FAMILIAR_SIZE: float = 3.0
## The shot shaders (core/README.md, "The shot shaders"): a decoy's copy is a sprite in the shots'
## style, a familiar an orbit shot drawn whole with its tail bent round its circle.
const SPRITE_SHADER: Shader = preload("res://core/projectiles/shot_sprite.gdshader")
const ORBIT_SHADER: Shader = preload("res://core/projectiles/shot_orbit.gdshader")
## A creature's telegraph (`creature_look.gd`), compiled before the first room (shader_warmup.gd).
const TELEGRAPH_SHADER: Shader = preload("res://gameplay/ai/telegraph.gdshader")
const ShaderWarmupScript := preload("res://core/projectiles/shader_warmup.gd")
const STRIDE: int = 16

## Above the room and the wizards, below the shots (`ProjectileManagerScript.DRAW_Z`): the
## autoload is drawn before the current scene, as the shots are.
const DRAW_Z: int = 40

## The event bus and the projectile manager. Only tests set these, before adding the node;
## otherwise the "Events" and "Projectiles" autoloads.
var events: EventsScript = null
var projectiles: ProjectileManagerScript = null
## Spells, for a decoy's guard and where a familiar is. Only tests set it; otherwise the "Spells" autoload.
var spells: SpellsScript = null
## The actor table. Only tests set it; otherwise the projectile manager's, else the "Actors"
## autoload.
var actors: ActorsScript = null

## Per row. `_kind` is &"" for a free row. `_owner` is the actor that cast it (the events'
## `caster`), `_ramp` its ramp at spawn (the familiar's colours).
var _kind: Array[StringName] = []
var _owner: PackedInt32Array = PackedInt32Array()
var _ramp: PackedInt32Array = PackedInt32Array()
var _tag: PackedInt32Array = PackedInt32Array()
var _left: PackedFloat32Array = PackedFloat32Array()
var _hits: PackedInt32Array = PackedInt32Array()
## A decoy's shield charges left, and 1 when it deflects (its guard, rules R4g).
var _shield: PackedInt32Array = PackedInt32Array()
var _deflect: PackedByteArray = PackedByteArray()
var _angle: PackedFloat32Array = PackedFloat32Array()
var _position: PackedVector2Array = PackedVector2Array()
## Spawn order, to find an owner's oldest.
var _born: PackedInt64Array = PackedInt64Array()
## A familiar's key from Spells (`Spells.entity_key`, 0 for none): where it is goes back by it.
var _key: PackedInt64Array = PackedInt64Array()
## The familiar's wizard or enemy, or null.
var _caster: Array[Node2D] = []
## The enemy of each actor id (`set_enemy`), or null.
var _enemies: Array[Node2D] = []
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
		sprite.material = _material()
		add_child(sprite)
		hat = Sprite2D.new()
		hat.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		hat.material = _material()
		sprite.add_child(hat)
		visible = false

	func _material() -> ShaderMaterial:
		var material := ShaderMaterial.new()
		material.shader = SPRITE_SHADER
		material.set_shader_parameter(&"core_override", Color.WHITE)
		material.set_shader_parameter(&"dissolve", DECOY_DISSOLVE)
		material.set_shader_parameter(&"sprite_glow", DECOY_GLOW)
		return material

	## Turn the copy to `colour` (its player's).
	func tint(colour: Color) -> void:
		(sprite.material as ShaderMaterial).set_shader_parameter(&"dissolve_color", colour)
		(hat.material as ShaderMaterial).set_shader_parameter(&"dissolve_color", colour)

	func is_downed() -> bool:
		return not active

	## Look like `wizard` does now (its `Sprite`, and a `Sprite/Hat` if it has one); plain when it
	## has none.
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


## The familiars' batch and its buffer, and the seconds its shader animates from.
var _familiar_node: MultiMeshInstance2D = null
var _familiar_buffer: PackedFloat32Array = PackedFloat32Array()
var _clock: float = 0.0


func _init() -> void:
	z_index = DRAW_Z
	_familiar_node = MultiMeshInstance2D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_2D
	multimesh.use_colors = true
	multimesh.use_custom_data = true
	multimesh.mesh = quad
	multimesh.instance_count = POOL_SIZE
	multimesh.visible_instance_count = 0
	multimesh.custom_aabb = AABB(Vector3(-100000.0, -100000.0, -1.0), Vector3(200000.0, 200000.0, 2.0))
	_familiar_node.multimesh = multimesh
	var material := ShaderMaterial.new()
	material.shader = ORBIT_SHADER
	_familiar_node.material = material
	_familiar_node.name = "Familiars"
	add_child(_familiar_node)
	_familiar_buffer.resize(POOL_SIZE * STRIDE)
	for row in POOL_SIZE:
		_kind.append(&"")
		_caster.append(null)
		_centre_at.append(Vector2.INF)
		_centre_slot.append(-1)
		_centre_seq.append(0)
		var decoy := Decoy.new()
		decoy.name = "Decoy%d" % row
		_decoys.append(decoy)
		add_child(decoy)
	_enemies.resize(ACTORS)
	_owner.resize(POOL_SIZE)
	_ramp.resize(POOL_SIZE)
	_tag.resize(POOL_SIZE)
	_left.resize(POOL_SIZE)
	_hits.resize(POOL_SIZE)
	_shield.resize(POOL_SIZE)
	_deflect.resize(POOL_SIZE)
	_key.resize(POOL_SIZE)
	_angle.resize(POOL_SIZE)
	_position.resize(POOL_SIZE)
	_born.resize(POOL_SIZE)


func _ready() -> void:
	ShaderWarmupScript.want(TELEGRAPH_SHADER, ShaderWarmupScript.RECT)
	if events == null:
		events = get_node_or_null("/root/Events") as EventsScript
	if projectiles == null:
		projectiles = get_node_or_null("/root/Projectiles") as ProjectileManagerScript
	if spells == null:
		spells = get_node_or_null("/root/Spells") as SpellsScript
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


## Move time on: lifetimes and familiar orbits.
func step(delta: float) -> void:
	_clock += delta
	if _live == 0:
		_write_familiars()
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
			if _key[row] != 0 and spells != null:
				spells.familiar_at(_key[row], _position[row])
		elif (_shield[row] > 0 or _deflect[row] != 0) and spells != null:
			_shield[row] = spells.guard_decoy(_owner[row], _tag[row], _position[row] + DECOY_OFFSET, DECOY_GUARD, _shield[row])
	queue_redraw()
	_write_familiars()


## How many entities are live, of `kind` (all kinds when empty) and the owner actor `caster`
## (all when -1).
func count(kind: StringName = &"", caster: int = -1) -> int:
	var found: int = 0
	for row in POOL_SIZE:
		if _kind[row] != &"" and (kind == &"" or _kind[row] == kind) and (caster < 0 or _owner[row] == caster):
			found += 1
	return found


## Where the live entities of the owner actor `caster` with `tag` are, the oldest first (tests and
## the sheets).
func positions_of(caster: int, tag: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	for row in _rows_by_age():
		if _owner[row] == caster and _tag[row] == tag:
			out.append(_position[row])
	return out


## How many entities of `kind` the owner actor `owner` has.
func count_owned(kind: StringName, owner: int) -> int:
	var found: int = 0
	for row in POOL_SIZE:
		if _kind[row] == kind and _owner[row] == owner:
			found += 1
	return found


## The enemy of the actor `caster` (`ai.gd`, when it opens its actor): its decoys copy it and its
## familiars circle it.
func set_enemy(caster: int, enemy: Node2D) -> void:
	if caster >= 0 and caster < ACTORS:
		_enemies[caster] = enemy


## The enemy of the actor `caster` is gone (`ai.gd`, as it closes its actor): its entities end
## where they are, each with `entity_ended`, so their `on expire` and blast still happen.
func enemy_gone(caster: int) -> void:
	set_enemy(caster, null)
	for row in POOL_SIZE:
		if _kind[row] != &"" and _owner[row] == caster:
			_end(row, true)


## The nearest live decoy of a seated owner within DECOY_LURE of `point`, or null (never an
## enemy's).
## `ai.gd` asks it when it looks for a target. Allocation-free.
func lure(point: Vector2) -> Node2D:
	var best: Node2D = null
	var best_sq: float = DECOY_LURE * DECOY_LURE
	for row in PLAYER_ROWS:
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


func _on_spawn_requested(caster: int, kind: StringName, at: Vector2, seconds: float, tag: int, anchor: int = CASTER_WIZARD) -> void:
	var owner: int = _owner_of(caster, tag)
	if owner < 0 or not at.is_finite() or is_nan(seconds):
		return
	if kind != DECOY and kind != FAMILIAR:
		push_warning("Entities: no entity of kind %s." % kind)
		return
	# The unseated owners' part of the pool (no seat drives the owner).
	var enemy: bool = not _seated(owner)
	if count_owned(kind, owner) >= (PER_ENEMY if enemy else PER_PLAYER):
		_end(_oldest(kind, owner), true)
	var row: int = _free_row(enemy)
	if row < 0:
		# Only the enemies' rows fill up (the players' fit every kind of every player).
		_end(_oldest(&"", owner), true)
		row = _free_row(enemy)
		if row < 0:
			return
	_kind[row] = kind
	_owner[row] = owner
	_ramp[row] = _ramp_of(owner)
	_tag[row] = tag
	_left[row] = seconds if seconds > 0.0 else INF
	_hits[row] = DECOY_HITS
	_shield[row] = spells.decoy_shield(tag) if kind == DECOY and spells != null else 0
	_deflect[row] = 1 if kind == DECOY and spells != null and spells.decoy_deflects(tag) else 0
	_angle[row] = 0.0
	_position[row] = at
	_key[row] = spells.entity_key if spells != null else 0
	_born[row] = _spawned
	_spawned += 1
	_live += 1
	var wizard: Node2D = _body_of(owner) if anchor == CASTER_WIZARD or kind == DECOY else null
	_centre_at[row] = Vector2.INF
	_centre_slot[row] = -1
	if kind == FAMILIAR and anchor != CASTER_WIZARD:
		# A trigger made it: it circles the shot that fired the trigger, or the point.
		_centre_at[row] = at
		if anchor >= 0 and projectiles != null and projectiles.is_alive(anchor):
			_centre_slot[row] = anchor
			_centre_seq[row] = projectiles.get_seq_of(anchor)
			_centre_at[row] = projectiles.get_position_of(anchor)
	if kind == DECOY:
		var decoy: Decoy = _decoys[row]
		decoy.position = at
		decoy.copy_look(wizard)
		var colour: Color = ProjectileManagerScript.ramp_color(_ramp[row])
		decoy.tint(colour.lerp(Color.WHITE, 0.4))
		decoy.active = true
		decoy.visible = true
		if projectiles != null:
			var layer: int = ProjectileManagerScript.LAYER_ENEMY if enemy else ProjectileManagerScript.LAYER_PLAYER
			projectiles.add_target(decoy, DECOY_RADIUS, layer, owner, DECOY_OFFSET)
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


func _on_end_requested(caster: int, tag: int) -> void:
	for row in POOL_SIZE:
		if _kind[row] != &"" and _owner[row] == caster and _tag[row] == tag:
			_end(row, true)


## Every hit wears a decoy down, whoever cast it (G3c); its own caster's shots never reach it
## (`core/projectiles` skips the targets a caster owns).
func _on_projectile_hit(_caster: int, target: Node, _position_hit: Vector2, _tag_hit: int) -> void:
	if not target is Decoy:
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
		events.entity_ended.emit(_owner[row], kind, _position[row], _tag[row])
	queue_redraw()


## The oldest entity of `kind` that `owner` has; with `kind` empty, the oldest in `owner`'s part
## of the pool (the seated owners' or the others'), whoever has it.
func _oldest(kind: StringName, owner: int) -> int:
	var best: int = -1
	var enemy: bool = not _seated(owner)
	for row in range(PLAYER_ROWS if enemy else 0, POOL_SIZE if enemy else PLAYER_ROWS):
		if _kind[row] == &"" or (kind != &"" and (_kind[row] != kind or _owner[row] != owner)):
			continue
		if best < 0 or _born[row] < _born[best]:
			best = row
	return best


## A free row in the players' part of the pool or the enemies', or -1.
func _free_row(enemy: bool) -> int:
	for row in range(PLAYER_ROWS if enemy else 0, POOL_SIZE if enemy else PLAYER_ROWS):
		if _kind[row] == &"":
			return row
	return -1


## The owner an `entity_spawn_requested` is for: its caster, an actor id; -1 for no actor, or a
## spell tag that names another caster.
func _owner_of(caster: int, tag: int) -> int:
	if caster < 0 or caster >= ACTORS:
		return -1
	if SpellTag.is_spell_tag(tag) and SpellTag.caster_of(tag) != caster:
		return -1
	return caster


## The body of the actor `owner` (an enemy named by `set_enemy`, else the node the actor table
## knows), or null. Only at spawn.
func _body_of(owner: int) -> Node2D:
	var enemy: Node2D = _enemies[owner]
	if is_instance_valid(enemy):
		return enemy
	var table: ActorsScript = _actor_table()
	return table.node_of(owner) as Node2D if table != null else null


func _rows_by_age() -> Array[int]:
	var rows: Array[int] = []
	for row in POOL_SIZE:
		if _kind[row] != &"":
			rows.append(row)
	rows.sort_custom(func(a: int, b: int) -> bool: return _born[a] < _born[b])
	return rows


## The actor table: `actors`, else the projectile manager's, else the "Actors" autoload.
func _actor_table() -> ActorsScript:
	if actors != null:
		return actors if is_instance_valid(actors) else null
	if projectiles != null and is_instance_valid(projectiles):
		return projectiles.actor_table()
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(^"Actors") as ActorsScript if tree != null and tree.root != null else null


## True while a seat drives the actor `owner` (its entities use the seats' part of the pool).
func _seated(owner: int) -> bool:
	var table: ActorsScript = _actor_table()
	return table != null and table.seat_of(owner) != ActorsScript.NONE


func _team_of(actor: int) -> int:
	var table: ActorsScript = _actor_table()
	return table.team_of(actor) if table != null else ActorsScript.NONE


func _ramp_of(actor: int) -> int:
	var table: ActorsScript = _actor_table()
	return table.ramp_of(actor) if table != null else ActorsScript.NONE


func _centre_of(wizard: Node2D) -> Vector2:
	return (wizard.global_position if wizard.is_inside_tree() else wizard.position) + FAMILIAR_CENTRE


## Write the live familiars into their batch: orbit shots flying along their circle (the bend of
## FAMILIAR_ORBIT), in their owner's ramp.
func _write_familiars() -> void:
	(_familiar_node.material as ShaderMaterial).set_shader_parameter(&"sim_time", _clock)
	var out: int = 0
	var size: float = ProjectileManagerScript.look_size(FAMILIAR_SIZE)
	var length: float = ProjectileManagerScript.look_length(FAMILIAR_SIZE)
	var code: float = ProjectileManagerScript.bend_code(1.0 / FAMILIAR_ORBIT)
	var zoom: int = ProjectileManagerScript.look_zoom(FAMILIAR_SIZE)
	for row in POOL_SIZE:
		if _kind[row] != FAMILIAR:
			continue
		# The way it flies: along its circle as the angle grows.
		var dir: Vector2 = Vector2(-sin(_angle[row]), cos(_angle[row]))
		var centre: Vector2 = _position[row] - dir * (length - size) * 0.5
		var i: int = out * STRIDE
		_familiar_buffer[i] = dir.x * length
		_familiar_buffer[i + 1] = dir.y * size
		_familiar_buffer[i + 2] = 0.0
		_familiar_buffer[i + 3] = centre.x
		_familiar_buffer[i + 4] = dir.y * length
		_familiar_buffer[i + 5] = -dir.x * size
		_familiar_buffer[i + 6] = 0.0
		_familiar_buffer[i + 7] = centre.y
		var data: Color = ProjectileManagerScript.look_color(_ramp[row], zoom, 0)
		_familiar_buffer[i + 8] = data.r
		_familiar_buffer[i + 9] = data.g
		_familiar_buffer[i + 10] = data.b
		_familiar_buffer[i + 11] = data.a
		_familiar_buffer[i + 12] = 1.0
		_familiar_buffer[i + 13] = 1.0
		_familiar_buffer[i + 14] = 1.0
		_familiar_buffer[i + 15] = 1.0 - (float(ProjectileManagerScript.KIND_ORBIT) + code) / ProjectileManagerScript.KIND_STEPS
		out += 1
	if out > 0:
		_familiar_node.multimesh.buffer = _familiar_buffer
	_familiar_node.multimesh.visible_instance_count = out


## Familiars drawn right now (for tests).
func drawn_familiars() -> int:
	return _familiar_node.multimesh.visible_instance_count

