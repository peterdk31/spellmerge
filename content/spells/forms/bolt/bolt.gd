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

var _profiled: CombatScript = null


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
	if fight != null and fight != _profiled:
		fight.set_hit_profile(BOLT_TAG, damage, KNOCKBACK)
		_profiled = fight
	var aim: Vector2 = direction.normalized() if direction != Vector2.ZERO else Vector2.RIGHT
	manager.spawn(player, origin, aim * speed, lifetime, SHOT_RADIUS, ProjectileManagerScript.LAYER_ENEMY, 0, BOLT_TAG)
