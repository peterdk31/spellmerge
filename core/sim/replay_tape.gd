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
## - **Live** (`live`; netcode spike S1, docs/milestones/netcode-spike.md): a replay that grows
##   while it plays (the online client's, `Frames.play_live`). Its ticks are added by whoever plays
##   it (`Replay.add_tick_bytes`, from `pump`); one not there yet is waited for, not the end; it
##   ends once `closed` and played out. `sent` is handed the frames this machine's seats
##   (`local_seats`) build meanwhile.

## The most ticks a live replay runs in one physics step to catch up.
const CATCH_UP: int = 3

var replay: Replay = null
## True while it plays, false while it records.
var plays: bool = false
## The next tick it plays (0 before its first).
var at: int = 0
## A live replay: it grows while it plays.
var live: bool = false
## A live replay that will grow no more (the host gone): it ends once played out.
var closed: bool = false
## A live replay: the seats whose input is this machine's (a bit each), built as it plays.
var local_seats: int = 0
## A live replay: the ticks it may hold ahead before it catches up (more a physics step).
var cushion: int = 0
## A live replay: called at each physics step's start, before its ticks are counted (to add the
## ticks that arrived). No arguments.
var pump: Callable = Callable()
## A live replay: handed each frame a local seat builds, `sent.call(tick, frame)`, `tick` being the
## replay's tick it was built in. The frame is reused: read it in the call.
var sent: Callable = Callable()
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


## The ticks it holds that it has not played yet.
func ahead() -> int:
	return replay.tick_count() - at if plays else 0


## True once it has nothing more to play: played out, and not live or live and closed.
func is_done() -> bool:
	return not has_tick() and (not live or closed)


## How many ticks to run this physics step: 1, but for a live replay 0 while it has none (it
## waits), and up to CATCH_UP while it holds more than its cushion.
func ticks_due() -> int:
	if not live:
		return 1
	var held: int = ahead()
	if held <= 0:
		return 0
	return clampi(held - cushion, 1, CATCH_UP)


## Whether seat `seat`'s input is this machine's while it plays live.
func is_local(seat: int) -> bool:
	return live and local_seats & (1 << seat) != 0


## The next recorded tick into `frames` (by seat).
func read_tick(frames: Array[InputFrame]) -> void:
	replay.read_tick(at, frames)
	at += 1
