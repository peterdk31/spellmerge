class_name NetSession
extends RefCounted
## One side of one link of an online run (netcode spike S2, docs/milestones/netcode-spike.md): what
## the host's view of a guest machine and the client's session share (`NetGuest`, `NetClient`). A
## session sits between a link and the frames service and knows nothing else of the game.
##
## - **Reading the link** (`pump`): at most `max_read` messages a call, each decoded strictly
##   (`NetMessage`) and handed to `_take`, which takes only the kinds the other side may send.
##   Anything else closes the link, `problem` says why, and nothing more is read from it.
## - **A machine that went silent** is taken for gone: one that is closed, loses its network or
##   crashes says no goodbye, and its link stays open for as long as the wire cares to keep it.
##   Once something was heard, SILENT_MS of this machine's own stepping with nothing read closes
##   the link (`problem` says so), as any refusal does. Both sides send steadily (the client its
##   pings and frames, the host its pongs and ticks), so silence is never a quiet moment of the
##   game. Before the first message nothing is counted (the other machine may still load), and a
##   stall of this machine's own counts as STALL_MS at most.
## - **The checks** (`_check`): after every tick the tick's part of the state is hashed
##   (`NetChecks`). The client sends each whole check, the host's guest compares; the first that differs
##   is kept on both sides (`parted_tick`, `parted_areas`).
## - **The link it is given is open.** Whoever holds the session makes it once the link is up, and
##   calls `pump` each physics step until the run starts and `after_tick` after every tick has
##   stepped.
## - A session writes no file and logs nothing: its holder shows `problem`, the parting and the
##   counters (`stats`), and saves `replay`.

const FramesScript := preload("res://core/sim/frames.gd")

## Nothing read for this long (milliseconds this machine stepped through): the other is gone.
const SILENT_MS: int = 10000
## The most one pump adds to the silence: this machine standing still is not the other's silence.
const STALL_MS: int = 250

var link: NetLink
var frames: FramesScript
## The game's areas by name (`Tick.state_areas`), for the checks; invalid: no checks.
var areas: Callable
var stats: NetStats = NetStats.new()
var checks: NetChecks = NetChecks.new()
## The run: the host's recording, the client's copy of it as it arrives (null before the run).
var replay: Replay = null
## Why this side closed the link ("" while it has not).
var problem: String = ""
## The first check that failed: its tick (-1: none) and the areas that differed.
var parted_tick: int = -1
var parted_areas: PackedStringArray = PackedStringArray()
## The most messages read in one `pump`.
var max_read: int = 64

## The time in milliseconds, for the silence (and a client's pings): a test's own; the engine's
## clock otherwise.
var clock: Callable = Callable()

var _message: NetMessage = NetMessage.new()
## True once a message was read; the silence since the last one, and when it was last counted.
var _heard: bool = false
var _silent_ms: float = 0.0
var _pumped_at: float = -1.0


func _init(frames_service: FramesScript, over: NetLink, state_areas: Callable) -> void:
	frames = frames_service
	link = over
	areas = state_areas


## Read what the other side sent. Returns true when everything waiting was read (false: the
## limit was reached, or the link was refused).
func pump() -> bool:
	if problem != "":
		return false
	var began: int = Time.get_ticks_usec()
	var drained: bool = false
	var read: int = 0
	for i in max_read:
		var bytes: PackedByteArray = link.read()
		if bytes.is_empty():
			drained = true
			break
		read += 1
		stats.count_read(bytes.size())
		var why: String = _message.decode(bytes)
		if why == "":
			why = _take(_message)
		if why != "":
			_refuse(why)
			break
	_listen(read > 0)
	stats.net_usec += Time.get_ticks_usec() - began
	return drained and problem == ""


## The silence is counted (see the top): `heard` when this pump read something.
func _listen(heard: bool) -> void:
	var now: float = _now_ms()
	var passed: float = clampf(now - _pumped_at, 0.0, float(STALL_MS)) if _pumped_at >= 0.0 else 0.0
	_pumped_at = now
	if heard:
		_heard = true
		_silent_ms = 0.0
		return
	if not _heard or problem != "" or not link.is_open():
		return
	_silent_ms += passed
	if _silent_ms >= float(SILENT_MS):
		_refuse("nothing was heard from the other machine for %d seconds" % (SILENT_MS / 1000))


func _now_ms() -> float:
	return float(clock.call()) if clock.is_valid() else float(Time.get_ticks_msec())


## Call after every tick has stepped.
func after_tick() -> void:
	pass


## A message of the other side's: "" when it was taken, else why the link closes.
func _take(_message_read: NetMessage) -> String:
	return "nothing is taken"


## Tick `tick` has stepped: its part of the state hashed. Returns the whole check when `tick` is
## a check's last, else an empty one.
func _check(tick: int) -> Dictionary[String, int]:
	var began: int = Time.get_ticks_usec()
	var check: Dictionary[String, int] = checks.add(tick, areas.call())
	stats.hash_usec += Time.get_ticks_usec() - began
	return check


## The first check that failed is kept.
func _part(tick: int, differing: PackedStringArray) -> void:
	if parted_tick < 0:
		parted_tick = tick
		parted_areas = differing


func _send(bytes: PackedByteArray) -> void:
	link.send(bytes)
	stats.count_sent(bytes.size())


## Close the link for `why`: nothing more is read from it or sent.
func _refuse(why: String) -> void:
	problem = why
	link.close()
