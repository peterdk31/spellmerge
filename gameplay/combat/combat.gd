extends Node
## Combat: the damage pipeline. One autoload ("Combat") turns hits into damage,
## knockback and deaths. It is the only sender of `damage_dealt` and `enemy_died`.
##
##     Combat.register_enemy(enemy, 20, 10.0, 1)         # health, hurt radius, contact damage
##     Combat.set_hit_profile(tag, 5, 200.0)             # what a shot with this tag does
##     Combat.register_player(0, wizard, 8.0)            # a wizard that enemies can touch
##
## A shot is hit by `core/projectiles`, which sends `projectile_hit(player, target,
## position, tag)`. Combat looks `tag` up in the hit profiles (damage and knockback
## strength) and runs the pipeline in hit(): ignore a bad hit, deal damage, push the
## enemy away from the hit, send `damage_dealt`, and on 0 health send `enemy_died`
## (naming the player who landed the last hit) and free the enemy.
##
## Hurt boxes: an enemy is registered with a hurt radius and added to
## `core/projectiles` as a target on LAYER_ENEMY; a wizard's hurt box is its own
## `take_damage` rules (the player ignores hits while dodging or downed, and Combat
## sends no event for those). Hit boxes: an enemy with contact damage hurts a
## registered wizard whose circle it overlaps, once per CONTACT_COOLDOWN per wizard.
##
## Knockback: Combat only keeps each enemy's knockback velocity. It never moves an
## enemy. The node that moves the enemy (the AI or enemy base, M1 part 12) adds
## `Combat.consume_knockback_step(enemy, delta)` to its own `move_and_slide()`
## velocity each physics frame, so walls and parent transforms are respected.
##
## Statuses (M2 part 7): an element's hit puts burn, chill, shock or hex on an enemy
## (`apply_status`, which sends `status_applied`); three chills freeze. They are packed
## arrays beside the health ones, counted down in step(). Burn deals whole points of damage
## as it goes, chill and freeze are read by the enemy's mover through `speed_factor`, a
## hexed enemy takes extra damage and is pulled toward hits, and a shocked enemy's next hit
## jumps to a neighbour found with the projectile manager's target grid. A static (charged)
## enemy hit again by a player's spell discharges to every other charged enemy near it, one
## step only (`_discharge`). A spell's hit comes
## with `Spells.hit_profile(tag)`; combat reads no spell field.
##
## Nothing here allocates per hit or per frame: enemies are rows in packed arrays.
## Players are told only through `damage_dealt`; wizards are not pushed (their
## movement is theirs), only enemies are. Listeners of `damage_dealt` and
## `enemy_died` may call hit(), register_enemy() or unregister_enemy(): contact
## hits are sent after the enemy loop, and hit() re-checks its row after sending.

const EventsScript := preload("res://core/events/events.gd")
const ProjectileManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const RegistryScript := preload("res://core/registry/registry.gd")
const SpellsScript := preload("res://core/spells/spells.gd")
## The element reactions, loaded by their literal path (the registry skips the table).
const REACTIONS: ReactionTable = preload("res://content/spells/reactions.tres")

## The statuses an element can put on an enemy (`ElementBase.status_id`), and `freeze`,
## which three stacks of chill make.
const BURN: StringName = &"burn"
const CHILL: StringName = &"chill"
const FREEZE: StringName = &"freeze"
const SHOCK: StringName = &"shock"
const HEX: StringName = &"hex"
const STATIC: StringName = &"static"
## The id a discharge is announced with on `reaction_triggered`, at each enemy it hits.
const DISCHARGE: StringName = &"discharge"

## The kinds of a hit (M2-staffs.md, "Self-harm and hits"). A shot or beam of a spell, an area
## hit (blast, a fallback), a reaction's damage, damage over time, and a heal.
const KIND_SHOT: StringName = &"shot"
const KIND_RAY: StringName = &"ray"
const KIND_BURST: StringName = &"burst"
const KIND_REACTION: StringName = &"reaction"
const KIND_STATUS: StringName = &"status"
const KIND_HEAL: StringName = &"heal"

## What "downed by your own ..." calls a hit when its spell has no name of its own.
const KIND_NAMES: Dictionary = {
	KIND_SHOT: "Shot",
	KIND_RAY: "Beam",
	KIND_BURST: "Blast",
	KIND_REACTION: "Reaction",
	KIND_STATUS: "Burn",
}
## Area hits started inside area hits go this deep and no further (a safeguard against a runaway chain).
const AREA_DEPTH: int = 8

const PLAYER_SLOTS: int = 4
## A barrier given for less than this many seconds lasts this long (a dash is shorter).
const WIZARD_SHIELD_MIN_TIME: float = 0.5
## An enemy knocked at least this fast into a wall (one step ahead of it) takes the slam of a
## heavy hit, once.
const SLAM_MIN_SPEED: float = 60.0
const SLAM_REACH: float = 2.0
## Seconds a wizard is safe from contact damage after one contact hit.
const CONTACT_COOLDOWN: float = 1.0
## How fast knockback speed falls, in pixels per second per second.
const KNOCKBACK_DECAY: float = 1200.0
## Chill stacks that freeze, how long the freeze lasts, and the largest share of speed
## chill can take away.
const CHILL_STACKS_TO_FREEZE: int = 3
const FREEZE_TIME: float = 1.0
const CHILL_SLOW_MAX: float = 0.9
## A shocked enemy's next hit also jumps to the nearest other enemy within this many pixels.
const SHOCK_JUMP_RANGE: float = 64.0
## A hit on a hexed enemy pulls it toward the hit point with this share of the push it
## would have had away from it.
const HEX_PULL_SHARE: float = 0.5
## A charged (static) enemy that is hit again discharges to every other charged enemy within
## this many pixels of it, once: the discharge is plain damage, so it sets off nothing else.
const STATIC_RANGE: float = 96.0
## The statuses a reaction can start from, in the order they are looked at.
const REACTING_STATUSES: Array[StringName] = [BURN, CHILL, SHOCK, HEX, STATIC]
## A consume reaction does this many times its damage to a frozen enemy.
const FROZEN_BONUS: int = 2
## An enemy reacts at most once per this many seconds; a hit inside the wait does its own
## status instead. Keeps fast spells from setting the same reaction off on every hit.
const REACTION_WAIT: float = 0.5
## Limits for the reaction EXTEND effect: the longest freeze, the longest any other extended
## status, the largest extra damage share of hex or shock in per cent, and the fastest burn.
const MAX_FREEZE: float = 4.0
const MAX_EXTENDED_TIME: float = 8.0
const MAX_EXTENDED_PERCENT: float = 100.0
const MAX_EXTENDED_BURN: float = 20.0

## The event bus, the projectile manager and the registry. Only tests set these, before
## adding the node; otherwise the "Events", "Projectiles" and "Registry" autoloads are used.
var events: EventsScript = null
var projectiles: ProjectileManagerScript = null
var registry: RegistryScript = null
## The spell runtime, which tells what a spell's shot does (`hit_profile`). Same rule.
var spells: SpellsScript = null
## The reaction table. Tests may set another one; null means REACTIONS.
var reactions: ReactionTable = null

# Scratch list for the targets of a burst or a spread (reused, so a reaction allocates nothing).
var _near: Array[Node2D] = []
# The targets of a discharge, copied out of `_near` (a hit can reuse that one).
var _discharge_targets: Array[Node2D] = []

# Hit profiles: tag -> damage and knockback strength.
var _profile_damage: Dictionary = {}
var _profile_knockback: Dictionary = {}

# Enemies, one row each.
var _enemies: Array[Node2D] = []
var _health: PackedInt32Array = PackedInt32Array()
var _contact_damage: PackedInt32Array = PackedInt32Array()
var _hurt_radius: PackedFloat32Array = PackedFloat32Array()
var _hurt_offset: PackedVector2Array = PackedVector2Array()
var _knock: PackedVector2Array = PackedVector2Array()

# Statuses, parallel to the enemy rows (a time left of 0 means the status is off).
# Burn: seconds left, damage per second, the fraction of a point not yet dealt, and who set it.
var _burn_left: PackedFloat32Array = PackedFloat32Array()
var _burn_rate: PackedFloat32Array = PackedFloat32Array()
var _burn_carry: PackedFloat32Array = PackedFloat32Array()
var _burn_player: PackedInt32Array = PackedInt32Array()
# Chill: seconds left, the share of speed it takes, stacks. Freeze: seconds left.
var _chill_left: PackedFloat32Array = PackedFloat32Array()
var _chill_slow: PackedFloat32Array = PackedFloat32Array()
var _chill_stacks: PackedInt32Array = PackedInt32Array()
var _freeze_left: PackedFloat32Array = PackedFloat32Array()
# Shock: seconds left and the percent of the hit's damage that jumps.
var _shock_left: PackedFloat32Array = PackedFloat32Array()
var _shock_share: PackedFloat32Array = PackedFloat32Array()
# Hex: seconds left and the percent of extra damage taken.
var _hex_left: PackedFloat32Array = PackedFloat32Array()
var _hex_extra: PackedFloat32Array = PackedFloat32Array()
# Static: seconds left and the percent of the hit's damage that discharges.
var _static_left: PackedFloat32Array = PackedFloat32Array()
var _static_share: PackedFloat32Array = PackedFloat32Array()
## True while a discharge is being dealt, so nothing it causes can start another.
var _discharging: bool = false
## Seconds until this enemy may react again.
var _react_wait: PackedFloat32Array = PackedFloat32Array()

