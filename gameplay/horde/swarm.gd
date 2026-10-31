class_name Swarm
extends RefCounted
## The swarm (docs/milestones/horde-swarm.md, part S1): the horde's touch-only enemies as rows of
## packed arrays and one shared step, instead of a full actor each. Owned and stepped by the
## director (`horde.gd`), which spawns a kind with a `SwarmKind` here and every other enemy as a
## full actor.
##
## **A light node per swarmer.** Each swarmer keeps one bare `Node2D` (no children, no script,
## never drawn) under the director's `Horde` node, registered with Combat as a plain body
## (`register_actor`: its kind's health, hurt circle and touch damage; Combat opens its actor id on
## the enemies' team). So every rule finds it as it finds any actor: shots and strikes hit its
## hurt circle, statuses, reactions, shock jumps, static, hex, pulls and barriers are Combat's
## rows, its touch hurts the wizards, and its death is Combat's (`enemy_died`, then the node is
## freed). Nothing else exists per swarmer.
##
## **The rows** (the contract with the look, part S2: it reads them and never writes them), rows 0
## to `count - 1`, swap-removed on death (every array kept in step): `nodes` (the bare Node2D),
## `kinds` (index into `kinds_list`), `positions` (the feet, in the `Horde` node's space, written to
## each node's `position` at the end of a step), `velocities` (pixels per second this step, the
## push included, as a full actor's `velocity`), `aims` (the look direction, unit length),
## `seeds` (per row, for idle habits), `hurt_left` (seconds of the hurt pose left, set to
## `CreatureLook.HURT_TIME` on every `damage_dealt` naming the swarmer, as a full enemy's look sets
## it on `Actor.damaged`), `down` (never set for a swarmer today) and `moved` (how many steps the
## swarm has run: the look reads the rows after the step it counts), `ran` (the seconds each row
## really stepped this step: 0 while a local stop holds it). Also `actor_ids`, each row's Combat and
## actor-table id (promotion, part S3). The look (`look`) is told of each step, hit and removal.
##
## **The step** (`step(delta)`, one for all rows, in physics steps):
## - **Chase** as `AIController` chases: the nearest standing actor of another team, a decoy in
##   its lure range first (`Entities.lure`), a teammate that hurt it for `AIController.GRUDGE_TIME`
##   (its grudge). The actors of other teams are read from the actor table a few times a second
##   (`_read_candidates`: the few that Combat has registered), not from the projectile manager's
##   grid, which a look without a range would walk whole (every swarmer is a target in it).
##   Each row looks every `AIController.RETARGET_TIME` seconds, staggered by its seed, at once
##   when its target is lost, downed or dying (checked once a step per distinct target, not per
##   row), and only on the timer while it has none.
## - **Pace and push:** the walk is the kind's speed times `Combat.pace` (chill slows, freeze
##   stops), plus Combat's push (`consume_knockback`: knockback, pulls). A local stop
##   (`Actors.hold`) holds a swarmer as it holds an actor. A swap card's
##   `target_move_requested` puts a swarmer where it says.
## - **Spacing:** swarmers do not stack. A spatial hash (cells of at least twice the largest body
##   radius) finds the pairs that overlap; each pair is moved apart by `SPACING_SHARE` of the
##   overlap a step (half the rows own their pairs each step, at twice the share), split by how free each one is to move (a frozen or held swarmer is not moved,
##   the other takes it all). No pair is looked at twice; nothing is O(n²).
## - **Walls:** the floor the director derived (`start`'s `arena`: the room's walls, a body's
##   radius in) holds every swarmer, and the world's other wall bodies (static bodies on layer 1
##   inside the floor) are a coarse grid of `WALL_CELL` cells, grown by `WALL_PAD`: a move into one
##   slides along it (x alone, then y alone) or stays.
## - Then each node's `position` is written.
##
## **Promotion** (part S3, docs/milestones/horde-swarm.md, "Where a rule needs a full actor"): a
## rule that needs the actor kit promotes the swarmer to the full actor of its kind; today that is
## only `possess_requested` naming a swarmer's actor id (every other request a card makes of a body
## is heard here or in Combat: hits, statuses, pushes, pulls, barriers, swaps, local stops, decoys).
## A request is kept and the swarmer promoted at the next moment no hit is being dealt: the start of
## Combat's next step (`Combat.stepping`, before it ticks statuses and checks touches), or of the
## swarm's own step if that comes first. So whatever the hit that asked still does (Combat's damage,
## its payload, its chain) is done to the swarmer it hit, and the full actor stands before anything
## touches it (a hit from a shot is promoted in the same physics frame). `promote(row)`: the kind's scene (`SwarmKind.scene`,
## with its `EnemyBase` as `data` and the swarm's services) at the row's place, its aim and velocity,
## under the same parent (so the director counts it as before: alive, its kill, its gem), with:
## - **the same actor id** (`Actor.take_id`): the id Combat opened for the swarmer is the actor's,
##   so whatever keeps the id (a spell's caster, a hold, the actor table's team and node) keeps it;
## - **the same Combat row:** `Combat.row_state` before, `carry_row_state` after the actor
##   registered (health, every status with its time, strength and stacks, barrier, push, armed slam,
##   contact and reaction waits, who hurt it last);
## - **the same body for whatever keeps a node:** `body_replaced(id, old, new)` is sent before the actor
##   is added (Spells, the projectile manager and Feel keep the new node instead: homing targets,
##   hit memories, stuck shots, payload skips, chain and sweep memories, status looks), and the
##   swarm's own target slots (a grudge on it) follow it too;
## - its grudge (`AIController.carry_grudge`).
## The row is dropped (the look told), the bare node freed, and the actor takes the request
## (`Actor.take_possession`). A promoted swarmer stays a full actor.
##
## Nothing is allocated in a step: the arrays grow only when a spawn needs room (doubling).

