extends "res://tests/support/suite.gd"
## The oracle of a body's room (tests/support/hit_room_oracle.gd, hit batch A0) answers every
## `hit_room_asked` as Combat does, to the bit. A real fight (piercing bolt fans, a fire bolt and a
## mending fan on imps, one hexed, one shielded, one barriered by the fire bolt's own spell, a weak
## one that dies) asks it at the bodies' first hits; and the kit's bodies are asked straight away in
## every state Combat reads: plain, hexed, shielded, barriered sparing the spell asked about or
## another, a caster of power 2, protected, invincible, depleted, down, with no Health, a plain body
## (Combat's own, not an actor), a body Combat does not know, and spells with no profile
## and a heal. A2 holds its new answers to this oracle. A shot with a hit profile of its own (`F_ALONE`) is A2's own test.
const ArenaScript := preload("res://tests/content/spells/combo_arena.gd")
const Oracle := preload("res://tests/support/hit_room_oracle.gd")
const ActorFixture := preload("res://tests/gameplay/actor/actor_fixture.gd")

var _asks: int = 0
var _differ: Array[String] = []
var _health_told: int = 0
var _damage_told: int = 0
var _charges_told: int = 0


func before_each() -> void:
	_asks = 0
	_differ.clear()
	_health_told = 0
	_damage_told = 0
	_charges_told = 0


## Listened after Combat's own answer: the oracle fills a room of its own for the same ask.
func _watch(arena: ArenaScript) -> void:
	var mine := HitRoom.new()
	arena.bus.hit_room_asked.connect(func(_caster: int, target: Node, tag: int, shot: int, room: HitRoom) -> void:
		_asks += 1
		Oracle.answer(arena.combat, target, tag, shot, mine)
		if room.health < INF:
			_health_told += 1
		if room.damage > 0.0:
			_damage_told += 1
		if room.charges > 0:
			_charges_told += 1
		if mine.health != room.health or mine.damage != room.damage or mine.charges != room.charges:
			_differ.append("ask %d, tag %d: Combat %s/%s/%d, oracle %s/%s/%d" % [_asks, tag, room.health, room.damage, room.charges, mine.health, mine.damage, mine.charges]))


func test_the_oracle_answers_every_ask_of_a_fight_as_combat_does() -> void:
	var arena := ArenaScript.new(root)
	_watch(arena)
	var imps: Array[Node2D] = []
	for k in 6:
		imps.append(arena.add_imp(Vector2(60.0 + 12.0 * float(k), -20.0 + 8.0 * float(k)), 40.0 + 15.0 * float(k)))
	# A weak imp in the fans' line: later spells' first hits ask about a dying or dead body.
	var weak: Node2D = arena.add_imp(Vector2(70.0, -6.0), 3.0)
	arena.combat.apply_status(1, imps[1], arena.combat.HEX, 5.0, 40.0)
	arena.combat.apply_status(1, imps[4], arena.combat.HEX, 5.0, 25.0)
	arena.combat.give_shield(imps[2], 2, 5.0)
	var fan: CompiledStaff = arena.install_cards(0, 0, [&"triple", &"pierce", &"bolt"])
	check(fan != null, "a fan of piercing bolts")
	var spared: CompiledStaff = arena.install_cards(0, 1, [&"fire", &"bolt"])
	check(spared != null, "a fire bolt")
	var mend: CompiledStaff = arena.install_cards(1, 0, [&"mend", &"triple", &"bolt"])
	check(mend != null, "a fan of mending bolts")
	arena.place_caster(1, Vector2(0.0, 10.0))
	for round in 6:
		if round == 2:
			# A barrier that spares the fire bolt's own spell: its charges are not told for it.
			arena.combat.give_barrier(imps[3], 3, 5.0, arena.spells.current_tag(0, 1))
		arena.cast(0, 0)
		arena.cast(0, 1, Vector2(1.0, 0.2).normalized())
		arena.cast(1, 0, Vector2(1.0, -0.1).normalized())
		arena.run(0.6)
	check(_asks > 20, "the fight asked often (%d)" % _asks)
	check(_damage_told > 0 and _charges_told > 0 and _health_told > _damage_told, "damage, charges and a heal's health-only answer all came up (%d, %d, %d)" % [_damage_told, _charges_told, _health_told])
	check(arena.combat.health_of(imps[1]) < 55.0, "the hexed imp was hurt (%s)" % arena.combat.health_of(imps[1]))
	check(arena.died(weak), "the weak imp died in the fight")
	check_equal(_differ, [] as Array[String], "the oracle and Combat agree at every ask")
	arena.free_all()


