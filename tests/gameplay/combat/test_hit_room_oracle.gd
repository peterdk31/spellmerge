extends "res://tests/support/suite.gd"
## The oracle of a body's room (tests/support/hit_room_oracle.gd, hit batch A0) answers every
## `hit_room_asked` of a real fight as Combat does, to the bit: plain, hexed, barriered (a barrier
## of another spell, and one sparing the spell that hits), healed and dying bodies, an invincible
## one, and a spell that deals none. A2 holds its new answers to this oracle.
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
	check(arena.died(imps[0]) or arena.lost(imps[0]) > 0, "the first imp was hurt")
	check_equal(_differ, [] as Array[String], "the oracle and Combat agree at every ask")
	arena.free_all()


func test_the_oracle_tells_an_invincible_body_and_a_stranger_as_unknown() -> void:
	var world := ActorFixture.new(root)
	var body: Actor = world.actor(Vector2(40.0, 0.0), [&"health", &"hurtbox"] as Array[StringName], ActorFixture.Scripted.new())
	var room := HitRoom.new()
	var mine := HitRoom.new()
	world.bus.hit_room_asked.emit(0, body, 0, -1, room)
	Oracle.answer(world.combat, body, 0, -1, mine)
	check(mine.health < INF and mine.health == room.health, "a plain body: its health (%s, %s)" % [mine.health, room.health])
	body.health.invincible = true
	room.clear()
	world.bus.hit_room_asked.emit(0, body, 0, -1, room)
	Oracle.answer(world.combat, body, 0, -1, mine)
	check_equal(mine.health, INF, "an invincible one: unknown")
	check_equal(room.health, mine.health, "as Combat tells it")
	var stranger := own(Node2D.new()) as Node2D
	Oracle.answer(world.combat, stranger, 0, -1, mine)
	check_equal([mine.health, mine.damage, mine.charges], [INF, 0.0, 0], "a body Combat does not know: unknown")
	world.free_all()