const EventsScript := preload("res://core/events/events.gd")
const ProjectileManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const ActorsScript := preload("res://core/actors/actors.gd")
const CombatScript := preload("res://gameplay/combat/combat.gd")
const EntitiesScript := preload("res://gameplay/ai/entities.gd")
const SpellsScript := preload("res://core/spells/spells.gd")

## The kinds the director runs in the swarm: an enemy whose id one of these names.
const KINDS: Array[SwarmKind] = [
	preload("res://gameplay/horde/swarm_kinds/crypt_mite.tres"),
	preload("res://gameplay/horde/swarm_kinds/bone_husk.tres"),
]

## The AI's numbers, read from it so a change there changes the swarm too.
const RETARGET_TIME: float = AIController.RETARGET_TIME
const GRUDGE_TIME: float = AIController.GRUDGE_TIME
const SIGHT: float = AIController.SIGHT
const CLOSE_ENOUGH: float = AIController.CLOSE_ENOUGH
## The look's hurt pose (`hurt_left`).
const HURT_TIME: float = CreatureLook.HURT_TIME
## A row's look timer before its first look (below anything a running timer reaches).
const FIRST_LOOK: float = -1.0
## Rows made room for at first; the arrays double when full.
const START_ROOM: int = 256
## The share of an overlap two swarmers are moved apart by per step (each pair is seen every other
## step, at twice this).
const SPACING_SHARE: float = 0.5
## The spatial hash's smallest cell (pixels); larger when a kind's body needs it.
const SPACING_CELL: float = 8.0
## The wall grid's cell (pixels), and how far a wall reaches out for a body's centre (about the
## largest swarmer's radius).
const WALL_CELL: float = 8.0
const WALL_PAD: float = 8.0
## Seconds between two readings of the actors a swarmer may chase, and the most kept.
const CANDIDATE_TIME: float = 0.1
const MAX_CANDIDATES: int = 64
## Distinct targets the rows chase at once (a target no row chases frees its place).
const TARGET_SLOTS: int = 64
## The wall layer of the world's static bodies.
const WALL_LAYER: int = 1

## The services. The director hands over its own; whatever is null is taken from the autoloads
## (`start`).
var events: EventsScript = null
var combat: CombatScript = null
var projectiles: ProjectileManagerScript = null
var actors: ActorsScript = null
var entities: EntitiesScript = null
var spells: SpellsScript = null

## The rows (see the class doc). Only the swarm writes them.
var nodes: Array[Node2D] = []
var kinds: PackedInt32Array = PackedInt32Array()
var kinds_list: Array[SwarmKind] = []
var positions: PackedVector2Array = PackedVector2Array()
var velocities: PackedVector2Array = PackedVector2Array()
var aims: PackedVector2Array = PackedVector2Array()
var seeds: PackedInt32Array = PackedInt32Array()
var hurt_left: PackedFloat32Array = PackedFloat32Array()
var down: PackedByteArray = PackedByteArray()
var actor_ids: PackedInt32Array = PackedInt32Array()
var moved: int = 0
var count: int = 0
## Per row: the seconds it really stepped this step (0 while a local stop holds it, the part
## after a stop that ends in the step), as doubles for the look.
var ran: PackedFloat64Array = PackedFloat64Array()
## The batched look (part S2), or null: told `step(delta)` each step after the velocities and aims
## are set and before the rows move, `on_hit(row)` on each hit of a swarmer, `on_row_removed(row)`
## right after a swap-remove (the last row moved into `row`) and `clear()` when the swarm empties.
var look: Node = null
## How many looks for a target the rows made (tests count them).
var lookup_count: int = 0
## How many swarmers were promoted to full actors (tests count them).
var promoted_count: int = 0
## The share of an overlap two swarmers are moved apart by per step (SPACING_SHARE; 0: they
## stack as full actors do, which tests comparing a swarmer with a full actor ask for).
var spacing: float = SPACING_SHARE

## The randomness of the seeds. Tests seed it.
var rng: RandomNumberGenerator = RandomNumberGenerator.new()

