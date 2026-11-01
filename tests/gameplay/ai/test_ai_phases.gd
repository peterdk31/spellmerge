extends "res://tests/support/suite.gd"
## A boss's phases (enemy AI AI7, docs/milestones/M2-enemy-ai.md): data only. A test boss made
## here: the imp's body with a bolt staff, then, under half health, a protected pause, a nova and a
## dash, a bigger body, a calmer face and an aggressive profile; then, after a while, a beam.
##
## godot --headless --path . --script res://tests/gameplay/ai/test_ai_phases.gd

const Fixture := preload("res://tests/gameplay/ai/ai_fixture.gd")
const ImpData: EnemyBase = preload("res://content/enemies/ember_imp/ember_imp.tres")

var fx: Fixture


func before_each() -> void:
	fx = Fixture.new(root)


func after_each() -> void:
	fx.free_all()


func _entry(cards: Array[StringName]) -> StaffCards:
	var staff := StaffBase.new()
	staff.slots = cards.size()
	staff.max_mana = 100.0
	staff.mana_regen = 50.0
	return StaffCards.make(staff, cards)


func _boss() -> EnemyBase:
	var data: EnemyBase = ImpData.duplicate() as EnemyBase
	data.id = &"test_boss"
	data.boss = true
	data.max_health = 100.0
	data.staffs = [_entry([&"fire", &"bolt"])] as Array[StaffCards]
	var angry := EnemyPhase.new()
	angry.health_below = 0.5
	angry.transition = 1.0
	angry.staffs = [_entry([&"nova"]), _entry([&"dash"])] as Array[StaffCards]
	angry.profile = Fixture.exact().duplicate() as AIProfile
	angry.profile.aggression = 1.0
	angry.look = PhaseLook.new()
	angry.look.size = 2.0
	angry.look.face_style = Face.Style.STRAY_ONE
	angry.look.glow = Color.RED
	var late := EnemyPhase.new()
	late.after_seconds = 6.0
	late.transition = 0.0
	late.staffs = [_entry([&"beam"])] as Array[StaffCards]
	data.phases = [angry, late] as Array[EnemyPhase]
	return data


func test_a_boss_changes_phase_under_half_health() -> void:
	fx.players[0].position = Vector2(150.0, 0.0)
	var boss: Actor = fx.imp(Vector2.ZERO, _boss())
	check(boss.phases != null, "data with phases gives the body its Phases")
	fx.run(boss, 4)
	check_equal(boss.phases.current, -1, "no phase at full health")
	check_equal(boss.caster.cards_of(0).slice(0, 2), [&"fire", &"bolt"] as Array[StringName], "the data's own staff first")
	var started: Array = []
	boss.phases.started.connect(func(index: int, _phase: EnemyPhase) -> void: started.append(index))
	fx.combat.hit(fx.players[0].id, boss, 55.0)
	fx.run(boss, 1)
	check_equal(started, [0], "under half health the first phase starts")
	check(boss.health.is_protected(), "protected through its transition")
	var brain: AIBrain = Fixture.ai(boss).brain
	check_equal(brain.state, AIBrain.State.TRANSITION, "standing")
	check_equal(boss.caster.staff_count, 2, "it holds the phase's two staffs")
	check(boss.caster.next_cast_sense(0).area and boss.caster.next_cast_sense(1).moves_caster, "a nova and a dash")
	check(is_equal_approx(boss.size, 2.0) and boss.scale.is_equal_approx(Vector2(2.0, 2.0)), "twice the size")
	check_equal(brain.profile.aggression, 1.0, "playing by the phase's profile")
	var face: Face = boss.get_node_or_null("Face") as Face
	if face != null:
		check_equal(face.style, Face.Style.STRAY_ONE, "a new face")
		check(face.glow.is_equal_approx(Color.RED), "glowing red")
	fx.run(boss, int(1.0 / Fixture.STEP) + 1)
	check(brain.state != AIBrain.State.TRANSITION, "after the transition it fights again")
	fx.run(boss, 2)
	check_equal(started, [0], "a phase starts once")


func test_a_phase_by_time() -> void:
	fx.players[0].position = Vector2(150.0, 0.0)
	var boss: Actor = fx.imp(Vector2.ZERO, _boss())
	boss.phases.begin(0)
	fx.run(boss, int(6.0 / Fixture.STEP) + 1)
	check_equal(boss.phases.current, 1, "after six seconds the next phase")
	check_equal(boss.caster.staff_count, 1, "one staff again")
	check(boss.caster.next_cast_sense(0).repeats_held, "a beam")
	check(not boss.caster.has_staff(1), "the dash button is emptied")
