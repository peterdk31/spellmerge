extends RefCounted
## A small world for the swarm's tests (docs/milestones/horde-swarm.md, S1): its own event bus,
## actor table, projectile manager, Spells (a stand-in registry with a plain bolt and the real
## elements, so a hit carries a real compiled profile) and Combat, a world in the tree with a
## `Horde` node, and a swarm (`swarm.gd`) on a floor round the origin. Wizards are actors made
## from the real wizard scene, standing still. Everything is stepped only by hand (`run`).
## `free_all()` frees everything.

const SwarmScript := preload("res://gameplay/horde/swarm.gd")
const CombatScript := preload("res://gameplay/combat/combat.gd")
const EventsScript := preload("res://core/events/events.gd")
const ProjectileManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const SpellsScript := preload("res://core/spells/spells.gd")
const ActorsScript := preload("res://core/actors/actors.gd")
const StaffKit := preload("res://tests/support/staff_kit.gd")
const WizardScene := preload("res://content/wizard/base/wizard.tscn")
const MiteData: EnemyBase = preload("res://content/enemies/crypt_mite/crypt_mite.tres")
const HuskData: EnemyBase = preload("res://content/enemies/bone_husk/bone_husk.tres")

## Time moves by this fixed binary fraction.
const STEP: float = 0.0625
## The floor the swarm keeps its swarmers on.
const ARENA: Rect2 = Rect2(-480.0, -280.0, 960.0, 560.0)
const ELEMENTS: Array[StringName] = [&"fire", &"frost", &"storm", &"void", &"lightning"]
## The plain bolt's damage.
const BOLT_DAMAGE: int = 4


## The registry questions the director asks (the swarmers' data and the cards).
class FakeRegistry:
	extends "res://core/registry/registry.gd"
	var folders: Dictionary = {}

	func _ready() -> void:
		pass

	func get_resource(folder: StringName, id: StringName) -> Resource:
		var found: Dictionary = folders.get(folder, {})
		return found.get(id)

	func get_ids(folder: StringName) -> Array[StringName]:
		var out: Array[StringName] = []
		out.assign((folders.get(folder, {}) as Dictionary).keys())
		return out


var bus: EventsScript
var actors: ActorsScript
var projectiles: ProjectileManagerScript
var registry: FakeRegistry
var spells: SpellsScript
var combat: CombatScript
var swarm: SwarmScript
var world: Node2D
var horde: Node2D
var wizards: Array[Actor] = []
var _root: Node


func _init(root: Node) -> void:
	_root = root
	bus = EventsScript.new()
	actors = ActorsScript.new()
	projectiles = ProjectileManagerScript.new()
	projectiles.events = bus
	projectiles.actors = actors
	registry = FakeRegistry.new()
	var cards: Dictionary = {}
	var bolt := FormBase.new()
	bolt.id = &"bolt"
	bolt.base_damage = BOLT_DAMAGE
	bolt.speed = 200.0
	bolt.lifetime = 1.0
	cards[&"bolt"] = bolt
	for element in ELEMENTS:
		cards[element] = load("res://content/spells/elements/%s/%s.tres" % [element, element])
	registry.folders[&"spells"] = cards
	registry.folders[&"enemies"] = {MiteData.id: MiteData, HuskData.id: HuskData}
	spells = SpellsScript.new()
	spells.registry = _SpellsRegistry.new(cards)
	spells.actors = actors
	spells.bind(projectiles, bus)
	combat = CombatScript.new()
	combat.events = bus
	combat.projectiles = projectiles
	combat.spells = spells
	combat.actors = actors
	combat._ready()
	world = Node2D.new()
	world.name = "World"
	root.add_child(world)
	horde = Node2D.new()
	horde.name = "Horde"
	world.add_child(horde)
	swarm = SwarmScript.new()
	swarm.events = bus
	swarm.combat = combat
	swarm.projectiles = projectiles
	swarm.actors = actors
	swarm.entities = null
	swarm.rng.seed = 11
	swarm.start(horde, ARENA)


## Spells asks its registry for cards by id alone.
class _SpellsRegistry:
	extends Node
	var items: Dictionary = {}

	func _init(cards: Dictionary) -> void:
		items = cards

	func get_resource(_folder: StringName, id: StringName) -> Resource:
		return items.get(id)


## The kind of `data` (the mite by default), prepared.
static func kind(data: EnemyBase = MiteData) -> SwarmKind:
	return SwarmScript.kind_for(data)


## A swarmer of `data` at `at`; its node.
func swarmer(at: Vector2, data: EnemyBase = MiteData) -> Node2D:
	var row: int = swarm.spawn(kind(data), at)
	return swarm.nodes[row] if row >= 0 else null


## A wizard of seat `seat` (the real scene, its own actor id), standing at `at`.
func wizard(at: Vector2, seat: int = 0) -> Actor:
	var body := WizardScene.instantiate() as Actor
	PlayerController.seat_wizard(body, seat, null, [[], [], [], []])
	body.events = bus
	body.combat = combat
	body.projectiles = projectiles
	body.spells = spells
	body.actors = actors
	body.position = at
	world.add_child(body)
	body.set_physics_process(false)
	wizards.append(body)
	return body


## The tag of a bolt of `element` (&"" for none) built into `caster`'s first staff.
func tag(caster: int, element: StringName = &"") -> int:
	var recipe: Dictionary = {"form": &"bolt"}
	if element != &"":
		recipe["element"] = element
	return StaffKit.build(spells, caster, 0, StaffKit.cards(recipe))


## A shot of `shot_tag` from `caster` hits `target` from its left, as the projectile manager
## reports a hit.
func hit(caster: int, target: Node2D, shot_tag: int) -> void:
	projectiles.step(STEP)
	bus.projectile_hit.emit(caster, target, target.global_position + Vector2(-8.0, 0.0), shot_tag, -1)


## `seconds` of physics steps: the swarm, then Combat, the projectiles and Spells.
func run(seconds: float) -> void:
	for i in roundi(seconds / STEP):
		swarm.step(STEP)
		combat.step(STEP)
		projectiles.step(STEP)
		spells.step(STEP)


## A wall body on the wall layer covering `rect` (world space).
func wall(rect: Rect2) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.collision_layer = 1
	var shape := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = rect.size
	shape.shape = box
	shape.position = rect.get_center()
	body.add_child(shape)
	world.add_child(body)
	return body


func free_all() -> void:
	swarm.stop()
	for body in wizards:
		if is_instance_valid(body):
			body.free()
	wizards.clear()
	if is_instance_valid(world):
		_root.remove_child(world)
		world.free()
	for node: Node in [combat, spells, spells.registry if spells != null else null, registry, projectiles, actors, bus]:
		if node != null and is_instance_valid(node):
			node.free()