## The node the swarmers stand under, and the floor they stand on (its space).
var _parent: Node2D = null
var _arena: Rect2 = Rect2()
## Each row's node's instance id, and the row of each (by instance id).
var _node_ids: PackedInt64Array = PackedInt64Array()
var _row_by_node: Dictionary[int, int] = {}
## Per row, from its kind: walking speed and body radius.
var _speed: PackedFloat32Array = PackedFloat32Array()
var _radius: PackedFloat32Array = PackedFloat32Array()
## Per row: seconds to its next look, seconds of grudge left, the target slot it chases (-1 none).
var _retarget_left: PackedFloat32Array = PackedFloat32Array()
var _grudge_left: PackedFloat32Array = PackedFloat32Array()
var _target_slot: PackedInt32Array = PackedInt32Array()
## Per row, this step: how free it is to be moved by spacing (0 frozen or held, 1 free), its push
## from spacing, and the next row in its hash cell.
var _give: PackedFloat32Array = PackedFloat32Array()
var _push: PackedVector2Array = PackedVector2Array()
var _next: PackedInt32Array = PackedInt32Array()
## Per row, this step: its hash cell, and Combat's pace and push for it (`own_paces_and_pushes`).
var _cell_of: PackedInt32Array = PackedInt32Array()
var _paces: PackedFloat64Array = PackedFloat64Array()
var _pushes: PackedVector2Array = PackedVector2Array()
## The distinct targets: node, how many rows chase it, whether it can be chased this step and its
## feet (in the parent's space).
var _slot_nodes: Array[Node2D] = []
var _slot_refs: PackedInt32Array = PackedInt32Array()
var _slot_ok: PackedByteArray = PackedByteArray()
var _slot_at: PackedVector2Array = PackedVector2Array()
var _slot_used: int = 0
## The actors a swarmer may chase (`_read_candidates`): node, team, hurt circle offset.
var _cand_nodes: Array[Node2D] = []
var _cand_team: PackedInt32Array = PackedInt32Array()
var _cand_offset: PackedVector2Array = PackedVector2Array()
var _cand_count: int = 0
var _cand_left: float = 0.0
## The spatial hash over the floor.
var _cell: float = SPACING_CELL
var _grid_w: int = 1
var _grid_h: int = 1
var _cell_head: PackedInt32Array = PackedInt32Array()
## The wall grid over the floor (1: a wall), and whether it has any.
var _walls: PackedByteArray = PackedByteArray()
var _wall_w: int = 1
var _wall_h: int = 1
var _has_walls: bool = false
var _listening: bool = false
var _warned: bool = false
## The possessions asked for swarmers since the last step (promoted at the start of the next):
## caster, target actor id and seconds of each, `_asked` of them.
var _ask_caster: PackedInt32Array = PackedInt32Array()
var _ask_target: PackedInt32Array = PackedInt32Array()
var _ask_seconds: PackedFloat32Array = PackedFloat32Array()
var _asked: int = 0


func _init() -> void:
	rng.randomize()
	_grow(START_ROOM)
	_slot_nodes.resize(TARGET_SLOTS)
	_slot_refs.resize(TARGET_SLOTS)
	_slot_ok.resize(TARGET_SLOTS)
	_slot_at.resize(TARGET_SLOTS)
	_cand_nodes.resize(MAX_CANDIDATES)
	_cand_team.resize(MAX_CANDIDATES)
	_cand_offset.resize(MAX_CANDIDATES)


## The kind the swarm runs `data` as (prepared from it), or null when the enemy is not a swarmer.
static func kind_for(data: EnemyBase) -> SwarmKind:
	if data == null:
		return null
	for kind: SwarmKind in KINDS:
		if kind != null and kind.enemy_id == data.id:
			return kind if kind.prepare(data) else null
	return null


## Starts the swarm under `parent` (the director's `Horde` node) on the floor `arena` (in the
## parent's space), forgetting any rows it had. The world's wall bodies inside the floor (the
## parent's parent's static bodies on the wall layer) become the wall grid.
func start(parent: Node2D, arena: Rect2) -> void:
	stop()
	_find_services()
	_parent = parent
	_arena = arena
	_fit_grid()
	_read_walls(parent.get_parent() if parent != null else null)
	_listen(true)


## Forgets every row and stops listening. The nodes are left to whoever frees the parent.
func stop() -> void:
	_listen(false)
	for row in count:
		nodes[row] = null
	count = 0
	if look != null and is_instance_valid(look):
		look.call(&"clear")
	_row_by_node.clear()
	for slot in _slot_used:
		_slot_nodes[slot] = null
		_slot_refs[slot] = 0
	_slot_used = 0
	for c in _cand_count:
		_cand_nodes[c] = null
	_cand_count = 0
	_cand_left = 0.0
	_asked = 0
	_parent = null


## The row of the swarmer `node`, or -1.
func row_of(node: Object) -> int:
	if node == null or not is_instance_valid(node):
		return -1
	return _row_by_node.get(node.get_instance_id(), -1)


