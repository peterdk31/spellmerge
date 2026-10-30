extends RefCounted
## The test arena for the combo catalogue (M2 part 14): the real registry, projectile manager,
## spell runtime and combat, wired together outside the scene tree's autoloads, with imps (plain
## `Node2D`s that Combat knows as enemies) standing where a combo wants them. It builds a
## staff from card ids, casts it and moves time on in the same order as project.godot
## (projectiles, spells, combat). Whoever uses it calls `free_all()` afterwards.
##
## Example (see test_combos.gd):
##   var arena := ArenaScript.new(root)
##   var imp: Node2D = arena.add_imp(Vector2(100.0, 0.0))
##   arena.install_cards(0, 0, [&"fire", &"bolt"])
##   arena.cast(0, 0)
##   arena.run(1.0)

const ManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const EventsScript := preload("res://core/events/events.gd")
const RegistryScript := preload("res://core/registry/registry.gd")
const SpellsScript := preload("res://core/spells/spells.gd")
const CombatScript := preload("res://gameplay/combat/combat.gd")
const ActorSeats := preload("res://tests/support/actor_seats.gd")

const STEP: float = 1.0 / 60.0
## Health of an imp, high enough that no combo kills it by accident.
const IMP_HEALTH: int = 400
const IMP_RADIUS: float = 10.0
## Mana handed to every cast.
const MANA: float = 100.0

## A body that is the actor `actor_id` (Combat registers it under that id).
class Guard extends Node2D:
	var actor_id: int = -1

var registry: Node
var bus: EventsScript
var projectiles: ManagerScript
var spells: SpellsScript
var combat: CombatScript
## Every imp added, in order.
var imps: Array[Node2D] = []
## Every caster_move_requested as [caster, mode] (a dash card moves its caster, staffs A6a).
var caster_moves: Array = []
## Every reaction_triggered as [caster, id, position].
var reactions: Array = []
## Every status_applied as [caster, imp, status id, health the imp had lost by then].
var statuses: Array = []
## Every heal_dealt as [caster, body, amount].
var heals: Array = []
## Every wizard body added (`add_guard`), in order.
var bodies: Array[Node2D] = []
## The most live shots seen after any step.
var peak_shots: int = 0
## Every enemy shot a barrier or a shielded shot stopped (`shield_blocked`, `shot_blocked`).
var blocks: Array = []
## Every enemy shot a deflect turned (`shot_deflected`), as the deflecting actor.
var deflects: Array = []
## Every entity a cast asked for (decoys, familiars), as [actor, kind].
var spawns: Array = []
## When true, `run` moves the imps by the push combat keeps for them (a pull or a knockback); off,
## imps stand where they are put.
var pushable: bool = false
## Seconds of arena time that have passed.
var time: float = 0.0

var _walls: Array[Rect2] = []
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
	# Four wizards seated 0-3 at actor ids 0-3, as the combos name their casters; spells and
	# combat find the table through the manager.
	projectiles.actors = _own(ActorSeats.table()) as ActorSeats.ActorsScript
	spells = _own(SpellsScript.new()) as SpellsScript
	spells.registry = registry
	spells.bind(projectiles, bus)
	combat = _own(CombatScript.new()) as CombatScript
	combat.events = bus
	combat.projectiles = projectiles
	combat.spells = spells
	combat._ready()
	bus.reaction_triggered.connect(func(player: int, id: StringName, at: Vector2, _shot: int) -> void: reactions.append([player, id, at]))
	bus.caster_move_requested.connect(func(player: int, mode: StringName, _to: Vector2, _seconds: float, _tag: int) -> void: caster_moves.append([player, mode]))
	bus.shield_blocked.connect(func(actor: int, _at: Vector2, _tag: int) -> void: blocks.append(actor))
	bus.shot_blocked.connect(func(actor: int, _at: Vector2, _tag: int, _shot: int) -> void: blocks.append(actor))
	bus.shot_deflected.connect(func(actor: int, _at: Vector2, _tag: int, _shot: int) -> void: deflects.append(actor))
	bus.entity_spawn_requested.connect(func(actor: int, kind: StringName, _at: Vector2, _seconds: float, _tag: int, _caster: int) -> void: spawns.append([actor, kind]))
	bus.heal_dealt.connect(func(caster: int, target: Node, amount: int, _at: Vector2) -> void: heals.append([caster, target, amount]))
	bus.status_applied.connect(func(player: int, target: Node, id: StringName) -> void: statuses.append([player, target, id, lost(target as Node2D)]))


## Puts an imp at `at`; it can be hurt and killed, and shots can hit it.
func add_imp(at: Vector2, health: int = IMP_HEALTH) -> Node2D:
	var imp := _own(Node2D.new()) as Node2D
	_root.add_child(imp)
	imp.global_position = at
	combat.register_actor(imp, health, IMP_RADIUS)
	imps.append(imp)
	return imp


