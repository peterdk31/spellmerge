extends "res://tests/support/suite.gd"
## The intro (living staffs H6, docs/milestones/M2-living-staffs.md, "The intro"): Play on a new
## save shows it, and the next Play does not; any joined player's button skips it at once; played
## out it starts the run within LENGTH (under 15 s); one staff is dropped per player, each later
## than the one before and faster each time; the captions run in order. Uses the real autoloads
## with a save of its own; time moves only by Flow.step.
##
## godot --headless --path . --script res://tests/gameplay/flow/test_intro.gd

const FlowScript := preload("res://gameplay/flow/flow.gd")
const IntroScript := preload("res://gameplay/flow/intro.gd")
const SAVE_PATH: String = "user://test_intro_save.cfg"
const STEP: float = 0.0625

var flow: FlowScript
var input: Node
var events: Node


func before_each() -> void:
	flow = root.get_node("Flow") as FlowScript
	input = root.get_node("PlayerInput")
	events = root.get_node("Events")
	DirAccess.remove_absolute(SAVE_PATH)
	flow.save = SaveFile.new(SAVE_PATH)
	flow.intro_enabled = true
	flow.world_parent = own(Node.new()) as Node
	root.add_child(flow.world_parent)
	input.add_virtual_device(0)


func after_each() -> void:
	flow.stop_run()
	flow.world_parent = null
	flow.intro_enabled = false
	flow.save = SaveFile.new()
	for seat in 4:
		input.leave(seat)
	DirAccess.remove_absolute(SAVE_PATH)


## Step Flow until the intro is gone or `seconds` have passed; the seconds it took.
func _run(seconds: float) -> float:
	var spent: float = 0.0
	while flow.intro != null and spent < seconds:
		flow.step(STEP)
		spent += STEP
	return spent


func test_the_first_play_on_a_new_save_shows_the_intro_and_the_next_does_not() -> void:
	events.play_requested.emit(0)
	check_equal(flow.state, FlowScript.State.INTRO, "a new save gets the intro")
	check(flow.intro != null and flow.intro.is_inside_tree(), "the intro is on show")
	var spent: float = _run(20.0)
	check(spent <= IntroScript.LENGTH + STEP and spent < 15.0, "it ends within its time (%.2f s)" % spent)
	check_equal(flow.state, FlowScript.State.RUNNING, "then the run starts")
	check(flow.get_wizard(0) != null, "with the player's staff in it")
	check(flow.world_parent.get_node_or_null(FlowScript.INTRO_NAME) == null, "and the intro is gone")
	flow.stop_run()
	events.play_requested.emit(0)
	check_equal(flow.state, FlowScript.State.RUNNING, "the next Play starts the run at once")
	# The flag is on disk: a new session on the same save skips it too.
	check(SaveFile.new(SAVE_PATH).has_flag(FlowScript.INTRO_SEEN), "the save remembers it")


func test_any_players_button_skips_it_at_once() -> void:
	input.add_virtual_device(2)
	for action: StringName in [&"accept", &"staff_3"]:
		DirAccess.remove_absolute(SAVE_PATH)
		flow.save = SaveFile.new(SAVE_PATH)
		flow.stop_run()
		events.play_requested.emit(0)
		check(flow.intro != null, "the intro shows")
		flow.step(STEP)
		check(flow.intro != null, "nobody pressed anything yet")
		input.send_virtual(2, action, 1.0)
		flow.step(STEP)
		input.send_virtual(2, action, 0.0)
		check(flow.intro == null, "player 3's %s skips it on the next step" % action)
		check_equal(flow.state, FlowScript.State.RUNNING, "and the run starts for everyone")
		check(flow.save.has_flag(FlowScript.INTRO_SEEN), "a skipped intro counts as seen")


func test_one_staff_drops_per_player_faster_each_time() -> void:
	for seat in [1, 2, 3]:
		input.add_virtual_device(seat)
	events.play_requested.emit(0)
	var shown: IntroScript = flow.intro
	check(shown != null, "the intro shows")
	if shown == null:
		return
	check_equal(shown.drops(), 4, "one staff per player")
	var gap: float = INF
	for i in range(1, 4):
		var this_gap: float = shown.drop_time(i) - shown.drop_time(i - 1)
		check(this_gap > 0.0 and this_gap < gap, "drop %d comes sooner after the last than the one before" % i)
		gap = this_gap
		check(shown.hit_time(i) > shown.drop_time(i), "staff %d lands after it is dropped" % i)
	check(shown.hit_time(3) + 5.4 < IntroScript.LENGTH, "the last one lands with time for the closing lines")
	check_equal(shown.caption_at(shown.drop_time(3) + 0.1), "\"Oops. Oops. Oops. Oops.\"", "an oops for each drop")


## Every staff leaves the hand over the hole and falls inside the shaft's walls, for 1-4 players.
func test_every_staff_drops_down_the_hole_and_falls_inside_the_shaft() -> void:
	for count in range(1, 5):
		var seats: Array[int] = []
		for seat in count:
			seats.append(seat)
		var shown := IntroScript.new()
		own(shown)
		shown.setup(seats, null)
		var inside: bool = true
		var seen_in_shaft: PackedInt32Array = PackedInt32Array()
		seen_in_shaft.resize(count)
		while not shown.is_done():
			shown.step(STEP)
			for i in count:
				var at: Vector2 = shown.staff_position(i)
				var falling: bool = shown.time >= shown.drop_time(i) and shown.time < shown.hit_time(i)
				if falling and at.y > IntroScript.SHAFT_TOP - 4.0 and at.y < IntroScript.SHAFT_END:
					seen_in_shaft[i] += 1
					if at.x <= IntroScript.SHAFT_LEFT or at.x >= IntroScript.SHAFT_RIGHT:
						inside = false
						check(false, "%d players: staff %d at %s is outside the shaft" % [count, i, at])
						break
			if not inside:
				break
		for i in count:
			check(seen_in_shaft[i] > 0, "%d players: staff %d falls down the shaft" % [count, i])


func test_the_captions_run_in_order() -> void:
	var shown := IntroScript.new()
	own(shown)
	shown.setup([0] as Array[int], null)
	var seen: PackedStringArray = PackedStringArray()
	var at: float = 0.0
	while at < IntroScript.LENGTH:
		var line: String = shown.caption_at(at)
		if line != "" and (seen.is_empty() or seen[seen.size() - 1] != line):
			seen.append(line)
		at += STEP
	var wanted: PackedStringArray = ["New staff day.", "\"Oops.\"", "\"Oh well.\"", "THUD.", "Thrown out? No. Dropped. By accident. Obviously.", "Home is up there."]
	var from: int = 0
	for line in wanted:
		var found: int = seen.find(line, from)
		check(found >= 0, "\"%s\" comes, in order (saw %s)" % [line, seen])
		from = maxi(found, from)


func test_it_stays_off_when_disabled() -> void:
	flow.intro_enabled = false
	events.play_requested.emit(0)
	check_equal(flow.state, FlowScript.State.RUNNING, "with the intro off, Play starts the run")
