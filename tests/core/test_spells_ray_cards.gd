extends "res://tests/support/suite.gd"
## Cards on beams and fissures (rules R4f, docs/milestones/M2-rules.md; owner, 2026-10-29): a
## ray's chain jump pierces as its carrier does (a fissure's every target); ghost takes a beam or
## a fissure through walls; a beam with magnet pulls toward its line, with growth widens every
## second it is on, with spiral waves sideways and hits along the wave (after a turn at a wall
## too); relay on a beam or a fissure takes on the infusions of the actors its line hits, for that
## hit and every one after while it is on. Cards built in code on a real projectile manager, and
## the real cards in the combo arena where combat has to answer.
##
## godot --headless --path . --script res://tests/core/test_spells_ray_cards.gd

const StaffKit := preload("res://tests/support/staff_kit.gd")
const SpellsScript := preload("res://core/spells/spells.gd")
const ManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const EventsScript := preload("res://core/events/events.gd")
const ArenaScript := preload("res://tests/content/spells/combo_arena.gd")

const DT: float = 1.0 / 60.0


class FakeRegistry:
	extends Node
	var items: Dictionary = {}

	func get_resource(_folder: StringName, id: StringName) -> Resource:
		return items.get(id)


var _fake: FakeRegistry
var _spells: SpellsScript
var _mgr: ManagerScript
var _bus: EventsScript
## Every projectile_hit as [player, target, position, tag].
var _hits: Array = []
## Every pull_requested as [position, to, radius].
var _pulls: Array = []
## The teammate of the last `_relay_scene`.
var _mate: Node2D = null


func before_each() -> void:
	_fake = own(FakeRegistry.new()) as FakeRegistry
	_bus = own(EventsScript.new()) as EventsScript
	_mgr = own(ManagerScript.new()) as ManagerScript
	_mgr.events = _bus
	_mgr.set_cap(512)
	_spells = own(SpellsScript.new()) as SpellsScript
	_spells.registry = _fake
	_spells.bind(_mgr, _bus)
	_mgr.set_anchor(0, Vector2.ZERO)
	_hits.clear()
	_pulls.clear()
	_bus.projectile_hit.connect(func(player: int, target: Node, at: Vector2, tag: int) -> void:
		_hits.append([player, target, at, tag]))
	_bus.pull_requested.connect(func(_player: int, at: Vector2, radius: float, _strength: float, _tag: int, to: Vector2) -> void:
		_pulls.append([at, to, radius]))
	var beam: FormBase = _form(&"beam", 0.0, 0.3)
	beam.motion = FormBase.Motion.RAY
	beam.ray_length = 200.0
	beam.radius = 6.0
	var fissure: FormBase = _form(&"fissure", 0.0, 0.3)
	fissure.motion = FormBase.Motion.FISSURE
	fissure.ray_length = 200.0
	fissure.radius = 6.0
	var long: FormBase = _form(&"long_beam", 0.0, 0.3)
	long.motion = FormBase.Motion.RAY
	long.ray_length = 300.0
	long.radius = 6.0
	_modifier(&"chain", ModifierBase.Behaviour.CHAIN, 1.0)
	_modifier(&"ghost", ModifierBase.Behaviour.GHOST, 1.0)
	_modifier(&"magnet", ModifierBase.Behaviour.MAGNET, 70.0)
	_modifier(&"growth", ModifierBase.Behaviour.GROWTH, 2.0)
	_modifier(&"spiral", ModifierBase.Behaviour.SPIRAL, 24.0)
	_modifier(&"bounce", ModifierBase.Behaviour.BOUNCE, 1.0)
	_modifier(&"hold", ModifierBase.Behaviour.HOLD, 1.0)
	var piercing := ModifierBase.new()
	piercing.extra_pierce = 1
	_put(piercing, &"pierce")


func _put(component: SpellComponent, id: StringName) -> void:
	component.id = id
	component.display_name = String(id).capitalize()
	component.complexity = 1
	_fake.items[id] = component


func _form(id: StringName, speed: float, lifetime: float) -> FormBase:
	var form := FormBase.new()
	form.base_damage = 2
	form.speed = speed
	form.lifetime = lifetime
	form.mana_cost = 2.0
	_put(form, id)
	return form


func _modifier(id: StringName, behaviour: ModifierBase.Behaviour, strength: float) -> void:
	var modifier := ModifierBase.new()
	modifier.behaviour = behaviour
	modifier.behaviour_strength = strength
	_put(modifier, id)


func _build(cards: Array[StringName]) -> void:
	StaffKit.build(_spells, 0, 0, cards)


func _cast(direction: Vector2 = Vector2.RIGHT) -> void:
	_spells.cast_staff(0, 0, Vector2.ZERO, direction, 100.0)


func _target(position: Vector2) -> Node2D:
	var node := Node2D.new()
	root.add_child(node)
	node.global_position = position
	own(node)
	_mgr.add_target(node, 10.0, ManagerScript.LAYER_ENEMY, EventsScript.NO_PLAYER)
	return node


func _tick(steps: int) -> void:
	for i in steps:
		_mgr.step(DT)
		_spells.step(DT)