## Puts a body for the actor `player` at `at` that Combat knows (so a barrier on it works) and
## shots hit. Returns the node.
func add_guard(player: int, at: Vector2) -> Node2D:
	var guard := _own(Guard.new()) as Guard
	guard.actor_id = player
	_root.add_child(guard)
	guard.global_position = at
	combat.register_actor(guard, IMP_HEALTH, IMP_RADIUS)
	bodies.append(guard)
	return guard


## Takes `amount` of health off the wizard body `body`, hit by an actor no wizard drives (so a
## mend has something to heal).
func hurt(body: Node2D, amount: int) -> void:
	combat.hit(ActorSeats.enemy(projectiles.actors), body, amount)


## Health given to wizard bodies by heals, all together.
func healed() -> int:
	var total: int = 0
	for row: Array in heals:
		total += int(row[2])
	return total


## Sends an enemy bolt (a real cast, with a hit that hurts) from `from` toward `to`, cast by an
## actor no wizard drives.
func shoot_at(from: Vector2, to: Vector2) -> void:
	var enemy: int = ActorSeats.enemy(projectiles.actors)
	var ids: Array[StringName] = [&"bolt"]
	spells.install_staff(enemy, 0, spells.compile_staff(ids, plain_staff(1)))
	projectiles.set_anchor(enemy, from)
	spells.cast_staff(enemy, 0, from, from.direction_to(to), MANA)


## Puts the body of teammate `player` at `at`: a shot of another actor hits it (and `relay` reads
## what `player` last cast), and it is nothing else, so it takes no damage. Returns the node.
func add_mate(at: Vector2, player: int) -> Node2D:
	var mate := _own(Node2D.new()) as Node2D
	_root.add_child(mate)
	mate.global_position = at
	projectiles.add_target(mate, IMP_RADIUS, ManagerScript.LAYER_PLAYER, player)
	return mate


## Puts a wall over `rect` (pixels, the caster at (0, 0)): shots end, bounce or pass on it as
## their cards say.
func add_wall(rect: Rect2) -> void:
	_walls.append(rect)
	projectiles.set_walls(_walls)


## Where `player` stands. Casts start here and the player's orbit circles it.
func place_caster(player: int, at: Vector2) -> void:
	_casters[player] = at


## Builds `cards` (card ids, one per slot) into `player`'s staff `staff` on a plain staff with
## no delay or recharge of its own (staffs A6b), and returns the compiled staff, so a test can
## look at its casts and wasted cards. An empty staff is installed as no build.
func install_cards(player: int, staff: int, cards: Array) -> CompiledStaff:
	var ids: Array[StringName] = []
	for id: Variant in cards:
		ids.append(StringName(str(id)))
	var compiled: CompiledStaff = spells.compile_staff(ids, plain_staff(ids.size()))
	spells.install_staff(player, staff, compiled)
	return compiled


## A staff of `slots` slots with no delay or recharge of its own, for tests.
static func plain_staff(slots: int) -> StaffBase:
	var staff := StaffBase.new()
	staff.id = &"arena"
	staff.slots = clampi(slots, 1, 64)
	staff.cast_delay = 0.0
	staff.recharge = 0.0
	return staff


## Casts `player`'s staff `staff` (its next cast) toward `direction` (+x by default). True when
## it was cast.
func cast(player: int, staff: int, direction: Vector2 = Vector2.RIGHT) -> bool:
	# An orbit has to find its anchor already set, as it is every physics step in the game.
	projectiles.set_anchor(player, _casters[player])
	return spells.cast_staff(player, staff, _casters[player], direction, MANA) != SpellsScript.REFUSED


## Moves time on by `seconds` in fixed steps.
func run(seconds: float) -> void:
	for i in int(ceilf(seconds / STEP)):
		for player in _casters.size():
			projectiles.set_anchor(player, _casters[player])
		projectiles.step(STEP)
		spells.step(STEP)
		combat.step(STEP)
		if pushable:
			for imp in imps:
				if is_instance_valid(imp):
					imp.global_position += combat.consume_knockback(imp, STEP) * STEP
		time += STEP
		peak_shots = maxi(peak_shots, projectiles.get_count())


## Health `imp` has lost (all of it once it is dead and gone).
func lost(imp: Node2D) -> int:
	var left: float = combat.health_of(imp) if is_instance_valid(imp) else -1.0
	# Whole points: health is decimal, 7.5 lost is 7 (a hair over, for float sums of specks).
	return IMP_HEALTH if left < 0.0 else floori(float(IMP_HEALTH) - left + 0.0001)


## True when `imp` has died (a spell's hit or anything else took all its health).
func died(imp: Node2D) -> bool:
	return not is_instance_valid(imp) or combat.health_of(imp) < 0


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