## A new swarmer of `kind` (prepared) at `at` (the parent's space): its node under the parent,
## registered with Combat. Returns its row, or -1 when it could not be made (no parent or Combat,
## an unprepared kind, the actor table full).
func spawn(kind: SwarmKind, at: Vector2) -> int:
	if _parent == null or not is_instance_valid(_parent) or kind == null or kind.enemy == null:
		return -1
	if combat == null or not is_instance_valid(combat):
		if not _warned:
			_warned = true
			push_warning("Swarm: Combat is missing, so no swarmer can be made.")
		return -1
	var kind_index: int = kinds_list.find(kind)
	if kind_index < 0:
		kind_index = kinds_list.size()
		kinds_list.append(kind)
		var cell: float = maxf(SPACING_CELL, kind.body_radius * 2.0)
		if cell > _cell:
			_cell = cell
			_fit_grid()
	if count == nodes.size():
		_grow(count * 2)
	var node := Node2D.new()
	node.position = at
	_parent.add_child(node)
	var id: int = combat.register_actor(node, kind.health, kind.hurt_radius, kind.contact_damage, kind.hurt_offset)
	if id == ActorsScript.NONE:
		_parent.remove_child(node)
		node.free()
		return -1
	var row: int = count
	count += 1
	nodes[row] = node
	_node_ids[row] = node.get_instance_id()
	_row_by_node[_node_ids[row]] = row
	kinds[row] = kind_index
	positions[row] = at
	velocities[row] = Vector2.ZERO
	ran[row] = 0.0
	aims[row] = Vector2.DOWN
	seeds[row] = rng.randi() & 0x7fffffff
	hurt_left[row] = 0.0
	down[row] = 0
	actor_ids[row] = id
	_speed[row] = kind.speed
	_radius[row] = kind.body_radius
	# The first look comes at once; the next after a share of RETARGET_TIME from its seed, so rows
	# spawned together do not all look in one step (as the AI staggers by its node).
	_retarget_left[row] = FIRST_LOOK
	_grudge_left[row] = 0.0
	_target_slot[row] = -1
	return row


## Moves every swarmer on by `delta` seconds (see the class doc).
func step(delta: float) -> void:
	if _parent == null or not is_instance_valid(_parent):
		return
	# Rows whose node went without `enemy_died` (backwards: a dropped row takes the last one's).
	var row: int = count - 1
	while row >= 0:
		if not is_instance_valid(nodes[row]):
			_drop(row)
		row -= 1
	_promote_asked()
	if count == 0:
		moved += 1
		return
	var origin: Vector2 = _parent.global_position if _parent.is_inside_tree() else _parent.position
	_read_candidates(delta)
	_read_targets(origin)
	# Every row's local stop, then its pace and push, each asked once for all rows (a call per row
	# each cost more than the rest of the row's step; S4). The rows do not touch each other's stops
	# or Combat rows, so asking first answers as asking row by row did.
	var held: bool = actors != null and actors.held_count > 0
	if held:
		actors.spend_holds(actor_ids, count, delta, ran)
	else:
		ran.fill(delta)
	combat.own_paces_and_pushes(nodes, actor_ids, count, ran, _paces, _pushes)
	var close_sq: float = CLOSE_ENOUGH * CLOSE_ENOUGH
	for i in count:
		if hurt_left[i] > 0.0:
			hurt_left[i] = maxf(hurt_left[i] - delta, 0.0)
		var walk: float = ran[i]
		if held and walk <= 0.0:
			velocities[i] = Vector2.ZERO
			_give[i] = 0.0
			continue
		var slot: int = _target_slot[i]
		var wait: float = _retarget_left[i] - walk
		if wait > 0.0 and _grudge_left[i] <= 0.0 and (slot < 0 or _slot_ok[slot] != 0):
			# The usual step (`_think`, written out): no look due.
			_retarget_left[i] = wait
		else:
			_think(i, nodes[i], actor_ids[i], walk, origin)
			slot = _target_slot[i]
		var pace: float = _paces[i]
		var push: Vector2 = _pushes[i]
		if walk <= 0.0:
			# A step of no time (never in play): asked here, as Combat leaves such rows alone.
			pace = combat.own_pace(nodes[i], actor_ids[i])
			push = combat.own_knockback(nodes[i], actor_ids[i], walk)
		var velocity: Vector2 = Vector2.ZERO
		if slot >= 0:
			var to_target: Vector2 = _slot_at[slot] - positions[i]
			var far_sq: float = to_target.length_squared()
			if far_sq > 0.0:
				var aim: Vector2 = to_target / sqrt(far_sq)
				aims[i] = aim
				if far_sq > close_sq:
					velocity = aim * (_speed[i] * pace)
		velocity += push
		velocities[i] = velocity
		_give[i] = 1.0 if pace > 0.0 else 0.0
	# The look steps once the velocities and aims are set, before the rows move.
	if look != null and is_instance_valid(look):
		look.call(&"step", delta)
	# The rows move as the spacing's hash is filled (`_space`), then the push, the floor and the
	# walls, and each node's `position`, in one pass (`_keep_in`).
	_space()
	_keep_in()
	moved += 1


# --- Targets ------------------------------------------------------------------------------------

## The row's look, on its timer, at once when its target was lost, and its grudge.
func _think(i: int, node: Node2D, id: int, delta: float, origin: Vector2) -> void:
	_retarget_left[i] -= delta
	var slot: int = _target_slot[i]
	if _grudge_left[i] > 0.0:
		_grudge_left[i] -= delta
		if _grudge_left[i] <= 0.0 or (slot >= 0 and _slot_ok[slot] == 0):
			# The grudge is over: back to its team's targets at once.
			_grudge_left[i] = 0.0
			_retarget_left[i] = 0.0
		else:
			return
	var lost: bool = slot >= 0 and _slot_ok[slot] == 0
	if _retarget_left[i] > 0.0 and not lost:
		return
	var first: bool = _retarget_left[i] <= FIRST_LOOK
	_retarget_left[i] = RETARGET_TIME * float(seeds[i] & 7) / 8.0 if first else RETARGET_TIME
	_set_target(i, _find_target(i, node, id, origin))


