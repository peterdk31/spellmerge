extends "res://tests/support/suite.gd"
## Plow (boss plan OB11, core/spells/plow.gd): what a carrier with it hits rides along in front of
## what moves it. A dash's body carries what its pass strikes as far as it goes and lets it go with a
## shove; pinned against a wall the carried body takes twice the hit and the dash ends there; one
## that walks out sideways slips off with no pin; a body that cannot move (a prop) is never carried;
## a barrier that takes the hit whole carries nothing; the carrier's contact damage reaches what it
## carries; a flying shot with Plow is a battering ram the bodies it carries do not spend. Real
## actors (a Hurtbox and a Mover each) and the real cards, moved against the walls as the game moves
## them.
const Fixture := preload("res://tests/gameplay/actor/actor_fixture.gd")
const ActorsScript := preload("res://core/actors/actors.gd")

var _world: Fixture


func before_each() -> void:
	_world = Fixture.new(root)


func after_each() -> void:
	_world.free_all()


## A wizard at `at` aiming right, its staff `cards` (`kinds` its components beside a caster).
func _dasher(at: Vector2, cards: Array[StringName], kinds: Array[StringName] = [&"health", &"hurtbox", &"mover"]) -> Actor:
	var controller := Fixture.Scripted.new()
	controller.team = ActorsScript.TEAM_WIZARDS
	controller.aim = Vector2.RIGHT
	var all: Array[StringName] = kinds.duplicate()
	all.append(&"caster")
	return _world.actor(at, all, controller, [cards])


## An enemy at `at` that can be moved (a Mover), walking `walk` (its intent).
func _target(at: Vector2, walk: Vector2 = Vector2.ZERO) -> Actor:
	var controller := Fixture.Scripted.new()
	controller.move = walk
	return _world.actor(at, [&"health", &"hurtbox", &"mover"], controller)


func _lost(body: Actor) -> int:
	return body.health.max_health - body.health.health


func _walk(count: int) -> void:
	for i in count:
		for body in _world.actors:
			if is_instance_valid(body) and body.is_inside_tree():
				body.step(Fixture.STEP)
				body.move(Fixture.STEP)
		_world.projectiles.step(Fixture.STEP)
		_world.spells.step(Fixture.STEP)
		_world.combat.step(Fixture.STEP)


## The damage one hit of `cards` deals (its compiled spell's, rounded as health is).
func _hit_of(cards: Array[StringName]) -> float:
	var staff: CompiledStaff = _world.spells.compile_staff(cards, null)
	return staff.casts[0].group.spells[0].damage


func test_a_plowed_dash_carries_what_it_strikes_and_lets_it_go_with_a_shove() -> void:
	var dasher: Actor = _dasher(Vector2.ZERO, [&"plow", &"dash"])
	var target: Actor = _target(Vector2(30.0, 0.0))
	_walk(1)
	check(dasher.caster.cast(0), "it dashes")
	var carried: bool = false
	var let_go: Vector2 = Vector2.INF
	for i in 40:
		_walk(1)
		var now: bool = _world.spells.plow().carrying(target.id, _world.tag_of(dasher))
		if carried and not now and not let_go.is_finite():
			let_go = target.global_position
		carried = carried or now
	check(carried, "its pass carried the body")
	check(target.global_position.x > 70.0, "the body rode along in front of it (%s)" % target.global_position)
	check(target.global_position.x > dasher.global_position.x, "ahead of the dasher (%s, %s)" % [target.global_position, dasher.global_position])
	check(_lost(target) > 0, "the pass hit it")
	check_equal(_world.spells.plow().carried_count(), 0, "let go when the dash was over")
	# The shove: it slid on after the dash was over, pushed by the hit.
	check(let_go.is_finite() and target.global_position.x > let_go.x + 0.5, "shoved on as it was let go (%s -> %s)" % [let_go, target.global_position])


func test_a_plain_dash_carries_nothing() -> void:
	var dasher: Actor = _dasher(Vector2.ZERO, [&"dash"])
	var target: Actor = _target(Vector2(30.0, 0.0))
	_walk(1)
	check(dasher.caster.cast(0), "it dashes")
	_walk(40)
	check(target.global_position.x < 50.0, "the body was passed, only knocked (%s)" % target.global_position)


