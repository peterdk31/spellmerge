class_name Departure
extends RefCounted
## The party's departure (the owner, 2026-11-19: a loading screen as a run starts and as the party
## returns): the next world is made TICKS ticks after it is decided, so the HUD's loading screen is
## down before the tick that makes it, which freezes the game (a run's biome a second or more, the
## hub a fifth of one). Two ways: to a run (A on the hub's lit stone) and to the hub (the run's end,
## lost or won). Flow's state (it holds one): counted in ticks, never real time, so the next world is
## made on the same tick on every machine and in a replay. Once begun it is the party's: nothing but
## `cancel` (the game left for the main menu, the world gone) ends it before it is due.

## Where the party goes.
enum To { RUN, HUB }

## Ticks from the decision to the next world (a fifth of a second): longer than the loading screen
## takes to come down (hud/panels/loading/, COVER_FRAMES of STEP_SECONDS: 0.1 s, at any frame rate).
const TICKS: int = 12

## The seat it is for (-1: none under way), where to, and the ticks left.
var seat: int = -1
var to: To = To.RUN
var left: int = 0


## True while a departure is under way.
func is_under_way() -> bool:
	return seat >= 0


## Depart for `where`, for seat `for_seat`, TICKS from now. False, and nothing changes, while one is
## already under way.
func begin(for_seat: int, where: To) -> bool:
	if is_under_way() or for_seat < 0:
		return false
	seat = for_seat
	to = where
	left = TICKS
	return true


## One tick of it: true on the tick it is due. The caller then reads `to` and ends it with `take`.
func due() -> bool:
	if not is_under_way():
		return false
	left -= 1
	return left <= 0


## The seat of a departure that is due, ending it (-1 when none was under way).
func take() -> int:
	var was: int = seat
	cancel()
	return was


## Ends it before it is due.
func cancel() -> void:
	seat = -1
	left = 0
