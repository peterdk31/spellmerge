extends CharacterBody2D
## Enemy AI (M1 part 12): chase the nearest standing player, then one telegraphed
## attack. The script goes on the root of an enemy scene (content/enemies/ember_imp/
## ember_imp.tscn); the spawner sets `data` (the enemy's `EnemyBase` resource)
## before adding the node, like `index` on a wizard.
##
## States: CHASE (walk to the nearest player who is not downed), WINDUP (stand
## still; the telegraph shows and the aim is locked at its start, so a player can
## step aside), then the shot flies and RECOVER (stand still) before CHASE again.
## An enemy never targets "the player": every player in the `players` group (or
## in `targets`) is a candidate, indices 0-3, and a downed one is skipped.
##
## The attack is a shot from `core/projectiles` that hits wizards (LAYER_PLAYER);
## Combat turns its hit into damage through a hit profile for `ATTACK_TAG`.
## Health, hurt box and knockback live in `gameplay/combat`: _ready() registers the
## enemy there and step() adds `consume_knockback_step` to the velocity. Death is
## Combat's (it frees the node), so there is no death code here.
##
## Telegraph: an optional `Sprite` child flashes (`modulate`) and an optional
## `Telegraph` child (a Line2D along +X) turns toward the locked aim and shows. Its
## far end is set to the real reach of the shot (`attack_speed * attack_lifetime`),
## and it grows wider and brighter with `telegraph_progress()`.
## Nothing here allocates per frame. Retargeting runs every RETARGET_TIME seconds
## (staggered per enemy), at once when `player_downed` arrives or the current target
## is lost, and once at the first step; with no explicit `targets` it reads the
## `players` group then. With nobody to chase it looks only every RETARGET_TIME.
##
## All timing runs in step(delta), so tests drive it with fixed deltas.
## _physics_process() calls step() and then move_and_slide().

const EventsScript := preload("res://core/events/events.gd")
const CombatScript := preload("res://gameplay/combat/combat.gd")
const ProjectileManagerScript := preload("res://core/projectiles/projectile_manager.gd")

enum State { CHASE, WINDUP, RECOVER }

## The group every wizard is in (player.gd adds it).
const PLAYERS_GROUP: StringName = &"players"
## Hit profile tags of enemy shots start here, plus a number derived from the enemy
## id (see `attack_tag`), so two enemy types do not overwrite each other's damage.
## Tag 0 means "no tag"; the fire bolt will use other tags.
const ATTACK_TAG_BASE: int = 1000
const ATTACK_TAG_SPREAD: int = 100000
## Collision layers of this body (see player.gd's LAYER_PLAYERS): its own and the walls.
const LAYER_ENEMIES: int = 4
const LAYER_WALLS: int = 1
## The telegraph line starts this far from the enemy; its look at 0% and 100% progress.
const TELEGRAPH_START: float = 10.0
const TELEGRAPH_WIDTH_MIN: float = 2.0
const TELEGRAPH_WIDTH_MAX: float = 4.0
const TELEGRAPH_ALPHA_MIN: float = 0.5
## Seconds between looking for the nearest player again.
const RETARGET_TIME: float = 0.5
## `Sprite` modulate while the telegraph shows.
const TELEGRAPH_COLOR: Color = Color(1.6, 1.3, 1.3)

## The enemy's numbers (speed, health, contact damage). Set before adding to the tree.
var data: EnemyBase = null
## Players to chase. Left empty, the `players` group is used.
var targets: Array = []

## Walk until a player is this close, then start the attack.
@export var attack_range: float = 90.0
## Seconds the telegraph shows before the shot.
@export var windup_time: float = 0.75
## Seconds standing still after the shot.
@export var recover_time: float = 1.0
@export var attack_damage: int = 10
## Shot speed in pixels per second and its life in seconds.
@export var attack_speed: float = 140.0
@export var attack_lifetime: float = 1.25
@export var attack_radius: float = 4.0
## Radius of the enemy's hurt box in pixels.
@export var hurt_radius: float = 8.0

