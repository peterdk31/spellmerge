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
## Nothing here allocates per hit or per frame: enemies are rows in packed arrays.
## Players are told only through `damage_dealt`; wizards are not pushed (their
## movement is theirs), only enemies are. Listeners of `damage_dealt` and
## `enemy_died` may call hit(), register_enemy() or unregister_enemy(): contact
## hits are sent after the enemy loop, and hit() re-checks its row after sending.

const EventsScript := preload("res://core/events/events.gd")
const ProjectileManagerScript := preload("res://core/projectiles/projectile_manager.gd")

const PLAYER_SLOTS: int = 4
## Seconds a wizard is safe from contact damage after one contact hit.
const CONTACT_COOLDOWN: float = 1.0
## How fast knockback speed falls, in pixels per second per second.
const KNOCKBACK_DECAY: float = 1200.0

## The event bus and the projectile manager. Only tests set these, before
## adding the node; otherwise the "Events" and "Projectiles" autoloads are used.
var events: EventsScript = null
var projectiles: ProjectileManagerScript = null

# Hit profiles: tag -> damage and knockback strength.
var _profile_damage: Dictionary = {}
var _profile_knockback: Dictionary = {}

# Enemies, one row each.
var _enemies: Array[Node2D] = []
var _health: PackedInt32Array = PackedInt32Array()
var _contact_damage: PackedInt32Array = PackedInt32Array()
var _hurt_radius: PackedFloat32Array = PackedFloat32Array()
var _knock: PackedVector2Array = PackedVector2Array()

# Contact hits waiting to be sent after the enemy loop: wizard index and damage.
var _pending_index: PackedInt32Array = PackedInt32Array()
var _pending_amount: PackedInt32Array = PackedInt32Array()

# Wizards by player index.
var _players: Array = [null, null, null, null]
var _player_radius: PackedFloat32Array = PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
var _contact_left: PackedFloat32Array = PackedFloat32Array([0.0, 0.0, 0.0, 0.0])


func _ready() -> void:
	if events == null:
		events = get_node_or_null("/root/Events") as EventsScript
		if events == null and is_inside_tree():
			push_warning("Combat: the Events autoload is missing, so combat hears and sends nothing.")
	if projectiles == null:
		projectiles = get_node_or_null("/root/Projectiles") as ProjectileManagerScript
	if events != null and not events.projectile_hit.is_connected(_on_projectile_hit):
		events.projectile_hit.connect(_on_projectile_hit)


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
func register_enemy(enemy: Node2D, health: int, hurt_radius: float, contact_damage: int = 0) -> void:
	if enemy == null or health <= 0:
		return
	var at: int = _enemies.find(enemy)
	if at >= 0:
		_health[at] = health
		_hurt_radius[at] = hurt_radius
		_contact_damage[at] = contact_damage
		if projectiles != null:
			projectiles.add_target(enemy, hurt_radius, ProjectileManagerScript.LAYER_ENEMY)
		return
	_enemies.append(enemy)
	_health.append(health)
	_contact_damage.append(contact_damage)
	_hurt_radius.append(hurt_radius)
	_knock.append(Vector2.ZERO)
	if projectiles != null:
		projectiles.add_target(enemy, hurt_radius, ProjectileManagerScript.LAYER_ENEMY)


## Forget `enemy` without killing it (no event).
func unregister_enemy(enemy: Node2D) -> void:
	var at: int = _enemies.find(enemy)
	if at >= 0:
		_remove_enemy_at(at)


## Make wizard `node` (player `index`, 0-3) something enemy contact can hurt.
## `radius` is its hit circle in pixels.
func register_player(index: int, node: Node2D, radius: float) -> void:
	if index < 0 or index >= PLAYER_SLOTS:
		push_warning("Combat: player index %d is not 0-3." % index)
		return
	_players[index] = node
	_player_radius[index] = radius
	_contact_left[index] = 0.0


