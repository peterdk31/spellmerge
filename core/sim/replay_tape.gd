class_name ReplayTape
extends RefCounted
## A replay on the frames service's deck (core/sim/frames.gd; online-ready N2): one being recorded
## or played, where it is, and how the runs it starts start. Frames holds one at a time, or none.
##
## - **Recording** (`recording`): each tick's frames go on the end (`record_tick`).
## - **Playing** (`playing`): each tick takes the next recorded one (`read_tick`) until none is left.
## - **The runs it starts:** each run's seed is the next of a dealer seeded by the replay's
##   `run_seed` (`next_run_seed`), so a recording that starts several runs (a restart) and its
##   playing get the same seeds in the same order; each run takes a copy of the replay's rules
##   (`run_rules`). This is instance state of the tape the frames service holds, never a global.

var replay: Replay = null
## True while it plays, false while it records.
var plays: bool = false
## The next tick it plays (0 before its first).
var at: int = 0
var _dealer: RandomNumberGenerator = RandomNumberGenerator.new()


func _init(of: Replay, playing_it: bool) -> void:
	replay = of
	plays = playing_it
	_dealer.seed = of.run_seed


## A tape that records into `replay`.
static func recording(into: Replay) -> ReplayTape:
	return ReplayTape.new(into, false)


## A tape that plays `replay` from its first tick.
static func playing(from: Replay) -> ReplayTape:
	return ReplayTape.new(from, true)


## The seed of the next run it starts.
func next_run_seed() -> int:
	return _dealer.randi()


## The rules a run it starts plays by (a copy: a run's change is its own).
func run_rules() -> SessionRules:
	return replay.rules.copy()


## Record a tick: the frames of the seats in `mask`.
func record_tick(frames: Array[InputFrame], mask: int) -> void:
	replay.add_tick(frames, mask)


## True while a recorded tick is left to play.
func has_tick() -> bool:
	return plays and at < replay.tick_count()


## The next recorded tick into `frames` (by seat).
func read_tick(frames: Array[InputFrame]) -> void:
	replay.read_tick(at, frames)
	at += 1
