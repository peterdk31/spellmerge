extends "res://tests/support/suite.gd"
## Enemy data (enemy AI AI4, docs/milestones/M2-enemy-ai.md): 1-4 staffs of cards, a profile and a
## boss's phases on `EnemyBase`, checked by `problems()`. Every enemy and boss in the registry is sound, and
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
	for folder: StringName in EnemyBase.FOLDERS:
		for item: Variant in registry.call("get_all", folder):
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
		for phase: EnemyPhase in data.phases:
			for entry: StaffCards in phase.staffs:
				check_equal(SpellValidator.check_staff(entry.staff).size(), 0, "%s: its phase's staff is valid" % data.id)


## Boss plan OB13: every phase's adds name an enemy of the registry that is not a boss (a boss calling
## a boss would have two bars and two deaths to wait for).
func test_every_phases_adds_are_enemies_of_the_registry() -> void:
	var registry := RegistryScript.new()
	registry.call("scan")
	for data in _enemies():
		for phase: EnemyPhase in data.phases:
			for adds: EnemyAdds in phase.adds:
				var called := registry.call("get_resource", &"enemies", adds.enemy) as EnemyBase
				check(called != null and not called.boss, "%s: its adds '%s' are an enemy of the registry" % [data.id, adds.enemy])
	registry.free()


## Boss plan OB13: an entry's numbers for the players in play (each "per player" after the first), its
## cap of those alive, and what is wrong with one.
func test_adds_count_by_the_players_in_play() -> void:
	var adds := EnemyAdds.new()
	adds.enemy = &"ember_imp"
	adds.count = 4
	adds.per_player = 2
	adds.every = 10.0
	adds.wave_count = 2
	adds.wave_per_player = 1
	adds.cap = 6
	adds.cap_per_player = 2
	check_equal([adds.burst_for(1), adds.burst_for(4), adds.burst_for(0)], [4, 10, 4], "4 and 2 a player after the first")
	check_equal([adds.wave_for(1), adds.wave_for(3)], [2, 4], "waves of 2 and 1 a player")
	check_equal([adds.cap_for(1), adds.cap_for(4)], [6, 12], "the cap")
	check_equal(adds.allowed(10, 0, 4), 10, "under the cap: all")
	check_equal(adds.allowed(4, 9, 4), 3, "the cap's room only")
	check_equal(adds.allowed(4, 14, 4), 0, "never fewer than none")
	adds.cap = 0
	check_equal(adds.allowed(40, 100, 1), 40, "no cap")
	check_equal(adds.problems(), PackedStringArray(), "sound")
	var bad := EnemyAdds.new()
	bad.wave_count = 2
	check_equal(bad.problems().size(), 3, "no enemy, nobody called, a wave with no time: %s" % bad.problems())
	var data := EnemyBase.new()
	data.id = &"boss"
	data.max_health = 100.0
	data.health_per_player = 0.7
	var phase := EnemyPhase.new()
	phase.health_below = 0.5
	phase.adds = [bad, null] as Array[EnemyAdds]
	data.phases = [phase] as Array[EnemyPhase]
	check_equal(data.problems().size(), 4, "the phase's adds' problems, an empty entry too: %s" % data.problems())
	check(is_equal_approx(data.health_for(4, 2.0), 100.0 * 2.0 * 3.1), "health by players and the room's scale")
	check(is_equal_approx(data.health_for(1), 100.0) and is_equal_approx(data.health_for(0), 100.0), "one player: its own")


func test_a_face_of_its_own_can_be_drawn() -> void:
	# Boss plan OB9: a face's own art (`FaceArt`) has every sheet, whole frames and enough columns.
	for data in _enemies():
		var body: Node = data.scene.instantiate()
		for child in body.get_children():
			if child is Face and (child as Face).art != null:
				check_equal((child as Face).art.problems(), PackedStringArray(), "%s: its face's own art" % data.id)
		body.free()
	var art := FaceArt.new()
	art.frame = Vector2i(8, 8)
	check_equal(art.problems().size(), 2, "no sheets: two problems")
	var image := Image.create(72, 16, false, Image.FORMAT_RGBA8)
	art.eyes = ImageTexture.create_from_image(image)
	art.brows = ImageTexture.create_from_image(Image.create(44, 8, false, Image.FORMAT_RGBA8))
	check_equal(art.problems().size(), 2, "nine eye columns, and brows not whole frames: %s" % art.problems())
	art.eyes = ImageTexture.create_from_image(Image.create(80, 16, false, Image.FORMAT_RGBA8))
	art.brows = ImageTexture.create_from_image(Image.create(40, 8, false, Image.FORMAT_RGBA8))
	check_equal(art.problems(), PackedStringArray(), "ten eye columns and five brows: sound")


func test_every_enemy_plays_by_the_enemy_ai() -> void:
	# The dummies and the swarmers too (owner, 2026-11-01): one system for every enemy.
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
		StaffCards.make(_staff(2), [&"nova", &"bolt"] as Array[StringName]),
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