func unregister_player(index: int) -> void:
	if index >= 0 and index < PLAYER_SLOTS:
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


## The damage pipeline. `player` (or EventsScript.NO_PLAYER) dealt `amount` to
## `target`, pushing it along `direction` (unit length, or zero) at `strength`
## pixels per second. Returns true if the hit counted: it did damage, so
## `damage_dealt` was sent. A hit on an unknown node, a dead target, a dodging
## or downed wizard or for 0 or less does nothing.
func hit(player: int, target: Node, amount: int, direction: Vector2 = Vector2.ZERO, strength: float = 0.0) -> bool:
	if amount <= 0 or target == null or not is_instance_valid(target):
		return false
	var at: int = _enemies.find(target)
	if at < 0:
		return _hit_player(player, target, amount)
	var enemy: Node2D = _enemies[at]
	var where: Vector2 = _position_of(enemy)
	_health[at] = maxi(_health[at] - amount, 0)
	if strength > 0.0:
		_knock[at] = direction * strength
	if events != null:
		events.damage_dealt.emit(player, enemy, amount, where)
		# A listener may have changed the registrations; find the row again.
		at = _enemies.find(enemy)
		if at < 0:
			return true
	if _health[at] == 0:
		_remove_enemy_at(at)
		if events != null:
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
		if _contact_damage[row] > 0:
			_touch_players(row)
	# Send after the loop, so listeners can change registrations safely.
	var sent: int = 0
	while sent < _pending_index.size():
		var wizard: Node2D = _players[_pending_index[sent]]
		if wizard != null and is_instance_valid(wizard) and events != null:
			events.damage_dealt.emit(EventsScript.NO_PLAYER, wizard, _pending_amount[sent], _position_of(wizard))
		sent += 1
	_pending_index.clear()
	_pending_amount.clear()


func _touch_players(row: int) -> void:
	var enemy_at: Vector2 = _position_of(_enemies[row])
	for index in PLAYER_SLOTS:
		if _players[index] == null or _contact_left[index] > 0.0:
			continue
		if not is_instance_valid(_players[index]):
			_players[index] = null
			continue
		var wizard: Node2D = _players[index]
		var reach: float = _hurt_radius[row] + _player_radius[index]
		if enemy_at.distance_squared_to(_position_of(wizard)) > reach * reach:
			continue
		if _can_hurt_player(wizard):
			_contact_left[index] = CONTACT_COOLDOWN
			_pending_index.append(index)
			_pending_amount.append(_contact_damage[row])


## A wizard decides for itself how much it is hurt; Combat only skips the event
## for hits it knows do nothing (the wizard is dodging or downed), and for
## nodes that are not registered wizards.
func _hit_player(player: int, target: Node, amount: int) -> bool:
	if not _can_hurt_player(target):
		return false
	if events != null:
		events.damage_dealt.emit(player, target, amount, _position_of(target as Node2D))
	return true


func _can_hurt_player(target: Node) -> bool:
	if not target is Node2D or not _players.has(target):
		return false
	if target.has_method("is_invulnerable") and target.is_invulnerable():
		return false
	if target.has_method("is_downed") and target.is_downed():
		return false
	return true


func _on_projectile_hit(player: int, target: Node, position: Vector2, tag: int) -> void:
	if not _profile_damage.has(tag) or not target is Node2D:
		return
	var direction: Vector2 = (_position_of(target as Node2D) - position).normalized()
	hit(player, target, _profile_damage[tag] as int, direction, _profile_knockback[tag] as float)


func _remove_enemy_at(at: int) -> void:
	if projectiles != null and is_instance_valid(_enemies[at]):
		projectiles.remove_target(_enemies[at])
	_enemies.remove_at(at)
	_health.remove_at(at)
	_contact_damage.remove_at(at)
	_hurt_radius.remove_at(at)
	_knock.remove_at(at)


func _position_of(node: Node2D) -> Vector2:
	return node.global_position if node.is_inside_tree() else node.position
