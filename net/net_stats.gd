class_name NetStats
extends RefCounted
## One session's counters (netcode spike S2, docs/milestones/netcode-spike.md): what S5 measures.
## A session counts as it goes; whoever owns it shows `line()` or logs `row()`.

## A tick's length, in milliseconds.
const TICK_MS: float = 1000.0 / 60.0

## The round trip, in milliseconds: the last ping's, and smoothed (the client measures it).
var rtt_ms: float = 0.0
var rtt_smooth_ms: float = 0.0
var pings: int = 0
## The client's input delay `D`, in ticks.
var delay: int = 0

## Messages and bytes, each way.
var sent: int = 0
var sent_bytes: int = 0
var read: int = 0
var read_bytes: int = 0

## The client: physics steps while it played, those that ran no tick (it waited), the ticks run,
## and the most ticks it ever held ahead.
var steps: int = 0
var steps_waited: int = 0
var ticks_run: int = 0
var most_ahead: int = 0
## The client: its presses that came back in the host's ticks, and how many physics steps each
## took from the step it was sent to the step it ran.
var presses: int = 0
var presses_sent: int = 0
var press_steps: int = 0
var press_steps_worst: int = 0

## The host: ticks recorded, those whose client frame had not arrived (the last stood in), and
## the client frames that arrived after their tick.
var ticks: int = 0
var stood_in: int = 0
var late_frames: int = 0

## Hash checks made (the client: sent), those that differed, and those the host could not make
## (the client's came too late to compare).
var checks: int = 0
var mismatches: int = 0
var unchecked: int = 0
## Microseconds spent hashing, and in the session's own work on the link (reading, decoding,
## sending).
var hash_usec: int = 0
var net_usec: int = 0


func count_sent(bytes: int) -> void:
	sent += 1
	sent_bytes += bytes


func count_read(bytes: int) -> void:
	read += 1
	read_bytes += bytes


## A ping came back after `ms` milliseconds.
func add_rtt(ms: float) -> void:
	rtt_ms = ms
	rtt_smooth_ms = ms if pings == 0 else lerpf(rtt_smooth_ms, ms, 0.2)
	pings += 1


## A press came back after `after_steps` physics steps.
func add_press(after_steps: int) -> void:
	presses += 1
	press_steps += after_steps
	press_steps_worst = maxi(press_steps_worst, after_steps)


## The mean time from a press to its tick, in milliseconds (0 with none measured).
func press_ms() -> float:
	return float(press_steps) / float(presses) * TICK_MS if presses > 0 else 0.0


## The counters as a row, by name (a log's line, the grid's).
func row() -> Dictionary:
	return {
		"rtt_ms": snappedf(rtt_smooth_ms, 0.1), "delay": delay,
		"sent": sent, "sent_bytes": sent_bytes, "read": read, "read_bytes": read_bytes,
		"steps": steps, "steps_waited": steps_waited, "ticks_run": ticks_run, "most_ahead": most_ahead,
		"presses": presses, "press_ms": snappedf(press_ms(), 0.1), "press_worst_ms": snappedf(press_steps_worst * TICK_MS, 0.1),
		"ticks": ticks, "stood_in": stood_in, "late_frames": late_frames,
		"checks": checks, "mismatches": mismatches, "unchecked": unchecked,
		"hash_usec": hash_usec, "net_usec": net_usec,
	}


## One line of text for the screen.
func line() -> String:
	if ticks > 0:
		return "host: %d ticks, %d stood in, %d late, %d/%d checks parted, %d B out, %d B in" % [ticks, stood_in, late_frames, mismatches, checks, sent_bytes, read_bytes]
	return "client: ping %d ms, delay %d, %d ticks, waited %d, press %d ms, %d checks, %d B out, %d B in" % [roundi(rtt_smooth_ms), delay, ticks_run, steps_waited, roundi(press_ms()), checks, sent_bytes, read_bytes]
