extends "res://tests/support/suite.gd"
## The rig a card's own test extends (content/spells/<kind>s/<id>/test_<id>.gd): the real spell
## runtime, projectile manager and event bus, the registry, and helpers to build cards into a
## staff, cast it, step the world and read what happened. A card test is about one card; the
## rules that hold for every card are tests of their own (tests/content/spells/).
##
##     extends "res://tests/support/card_rig.gd"
##
##     func test_the_bolt_hits() -> void:
##         var imp := _target(Vector2(100.0, 0.0))
##         _cast_form(&"bolt", 0, Vector2.ZERO)
##         _tick(30)
##         check_equal(_hit_targets(), [imp] as Array, "it hit the imp")

const StaffKit := preload("res://tests/support/staff_kit.gd")
const SpellsScript := preload("res://core/spells/spells.gd")
const ManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const EventsScript := preload("res://core/events/events.gd")
const RegistryScript := preload("res://core/registry/registry.gd")
const ActorSeats := preload("res://tests/support/actor_seats.gd")

const DT: float = 1.0 / 60.0

var _registry: Node
var _spells: SpellsScript
var _mgr: ManagerScript
var _bus: EventsScript
## Every projectile_hit as [player, target, position, tag].
var _hits: Array = []
## tag -> how many of its shots have ended
var _ended: Dictionary = {}


func before_each() -> void:
	_registry = own(RegistryScript.new()) as Node
	_registry.call("scan")
	_bus = own(EventsScript.new()) as EventsScript
	_mgr = own(ManagerScript.new()) as ManagerScript
	_mgr.events = _bus
	_spells = own(SpellsScript.new()) as SpellsScript
	_spells.registry = _registry
	_spells.bind(_mgr, _bus)
	_hits.clear()
	_ended.clear()
	_bus.projectile_hit.connect(func(player: int, target: Node, at: Vector2, tag: int, _shot: int) -> void: _hits.append([player, target, at, tag]))
	_mgr.shot_ended.connect(func(tag: int) -> void: _ended[tag] = _ended.get(tag, 0) + 1)


## Four wizards seated 0-3 at actor ids 0-3, as a test names its casters, and room for 512 shots
## (a trigger test calls it from its own `before_each`, after `super()`).
func _seat_wizards() -> void:
	_mgr.set_cap(512)
	_mgr.actors = own(ActorSeats.table()) as ActorSeats.ActorsScript


## The card `id` as the registry has it (null for an unknown id).
func _card(id: StringName) -> SpellComponent:
	return _registry.call("get_resource", &"spells", id) as SpellComponent


func _form(id: StringName) -> FormBase:
	return _card(id) as FormBase


func _modifier(id: StringName) -> ModifierBase:
	return _card(id) as ModifierBase


func _trigger(id: StringName) -> TriggerBase:
	return _card(id) as TriggerBase


## The card `id` is what the registry found in its folder: a card of its class, its id the folder
## name, a name, a description and an icon, its complexity `complexity`, inside every range.
func _check_card(id: StringName, complexity: int) -> SpellComponent:
	var card: SpellComponent = _card(id)
	check(card != null, "the registry finds %s" % id)
	if card == null:
		return null
	check_equal(card.id, id, "%s: the id is the folder name" % id)
	check(card.resource_path.get_base_dir().get_file() == String(id), "%s: in its own folder (%s)" % [id, card.resource_path])
	check(card.display_name != "", "%s has a name" % id)
	check(card.description != "", "%s has a description" % id)
	check(card.icon != null, "%s has an icon" % id)
	check_equal(card.complexity, complexity, "%s: complexity from the design table" % id)
	check_equal(card.range_problems().size(), 0, "%s: %s" % [id, ", ".join(card.range_problems())])
	return card


func _target(position: Vector2, radius: float = 10.0) -> Node2D:
	var node := Node2D.new()
	root.add_child(node)
	node.global_position = position
	own(node)
	_mgr.add_target(node, radius, ManagerScript.LAYER_ENEMY)
	return node


## Steps the manager and the runtime `steps` times; `anchors` (player -> position) are pushed
## every step, as a player pushes its wizard's place.
func _tick(steps: int, anchors: Dictionary = {}) -> void:
	for i in steps:
		for player: int in anchors:
			_mgr.set_anchor(player, anchors[player])
		_mgr.step(DT)
		_spells.step(DT)