## A decoy in lure range, else the nearest standing actor of another team (as the AI looks).
func _find_target(i: int, node: Node2D, id: int, origin: Vector2) -> Node2D:
	lookup_count += 1
	var here: Vector2 = positions[i] + origin
	if entities != null and is_instance_valid(entities):
		var decoy: Node2D = entities.lure(here)
		if decoy != null:
			return decoy
	var team: int = actors.team_of(id) if actors != null else ActorsScript.TEAM_ENEMIES
	var from: Vector2 = here + kinds_list[kinds[i]].body_offset
	var best: Node2D = null
	var best_sq: float = SIGHT * SIGHT
	for c in _cand_count:
		if _cand_team[c] == team:
			continue
		var other: Node2D = _cand_nodes[c]
		if other == node or not _chaseable(other):
			continue
		var d: float = (_feet_of(other) + _cand_offset[c]).distance_squared_to(from)
		if d < best_sq:
			best_sq = d
			best = other
	return best


## The actors a swarmer may chase, read from the actor table every CANDIDATE_TIME seconds: every
## actor of another team than the swarm's that Combat has registered (a body that can be hit), with
## its body offset. The look then picks the nearest standing one among these few, as
## `nearest_target` with the team would among the grid's targets, without walking a grid full of
## swarmers (an unbounded `nearest_target` visits every target: about 0.5 ms at 1,000).
func _read_candidates(delta: float) -> void:
	_cand_left -= delta
	if _cand_left > 0.0 or actors == null:
		return
	_cand_left = CANDIDATE_TIME
	for c in _cand_count:
		_cand_nodes[c] = null
	_cand_count = 0
	var open: int = actors.open_count()
	var seen: int = 0
	for id in ActorsScript.ACTORS:
		if seen >= open or _cand_count >= MAX_CANDIDATES:
			break
		var team: int = actors.team_of(id)
		if team == ActorsScript.NONE:
			continue
		seen += 1
		if team == ActorsScript.TEAM_ENEMIES:
			continue
		var body := actors.node_of(id) as Node2D
		if body == null or not combat.is_registered(body):
			continue
		_cand_nodes[_cand_count] = body
		_cand_team[_cand_count] = team
		_cand_offset[_cand_count] = (body as Actor).body_offset if body is Actor else Vector2.ZERO
		_cand_count += 1


## The row chases `target` (null: nothing): the slot it holds is given back, the new one taken.
func _set_target(i: int, target: Node2D) -> void:
	var old: int = _target_slot[i]
	var slot: int = _slot_for(target) if target != null else -1
	if slot == old:
		return
	if old >= 0:
		_slot_refs[old] -= 1
	if slot >= 0:
		_slot_refs[slot] += 1
	_target_slot[i] = slot


## The slot of `target` (a new one when no row chases it yet), or -1 when every slot is taken.
func _slot_for(target: Node2D) -> int:
	var free: int = -1
	for slot in _slot_used:
		if _slot_refs[slot] > 0:
			if _slot_nodes[slot] == target:
				return slot
		elif free < 0:
			free = slot
	if free < 0:
		if _slot_used >= TARGET_SLOTS:
			return -1
		free = _slot_used
		_slot_used += 1
	_slot_nodes[free] = target
	_slot_refs[free] = 0
	# It was chaseable when found; its place is read now, so a row chasing it walks this step.
	_slot_ok[free] = 1
	var origin: Vector2 = _parent.global_position if _parent.is_inside_tree() else _parent.position
	_slot_at[free] = _feet_of(target) - origin
	return free


## Once a step for every distinct target: can it still be chased, and where are its feet.
func _read_targets(origin: Vector2) -> void:
	for slot in _slot_used:
		if _slot_refs[slot] <= 0:
			_slot_ok[slot] = 0
			continue
		var target: Variant = _slot_nodes[slot]
		if not _chaseable(target):
			_slot_ok[slot] = 0
			continue
		_slot_ok[slot] = 1
		_slot_at[slot] = _feet_of(target as Node2D) - origin


## The AI's test: a freed node, a down actor and a dying one are no targets.
func _chaseable(node: Variant) -> bool:
	if not is_instance_valid(node):
		return false
	if node is Actor:
		var other: Actor = node as Actor
		return not other.is_down() and not other.is_dying()
	return not (node.has_method("is_downed") and node.is_downed())


func _feet_of(node: Node2D) -> Vector2:
	return node.global_position if node.is_inside_tree() else node.position


# --- Spacing and walls --------------------------------------------------------------------------

