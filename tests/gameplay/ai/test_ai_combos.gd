extends "res://tests/support/suite.gd"
## Every combo in the catalogue (`content/spells/combos/`), played by an enemy (enemy AI AI5,
## docs/milestones/M2-enemy-ai.md, "Done when" 3): it casts each combo's staffs on its own, by
## what they cast next, never shoots an aimed cast into a wall, and never kills itself. A wizard
## stands 100 px away and stings it once a second, so a guarding staff is called for too.
##
## godot --headless --path . --script res://tests/gameplay/ai/test_ai_combos.gd

const Fixture := preload("res://tests/gameplay/ai/ai_fixture.gd")
const ComboFiles := preload("res://tests/support/combo_files.gd")
const ImpData: EnemyBase = preload("res://content/enemies/ember_imp/ember_imp.tres")

const SECONDS: float = 6.0
## Combos whose staffs only heal: no baseline behaviour heals yet (Heal ally comes later,
## docs/milestones/M2-enemy-ai.md, "Later behaviours").
const HEAL_ONLY: Array[String] = ["mend_pierce_party"]


func _data(casts: Array) -> EnemyBase:
	var data: EnemyBase = ImpData.duplicate() as EnemyBase
	data.max_health = 1000.0
	data.staffs = [] as Array[StaffCards]
	var rows: Array = []
	rows.resize(EnemyBase.MAX_STAFFS)
	for row: Variant in casts:
		var at: int = int((row as Dictionary).get("staff", 0))
		if at >= 0 and at < rows.size():
			rows[at] = (row as Dictionary).get("cards", [])
	for row: Variant in rows:
		var cards: Array[StringName] = []
		for id: Variant in (row if row is Array else []):
			cards.append(StringName(str(id)))
		var staff := StaffBase.new()
		staff.slots = maxi(cards.size(), 1)
		staff.cast_delay = 0.0
		staff.recharge = 0.0
		staff.max_mana = 200.0
		staff.mana_regen = 40.0
		data.staffs.append(StaffCards.make(staff, cards))
	while not data.staffs.is_empty() and data.staffs[-1].cards.is_empty():
		data.staffs.pop_back()
	return data


func test_every_combo_is_played() -> void:
	var problems: PackedStringArray = PackedStringArray()
	var combos: Array = ComboFiles.read_all(ComboFiles.FOLDER, problems)
	check(combos.size() > 50, "the combos are read: %d" % combos.size())
	var silent: PackedStringArray = PackedStringArray()
	for combo: Variant in combos:
		var row := combo as Dictionary
		var id: String = str(row.get("id", ""))
		var fx := Fixture.new(root)
		fx.players[0].position = Vector2(100.0, 0.0)
		var body: Actor = ImpData.scene.instantiate() as Actor
		(body.get_node("AIController") as AIController).profile = Fixture.exact()
		body.data = _data(row.get("casts", []))
		fx.wire(body)
		root.add_child(body)
		body.set_physics_process(false)
		fx.enemies.append(body)
		var cast: Array[int] = [0]
		var walled: Array[int] = [0]
		if body.caster != null:
			body.caster.cast_done.connect(func(staff: int, _o: Vector2, _d: Vector2) -> void:
				cast[0] += 1
				var sense: CastSense = body.caster.next_cast_sense(staff)
				if sense != null and sense.reach > 0.0 and not AISight.line_clear(fx.projectiles, body.global_position + body.body_offset, fx.players[0].global_position + fx.players[0].body_offset):
					walled[0] += 1)
		var steps: int = int(SECONDS / Fixture.STEP)
		for i in steps:
			if i % 16 == 0 and is_instance_valid(body):
				fx.combat.hit(fx.players[0].id, body, 0.1)
			if not is_instance_valid(body) or body.is_dying():
				break
			fx.run_all(1)
		check(is_instance_valid(body) and not body.is_dying(), "%s: the enemy is still alive" % id)
		if cast[0] == 0 and not HEAL_ONLY.has(id):
			silent.append(id)
		check_equal(walled[0], 0, "%s: no aimed cast into a wall" % id)
		fx.free_all()
	check_equal(silent, PackedStringArray(), "every combo is cast by an enemy at least once")
