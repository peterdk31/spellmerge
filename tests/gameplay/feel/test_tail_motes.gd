extends "res://tests/support/suite.gd"
## Tails as motes (docs/milestones/spell-spectacle-2.md, S5 step 4): the motes lay each tail code
## of the shots' births (the projectile manager's SPARK_TAIL + 0 to TAIL_KINDS - 1, one a shot) in
## its own tail kind (`MoteKind.tail`, in id order, round again when there are fewer), in the
## shot's own ramp.

const MotesScript := preload("res://gameplay/feel/mote.gd")
const ProjectilesScript := preload("res://core/projectiles/projectile_manager.gd")
const NativeScript := preload("res://core/native/native.gd")


func _kind(id: StringName, tail: bool) -> MoteKind:
	var kind := MoteKind.new()
	kind.id = id
	kind.tail = tail
	kind.look_layers = PackedInt32Array([0]) if not tail else PackedInt32Array()
	kind.height = 0.0
	return kind


## A pool of a spark kind and two tail kinds, in the tree unless `alone`.
func _pool(alone: bool = false) -> MotesScript:
	var motes := MotesScript.new(256, 0, [_kind(&"spark", false), _kind(&"tail", true), _kind(&"tail_b", true)] as Array[MoteKind])
	motes.native = false
	if alone:
		return motes
	own(motes)
	root.add_child(motes)
	motes.step(1.0)
	return motes


## One tail birth at `at` of tail code `code`, of a shot of ramp 1 with the core `core`.
func _tail_birth(at: Vector2, core: Color, code: int = ProjectilesScript.SPARK_TAIL) -> PackedFloat32Array:
	var given := PackedFloat32Array()
	given.resize(ProjectilesScript.SPARK_BIRTH_STRIDE)
	given[ProjectilesScript.SPARK_X] = at.x
	given[ProjectilesScript.SPARK_Y] = at.y
	given[ProjectilesScript.SPARK_BACK_X] = -1.0
	given[ProjectilesScript.SPARK_KIND] = code
	given[ProjectilesScript.SPARK_RAMP] = 1
	for c in 3:
		given[ProjectilesScript.SPARK_CORE + c] = core[c]
	return given


func test_each_tail_code_has_its_own_kind() -> void:
	var motes: MotesScript = _pool()
	check(motes.tail_kinds() == PackedInt32Array([1, 2]), "the kinds marked tail")
	var code: int = ProjectilesScript.SPARK_TAIL
	check(motes.tail_kind_of(code) == PackedInt32Array([1]), "A: the first")
	check(motes.tail_kind_of(code + 1) == PackedInt32Array([2]), "B: the second")
	check(motes.tail_kind_of(code + 2) == PackedInt32Array([1]), "C with two kinds: round again to the first")
	check(motes.tail_kind_of(code - 1).is_empty() and motes.tail_kind_of(code + ProjectilesScript.TAIL_KINDS).is_empty(), "no kind for a code that is no tail's")


func test_a_tail_birth_is_a_mote_of_its_codes_kind() -> void:
	var motes: MotesScript = _pool()
	var row: int = motes.next_row()
	motes.give_off(_tail_birth(Vector2(40.0, 30.0), Color(0.9, 0.3, 0.2), ProjectilesScript.SPARK_TAIL + 1), 1)
	check(motes.next_row() == row + 1 and motes.births == 1, "one mote")
	var data: PackedFloat32Array = motes.row_data(row)
	check(roundi(data[MotesScript.ROW_KIND] * MotesScript.KIND_CODE) == 2, "of the second tail kind")
	check(is_equal_approx(data[MotesScript.ROW_X], 40.0) and is_equal_approx(data[MotesScript.ROW_Y], 30.0), "where it was laid")
	check(roundi(data[MotesScript.ROW_SOURCE] * MotesScript.SOURCE_CODE) == MotesScript.spell_source(1, 0), "in the shot's own ramp")
	check(is_equal_approx(data[MotesScript.ROW_CORE], 0.9), "with its core colour")


