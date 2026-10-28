extends RefCounted
## A small world for the actor kit's tests (actors G4): its own event bus, projectile manager,
## Spells, Combat and actor table, and actors put together in code from the kit's components with
## a scripted controller (`Scripted`). `free_all()` frees everything.
##
## Spells reads its cards from `registry`: the real one (scanned) by default, or a stand-in with
## cards a test made in code (a `FakeRegistry`; tests may read spell fields, fixtures may not).

const EventsScript := preload("res://core/events/events.gd")
const ProjectilesScript := preload("res://core/projectiles/projectile_manager.gd")
const RegistryScript := preload("res://core/registry/registry.gd")
const SpellsScript := preload("res://core/spells/spells.gd")
const ActorsScript := preload("res://core/actors/actors.gd")
const CombatScript := preload("res://gameplay/combat/combat.gd")

## Time moves by this fixed binary fraction.
const STEP: float = 0.0625


## A controller that wants what a test sets: a walk, an aim, staffs pressed once or held.
class Scripted:
	extends ActorController
	var move: Vector2 = Vector2.ZERO
	var aim: Vector2 = Vector2.ZERO
	## Staffs to press at the next think (each once).
	var presses: Array[int] = []
	var held: Array[int] = []
	var thinks: int = 0
	var started_count: int = 0
	var stopped_count: int = 0

	func think(actor: Actor, _delta: float) -> void:
		thinks += 1
		actor.intent.move = move
		actor.intent.aim = aim
		for staff in presses:
			actor.intent.press(staff)
		presses.clear()
		for staff in ActorIntent.STAFFS:
			actor.intent.hold(staff, held.has(staff))

	func started(_actor: Actor) -> void:
		started_count += 1

	func stopped(_actor: Actor) -> void:
		stopped_count += 1


## Cards made in code, by id.
class FakeRegistry:
	extends Node
	var items: Dictionary = {}

	func get_resource(_folder: StringName, id: StringName) -> Resource:
		return items.get(id)


var bus: EventsScript
var projectiles: ProjectilesScript
var registry: Node
var spells: SpellsScript
var combat: CombatScript
var table: ActorsScript
var actors: Array[Actor] = []
var _root: Node


## A world in `root`; `fake` (a FakeRegistry a test filled) replaces the real registry.
func _init(root: Node, fake: FakeRegistry = null) -> void:
	_root = root
	bus = EventsScript.new()
	projectiles = ProjectilesScript.new()
	projectiles.events = bus
	projectiles.set_bounds(Rect2(-400.0, -400.0, 1040.0, 800.0))
	table = ActorsScript.new()
	if fake != null:
		registry = fake
	else:
		registry = RegistryScript.new()
		registry.call("scan")
	spells = SpellsScript.new()
	spells.registry = registry
	spells.actors = table
	spells.bind(projectiles, bus)
	combat = CombatScript.new()
	combat.events = bus
	combat.projectiles = projectiles
	combat.spells = spells
	combat._ready()


## An actor at `at` with the components named in `kinds` (&"health", &"hurtbox", &"contact",
## &"mover", &"caster"), driven by `controller` (null: none), added to the tree and ready. The
## caster's staffs are `cards` (one row per staff), on a plain staff of no delay unless `staff`.
func actor(at: Vector2, kinds: Array[StringName], controller: ActorController = null, cards: Array = [], staff: StaffBase = null) -> Actor:
	var body := Actor.new()
	body.name = "Actor%d" % actors.size()
	_wire(body)
	if kinds.has(&"health"):
		var health := Health.new()
		health.max_health = 50
		body.add_child(health)
	if kinds.has(&"hurtbox"):
		body.add_child(Hurtbox.new())
	if kinds.has(&"contact"):
		body.add_child(Contact.new())
	if kinds.has(&"mover"):
		body.add_child(Mover.new())
	if kinds.has(&"caster"):
		var caster := Caster.new()
		caster.staff_count = maxi(cards.size(), 1)
		caster.start_cards = cards
		caster.staff = staff
		body.add_child(caster)
	if controller != null:
		body.add_child(controller)
	return add(body, at)


## Services set on `body`, so the autoloads are not used.
func _wire(body: Actor) -> void:
	body.events = bus
	body.combat = combat
	body.projectiles = projectiles
	body.spells = spells
	body.actors = table


## `body` (made in code or from a scene) with this world's services, in the tree at `at`, stepped
## only by hand.
func add(body: Actor, at: Vector2) -> Actor:
	_wire(body)
	body.position = at
	_root.add_child(body)
	body.set_physics_process(false)
	actors.append(body)
	return body


## `count` steps: every actor, then its body moves by its velocity, then the systems.
func run(count: int) -> void:
	for i in count:
		for body in actors:
			if is_instance_valid(body) and body.is_inside_tree():
				body.step(STEP)
				body.position += body.velocity * STEP
		projectiles.step(STEP)
		spells.step(STEP)
		combat.step(STEP)


## The tag a card of `body`'s staff `staff` carries now (for moves asked by hand).
func tag_of(body: Actor, staff: int = 0) -> int:
	return SpellTag.make(body.caster_number(), staff, 0, 0)


func free_all() -> void:
	for body in actors:
		if is_instance_valid(body):
			body.free()
	actors.clear()
	for node: Node in [combat, spells, registry, projectiles, table, bus]:
		if node != null and is_instance_valid(node):
			node.free()

