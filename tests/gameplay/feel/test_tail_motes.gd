extends "res://tests/support/suite.gd"
## Tails as motes (docs/milestones/spell-spectacle-2.md, S5 step 4): the motes lay each tail code
## of the shots' births (the projectile manager's SPARK_TAIL + 0 to TAIL_KINDS - 1, one a shot) in
## its own tail kind (`MoteKind.tail`, in id order, round again when there are fewer), in the
## shot's own ramp.

const MotesScript := preload("res://gameplay/feel/mote.gd")
const ProjectilesScript := preload("res://core/projectiles/projectile_manager.gd")


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