## Builds a bare `form` into staff A of `player` and casts it from `origin` toward `direction`.
func _cast_form(form: StringName, player: int, origin: Vector2, direction: Vector2 = Vector2.RIGHT) -> int:
	var tag: int = StaffKit.build(_spells, player, 0, [form] as Array[StringName])
	check(tag != 0, "%s builds" % form)
	# An orbit needs its caster's anchor; the player pushes it every step.
	_mgr.set_anchor(player, origin)
	check(_spells.cast_staff(player, 0, origin, direction, 100.0) != SpellsScript.REFUSED, "%s is cast" % form)
	return tag


## The modifiers before the form: one carrier with all of them (staffs A6c).
func _row(form: StringName, modifiers: Array) -> Array[StringName]:
	var row: Array[StringName] = []
	for id: StringName in modifiers:
		row.append(id)
	row.append(form)
	return row


## The compiled spell of `form` with `modifiers`.
func _compile_with(form: StringName, modifiers: Array) -> CompiledSpell:
	var spell: CompiledSpell = StaffKit.first(_spells, _row(form, modifiers))
	check(spell != null, "%s + %s compiles" % [form, modifiers])
	return spell


## Builds `form` with `modifiers` into staff A of `player` and casts it from `origin`.
func _cast_with(form: StringName, modifiers: Array, player: int, origin: Vector2, direction: Vector2 = Vector2.RIGHT) -> int:
	var tag: int = StaffKit.build(_spells, player, 0, _row(form, modifiers))
	check(_spells.cast_staff(player, 0, origin, direction, 100.0) != SpellsScript.REFUSED, "%s + %s is cast" % [form, modifiers])
	return tag


## The first carrier of the staff for `recipe` (the recipe shape of staff_kit.gd).
func _compile_recipe(recipe: Dictionary) -> CompiledSpell:
	var spell: CompiledSpell = StaffKit.first(_spells, StaffKit.cards(recipe))
	check(spell != null, "the staff for %s casts" % [recipe])
	return spell


## Builds `recipe` into a staff and casts it from `origin` toward +x. Returns the cast's tag. A
## payload's spells have the next nodes, so `current_tag(player, staff, 1)` is the first one.
func _build_and_cast(player: int, staff: int, recipe: Dictionary, origin: Vector2 = Vector2.ZERO) -> int:
	var tag: int = StaffKit.build(_spells, player, staff, StaffKit.cards(recipe))
	check(_spells.cast_staff(player, staff, origin, Vector2.RIGHT, 100.0) != SpellsScript.REFUSED, "%s is cast" % [recipe])
	return tag


## Shots ever made with `tag` since the test began (alive plus ended).
func _born(tag: int) -> int:
	return _spells.live_shots(tag) + int(_ended.get(tag, 0))


## The slots of the live shots with `tag`.
func _slots(tag: int) -> Array[int]:
	var found: Array[int] = []
	for slot in _mgr.get_cap():
		if _mgr.is_alive(slot) and _mgr.get_tag_of(slot) == tag:
			found.append(slot)
	return found


func _hit_targets() -> Array:
	var targets: Array = []
	for hit: Array in _hits:
		targets.append(hit[1])
	return targets


## Ticks until the first hit and returns the number of steps it took (-1 if none in `limit`).
func _steps_to_first_hit(limit: int) -> int:
	for step in limit:
		_tick(1)
		if not _hits.is_empty():
			return step + 1
	return -1


## Every player casts `cards` from a row of their own, 400 px apart, at a target of their own
## 100 px ahead (none when `targets` is false); returns the targets. For "works for all four
## players at once".
func _four_players_cast(cards: Array, with_targets: bool = true) -> Array[Node2D]:
	var targets: Array[Node2D] = []
	var row: Array[StringName] = []
	for id: StringName in cards:
		row.append(id)
	for player in 4:
		var origin := Vector2(-600.0, -600.0 + 400.0 * player)
		if with_targets:
			targets.append(_target(origin + Vector2(100.0, 0.0)))
		StaffKit.build(_spells, player, 0, row)
		_mgr.set_anchor(player, origin)
		check(_spells.cast_staff(player, 0, origin, Vector2.RIGHT, 100.0) != SpellsScript.REFUSED, "player %d casts %s" % [player, row])
	return targets


## Each player's own target was hit by that player, and by nobody else.
func _check_own_targets_hit(targets: Array[Node2D], what: String) -> void:
	for player in targets.size():
		var credited: bool = false
		var stolen: bool = false
		for hit: Array in _hits:
			if hit[1] == targets[player]:
				credited = credited or hit[0] == player
				stolen = stolen or hit[0] != player
		check(credited, "%s: player %d hit their own target" % [what, player])
		check(not stolen, "%s: nobody else hit player %d's target" % [what, player])
