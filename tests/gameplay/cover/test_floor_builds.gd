extends "res://tests/support/suite.gd"
## Builds 1 and 4 of docs/milestones/foundations.md, played with the cards there are on the floor's
## own cover (the floor's first slice, docs/milestones/floor.md): real casters, real shots, the real
## cover area and Combat.
##
## - **The lake** (build 1): a water Nova with Blast soaks the floor round a crowd (its bolts wet their way and
##   end on the bodies); one lightning atom into the water and everybody standing in it is zapped,
##   the soaked set off Current, and its kills are the atom's caster's (`kill_landed` with its tag).
## - **Ice bridge** (build 4): a fountain's puddle; a frost bolt over it freezes its way; who stands
##   on the ice is chilled, never frozen; a fire bolt over it thaws it to water, for the lake.
const Kit := preload("res://tests/gameplay/cover/cover_kit.gd")
const Fixture := preload("res://tests/gameplay/actor/actor_fixture.gd")
const FLOOR: CoverKind = preload("res://content/cover/floor/floor.tres")
const FOUNTAIN: PropBase = preload("res://content/props/fountain/fountain.tres")
const MIDDLE: Vector2 = Vector2(160.0, 80.0)

var _kit: Kit
var _struck: Array = []
var _reactions: Array = []
var _kills: Array = []


func before_each() -> void:
	_kit = Kit.new(root, FLOOR)
	_kit.world.projectiles.set_cap(512)
	_struck.clear()
	_reactions.clear()
	_kills.clear()
	_kit.world.bus.floor_strike_requested.connect(func(caster: int, target: Node, _e: StringName, _d: float, tag: int) -> void: _struck.append([caster, target, tag]))
	_kit.world.bus.reaction_landed.connect(func(_c: int, reaction: StringName, target: Node, _p: Vector2, _t: int, _s: int) -> void: _reactions.append([reaction, target]))
	_kit.world.bus.kill_landed.connect(func(caster: int, target: Node, _p: Vector2, tag: int, _s: int) -> void: _kills.append([caster, target, tag]))


func after_each() -> void:
	_kit.free_all()


## `count` ticks of the game's order: the bodies, the shots, the spells and Combat, then the cover.
func _tick(count: int) -> void:
	for i in count:
		_kit.world.run(1)
		_kit.cover.step(Fixture.STEP)


func _dummy(at: Vector2, health: float) -> Actor:
	var body: Actor = _kit.world.actor(at, [&"health", &"hurtbox"], Fixture.Scripted.new())
	body.health.max_health = health
	body.health.reset(health)
	return body


## A caster of `cards` aiming `aim`, its staff's tip (its muzzle) at `muzzle`.
func _caster(muzzle: Vector2, cards: Array[StringName], aim: Vector2) -> Actor:
	var caster: Actor = _kit.world.actor(muzzle, [&"caster"], Fixture.Scripted.new(), [cards])
	caster.aim = aim.normalized()
	caster.position += muzzle - caster.muzzle_position()
	return caster


func _state_at(at: Vector2) -> StringName:
	return _kit.state_of(_kit.cover.layout.cell_of(at))


func _struck_bodies() -> Array[Node]:
	var bodies: Array[Node] = []
	for heard: Array in _struck:
		if not bodies.has(heard[1]):
			bodies.append(heard[1])
	return bodies


func test_build_1_the_lake() -> void:
	var crowd: Array[Actor] = []
	for n in 8:
		crowd.append(_dummy(MIDDLE + Vector2.from_angle(float(n) * TAU / 8.0) * 48.0, 1000.0))
	var nova: Actor = _caster(MIDDLE, [&"water", &"blast", &"nova", &"bolt"], Vector2.RIGHT)
	check(nova.caster.cast(0), "the water Nova leaves")
	_tick(12)
	var wet: int = _kit.count_in(&"wet") + _kit.count_in(&"wetting")
	check(wet >= 20, "the floor round the crowd is wet (%d cells)" % wet)
	var soaked: int = 0
	for body in crowd:
		if _kit.has_status(body, &"soak"):
			soaked += 1
	check(soaked >= 6, "the crowd is soaked (%d of 8)" % soaked)
	_kit.world.actors.erase(nova)
	nova.free()
	# One more, nearly dead, in a puddle the lake runs to, out of the crowd's Current (whose kills are
	# a reaction's, never a spell's own): the lake's own kill is the atom's caster's.
	var east: Vector2 = crowd[0].position
	for x in range(0, 9):
		_kit.world.bus.floor_touched.emit(-1, &"water", east + Vector2(16.0 * float(x), 0.0), 0.0, 0)
	var weak: Actor = _dummy(east + Vector2(128.0, 0.0), 3.0)
	_tick(8)
	check_equal(_state_at(weak.position), &"wet", "the weak one stands in the water")
	check(is_instance_valid(weak) and _kit.world.combat.health_of(weak) > 0.0, "alive")
	var before: Array[float] = []
	for body in crowd:
		before.append(_kit.world.combat.health_of(body))
	var atom: Actor = _caster(Vector2(20.0, 20.0), [&"lightning", &"atom"], MIDDLE - Vector2(20.0, 20.0))
	check(atom.caster.cast(0), "one lightning atom")
	_tick(24)
	check(_kit.count_in(&"live") + _kit.count_in(&"spent") >= wet - 2, "the whole lake went live (%d of %d)" % [_kit.count_in(&"live") + _kit.count_in(&"spent"), wet])
	var struck: Array[Node] = _struck_bodies()
	var hurt: int = 0
	for n in crowd.size():
		if struck.has(crowd[n]) and _kit.world.combat.health_of(crowd[n]) < before[n]:
			hurt += 1
	check(hurt >= 6, "everybody standing in it is zapped (%d of 8)" % hurt)
	var currents: int = 0
	for heard: Array in _reactions:
		if heard[0] == &"current":
			currents += 1
	check(currents >= 4, "the soaked set off Current (%d)" % currents)
	for heard: Array in _struck:
		check_equal(heard[0], atom.caster_number(), "zapped as the atom's caster's")
	var killed: bool = false
	for heard: Array in _kills:
		if heard[1] == weak:
			killed = true
			check_equal(heard[0], atom.caster_number(), "the kill is the atom's caster's")
			check_equal(SpellTag.caster_of(int(heard[2])), atom.caster_number(), "with its spell's tag (on kill hears it)")
	var on_weak: Array = []
	for heard: Array in _struck:
		if heard[1] == weak:
			on_weak.append(heard)
	check(killed, "the weak one in the water died, a kill that counts (%s %s)" % [_kills, on_weak])