func test_pinned_against_a_wall_it_takes_twice_the_hit_and_the_dash_ends_there() -> void:
	_world.projectiles.set_walls([Rect2(60.0, -200.0, 40.0, 400.0)] as Array[Rect2])
	var dasher: Actor = _dasher(Vector2.ZERO, [&"plow", &"dash"])
	var target: Actor = _target(Vector2(30.0, 0.0))
	var pinned: Array[bool] = []
	_world.bus.carry_ended.connect(func(_caster: int, _body: Node, carrier: int, _way: Vector2, was_pinned: bool, _tag: int) -> void:
		pinned.append(was_pinned)
		check_equal(carrier, dasher.id, "the body that carried it is named"))
	_walk(1)
	check(dasher.caster.cast(0), "it dashes at the wall")
	_walk(40)
	check_equal(pinned, [true] as Array[bool], "the carry ended pinned")
	var hit: float = _hit_of([&"plow", &"dash"])
	var pin: int = maxi(roundi(hit * SpellLimits.PIN_SHARE), 1)
	check_equal(_lost(target), roundi(hit) + pin, "the pass and a pin of twice the hit (%s + %s)" % [hit, pin])
	check(not dasher.mover.is_dashing(), "the dash ended there")
	check(dasher.global_position.x <= target.global_position.x, "behind the pinned body (%s, %s)" % [dasher.global_position, target.global_position])


func test_a_pin_ends_the_carriers_dash_where_it_is() -> void:
	# In the open, a slow dash's carried body is told pinned (as its mover finds it against a wall).
	var dasher: Actor = _dasher(Vector2.ZERO, [&"slow", &"plow", &"dash"])
	var target: Actor = _target(Vector2(20.0, 0.0))
	_walk(1)
	check(dasher.caster.cast(0), "it dashes")
	var steps: int = 0
	while _world.spells.plow().carried_count() == 0 and steps < 30:
		_walk(1)
		steps += 1
	check(_world.spells.plow().carrying(target.id, _world.tag_of(dasher)), "it carries the body")
	_world.spells.plow().pinned(target.id)
	_walk(3)
	check(not dasher.mover.is_dashing(), "its dash ended at the pin, as if it met the wall itself")
	check(dasher.global_position.x < 60.0, "far short of its whole way (%s)" % dasher.global_position)


## The Scripted controller of `body`.
func _controller(body: Actor) -> Fixture.Scripted:
	for child in body.get_children():
		if child is Fixture.Scripted:
			return child as Fixture.Scripted
	return null


func test_walking_out_sideways_slips_off_with_no_pin() -> void:
	_world.projectiles.set_walls([Rect2(200.0, -400.0, 40.0, 800.0)] as Array[Rect2])
	# A long dash (Lumber: 240 px), and a body that walks out of it sideways once it is carried.
	var dasher: Actor = _dasher(Vector2.ZERO, [&"lumber", &"plow", &"dash"])
	var target: Actor = _target(Vector2(30.0, 0.0))
	var ends: Array[Vector2] = []
	_world.bus.carry_ended.connect(func(_caster: int, _body: Node, _carrier: int, way: Vector2, was_pinned: bool, _tag: int) -> void:
		check(not was_pinned, "it was not pinned")
		ends.append(way))
	_walk(1)
	check(dasher.caster.cast(0), "it dashes")
	var carried: int = 0
	for i in 90:
		_walk(1)
		if _world.spells.plow().carried_count() > 0:
			carried += 1
			if carried == 3:
				_controller(target).move = Vector2.DOWN
	check(carried >= 3, "it was carried a while")
	check_equal(ends.size(), 1, "the carry ended once")
	check(not ends.is_empty() and ends[0] == Vector2.ZERO, "slipped off: no shove")
	check(target.global_position.x < 190.0, "short of the wall (%s)" % target.global_position)
	check_equal(_lost(target), roundi(_hit_of([&"lumber", &"plow", &"dash"])), "it took only the pass")


func test_it_cannot_walk_back_through_what_carries_it() -> void:
	var dasher: Actor = _dasher(Vector2.ZERO, [&"lumber", &"plow", &"dash"])
	var target: Actor = _target(Vector2(30.0, 0.0))
	_walk(1)
	check(dasher.caster.cast(0), "it dashes")
	var carried: int = 0
	var behind: bool = false
	for i in 60:
		_walk(1)
		if _world.spells.plow().carried_count() > 0:
			carried += 1
			if carried == 3:
				_controller(target).move = Vector2.LEFT
			elif carried > 3:
				behind = behind or target.global_position.x < dasher.global_position.x
	check(carried > 10, "it was carried on (%s steps)" % carried)
	check(not behind, "walking against the carry, it stays in front")


func test_a_body_that_cannot_move_is_never_carried() -> void:
	var dasher: Actor = _dasher(Vector2.ZERO, [&"plow", &"dash"])
	var prop: Actor = _world.prop(Vector2(30.0, 30.0))
	_walk(1)
	check(dasher.caster.cast(0), "it dashes through the prop")
	var carried: bool = false
	for i in 30:
		_walk(1)
		carried = carried or _world.spells.plow().carried_count() > 0
	check(not carried, "a prop stands where it is")
	check_equal(prop.global_position, Vector2(30.0, 30.0), "and is not moved")


