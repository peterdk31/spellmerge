extends SpellBase
## The fire bolt (M1): one shot in the facing direction. The only code besides
## `core/base` that knows the spell's fields. Players and bots just call cast().
##
## The shot is a row in `core/projectiles` (its packed arrays are the fixed-size
## pool; nothing is allocated per cast). What the shot does on a hit is told to
## `gameplay/combat` once, as a hit profile for BOLT_TAG.

const ProjectileManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const CombatScript := preload("res://gameplay/combat/combat.gd")

## The tag of every bolt shot; Combat maps it to damage and knockback.
const BOLT_TAG: int = 1
## Hit circle of the shot in pixels.
const SHOT_RADIUS: float = 4.0
## Knockback strength in pixels per second.
const KNOCKBACK: float = 120.0

## The projectile manager and combat. Only tests set these; otherwise the
## "Projectiles" and "Combat" autoloads are used.
var projectiles: ProjectileManagerScript = null
var combat: CombatScript = null

## Instance id of the Combat that has the hit profile (an id, not the node, so a freed
## Combat after a scene reload is just a different id).
var _profiled_id: int = 0

## Note: the cooldowns live on this one resource, which the registry shares between all
## holders, so `flow` must call `reset_cooldowns()` on a new run (or `duplicate()` the spell).


func _fire(player: int, origin: Vector2, direction: Vector2) -> void:
	var manager: ProjectileManagerScript = projectiles
	var fight: CombatScript = combat
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree != null:
		if manager == null:
			manager = tree.root.get_node_or_null("Projectiles") as ProjectileManagerScript
		if fight == null:
			fight = tree.root.get_node_or_null("Combat") as CombatScript
	if manager == null:
		push_warning("Bolt: the Projectiles autoload is missing, so nothing was fired.")
		return
	if fight == null:
		push_warning("Bolt: the Combat autoload is missing, so the shot will deal no damage.")
	elif fight.get_instance_id() != _profiled_id:
		fight.set_hit_profile(BOLT_TAG, damage, KNOCKBACK)
		_profiled_id = fight.get_instance_id()
	var aim: Vector2 = direction.normalized() if direction != Vector2.ZERO else Vector2.RIGHT
	manager.spawn(player, origin, aim * speed, lifetime, SHOT_RADIUS, ProjectileManagerScript.LAYER_ENEMY, 0, BOLT_TAG)
