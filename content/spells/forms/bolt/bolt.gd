extends SpellBase
## The fire bolt (M1): one shot in the facing direction. The only code besides
## `core/base` that knows the spell's fields. Players and bots just call cast().
##
## The shot is a row in `core/projectiles` (its packed arrays are the fixed-size
## pool; nothing is allocated per cast). What the shot does on a hit is not told to
## `gameplay/combat` from here: Combat hears `spell_cast` and asks the spell through
## hit_tag(), hit_damage() and hit_knockback().

const ProjectileManagerScript := preload("res://core/projectiles/projectile_manager.gd")

## The tag of every bolt shot; Combat maps it to damage and knockback.
const BOLT_TAG: int = 1
## Hit circle of the shot in pixels.
const SHOT_RADIUS: float = 4.0
## Knockback strength in pixels per second.
const KNOCKBACK: float = 120.0

## The projectile manager. Only tests set it; otherwise the "Projectiles" autoload is
## looked up on the first cast and kept.
var projectiles: ProjectileManagerScript = null

# Note: the cooldowns (in SpellBase) live on this one resource, which the registry shares
# between all holders, so `flow` must call `reset_cooldowns()` on a new run.


func hit_tag() -> int:
	return BOLT_TAG


func hit_knockback() -> float:
	return KNOCKBACK


func _fire(player: int, origin: Vector2, direction: Vector2) -> bool:
	if projectiles == null or not is_instance_valid(projectiles):
		var tree: SceneTree = Engine.get_main_loop() as SceneTree
		if tree != null:
			projectiles = tree.root.get_node_or_null("Projectiles") as ProjectileManagerScript
	if projectiles == null:
		push_warning("Bolt: the Projectiles autoload is missing, so nothing was fired.")
		return false
	var aim: Vector2 = direction.normalized() if direction != Vector2.ZERO else Vector2.RIGHT
	var row: int = projectiles.spawn(player, origin, aim * speed, lifetime, SHOT_RADIUS, ProjectileManagerScript.LAYER_ENEMY, 0, BOLT_TAG)
	return row >= 0