# Burn damage due this step, sent after the status loop: enemy, player and points.
var _due_enemy: Array[Node2D] = []
var _due_player: PackedInt32Array = PackedInt32Array()
var _due_amount: PackedInt32Array = PackedInt32Array()

# Contact hits waiting to be sent after the enemy loop: wizard index and damage.
var _pending_index: PackedInt32Array = PackedInt32Array()
var _pending_amount: PackedInt32Array = PackedInt32Array()

# Wizards by player index.
var _players: Array = [null, null, null, null]
var _player_radius: PackedFloat32Array = PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
var _player_offset: PackedVector2Array = PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
var _contact_left: PackedFloat32Array = PackedFloat32Array([0.0, 0.0, 0.0, 0.0])

# Wizards' own state, by player index. Self-harm is always on: a wizard's statuses and
# knockback work like an enemy's, and are read by whoever moves the wizard (`gameplay/player`).
var _w_knock: PackedVector2Array = PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
var _w_burn_left: PackedFloat32Array = PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
var _w_burn_rate: PackedFloat32Array = PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
var _w_burn_carry: PackedFloat32Array = PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
var _w_burn_player: PackedInt32Array = PackedInt32Array([-1, -1, -1, -1])
var _w_chill_left: PackedFloat32Array = PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
var _w_chill_slow: PackedFloat32Array = PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
var _w_chill_stacks: PackedInt32Array = PackedInt32Array([0, 0, 0, 0])
var _w_freeze_left: PackedFloat32Array = PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
var _w_shock_left: PackedFloat32Array = PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
var _w_shock_share: PackedFloat32Array = PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
var _w_hex_left: PackedFloat32Array = PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
var _w_hex_extra: PackedFloat32Array = PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
var _w_static_left: PackedFloat32Array = PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
var _w_static_share: PackedFloat32Array = PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
# Seconds before a wizard can react again (REACTION_WAIT, as on an enemy).
var _w_react_wait: PackedFloat32Array = PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
# The barrier on a wizard: blocked hits left, seconds left and the card's tag.
var _w_shield: PackedInt32Array = PackedInt32Array([0, 0, 0, 0])
var _w_shield_left: PackedFloat32Array = PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
var _w_shield_tag: PackedInt32Array = PackedInt32Array([0, 0, 0, 0])
# Who hurt each wizard last, for "downed by ...": the player (or NO_PLAYER), the hit kind and the spell's name.
var _w_last_player: PackedInt32Array = PackedInt32Array([-1, -1, -1, -1])
var _w_last_kind: Array[StringName] = [&"", &"", &"", &""]
var _w_last_name: PackedStringArray = PackedStringArray(["", "", "", ""])

## The tag of the spell hit being dealt now (0 for none): `kill_landed`, `reaction_landed` and
## `wizard_hurt` carry it. Set around a spell's hit, restored after, so hits inside hits are right.
var _tag: int = 0
# Heavy hits armed on enemies: the slam damage waiting for a wall, and who dealt it.
var _slam: PackedInt32Array = PackedInt32Array()
var _slam_player: PackedInt32Array = PackedInt32Array()
# Slams due this step (after the loop, as hits can remove rows).
var _slam_due_enemy: Array[Node2D] = []
var _slam_due_player: PackedInt32Array = PackedInt32Array()
var _slam_due_amount: PackedInt32Array = PackedInt32Array()
# Scratch copies of the targets of area hits, one per nesting depth, and the depth now.
var _area_pool: Array = []
var _area_depth: int = 0


func _ready() -> void:
	setup()


## Find what is not set yet and listen to the events. `_ready` calls it; a scene that builds
## combat outside the tree (a test, the clip recorder) calls it after setting the fields.
func setup() -> void:
	# Absolute paths only work inside the tree (tests build combat outside it).
	var in_tree: bool = is_inside_tree()
	if events == null and in_tree:
		events = get_node_or_null("/root/Events") as EventsScript
		if events == null:
			push_warning("Combat: the Events autoload is missing, so combat hears and sends nothing.")
	if projectiles == null and in_tree:
		projectiles = get_node_or_null("/root/Projectiles") as ProjectileManagerScript
	if registry == null and in_tree:
		registry = get_node_or_null("/root/Registry") as RegistryScript
	if spells == null and in_tree:
		spells = get_node_or_null("/root/Spells") as SpellsScript
	if reactions == null:
		reactions = REACTIONS
	if events != null and not events.projectile_hit.is_connected(_on_projectile_hit):
		events.projectile_hit.connect(_on_projectile_hit)
	if events != null:
		if not events.player_downed.is_connected(_on_player_downed):
			events.player_downed.connect(_on_player_downed)
		if not events.player_revived.is_connected(_on_player_revived):
			events.player_revived.connect(_on_player_revived)
		if not events.area_hit_requested.is_connected(_on_area_hit_requested):
			events.area_hit_requested.connect(_on_area_hit_requested)
		if not events.wizard_shield_requested.is_connected(_on_wizard_shield_requested):
			events.wizard_shield_requested.connect(_on_wizard_shield_requested)
		if not events.pull_requested.is_connected(_on_pull_requested):
			events.pull_requested.connect(_on_pull_requested)


func _physics_process(delta: float) -> void:
	step(delta)


## Say what a shot with `tag` does: `damage` and knockback `strength` (pixels per second).
## Tag 0 means "no tag" and is refused. Whoever spawns the shots (a spell's bolt)
## picks its tag; setting a different profile on a tag in use replaces it, with a warning.
func set_hit_profile(tag: int, damage: int, strength: float = 0.0) -> void:
	if tag == 0:
		push_warning("Combat: tag 0 means no tag, so it has no hit profile.")
		return
	if _profile_damage.has(tag) and (_profile_damage[tag] != damage or _profile_knockback[tag] != strength):
		push_warning("Combat: tag %d already had a different hit profile; replacing it." % tag)
	_profile_damage[tag] = damage
	_profile_knockback[tag] = strength


func clear_hit_profile(tag: int) -> void:
	_profile_damage.erase(tag)
	_profile_knockback.erase(tag)


## Make `enemy` something that can be hurt and killed. Registering twice only
## resets its numbers.
func register_enemy(enemy: Node2D, health: int, hurt_radius: float, contact_damage: int = 0, hurt_offset: Vector2 = Vector2.ZERO) -> void:
	if enemy == null or health <= 0:
		return
	var at: int = _enemies.find(enemy)
	if at >= 0:
		_health[at] = health
		_hurt_radius[at] = hurt_radius
		_hurt_offset[at] = hurt_offset
		_contact_damage[at] = contact_damage
		_clear_statuses(at)
		_slam[at] = 0
		if projectiles != null:
			projectiles.add_target(enemy, hurt_radius, ProjectileManagerScript.LAYER_ENEMY, -1, hurt_offset)
		return
	_enemies.append(enemy)
	_health.append(health)
	_contact_damage.append(contact_damage)
	_hurt_radius.append(hurt_radius)
	_hurt_offset.append(hurt_offset)
	_knock.append(Vector2.ZERO)
	_burn_left.append(0.0)
	_burn_rate.append(0.0)
	_burn_carry.append(0.0)
	_burn_player.append(EventsScript.NO_PLAYER)
	_chill_left.append(0.0)
	_chill_slow.append(0.0)
	_chill_stacks.append(0)
	_freeze_left.append(0.0)
	_shock_left.append(0.0)
	_shock_share.append(0.0)
	_hex_left.append(0.0)
	_hex_extra.append(0.0)
	_static_left.append(0.0)
	_static_share.append(0.0)
	_react_wait.append(0.0)
	_slam.append(0)
	_slam_player.append(EventsScript.NO_PLAYER)
	if projectiles != null:
		projectiles.add_target(enemy, hurt_radius, ProjectileManagerScript.LAYER_ENEMY, -1, hurt_offset)


## Forget `enemy` without killing it (no event).
func unregister_enemy(enemy: Node2D) -> void:
	var at: int = _enemies.find(enemy)
	if at >= 0:
		_remove_enemy_at(at)


## Make wizard `node` (player `index`, 0-3) something enemy contact can hurt.
## `radius` is its hit circle in pixels; `hit_offset` moves the circle for enemy shots
## from the node's origin (the feet) to the drawn body.
func register_player(index: int, node: Node2D, radius: float, hit_offset: Vector2 = Vector2.ZERO) -> void:
	if index < 0 or index >= PLAYER_SLOTS:
		push_warning("Combat: player index %d is not 0-3." % index)
		return
	if _players[index] != node:
		unregister_player(index)
	_players[index] = node
	_player_radius[index] = radius
	_player_offset[index] = hit_offset
	_contact_left[index] = 0.0
	_clear_wizard(index)
	_w_last_player[index] = EventsScript.NO_PLAYER
	_w_last_name[index] = ""
	# Enemy shots (LAYER_PLAYER) find the wizard as a projectile target.
	# A downed wizard is not a target, so shots fly past it to the standing ones.
	if projectiles != null and not _is_downed(node):
		projectiles.add_target(node, radius, ProjectileManagerScript.LAYER_PLAYER, index, hit_offset)


