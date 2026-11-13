class_name NetRun
extends RefCounted
## What whoever holds an online run watches of it (online lobby L5b,
## docs/milestones/online-lobby.md), whichever side this machine plays: the host's session with
## its guest machines (`NetHost`) or one end of one link (`NetSession`: the client's, and the
## host's view of each guest). `NetPlay` asks these and never which one it holds; what only one
## side does (a host's guests coming and going, a client's devices) it asks that side.


## Call after every tick has stepped.
func after_tick() -> void:
	pass


## The counters, for the screen's line and the log's row.
func counters() -> NetStats:
	return null


## The tick of the first hash check that failed (-1: none), and the areas that differed there.
func parted_at() -> int:
	return -1


func parted_in() -> PackedStringArray:
	return PackedStringArray()
