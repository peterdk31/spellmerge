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
	return Fixture.staff_entry(cards, 100.0, 50.0)


func _boss() -> EnemyBase:
	var data: EnemyBase = ImpData.duplicate() as EnemyBase
	data.id = &"test_boss"
	data.boss = true
	data.max_health = 100.0
	data.staffs = [_entry([&"fire", &"bolt"])] as Array[StaffCards]
	var angry := EnemyPhase.new()
	angry.health_below = 0.5
	angry.transition = 1.0
	angry.staffs = [_entry([&"nova", &"bolt"]), _entry([&"dash"])] as Array[StaffCards]
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
	# Six seconds of the boss's own time: its beam's hits hold it now and then (hit-stop, online-ready
	# N4), and its clock stands while it is held.
	var steps: int = 0
	while boss.phases.current == 0 and steps < int(9.0 / Fixture.STEP):
		fx.run(boss, 1)
		steps += 1
	check(float(steps) * Fixture.STEP >= 6.0, "not before six seconds (%d steps)" % steps)
	check_equal(boss.phases.current, 1, "after six seconds the next phase")
	check_equal(boss.caster.staff_count, 1, "one staff again")
	check(boss.caster.next_cast_sense(0).repeats_held, "a beam")
	check(not boss.caster.has_staff(1), "the dash button is emptied")


func test_a_phase_brings_its_stats_and_builds_at_their_size() -> void:
	# Boss plan OB7: a phase's stats become the body's (null keeps the last); a new spell scale builds
	# the staffs again, the phase's own or the ones it keeps.
	fx.players[0].position = Vector2(150.0, 0.0)
	var data: EnemyBase = _boss()
	data.stats = ActorStats.new()
	data.stats.power = 2.0
	data.phases[0].stats = ActorStats.new()
	data.phases[0].stats.power = 3.0
	data.phases[0].stats.spell_scale = 2.0
	data.phases[1].staffs = [] as Array[StaffCards]
	data.phases[1].stats = ActorStats.new()
	data.phases[1].stats.spell_scale = 1.0
	var boss: Actor = fx.imp(Vector2.ZERO, data)
	check_equal(boss.stats.power, 2.0, "its data's stats")
	var radius: float = boss.caster.next_cast_radius(0)
	boss.phases.begin(0)
	check_equal(boss.stats.power, 3.0, "the phase's power")
	var nova: float = boss.caster.next_cast_radius(0)
	var plain: CompiledStaff = fx.spells.compile_staff(boss.caster.cards_of(0), boss.caster.staff_of(0))
	check(is_equal_approx(nova, plain.casts[0].group.spells[0].radius * 2.0), "its staffs built at spell scale 2")
	boss.phases.begin(1)
	check_equal(boss.stats.power, 1.0, "the last phase's own stats")
	check(is_equal_approx(boss.caster.next_cast_radius(0), nova * 0.5), "the staffs it keeps built again at scale 1")
	check(radius > 0.0, "(a radius to compare)")
	data.phases[0].stats = null
	var keeps: Actor = fx.imp(Vector2(0.0, 80.0), data)
	keeps.phases.begin(0)
	check_equal(keeps.stats.power, 2.0, "a phase with no stats keeps the last")


func test_a_phase_met_during_a_possession_starts_when_it_ends() -> void:
	# Boss plan OB7, "A rule changed": the possessor never loses its staffs mid-cast.
	fx.players[0].position = Vector2(150.0, 0.0)
	var boss: Actor = fx.imp(Vector2.ZERO, _boss())
	var possession: Possession = Possession.begin(fx.players[0], boss, 1.0)
	check(possession != null, "a wizard possesses the boss")
	fx.combat.hit(-1, boss, 55.0)
	fx.run(boss, 2)
	check_equal(boss.phases.current, -1, "under half health, no phase while it is possessed")
	check_equal(boss.caster.cards_of(0).slice(0, 2), [&"fire", &"bolt"] as Array[StringName], "the possessor keeps its staffs")
	var steps: int = 0
	while boss.possessed_by != null and steps < 40:
		fx.run(boss, 1)
		steps += 1
	check(boss.possessed_by == null, "the possession ends")
	fx.run(boss, 1)
	check_equal(boss.phases.current, 0, "and the phase starts then")
