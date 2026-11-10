extends "res://tests/support/suite.gd"
## A live replay on the real game (netcode spike S1, docs/milestones/netcode-spike.md): a scripted
## sandbox run (its storm, a rebuild and a pause by commands) recorded by the Frames autoload, then
## played from a fresh game twice: whole, as a replay file, and live, its ticks arriving as over a
## link with jitter and stalls (`ReplayRun.play_live`), its own player's seat this machine's and
## driven otherwise (those frames are sent, never played). The Tick runs no tick while the next has
## not arrived and catches up after, and the live play is the whole one's after every step, waits
## included.

const ReplayRun := preload("res://tests/support/replay_run.gd")

const TICKS: int = 240
const CUSHION: int = 2

var _run: ReplayRun


func before_each() -> void:
	_run = ReplayRun.new(self)
	_run.ticks = TICKS
	_run.run_seed = 0x11fe


func after_each() -> void:
	await _run.fresh()


## When each tick arrives, in physics steps from the play's start, as over an ordered link: a few
## steps of jitter, a first tick that comes late, and a stall now and then whose ticks then come
## together.
static func _arrivals(ticks: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	var last: int = 0
	for tick in ticks:
		var at: int = tick + 6 + (tick * 37) % 5
		if tick % 70 >= 30 and tick % 70 < 33:
			at += 25
		last = maxi(last, at)
		out.append(last)
	return out


func test_a_run_played_live_agrees_with_it_played_whole() -> void:
	var recorded := Desync.new()
	var replay: Replay = await _run.record(&"sandbox_requested", 0, 1, recorded)
	check(replay != null and replay.tick_count() == TICKS, "recorded")
	if replay == null:
		return
	check(ReplayRun.has_command(replay) and ReplayRun.has_command(replay, &"pause_requested"), "the run carries its commands")
	var whole := Desync.new()
	await _run.play(replay, 0, whole)
	check_equal(whole.hashes.size(), TICKS, "played whole: every tick")
	check_equal(Desync.first_parting(recorded, whole), -1, "and as recorded")
	var live := Desync.new()
	var played := PackedInt32Array()
	var steps: Array[Vector2i] = []
	var arrive_at: PackedInt32Array = _arrivals(TICKS)
	await _run.play_live(replay, arrive_at, live, played, steps, CUSHION)
	for problem in _run.problems:
		check(false, problem)
	check(not played.is_empty() and played[played.size() - 1] == TICKS, "played live to its last tick")
	var parting: int = _first_parting(whole, live, played)
	if parting >= 0:
		# Again, keeping the parting step's leaves and the tick's, so the report names the members.
		var tick: int = played[parting] - 1
		var whole_again := Desync.new(tick)
		await _run.play(replay, 0, whole_again)
		var live_again := Desync.new(parting)
		await _run.play_live(replay, arrive_at, live_again, PackedInt32Array(), [] as Array[Vector2i], CUSHION)
		var lines := PackedStringArray()
		for area: String in whole_again.leaves:
			lines.append_array(Desync.members_parting(whole_again.leaves[area], live_again.leaves.get(area, {})))
		check(false, "the live replay parts from the whole one after tick %d: %s" % [tick, "\n".join(lines)])
	_check_steps(steps)


## The first capture of the live play (by step) whose hashes are not the whole play's after the same
## tick, or -1.
func _first_parting(whole: Desync, live: Desync, played: PackedInt32Array) -> int:
	check_equal(live.hashes.size(), played.size(), "a tick count for every capture")
	for at in mini(live.hashes.size(), played.size()):
		var tick: int = played[at] - 1
		if tick >= whole.hashes.size() or live.hashes[at] != whole.hashes[tick]:
			return at
	return -1


## The steps of the live play: none ran a tick that had not arrived or more than three, a step with
## nothing to play ran none, and a backlog is caught up within the cushion in a few steps.
func _check_steps(steps: Array[Vector2i]) -> void:
	var waited: int = 0
	var caught_up: int = 0
	for at in steps.size() - 1:
		var played: int = steps[at].x
		var there: int = steps[at].y
		var ran: int = steps[at + 1].x - played
		check(ran >= 0 and ran <= 3, "step %d: %d ticks run (at most three)" % [at, ran])
		check(played + ran <= there, "step %d: no tick run before it arrived" % at)
		if there == played:
			waited += 1
			check_equal(ran, 0, "step %d: nothing there, no tick" % at)
		if there - played > CUSHION + 1:
			caught_up += 1
			check(ran > 1, "step %d: %d ahead, it catches up" % [at, there - played])
	check(waited > 6, "it waited at the start and in the stalls (%d steps)" % waited)
	check(caught_up > 0, "and caught up after them (%d steps)" % caught_up)