func test_a_tail_kind_belongs_to_nothing_else() -> void:
	var kind: MoteKind = _kind(&"tail", true)
	check(kind.problems().is_empty(), "a tail kind on its own is fine: %s" % [kind.problems()])
	kind.cards = [&"fire"] as Array[StringName]
	check(not kind.problems().is_empty(), "one that names a card is not")
	kind.cards = [] as Array[StringName]
	kind.dash_path = true
	check(not kind.problems().is_empty(), "nor one that is a dash's path")


func test_the_content_has_three_tail_kinds() -> void:
	var found: Array[StringName] = []
	for path in ["res://content/motes/tail.tres", "res://content/motes/tail_streak.tres", "res://content/motes/tail_long.tres"]:
		var kind := load(path) as MoteKind
		check(kind != null and kind.tail and kind.problems().is_empty(), "%s is a fine tail kind" % path)
		if kind != null:
			found.append(kind.id)
	check(found.size() == ProjectilesScript.TAIL_KINDS, "one for each tail code: A, B and C")


## `count` tail births in a row from x = `x0` on (as the projectile manager lays a frame's: every
## shot's tail in slot order, then its other births).
func _tail_births(count: int, x0: float, core: Color) -> PackedFloat32Array:
	var given := PackedFloat32Array()
	for n in count:
		given.append_array(_tail_birth(Vector2(x0 + float(n), 30.0), core))
	return given


## The regression (the owner, 2026-11-05): a splitting Storm's hits shed their sparks all frame,
## before the trails' births are given off, so they took the frame's rows and the tail laid last
## in the births, a Fireball's cast through the Storm, was cut though the projectile manager had
## given it its whole share. The tail rows (`tail_rows`) are kept from every other write until the
## spectacle hands them to the births (`open_tail_rows`), in GDScript and in the native kernel.
func test_the_hits_never_take_the_tails_rows() -> void:
	for native in [false, true]:
		if native and not NativeScript.loaded():
			continue
		var motes := MotesScript.new(4096, 0, [_kind(&"spark", false), _kind(&"tail", true)] as Array[MoteKind])
		motes.native = native
		own(motes)
		root.add_child(motes)
		var tails: int = 200
		motes.frame_rows = MotesScript.FRAME_ROWS + tails
		motes.tail_rows = tails
		motes.step(1.0)
		var label: String = "native" if native else "GDScript"
		# The Storm's hits: sheds until only the moments' rows are left, then a moment that takes all.
		for n in 100:
			motes.throw(0, Vector2(float(n), 0.0), Vector2.LEFT, 0, Color.WHITE, 4.0)
		motes.throw_part(0, Vector2.ZERO, Vector2.RIGHT, 0, Color.WHITE, MotesScript.FRAME_ROWS * 2, 0.0, 360.0, 1.0, false)
		check_equal(motes.written, MotesScript.FRAME_ROWS, "%s: the hits and moments take the frame's rows past the tails'" % label)
		# The Storm's thinned tails, then the Fireball's whole one, last in the births.
		var given: PackedFloat32Array = _tail_births(tails - 12, 0.0, Color(0.9, 0.8, 0.2))
		given.append_array(_tail_births(12, 500.0, Color(0.9, 0.3, 0.1)))
		var births: int = motes.births
		motes.open_tail_rows()
		motes.give_off(given, tails)
		check_equal(motes.births - births, tails, "%s: every tail birth is a mote, the Fireball's last ones too" % label)
		var last: PackedFloat32Array = motes.row_data(motes.next_row() - 1)
		check(is_equal_approx(last[MotesScript.ROW_X], 511.0), "%s: the Fireball's tail is written to its end" % label)
		motes.step(1.1)
		for n in 100:
			motes.throw(0, Vector2(float(n), 0.0), Vector2.LEFT, 0, Color.WHITE, 4.0)
		check(motes.written - MotesScript.FRAME_ROWS - tails <= MotesScript.FRAME_ROWS - MotesScript.MOMENT_ROWS, "%s: the next frame keeps them again" % label)
