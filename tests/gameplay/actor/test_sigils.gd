extends "res://tests/support/suite.gd"
## Sigils (docs/milestones/staff-language.md, L4; gameplay/actor/caster.gd, inventory.gd): an item put on
## a whole staff that makes it cast by itself while its condition holds, along its holder's aim, at the
## staff's own cooldown and mana. Put on and taken off freely (at most 3 a staff, no two the same),
## kept by the staff through the loadout, read from the simulation only.
const Fixture := preload("res://tests/gameplay/player/wizard_fixture.gd")
const ActorsScript := preload("res://core/actors/actors.gd")
const ProjectilesScript := preload("res://core/projectiles/projectile_manager.gd")

const HURT: StringName = &"cast_when_hurt"
const CLOSE: StringName = &"cast_when_close"
const BAG: StringName = &"sigils"

var _world: Fixture
var _staff: StaffBase
var _casts: int = 0


func before_each() -> void:
	_world = Fixture.new(root)
	_staff = StaffBase.new()
	_staff.id = &"test"
	_staff.slots = 3
	_staff.cooldown = 0.0
	_staff.max_mana = 100.0
	_staff.mana_regen = 100.0
	_casts = 0


func after_each() -> void:
	_world.free_all()


## A wizard holding `_staff` on RB with a bolt, and `sigils` copies of each sigil in its bag.
func _wizard(sigils: int = 1) -> Actor:
	var hands: Array[StaffBase] = [_staff, null, null, null]
	var body: Actor = _world.wizard(0, Vector2.ZERO, [[&"bolt"], [], [], []], null, false, hands)
	_world.add(body)
	body.inventory.registry = _world.registry
	for id: StringName in [HURT, CLOSE]:
		body.inventory.add(ItemStack.of(ItemKinds.SIGIL, id, sigils))
	body.caster.cast_done.connect(func(_at: int, _o: Vector2, _d: Vector2) -> void: _casts += 1)
	return body


func _run(seconds: float) -> void:
	_world.run(int(seconds / Fixture.STEP), false)


func test_the_sigils_are_valid_content() -> void:
	for id: StringName in [HURT, CLOSE]:
		var sigil: SigilBase = ItemKinds.content(ItemKinds.SIGIL, id, _world.registry) as SigilBase
		check(sigil != null, "%s is a sigil" % id)
		if sigil != null:
			check(sigil.problems().is_empty(), "%s: %s" % [id, sigil.problems()])
	check(ItemKinds.bag_of(ItemKinds.SIGIL) == BAG, "they are kept in the sigils bag")


func test_put_on_and_take_off() -> void:
	var body: Actor = _wizard()
	var inventory: Inventory = body.inventory
	check_equal(inventory.put_sigil(0, HURT), Inventory.Refusal.NONE, "put on")
	check_equal(inventory.count_of(BAG, HURT), 0, "out of the bag")
	check_equal(inventory.sigils_of(0), [HURT] as Array[StringName], "on the staff")
	check_equal(body.caster.sigils_of(0), [HURT] as Array[StringName], "its hand casts by it")
	check_equal(inventory.plan_of(0).get("sigils"), [HURT] as Array[StringName], "the builder's plan names it")
	check_equal(inventory.take_sigil(0, HURT), Inventory.Refusal.NONE, "taken off")
	check_equal(inventory.count_of(BAG, HURT), 1, "back in the bag")
	check(body.caster.sigils_of(0).is_empty(), "its hand casts by none")