func unregister_player(index: int) -> void:
	if index >= 0 and index < PLAYER_SLOTS:
		if projectiles != null and _players[index] != null and is_instance_valid(_players[index]):
			projectiles.remove_target(_players[index])
		_players[index] = null


func is_enemy(node: Node) -> bool:
	return _enemies.find(node) >= 0


func get_enemy_count() -> int:
	return _enemies.size()


## Health left of a registered enemy, or -1 if it is not registered (or dead).
func get_health(enemy: Node2D) -> int:
	var at: int = _enemies.find(enemy)
	return _health[at] if at >= 0 else -1


## Current knockback velocity of a registered enemy (zero when none).
func get_knockback(enemy: Node2D) -> Vector2:
	var at: int = _enemies.find(enemy)
	return _knock[at] if at >= 0 else Vector2.ZERO


## For the node that moves `enemy`: the knockback velocity (pixels per second) to
## add to its own movement this frame. Call it once per physics frame; it then
## fades the stored knockback by `KNOCKBACK_DECAY * delta`. Zero when there is none.
func consume_knockback_step(enemy: Node2D, delta: float) -> Vector2:
	var at: int = _enemies.find(enemy)
	if at < 0:
		return Vector2.ZERO
	var push: Vector2 = _knock[at]
	if push != Vector2.ZERO:
		_knock[at] = push.move_toward(Vector2.ZERO, KNOCKBACK_DECAY * delta)
	return push


## Put `status_id` (burn, chill, shock or hex) on `enemy` for `duration` seconds. `strength`
## is burn damage per second, the percent of speed chill takes, the percent of the hit that
## a shock jumps with, or the percent of extra damage a hex adds. `player` is credited with
## burn damage. A second application refreshes the time and keeps the stronger number; the
## third chill in a row freezes (`freeze`, FREEZE_TIME seconds) and clears the chill, and a
## frozen enemy takes no chill. Sends `status_applied`. Returns false for an unknown status,
## a time of 0, an enemy that is not registered, or a chill on a frozen enemy.
func apply_status(player: int, enemy: Node2D, status_id: StringName, duration: float, strength: float) -> bool:
	var at: int = _enemies.find(enemy)
	if at < 0 or duration <= 0.0:
		return false
	var froze: bool = false
	match status_id:
		BURN:
			if _burn_left[at] <= 0.0:
				_burn_rate[at] = 0.0
				_burn_carry[at] = 0.0
			_burn_left[at] = maxf(_burn_left[at], duration)
			_burn_rate[at] = maxf(_burn_rate[at], strength)
			_burn_player[at] = player
		CHILL:
			if _freeze_left[at] > 0.0:
				return false
			_chill_left[at] = maxf(_chill_left[at], duration)
			_chill_slow[at] = maxf(_chill_slow[at], clampf(strength / 100.0, 0.0, CHILL_SLOW_MAX))
			_chill_stacks[at] += 1
			if _chill_stacks[at] >= CHILL_STACKS_TO_FREEZE:
				_chill_left[at] = 0.0
				_chill_slow[at] = 0.0
				_chill_stacks[at] = 0
				_freeze_left[at] = FREEZE_TIME
				froze = true
		SHOCK:
			_shock_left[at] = maxf(_shock_left[at], duration)
			_shock_share[at] = maxf(_shock_share[at], strength)
		HEX:
			_hex_left[at] = maxf(_hex_left[at], duration)
			_hex_extra[at] = maxf(_hex_extra[at], strength)
		STATIC:
			_static_left[at] = maxf(_static_left[at], duration)
			_static_share[at] = maxf(_static_share[at], strength)
		_:
			push_warning("Combat: unknown status '%s'." % status_id)
			return false
	if events != null:
		events.status_applied.emit(player, enemy, status_id)
		if froze:
			events.status_applied.emit(player, enemy, FREEZE)
	return true


## Seconds left of `status_id` (burn, chill, freeze, shock or hex) on `enemy`; 0 when it
## is off or the enemy is not registered.
func status_left(enemy: Node2D, status_id: StringName) -> float:
	var at: int = _enemies.find(enemy)
	if at < 0:
		return 0.0
	match status_id:
		BURN:
			return _burn_left[at]
		CHILL:
			return _chill_left[at]
		FREEZE:
			return _freeze_left[at]
		SHOCK:
			return _shock_left[at]
		HEX:
			return _hex_left[at]
		STATIC:
			return _static_left[at]
	return 0.0


func has_status(enemy: Node2D, status_id: StringName) -> bool:
	return status_left(enemy, status_id) > 0.0


## Chill stacks on `enemy` (0 up to CHILL_STACKS_TO_FREEZE - 1; the last one freezes).
func chill_stacks(enemy: Node2D) -> int:
	var at: int = _enemies.find(enemy)
	return _chill_stacks[at] if at >= 0 else 0


## For the node that moves `enemy`: the share of its normal pace to keep. 1.0 when free,
## less when chilled, 0.0 when frozen. It scales walking and the attack timers; the
## enemy's knockback is not scaled.
func speed_factor(enemy: Node2D) -> float:
	var at: int = _enemies.find(enemy)
	if at < 0:
		return 1.0
	if _freeze_left[at] > 0.0:
		return 0.0
	if _chill_left[at] > 0.0:
		return 1.0 - _chill_slow[at]
	return 1.0


## The damage pipeline. `player` (or EventsScript.NO_PLAYER) dealt `amount` to
## `target`, pushing it along `direction` (unit length, or zero) at `strength`
## pixels per second. Returns true if the hit counted: it did damage, so
## `damage_dealt` was sent. A hit on an unknown node, a dead target, a dodging
## or downed wizard or for 0 or less does nothing.
## `kind` is the hit kind (`KIND_*`), told to Feel by `hit_landed`.
func hit(player: int, target: Node, amount: int, direction: Vector2 = Vector2.ZERO, strength: float = 0.0, kind: StringName = KIND_SHOT) -> bool:
	return _hit(player, target, amount, direction, strength, false, kind)


## hit() with a switch: a `quiet` hit (burn ticks) takes the whole pipeline, deaths
## included, but sends no `damage_dealt` for an enemy that survives, so Feel and the
## AI do not stutter, shake or flinch twice a second per burning enemy.
func _hit(player: int, target: Node, amount: int, direction: Vector2, strength: float, quiet: bool, kind: StringName = KIND_SHOT) -> bool:
	if amount <= 0 or target == null or not is_instance_valid(target):
		return false
	var at: int = _enemies.find(target)
	if at < 0:
		return _hit_player(player, target, amount, direction, strength, kind, null)
	var enemy: Node2D = _enemies[at]
	var where: Vector2 = _position_of(enemy)
	if _hex_left[at] > 0.0:
		amount += roundi(float(amount) * _hex_extra[at] / 100.0)
	_health[at] = maxi(_health[at] - amount, 0)
	if strength > 0.0:
		_knock[at] = direction * strength
	if events != null and not (quiet and _health[at] > 0):
		events.hit_landed.emit(player, enemy, amount, where, kind)
		events.damage_dealt.emit(player, enemy, amount, where)
		# A listener may have changed the registrations; find the row again.
		at = _enemies.find(enemy)
		if at < 0:
			return true
	if _health[at] == 0:
		_remove_enemy_at(at)
		if events != null:
			if _tag != 0:
				events.kill_landed.emit(player, enemy, where, _tag)
			events.enemy_died.emit(player, enemy, where)
		if enemy.is_inside_tree():
			enemy.queue_free()
	return true


## Move time on: contact boxes hurt wizards. Called every physics frame; tests
## call it with fixed deltas. Knockback is not applied here (see the top).
func step(delta: float) -> void:
	for i in PLAYER_SLOTS:
		_contact_left[i] = maxf(_contact_left[i] - delta, 0.0)
	# Drop enemies freed from outside, newest first so removal keeps the order.
	var at: int = _enemies.size() - 1
	while at >= 0:
		if not is_instance_valid(_enemies[at]):
			_remove_enemy_at(at)
		at -= 1
	for row in _enemies.size():
		_tick_statuses(row, delta)
		_check_slam(row)
		if _contact_damage[row] > 0:
			_touch_players(row)
	_send_burns()
	_send_slams()
	for index in PLAYER_SLOTS:
		_tick_wizard(index, delta)
	# Send after the loop, so listeners can change registrations safely.
	var sent: int = 0
	while sent < _pending_index.size():
		var wizard: Node2D = _players[_pending_index[sent]]
		if wizard != null and is_instance_valid(wizard) and events != null:
			_hit_player(EventsScript.NO_PLAYER, wizard, _pending_amount[sent], Vector2.ZERO, 0.0, KIND_SHOT, null)
		sent += 1
	_pending_index.clear()
	_pending_amount.clear()


