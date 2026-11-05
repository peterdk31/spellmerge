class_name FrameSource
extends RefCounted
## What fills a seat's input frame instead of its device (online-ready N2): a bot today (tests/bots),
## and later the network. The frames service (core/sim/frames.gd) asks it at each tick's start
## (`Frames.set_source`); the simulation never knows which it was.


## Fill `frame` for a tick of `delta` seconds: its walk, aim and buttons (it comes cleared; its
## seat is set). Commands are the bus's (core/events), not a source's.
func fill_frame(_frame: InputFrame, _delta: float) -> void:
	pass
