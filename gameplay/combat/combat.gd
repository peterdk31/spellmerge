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
## jumps to a neighbour found with the projectile manager's target grid. A spell's hit comes
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

const PLAYER_SLOTS: int = 4
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
## The statuses a reaction can start from, in the order they are looked at.
const REACTING_STATUSES: Array[StringName] = [BURN, CHILL, SHOCK, HEX]
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

# Hit profiles: tag -> damage and knockback strength.
var _profile_damage: Dictionary = {}
var _profile_knockback: Dictionary = {}
# Spell ids whose hit profile was already read after a `spell_cast`.
var _profiled_spells: Dictionary = {}

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


func _ready() -> void:
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
		if not events.spell_cast.is_connected(_on_spell_cast):
			events.spell_cast.connect(_on_spell_cast)
		if not events.player_downed.is_connected(_on_player_downed):
			events.player_downed.connect(_on_player_downed)
		if not events.player_revived.is_connected(_on_player_revived):
			events.player_revived.connect(_on_player_revived)


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
	_react_wait.append(0.0)
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
func hit(player: int, target: Node, amount: int, direction: Vector2 = Vector2.ZERO, strength: float = 0.0) -> bool:
	return _hit(player, target, amount, direction, strength, false)


## hit() with a switch: a `quiet` hit (burn ticks) takes the whole pipeline, deaths
## included, but sends no `damage_dealt` for an enemy that survives, so Feel and the
## AI do not stutter, shake or flinch twice a second per burning enemy.
func _hit(player: int, target: Node, amount: int, direction: Vector2, strength: float, quiet: bool) -> bool:
	if amount <= 0 or target == null or not is_instance_valid(target):
		return false
	var at: int = _enemies.find(target)
	if at < 0:
		return _hit_player(player, target, amount)
	var enemy: Node2D = _enemies[at]
	var where: Vector2 = _position_of(enemy)
	if _hex_left[at] > 0.0:
		amount += roundi(float(amount) * _hex_extra[at] / 100.0)
	_health[at] = maxi(_health[at] - amount, 0)
	if strength > 0.0:
		_knock[at] = direction * strength
	if events != null and not (quiet and _health[at] > 0):
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
		_tick_statuses(row, delta)
		if _contact_damage[row] > 0:
			_touch_players(row)
	_send_burns()
	# Send after the loop, so listeners can change registrations safely.
	var sent: int = 0
	while sent < _pending_index.size():
		var wizard: Node2D = _players[_pending_index[sent]]
		if wizard != null and is_instance_valid(wizard) and events != null:
			events.damage_dealt.emit(EventsScript.NO_PLAYER, wizard, _pending_amount[sent], _position_of(wizard))
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
	_react_wait[row] = maxf(_react_wait[row] - delta, 0.0)


## Deal the burn damage counted this step. After the loop, because hit() can remove rows.
func _send_burns() -> void:
	var sent: int = 0
	while sent < _due_enemy.size():
		if is_instance_valid(_due_enemy[sent]):
			_hit(_due_player[sent], _due_enemy[sent], _due_amount[sent], Vector2.ZERO, 0.0, true)
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


func _is_downed(node: Node) -> bool:
	return node.has_method("is_downed") and node.is_downed()


func _on_player_downed(player: int) -> void:
	if projectiles != null and player >= 0 and player < PLAYER_SLOTS:
		var wizard: Node2D = _players[player]
		if wizard != null and is_instance_valid(wizard):
			projectiles.remove_target(wizard)


func _on_player_revived(player: int, _reviver: int) -> void:
	if projectiles != null and player >= 0 and player < PLAYER_SLOTS:
		var wizard: Node2D = _players[player]
		if wizard != null and is_instance_valid(wizard):
			projectiles.add_target(wizard, _player_radius[player], ProjectileManagerScript.LAYER_PLAYER, player, _player_offset[player])


## The first time a spell is cast, ask it (through the registry) what its shots do and
## keep that as a hit profile. Content never calls Combat; the spell only answers.
func _on_spell_cast(_player: int, spell_id: StringName, _origin: Vector2, _direction: Vector2) -> void:
	if registry == null or _profiled_spells.has(spell_id):
		return
	var spell: SpellBase = registry.get_resource(&"spells", spell_id) as SpellBase
	if spell == null:
		return
	_profiled_spells[spell_id] = true
	var tag: int = spell.hit_tag()
	if tag != 0:
		set_hit_profile(tag, spell.hit_damage(), spell.hit_knockback())


## A shot landed. A spell's shot is described by `Spells.hit_profile(tag)` (damage, knockback,
## status); any other shot (an enemy's, or M1's bolt) by the table of `set_hit_profile`. A
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
	var enemy: Node2D = target as Node2D
	var direction: Vector2 = (_position_of(enemy) - position).normalized()
	var at: int = _enemies.find(enemy)
	var jump_share: float = 0.0
	var jump_from: Vector2 = Vector2.ZERO
	if at >= 0:
		if _hex_left[at] > 0.0:
			direction = -direction
			strength *= HEX_PULL_SHARE
		if _shock_left[at] > 0.0:
			jump_share = _shock_share[at]
			jump_from = _position_of(enemy) + _hurt_offset[at]
	# The reaction is chosen from the statuses the target had when the shot arrived.
	var reaction: ReactionRow = null
	if at >= 0 and profile != null and profile.element_id != &"" and _react_wait[at] <= 0.0:
		reaction = _reaction_for(at, profile.element_id)
	if not hit(player, enemy, damage, direction, strength):
		return
	var spent: int = _enemies.find(enemy)
	if spent >= 0:
		_shock_left[spent] = 0.0
		_shock_share[spent] = 0.0
	if jump_share > 0.0:
		_shock_jump(player, enemy, jump_from, roundi(float(damage) * jump_share / 100.0))
	if reaction != null:
		# The reaction runs instead of the hit's own status, and only on a target that lived.
		_react(player, enemy, reaction)
	elif profile != null and profile.status_id != &"" and is_instance_valid(enemy):
		apply_status(player, enemy, profile.status_id, profile.status_duration, profile.status_strength)


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
		at = _enemies.find(enemy)
		if at < 0:
			return
	match row.effect:
		ReactionRow.Effect.CONSUME:
			var amount: int = row.damage
			if _freeze_left[at] > 0.0:
				amount *= FROZEN_BONUS
				_remove_status(at, CHILL)
			_remove_status(at, row.status_id)
			hit(player, enemy, amount)
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
		hit(player, enemy, row.damage)
		return
	var count: int = projectiles.targets_in(centre, row.radius, ProjectileManagerScript.LAYER_ENEMY, _near)
	for i in count:
		var near: Node2D = _near[i]
		if not is_instance_valid(near):
			continue
		var toward: Vector2 = (centre - _position_of(near)).normalized() if row.pull > 0.0 else Vector2.ZERO
		hit(player, near, row.damage, toward, row.pull)
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


## The hit on `from_enemy` jumps from `from` to the nearest other enemy in reach, for `amount`
## (at least 1). The jump pushes nothing and puts on no status.
func _shock_jump(player: int, from_enemy: Node2D, from: Vector2, amount: int) -> void:
	if projectiles == null:
		return
	var next: Node2D = projectiles.nearest_target(from, SHOCK_JUMP_RANGE, ProjectileManagerScript.LAYER_ENEMY, from_enemy)
	if next != null:
		hit(player, next, maxi(amount, 1))


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
	_react_wait.remove_at(at)


func _position_of(node: Node2D) -> Vector2:
	return node.global_position if node.is_inside_tree() else node.position