## Count one enemy's statuses down; burn collects whole points of damage for _send_burns().
func _tick_statuses(row: int, delta: float) -> void:
	if _burn_left[row] > 0.0:
		var burned: float = minf(delta, _burn_left[row])
		_burn_left[row] -= burned
		_burn_carry[row] += _burn_rate[row] * burned
		var whole: int = int(_burn_carry[row])
		if whole > 0:
			_burn_carry[row] -= float(whole)
			_due_enemy.append(_enemies[row])
			_due_player.append(_burn_player[row])
			_due_amount.append(whole)
	if _chill_left[row] > 0.0:
		_chill_left[row] = maxf(_chill_left[row] - delta, 0.0)
		if _chill_left[row] == 0.0:
			_chill_slow[row] = 0.0
			_chill_stacks[row] = 0
	_freeze_left[row] = maxf(_freeze_left[row] - delta, 0.0)
	_shock_left[row] = maxf(_shock_left[row] - delta, 0.0)
	_hex_left[row] = maxf(_hex_left[row] - delta, 0.0)
	_static_left[row] = maxf(_static_left[row] - delta, 0.0)
	_react_wait[row] = maxf(_react_wait[row] - delta, 0.0)


## Deal the burn damage counted this step. After the loop, because hit() can remove rows.
func _send_burns() -> void:
	var sent: int = 0
	while sent < _due_enemy.size():
		if is_instance_valid(_due_enemy[sent]):
			_hit(_due_player[sent], _due_enemy[sent], _due_amount[sent], Vector2.ZERO, 0.0, true, KIND_STATUS)
		sent += 1
	_due_enemy.clear()
	_due_player.clear()
	_due_amount.clear()


func _clear_statuses(row: int) -> void:
	_burn_left[row] = 0.0
	_burn_rate[row] = 0.0
	_burn_carry[row] = 0.0
	_chill_left[row] = 0.0
	_chill_slow[row] = 0.0
	_chill_stacks[row] = 0
	_freeze_left[row] = 0.0
	_shock_left[row] = 0.0
	_shock_share[row] = 0.0
	_hex_left[row] = 0.0
	_hex_extra[row] = 0.0
	_static_left[row] = 0.0
	_static_share[row] = 0.0


func _touch_players(row: int) -> void:
	var enemy_at: Vector2 = _position_of(_enemies[row]) + _hurt_offset[row]
	for index in PLAYER_SLOTS:
		if _players[index] == null or _contact_left[index] > 0.0:
			continue
		if not is_instance_valid(_players[index]):
			_players[index] = null
			continue
		var wizard: Node2D = _players[index]
		var reach: float = _hurt_radius[row] + _player_radius[index]
		if enemy_at.distance_squared_to(_position_of(wizard) + _player_offset[index]) > reach * reach:
			continue
		if _can_hurt_player(wizard):
			_contact_left[index] = CONTACT_COOLDOWN
			_pending_index.append(index)
			_pending_amount.append(_contact_damage[row])


## A wizard decides for itself how much it is hurt; Combat only skips the event
## for hits it knows do nothing (the wizard is dodging or downed), and for
## nodes that are not registered wizards.
func _hit_player(player: int, target: Node, amount: int, direction: Vector2, strength: float, kind: StringName, profile: HitProfile) -> bool:
	if not _can_hurt_player(target):
		return false
	var index: int = _players.find(target)
	var where: Vector2 = _position_of(target as Node2D)
	# A barrier takes the hit whole: no damage, no status, no push.
	if kind != KIND_STATUS and _w_shield[index] > 0 and _w_shield_left[index] > 0.0:
		_w_shield[index] -= 1
		if _w_shield[index] == 0:
			_w_shield_left[index] = 0.0
		if events != null:
			events.shield_blocked.emit(index, where, _w_shield_tag[index])
		return false
	var discharge_share: float = 0.0
	# A status tick (a burn) is not a hit: no hex bonus, and it spends no shock or static.
	if kind != KIND_STATUS:
		if _w_hex_left[index] > 0.0:
			amount += roundi(float(amount) * _w_hex_extra[index] / 100.0)
		if _w_shock_left[index] > 0.0:
			amount += roundi(float(amount) * _w_shock_share[index] / 100.0)
			_w_shock_left[index] = 0.0
			_w_shock_share[index] = 0.0
		if _w_static_left[index] > 0.0:
			discharge_share = _w_static_share[index]
			_w_static_left[index] = 0.0
			_w_static_share[index] = 0.0
	if strength > 0.0:
		_w_knock[index] = direction * strength
	_w_last_player[index] = player
	_w_last_kind[index] = kind
	_w_last_name[index] = profile.source_name if profile != null else ""
	if events != null:
		events.hit_landed.emit(player, target, amount, where, kind)
		events.damage_dealt.emit(player, target, amount, where)
		# A burn tick is not a hit: cards that fire on hurt are not set off by it.
		if kind != KIND_STATUS:
			events.wizard_hurt.emit(index, amount, where, _tag, kind)
	if discharge_share > 0.0:
		# A charged wizard is a lightning rod: the charge leaves in one step to the enemies near.
		_wizard_discharge(index, where, maxi(roundi(float(amount) * discharge_share / 100.0), 1))
	return true


## A charged wizard was hit: every enemy within STATIC_RANGE takes `amount`, credited to the wizard.
## One step: the damage sets off nothing else (`_discharging`).
func _wizard_discharge(index: int, from: Vector2, amount: int) -> void:
	if projectiles == null or _discharging:
		return
	_discharging = true
	var spell_tag: int = _tag
	_tag = 0
	var count: int = projectiles.targets_in(from, STATIC_RANGE, ProjectileManagerScript.LAYER_ENEMY, _near)
	_discharge_targets.clear()
	for i in count:
		_discharge_targets.append(_near[i])
	_near.clear()
	for near in _discharge_targets:
		if is_instance_valid(near):
			var row: int = _enemies.find(near)
			if row >= 0 and events != null:
				var zapped: Vector2 = _position_of(near) + _hurt_offset[row]
				events.reaction_triggered.emit(index, DISCHARGE, zapped)
				events.discharge_arc.emit(index, from, zapped)
			hit(index, near, amount, Vector2.ZERO, 0.0, KIND_REACTION)
	_tag = spell_tag
	_discharging = false


## A heal hit: `amount` health for the wizard `index`, from `player`'s spell. A downed wizard is
## not healed. The wizard's own code adds the health (`heal_dealt`).
func _heal_player(player: int, index: int, amount: int) -> bool:
	var wizard: Node2D = _players[index]
	if amount <= 0 or wizard == null or not is_instance_valid(wizard) or _is_downed(wizard):
		return false
	var where: Vector2 = _position_of(wizard)
	if events != null:
		events.hit_landed.emit(player, wizard, amount, where, KIND_HEAL)
		events.heal_dealt.emit(player, wizard, amount, where)
	return true


func _can_hurt_player(target: Node) -> bool:
	if not target is Node2D or not _players.has(target):
		return false
	if target.has_method("is_invulnerable") and target.is_invulnerable():
		return false
	if target.has_method("is_downed") and target.is_downed():
		return false
	return true


func _is_downed(node: Node) -> bool:
	return node.has_method("is_downed") and node.is_downed()


func _on_player_downed(player: int) -> void:
	if player >= 0 and player < PLAYER_SLOTS:
		_clear_wizard(player)
	if projectiles != null and player >= 0 and player < PLAYER_SLOTS:
		var wizard: Node2D = _players[player]
		if wizard != null and is_instance_valid(wizard):
			projectiles.remove_target(wizard)


func _on_player_revived(player: int, _reviver: int) -> void:
	if player >= 0 and player < PLAYER_SLOTS:
		_w_last_player[player] = EventsScript.NO_PLAYER
		_w_last_name[player] = ""
	if projectiles != null and player >= 0 and player < PLAYER_SLOTS:
		var wizard: Node2D = _players[player]
		if wizard != null and is_instance_valid(wizard):
			projectiles.add_target(wizard, _player_radius[player], ProjectileManagerScript.LAYER_PLAYER, player, _player_offset[player])


## A shot landed. A spell's shot is described by `Spells.hit_profile(tag)` (damage, knockback,
## status); any other shot (an enemy's) by the table of `set_hit_profile`. A
## shocked target also sends the hit on to its nearest neighbour; a hexed one is pulled toward
## the hit instead of pushed away. The hit's own status goes on after the damage, on a target
## that survived.
func _on_projectile_hit(player: int, target: Node, position: Vector2, tag: int) -> void:
	if not target is Node2D:
		return
	var profile: HitProfile = spells.hit_profile(tag) if spells != null else null
	var damage: int = 0
	var strength: float = 0.0
	if profile != null:
		damage = profile.damage
		strength = profile.knockback
	elif _profile_damage.has(tag):
		damage = _profile_damage[tag] as int
		strength = _profile_knockback[tag] as float
	else:
		return
	var saved_tag: int = _tag
	_tag = tag if profile != null else 0
	var kind: StringName = profile.kind if profile != null else KIND_SHOT
	var index: int = _players.find(target)
	if index >= 0:
		_apply_to_wizard(player, index, position, profile, damage, strength, kind)
	else:
		_apply_to_enemy(player, target as Node2D, position, profile, damage, strength, kind)
	_tag = saved_tag