## Moves overlapping pairs apart (see the class doc): the hash is filled with every row, then
## each owning row looks at its own cell (the rows after it in the cell's list) and four of its
## eight neighbours, so every pair is seen once.
func _space() -> void:
	_cell_head.fill(-1)
	_push.fill(Vector2.ZERO)
	var inv: float = 1.0 / _cell
	var gw: int = _grid_w
	var gh: int = _grid_h
	var ox: float = _arena.position.x
	var oy: float = _arena.position.y
	for i in count:
		# The row's move of this step first (its velocity for the seconds it ran).
		var p: Vector2 = positions[i] + velocities[i] * ran[i]
		positions[i] = p
		var cy: int = clampi(int((p.y - oy) * inv), 0, gh - 1)
		var cx: int = clampi(int((p.x - ox) * inv), 0, gw - 1)
		var cell: int = cy * gw + cx
		_next[i] = _cell_head[cell]
		_cell_head[cell] = i
		_cell_of[i] = cell
	# Half the rows own their pairs this step, the other half the next (a pair is seen every other
	# step, from whichever of its rows owns it then), at twice the share.
	var share: float = minf(spacing * 2.0, 1.0)
	# Spacing off (`spacing` 0, the card-rules parity test): the rows have moved, nothing pushes.
	var first: int = (moved & 1) if share > 0.0 else count
	for i in range(first, count, 2):
		var cell: int = _cell_of[i]
		var cy: int = cell / gw
		var cx: int = cell - cy * gw
		# Its own cell (only the rows after it in the list: each pair once), then four of its
		# neighbours: right, and the three below, in that order.
		var right: bool = cx + 1 < gw
		var has_below: bool = cy + 1 < gh
		var below: int = cell + gw
		var j: int = _next[i]
		var h1: int = _cell_head[cell + 1] if right else -1
		var h2: int = _cell_head[below] if has_below else -1
		var h3: int = _cell_head[below - 1] if has_below and cx > 0 else -1
		var h4: int = _cell_head[below + 1] if has_below and right else -1
		if j < 0 and h1 < 0 and h2 < 0 and h3 < 0 and h4 < 0:
			continue
		var p: Vector2 = positions[i]
		var r: float = _radius[i]
		var gi: float = _give[i]
		var push_i: Vector2 = _push[i]
		var k: int = 0
		while true:
			while j >= 0:
				var d: Vector2 = positions[j] - p
				var reach: float = r + _radius[j]
				var far_sq: float = d.length_squared()
				if far_sq < reach * reach:
					var gj: float = _give[j]
					var give: float = gi + gj
					if give > 0.0:
						var far: float = sqrt(far_sq)
						var normal: Vector2
						if far > 0.0001:
							normal = d / far
						else:
							# On the same spot: apart along a direction from the pair's seeds.
							normal = Vector2.from_angle(float((seeds[i] ^ seeds[j]) & 1023) * (TAU / 1024.0))
						var shift: Vector2 = normal * ((reach - far) * share / give)
						push_i -= shift * gi
						_push[j] += shift * gj
				j = _next[j]
			k += 1
			if k == 1:
				j = h1
			elif k == 2:
				j = h2
			elif k == 3:
				j = h3
			elif k == 4:
				j = h4
			else:
				break
		_push[i] = push_i


## Every row's spacing push (`_space`), then on the floor and out of the walls (a move into a wall
## cell slides along it or stays), and its node's `position` written.
func _keep_in() -> void:
	var low: Vector2 = _arena.position
	var high: Vector2 = _arena.end
	var ax: float = _arena.position.x
	var ay: float = _arena.position.y
	var walls: bool = _has_walls
	for i in count:
		var p: Vector2 = positions[i]
		var push: Vector2 = _push[i]
		if push != Vector2.ZERO:
			p += push
		p = p.clamp(low, high)
		if walls:
			# `_walled(p)`, written out.
			var cx: int = int((p.x - ax) / WALL_CELL)
			var cy: int = int((p.y - ay) / WALL_CELL)
			if cx >= 0 and cy >= 0 and cx < _wall_w and cy < _wall_h and _walls[cy * _wall_w + cx] != 0:
				var was: Vector2 = nodes[i].position
				if not _walled(Vector2(p.x, was.y)):
					p = Vector2(p.x, was.y)
				elif not _walled(Vector2(was.x, p.y)):
					p = Vector2(was.x, p.y)
				else:
					p = was
		positions[i] = p
		nodes[i].position = p


func _walled(p: Vector2) -> bool:
	var cx: int = int((p.x - _arena.position.x) / WALL_CELL)
	var cy: int = int((p.y - _arena.position.y) / WALL_CELL)
	if cx < 0 or cy < 0 or cx >= _wall_w or cy >= _wall_h:
		return false
	return _walls[cy * _wall_w + cx] != 0


## The hash's size for the floor and the cell (allocated at start and when a larger kind comes).
func _fit_grid() -> void:
	_grid_w = maxi(ceili(_arena.size.x / _cell), 1)
	_grid_h = maxi(ceili(_arena.size.y / _cell), 1)
	_cell_head.resize(_grid_w * _grid_h)


## The wall grid from `world`'s static bodies on the wall layer (their shapes' boxes, in the
## parent's space), grown by WALL_PAD; only the parts inside the floor count.
func _read_walls(world: Node) -> void:
	_wall_w = maxi(ceili(_arena.size.x / WALL_CELL), 1)
	_wall_h = maxi(ceili(_arena.size.y / WALL_CELL), 1)
	_walls.resize(_wall_w * _wall_h)
	_walls.fill(0)
	_has_walls = false
	if world == null:
		return
	for found: Node in world.find_children("*", "StaticBody2D", true, false):
		var body := found as StaticBody2D
		if (body.collision_layer & WALL_LAYER) == 0:
			continue
		for child: Node in body.get_children():
			var box: Rect2 = _shape_box(child)
			if box.size != Vector2.ZERO:
				_mark_wall(box.grow(WALL_PAD))


