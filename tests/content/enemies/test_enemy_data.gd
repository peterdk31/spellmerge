extends "res://tests/support/suite.gd"
## Enemy data (enemy AI AI4, docs/milestones/M2-enemy-ai.md): 1-4 staffs of cards, a profile and a
## boss's phases on `EnemyBase`, checked by `problems()`. Every enemy in the registry is sound, and
## an actor holds every staff its data names.
##
## godot --headless --path . --script res://tests/content/enemies/test_enemy_data.gd

const RegistryScript := preload("res://core/registry/registry.gd")
const Fixture := preload("res://tests/gameplay/ai/ai_fixture.gd")
const ImpData: EnemyBase = preload("res://content/enemies/ember_imp/ember_imp.tres")


func _enemies() -> Array[EnemyBase]:
	var registry := RegistryScript.new()
	registry.call("scan")
	var found: Array[EnemyBase] = []
	for item: Variant in registry.call("get_all", "enemies"):
		if item is EnemyBase:
			found.append(item as EnemyBase)
	registry.free()
	return found


func _staff(slots: int) -> StaffBase:
	var staff := StaffBase.new()
	staff.slots = slots
	return staff


func test_every_enemy_is_sound() -> void:
	var all: Array[EnemyBase] = _enemies()
	check(all.size() >= 7, "the enemies are found: %d" % all.size())
	for data in all:
		check_equal(data.problems(), PackedStringArray(), "%s: its data is sound" % data.id)
		for entry: StaffCards in data.staffs:
			check_equal(SpellValidator.check_staff(entry.staff).size(), 0, "%s: its staff is valid" % data.id)


func test_every_enemy_plays_by_the_enemy_ai() -> void:
	# The dummies and the horde's swarmers too (owner, 2026-11-01): one system for every enemy.
	for data in _enemies():
		check(data.profile != null, "%s names a profile" % data.id)
		var body: Node = data.scene.instantiate()
		var ai: AIController = null
		for child in body.get_children():
			if child is AIController:
				ai = child as AIController
		check(ai != null, "%s: an AIController drives it" % data.id)
		body.free()


func test_more_cards_than_slots_is_caught() -> void:
	var data := EnemyBase.new()
	data.id = &"crook"
	data.staffs = [StaffCards.make(_staff(2), [&"frost", &"pull", &"bolt"] as Array[StringName])] as Array[StaffCards]
	var problems: PackedStringArray = data.problems()
	check_equal(problems.size(), 1, "one problem: %s" % problems)
	check(problems.size() == 1 and problems[0].contains("bolt"), "it names the card cut off")


func test_too_many_staffs_and_bad_phases_are_caught() -> void:
	var data := EnemyBase.new()
	data.id = &"boss"
	for i in 5:
		data.staffs.append(StaffCards.make(_staff(1), [&"bolt"] as Array[StringName]))
	data.phases.append(EnemyPhase.new())
	check_equal(data.problems().size(), 2, "five staffs and a phase with no condition: %s" % data.problems())
	var empty := StaffCards.make(_staff(2), [&"", &""] as Array[StringName])
	check_equal(empty.problems().size(), 1, "a staff with no card")
	check_equal(StaffCards.new().problems().size(), 1, "an entry with no staff")


func test_an_actor_holds_every_staff_of_its_data() -> void:
	var fx := Fixture.new(root)
	var data: EnemyBase = ImpData.duplicate() as EnemyBase
	data.staffs = [
		StaffCards.make(_staff(2), [&"fire", &"bolt"] as Array[StringName]),
		StaffCards.make(_staff(1), [&"dash"] as Array[StringName]),
		StaffCards.make(_staff(1), [&"nova"] as Array[StringName]),
	] as Array[StaffCards]
	var body: Actor = fx.enemy(ImpData.scene, data, Vector2(100.0, 0.0))
	check(body.caster != null, "it has a caster")
	if body.caster != null:
		check_equal(body.caster.staff_count, 3, "of three staffs")
		for at in 3:
			check(body.caster.has_staff(at), "staff %d is built" % at)
		check(body.caster.next_cast_sense(1).moves_caster, "staff 1 is the dash")
		check(body.caster.next_cast_sense(2).area, "staff 2 the nova")
	fx.free_all()


func test_size_scales_the_body() -> void:
	var fx := Fixture.new(root)
	var data: EnemyBase = ImpData.duplicate() as EnemyBase
	data.size = 2.0
	var body: Actor = fx.enemy(ImpData.scene, data, Vector2(100.0, 0.0))
	check(body.scale.is_equal_approx(Vector2(2.0, 2.0)), "a body twice the size")
	check(body.hurtbox != null and is_equal_approx(body.hurtbox.radius, 22.0), "with a hurt circle twice as wide: %s" % (body.hurtbox.radius if body.hurtbox != null else 0.0))
	fx.free_all()