## A spell's hit (or the AI's old shot, with `profile` null) on the wizard `index`: a heal for a
## mend hit, else damage, a push away from `position`, then each element's reaction or status, as
## on an enemy (staffs F6: wizards react, from the same table, to every spell: an enemy's, a
## teammate's with friendly fire, their own). The caster's own spell hurts them like any other
## (self-harm is always on); `core/projectiles` decides which shots can reach a wizard at all
## (an enemy's, the caster once out of their hitbox, a teammate with friendly fire).
func _apply_to_wizard(player: int, index: int, position: Vector2, profile: HitProfile, damage: int, strength: float, kind: StringName) -> void:
	if profile != null and profile.heal > 0:
		_heal_player(player, index, profile.heal)
		return
	var wizard: Node2D = _players[index]
	var direction: Vector2 = (_position_of(wizard) - position).normalized()
	# The reaction is chosen from the statuses the wizard had when the hit arrived.
	var reaction: ReactionRow = null
	if profile != null and index < PLAYER_SLOTS and profile.element_id != &"" and _w_react_wait[index] <= 0.0:
		reaction = _wizard_reaction_for(index, profile.element_id)
	if not _hit_player(player, wizard, damage, direction, strength, kind, profile) or profile == null \
			or index >= PLAYER_SLOTS:
		return
	# Every element in order: each reacts with what the ones before it left, or puts its own status on.
	var reacted: bool = false
	var elements: int = maxi(profile.element_ids.size(), profile.later_status_ids.size() + 1)
	for i in elements:
		if not is_instance_valid(wizard) or _is_downed(wizard):
			return
		var step_reaction: ReactionRow = reaction
		var status_id: StringName = profile.status_id
		var duration: float = profile.status_duration
		var power: float = profile.status_strength
		if i > 0:
			var element: StringName = profile.element_ids[i] if i < profile.element_ids.size() else &""
			step_reaction = _wizard_reaction_for(index, element) if element != &"" and (reacted or _w_react_wait[index] <= 0.0) else null
			status_id = profile.later_status_ids[i - 1] if i - 1 < profile.later_status_ids.size() else &""
			duration = profile.later_status_durations[i - 1] if i - 1 < profile.later_status_durations.size() else 0.0
			power = profile.later_status_strengths[i - 1] if i - 1 < profile.later_status_strengths.size() else 0.0
		if step_reaction != null:
			_react_wizard(player, index, step_reaction)
			reacted = true
		elif status_id != &"":
			apply_wizard_status(player, index, status_id, duration, power)


## The reaction a hit of `element_id` sets off on the wizard `index`, from the first of their
## statuses that has a row for that element (a frozen wizard counts as chilled); null for none.
func _wizard_reaction_for(index: int, element_id: StringName) -> ReactionRow:
	var table: ReactionTable = reactions if reactions != null else REACTIONS
	for status in REACTING_STATUSES:
		if _w_status_on(index, status):
			var row: ReactionRow = table.find(status, element_id)
			if row != null:
				return row
	return null


func _w_status_on(index: int, status_id: StringName) -> bool:
	match status_id:
		BURN:
			return _w_burn_left[index] > 0.0
		CHILL:
			return _w_chill_left[index] > 0.0 or _w_freeze_left[index] > 0.0
		SHOCK:
			return _w_shock_left[index] > 0.0
		HEX:
			return _w_hex_left[index] > 0.0
		STATIC:
			return _w_static_left[index] > 0.0
	return false


## Run `row` on the wizard `index`, as `_react` does on an enemy: announced (`reaction_triggered`,
## and `reaction_landed` for the caster's `on reaction`), then its effect on wizards: CONSUME hurts
## this one, BURST every wizard in the circle, EXTEND lengthens (or freezes), SPREAD copies the
## status to the wizards near. What it deals sets off no more reactions and is no spell's kill.
func _react_wizard(player: int, index: int, row: ReactionRow) -> void:
	var wizard: Node2D = _players[index]
	if wizard == null or not is_instance_valid(wizard):
		return
	var centre: Vector2 = _position_of(wizard) + _player_offset[index]
	_w_react_wait[index] = REACTION_WAIT
	if events != null:
		events.reaction_triggered.emit(player, row.reaction_id, centre)
		if _tag != 0:
			events.reaction_landed.emit(player, row.reaction_id, wizard, centre, _tag)
	var spell_tag: int = _tag
	_tag = 0
	match row.effect:
		ReactionRow.Effect.CONSUME:
			var amount: int = row.damage
			if _w_freeze_left[index] > 0.0:
				amount *= FROZEN_BONUS
				_w_remove_status(index, CHILL)
			_w_remove_status(index, row.status_id)
			_hit_player(player, wizard, amount, Vector2.ZERO, 0.0, KIND_REACTION, null)
		ReactionRow.Effect.BURST:
			if row.consume_status:
				_w_remove_status(index, row.status_id)
			for other in PLAYER_SLOTS:
				var near: Node2D = _players[other]
				if near == null or not is_instance_valid(near) or _is_downed(near):
					continue
				var reach: float = row.radius + _player_radius[other]
				var at: Vector2 = _position_of(near) + _player_offset[other]
				if at.distance_squared_to(centre) > reach * reach and other != index:
					continue
				var toward: Vector2 = (centre - at).normalized() if row.pull > 0.0 else Vector2.ZERO
				_hit_player(player, near, row.damage, toward, row.pull, KIND_REACTION, null)
		ReactionRow.Effect.EXTEND:
			_w_extend(player, index, row)
		ReactionRow.Effect.SPREAD:
			var left: float = wizard_status_left(index, row.status_id)
			var spread_strength: float = _w_strength_of(index, row.status_id)
			if row.consume_status:
				_w_remove_status(index, row.status_id)
			if left > 0.0:
				for other in PLAYER_SLOTS:
					var near: Node2D = _players[other]
					if other == index or near == null or not is_instance_valid(near):
						continue
					var reach: float = row.radius + _player_radius[other]
					if (_position_of(near) + _player_offset[other]).distance_squared_to(centre) <= reach * reach:
						apply_wizard_status(player, other, row.status_id, left, spread_strength)
	_tag = spell_tag


## EXTEND on the wizard `index`: as `_extend` on an enemy (a chilled wizard freezes).
func _w_extend(player: int, index: int, row: ReactionRow) -> void:
	match row.status_id:
		BURN:
			_w_burn_left[index] = minf(_w_burn_left[index] + row.duration, MAX_EXTENDED_TIME)
			_w_burn_rate[index] = minf(_w_burn_rate[index] + row.strength, MAX_EXTENDED_BURN)
		CHILL:
			var newly: bool = _w_freeze_left[index] <= 0.0
			_w_chill_left[index] = 0.0
			_w_chill_slow[index] = 0.0
			_w_chill_stacks[index] = 0
			_w_freeze_left[index] = minf(_w_freeze_left[index] + row.duration, MAX_FREEZE)
			if newly and events != null:
				events.status_applied.emit(player, _players[index], FREEZE)
		SHOCK:
			_w_shock_left[index] = minf(_w_shock_left[index] + row.duration, MAX_EXTENDED_TIME)
			_w_shock_share[index] = minf(_w_shock_share[index] + row.strength, MAX_EXTENDED_PERCENT)
		HEX:
			_w_hex_left[index] = minf(_w_hex_left[index] + row.duration, MAX_EXTENDED_TIME)
			_w_hex_extra[index] = minf(_w_hex_extra[index] + row.strength, MAX_EXTENDED_PERCENT)
		STATIC:
			_w_static_left[index] = minf(_w_static_left[index] + row.duration, MAX_EXTENDED_TIME)
			_w_static_share[index] = minf(_w_static_share[index] + row.strength, MAX_EXTENDED_PERCENT)


## The strength `apply_wizard_status` takes for the wizard's status now (as `_strength_of`).
func _w_strength_of(index: int, status_id: StringName) -> float:
	match status_id:
		BURN:
			return _w_burn_rate[index]
		CHILL:
			return _w_chill_slow[index] * 100.0
		SHOCK:
			return _w_shock_share[index]
		HEX:
			return _w_hex_extra[index]
		STATIC:
			return _w_static_share[index]
	return 0.0


## Switch `status_id` off on the wizard `index` (the freeze goes with the chill).
func _w_remove_status(index: int, status_id: StringName) -> void:
	match status_id:
		BURN:
			_w_burn_left[index] = 0.0
			_w_burn_rate[index] = 0.0
			_w_burn_carry[index] = 0.0
		CHILL:
			_w_chill_left[index] = 0.0
			_w_chill_slow[index] = 0.0
			_w_chill_stacks[index] = 0
			_w_freeze_left[index] = 0.0
		SHOCK:
			_w_shock_left[index] = 0.0
			_w_shock_share[index] = 0.0
		HEX:
			_w_hex_left[index] = 0.0
			_w_hex_extra[index] = 0.0
		STATIC:
			_w_static_left[index] = 0.0
			_w_static_share[index] = 0.0