func test_a_barrier_that_takes_the_hit_carries_nothing() -> void:
	var dasher: Actor = _dasher(Vector2.ZERO, [&"plow", &"dash"])
	var target: Actor = _target(Vector2(30.0, 0.0))
	_world.combat.give_shield(target, 1, 5.0)
	_walk(1)
	check(dasher.caster.cast(0), "it dashes")
	_walk(40)
	check_equal(_lost(target), 0, "the barrier took the hit")
	check(target.global_position.x < 40.0, "and nothing carried the body (%s)" % target.global_position)
	check_equal(_world.spells.plow().carried_count(), 0, "no carry is left")


func test_the_carriers_contact_reaches_what_it_carries() -> void:
	# An enemy dasher that touches, carrying a wizard at the edge of its pass (bigger: a wide one),
	# out of its own hurt circle's reach.
	var controller := Fixture.Scripted.new()
	controller.team = ActorsScript.TEAM_ENEMIES
	controller.aim = Vector2.RIGHT
	var dasher: Actor = _world.actor(Vector2.ZERO, [&"health", &"hurtbox", &"mover", &"contact", &"caster"], controller, [[&"bigger", &"plow", &"dash"] as Array[StringName]])
	var contact: Contact = null
	for child in dasher.get_children():
		if child is Contact:
			contact = child as Contact
	contact.damage = 5
	# Registered again with its touch (a hurtbox hands Combat its contact as it registers).
	dasher.hurtbox.set_enabled(false)
	dasher.hurtbox.set_enabled(true)
	var wizard_controller := Fixture.Scripted.new()
	wizard_controller.team = ActorsScript.TEAM_WIZARDS
	var wizard: Actor = _world.actor(Vector2(30.0, 18.0), [&"health", &"hurtbox", &"mover"], wizard_controller)
	_walk(1)
	check(dasher.caster.cast(0), "it dashes")
	_walk(40)
	var hit: int = roundi(_hit_of([&"bigger", &"plow", &"dash"]))
	check(_lost(wizard) >= hit + 5, "the pass and the contact (%s of %s + 5)" % [_lost(wizard), hit])


func test_a_plowed_bolt_is_a_battering_ram() -> void:
	var shooter: Actor = _dasher(Vector2.ZERO, [&"plow", &"bolt"], [&"health", &"hurtbox"])
	var first: Actor = _target(Vector2(40.0, -12.0))
	var second: Actor = _target(Vector2(60.0, -12.0))
	_walk(1)
	check(shooter.caster.cast(0), "it fires")
	var most: int = 0
	for i in 30:
		_walk(1)
		most = maxi(most, _world.spells.plow().carried_count())
	check_equal(most, 2, "the bolt carried both bodies at once: they did not spend it")
	check(first.global_position.x > 90.0 and second.global_position.x > 90.0, "both rode along with it (%s, %s)" % [first.global_position, second.global_position])


func test_a_plows_hit_arms_twice_its_damage() -> void:
	var spell: CompiledSpell = _world.spells.compile_staff([&"plow", &"dash"] as Array[StringName], null).casts[0].group.spells[0]
	check_equal(spell.hit.pin, maxi(roundi(spell.damage * SpellLimits.PIN_SHARE), 1), "its pin is twice the hit")
	var bolt: CompiledSpell = _world.spells.compile_staff([&"plow", &"bolt"] as Array[StringName], null).casts[0].group.spells[0]
	var plain: CompiledSpell = _world.spells.compile_staff([&"bolt"] as Array[StringName], null).casts[0].group.spells[0]
	check_equal(bolt.pierce, plain.pierce + SpellLimits.PLOW_MOST, "a flying shot's carried bodies do not spend it")
	var dash: CompiledSpell = _world.spells.compile_staff([&"dash"] as Array[StringName], null).casts[0].group.spells[0]
	check_equal(dash.hit.pin, 0, "a hit with no Plow arms none")


