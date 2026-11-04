extends "res://tests/support/suite.gd"
## Feel's own births (spell spectacle 2, S6 item 10; `gameplay/feel/births.gd`): what a swing and a
## beam give off, in the trails' birth format, so the motes' one writer (`Motes.give_off`, the
## native kernel where built) throws them.

const BirthsScript := preload("res://gameplay/feel/births.gd")
const ProjectilesScript := preload("res://core/projectiles/projectile_manager.gd")
const MotesScript := preload("res://gameplay/feel/mote.gd")


func test_a_birth_is_written_as_the_trails_are() -> void:
	var births := BirthsScript.new()
	check(births.add(Vector2(3, 4), Vector2.LEFT, ProjectilesScript.LOOK_EMBERS, 2, 9, Color(0.5, 0.25, 1.0), (7 << 20) + 5), "taken")
	check_equal(births.count, 1, "one")
	var rows: PackedFloat32Array = births.rows
	check_equal(Vector2(rows[ProjectilesScript.SPARK_X], rows[ProjectilesScript.SPARK_Y]), Vector2(3, 4), "where")
	check_equal(Vector2(rows[ProjectilesScript.SPARK_BACK_X], rows[ProjectilesScript.SPARK_BACK_Y]), Vector2.LEFT, "the way it is thrown")
	check_equal(int(rows[ProjectilesScript.SPARK_KIND]), ProjectilesScript.LOOK_EMBERS, "its look kind")
	check_equal(int(rows[ProjectilesScript.SPARK_RAMP]), 2, "the caster's ramp")
	check_equal(int(rows[ProjectilesScript.SPARK_LOOK]), 9, "the look")
	check_equal(Color(rows[ProjectilesScript.SPARK_CORE], rows[ProjectilesScript.SPARK_CORE + 1], rows[ProjectilesScript.SPARK_CORE + 2]), Color(0.5, 0.25, 1.0), "the core colour")
	check_equal(ProjectilesScript.spark_tag(rows, 0), (7 << 20) + 5, "the spell's tag, whole")
	births.clear()
	check_equal(births.count, 0, "a new frame forgets them")


func test_a_frame_holds_at_most_the_trails_most() -> void:
	var births := BirthsScript.new()
	for n in BirthsScript.MOST:
		births.add(Vector2.ZERO, Vector2.RIGHT, 0, 0, 0, Color.WHITE, 0)
	check(not births.add(Vector2.ZERO, Vector2.RIGHT, 0, 0, 0, Color.WHITE, 0), "full")
	check_equal(births.count, BirthsScript.MOST, "never past it")
	check_equal(births.dropped, 1, "and counts what it dropped")
	check(births.add(Vector2.INF, Vector2.RIGHT, 0, 0, 0, Color.WHITE, 0) == false, "still full")


func test_a_rate_is_given_off_whole_over_frames() -> void:
	var births := BirthsScript.new(3)
	var sum: int = 0
	for n in 600:
		sum += births.roll(36.0 / 60.0)
	check(absf(float(sum) - 360.0) < 40.0, "0.6 a frame is about 360 in 600 frames: %d" % sum)
	check_equal(births.roll(0.0), 0, "none for nothing")
	check_equal(births.roll(-1.0), 0, "none below")


func test_a_card_particle_is_one_of_its_looks_emitting_kinds() -> void:
	var births := BirthsScript.new(4)
	var look: int = ProjectilesScript.pack_look(PackedInt32Array([ProjectilesScript.LOOK_EMBERS, ProjectilesScript.LOOK_SPARKS, ProjectilesScript.LOOK_WEAVE]))
	check_equal(BirthsScript.emitting_count(look), 2, "the weave gives off none")
	var seen: Dictionary = {}
	for n in 200:
		seen[births.emitting_layer(look)] = true
	check(seen.has(ProjectilesScript.LOOK_EMBERS) and seen.has(ProjectilesScript.LOOK_SPARKS) and seen.size() == 2, "both kinds, and only them: %s" % [seen.keys()])
	check_equal(births.emitting_layer(0), 0, "a look of none: 0")


func test_the_motes_throw_them_with_one_writer() -> void:
	var kinds: Array[MoteKind] = []
	kinds.append(load("res://content/motes/spark.tres") as MoteKind)
	kinds.append(load("res://content/motes/ember.tres") as MoteKind)
	var pool := MotesScript.new(1024, 0, kinds)
	own(pool)
	root.add_child(pool)
	pool.step(1.0)
	var births := BirthsScript.new()
	births.add(Vector2(10, 10), Vector2.UP, 0, 0, 0, Color.WHITE, 0)
	births.add(Vector2(20, 10), Vector2.UP, ProjectilesScript.LOOK_EMBERS, 0, 1, Color(1, 0.4, 0.1), 0)
	pool.give_off(births.rows, births.count)
	check_equal(pool.births, 2, "each a one-mote birth")
	check_equal(pool.written, 2, "written by the pool's one writer")
