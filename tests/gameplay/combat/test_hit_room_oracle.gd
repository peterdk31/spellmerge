extends "res://tests/support/suite.gd"
## The hit batch's room of a body (hit batch A2: Combat's two answers, a body's room and a spell's
## damage, each asked once a pass and again after any event) gives at every entry what Combat's one
## answer before A2 gave (the oracle, tests/support/hit_room_oracle.gd), to the bit: health, damage
## and the barrier's charges. A real fight holds it at every entry (tests/support/checked_batch.gd):
## piercing bolt fans, a fire bolt, Plow bolts, a fan of mending bolts and Blast bolts that burst where they end,
## sending events during its passes (in this fight none falls between two entries of one body or
## spell; a pass where one does, and changes them, is the staged test below); one imp hexed, one
## shielded, one barriered by the fire bolt's own spell, a weak one that dies. And the kit's bodies
## are held to it straight away in every state Combat reads: plain, hexed, shielded, barriered
## sparing the spell or another, a caster of power 2, protected, invincible, depleted, down, with
## no Health, a plain body (Combat's own, not an actor), a body Combat does not know, and spells
## with no profile and a heal. A shot with a hit profile of its own asks for itself (the manager).
const ArenaScript := preload("res://tests/content/spells/combo_arena.gd")
const Oracle := preload("res://tests/support/hit_room_oracle.gd")
const CheckedBatch := preload("res://tests/support/checked_batch.gd")
const ActorFixture := preload("res://tests/gameplay/actor/actor_fixture.gd")
const ManagerScript := preload("res://core/projectiles/projectile_manager.gd")


func test_every_entry_of_a_fight_has_the_room_the_oracle_gives() -> void:
	var arena := ArenaScript.new(root)
	var batch := CheckedBatch.new()
	batch.combat = arena.combat
	batch.manager = arena.projectiles
	arena.projectiles._hit_batch = batch
	# The GDScript's entries, each held to the oracle here; the native hit pass's (it opens some
	# itself, hit batch A4) are held to the GDScript's by tests/core/test_native_kernel.gd.
	arena.projectiles.native = false
	var imps: Array[Node2D] = []
	for k in 6:
		imps.append(arena.add_imp(Vector2(60.0 + 12.0 * float(k), -20.0 + 8.0 * float(k)), 40.0 + 15.0 * float(k)))
	# A weak imp in the fans' line: later spells' first hits ask about a dying or dead body.
	var weak: Node2D = arena.add_imp(Vector2(70.0, -6.0), 3.0)
	arena.combat.apply_status(1, imps[1], arena.combat.HEX, 5.0, 40.0)
	arena.combat.apply_status(1, imps[4], arena.combat.HEX, 5.0, 25.0)
	arena.combat.give_shield(imps[2], 2, 5.0)
	check(arena.install_cards(0, 0, [&"triple", &"pierce", &"bolt"]) != null, "a fan of piercing bolts")
	check(arena.install_cards(0, 1, [&"fire", &"bolt"]) != null, "a fire bolt")
	check(arena.install_cards(1, 0, [&"mend", &"triple", &"bolt"]) != null, "a fan of mending bolts")
	check(arena.install_cards(1, 1, [&"blast", &"triple", &"bolt"]) != null, "a fan of Blast bolts")
	# Plow (docs/milestones/hit-batch.md, A2, "Plow"): a body a shot carries is not hurt by it, which
	# neither the oracle nor the batch knows; its entries are held to the oracle all the same.
	check(arena.install_cards(0, 2, [&"plow", &"bolt"]) != null, "a Plow bolt")
	arena.place_caster(1, Vector2(0.0, 10.0))
	var carried: bool = false
	for round in 8:
		if round == 2:
			# A barrier that spares the fire bolt's own spell: its charges are not told for it.
			arena.combat.give_barrier(imps[3], 3, 5.0, arena.spells.current_tag(0, 1))
		arena.cast(0, 0)
		arena.cast(0, 1, Vector2(1.0, 0.2).normalized())
		arena.cast(1, 0, Vector2(1.0, -0.1).normalized())
		arena.cast(1, 1, Vector2(1.0, 0.05).normalized())
		arena.cast(0, 2, Vector2(1.0, 0.1).normalized())
		for step in 36:
			arena.run(1.0 / 60.0)
			for imp: Node2D in imps:
				if is_instance_valid(imp) and arena.spells._plow.carrying(arena.combat.actor_of(imp), arena.spells.current_tag(0, 2)):
					carried = true
	check(batch.checked > 20, "the fight opened many entries (%d)" % batch.checked)
	for shape: String in ["health only", "damage", "charges"]:
		check(int(batch.shapes.get(shape, 0)) > 0, "an entry of %s came up (%s)" % [shape, batch.shapes])
	check(arena.combat.health_of(imps[1]) < 55.0, "the hexed imp was hurt (%s)" % arena.combat.health_of(imps[1]))
	check(arena.died(weak), "the weak imp died in the fight")
	check(carried, "a Plow bolt carried an imp")
	check_equal(batch.differ, [] as Array[String], "the batch's room and the oracle's agree at every entry")
	arena.free_all()


