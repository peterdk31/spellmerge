extends "res://tests/support/suite.gd"
## Mote jets (`gameplay/feel/jets.gd`, a cue's `motes` part with `for`): a part's count poured
## over its seconds instead of thrown at once, from where its cue played, each frame's share thrown
## by the spectacle's motes player (here a stand-in that counts what it is handed). The owner,
## 2026-11-16: "I really like the jet animation".
##
## godot --headless --path . --script res://tests/gameplay/feel/test_jets.gd

const JetsScript := preload("res://gameplay/feel/jets.gd")
const MotesPartScript := preload("res://gameplay/feel/motes_part.gd")
const CueContextScript := preload("res://gameplay/feel/cue_context.gd")
const SpectacleScript := preload("res://gameplay/feel/spectacle.gd")

const DT: float = 1.0 / 60.0

## What the stand-in player was handed: [count, where, way, kind] each throw.
var thrown: Array = []
var jets: JetsScript


func before_each() -> void:
	thrown.clear()
	jets = JetsScript.new(func(part: MotesPartScript, cue: CueContextScript) -> void:
		thrown.append([part.count, cue.at, cue.aim, part.named, part.reach, part.radius, cue.power]))


func _part(count: int, lasts: float) -> MotesPartScript:
	var part := MotesPartScript.new()
	part.named = &"glob"
	part.count = count
	part.lasts = lasts
	return part


func _cue(at: Vector2) -> CueContextScript:
	var cue := CueContextScript.new()
	cue.at = at
	cue.aim = Vector2.UP
	return cue


func _total() -> int:
	var all: int = 0
	for each: Array in thrown:
		all += int(each[0])
	return all


func test_a_jet_pours_its_count_over_its_seconds() -> void:
	var part := _part(30, 0.25)
	jets.start(part, _cue(Vector2(10.0, 20.0)), 0.0)
	check(jets.is_pouring(), "it pours")
	var clock: float = 0.0
	var by_half: int = -1
	for n in 30:
		clock += DT
		jets.step(clock)
		if by_half < 0 and clock >= 0.125:
			by_half = _total()
	check_equal(_total(), 30, "its whole count in all")
	check(by_half >= 12 and by_half <= 18, "about half by half its time (%d)" % by_half)
	check(thrown.size() >= 10, "a little every frame, not all at once (%d throws)" % thrown.size())
	check(not jets.is_pouring(), "and it ends")
	check_equal(thrown[0][1], Vector2(10.0, 20.0), "from where its cue played")
	check_equal(thrown[0][2], Vector2.UP, "along its way")
	check_equal(thrown[0][3], &"glob", "as its part")
	check_equal(part.count, 30, "the cue's own part is left as it was")


func test_a_jet_keeps_its_cue_when_the_next_cue_refills_it() -> void:
	var cue := _cue(Vector2(10.0, 20.0))
	jets.start(_part(10, 0.1), cue, 0.0)
	cue.at = Vector2(500.0, 500.0)
	jets.step(0.05)
	check_equal(thrown[0][1], Vector2(10.0, 20.0), "where it was played, not where the cue went next")


func test_a_stall_pours_no_more_than_a_frames_worth() -> void:
	jets.start(_part(60, 1.0), _cue(Vector2.ZERO), 0.0)
	jets.step(0.0)
	jets.step(5.0)
	check(_total() <= 8, "after a stall it takes up where it was (%d)" % _total())
	check(jets.is_pouring(), "and pours on")


func test_a_full_set_of_jets_gives_way_to_a_new_one() -> void:
	for n in JetsScript.MOST:
		jets.start(_part(10, 2.0 + float(n)), _cue(Vector2(float(n), 0.0)), 0.0)
	jets.start(_part(10, 0.5), _cue(Vector2(-1.0, -1.0)), 0.0)
	check_equal(jets.count, JetsScript.MOST, "never more than MOST")
	jets.step(0.25)
	var seen: bool = false
	for each: Array in thrown:
		seen = seen or each[1] == Vector2(-1.0, -1.0)
	check(seen, "the new one pours")
	var evicted: bool = false
	for each: Array in thrown:
		evicted = evicted or each[1] == Vector2(0.0, 0.0)
	check(not evicted, "in the place of the one that would end soonest (the first, 2 s)")


func test_a_part_with_for_is_prepared_as_a_jet() -> void:
	var spectacle := SpectacleScript.new()
	var prepared: MotesPartScript = spectacle.prepare_motes_part({"part": &"motes", "kind": &"glob", "count": 12, "for": 0.3})
	check(is_equal_approx(prepared.lasts, 0.3), "its for is how long it pours")
	check(is_equal_approx(spectacle.prepare_motes_part({"part": &"motes"}).lasts, 0.0), "none: thrown at once")
	spectacle.free()


