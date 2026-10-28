extends RefCounted
## A small world for the enemy tests: its own event bus, actor table (`actors`, which the services,
## the wizards and the imps use instead of the autoload), projectile manager, Spells (with the
## real cards, from a scanned registry) and Combat, a number of wizards, and imps: actors made from
## the real scene and data (actors G6: an Actor with Health, Hurtbox, Contact, Mover, Caster, its
## AIController and CreatureLook), in the tree and stepped only by hand. `free_all()` frees
## everything, so a test that builds a world with this leaves nothing behind.

const CombatScript := preload("res://gameplay/combat/combat.gd")
const EventsScript := preload("res://core/events/events.gd")
const EntitiesScript := preload("res://gameplay/ai/entities.gd")
const PlayerScript := preload("res://gameplay/player/player.gd")
const ProjectileManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const RegistryScript := preload("res://core/registry/registry.gd")
const SpellsScript := preload("res://core/spells/spells.gd")
const ActorsScript := preload("res://core/actors/actors.gd")
const ImpData := preload("res://content/enemies/ember_imp/ember_imp.tres")

## Time moves by this fixed binary fraction.
const STEP: float = 0.0625

var bus: Node
var actors: ActorsScript
var combat: Node
var projectiles: Node
var registry: Node
var spells: Node
## The decoys the imps ask (`lure`); null leaves the "Entities" autoload, which has none.
var entities: EntitiesScript = null
var enemies: Array[Actor] = []
var players: Array[PlayerScript] = []
var _root: Node


## `player_count` wizards are added to `root` (they must be in the tree to be hit).
func _init(root: Node, player_count: int = 1) -> void:
	_root = root
	bus = EventsScript.new()
	projectiles = ProjectileManagerScript.new()
	projectiles.events = bus
	actors = ActorsScript.new()
	projectiles.actors = actors
	registry = RegistryScript.new()
	registry.call("scan")
	spells = SpellsScript.new()
	spells.set("registry", registry)
	spells.set("actors", actors)
	spells.call("bind", projectiles, bus)
	combat = CombatScript.new()
	combat.events = bus
	combat.projectiles = projectiles
	combat.spells = spells
	combat.set("actors", actors)
	combat._ready()
	for index in player_count:
		var wizard := PlayerScript.new()
		wizard.index = index
		wizard.events = bus
		wizard.actors = actors
		root.add_child(wizard)
		wizard.position = Vector2(1000.0, 1000.0 * index)
		players.append(wizard)
		combat.register_player(index, wizard, 8.0, Vector2(0.0, -12.0))


## An imp from the real scene (sprite, telegraph, poses) with the real data, in the tree at `at`.
func imp(at: Vector2 = Vector2.ZERO, data: EnemyBase = ImpData) -> Actor:
	return enemy(ImpData.scene, data, at)


## An enemy actor of `scene` with `data`, this world's services, in the tree at `at`, stepped
## only by hand.
func enemy(scene: PackedScene, data: EnemyBase, at: Vector2 = Vector2.ZERO) -> Actor:
	var body: Actor = scene.instantiate() as Actor
	body.data = data
	body.position = at
	wire(body)
	_root.add_child(body)
	body.set_physics_process(false)
	enemies.append(body)
	return body


## This world's services on `body` (and its AI's decoys), so the autoloads are not used.
func wire(body: Actor) -> void:
	body.events = bus
	body.combat = combat
	body.projectiles = projectiles
	body.spells = spells
	body.actors = actors
	var mind: AIController = ai(body)
	if mind != null and entities != null:
		mind.entities = entities


## One imp with the first wizard `distance` px to its right, in range to wind up.
func imp_facing_player(distance: float = 80.0) -> Actor:
	players[0].position = Vector2(distance, 0.0)
	return imp()


## The AI in `body`'s scene (its home controller), or null.
static func ai(body: Actor) -> AIController:
	for child in body.get_children():
		if child is AIController:
			return child as AIController
	return null


## The creature look in `body`'s scene, or null.
static func look(body: Actor) -> CreatureLook:
	for child in body.get_children():
		if child is CreatureLook:
			return child as CreatureLook
	return null


## `count` physics frames: the actor, then the body moves, then Combat, the projectiles and
## Spells.
func run(body: Actor, count: int) -> void:
	for i in count:
		body.step(STEP)
		body.position += body.velocity * STEP
		combat.step(STEP)
		projectiles.step(STEP)
		spells.call("step", STEP)


## `count` physics frames of every enemy, then the systems.
func run_all(count: int) -> void:
	for i in count:
		for body in enemies:
			if is_instance_valid(body) and body.is_inside_tree():
				body.step(STEP)
				body.position += body.velocity * STEP
		combat.step(STEP)
		projectiles.step(STEP)
		spells.call("step", STEP)
		if entities != null:
			entities.step(STEP)


func free_all() -> void:
	for body in enemies:
		if is_instance_valid(body):
			body.free()
	enemies.clear()
	for wizard in players:
		if is_instance_valid(wizard):
			wizard.free()
	players.clear()
	for node: Node in [combat, spells, registry, projectiles, actors, bus]:
		if node != null and is_instance_valid(node):
			node.free()
	combat = null
	spells = null
	registry = null
	projectiles = null
	actors = null
	bus = null
