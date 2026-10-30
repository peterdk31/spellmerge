extends "res://tests/support/suite.gd"
## Health (actors G4): `take` and `heal` within 0 and `max_health`, `protect` for a while,
## `changed` on every change and `depleted` once at 0; Combat takes and heals through it (actors
## G5), and the bus's `damage_dealt` and `heal_dealt` are not its way in. Contact and Hurtbox hand
## the actor's circle and touch damage to Combat.
##
## godot --headless --path . --script res://tests/gameplay/actor/test_actor_health.gd

const Fixture := preload("res://tests/gameplay/actor/actor_fixture.gd")

var _world: Fixture
var _changes: Array[int] = []
var _depleted: Array[int] = []


func before_each() -> void:
	_world = Fixture.new(root)
	_changes.clear()
	_depleted.clear()


func after_each() -> void:
	_world.free_all()


func _body() -> Actor:
	var body: Actor = _world.actor(Vector2.ZERO, [&"health"])
	body.downable = true
	body.health.changed.connect(func(health: int, _most: int) -> void: _changes.append(health))
	body.health.depleted.connect(func(killer: int) -> void: _depleted.append(killer))
	return body


func test_take_and_heal_stay_between_zero_and_the_most() -> void:
	var body: Actor = _body()
	check(body.health.take(20), "a hit counts")
	check_equal(body.health.health, 30, "it loses what it took")
	check(body.health.heal(100), "a heal counts")
	check_equal(body.health.health, 50, "never above the most")
	check(not body.health.heal(5), "a full actor gains nothing")
	check(not body.health.take(0) and not body.health.take(-3), "nothing for 0 or less")
	check_equal(_changes, [30, 50] as Array[int], "changed on each change only")


func test_depleted_comes_once_with_the_killer() -> void:
	var body: Actor = _body()
	body.health.take(30, 2)
	body.health.take(30, 1)
	check_equal(body.health.health, 0, "not below 0")
	check(not body.health.take(5, 3), "nothing more at 0")
	check(not body.health.heal(5), "and no heal: a revive is the way back")
	check_equal(_depleted, [1] as Array[int], "once, naming the last hit's player")
	body.health.reset(25)
	check_equal(body.health.health, 25, "a reset brings it back")


func test_protection_holds_for_its_time() -> void:
	var body: Actor = _body()
	body.health.protect(0.25)
	check(not body.health.take(10), "protected")
	_world.run(4)
	check(not body.health.is_protected(), "for the time asked")
	check(body.health.take(10), "then it can be hurt")


func test_combat_takes_and_heals_through_health_and_the_bus_does_not() -> void:
	var body: Actor = _world.actor(Vector2.ZERO, [&"health", &"hurtbox"])
	var other: Actor = _world.actor(Vector2(200.0, 0.0), [&"health", &"hurtbox"])
	check(_world.combat.hit(0, body, 15), "Combat's hit counts")
	check_equal(body.health.health, 35, "and takes from its Health")
	check_equal(other.health.health, 50, "another actor is untouched")
	_world.bus.damage_dealt.emit(0, body, 15, Vector2.ZERO)
	_world.bus.heal_dealt.emit(0, body, 15, Vector2.ZERO)
	check_equal(body.health.health, 35, "the bus is for the rest of the game: Health does not hear it")
	# A mend heals its caster's team: the actor's own, cast on itself.
	_world.table.set_driver(body.id, Actor.ActorsScript.TEAM_WIZARDS, -1)
	var mend := HitProfile.new()
	mend.heal = 5
	var spell := CompiledSpell.new()
	spell.hit = mend
	var tag: int = SpellTag.make(body.id, 0, 1, 1)
	_world.spells._profiles[tag] = spell
	_world.bus.projectile_hit.emit(body.id, body, body.position, tag, -1)
	check_equal(body.health.health, 40, "a mend heals it through its Health")


func test_the_hurtbox_hands_its_circle_and_the_touch_to_combat() -> void:
	var imp := Actor.new()
	var health := Health.new()
	health.max_health = 30
	var hurtbox := Hurtbox.new()
	hurtbox.radius = 11.0
	var contact := Contact.new()
	contact.damage = 4
	for component: Node in [health, hurtbox, contact]:
		imp.add_child(component)
	_world.add(imp, Vector2(40.0, 0.0))
	check(_world.combat.is_registered(imp), "registered with Combat")
	check_equal(_world.combat.actor_of(imp), imp.id, "under its actor id")
	check_equal(_world.combat.health_of(imp), 30, "with its health")
	root.remove_child(imp)
	check(not _world.combat.is_registered(imp), "forgotten when it leaves the tree")
	root.add_child(imp)
	check(_world.combat.is_registered(imp), "and registered again when it comes back")
