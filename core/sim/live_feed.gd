class_name LiveFeed
extends RefCounted
## Whoever plays a live replay (netcode spike S1, docs/milestones/netcode-spike.md;
## `Frames.play_live`): the online client's session (net/, later) extends it, as a bot extends
## `FrameSource`. The frames service calls it at each physics step's start and knows nothing else
## of it; it knows no network either.
##
## - **`replay`**: the replay it feeds, the one played (its header read, its ticks added here).
## - **`pump`**: add the ticks that arrived to `replay` (`Replay.add_tick_bytes`), and set `closed`
##   once no more will come (the host gone): the replay then ends once played out.
## - **`send`**: take this machine's seats' frames (`local_seats`), one a physics step, also while
##   the replay waits, so the other machine hears this one at its own pace. `tick` is the replay's
##   next tick to play; which of the host's ticks a frame is for (the input delay) is the feed's.
## - **`ticks_to_run`**: how many ticks this step, with `ahead` (at least 1) there to play: the
##   pacing (the cushion, the catch-up) is the feed's, the frames service only keeps it within what
##   is there. The default runs one, up to CATCH_UP while more than `cushion` are ahead.

## The most ticks the default pacing runs in one physics step to catch up. With the engine's own
## catch-up (`max_physics_steps_per_frame`, 3) a slow frame runs up to nine.
const CATCH_UP: int = 3

## The replay it feeds (set before `Frames.play_live`).
var replay: Replay = null
## No more ticks will come: the replay ends once played out.
var closed: bool = false
## The seats whose input is this machine's (a bit each). Read when the play starts.
var local_seats: int = 0
## The ticks the default pacing lets wait before it catches up.
var cushion: int = 2


func _init(seats: int = 0, wait: int = 2) -> void:
	local_seats = seats & 0x0f
	cushion = maxi(wait, 0)


## Add the ticks that arrived to `replay`. Called first in every physics step.
func pump() -> void:
	pass


## Take local seat `frame.seat`'s frame of this physics step (reused: read it here). `tick`: the
## replay's next tick to play.
func send(_tick: int, _frame: InputFrame) -> void:
	pass


## How many of the `ahead` ticks there (at least 1) to run this physics step.
func ticks_to_run(ahead: int) -> int:
	return clampi(ahead - cushion, 1, CATCH_UP)
