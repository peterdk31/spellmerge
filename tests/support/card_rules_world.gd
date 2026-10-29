extends RefCounted
## The small world of the card rules test (rules R3, tests/core/test_card_rules.gd): the real
## projectile manager, Spells, Combat and Entities on their own event bus, with actors built from
## the actor kit (health, hurtbox, mover, caster, a scripted controller), stepped by hand in the
## order of project.godot. A wizard stands with its hand at (0, 0) and aims along +x; the scene
## puts enemies, walls, an enemy shooter or a donor of infusions where a probe asks.
##
## Everything a player could see is written to `trace`, one line per thing, in order: every bus
## event that changes the game (hits with their whole profile, damage, heals, statuses, kills,
## area hits, moves, spawns, blocks, deflects, pulls, possessions, refunds, zaps, expiries, walls
## met), and every SAMPLE_EVERY steps the live shots (who cast them, their spell node, place and
## size), the beams' points, the swings' sweep, the slams, and the actors' places and health when they
## changed. Looks (tint, particles, the cast flash) are left out: a card that only changes its look
## changes nothing. Two worlds built alike and cast alike write the same trace (the runtime's
## randomness is seeded by the cast).
##
##     var world := World.new(root, shelf, staff)
##     world.add_wizard([&"homing", &"bolt"])
##     world.add_enemy(&"A", Vector2(90.0, 0.0))
##     world.press()
##     world.run(2.0)
##     world.free_all()

const EventsScript := preload("res://core/events/events.gd")
const ProjectilesScript := preload("res://core/projectiles/projectile_manager.gd")
const SpellsScript := preload("res://core/spells/spells.gd")
const ActorsScript := preload("res://core/actors/actors.gd")
const CombatScript := preload("res://gameplay/combat/combat.gd")
const EntitiesScript := preload("res://gameplay/ai/entities.gd")
const ActorFixture := preload("res://tests/gameplay/actor/actor_fixture.gd")

const STEP: float = 1.0 / 60.0
## Steps between two samples of the shots, beams, swings and actors.
const SAMPLE_EVERY: int = 2
## A run stops early once nothing has been live (no shot, beam, swing, move, waiting launch or
## entity) for this long.
const QUIET_SECONDS: float = 0.25
## Health of an enemy that should not die by accident.
const HEALTH: int = 400
## Mana of the wizard: no cast is refused for mana.
const MANA: float = 10000.0

## The cards Spells reads: the registry's, plus cards a test made in code (`extra`, by id).
class Shelf:
	extends Node
	var base: Node = null
	var extra: Dictionary = {}

	func get_resource(folder: StringName, id: StringName) -> Resource:
		if extra.has(id):
			return extra[id]
		return base.call("get_resource", folder, id) as Resource


var bus: EventsScript
var projectiles: ProjectilesScript
var spells: SpellsScript
var combat: CombatScript
var entities: EntitiesScript
var table: ActorsScript
var wizard: Actor = null
var brain: ActorFixture.Scripted = null
## What a player could see, in order (see the class doc).
var trace: PackedStringArray = PackedStringArray()
## A trace to compare with as it is written (another cast's): `run` stops at the first line that
## differs, and `differs` says so. Empty: none.
var expect: PackedStringArray = PackedStringArray()
var differs: bool = false
## Calls made after the step of that index: step -> Array[Callable].
var at_step: Dictionary = {}

var _root: Node
var _staff: StaffBase
var _bodies: Array[Actor] = []
var _walls: Array[Rect2] = []
## The root's children before this world, so `free_all` frees what it left there.
var _root_before: Array[Node] = []
## Actor id -> name, for the trace.
var _names: Dictionary = {}
## Actor name -> the last "place health" written, so a still actor writes nothing more.
var _last_seen: Dictionary = {}
var _last_entities: int = 0
var _step: int = 0
## See `press_when_shot_within`; 0 when it is not waiting.
var _press_within: float = 0.0


