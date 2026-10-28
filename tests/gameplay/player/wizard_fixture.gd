extends RefCounted
## A small world for the wizard tests (actors G7): its own event bus, input manager (virtual
## devices), projectile manager, Combat, actor table and spell runtime, and wizards made from the
## real scene (content/wizard/base/wizard.tscn), seated as flow seats them, in the tree, and
## stepped only by hand. `free_all()` frees everything.
##
## The spell runtime is the real one reading the real registry by default, or the stand-in
## (fixtures/fake_spells.gd) with `fake` true, so a test runs the wizard on its own. The registry
## is scanned only for the real runtime; the stand-in's has no cards and no sounds unless a test
## gives it some.
##
## A test reads a wizard through its components (`wizard.health`, `wizard.caster`,
## `wizard.mover`, `downed(wizard)`, `controller(wizard)`, `look(wizard)`).

const EventsScript := preload("res://core/events/events.gd")
const InputManagerScript := preload("res://core/input/input_manager.gd")
const ProjectilesScript := preload("res://core/projectiles/projectile_manager.gd")
const RegistryScript := preload("res://core/registry/registry.gd")
const SpellsScript := preload("res://core/spells/spells.gd")
const ActorsScript := preload("res://core/actors/actors.gd")
const CombatScript := preload("res://gameplay/combat/combat.gd")
const FakeSpells := preload("res://tests/gameplay/player/fixtures/fake_spells.gd")
const WizardScene := preload("res://content/wizard/base/wizard.tscn")

## Time moves by this fixed binary fraction.
const STEP: float = 0.0625
## No cards in any staff.
const NO_CARDS: Array = [[], [], [], []]

var bus: EventsScript
var input: InputManagerScript
var projectiles: ProjectilesScript
var registry: RegistryScript
var spells: SpellsScript
var combat: CombatScript
var table: ActorsScript
## The stand-in runtime when made with `fake` (else null).
var fake: FakeSpells = null
var wizards: Array[Actor] = []
var _root: Node


## A world in `root`. `fake`: the stand-in spell runtime and an empty registry; else the real ones.
func _init(root: Node, use_fake: bool = false) -> void:
	_root = root
	bus = EventsScript.new()
	input = InputManagerScript.new()
	input.events = bus
	projectiles = ProjectilesScript.new()
	projectiles.events = bus
	projectiles.set_bounds(Rect2(-400.0, -400.0, 1040.0, 800.0))
	table = ActorsScript.new()
	projectiles.actors = table
	registry = RegistryScript.new()
	if use_fake:
		fake = FakeSpells.new()
		spells = fake
	else:
		registry.scan()
		spells = SpellsScript.new()
		spells.registry = registry
	spells.actors = table
	spells.bind(projectiles, bus)
	combat = CombatScript.new()
	combat.events = bus
	combat.projectiles = projectiles
	combat.spells = spells
	combat.actors = table
	combat.setup()


## A wizard for `seat` (its virtual device joined) at `at`, with `cards` (four lists of card ids)
## on `staff` (null: a plain staff of 4 slots and no delay), in the tree and ready. Set `ready`
## false to get it seated and wired but not yet added (`add` it later).
func wizard(seat: int, at: Vector2 = Vector2.ZERO, cards: Array = NO_CARDS, staff: StaffBase = null, ready: bool = true) -> Actor:
	if not input.is_joined(seat):
		input.add_virtual_device(seat)
	var body := WizardScene.instantiate() as Actor
	body.name = "Wizard%d" % seat
	PlayerController.seat_wizard(body, seat, staff, cards.duplicate(true))
	var seat_controller: PlayerController = PlayerController.of(body)
	seat_controller.input = input
	seat_controller.registry = registry
	_wire(body)
	body.position = at
	if ready:
		add(body)
	return body


## `body` (wired) into the tree, stepped only by hand.
func add(body: Actor) -> Actor:
	_wire(body)
	_root.add_child(body)
	body.set_physics_process(false)
	if not wizards.has(body):
		wizards.append(body)
	return body


## Services set on `body`, so the autoloads are not used.
func _wire(body: Actor) -> void:
	body.events = bus
	body.combat = combat
	body.projectiles = projectiles
	body.spells = spells
	body.actors = table


static func controller(body: Actor) -> PlayerController:
	return PlayerController.of(body)


static func downed(body: Actor) -> Downed:
	return Downed.of(body)


static func look(body: Actor) -> WizardLook:
	for child in body.get_children():
		if child is WizardLook:
			return child as WizardLook
	return null


## Hold `action` of `seat` down (`strength` 1) or let it go (0).
func hold(seat: int, action: StringName, strength: float = 1.0) -> void:
	input.send_virtual(seat, action, strength)


func release(seat: int, action: StringName) -> void:
	input.send_virtual(seat, action, 0.0)


## `count` steps: the runtime ticks first (the stand-in's delays), then every wizard steps and
## its body moves by its velocity when `move` (as `move_and_slide` would, without walls), then the
## systems.
func run(count: int, move: bool = true) -> void:
	for i in count:
		if fake != null:
			fake.step(STEP)
		for body in wizards:
			if is_instance_valid(body) and body.is_inside_tree():
				body.step(STEP)
				if move:
					body.position += body.velocity * STEP
		projectiles.step(STEP)
		if fake == null:
			spells.step(STEP)
		combat.step(STEP)


## A hit of `amount` on `body` through Combat, which takes it from its Health (actors G5).
func hurt(body: Actor, amount: int, by: int = 0) -> void:
	combat.hit(by, body, amount)


func free_all() -> void:
	for body in wizards:
		if is_instance_valid(body):
			body.free()
	wizards.clear()
	for node: Node in [combat, spells, registry, projectiles, input, table, bus]:
		if node != null and is_instance_valid(node):
			node.free()