## The event bus, Combat and the projectile manager. Only tests set these, before
## _ready(); otherwise the "Events", "Combat" and "Projectiles" autoloads are used.
var events: EventsScript = null
var combat: CombatScript = null
var projectiles: ProjectileManagerScript = null

var state: State = State.CHASE
## The player being chased, or null.
var target: Node2D = null
## Direction of the attack, locked when the windup starts (unit length).
var aim: Vector2 = Vector2.DOWN
## Hit profile tag of this enemy's shot, set in _ready() from `data.id`.
var attack_tag: int = ATTACK_TAG_BASE
## How often the players were looked up (tests count it).
var lookup_count: int = 0

var _state_left: float = 0.0
var _retarget_left: float = 0.0
var _retarget_offset: float = 0.0
var _looked: bool = false
## Instance id of `target` when it was chosen, or 0 for none.
var _target_id: int = 0
var _sprite: Sprite2D = null
var _telegraph: Node2D = null
var _telegraph_line: Line2D = null


func _init() -> void:
	collision_layer = LAYER_ENEMIES
	collision_mask = LAYER_WALLS
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING


func _ready() -> void:
	_sprite = get_node_or_null("Sprite") as Sprite2D
	_telegraph = get_node_or_null("Telegraph") as Node2D
	_telegraph_line = _telegraph as Line2D
	if _telegraph != null:
		_telegraph.visible = false
	if _telegraph_line != null and _telegraph_line.get_point_count() >= 2:
		var reach: float = maxf(attack_speed * attack_lifetime, TELEGRAPH_START)
		_telegraph_line.set_point_position(0, Vector2(TELEGRAPH_START, 0.0))
		_telegraph_line.set_point_position(1, Vector2(reach, 0.0))
	if events == null:
		events = get_node_or_null("/root/Events") as EventsScript
	if combat == null:
		combat = get_node_or_null("/root/Combat") as CombatScript
	if projectiles == null:
		projectiles = get_node_or_null("/root/Projectiles") as ProjectileManagerScript
	if events != null and not events.player_downed.is_connected(_on_player_downed):
		events.player_downed.connect(_on_player_downed)
	if data == null:
		push_warning("Ai: no enemy data set, so this enemy stands still.")
	if combat != null:
		if data != null:
			attack_tag = ATTACK_TAG_BASE + absi(hash([data.id, attack_damage])) % ATTACK_TAG_SPREAD
		combat.set_hit_profile(attack_tag, attack_damage, 0.0)
		if data != null:
			combat.register_enemy(self, data.max_health, hurt_radius, data.contact_damage)
	# Spread retargeting over the half second so 200 enemies do not all look at once.
	_retarget_offset = RETARGET_TIME * float(get_instance_id() % 8) / 8.0
	_retarget_left = _retarget_offset


func _exit_tree() -> void:
	if events != null and events.player_downed.is_connected(_on_player_downed):
		events.player_downed.disconnect(_on_player_downed)
	# Leaving the tree without being freed must not leave a target behind in Combat.
	if combat != null and is_instance_valid(combat):
		combat.unregister_enemy(self)


func _physics_process(delta: float) -> void:
	step(delta)
	move_and_slide()