func _init(root: Node, shelf: Shelf, staff: StaffBase) -> void:
	_root = root
	_root_before = root.get_children()
	_staff = staff
	bus = EventsScript.new()
	projectiles = ProjectilesScript.new()
	projectiles.events = bus
	projectiles.set_cap(256)
	projectiles.set_bounds(Rect2(-480.0, -480.0, 960.0, 960.0))
	table = ActorsScript.new()
	projectiles.actors = table
	spells = SpellsScript.new()
	spells.registry = shelf
	spells.actors = table
	spells.bind(projectiles, bus)
	combat = CombatScript.new()
	combat.events = bus
	combat.projectiles = projectiles
	combat.spells = spells
	combat.actors = table
	combat._ready()
	entities = EntitiesScript.new()
	entities.events = bus
	entities.projectiles = projectiles
	entities.spells = spells
	entities.actors = table
	_root.add_child(entities)
	entities.set_physics_process(false)
	_listen()


## The wizard of seat 0 with its hand at (0, 0), aiming along +x, its first staff `cards`.
func add_wizard(cards: Array[StringName]) -> Actor:
	brain = ActorFixture.Scripted.new()
	brain.team = ActorsScript.TEAM_WIZARDS
	brain.seat = 0
	brain.aim = Vector2.RIGHT
	wizard = _body(&"wizard", Vector2.ZERO, brain, cards, HEALTH)
	return wizard


## A teammate of the wizard (seat 1) whose body stands at `at`: shots hit it, mend heals it.
func add_ally(at: Vector2) -> Actor:
	var mate := ActorFixture.Scripted.new()
	mate.team = ActorsScript.TEAM_WIZARDS
	mate.seat = 1
	return _body(&"ally", at, mate, [], HEALTH)


## An enemy whose hurt circle is centred on `at`, standing still (it is pushed by knockback and
## pulls). With `cards` it casts them once along `aim` at the first step (a donor for relay), or
## for the whole run when `stream` (an enemy shooter).
func add_enemy(label: StringName, at: Vector2, health: int = HEALTH, cards: Array[StringName] = [], aim: Vector2 = Vector2.LEFT, stream: bool = false) -> Actor:
	var mind: ActorFixture.Scripted = null
	if not cards.is_empty():
		mind = ActorFixture.Scripted.new()
		mind.team = ActorsScript.TEAM_ENEMIES
		mind.aim = aim
		if stream:
			mind.held = [0]
		else:
			mind.presses = [0]
	return _body(label, at, mind, cards, health)


## A wall over `rect`.
func add_wall(rect: Rect2) -> void:
	_walls.append(rect)
	projectiles.set_walls(_walls)


## The wizard presses its staff at the first step; `hold_button` keeps it down (it casts again
## whenever its staff is ready).
func press(hold_button: bool = false) -> void:
	if hold_button:
		brain.held = [0]
	else:
		brain.presses = [0]


## The wizard presses its staff once, at the first step an enemy shot is within `distance`
## pixels of its hand (so a carrier that touches shots only briefly, a swing or a fissure, meets one).
func press_when_shot_within(distance: float) -> void:
	_press_within = distance


## Hurts the wizard by `amount` (an enemy no body stands for hits it) after step `step`.
func hurt_wizard_at(step: int, amount: int) -> void:
	var by: int = table.open(ActorsScript.TEAM_ENEMIES, ActorsScript.RAMP_ENEMY)
	_later(step, func() -> void:
		if is_instance_valid(wizard):
			combat.hit(by, wizard, amount))


func _later(step: int, call: Callable) -> void:
	if not at_step.has(step):
		at_step[step] = []
	(at_step[step] as Array).append(call)