## The row of the one live beam, or -1.
func _beam() -> int:
	for at in _spells.beam_slots():
		if _spells.beam_on(at):
			return at
	return -1


## How many hits `target` took.
func _hits_on(target: Node2D) -> int:
	var count: int = 0
	for row: Array in _hits:
		if row[1] == target:
			count += 1
	return count


## Lets every beam end and forgets the hits, between two casts in one test.
func _settle() -> void:
	_tick(60)
	_hits.clear()
	_pulls.clear()


# --- Item 13: a ray's chain jump pierces as its carrier does ---------------------------------

## A target on the line of the beam, the next one up from it (where the jump goes) and one just
## past that on the jump's line (only a jump that pierces reaches it).
func _chain_scene() -> Array[Node2D]:
	return [_target(Vector2(100.0, 0.0)), _target(Vector2(100.0, 50.0)), _target(Vector2(100.0, 72.0))] as Array[Node2D]


func test_a_piercing_beams_jump_pierces_too() -> void:
	var scene: Array[Node2D] = _chain_scene()
	_build([&"chain", &"beam"])
	_cast()
	check_equal(_hits_on(scene[1]), 1, "the jump hits the next target")
	check_equal(_hits_on(scene[2]), 0, "a beam without pierce: its jump stops there")
	_settle()
	_build([&"pierce", &"chain", &"beam"])
	_cast()
	check_equal(_hits_on(scene[1]), 1, "the jump hits the next target")
	check_equal(_hits_on(scene[2]), 1, "and goes on through it, as the beam pierces")


func test_a_fissures_jump_pierces_everything_on_its_line() -> void:
	var scene: Array[Node2D] = _chain_scene()
	_build([&"chain", &"fissure"])
	_cast()
	check_equal(_hits_on(scene[0]), 1, "the fissure hits the first target")
	check_equal(_hits_on(scene[1]), 1, "its jump the next")
	check_equal(_hits_on(scene[2]), 1, "and the one past it, as the fissure pierces all")


# --- Item 20: ghost, magnet, growth, spiral -----------------------------------------------

func test_ghost_takes_a_beam_and_a_fissure_through_walls() -> void:
	_mgr.set_walls([Rect2(60.0, -40.0, 16.0, 80.0)] as Array[Rect2])
	var behind: Node2D = _target(Vector2(120.0, 0.0))
	for form: StringName in [&"beam", &"fissure"]:
		_build([form])
		_cast()
		check_equal(_hits_on(behind), 0, "a plain %s stops at the wall" % form)
		_settle()
		_build([&"ghost", form])
		_cast()
		check_equal(_hits_on(behind), 1, "a ghost %s passes through it" % form)
		_settle()


func test_a_ghost_beam_is_drawn_through_the_wall_for_its_whole_length() -> void:
	_mgr.set_walls([Rect2(60.0, -40.0, 16.0, 80.0)] as Array[Rect2])
	_build([&"ghost", &"beam"])
	_cast()
	var at: int = _beam()
	check(at >= 0, "the beam is on")
	if at >= 0:
		check(absf(_spells.beam_reach(at) - 200.0) < 0.01, "its whole 200 px (%s)" % str(_spells.beam_reach(at)))


func test_a_magnet_beam_pulls_toward_its_line_every_step() -> void:
	_build([&"magnet", &"beam"])
	_cast()
	_tick(6)
	check(_pulls.size() >= 6, "a pull every step it is on (%d)" % _pulls.size())
	if not _pulls.is_empty():
		var pull: Array = _pulls[_pulls.size() - 1]
		check((pull[0] as Vector2).is_zero_approx(), "from the staff (%s)" % str(pull[0]))
		check((pull[1] as Vector2).distance_to(Vector2(200.0, 0.0)) < 0.01, "along its whole line (%s)" % str(pull[1]))
		check_equal(pull[2], 70.0, "as far out as the card reaches")
	_settle()
	_build([&"beam"])
	_cast()
	_tick(6)
	check_equal(_pulls.size(), 0, "a plain beam pulls nothing")


func test_a_magnet_beam_draws_an_enemy_onto_its_line_not_toward_the_caster() -> void:
	var arena := ArenaScript.new(root)
	arena.pushable = true
	var imp: Node2D = arena.add_imp(Vector2(120.0, 40.0))
	arena.install_cards(0, 0, ["magnet", "beam"])
	check(arena.cast(0, 0), "the magnet beam is cast")
	arena.run(0.25)
	check(imp.global_position.y < 34.0, "pulled toward the line (%s)" % str(imp.global_position))
	check(absf(imp.global_position.x - 120.0) < 1.0, "straight across it, not toward the staff (%s)" % str(imp.global_position))
	arena.free_all()