## Advance the AI by `delta` seconds and set `velocity`. The caller moves the body
## (_physics_process does).
func step(delta: float) -> void:
	_retarget_left -= delta
	# Look on the timer, at the first step (staggered afterwards) or when the target
	# was just lost. With no target at all only the timer applies.
	# A freed target reads as null, so the id tells "never had one" from "lost it".
	var lost: bool = _target_id != 0 and not _is_valid_target(target)
	if _retarget_left <= 0.0 or lost or not _looked:
		_retarget_left = RETARGET_TIME if _looked else _retarget_offset
		_looked = true
		target = _find_target()
		_target_id = target.get_instance_id() if target != null else 0
	match state:
		State.CHASE:
			_step_chase()
		State.WINDUP:
			velocity = Vector2.ZERO
			_state_left -= delta
			if _state_left <= 0.0:
				_attack()
			else:
				_update_telegraph()
		State.RECOVER:
			velocity = Vector2.ZERO
			_state_left -= delta
			if _state_left <= 0.0:
				state = State.CHASE
	if combat != null:
		velocity += combat.consume_knockback_step(self, delta)


## True from the start of the windup until the shot leaves: the attack is coming.
func is_telegraphing() -> bool:
	return state == State.WINDUP


## 0.0 at the start of the telegraph, 1.0 when the shot leaves; 0.0 when not telegraphing.
func telegraph_progress() -> float:
	if state != State.WINDUP or windup_time <= 0.0:
		return 0.0
	return clampf(1.0 - _state_left / windup_time, 0.0, 1.0)


func _step_chase() -> void:
	_show_telegraph(false)
	if target == null or data == null:
		velocity = Vector2.ZERO
		return
	var to_target: Vector2 = _position_of(target) - _position_of(self)
	if to_target.length_squared() <= attack_range * attack_range:
		if to_target != Vector2.ZERO:
			aim = to_target.normalized()
		state = State.WINDUP
		_state_left = windup_time
		velocity = Vector2.ZERO
		_show_telegraph(true)
		return
	velocity = to_target.normalized() * data.move_speed


func _attack() -> void:
	if projectiles != null:
		projectiles.spawn(EventsScript.NO_PLAYER, _position_of(self), aim * attack_speed,
				attack_lifetime, attack_radius, ProjectileManagerScript.LAYER_PLAYER, 0, attack_tag)
	state = State.RECOVER
	_state_left = recover_time
	_show_telegraph(false)


func _show_telegraph(on: bool) -> void:
	if _telegraph != null:
		_telegraph.visible = on
		if on:
			_telegraph.rotation = aim.angle()
			_update_telegraph()
	if _sprite != null:
		_sprite.modulate = TELEGRAPH_COLOR if on else Color.WHITE


## Grow the telegraph line wider and brighter as the shot gets closer.
func _update_telegraph() -> void:
	if _telegraph == null:
		return
	var progress: float = telegraph_progress()
	_telegraph.modulate.a = lerpf(TELEGRAPH_ALPHA_MIN, 1.0, progress)
	if _telegraph_line != null:
		_telegraph_line.width = lerpf(TELEGRAPH_WIDTH_MIN, TELEGRAPH_WIDTH_MAX, progress)


func _find_target() -> Node2D:
	lookup_count += 1
	var here: Vector2 = _position_of(self)
	var best: Node2D = null
	var best_distance: float = INF
	var candidates: Array = targets
	if candidates.is_empty() and is_inside_tree():
		candidates = get_tree().get_nodes_in_group(PLAYERS_GROUP)
	for candidate: Variant in candidates:
		if not _is_valid_target(candidate):
			continue
		var wizard: Node2D = candidate as Node2D
		var distance: float = here.distance_squared_to(_position_of(wizard))
		if distance < best_distance:
			best_distance = distance
			best = wizard
	return best


## A freed player may still sit in `targets` or in `target`, hence the Variant.
func _is_valid_target(node: Variant) -> bool:
	if not is_instance_valid(node):
		return false
	return not (node.has_method("is_downed") and node.is_downed())


func _on_player_downed(player: int) -> void:
	# Only enemies chasing the downed wizard look again at once; the rest keep their
	# staggered timer, so a death does not make every enemy search in one frame.
	if is_instance_valid(target) and target.get("index") == player:
		_retarget_left = 0.0


func _position_of(node: Node2D) -> Vector2:
	return node.global_position if node.is_inside_tree() else node.position
