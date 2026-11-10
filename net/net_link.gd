class_name NetLink
extends RefCounted
## A link to one other machine (netcode spike S2, docs/milestones/netcode-spike.md): whole
## messages out and in, in order, none lost, as a reliable ordered data channel gives them. The
## sessions (`NetHost`, `NetClient`) know only this; what carries the bytes is a link's own: the
## loopback in one process (`NetLoopback`: the tests and the measured grid), WebRTC (S4), and a
## conditioner round either (`NetConditioner`: delay, jitter, loss).
##
## A link has no clock of its own and no thread: it moves bytes when it is called. A session is
## handed a link that is already open (connecting is the link's maker's, S4), and a link carries
## a message of any size up to `NetMessage.MAX_BYTES` whole (a link whose wire takes less splits
## and joins it itself).


## Send one message (never empty: an empty one is nothing). Dropped once the link is closed.
func send(_bytes: PackedByteArray) -> void:
	pass


## The next message that arrived, or empty when none waits. What arrived before the link closed
## can still be read after.
func read() -> PackedByteArray:
	return PackedByteArray()


## False once either side closed it (or it broke): nothing more will arrive than what waits.
func is_open() -> bool:
	return false


func close() -> void:
	pass