func test_a_growing_beam_widens_every_second_it_is_on() -> void:
	var off: Node2D = _target(Vector2(100.0, 20.0))
	_build([&"hold", &"beam"])
	_cast()
	_tick(150)
	check_equal(_hits_on(off), 0, "a plain beam never reaches a target 20 px off its line")
	_cast()
	_settle()
	_build([&"hold", &"growth", &"beam"])
	_cast()
	var at: int = _beam()
	check(at >= 0, "the beam is on")
	if at < 0:
		return
	check(is_equal_approx(_spells.beam_growth(at), 1.0), "as wide as its carrier at first")
	_tick(60)
	check(absf(_spells.beam_growth(at) - 2.0) < 0.1, "twice as wide after a second (%s)" % str(_spells.beam_growth(at)))
	_tick(90)
	check(_hits_on(off) > 0, "and wide enough to hit the target off its line")


func test_a_spiral_beam_waves_and_hits_along_the_wave() -> void:
	# Its wave crests 12 px off its line every BEAM_WAVE / 2, first on the left of its way.
	var crest: float = SpellLimits.BEAM_WAVE * 0.75
	var off: Node2D = _target(Vector2(crest, 21.0))
	_build([&"beam"])
	_cast()
	check_equal(_hits_on(off), 0, "a plain beam misses a target 21 px off its line")
	_settle()
	_build([&"spiral", &"beam"])
	_cast()
	check_equal(_hits_on(off), 1, "a spiral one hits it at its wave's crest")
	var at: int = _beam()
	check(at >= 0, "the beam is on")
	if at < 0:
		return
	var count: int = _spells.beam_point_count(at)
	check(count > 2 and count <= 80, "its path is drawn along the wave, inside the shader's 80 points (%d)" % count)
	var widest: float = 0.0
	for n in count:
		widest = maxf(widest, absf(_spells.beam_point(at, n).y))
	check(absf(widest - 12.0) < 0.5, "12 px either side, half the card's 24 (%s)" % str(widest))


func test_a_spiral_beam_waves_on_after_it_turns_at_a_wall() -> void:
	_mgr.set_walls([Rect2(80.0, -200.0, 16.0, 400.0)] as Array[Rect2])
	_build([&"bounce", &"spiral", &"long_beam"])
	_cast(Vector2(1.0, 1.0).normalized())
	var at: int = _beam()
	check(at >= 0, "the beam is on")
	if at < 0:
		return
	var count: int = _spells.beam_point_count(at)
	var turn: int = 0
	for n in count:
		if _spells.beam_point(at, n).x > _spells.beam_point(at, turn).x:
			turn = n
	check(_spells.beam_point(at, turn).x > 78.0, "it turned at the wall (%s)" % str(_spells.beam_point(at, turn)))
	check(count - 1 - turn >= 3, "and goes on waving, not straight (%d points past the turn)" % (count - 1 - turn))


# --- Item 15: relay on a beam and a fissure ---------------------------------------------------

## The teammate (seat 1, at 60 px) casts frost, then seat 0 casts `cards` through it at an imp at
## 110 px. Returns the arena; the caller frees it.
func _relay_scene(cards: Array) -> ArenaScript:
	var arena := ArenaScript.new(root)
	_mate = arena.add_mate(Vector2(60.0, 0.0), 1)
	arena.add_imp(Vector2(110.0, 0.0))
	arena.install_cards(1, 0, ["frost", "bolt"])
	arena.install_cards(0, 0, cards)
	check(arena.cast(1, 0, Vector2.DOWN), "the teammate casts frost")
	arena.run(0.1)
	return arena


func test_a_relay_beam_takes_on_what_it_passes_through_while_it_is_on() -> void:
	for relay: bool in [false, true]:
		var cards: Array = ["pierce", "beam"]
		if relay:
			cards.push_front("relay")
		var arena: ArenaScript = _relay_scene(cards)
		var imp: Node2D = arena.imps[0]
		# The elements of every hit on the imp.
		var hits: Array = []
		arena.bus.projectile_hit.connect(func(_actor: int, target: Node, _at: Vector2, tag: int) -> void:
			if target == imp:
				var profile: HitProfile = arena.spells.hit_profile(tag)
				hits.append(profile.element_ids.duplicate() if profile != null else PackedStringArray()))
		check(arena.cast(0, 0), "the beam is cast")
		arena.run(0.05)
		# The teammate steps off the line: what the beam took on stays while it is on.
		arena.projectiles.remove_target(_mate)
		arena.run(0.3)
		check(hits.size() >= 2, "the imp is hit on more than one tick (%d)" % hits.size())
		var frosted: int = 0
		for elements: Variant in hits:
			if not (elements as PackedStringArray).is_empty():
				frosted += 1
		if relay:
			check_equal(frosted, hits.size(), "every hit after the teammate carries its frost")
			check(arena.was_given(imp, &"chill"), "the imp is chilled")
		else:
			check_equal(frosted, 0, "without relay nothing is taken on")
			check(not arena.was_given(imp, &"chill"), "and nothing chills")
		arena.free_all()


func test_a_relay_fissure_takes_on_what_it_passes_through() -> void:
	for relay: bool in [false, true]:
		var cards: Array = ["fissure"]
		if relay:
			cards.push_front("relay")
		var arena: ArenaScript = _relay_scene(cards)
		check(arena.cast(0, 0), "the fissure is cast")
		arena.run(0.2)
		check_equal(arena.was_given(arena.imps[0], &"chill"), relay, "the imp past the teammate is chilled only with relay")
		arena.free_all()