## Runs up to `seconds`, stopping early when it has been quiet for QUIET_SECONDS (and at least
## `least` seconds have gone), or once the trace differs from `expect`. Returns the steps run.
func run(seconds: float, least: float = 0.0) -> int:
	var steps: int = int(ceilf(seconds / STEP))
	var quiet: float = 0.0
	for i in steps:
		_step = i
		if _press_within > 0.0 and _shot_within(_press_within):
			_press_within = 0.0
			brain.presses = [0]
		for body in _bodies:
			if is_instance_valid(body) and body.is_inside_tree():
				body.step(STEP)
				body.position += body.velocity * STEP
		projectiles.step(STEP)
		spells.step(STEP)
		combat.step(STEP)
		entities.step(STEP)
		if at_step.has(i):
			for call: Callable in at_step[i]:
				call.call()
		if i % SAMPLE_EVERY == 0:
			_sample()
		if differs:
			return i + 1
		if _is_quiet():
			quiet += STEP
			if quiet >= QUIET_SECONDS and i * STEP >= least:
				return i + 1
		else:
			quiet = 0.0
	return steps


## Frees everything the world made.
func free_all() -> void:
	# The calls hold this world: let it go.
	at_step.clear()
	for body in _bodies:
		if is_instance_valid(body):
			body.free()
	_bodies.clear()
	# A possession may have moved a controller out of its body (into the root).
	for node: Node in _root.get_children():
		if not _root_before.has(node) and node != entities:
			node.free()
	for node: Node in [entities, combat, spells, projectiles, table, bus]:
		if node != null and is_instance_valid(node):
			node.free()


func _body(label: StringName, centre: Vector2, mind: ActorController, cards: Array[StringName], health: int) -> Actor:
	var body := Actor.new()
	body.name = String(label)
	body.events = bus
	body.combat = combat
	body.projectiles = projectiles
	body.spells = spells
	body.actors = table
	body.idle_team = ActorsScript.TEAM_ENEMIES
	var life := Health.new()
	life.max_health = health
	body.add_child(life)
	body.add_child(Hurtbox.new())
	body.add_child(Mover.new())
	if not cards.is_empty():
		var caster := Caster.new()
		caster.staff_count = 1
		caster.start_cards = [cards]
		caster.staff = _staff
		caster.max_mana = MANA
		caster.regen = 0.0
		body.add_child(caster)
	if mind != null:
		body.add_child(mind)
	# The hurt circle and the hand sit `body_offset` above the feet.
	body.position = centre - body.body_offset
	_root.add_child(body)
	body.set_physics_process(false)
	_bodies.append(body)
	_names[body.id] = String(label)
	return body


func _shot_within(distance: float) -> bool:
	var hand: Vector2 = wizard.aim_pivot()
	for slot in projectiles._high:
		if projectiles.is_alive(slot) and projectiles.get_actor_of(slot) != wizard.id and projectiles.get_position_of(slot).distance_to(hand) <= distance:
			return true
	return false


func _is_quiet() -> bool:
	if projectiles.get_count() > 0 or spells.beam_count() > 0 or spells.swing_count() > 0 or spells.slam_count() > 0:
		return false
	if not spells._pending.is_empty() or spells._mv_count > 0 or spells._jq_count > 0:
		return false
	if entities.count() > 0:
		return false
	for body in _bodies:
		if is_instance_valid(body) and body.mover != null and body.mover.is_moving():
			return false
	return true


# --- The trace ------------------------------------------------------------------------------

func _who(actor: int) -> String:
	return _names.get(actor, "a%d" % actor)


func _node(tag: int) -> String:
	if not SpellTag.is_spell_tag(tag):
		return "-"
	return "%s/n%d" % [_who(SpellTag.caster_of(tag)), SpellTag.node_of(tag)]


static func _at(point: Vector2) -> String:
	if not point.is_finite():
		return "inf"
	return "%.1f,%.1f" % [point.x, point.y]


func _name_of(target: Object) -> String:
	if target == null or not is_instance_valid(target):
		return "?"
	return String((target as Node).name) if target is Node else "?"


func _put(text: String) -> void:
	var line: String = "%d %s" % [_step, text]
	if not expect.is_empty() and not differs:
		var at: int = trace.size()
		differs = at >= expect.size() or expect[at] != line
	trace.append(line)


func _profile(tag: int) -> String:
	var hit: HitProfile = spells.hit_profile(tag)
	if hit == null:
		return "none"
	var statuses: Array = [hit.status_id] + Array(hit.later_status_ids)
	return "d%d h%d s%d k%d %s %s %s" % [hit.damage, hit.heal, hit.slam, roundi(hit.knockback), hit.kind, ",".join(PackedStringArray(hit.element_ids)), ",".join(PackedStringArray(statuses))]