## One entry of `tag` on `target`, its room worked out by a hit batch from Combat's two answers, and
## the oracle's for it, compared; the oracle's answer's shape is counted in `shapes`.
func _ask(world: ActorFixture, target: Node, tag: int, shapes: Dictionary, what: String) -> void:
	var batch := HitBatch.new()
	batch.open(1, 1)
	var entry: int = batch.add(0, 1, 0, tag, 0, 0, Vector2.ZERO, Vector2.RIGHT, &"bolt", 0, Color.WHITE, 0, false, 0)
	check_equal(batch.asks, HitBatch.ASK_ROOM | HitBatch.ASK_DAMAGE, what + ": a fresh batch asks both")
	world.bus.hit_room_asked.emit(target, batch.room)
	world.bus.hit_damage_asked.emit(tag, -1, batch.damage)
	batch.take_room(entry)
	var told := Oracle.Answer.new()
	Oracle.answer(world.combat, target, tag, -1, told)
	var charges: int = batch._charges[0] if batch._blocks[entry] != 0 else 0
	check_equal([batch._health[0], batch._damage[entry], charges], [told.health, told.damage, told.charges], what + ": the batch's room as the oracle's")
	var shape: String = "unknown" if told.health == INF else ("health only" if told.damage <= 0.0 else ("charges" if told.charges > 0 else "damage"))
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
	var plain := Oracle.Answer.new()
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