## A spell's hit on an enemy: damage and push (pulled toward the hit when hexed), the shock jump,
## the static discharge, then the reaction or the hit's own status. `position` is where it struck.
func _apply_to_enemy(player: int, enemy: Node2D, position: Vector2, profile: HitProfile, damage: int, strength: float, kind: StringName) -> void:
	var direction: Vector2 = (_position_of(enemy) - position).normalized()
	var at: int = _enemies.find(enemy)
	var jump_share: float = 0.0
	var jump_from: Vector2 = Vector2.ZERO
	var discharge_share: float = 0.0
	var discharge_from: Vector2 = Vector2.ZERO
	if at >= 0:
		if _hex_left[at] > 0.0:
			direction = -direction
			strength *= HEX_PULL_SHARE
		if _shock_left[at] > 0.0:
			jump_share = _shock_share[at]
			jump_from = _position_of(enemy) + _hurt_offset[at]
		# Only a player's spell discharges: the hit must carry a player index.
		if _static_left[at] > 0.0 and profile != null and player >= 0 and player < PLAYER_SLOTS:
			discharge_share = _static_share[at]
			discharge_from = _position_of(enemy) + _hurt_offset[at]
	# The reaction is chosen from the statuses the target had when the shot arrived.
	var reaction: ReactionRow = null
	if at >= 0 and profile != null and profile.element_id != &"" and _react_wait[at] <= 0.0:
		reaction = _reaction_for(at, profile.element_id)
	if not hit(player, enemy, damage, direction, strength, kind):
		return
	if strength > 0.0:
		# A push replaces the knockback, so it replaces the slam too: only a heavy hit arms it.
		var armed: int = _enemies.find(enemy)
		if armed >= 0:
			_slam[armed] = profile.slam if profile != null and profile.slam > 0 else 0
			_slam_player[armed] = player
	var spent: int = _enemies.find(enemy)
	if spent >= 0:
		_shock_left[spent] = 0.0
		_shock_share[spent] = 0.0
	# What the jump, the discharge and the reactions kill is not the spell's own kill: no `kill_landed`.
	var spell_tag: int = _tag
	if jump_share > 0.0:
		_tag = 0
		_shock_jump(player, enemy, jump_from, roundi(float(damage) * jump_share / 100.0))
		_tag = spell_tag
	var discharged: bool = false
	if discharge_share > 0.0:
		_tag = 0
		discharged = _discharge(player, enemy, discharge_from, roundi(float(damage) * discharge_share / 100.0))
		_tag = spell_tag
		if discharged:
			# The struck enemy is spent; the ones it hit stay charged.
			var spent_at: int = _enemies.find(enemy)
			if spent_at >= 0:
				_remove_status(spent_at, STATIC)
	if profile == null:
		return
	# Every element of the hit in order: each reacts with what the ones before it left, or puts its
	# own status on (`fire · frost · bolt` thaws on its own hit). The first reaction was chosen above.
	# (One reaction per hit on a target, but within a hit the chain goes on: `reacted` lets the next element read what is left.)
	var reacted: bool = false
	var elements: int = maxi(profile.element_ids.size(), 1)
	for i in elements:
		var row: int = _enemies.find(enemy)
		if row < 0 or not is_instance_valid(enemy):
			return
		var step_reaction: ReactionRow = reaction
		var status_id: StringName = profile.status_id
		var duration: float = profile.status_duration
		var power: float = profile.status_strength
		if i > 0:
			var element: StringName = profile.element_ids[i] if i < profile.element_ids.size() else &""
			step_reaction = _reaction_for(row, element) if element != &"" and (reacted or _react_wait[row] <= 0.0) else null
			status_id = profile.later_status_ids[i - 1] if i - 1 < profile.later_status_ids.size() else &""
			duration = profile.later_status_durations[i - 1] if i - 1 < profile.later_status_durations.size() else 0.0
			power = profile.later_status_strengths[i - 1] if i - 1 < profile.later_status_strengths.size() else 0.0
		if step_reaction != null:
			# The reaction runs instead of the status, and only on a target that lived.
			_react(player, enemy, step_reaction)
			reacted = true
		elif status_id != &"" and not (i == 0 and discharged):
			# (A discharge replaces the first status, so a lightning hit does not charge again at once.)
			apply_status(player, enemy, status_id, duration, power)


## The reaction a hit of `element_id` sets off on enemy row `at`, from the first of its
## statuses that has a row for that element; null when none does. A frozen enemy counts as
## chilled. Allocation-free.
func _reaction_for(at: int, element_id: StringName) -> ReactionRow:
	var table: ReactionTable = reactions if reactions != null else REACTIONS
	for status in REACTING_STATUSES:
		if _status_on(at, status):
			var row: ReactionRow = table.find(status, element_id)
			if row != null:
				return row
	return null


func _status_on(at: int, status_id: StringName) -> bool:
	match status_id:
		BURN:
			return _burn_left[at] > 0.0
		CHILL:
			return _chill_left[at] > 0.0 or _freeze_left[at] > 0.0
		SHOCK:
			return _shock_left[at] > 0.0
		HEX:
			return _hex_left[at] > 0.0
		STATIC:
			return _static_left[at] > 0.0
	return false


## Run `row` on `enemy`: announce it (`reaction_triggered`, at the enemy), then do its effect
## kind. Reactions only start from a projectile hit; the damage they deal sets off no more.
func _react(player: int, enemy: Node2D, row: ReactionRow) -> void:
	var at: int = _enemies.find(enemy)
	if at < 0:
		return
	var centre: Vector2 = _position_of(enemy) + _hurt_offset[at]
	_react_wait[at] = REACTION_WAIT
	if events != null:
		events.reaction_triggered.emit(player, row.reaction_id, centre)
		if _tag != 0:
			events.reaction_landed.emit(player, row.reaction_id, enemy, centre, _tag)
		at = _enemies.find(enemy)
		if at < 0:
			return
	# A kill by the reaction's own damage is not the spell's kill: no `kill_landed`.
	var spell_tag: int = _tag
	_tag = 0
	_react_effect(player, enemy, at, centre, row)
	_tag = spell_tag


func _react_effect(player: int, enemy: Node2D, at: int, centre: Vector2, row: ReactionRow) -> void:
	match row.effect:
		ReactionRow.Effect.CONSUME:
			var amount: int = row.damage
			if _freeze_left[at] > 0.0:
				amount *= FROZEN_BONUS
				_remove_status(at, CHILL)
			_remove_status(at, row.status_id)
			hit(player, enemy, amount, Vector2.ZERO, 0.0, KIND_REACTION)
		ReactionRow.Effect.BURST:
			if row.consume_status:
				_remove_status(at, row.status_id)
			_burst(player, enemy, centre, row)
		ReactionRow.Effect.EXTEND:
			_extend(player, at, row)
		ReactionRow.Effect.SPREAD:
			_spread(player, at, centre, row)


## BURST: `row.damage` to every enemy in the circle, the struck one included, and a pull
## toward the centre when the row has one.
func _burst(player: int, enemy: Node2D, centre: Vector2, row: ReactionRow) -> void:
	if projectiles == null:
		hit(player, enemy, row.damage, Vector2.ZERO, 0.0, KIND_REACTION)
		return
	var count: int = projectiles.targets_in(centre, row.radius, ProjectileManagerScript.LAYER_ENEMY, _near)
	for i in count:
		var near: Node2D = _near[i]
		if not is_instance_valid(near):
			continue
		var toward: Vector2 = (centre - _position_of(near)).normalized() if row.pull > 0.0 else Vector2.ZERO
		hit(player, near, row.damage, toward, row.pull, KIND_REACTION)
	_near.clear()


## EXTEND: the status lasts longer and is stronger. A chilled enemy freezes for the row's
## duration; a frozen one stays frozen that much longer.
func _extend(player: int, at: int, row: ReactionRow) -> void:
	var enemy: Node2D = _enemies[at]
	match row.status_id:
		BURN:
			_burn_left[at] = minf(_burn_left[at] + row.duration, MAX_EXTENDED_TIME)
			_burn_rate[at] = minf(_burn_rate[at] + row.strength, MAX_EXTENDED_BURN)
		CHILL:
			var newly: bool = _freeze_left[at] <= 0.0
			_chill_left[at] = 0.0
			_chill_slow[at] = 0.0
			_chill_stacks[at] = 0
			_freeze_left[at] = minf(_freeze_left[at] + row.duration, MAX_FREEZE)
			if newly and events != null:
				events.status_applied.emit(player, enemy, FREEZE)
		SHOCK:
			_shock_left[at] = minf(_shock_left[at] + row.duration, MAX_EXTENDED_TIME)
			_shock_share[at] = minf(_shock_share[at] + row.strength, MAX_EXTENDED_PERCENT)
		HEX:
			_hex_left[at] = minf(_hex_left[at] + row.duration, MAX_EXTENDED_TIME)
			_hex_extra[at] = minf(_hex_extra[at] + row.strength, MAX_EXTENDED_PERCENT)
		STATIC:
			_static_left[at] = minf(_static_left[at] + row.duration, MAX_EXTENDED_TIME)
			_static_share[at] = minf(_static_share[at] + row.strength, MAX_EXTENDED_PERCENT)


