extends RefCounted
## A small world for the enemy tests: its own event bus, projectile manager and Combat, a
## number of wizards, and imps made from the real scene. `free_all()` frees everything, so a
## test that builds a world with this leaves nothing behind.

const AiScript := preload("res://gameplay/ai/ai.gd")
const CombatScript := preload("res://gameplay/combat/combat.gd")
const EventsScript := preload("res://core/events/events.gd")
const PlayerScript := preload("res://gameplay/player/player.gd")
const ProjectileManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const ImpData := preload("res://content/enemies/ember_imp/ember_imp.tres")

## Time moves by this fixed binary fraction.
const STEP: float = 0.0625

var bus: Node
var combat: Node
var projectiles: Node
var enemies: Array[AiScript] = []
var players: Array[PlayerScript] = []
var _root: Node


## `player_count` wizards are added to `root` (they must be in the tree to be hit).
func _init(root: Node, player_count: int = 1) -> void:
	_root = root
	bus = EventsScript.new()
	projectiles = ProjectileManagerScript.new()
	projectiles.events = bus
	combat = CombatScript.new()
	combat.events = bus
	combat.projectiles = projectiles
	combat._ready()
	for index in player_count:
		var wizard := PlayerScript.new()
		wizard.index = index
		wizard.events = bus
		root.add_child(wizard)
		wizard.position = Vector2(1000.0, 1000.0 * index)
		players.append(wizard)
		combat.register_player(index, wizard, 8.0)


## An imp made from the real scene (sprite, telegraph, poses) that chases every wizard.
func imp(at: Vector2 = Vector2.ZERO) -> AiScript:
	var enemy: AiScript = ImpData.scene.instantiate()
	enemy.data = ImpData
	enemy.position = at
	enemy.events = bus
	enemy.combat = combat
	enemy.projectiles = projectiles
	for wizard in players:
		enemy.targets.append(wizard)
	enemy._ready()
	enemies.append(enemy)
	return enemy


## One imp with the first wizard `distance` px to its right, in range to wind up.
func imp_facing_player(distance: float = 80.0) -> AiScript:
	players[0].position = Vector2(distance, 0.0)
	return imp()


## `count` physics frames: the AI, then the body moves, then Combat and the projectiles.
func run(enemy: AiScript, count: int) -> void:
	for i in count:
		enemy.step(STEP)
		enemy.position += enemy.velocity * STEP
		combat.step(STEP)
		projectiles.step(STEP)


func free_all() -> void:
	for enemy in enemies:
		if is_instance_valid(enemy):
			enemy.free()
	enemies.clear()
	for wizard in players:
		if is_instance_valid(wizard):
			wizard.free()
	players.clear()
	for node: Node in [combat, projectiles, bus]:
		if node != null:
			node.free()
	combat = null
	projectiles = null
	bus = null