func test_what_is_refused() -> void:
	var body: Actor = _wizard(2)
	var inventory: Inventory = body.inventory
	check_equal(inventory.put_sigil(5, HURT), Inventory.Refusal.NO_STAFF, "no such staff")
	check_equal(inventory.put_sigil(0, &"potion"), Inventory.Refusal.NO_ITEM, "no such sigil")
	check_equal(inventory.take_sigil(0, HURT), Inventory.Refusal.NO_ITEM, "none on it to take")
	inventory.put_sigil(0, HURT)
	check_equal(inventory.put_sigil(0, HURT), Inventory.Refusal.SIGIL_TWICE, "the same twice")
	check_equal(inventory.count_of(BAG, HURT), 1, "the second stays in the bag")
	# A third and a fourth kind, for the most a staff holds.
	for id: StringName in [&"test_sigil_a", &"test_sigil_b"]:
		var made := SigilBase.new()
		made.id = id
		_world.registry.add(&"sigils", made)
		inventory.add(ItemStack.of(ItemKinds.SIGIL, id, 1))
	check_equal(inventory.put_sigil(0, CLOSE), Inventory.Refusal.NONE, "a second kind")
	check_equal(inventory.put_sigil(0, &"test_sigil_a"), Inventory.Refusal.NONE, "a third")
	check_equal(inventory.put_sigil(0, &"test_sigil_b"), Inventory.Refusal.SIGILS_FULL, "a fourth is refused")
	for id: StringName in [&"test_sigil_a", &"test_sigil_b"]:
		_world.registry.remove(&"sigils", id)


func test_a_dropped_staff_s_sigils_come_off_into_the_bag() -> void:
	var body: Actor = _wizard()
	var inventory: Inventory = body.inventory
	inventory.put_sigil(0, HURT)
	var lying: Array[ItemStack] = []
	_world.bus.item_drop_requested.connect(func(_actor: int, stack: ItemStack) -> void: lying.append(stack))
	check_equal(inventory.drop_staff(0), Inventory.Refusal.NONE, "dropped")
	check_equal(inventory.count_of(BAG, HURT), 1, "its sigil is back in the bag")
	check(lying.size() == 1 and lying[0].sigils.is_empty(), "the staff on the ground holds none")


func test_a_staff_picked_up_onto_a_hand_casts_by_its_sigils() -> void:
	var body: Actor = _wizard()
	var held := ItemStack.of_staff(_staff, [&"bolt"] as Array[StringName])
	held.sigils = [HURT] as Array[StringName]
	check(body.inventory.put_on_hand(held, 1), "onto RT")
	check_equal(body.caster.sigils_of(1), [HURT] as Array[StringName], "its hand casts by its sigil")


func test_sigils_follow_a_staff_from_hand_to_hand() -> void:
	var body: Actor = _wizard()
	body.inventory.put_sigil(0, HURT)
	check_equal(body.inventory.set_hand(0, 2), Inventory.Refusal.NONE, "RB's staff onto LB")
	check(body.caster.sigils_of(0).is_empty(), "RB casts by none")
	check_equal(body.caster.sigils_of(2), [HURT] as Array[StringName], "LB by its sigil")
	check_equal(body.inventory.set_hand(0, Inventory.NO_HAND), Inventory.Refusal.NONE, "into the bag")
	check(body.caster.sigils_of(2).is_empty(), "no hand casts by it")
	check_equal(body.inventory.sigils_of(0), [HURT] as Array[StringName], "the staff in the bag keeps it")


func test_new_staffs_drop_the_old_staffs_sigils() -> void:
	var body: Actor = _wizard()
	body.inventory.put_sigil(0, HURT)
	body.caster.replace_staffs([_staff] as Array[StaffBase], [[&"bolt"]])
	check(body.caster.sigils_of(0).is_empty(), "a boss's phase staffs carry none")


func test_it_casts_by_itself_only_while_hurt() -> void:
	var body: Actor = _wizard()
	body.inventory.put_sigil(0, HURT)
	_run(1.0)
	check_equal(_casts, 0, "whole: it waits for a press")
	_world.hurt(body, 60, 1)
	_run(1.0)
	check(_casts > 0, "below half: it casts by itself (%d)" % _casts)
	# A bolt's wind-down is 0.35 s: no faster than a held button.
	check(_casts <= 4, "at its own pace: %d in a second" % _casts)


func test_no_sigil_no_auto_cast() -> void:
	var body: Actor = _wizard()
	_world.hurt(body, 60, 1)
	_run(1.0)
	check_equal(_casts, 0, "a staff with no sigil only casts when pressed")


func test_it_pays_its_mana() -> void:
	_staff.max_mana = 10.0
	_staff.mana_regen = 0.0
	var body: Actor = _wizard()
	body.inventory.put_sigil(0, HURT)
	_world.hurt(body, 60, 1)
	_run(2.0)
	check_equal(_casts, 2, "two 5-mana bolts from a pool of 10, then nothing (%d)" % _casts)