func _listen() -> void:
	bus.projectile_hit.connect(func(caster: int, target: Node, at: Vector2, tag: int) -> void:
		_put("hit %s %s %s at %s [%s]" % [_who(caster), _node(tag), _name_of(target), _at(at), _profile(tag)]))
	projectiles.wall_met.connect(func(caster: int, at: Vector2, _heading: Vector2, tag: int) -> void:
		_put("wall %s %s at %s" % [_who(caster), _node(tag), _at(at)]))
	bus.projectile_expired.connect(func(caster: int, at: Vector2, tag: int) -> void:
		_put("expired %s %s at %s" % [_who(caster), _node(tag), _at(at)]))
	bus.damage_dealt.connect(func(caster: int, target: Node, amount: int, _at_point: Vector2) -> void:
		_put("damage %s -> %s %d" % [_who(caster), _name_of(target), amount]))
	bus.hit_landed.connect(func(caster: int, target: Node, amount: int, _at_point: Vector2, kind: StringName) -> void:
		_put("landed %s -> %s %d %s" % [_who(caster), _name_of(target), amount, kind]))
	bus.heal_dealt.connect(func(caster: int, target: Node, amount: int, _at_point: Vector2) -> void:
		_put("heal %s -> %s %d" % [_who(caster), _name_of(target), amount]))
	bus.status_applied.connect(func(caster: int, target: Node, id: StringName) -> void:
		_put("status %s -> %s %s" % [_who(caster), _name_of(target), id]))
	bus.reaction_triggered.connect(func(caster: int, id: StringName, at: Vector2) -> void:
		_put("reaction %s %s at %s" % [_who(caster), id, _at(at)]))
	bus.kill_landed.connect(func(caster: int, target: Node, at: Vector2, tag: int) -> void:
		_put("kill %s %s %s at %s" % [_who(caster), _node(tag), _name_of(target), _at(at)]))
	bus.actor_hurt.connect(func(actor: int, amount: int, _at_point: Vector2, tag: int, kind: StringName) -> void:
		_put("hurt %s %d %s %s" % [_who(actor), amount, _node(tag), kind]))
	bus.area_hit_requested.connect(func(caster: int, at: Vector2, radius: float, tag: int) -> void:
		_put("area %s %s at %s r%d" % [_who(caster), _node(tag), _at(at), roundi(radius)]))
	bus.caster_move_requested.connect(func(caster: int, mode: StringName, to: Vector2, seconds: float, tag: int) -> void:
		_put("move %s %s %s to %s in %d ms" % [_who(caster), mode, _node(tag), _at(to), roundi(seconds * 1000.0)]))
	bus.caster_move_finished.connect(func(caster: int, mode: StringName, at: Vector2, tag: int) -> void:
		_put("moved %s %s %s at %s" % [_who(caster), mode, _node(tag), _at(at)]))
	bus.target_move_requested.connect(func(caster: int, target: Node, to: Vector2) -> void:
		_put("swap %s %s to %s" % [_who(caster), _name_of(target), _at(to)]))
	bus.entity_spawn_requested.connect(func(caster: int, kind: StringName, at: Vector2, seconds: float, tag: int, anchor: int) -> void:
		_put("spawn %s %s %s at %s for %s by %d" % [_who(caster), kind, _node(tag), _at(at), str(roundi(seconds * 1000.0)) if is_finite(seconds) else "ever", anchor]))
	bus.entity_ended.connect(func(caster: int, kind: StringName, at: Vector2, tag: int) -> void:
		_put("ended %s %s %s at %s" % [_who(caster), kind, _node(tag), _at(at)]))
	bus.entity_end_requested.connect(func(caster: int, tag: int) -> void:
		_put("end %s %s" % [_who(caster), _node(tag)]))
	bus.familiar_cast_requested.connect(func(caster: int, at: Vector2, direction: Vector2, tag: int) -> void:
		_put("familiar %s %s at %s to %s" % [_who(caster), _node(tag), _at(at), _at(direction * 100.0)]))
	bus.mana_refund_requested.connect(func(caster: int, amount: float) -> void:
		_put("refund %s %s" % [_who(caster), str(snappedf(amount, 0.01))]))
	bus.shot_blocked.connect(func(caster: int, at: Vector2, tag: int) -> void:
		_put("blocked %s %s at %s" % [_who(caster), _node(tag), _at(at)]))
	bus.shield_blocked.connect(func(actor: int, at: Vector2, tag: int) -> void:
		_put("shielded %s %s at %s" % [_who(actor), _node(tag), _at(at)]))
	bus.shot_deflected.connect(func(caster: int, at: Vector2, tag: int) -> void:
		_put("deflected %s %s at %s" % [_who(caster), _node(tag), _at(at)]))
	bus.wizard_shield_requested.connect(func(caster: int, charges: int, seconds: float, tag: int) -> void:
		_put("barrier %s %s %d for %d ms" % [_who(caster), _node(tag), charges, roundi(seconds * 1000.0)]))
	bus.pull_requested.connect(func(caster: int, at: Vector2, radius: float, strength: float, tag: int) -> void:
		_put("pull %s %s at %s r%d %d" % [_who(caster), _node(tag), _at(at), roundi(radius), roundi(strength)]))
	bus.possess_requested.connect(func(caster: int, target: int, seconds: float, tag: int) -> void:
		_put("possess %s %s %s for %d ms" % [_who(caster), _who(target), _node(tag), roundi(seconds * 1000.0)]))
	bus.discharge_arc.connect(func(caster: int, from: Vector2, to: Vector2) -> void:
		_put("arc %s %s -> %s" % [_who(caster), _at(from), _at(to)]))
	bus.enemy_died.connect(func(killer: int, enemy: Node, at: Vector2) -> void:
		_put("died %s by %s at %s" % [_name_of(enemy), _who(killer), _at(at)]))