func _mark_wall(box: Rect2) -> void:
	var cut: Rect2 = box.intersection(_arena)
	if cut.size.x <= 0.0 or cut.size.y <= 0.0:
		return
	var x0: int = clampi(floori((cut.position.x - _arena.position.x) / WALL_CELL), 0, _wall_w - 1)
	var y0: int = clampi(floori((cut.position.y - _arena.position.y) / WALL_CELL), 0, _wall_h - 1)
	var x1: int = clampi(floori((cut.end.x - _arena.position.x) / WALL_CELL), 0, _wall_w - 1)
	var y1: int = clampi(floori((cut.end.y - _arena.position.y) / WALL_CELL), 0, _wall_h - 1)
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			_walls[y * _wall_w + x] = 1
	_has_walls = true


## One collision shape's box in the parent's space (empty for anything else).
func _shape_box(node: Node) -> Rect2:
	var shape_node := node as CollisionShape2D
	if shape_node == null or shape_node.shape == null or shape_node.disabled:
		return Rect2()
	return _to_parent(shape_node) * shape_node.shape.get_rect()


## The transform from `node`'s space to the parent's (both under the same world).
func _to_parent(node: Node2D) -> Transform2D:
	var out: Transform2D = Transform2D.IDENTITY
	var at: Node = node
	var world: Node = _parent.get_parent()
	while at != null and at != world:
		var step_node := at as Node2D
		if step_node != null:
			out = step_node.transform * out
		at = at.get_parent()
	return _parent.transform.affine_inverse() * out


# --- Events -------------------------------------------------------------------------------------

func _listen(on: bool) -> void:
	if events == null or not is_instance_valid(events) or on == _listening:
		return
	_listening = on
	if combat != null and is_instance_valid(combat):
		if on and not combat.stepping.is_connected(_promote_asked):
			combat.stepping.connect(_promote_asked)
		elif not on and combat.stepping.is_connected(_promote_asked):
			combat.stepping.disconnect(_promote_asked)
	if on:
		events.enemy_died.connect(_on_enemy_died)
		events.damage_dealt.connect(_on_damage_dealt)
		events.target_move_requested.connect(_on_target_move_requested)
		events.possess_requested.connect(_on_possess_requested)
	else:
		events.enemy_died.disconnect(_on_enemy_died)
		events.damage_dealt.disconnect(_on_damage_dealt)
		events.target_move_requested.disconnect(_on_target_move_requested)
		events.possess_requested.disconnect(_on_possess_requested)


## A swarmer died (Combat frees its node next): its row goes.
func _on_enemy_died(_killer: int, enemy: Node, _at: Vector2, _shot: int) -> void:
	var row: int = row_of(enemy)
	if row >= 0:
		if look != null and is_instance_valid(look) and look.has_method(&"on_row_died"):
			look.call(&"on_row_died", row)
		_drop(row)


## A hit on a swarmer: the hurt pose, and a grudge on a teammate that hurt it (as the AI holds).
func _on_damage_dealt(caster: int, target: Node, _amount: int, _at: Vector2) -> void:
	var row: int = row_of(target)
	if row < 0:
		return
	hurt_left[row] = HURT_TIME
	if look != null and is_instance_valid(look):
		look.call(&"on_hit", row)
	var id: int = actor_ids[row]
	if caster < 0 or caster == id or actors == null:
		return
	if actors.team_of(caster) != actors.team_of(id):
		return
	var attacker := actors.node_of(caster) as Node2D
	if attacker == null or attacker == target or not _chaseable(attacker):
		return
	_set_target(row, attacker)
	_grudge_left[row] = GRUDGE_TIME if _target_slot[row] >= 0 else 0.0


## A swap card moved a swarmer: it is there at once.
func _on_target_move_requested(_caster: int, target: Node, to: Vector2) -> void:
	var row: int = row_of(target)
	if row < 0 or not to.is_finite():
		return
	var origin: Vector2 = _parent.global_position if _parent != null and _parent.is_inside_tree() else Vector2.ZERO
	positions[row] = to - origin
	nodes[row].position = positions[row]


## A possession asked for a swarmer: kept, and the swarmer promoted at the start of the next step
## (see the class doc).
func _on_possess_requested(caster: int, target: int, seconds: float, _tag: int) -> void:
	if actors == null or row_of(actors.node_of(target)) < 0:
		return
	if _asked == _ask_target.size():
		var room: int = maxi(_asked * 2, 4)
		_ask_caster.resize(room)
		_ask_target.resize(room)
		_ask_seconds.resize(room)
	_ask_caster[_asked] = caster
	_ask_target[_asked] = target
	_ask_seconds[_asked] = seconds
	_asked += 1


# --- Promotion ----------------------------------------------------------------------------------

## Every swarmer asked for is promoted (once), and each request taken by its actor, in the order
## they came.
func _promote_asked() -> void:
	if _asked == 0:
		return
	var asked: int = _asked
	_asked = 0
	for n in asked:
		var node: Node = actors.node_of(_ask_target[n]) if actors != null else null
		var row: int = row_of(node)
		var body: Actor = promote(row) if row >= 0 else node as Actor
		if body != null and is_instance_valid(body) and body.is_inside_tree():
			body.take_possession(_ask_caster[n], _ask_seconds[n])


