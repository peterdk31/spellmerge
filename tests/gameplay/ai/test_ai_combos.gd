extends "res://tests/support/suite.gd"
## Every combo in the catalogue (`content/spells/combos/`), played by an enemy (enemy AI AI5,
## docs/milestones/M2-enemy-ai.md, "Done when" 3): it casts each combo's staffs on its own, by
## what they cast next, never shoots an aimed cast into a wall, and never kills itself. A wizard
## stands 100 px away and stings it once a second, so a guarding staff is called for too. A
## combo's `allies` stand by it as its teammates, hurt by the combo's `hurt` (out of MATE_HEALTH),
## so a staff that only heals has someone to heal (the Heal ally behaviour, L2).
##
## godot --headless --path . --script res://tests/gameplay/ai/test_ai_combos.gd

const Fixture := preload("res://tests/gameplay/ai/ai_fixture.gd")
const ComboFiles := preload("res://tests/support/combo_files.gd")

const SECONDS: float = 6.0
## The most health of a combo's allies.
const MATE_HEALTH: float = 100.0


## The combo's staffs, by the staff each of its casts names (empty buttons in between kept).
func _data(casts: Array) -> EnemyBase:
	var rows: Array = [[], [], [], []]
	for row: Variant in casts:
		var at: int = int((row as Dictionary).get("staff", 0))
		if at >= 0 and at < rows.size():
			rows[at] = (row as Dictionary).get("cards", [])
	while not rows.is_empty() and (rows[-1] as Array).is_empty():
		rows.pop_back()
	var data: EnemyBase = Fixture.staffed(rows, 200.0, 40.0)
	data.max_health = 1000.0
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
		var body: Actor = fx.imp(Vector2.ZERO, _data(row.get("casts", [])))
		for ally: Variant in row.get("allies", []):
			var at: Array = ally as Array
			var mate_data: EnemyBase = Fixture.staffed([])
			mate_data.max_health = MATE_HEALTH
			var mate: Actor = fx.imp(Vector2(float(at[0]), float(at[1])), mate_data)
			mate.health.reset(MATE_HEALTH - float(row.get("hurt", 0)))
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
		if cast[0] == 0:
			silent.append(id)
		check_equal(walled[0], 0, "%s: no aimed cast into a wall" % id)
		fx.free_all()
	check_equal(silent, PackedStringArray(), "every combo is cast by an enemy at least once")