## Combat's answer and the oracle's for one ask, compared; the answer's shape is counted in `shapes`.
func _ask(world: ActorFixture, target: Node, tag: int, shapes: Dictionary, what: String) -> void:
	var room := HitRoom.new()
	var mine := HitRoom.new()
	world.bus.hit_room_asked.emit(0, target, tag, -1, room)
	Oracle.answer(world.combat, target, tag, -1, mine)
	check_equal([mine.health, mine.damage, mine.charges], [room.health, room.damage, room.charges], what + ": the oracle as Combat")
	var shape: String = "unknown" if room.health == INF else ("health only" if room.damage <= 0.0 else ("charges" if room.charges > 0 else "damage"))
	shapes[shape] = int(shapes.get(shape, 0)) + 1


func test_the_oracle_answers_every_state_of_a_body_as_combat_does() -> void:
	var world := ActorFixture.new(root)
	var wizard: Actor = world.actor(Vector2.ZERO, [&"health", &"hurtbox", &"caster"] as Array[StringName], ActorFixture.Scripted.new(), [[&"bolt"], [&"mend", &"bolt"]])
	var bolt: int = world.spells.current_tag(wizard.id, 0)
	var mend: int = world.spells.current_tag(wizard.id, 1)
	check(bolt != 0 and mend != 0, "the wizard's two spells have tags (%d, %d)" % [bolt, mend])
	var kinds: Array[StringName] = [&"health", &"hurtbox"]
	var shapes: Dictionary = {}
	var damages: Array[float] = []
	var body: Actor = world.actor(Vector2(40.0, 0.0), kinds, ActorFixture.Scripted.new())
	_ask(world, body, bolt, shapes, "plain")
	_ask(world, body, 0, shapes, "no spell")
	_ask(world, body, mend, shapes, "a heal")
	var plain := HitRoom.new()
	Oracle.answer(world.combat, body, bolt, -1, plain)
	damages.append(plain.damage)
	wizard.stats.power = 2.0
	_ask(world, body, bolt, shapes, "a caster of power 2")
	Oracle.answer(world.combat, body, bolt, -1, plain)
	damages.append(plain.damage)
	wizard.stats.power = 1.0
	var hexed: Actor = world.actor(Vector2(80.0, 0.0), kinds, ActorFixture.Scripted.new())
	world.combat.apply_status(wizard.id, hexed, world.combat.HEX, 5.0, 40.0)
	_ask(world, hexed, bolt, shapes, "hexed")
	Oracle.answer(world.combat, hexed, bolt, -1, plain)
	damages.append(plain.damage)
	check(damages[1] == damages[0] * 2.0 and damages[2] > damages[0], "power and the hex change the damage told (%s)" % [damages])
	var shielded: Actor = world.actor(Vector2(120.0, 0.0), kinds, ActorFixture.Scripted.new())
	world.combat.give_shield(shielded, 2, 5.0)
	_ask(world, shielded, bolt, shapes, "shielded")
	var spares: Actor = world.actor(Vector2(160.0, 0.0), kinds, ActorFixture.Scripted.new())
	world.combat.give_barrier(spares, 3, 5.0, bolt)
	_ask(world, spares, bolt, shapes, "a barrier sparing the spell asked about")
	var other: Actor = world.actor(Vector2(200.0, 0.0), kinds, ActorFixture.Scripted.new())
	world.combat.give_barrier(other, 3, 5.0, mend)
	_ask(world, other, bolt, shapes, "a barrier sparing another spell")
	var protected: Actor = world.actor(Vector2(240.0, 0.0), kinds, ActorFixture.Scripted.new())
	protected.health.protect(5.0)
	_ask(world, protected, bolt, shapes, "protected")
	var invincible: Actor = world.actor(Vector2(280.0, 0.0), kinds, ActorFixture.Scripted.new())
	invincible.health.invincible = true
	_ask(world, invincible, bolt, shapes, "invincible")
	var depleted: Actor = world.actor(Vector2(320.0, 0.0), kinds, ActorFixture.Scripted.new())
	depleted.health.lose(depleted.health.health)
	_ask(world, depleted, bolt, shapes, "depleted")
	var down: Actor = world.actor(Vector2(360.0, 0.0), kinds, ActorFixture.Scripted.new())
	down.set_down(true)
	_ask(world, down, bolt, shapes, "down (%s)" % down.is_down())
	var no_health: Actor = world.actor(Vector2(400.0, 0.0), [&"hurtbox"] as Array[StringName], ActorFixture.Scripted.new())
	_ask(world, no_health, bolt, shapes, "no Health")
	var stone := own(Node2D.new()) as Node2D
	root.add_child(stone)
	world.combat.register_actor(stone, 20.0)
	_ask(world, stone, bolt, shapes, "a plain body")
	_ask(world, own(Node2D.new()) as Node2D, bolt, shapes, "a stranger")
	for shape: String in ["unknown", "health only", "damage", "charges"]:
		check(int(shapes.get(shape, 0)) > 0, "an answer of %s came up (%s)" % [shape, shapes])
	world.free_all()