## Replaces the swarmer in `row` with the full actor of its kind, the same actor in every way the
## game keeps (see the class doc), and returns it; null when it cannot be made (no scene, or it is
## not an Actor), and the swarmer stays.
func promote(row: int) -> Actor:
	if row < 0 or row >= count or _parent == null or not is_instance_valid(_parent):
		return null
	var kind: SwarmKind = kinds_list[kinds[row]]
	if kind == null or kind.scene == null:
		return null
	var made: Node = kind.scene.instantiate()
	var actor := made as Actor
	if actor == null:
		if made != null:
			made.free()
		push_warning("Swarm: %s is no actor scene, so a swarmer of it cannot be promoted." % kind.enemy_id)
		return null
	var old: Node2D = nodes[row]
	var id: int = actor_ids[row]
	var state: Dictionary = combat.row_state(old) if combat != null and is_instance_valid(combat) else {}
	actor.data = kind.enemy
	actor.events = events
	actor.combat = combat
	actor.projectiles = projectiles
	actor.spells = spells
	actor.actors = actors
	actor.take_id = id
	actor.name = old.name
	actor.position = positions[row]
	actor.aim = aims[row]
	actor.velocity = velocities[row]
	var ai: AIController = null
	for child: Node in actor.get_children():
		if child is AIController:
			ai = child as AIController
			if entities != null:
				ai.entities = entities
			break
	var grudge: Node2D = null
	var grudge_left: float = _grudge_left[row]
	if grudge_left > 0.0 and _target_slot[row] >= 0:
		grudge = _slot_nodes[_target_slot[row]]
	_drop(row)
	# Whatever keeps the old body keeps the actor from now on (it is not in the tree yet: its target
	# entry is taken over in place, and its registration below finds it).
	if events != null and is_instance_valid(events):
		events.body_replaced.emit(id, old, actor)
	for slot in _slot_used:
		var held: Variant = _slot_nodes[slot]
		if is_instance_valid(held) and held == old:
			_slot_nodes[slot] = actor
	# The old node leaves first, so the actor takes its name.
	_parent.remove_child(old)
	_parent.add_child(actor)
	if not state.is_empty():
		combat.carry_row_state(actor, state)
	if ai != null and grudge != null and is_instance_valid(grudge):
		ai.carry_grudge(grudge, grudge_left)
	old.free()
	promoted_count += 1
	return actor


# --- Rows ---------------------------------------------------------------------------------------

## Drops row `row` in O(1): the last row takes its place in every array.
func _drop(row: int) -> void:
	var last: int = count - 1
	_row_by_node.erase(_node_ids[row])
	var slot: int = _target_slot[row]
	if slot >= 0:
		_slot_refs[slot] -= 1
	if row != last:
		nodes[row] = nodes[last]
		_node_ids[row] = _node_ids[last]
		_row_by_node[_node_ids[row]] = row
		kinds[row] = kinds[last]
		positions[row] = positions[last]
		velocities[row] = velocities[last]
		ran[row] = ran[last]
		aims[row] = aims[last]
		seeds[row] = seeds[last]
		hurt_left[row] = hurt_left[last]
		down[row] = down[last]
		actor_ids[row] = actor_ids[last]
		_speed[row] = _speed[last]
		_radius[row] = _radius[last]
		_retarget_left[row] = _retarget_left[last]
		_grudge_left[row] = _grudge_left[last]
		_target_slot[row] = _target_slot[last]
		_give[row] = _give[last]
	nodes[last] = null
	count = last
	if look != null and is_instance_valid(look):
		look.call(&"on_row_removed", row)


## Room for `size` rows in every array.
func _grow(size: int) -> void:
	nodes.resize(size)
	kinds.resize(size)
	positions.resize(size)
	velocities.resize(size)
	ran.resize(size)
	aims.resize(size)
	seeds.resize(size)
	hurt_left.resize(size)
	down.resize(size)
	actor_ids.resize(size)
	_node_ids.resize(size)
	_speed.resize(size)
	_radius.resize(size)
	_retarget_left.resize(size)
	_grudge_left.resize(size)
	_target_slot.resize(size)
	_give.resize(size)
	_push.resize(size)
	_next.resize(size)
	_cell_of.resize(size)
	_paces.resize(size)
	_pushes.resize(size)


## The autoloads, for every service the director did not hand over.
func _find_services() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var root: Node = tree.root if tree != null else null
	if root == null:
		return
	if events == null:
		events = root.get_node_or_null(^"Events") as EventsScript
	if combat == null:
		combat = root.get_node_or_null(^"Combat") as CombatScript
	if projectiles == null:
		projectiles = root.get_node_or_null(^"Projectiles") as ProjectileManagerScript
	if actors == null:
		actors = root.get_node_or_null(^"Actors") as ActorsScript
	if entities == null:
		entities = root.get_node_or_null(^"Entities") as EntitiesScript
	if spells == null:
		spells = root.get_node_or_null(^"Spells") as SpellsScript
