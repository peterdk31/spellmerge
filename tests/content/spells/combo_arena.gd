extends RefCounted
## The test arena for the combo catalogue (M2 part 14): the real registry, projectile manager,
## spell runtime and combat, wired together outside the scene tree's autoloads, with imps (plain
## `Node2D`s that Combat knows as enemies) standing where a combo wants them. It builds a
## recipe, casts it and moves time on in the same order as project.godot (projectiles, spells,
## combat). Whoever uses it calls `free_all()` afterwards.
##
## Example (see test_combos.gd):
##   var arena := ArenaScript.new(root)
##   var imp: Node2D = arena.add_imp(Vector2(100.0, 0.0))
##   arena.install(0, 0, {"form": &"bolt", "element": &"fire"})
##   arena.cast(0, 0)
##   arena.run(1.0)

const ManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const EventsScript := preload("res://core/events/events.gd")
const RegistryScript := preload("res://core/registry/registry.gd")
const SpellsScript := preload("res://core/spells/spells.gd")
const CombatScript := preload("res://gameplay/combat/combat.gd")

const STEP: float = 1.0 / 60.0
## Health of an imp, high enough that no combo kills it by accident.
const IMP_HEALTH: int = 400
const IMP_RADIUS: float = 10.0
## Mana handed to every cast.
const MANA: float = 100.0

var registry: Node
var bus: EventsScript
var projectiles: ManagerScript
var spells: SpellsScript
var combat: CombatScript
## Every imp added, in order.
var imps: Array[Node2D] = []
## Every reaction_triggered as [player, id, position].
var reactions: Array = []
## Every status_applied as [player, imp, status id, health the imp had lost by then].
var statuses: Array = []
## The most live shots seen after any step.
var peak_shots: int = 0
## Seconds of arena time that have passed.
var time: float = 0.0

var _root: Node
var _owned: Array[Object] = []
## Where each player stands (the origin of casts and the orbit anchor).
var _casters: Array[Vector2] = [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]


func _init(root: Node) -> void:
	_root = root
	registry = _own(RegistryScript.new()) as Node
	registry.call("scan")
	bus = _own(EventsScript.new()) as EventsScript
	projectiles = _own(ManagerScript.new()) as ManagerScript
	projectiles.events = bus
	projectiles.set_cap(512)
	spells = _own(SpellsScript.new()) as SpellsScript
	spells.registry = registry
	spells.bind(projectiles, bus)
	combat = _own(CombatScript.new()) as CombatScript
	combat.events = bus
	combat.projectiles = projectiles
	combat.spells = spells
	combat._ready()
	bus.reaction_triggered.connect(func(player: int, id: StringName, at: Vector2) -> void: reactions.append([player, id, at]))
	bus.status_applied.connect(func(player: int, target: Node, id: StringName) -> void: statuses.append([player, target, id, lost(target as Node2D)]))


## Puts an imp at `at`; it can be hurt and killed, and shots can hit it.
func add_imp(at: Vector2, health: int = IMP_HEALTH) -> Node2D:
	var imp := _own(Node2D.new()) as Node2D
	_root.add_child(imp)
	imp.global_position = at
	combat.register_enemy(imp, health, IMP_RADIUS)
	imps.append(imp)
	return imp


## Where `player` stands. Casts start here and the player's orbit circles it.
func place_caster(player: int, at: Vector2) -> void:
	_casters[player] = at


## Compiles `recipe` and builds it into `player`'s `slot`. Returns the compile result, so a
## test can look at `valid` and `reason`.
func install(player: int, slot: int, recipe: Dictionary) -> CompiledSpell:
	var spell: CompiledSpell = spells.compile(recipe)
	if spell.valid:
		spells.install(player, slot, spell)
	return spell


## Casts `player`'s `slot` toward `direction` (+x by default). True when it was cast.
func cast(player: int, slot: int, direction: Vector2 = Vector2.RIGHT) -> bool:
	# An orbit has to find its anchor already set, as it is every physics step in the game.
	projectiles.set_anchor(player, _casters[player])
	return spells.cast(player, slot, _casters[player], direction, MANA) != SpellsScript.REFUSED


## Moves time on by `seconds` in fixed steps.
func run(seconds: float) -> void:
	for i in int(ceilf(seconds / STEP)):
		for player in _casters.size():
			projectiles.set_anchor(player, _casters[player])
		projectiles.step(STEP)
		spells.step(STEP)
		combat.step(STEP)
		time += STEP
		peak_shots = maxi(peak_shots, projectiles.get_count())


## Health `imp` has lost (all of it once it is dead and gone).
func lost(imp: Node2D) -> int:
	var left: int = combat.get_health(imp) if is_instance_valid(imp) else -1
	return IMP_HEALTH if left < 0 else IMP_HEALTH - left


## True when `status_id` was ever put on `imp`.
func was_given(imp: Node2D, status_id: StringName) -> bool:
	for row: Array in statuses:
		if row[1] == imp and row[2] == status_id:
			return true
	return false


## Health `imp` had lost when `status_id` was first put on it, or -1 if it never was.
func lost_when_given(imp: Node2D, status_id: StringName) -> int:
	for row: Array in statuses:
		if row[1] == imp and row[2] == status_id:
			return row[3] as int
	return -1


## The ids of the reactions seen, in order.
func reaction_ids() -> Array:
	var ids: Array = []
	for row: Array in reactions:
		ids.append(row[1])
	return ids


## Frees everything the arena made.
func free_all() -> void:
	for object in _owned:
		if is_instance_valid(object):
			if object is Node and (object as Node).is_inside_tree():
				(object as Node).get_parent().remove_child(object as Node)
			object.free()
	_owned.clear()
	imps.clear()


func _own(object: Object) -> Object:
	_owned.append(object)
	return object
