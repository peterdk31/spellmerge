class_name ReplayTape
extends RefCounted
## A replay on the frames service's deck (core/sim/frames.gd; online-ready N2): one being recorded
## or played, where it is, and how the runs it starts start. Frames holds one at a time, or none.
##
## - **Recording** (`recording`): each tick's frames go on the end (`record_tick`).
## - **Playing** (`playing`): each tick takes the next recorded one (`read_tick`) until none is left.
##   The seats it has seated (`seated`) are the replay's: its header's, then each JOIN and LEAVE as
##   its tick is read, whatever this machine's devices do meanwhile.
## - **The runs it starts:** each run's seed is the next of a dealer seeded by the replay's
##   `run_seed` (`next_run_seed`), so a recording that starts several runs (a restart) and its
##   playing get the same seeds in the same order; each run takes a copy of the replay's rules
##   (`run_rules`). This is instance state of the tape the frames service holds, never a global.
## - **Live** (`feed`; netcode spike S1, docs/milestones/netcode-spike.md): a replay that grows
##   while it plays (the online client's, `Frames.play_live`), fed by a `LiveFeed`. A tick not
##   there yet is waited for, not the end; it ends once its feed is closed and it is played out.

var replay: Replay = null
## True while it plays, false while it records.
var plays: bool = false
## The next tick it plays (0 before its first).
var at: int = 0
## While it plays: the seats the replay has seated (a bit each).
var seated: int = 0
## A live replay's feed (null: a replay file).
var feed: LiveFeed = null
## A live replay's local seats (a bit each): its feed's when the play started.
var local_seats: int = 0
var _dealer: RandomNumberGenerator = RandomNumberGenerator.new()


func _init(of: Replay, playing_it: bool, fed_by: LiveFeed = null) -> void:
	replay = of
	plays = playing_it
	feed = fed_by
	local_seats = fed_by.local_seats & 0x0f if fed_by != null else 0
	seated = of.seats & 0x0f if playing_it else 0
	_dealer.seed = of.run_seed


## A tape that records into `replay`.
static func recording(into: Replay) -> ReplayTape:
	return ReplayTape.new(into, false)


## A tape that plays `replay` from its first tick; live, fed by `feed`, when one is given.
static func playing(from: Replay, feed: LiveFeed = null) -> ReplayTape:
	return ReplayTape.new(from, true, feed)


## True for a live replay (one that grows while it plays).
func is_live() -> bool:
	return feed != null


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
	return not has_tick() and (feed == null or feed.closed)


## How many ticks to run this physics step: 1; for a live replay none while it has none (it waits),
## else as its feed paces it, never more than it holds.
func ticks_due() -> int:
	if feed == null:
		return 1
	var held: int = ahead()
	if held <= 0:
		return 0
	return clampi(feed.ticks_to_run(held), 0, held)


## Whether seat `seat`'s input is this machine's (a live replay's local seat).
func is_local(seat: int) -> bool:
	return seat >= 0 and local_seats & (1 << seat) != 0


## The next recorded tick into `frames` (by seat).
func read_tick(frames: Array[InputFrame]) -> void:
	replay.read_tick(at, frames)
	at += 1
