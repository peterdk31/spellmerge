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
		thrown.append([part.count, cue.at, cue.aim, part.named]), MotesPartScript.new)


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
	check(seen, "the new one pours, in the place of the one that would end soonest")


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
