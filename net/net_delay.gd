class_name NetDelay
extends RefCounted
## The client's input delay `D` (netcode spike S5, docs/milestones/netcode-spike.md): how many
## ticks ahead of the tick it plays a client's frame is sent for, so the frame is at the host
## before its tick. It knows no link, session or clock: it is told each round trip measured and
## each frame sent, and says the delay.
##
## - **Given** (`NetDelay.new(4)`): that delay, never moved.
## - **Not given:** it follows the ping. The delay a ping asks for is its round trip in ticks,
##   the cushion, and one; the round trip taken is the middle one of the last RTTS_KEPT measured
##   (`rtt_ms`; of two the longer), so a ping held up once, by a busy frame or a lost packet
##   sent again, does not count.
##   - `start()`, when the run starts: the delay the pings so far ask for (DEFAULT with none).
##   - `retune()`, at every ping answered in the run, once MIN_RTTS were measured: **up at once**
##     when the middle ping asks for more (frames sent with too short a delay arrive late; a
##     link that got slower shows after three slow pings); **down** only when it asks for
##     LOWER_BY ticks less, so jitter does not move it.
##   - `step()`, at every frame sent: a fall goes one tick every LOWER_EVERY frames. A tick of
##     fall sends two frames for one host tick, which the host uses together, so a slow fall
##     leaves no tick without a frame; a sudden one would leave a row of them.
##
##     var delay := NetDelay.new(-1, 2)
##     delay.add_rtt(48.0)    # each pong
##     delay.start()          # the header
##     delay.retune()         # each pong in the run
##     delay.step()           # each frame sent: the delay to send it with

## The delay with no ping answered yet, and the most it is.
const DEFAULT: int = 6
const MOST: int = 60
## The delay is worked out from this many of the last pings, in the run once this many came.
const RTTS_KEPT: int = 5
const MIN_RTTS: int = 3
## It falls only when the ping asks for this many ticks less.
const LOWER_BY: int = 2
## A fall goes one tick every this many frames sent.
const LOWER_EVERY: int = 4

## A tick's length, in milliseconds.
const TICK_MS: float = 1000.0 / 60.0

## The delay in ticks; below 0 until `start` when none was given.
var ticks: int = -1
## True when the delay was given: it never moves.
var given: bool = false
## The client's cushion (the ticks it holds ahead before it catches up), part of what a ping
## asks for.
var cushion: int = 2
## How often the ping moved the delay since `start`: a rise, or a fall begun.
var retunes: int = 0

## Where a fall ends (`ticks` when it is not falling).
var _fall_to: int = -1
## The last RTTS_KEPT round trips (a ring), how many were measured, and a scratch.
var _rtts: PackedFloat32Array = PackedFloat32Array()
var _measured: int = 0
var _sorted: PackedFloat32Array = PackedFloat32Array()
## Frames sent since the fall's last tick.
var _since_fall: int = 0


func _init(given_ticks: int = -1, with_cushion: int = 2) -> void:
	given = given_ticks >= 0
	if given:
		ticks = mini(given_ticks, MOST)
	_fall_to = ticks
	cushion = with_cushion
	_rtts.resize(RTTS_KEPT)


## A ping came back after `ms` milliseconds.
func add_rtt(ms: float) -> void:
	_rtts[_measured % RTTS_KEPT] = ms
	_measured += 1


## The round trip the delay is worked out from, in milliseconds (0 with none measured).
func rtt_ms() -> float:
	var kept: int = mini(_measured, RTTS_KEPT)
	if kept == 0:
		return 0.0
	_sorted.resize(kept)
	for i in kept:
		_sorted[i] = _rtts[i]
	_sorted.sort()
	return _sorted[kept >> 1]


## The delay the pings ask for now.
func wanted() -> int:
	return clampi(ceili(rtt_ms() / TICK_MS) + cushion + 1, 1, MOST)


## The run starts. Returns the delay.
func start() -> int:
	if not given:
		ticks = wanted() if _measured > 0 else DEFAULT
	_fall_to = ticks
	retunes = 0
	return ticks


## A ping was answered in the run. Returns the delay.
func retune() -> int:
	if given or ticks < 0 or _measured < MIN_RTTS:
		return ticks
	var asked: int = wanted()
	if asked > ticks:
		ticks = asked
		_fall_to = asked
		retunes += 1
	elif asked <= ticks - LOWER_BY:
		if _fall_to == ticks:
			retunes += 1
			_since_fall = 0
		_fall_to = asked
	else:
		_fall_to = ticks
	return ticks


## A frame is sent. Returns the delay to send it with.
func step() -> int:
	if ticks > _fall_to:
		_since_fall += 1
		if _since_fall >= LOWER_EVERY:
			_since_fall = 0
			ticks -= 1
	return ticks
