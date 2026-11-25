extends "res://tests/support/suite.gd"
## Siphon pays for the Current (the owner, 2026-11-25): every foe a Current runs to from a hit of a
## spell with Siphon pays that caster's Siphon, as the spell's own hit, whatever its carrier: a shot (a bolt),
## a ray (a beam), a sweep (a swing), or the floor's strike of a live lake. Combat says where a reaction ran
## (`reaction_struck`, with the spell's tag); Spells pays the Siphon for a foe struck so.
const Fixture := preload("res://tests/gameplay/actor/actor_fixture.gd")

## Each kind of carrier (a shot, a ray, a sweep; the floor below), and how far ahead of its caster the first body stands (in its reach).
const CARRIERS: Array = [[&"bolt", 60.0], [&"beam", 60.0], [&"swing", 22.0]]

var _world: Fixture
## Every `reaction_struck` heard: [caster, reaction, target, tag]; every refund: [actor, staff, amount].
var _struck: Array = []
var _refunds: Array = []


func before_each() -> void:
	_world = Fixture.new(root)
	_world.projectiles.set_cap(512)
	_struck.clear()
	_refunds.clear()
	_world.bus.reaction_struck.connect(func(caster: int, reaction: StringName, target: Node, tag: int) -> void: _struck.append([caster, reaction, target, tag]))
	_world.bus.mana_refund_requested.connect(func(actor: int, staff: int, amount: float) -> void: _refunds.append([actor, staff, amount]))


func after_each() -> void:
	_world.free_all()


## A soaked dummy at `at` that only stands and is hurt.
func _soaked(at: Vector2) -> Actor:
	var body: Actor = _world.actor(at, [&"health", &"hurtbox"], Fixture.Scripted.new())
	body.health.max_health = 1000.0
	body.health.reset(1000.0)
	_world.combat.apply_status(-1, body, &"soak", 30.0, 25.0)
	return body


## A caster of `siphon · lightning · <carrier>` aiming right, its staff's tip at `muzzle`.
func _caster(muzzle: Vector2, carrier: StringName) -> Actor:
	var caster: Actor = _world.actor(muzzle, [&"caster"], Fixture.Scripted.new(), [[&"siphon", &"lightning", carrier]])
	caster.aim = Vector2.RIGHT
	caster.position += muzzle - caster.muzzle_position()
	return caster


func _struck_bodies(target: Node) -> Array:
	var found: Array = []
	for heard: Array in _struck:
		if heard[2] == target:
			found.append(heard)
	return found


func test_every_carriers_current_pays_its_siphon_for_the_foe_it_runs_to() -> void:
	for row: Array in CARRIERS:
		var carrier: StringName = row[0]
		_world.free_all()
		before_each()
		var muzzle := Vector2(100.0, 100.0)
		var hit: Actor = _soaked(muzzle + Vector2(float(row[1]), 0.0))
		# Off the carrier's way, within Current's reach of the body it hits.
		var beside: Actor = _soaked(hit.position + Vector2(0.0, 48.0))
		var caster: Actor = _caster(muzzle, carrier)
		check(caster.caster.cast(0), "%s: cast" % carrier)
		_world.run(16)
		var ran: Array = _struck_bodies(beside)
		check(not ran.is_empty(), "%s: the Current ran to the body beside it" % carrier)
		if ran.is_empty():
			continue
		check_equal(ran[0][0], caster.caster_number(), "%s: as the caster's" % carrier)
		check_equal(SpellTag.caster_of(int(ran[0][3])), caster.caster_number(), "%s: with its spell's tag" % carrier)
		check_equal(ran[0][1], &"current", "%s: by Current" % carrier)
		var paid: int = 0
		for refund: Array in _refunds:
			if refund[0] == caster.caster_number():
				paid += 1
		check(paid >= 2, "%s: Siphon paid for the body hit and the one the Current ran to (%d refunds)" % [carrier, paid])


func test_the_floors_current_pays_its_siphon_too() -> void:
	var muzzle := Vector2(100.0, 100.0)
	var caster: Actor = _caster(muzzle, &"bolt")
	check(caster.caster.cast(0), "cast, for its spell's tag")
	var tag: int = -1
	for s in _world.projectiles.get_cap():
		if _world.projectiles.is_alive(s) and _world.projectiles.get_actor_of(s) == caster.caster_number():
			tag = _world.projectiles.get_tag_of(s)
	_world.projectiles.remove_by_tag(tag)
	var hit: Actor = _soaked(Vector2(300.0, 300.0))
	var beside: Actor = _soaked(Vector2(300.0, 340.0))
	_world.run(1)
	_refunds.clear()
	_world.bus.floor_strike_requested.emit(caster.caster_number(), hit, &"lightning", 4.0, tag)
	check(not _struck_bodies(beside).is_empty(), "the lake's Current ran to the body beside it")
	check_equal(_refunds.size(), 2, "Siphon paid for the body the floor struck and the one its Current ran to")


func test_a_current_running_to_a_friend_pays_nothing() -> void:
	var muzzle := Vector2(100.0, 100.0)
	var caster: Actor = _caster(muzzle, &"bolt")
	var hit: Actor = _soaked(muzzle + Vector2(60.0, 0.0))
	check(caster.caster.cast(0), "cast")
	# The caster itself stands soaked within the Current's reach of the body it hits.
	_world.combat.apply_status(-1, caster, &"soak", 30.0, 25.0)
	_world.run(16)
	var ran: Array = _struck_bodies(caster)
	var paid_for_self: int = 0
	for heard: Array in ran:
		paid_for_self += 1
	check(paid_for_self <= 1, "the Current may run to its caster")
	var paid: int = 0
	for refund: Array in _refunds:
		paid += 1
	check(paid <= 1, "but Siphon pays only for the foe hit, not for its own body (%d refunds)" % paid)
	check(is_instance_valid(hit), "the body hit stands")