## SPREAD: the status, as it is now, goes on every other enemy in the circle.
func _spread(player: int, at: int, centre: Vector2, row: ReactionRow) -> void:
	if projectiles == null:
		return
	var enemy: Node2D = _enemies[at]
	var left: float = status_left(enemy, row.status_id)
	var strength: float = _strength_of(at, row.status_id)
	if row.consume_status:
		_remove_status(at, row.status_id)
	if left <= 0.0:
		return
	var count: int = projectiles.targets_in(centre, row.radius, ProjectileManagerScript.LAYER_ENEMY, _near)
	for i in count:
		var near: Node2D = _near[i]
		if near != enemy and is_instance_valid(near):
			apply_status(player, near, row.status_id, left, strength)
	_near.clear()


## The number `apply_status` takes as strength for the status on row `at`.
func _strength_of(at: int, status_id: StringName) -> float:
	match status_id:
		BURN:
			return _burn_rate[at]
		CHILL:
			return _chill_slow[at] * 100.0
		SHOCK:
			return _shock_share[at]
		HEX:
			return _hex_extra[at]
		STATIC:
			return _static_share[at]
	return 0.0


## Switch `status_id` off on row `at` (a frozen enemy loses its freeze with its chill).
func _remove_status(at: int, status_id: StringName) -> void:
	match status_id:
		BURN:
			_burn_left[at] = 0.0
			_burn_rate[at] = 0.0
			_burn_carry[at] = 0.0
		CHILL:
			_chill_left[at] = 0.0
			_chill_slow[at] = 0.0
			_chill_stacks[at] = 0
			_freeze_left[at] = 0.0
		SHOCK:
			_shock_left[at] = 0.0
			_shock_share[at] = 0.0
		HEX:
			_hex_left[at] = 0.0
			_hex_extra[at] = 0.0
		STATIC:
			_static_left[at] = 0.0
			_static_share[at] = 0.0


## The hit on `from_enemy` jumps from `from` to the nearest other enemy in reach, for `amount`
## (at least 1). The jump pushes nothing and puts on no status.
func _shock_jump(player: int, from_enemy: Node2D, from: Vector2, amount: int) -> void:
	if projectiles == null:
		return
	var next: Node2D = projectiles.nearest_target(from, SHOCK_JUMP_RANGE, ProjectileManagerScript.LAYER_ENEMY, from_enemy)
	if next != null:
		hit(player, next, maxi(amount, 1))


## The hit on `from_enemy` discharges: every other charged enemy within STATIC_RANGE of `from`
## takes `amount` (at least 1) as `player`'s damage. One step only: the damage is plain `hit`s
## that react to nothing and charge nothing, and `_discharging` refuses a discharge started
## from inside another one (a listener of `damage_dealt` casting, say). Returns true if
## anyone was hit.
func _discharge(player: int, from_enemy: Node2D, from: Vector2, amount: int) -> bool:
	if projectiles == null or _discharging:
		return false
	_discharging = true
	var hit_any: bool = false
	var count: int = projectiles.targets_in(from, STATIC_RANGE, ProjectileManagerScript.LAYER_ENEMY, _near)
	# Hits can remove rows and listeners can reuse `_near`: copy the targets before dealing damage.
	_discharge_targets.clear()
	for i in count:
		_discharge_targets.append(_near[i])
	_near.clear()
	for near in _discharge_targets:
		if near == from_enemy or not is_instance_valid(near):
			continue
		var row: int = _enemies.find(near)
		if row >= 0 and _static_left[row] > 0.0:
			if events != null:
				# Feel shows a burst on each enemy zapped and a jagged arc from the struck one.
				var zapped: Vector2 = _position_of(near) + _hurt_offset[row]
				events.reaction_triggered.emit(player, DISCHARGE, zapped)
				events.discharge_arc.emit(player, from, zapped)
			hit_any = hit(player, near, maxi(amount, 1)) or hit_any
	_discharging = false
	return hit_any


func _remove_enemy_at(at: int) -> void:
	if projectiles != null and is_instance_valid(_enemies[at]):
		projectiles.remove_target(_enemies[at])
	_enemies.remove_at(at)
	_health.remove_at(at)
	_contact_damage.remove_at(at)
	_hurt_radius.remove_at(at)
	_hurt_offset.remove_at(at)
	_knock.remove_at(at)
	_burn_left.remove_at(at)
	_burn_rate.remove_at(at)
	_burn_carry.remove_at(at)
	_burn_player.remove_at(at)
	_chill_left.remove_at(at)
	_chill_slow.remove_at(at)
	_chill_stacks.remove_at(at)
	_freeze_left.remove_at(at)
	_shock_left.remove_at(at)
	_shock_share.remove_at(at)
	_hex_left.remove_at(at)
	_hex_extra.remove_at(at)
	_static_left.remove_at(at)
	_static_share.remove_at(at)
	_react_wait.remove_at(at)
	_slam.remove_at(at)
	_slam_player.remove_at(at)


## Area hits (`area_hit_requested`, from blast and a payload's fallback): the spell's hit lands
## on every enemy and every wizard in the circle, the caster included, with kind `burst`.
## A teammate is only hurt with friendly fire (`Projectiles.friendly_fire`); a mend hit heals
## whoever stands in it. Nested area hits (on kill, on hit chains) are cut at AREA_DEPTH.
## An enemy's area hit (its tag is an enemy's, staffs F6) takes its side: it hurts every wizard
## in the circle, other enemies only with `Projectiles.enemy_fire` and never the enemy that cast
## it (the target its caster row owns); an enemy's mend heals no wizard.
func _on_area_hit_requested(player: int, position: Vector2, radius: float, tag: int) -> void:
	var profile: HitProfile = spells.hit_profile(tag) if spells != null else null
	if profile == null or _area_depth >= AREA_DEPTH:
		return
	var depth: int = _area_depth
	_area_depth += 1
	if depth >= _area_pool.size():
		var fresh: Array[Node2D] = []
		_area_pool.append(fresh)
	var targets: Array[Node2D] = _area_pool[depth]
	targets.clear()
	var saved_tag: int = _tag
	_tag = tag
	var enemy_side: bool = SpellTag.is_enemy_tag(tag)
	var caster: int = SpellTag.caster_of(tag)
	if projectiles != null and (not enemy_side or projectiles.enemy_fire):
		var count: int = projectiles.targets_in(position, radius, ProjectileManagerScript.LAYER_ENEMY, _near)
		for i in count:
			targets.append(_near[i])
		_near.clear()
	for enemy in targets:
		if is_instance_valid(enemy) and _enemies.has(enemy) and not (enemy_side and projectiles.target_owner_of(enemy) == caster):
			_apply_to_enemy(player, enemy, position, profile, profile.damage, profile.knockback, KIND_BURST)
	targets.clear()
	var friendly: bool = projectiles != null and projectiles.friendly_fire
	for index in PLAYER_SLOTS:
		var wizard: Node2D = _players[index]
		if wizard == null or not is_instance_valid(wizard) or _is_downed(wizard):
			continue
		var reach: float = radius + _player_radius[index]
		if (_position_of(wizard) + _player_offset[index]).distance_squared_to(position) > reach * reach:
			continue
		if enemy_side and profile.heal > 0:
			continue
		if not enemy_side and index != player and not friendly and profile.heal <= 0:
			continue
		_apply_to_wizard(player, index, position, profile, profile.damage, profile.knockback, KIND_BURST)
	_tag = saved_tag
	_area_depth -= 1


## A barrier on the wizard `index` (`wizard_shield_requested`): `charges` more blocked hits for
## `seconds` (at least WIZARD_SHIELD_MIN_TIME). Charges add up; the longer time is kept.
func give_wizard_shield(index: int, charges: int, seconds: float, tag: int = 0) -> void:
	if index < 0 or index >= PLAYER_SLOTS or charges <= 0:
		return
	var wizard: Node2D = _players[index]
	if wizard != null and is_instance_valid(wizard) and _is_downed(wizard):
		return
	_w_shield[index] = (_w_shield[index] if _w_shield_left[index] > 0.0 else 0) + charges
	_w_shield_left[index] = maxf(_w_shield_left[index], maxf(seconds, WIZARD_SHIELD_MIN_TIME))
	_w_shield_tag[index] = tag


func _on_wizard_shield_requested(player: int, charges: int, seconds: float, tag: int) -> void:
	give_wizard_shield(player, charges, seconds, tag)


## Hits the barrier on the wizard `index` still blocks; 0 when none.
func wizard_shield(index: int) -> int:
	if index < 0 or index >= PLAYER_SLOTS or _w_shield_left[index] <= 0.0:
		return 0
	return _w_shield[index]


func _on_pull_requested(player: int, position: Vector2, radius: float, strength: float, _tag_of_card: int) -> void:
	pull(player, position, radius, strength)


## Pull every enemy within `radius` of `position` toward it at `strength` pixels per second,
## through the knockback velocity combat keeps (whoever moves the enemy already adds it). A pull
## replaces the push an enemy had, so a magnet each step does not pile speed up. Wizards are not
## pulled. `player` is who pulls (for the record; a pull does no damage).
func pull(_player: int, position: Vector2, radius: float, strength: float) -> void:
	if projectiles == null or strength <= 0.0:
		return
	var count: int = projectiles.targets_in(position, radius, ProjectileManagerScript.LAYER_ENEMY, _near)
	for i in count:
		var near: Node2D = _near[i]
		var at: int = _enemies.find(near)
		if at < 0:
			continue
		var toward: Vector2 = (position - (_position_of(near) + _hurt_offset[at])).normalized()
		_knock[at] = toward * strength
		_slam[at] = 0
	_near.clear()


