extends RefCounted
## A small world for the enemy tests: its own event bus, projectile manager, Spells (with the
## real cards, from a scanned registry) and Combat, a number of wizards, and imps made from the
## real scene and data (staffs F9: the imp casts its staff). `free_all()` frees everything, so a
## test that builds a world with this leaves nothing behind.

const AiScript := preload("res://gameplay/ai/ai.gd")
const CombatScript := preload("res://gameplay/combat/combat.gd")
const EventsScript := preload("res://core/events/events.gd")
const PlayerScript := preload("res://gameplay/player/player.gd")
const ProjectileManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const RegistryScript := preload("res://core/registry/registry.gd")
const SpellsScript := preload("res://core/spells/spells.gd")
const ImpData := preload("res://content/enemies/ember_imp/ember_imp.tres")

## Time moves by this fixed binary fraction.
const STEP: float = 0.0625

var bus: Node
var combat: Node
var projectiles: Node
var registry: Node
var spells: Node
var enemies: Array[AiScript] = []
var players: Array[PlayerScript] = []
var _root: Node


## `player_count` wizards are added to `root` (they must be in the tree to be hit).
func _init(root: Node, player_count: int = 1) -> void:
	_root = root
	bus = EventsScript.new()
	projectiles = ProjectileManagerScript.new()
	projectiles.events = bus
	registry = RegistryScript.new()
	registry.call("scan")
	spells = SpellsScript.new()
	spells.set("registry", registry)
	spells.call("bind", projectiles, bus)
	combat = CombatScript.new()
	combat.events = bus
	combat.projectiles = projectiles
	combat.spells = spells
	combat._ready()
	for index in player_count:
		var wizard := PlayerScript.new()
		wizard.index = index
		wizard.events = bus
		root.add_child(wizard)
		wizard.position = Vector2(1000.0, 1000.0 * index)
		players.append(wizard)
		combat.register_player(index, wizard, 8.0, Vector2(0.0, -12.0))


## An imp made from the real scene (sprite, telegraph, poses) that chases every wizard.
func imp(at: Vector2 = Vector2.ZERO) -> AiScript:
	var enemy: AiScript = ImpData.scene.instantiate()
	enemy.data = ImpData
	enemy.position = at
	enemy.events = bus
	enemy.combat = combat
	enemy.projectiles = projectiles
	enemy.spells = spells
	for wizard in players:
		enemy.targets.append(wizard)
	enemy._ready()
	enemies.append(enemy)
	return enemy


## One imp with the first wizard `distance` px to its right, in range to wind up.
func imp_facing_player(distance: float = 80.0) -> AiScript:
	players[0].position = Vector2(distance, 0.0)
	return imp()


## `count` physics frames: the AI, then the body moves, then Combat, the projectiles and Spells.
func run(enemy: AiScript, count: int) -> void:
	for i in count:
		enemy.step(STEP)
		enemy.position += enemy.velocity * STEP
		combat.step(STEP)
		projectiles.step(STEP)
		spells.call("step", STEP)


func free_all() -> void:
	for enemy in enemies:
		if is_instance_valid(enemy):
			enemy.free()
	enemies.clear()
	for wizard in players:
		if is_instance_valid(wizard):
			wizard.free()
	players.clear()
	for node: Node in [combat, spells, registry, projectiles, bus]:
		if node != null:
			node.free()
	combat = null
	spells = null
	registry = null
	projectiles = null
	bus = null