func test_two_plowed_dashes_never_carry_each_other() -> void:
	# Regression (review of OB11): an enemy's Plow dash carries a wizard, who dashes back with its
	# own; each carrying the other, both ran off ever faster, through the walls.
	_world.projectiles.set_walls([Rect2(400.0, -400.0, 10.0, 800.0)] as Array[Rect2])
	var controller := Fixture.Scripted.new()
	controller.team = ActorsScript.TEAM_ENEMIES
	controller.aim = Vector2.RIGHT
	var enemy: Actor = _world.actor(Vector2.ZERO, [&"health", &"hurtbox", &"mover", &"caster"], controller, [[&"lumber", &"plow", &"dash"] as Array[StringName]])
	var wizard: Actor = _dasher(Vector2(30.0, 0.0), [&"lumber", &"plow", &"dash"])
	_controller(wizard).aim = Vector2.LEFT
	wizard.aim = Vector2.LEFT
	_walk(1)
	check(enemy.caster.cast(0), "the enemy dashes")
	var steps: int = 0
	while not _world.spells.plow().carrying(wizard.id, _world.tag_of(enemy)) and steps < 30:
		_walk(1)
		steps += 1
	check(_world.spells.plow().carrying(wizard.id, _world.tag_of(enemy)), "it carries the wizard")
	check(wizard.caster.cast(0), "the wizard dashes back into it")
	var most: int = 0
	for i in 90:
		_walk(1)
		most = maxi(most, _world.spells.plow().carried_count())
	check_equal(most, 1, "the carrier is never carried by what it carries")
	for body: Actor in [enemy, wizard]:
		check(body.global_position.x < 400.0 and body.global_position.x > -400.0, "nobody ran off (%s)" % body.global_position)


func test_a_plowed_bolt_pinned_against_a_wall_hits_once_and_pins_once() -> void:
	# Regression (review of OB11): the bolt caught up with the body it carried at the wall and hit
	# it again, arming a second pin.
	_world.projectiles.set_walls([Rect2(150.0, -400.0, 40.0, 800.0)] as Array[Rect2])
	var shooter: Actor = _dasher(Vector2.ZERO, [&"plow", &"bolt"], [&"health", &"hurtbox"])
	var target: Actor = _target(Vector2(40.0, -12.0))
	var pins: Array[bool] = []
	_world.bus.carry_ended.connect(func(_caster: int, _body: Node, _carrier: int, _way: Vector2, was_pinned: bool, _tag: int) -> void: pins.append(was_pinned))
	_walk(1)
	check(shooter.caster.cast(0), "it fires at the wall")
	_walk(60)
	check_equal(pins, [true] as Array[bool], "carried into the wall and pinned")
	var hit: float = _hit_of([&"plow", &"bolt"])
	check_equal(_lost(target), roundi(hit) + maxi(roundi(hit * SpellLimits.PIN_SHARE), 1), "one hit and one pin of twice it")


func test_a_pin_in_the_moves_last_step_still_counts() -> void:
	# Regression (review of OB11): a pass that ended before the next step lost the pin its mover
	# found, and shoved the body into the wall instead.
	var dasher: Actor = _dasher(Vector2.ZERO, [&"slow", &"plow", &"dash"])
	var target: Actor = _target(Vector2(20.0, 0.0))
	var ends: Array[bool] = []
	_world.bus.carry_ended.connect(func(_caster: int, _body: Node, _carrier: int, _way: Vector2, was_pinned: bool, _tag: int) -> void: ends.append(was_pinned))
	_walk(1)
	check(dasher.caster.cast(0), "it dashes")
	var steps: int = 0
	while _world.spells.plow().carried_count() == 0 and steps < 30:
		_walk(1)
		steps += 1
	_world.spells.plow().pinned(target.id)
	_world.spells.plow().let_go(_world.tag_of(dasher), dasher.id, -1)
	check_equal(ends, [true] as Array[bool], "let go pinned")
	var hit: float = _hit_of([&"slow", &"plow", &"dash"])
	_world.combat.step(Fixture.STEP)
	check_equal(_lost(target), roundi(hit) + maxi(roundi(hit * SpellLimits.PIN_SHARE), 1), "the pass and the pin")


func test_a_body_that_stops_being_a_target_is_dropped() -> void:
	# A downed body leaves the targets (its hurtbox goes, decision 21): its carry is dropped, with no
	# pin and no shove.
	var dasher: Actor = _dasher(Vector2.ZERO, [&"lumber", &"plow", &"dash"])
	var target: Actor = _target(Vector2(30.0, 0.0))
	var ends: Array[Vector2] = []
	_world.bus.carry_ended.connect(func(_caster: int, _body: Node, _carrier: int, way: Vector2, was_pinned: bool, _tag: int) -> void:
		check(not was_pinned, "not pinned")
		ends.append(way))
	_walk(1)
	check(dasher.caster.cast(0), "it dashes")
	var steps: int = 0
	while _world.spells.plow().carried_count() == 0 and steps < 30:
		_walk(1)
		steps += 1
	target.hurtbox.set_enabled(false)
	var at: Vector2 = target.global_position
	_walk(5)
	check_equal(ends, [Vector2.ZERO] as Array[Vector2], "dropped, no shove")
	check(target.global_position.distance_to(at) < 1.0, "and it stays where it was (%s -> %s)" % [at, target.global_position])