func _sample() -> void:
	for slot in projectiles._high:
		if projectiles.is_alive(slot):
			var tag: int = projectiles.get_tag_of(slot)
			_put("shot %s %s at %s r%d" % [_who(projectiles.get_actor_of(slot)), _node(tag), _at(projectiles.get_position_of(slot)), roundi(projectiles._radius[slot])])
	for at in spells.beam_slots():
		if spells.beam_on(at):
			var points: PackedStringArray = PackedStringArray()
			for n in spells.beam_point_count(at):
				points.append(_at(spells.beam_point(at, n)))
			_put("beam %s %s" % [_who(spells.beam_caster(at)), " ".join(points)])
	for at in spells.slam_slots():
		if spells.slam_on(at):
			# A slam's row is read directly: Spells has no getter for its caster and aim.
			_put("slam %s %s from %s way %s impact %s" % [_who(spells._sl_actor[at]), _node(spells._sl_tag[at]), _at(spells._sl_origin[at]), _at(spells._sl_dir[at] * 100.0), _at(spells.slam_impact(at)) if spells.slam_impact(at).is_finite() else "-"])
	for at in spells.swing_slots():
		if spells.swing_on(at):
			_put("swing %s %s at %s to %s side %d turned %d reach %d" % [_who(spells.swing_actor(at)), _node(spells.swing_tag(at)), _at(spells.swing_origin(at)), _at(spells.swing_dir(at) * 100.0), spells.swing_side(at), roundi(rad_to_deg(spells.swing_turned(at))), roundi(spells.swing_reach(at))])
	for body in _bodies:
		var seen: String = "gone"
		if is_instance_valid(body) and not body.is_dying():
			seen = "at %s health %d" % [_at(body.global_position), combat.health_of(body)]
		if _last_seen.get(body.name, "") != seen:
			_last_seen[body.name] = seen
			_put("%s %s" % [body.name, seen])
	var live: int = entities.count()
	if live != _last_entities:
		_last_entities = live
		_put("entities %d" % live)