func test_build_4_the_ice_bridge() -> void:
	var fountain: Actor = _kit.world.add(PropBody.make(FOUNTAIN), MIDDLE)
	_tick(64)
	# Its puddle laid, the fountain goes: its jets on a chilled body would freeze it (Rime), which is
	# the jets' doing, not the ice's.
	_kit.world.actors.erase(fountain)
	fountain.free()
	var wet: int = _kit.count_in(&"wet") + _kit.count_in(&"wetting")
	check(wet >= 9, "the fountain's puddle (%d cells)" % wet)
	var lane: float = MIDDLE.y + 20.0
	check_equal(_state_at(Vector2(MIDDLE.x, lane)), &"wet", "the puddle reaches the lane")
	var frost: Actor = _caster(Vector2(40.0, lane), [&"frost", &"bolt"], Vector2.RIGHT)
	check(frost.caster.cast(0), "a frost bolt over it")
	_tick(12)
	var ice: int = _kit.count_in(&"ice") + _kit.count_in(&"freezing")
	check(ice >= 3, "it froze the water along its way (%d cells)" % ice)
	check_equal(_state_at(Vector2(MIDDLE.x, lane)), &"ice", "an ice bridge across the puddle")
	var walker: Actor = _dummy(Vector2(MIDDLE.x, lane), 1000.0)
	var chilled: bool = false
	var frozen: bool = false
	for i in 48:
		_tick(1)
		chilled = chilled or _kit.has_status(walker, &"chill")
		frozen = frozen or _kit.has_status(walker, &"freeze")
	check(chilled, "who stands on it is chilled")
	check(not frozen, "three seconds on it: never frozen")
	_kit.world.actors.erase(walker)
	walker.free()
	_kit.world.actors.erase(frost)
	frost.free()
	var fire: Actor = _caster(Vector2(40.0, lane), [&"fire", &"bolt"], Vector2.RIGHT)
	check(fire.caster.cast(0), "a fire bolt over it")
	_tick(12)
	check(_state_at(Vector2(MIDDLE.x, lane)) == &"wet" or _state_at(Vector2(MIDDLE.x, lane)) == &"thawing", "thawed to water (%s)" % _state_at(Vector2(MIDDLE.x, lane)))
	_tick(4)
	check_equal(_state_at(Vector2(MIDDLE.x, lane)), &"wet", "water again, for the lake")



## The owner, 2026-11-25: a foe killed by the Current of a live lake is its lighter's kill
## (`kill_landed` with its tag: on kill), though a reaction's kills are no spell's own elsewhere. The
## zap (4) leaves the soaked body half a point; the Current it sets off on that body (5) kills it.
func test_a_kill_by_the_lakes_current_is_the_lighters() -> void:
	for x in range(0, 4):
		_kit.world.bus.floor_touched.emit(-1, &"water", MIDDLE + Vector2(16.0 * float(x), 0.0), 0.0, 0)
	var weak: Actor = _dummy(MIDDLE + Vector2(32.0, 0.0), 4.5)
	_tick(8)
	check(_kit.has_status(weak, &"soak"), "it stands soaked in the lake")
	var tag: int = SpellTag.make(3, 1, 0, 0)
	_kit.world.bus.floor_touched.emit(3, &"lightning", MIDDLE, 0.0, tag)
	_tick(12)
	var current: bool = false
	for heard: Array in _reactions:
		current = current or heard[0] == &"current"
	check(current, "the zap set off Current")
	check_equal(_kills.size(), 1, "one kill heard (%s)" % [_kills])
	if _kills.size() == 1:
		check(_kills[0][1] == weak, "its")
		check_equal(_kills[0][0], 3, "the lighter's kill")
		check_equal(_kills[0][2], tag, "with its spell's tag (on kill hears it)")