## A room and a spell's damage told before an event of the pass are asked again, and a shot that
## hits alone asks for itself, in one pass, each entry held to the oracle. Shot A (bolt) hits X, which
## is hexed (30: damage 6 grows to 7.8, the sum's order shows in the last bit) and barriered sparing
## the fire spell; shot B ends on a wall, and its handler takes health off X, raises the caster's
## power and adds body Z; then C (fire) hits X, D (bolt) hits Y, F (bolt) the invincible W, G (bolt,
## a profile of its own) V, and H (bolt) V again: C sees X's health after the handler, D the new
## power, G asks for itself, and H takes the bolt's damage, not G's. E (bolt) hits Z in the next pass
## (a target added during a pass is in the target grid from the next).
func test_a_room_and_a_damage_told_before_an_event_are_asked_again() -> void:
	var world := ActorFixture.new(root)
	var wizard: Actor = world.actor(Vector2.ZERO, [&"health", &"hurtbox", &"caster"] as Array[StringName], ActorFixture.Scripted.new(), [[&"bolt"], [&"fire", &"bolt"]])
	wizard.stats.power = 1.2
	var kinds: Array[StringName] = [&"health", &"hurtbox"]
	var x: Actor = world.actor(Vector2(200.0, 0.0), kinds, ActorFixture.Scripted.new())
	var y: Actor = world.actor(Vector2(200.0, 120.0), kinds, ActorFixture.Scripted.new())
	var w: Actor = world.actor(Vector2(200.0, -120.0), kinds, ActorFixture.Scripted.new())
	var v: Actor = world.actor(Vector2(200.0, -240.0), kinds, ActorFixture.Scripted.new())
	w.health.invincible = true
	var batch := CheckedBatch.new()
	batch.combat = world.combat
	batch.manager = world.projectiles
	world.projectiles._hit_batch = batch
	world.projectiles.native = false
	world.projectiles.set_walls([Rect2(400.0, 300.0, 40.0, 40.0)] as Array[Rect2])
	var bolt: int = world.tag_of(wizard, 0)
	var fire: int = world.tag_of(wizard, 1)
	world.combat.apply_status(wizard.id, x, world.combat.HEX, 5.0, 30.0)
	world.combat.give_barrier(x, 2, 5.0, fire)
	var names: Dictionary = {x.name: "X", y.name: "Y", w.name: "W", v.name: "V"}
	var asked: Array[String] = []
	world.bus.hit_room_asked.connect(func(target: Node, _room: HitRoom) -> void: asked.append("room " + str(names.get(target.name, "Z"))))
	world.bus.hit_damage_asked.connect(func(tag: int, _shot: int, _answer: HitDamage) -> void: asked.append("damage %s" % ("bolt" if tag == bolt else "fire")))
	var added: Array[Actor] = []
	world.bus.projectile_expired.connect(func(_caster: int, _at: Vector2, _tag: int, _shot: int) -> void:
		asked.append("wall")
		x.health.lose(7.0)
		wizard.stats.power = 2.4
		added.append(world.actor(Vector2(200.0, 240.0), kinds, ActorFixture.Scripted.new())))
	var mgr: ManagerScript = world.projectiles
	var aim: Vector2 = x.body_offset - Vector2(6.0, 0.0)
	# A to H, in slot order: where each starts and its spell (B, the wall's, has none).
	var starts: Array[Vector2] = [x.global_position + aim, Vector2(394.0, 320.0), x.global_position + aim + Vector2(0.0, 2.0), y.global_position + aim, w.global_position + aim, Vector2(200.0, 240.0) + aim - Vector2(10.0, 0.0), v.global_position + aim, v.global_position + aim + Vector2(0.0, 2.0)]
	var tags: Array[int] = [bolt, 0, fire, bolt, bolt, bolt, bolt, bolt]
	var shots: Array[int] = []
	for n in starts.size():
		shots.append(mgr.spawn(wizard.id, starts[n], Vector2(600.0, 0.0), 1.0, 3.0, ManagerScript.ACTOR_LAYERS, 0, tags[n]))
	var ordered: bool = true
	for n in shots.size() - 1:
		ordered = ordered and shots[n] < shots[n + 1]
	check(ordered, "the pass meets the shots in that order (%s)" % [shots])
	# G hits with a profile of its own, as Spells gives a relay's (`_set_relay`: it hits alone).
	var g: int = shots[6]
	var own := HitProfile.new()
	own.damage = 20.0
	if world.spells._rec_seq.size() <= g:
		world.spells._grow_records(mgr.get_cap())
	world.spells._rec_seq[g] = mgr.get_seq_of(g)
	world.spells._set_relay(g, own)
	mgr.step(1.0 / 60.0)
	check_equal(added.size(), 1, "the wall's handler added Z during the pass")
	check_equal(asked, ["room X", "damage bolt", "wall", "room X", "damage fire", "room Y", "damage bolt", "room W", "room V", "damage bolt"] as Array[String], "each asked once, again after the wall's event, and G for itself")
	check_equal(batch.checked, 6, "six entries: X twice, Y, W, and V twice (G alone)")
	check_equal(batch.asked_again, 2, "X's room and the bolt's damage asked again after the wall")
	# Z, added during the pass, is in the target grid from the next pass on: E, a step behind, hits it.
	mgr.step(1.0 / 60.0)
	check_equal(asked.slice(10), ["room Z", "damage bolt"] as Array[String], "the next pass asks of Z and of the bolt afresh")
	check_equal(batch.checked, 7, "and Z's entry is the seventh")
	check_equal(batch.differ, [] as Array[String], "each as the oracle tells it at its first hit")
	world.free_all()