## Count a heavy hit's slam: an enemy knocked fast into a wall (a step ahead of it) takes the
## damage once. Rows are collected here and hit after the loop, as hits can remove rows.
func _check_slam(row: int) -> void:
	if _slam[row] <= 0:
		return
	var speed: float = _knock[row].length()
	if speed < SLAM_MIN_SPEED:
		_slam[row] = 0
		return
	if projectiles == null:
		return
	var from: Vector2 = _position_of(_enemies[row]) + _hurt_offset[row]
	var to: Vector2 = from + _knock[row] / speed * (_hurt_radius[row] + SLAM_REACH)
	if projectiles.clip_to_walls(from, to) != to:
		_slam_due_enemy.append(_enemies[row])
		_slam_due_player.append(_slam_player[row])
		_slam_due_amount.append(_slam[row])
		_slam[row] = 0


## A slam is not the spell's own hit: no tag, so it sends no `kill_landed`.
func _send_slams() -> void:
	var saved_tag: int = _tag
	_tag = 0
	var sent: int = 0
	while sent < _slam_due_enemy.size():
		if is_instance_valid(_slam_due_enemy[sent]):
			_hit(_slam_due_player[sent], _slam_due_enemy[sent], maxi(_slam_due_amount[sent], 1), Vector2.ZERO, 0.0, false, KIND_REACTION)
		sent += 1
	_tag = saved_tag
	_slam_due_enemy.clear()
	_slam_due_player.clear()
	_slam_due_amount.clear()


## Put `status_id` on the wizard `index` like `apply_status` does on an enemy (same numbers, same
## stacking: three chills freeze), credited to `player`. A downed wizard takes none. Sends
## `status_applied`. Burn hurts as damage over time (kind `status`, past barriers), chill and
## freeze slow (`wizard_speed_factor`, read by `gameplay/player`), a hex adds damage to hits the
## wizard takes, a shock adds its share to the next hit and is spent, and a static wizard
## discharges that share of the next hit to the enemies near.
func apply_wizard_status(player: int, index: int, status_id: StringName, duration: float, strength: float) -> bool:
	if index < 0 or index >= PLAYER_SLOTS or duration <= 0.0:
		return false
	var wizard: Node2D = _players[index]
	if wizard == null or not is_instance_valid(wizard) or _is_downed(wizard):
		return false
	var froze: bool = false
	match status_id:
		BURN:
			if _w_burn_left[index] <= 0.0:
				_w_burn_rate[index] = 0.0
				_w_burn_carry[index] = 0.0
			_w_burn_left[index] = maxf(_w_burn_left[index], duration)
			_w_burn_rate[index] = maxf(_w_burn_rate[index], strength)
			_w_burn_player[index] = player
		CHILL:
			if _w_freeze_left[index] > 0.0:
				return false
			_w_chill_left[index] = maxf(_w_chill_left[index], duration)
			_w_chill_slow[index] = maxf(_w_chill_slow[index], clampf(strength / 100.0, 0.0, CHILL_SLOW_MAX))
			_w_chill_stacks[index] += 1
			if _w_chill_stacks[index] >= CHILL_STACKS_TO_FREEZE:
				_w_chill_left[index] = 0.0
				_w_chill_slow[index] = 0.0
				_w_chill_stacks[index] = 0
				_w_freeze_left[index] = FREEZE_TIME
				froze = true
		SHOCK:
			_w_shock_left[index] = maxf(_w_shock_left[index], duration)
			_w_shock_share[index] = maxf(_w_shock_share[index], strength)
		HEX:
			_w_hex_left[index] = maxf(_w_hex_left[index], duration)
			_w_hex_extra[index] = maxf(_w_hex_extra[index], strength)
		STATIC:
			_w_static_left[index] = maxf(_w_static_left[index], duration)
			_w_static_share[index] = maxf(_w_static_share[index], strength)
		_:
			push_warning("Combat: unknown status '%s'." % status_id)
			return false
	if events != null:
		events.status_applied.emit(player, wizard, status_id)
		if froze:
			events.status_applied.emit(player, wizard, FREEZE)
	return true


## Seconds left of `status_id` on the wizard `index`; 0 when off.
func wizard_status_left(index: int, status_id: StringName) -> float:
	if index < 0 or index >= PLAYER_SLOTS:
		return 0.0
	match status_id:
		BURN:
			return _w_burn_left[index]
		CHILL:
			return _w_chill_left[index]
		FREEZE:
			return _w_freeze_left[index]
		SHOCK:
			return _w_shock_left[index]
		HEX:
			return _w_hex_left[index]
		STATIC:
			return _w_static_left[index]
	return 0.0


## For the node that moves the wizard `index`: the share of normal pace to keep (1.0 free, less
## when chilled, 0.0 when frozen).
func wizard_speed_factor(index: int) -> float:
	if index < 0 or index >= PLAYER_SLOTS:
		return 1.0
	if _w_freeze_left[index] > 0.0:
		return 0.0
	if _w_chill_left[index] > 0.0:
		return 1.0 - _w_chill_slow[index]
	return 1.0


## For the node that moves the wizard `index`: the push (pixels per second) to add to its
## movement this frame, from hits on the wizard, fading like an enemy's. Zero when none.
func consume_wizard_knockback(index: int, delta: float) -> Vector2:
	if index < 0 or index >= PLAYER_SLOTS:
		return Vector2.ZERO
	var push: Vector2 = _w_knock[index]
	if push != Vector2.ZERO:
		_w_knock[index] = push.move_toward(Vector2.ZERO, KNOCKBACK_DECAY * delta)
	return push


func _tick_wizard(index: int, delta: float) -> void:
	if _w_shield_left[index] > 0.0:
		_w_shield_left[index] = maxf(_w_shield_left[index] - delta, 0.0)
		if _w_shield_left[index] == 0.0:
			_w_shield[index] = 0
	if _w_burn_left[index] > 0.0:
		var burned: float = minf(delta, _w_burn_left[index])
		_w_burn_left[index] -= burned
		_w_burn_carry[index] += _w_burn_rate[index] * burned
		var whole: int = int(_w_burn_carry[index])
		if whole > 0:
			_w_burn_carry[index] -= float(whole)
			var wizard: Node2D = _players[index]
			if wizard != null and is_instance_valid(wizard):
				_hit_player(_w_burn_player[index], wizard, whole, Vector2.ZERO, 0.0, KIND_STATUS, null)
	if _w_chill_left[index] > 0.0:
		_w_chill_left[index] = maxf(_w_chill_left[index] - delta, 0.0)
		if _w_chill_left[index] == 0.0:
			_w_chill_slow[index] = 0.0
			_w_chill_stacks[index] = 0
	_w_freeze_left[index] = maxf(_w_freeze_left[index] - delta, 0.0)
	_w_shock_left[index] = maxf(_w_shock_left[index] - delta, 0.0)
	_w_hex_left[index] = maxf(_w_hex_left[index] - delta, 0.0)
	_w_static_left[index] = maxf(_w_static_left[index] - delta, 0.0)
	_w_react_wait[index] = maxf(_w_react_wait[index] - delta, 0.0)


func _clear_wizard(index: int) -> void:
	_w_knock[index] = Vector2.ZERO
	_w_burn_left[index] = 0.0
	_w_burn_rate[index] = 0.0
	_w_burn_carry[index] = 0.0
	_w_chill_left[index] = 0.0
	_w_chill_slow[index] = 0.0
	_w_chill_stacks[index] = 0
	_w_freeze_left[index] = 0.0
	_w_shock_left[index] = 0.0
	_w_shock_share[index] = 0.0
	_w_hex_left[index] = 0.0
	_w_hex_extra[index] = 0.0
	_w_static_left[index] = 0.0
	_w_static_share[index] = 0.0
	_w_shield[index] = 0
	_w_shield_left[index] = 0.0
	_w_react_wait[index] = 0.0


## Why the wizard `index` went down, in plain words, for the screen: "downed by your own Blast"
## when their own spell did it, "downed by player 2's Frost Nova" for a teammate's, and an empty
## string for an enemy or when nothing is known. Read it when `player_downed` arrives.
func downed_note(index: int) -> String:
	if index < 0 or index >= PLAYER_SLOTS:
		return ""
	var who: int = _w_last_player[index]
	if who < 0 or who >= PLAYER_SLOTS:
		return ""
	var what: String = _w_last_name[index]
	if what.is_empty():
		what = KIND_NAMES.get(_w_last_kind[index], "spell") as String
	if who == index:
		return "downed by your own %s" % what
	return "downed by player %d's %s" % [who + 1, what]


## The wizard registered as player `index`, or null.
func wizard_of(index: int) -> Node2D:
	if index < 0 or index >= PLAYER_SLOTS:
		return null
	var wizard: Node2D = _players[index]
	return wizard if wizard != null and is_instance_valid(wizard) else null


func _position_of(node: Node2D) -> Vector2:
	return node.global_position if node.is_inside_tree() else node.position
