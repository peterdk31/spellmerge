extends "res://tests/support/screenshot.gd"
## Screenshots of the intro (living staffs H6) with four players (the widest spread down the shaft): the wizard walking in, the
## drops ("Oops. Oops. Oops."), the fall down the shaft, the thud, and the staffs looking up the
## shaft. The intro is put at each moment by hand (its time, then a zero step), so the shots do
## not depend on the frame rate.


const SAVE_PATH: String = "user://shot_intro_save.cfg"
const MOMENTS: Array = [[1.5, "intro_walk_in"], [5.0, "intro_oops"], [6.6, "intro_fall"], [7.9, "intro_thud"], [11.0, "intro_obviously"], [12.6, "intro_home_is_up_there"]]


func take() -> void:
	if not need(["PlayerInput", "Flow", "Events"]):
		return
	var input: Node = root.get_node("PlayerInput")
	var flow: Node = root.get_node("Flow")
	DirAccess.remove_absolute(SAVE_PATH)
	flow.set("save", SaveFile.new(SAVE_PATH))
	flow.set("intro_enabled", true)
	for index in 4:
		input.call("add_virtual_device", index)
	root.get_node("Events").emit_signal("play_requested", 0)
	var intro: Node = flow.get("intro") as Node
	if intro == null:
		fail("the intro did not start")
		return
	# Hold it still between shots: Flow steps it only through its own process.
	flow.set_process(false)
	for moment: Array in MOMENTS:
		intro.set("time", float(moment[0]))
		intro.call("step", 0.0)
		await shot(String(moment[1]))
	flow.set_process(true)
	DirAccess.remove_absolute(SAVE_PATH)
