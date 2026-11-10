class_name FrameSource
extends RefCounted
## What fills a seat's input frame instead of its device (online-ready N2): a bot today (tests/bots),
## and later the network (the host's source for a client's seat). The frames service
## (core/sim/frames.gd) asks it at each tick's start (`Frames.set_source`); the simulation never
## knows which it was.


## Fill `frame` for a tick of `delta` seconds: its walk, aim and buttons (it comes cleared; its
## seat is set). A bot's commands are the bus's (core/events); a source that passes on another
## machine's frame may add that frame's commands (`InputFrame.add_command`), but never a JOIN or a
## LEAVE: a seat joins and leaves through the input layer (its device, real or virtual), which is
## what seats it and tells the recording, so the frames service drops one a source wrote.
func fill_frame(_frame: InputFrame, _delta: float) -> void:
	pass