func test_a_cue_checks_its_jets() -> void:
	var cue := CueBase.new()
	cue.id = &"test_jet"
	cue.parts = [{"part": &"motes", "kind": &"glob", "count": 12, "for": 0.3}]
	check(cue.problems().is_empty(), "a jet with a count is fine: %s" % [cue.problems()])
	cue.parts = [{"part": &"motes", "kind": &"glob", "for": 0.3}]
	check(" ".join(cue.problems()).contains("takes a count"), "a jet needs a count")
	cue.parts = [{"part": &"motes", "kind": &"glob", "count": 12, "for": 9.0}]
	check(" ".join(cue.problems()).contains("for is not"), "and pours for at most MOTES_FOR_MOST")
	cue.parts = [{"part": &"motes", "kind": &"glob", "count": 12, "for": 0.3, "often": true}]
	check(" ".join(cue.problems()).contains("neither share nor often"), "and is never one of many a frame")


func test_a_strong_cue_pours_more_and_further() -> void:
	# A cue's power is times its motes parts' counts and how far they fly (CueBase): a jet's too.
	var part := _part(10, 0.1)
	part.reach = 1.0
	part.radius = 8.0
	var cue := _cue(Vector2.ZERO)
	cue.power = 2.0
	jets.start(part, cue, 0.0)
	for n in 12:
		jets.step(float(n + 1) * DT)
	check_equal(_total(), 20, "twice the count")
	check(is_equal_approx(thrown[0][4], 2.0) and is_equal_approx(thrown[0][5], 16.0), "twice as far (reach %s, radius %s)" % [thrown[0][4], thrown[0][5]])
	check(is_equal_approx(thrown[0][6], 1.0), "each share thrown at power 1, its power in it")
	check(is_equal_approx(part.reach, 1.0), "the cue's own part is left as it was")


func test_a_jets_share_of_its_spells_kinds_adds_up() -> void:
	# A spell's motes are split between its cards' kinds: a jet's few a frame must not give each kind
	# one more than it is due (review, 2026-11-16: it poured three times its count).
	var kinds: int = 3
	var given := PackedInt32Array([0, 0, 0])
	var turn: int = 0
	var whole: int = 0
	for frame in 30:
		var count: int = 1 + frame % 2
		var frame_total: int = 0
		for at in kinds:
			var each: int = SpectacleScript.jet_share(count, kinds, turn, at)
			given[at] += each
			frame_total += each
		check_equal(frame_total, count, "a frame's share is thrown, no more")
		turn = posmod(turn + count, kinds)
		whole += count
	check_equal(given[0] + given[1] + given[2], whole, "the whole count in all")
	check(absi(given[0] - given[1]) <= 1 and absi(given[1] - given[2]) <= 1, "each kind its share (%s)" % [given])


func test_the_spectacle_pours_only_while_motes_are_thrown_and_ends_its_jets_with_the_room() -> void:
	var spectacle := SpectacleScript.new()
	var part := _part(30, 1.0)
	spectacle.jets.start(part, _cue(Vector2.ZERO), 0.0)
	spectacle.particles_enabled = false
	spectacle.step(0.1)
	check(not spectacle.jets.is_pouring(), "particles off: its jets end (nothing thrown, no pool read)")
	spectacle.jets.start(part, _cue(Vector2.ZERO), 0.1)
	spectacle.use_room(null)
	check(not spectacle.jets.is_pouring(), "a new room ends them too")
	spectacle.free()


## Every field of a script's own, set to something other than its default.
func _fill(target: Object) -> void:
	for prop: Dictionary in target.get_property_list():
		if (int(prop["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0:
			continue
		var name: StringName = prop["name"]
		match typeof(target.get(name)):
			TYPE_INT:
				target.set(name, 7)
			TYPE_FLOAT:
				target.set(name, 0.375)
			TYPE_BOOL:
				target.set(name, not bool(target.get(name)))
			TYPE_STRING_NAME:
				target.set(name, &"filled")
			TYPE_VECTOR2:
				target.set(name, Vector2(3.0, 4.0))
			TYPE_COLOR:
				target.set(name, Color(0.25, 0.5, 0.75, 1.0))


func _differs(a: Object, b: Object) -> PackedStringArray:
	var found := PackedStringArray()
	for prop: Dictionary in a.get_property_list():
		if (int(prop["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE) != 0 and a.get(prop["name"]) != b.get(prop["name"]):
			found.append(String(prop["name"]))
	return found


func test_a_copy_takes_every_field() -> void:
	# A field added later must be copied too, or a jet throws with its default.
	var part := MotesPartScript.new()
	_fill(part)
	var copy := MotesPartScript.new()
	copy.copy_from(part)
	check(_differs(part, copy).is_empty(), "a motes part's copy takes every field (missed: %s)" % [_differs(part, copy)])
	var cue := CueContextScript.new()
	_fill(cue)
	var cue_copy := CueContextScript.new()
	cue_copy.copy_from(cue)
	check(_differs(cue, cue_copy).is_empty(), "a cue's copy takes every field (missed: %s)" % [_differs(cue, cue_copy)])