func test_it_casts_while_a_foe_is_close() -> void:
	var body: Actor = _wizard()
	body.inventory.put_sigil(0, CLOSE)
	_run(0.5)
	check_equal(_casts, 0, "no foe: it waits")
	var foe_id: int = _world.table.open(ActorsScript.TEAM_ENEMIES, ActorsScript.RAMP_ENEMY)
	var foe := Node2D.new()
	root.add_child(foe)
	foe.global_position = body.global_position + body.body_offset + Vector2(60.0, 0.0)
	_world.table.set_node(foe_id, foe)
	_world.projectiles.add_target(foe, 6.0, ProjectilesScript.LAYER_ENEMY, foe_id)
	_run(0.5)
	check(_casts > 0, "a foe within 96 px: it casts by itself (%d)" % _casts)
	_world.projectiles.remove_target(foe)
	foe.free()


func test_the_loadout_keeps_a_staff_s_sigils() -> void:
	var body: Actor = _wizard()
	body.inventory.put_sigil(0, HURT)
	var loadout: PlayerLoadout = body.inventory.loadout()
	check_equal(loadout.staff_sigils(0), [HURT] as Array[StringName], "the loadout carries them")
	var bytes := PackedByteArray()
	loadout.encode_into(bytes)
	var back := PlayerLoadout.new()
	check_equal(back.decode_at(bytes, 0), "", "it reads back")
	check_equal(back.staff_sigils(0), [HURT] as Array[StringName], "with its sigils")
	var served := _Served.new()
	served.staff = _staff
	served.content = _world.registry
	var next: Actor = Fixture.WizardScene.instantiate() as Actor
	PlayerController.seat_loadout(next, 1, back, served)
	PlayerController.of(next).frames = _world.frames
	PlayerController.of(next).registry = _world.registry
	_world.add(next)
	next.inventory.registry = _world.registry
	check_equal(next.inventory.sigils_of(0), [HURT] as Array[StringName], "the next run's staff has it")
	check_equal(next.caster.sigils_of(0), [HURT] as Array[StringName], "and casts by it")
	served.free()


func test_a_loadout_written_before_sigils_still_reads() -> void:
	var loadout := PlayerLoadout.new()
	loadout.add_staff(0, &"curl", [&"bolt"] as Array[StringName])
	var bytes := PackedByteArray()
	loadout.encode_into(bytes)
	# The same loadout as four sections: drop the last (SIGILS: tag, length, an empty count).
	var four: PackedByteArray = bytes.slice(0, bytes.size() - 4)
	four[0] = PlayerLoadout.FIRST_SECTIONS
	var back := PlayerLoadout.new()
	check_equal(back.decode_at(four, 0), "", "four sections read")
	check(back.staff_sigils(0).is_empty(), "with no sigils")


func test_an_enemy_staff_with_a_sigil_must_wind_up() -> void:
	var entry := StaffCards.make(StaffBase.new(), [&"bolt"] as Array[StringName])
	entry.staff.slots = 2
	entry.sigils = [ItemKinds.content(ItemKinds.SIGIL, CLOSE, _world.registry) as SigilBase]
	check(not entry.problems().is_empty(), "no wind-up: refused, it would cast with no warning")
	entry.staff.wind_up = 0.5
	check(entry.problems().is_empty(), "a telegraph: fine (%s)" % [entry.problems()])
	for id: StringName in [&"rime_crook", &"storm_fork"]:
		var enemy: EnemyBase = _world.registry.get_resource(&"enemies", id) as EnemyBase
		# The staff with the sigil (the Rime Crook's frost pull is its second since enemy AI L7).
		var signed: StaffCards = null
		if enemy != null:
			for entry_of: StaffCards in enemy.staffs:
				if not entry_of.sigils.is_empty():
					signed = entry_of
		check(signed != null, "%s has a staff with a sigil" % id)
		check(signed != null and signed.staff.wind_up > 0.0, "and it winds up")


## A registry that serves `_staff` as a staff and everything else from the real one.
class _Served:
	extends Node
	var staff: StaffBase
	var content: Node

	func get_resource(folder: StringName, id: StringName) -> Resource:
		if folder == &"wizard":
			return staff if staff != null and id == staff.id else null
		return content.call(&"get_resource", folder, id) as Resource
