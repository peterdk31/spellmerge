extends Node
## Two game processes on one machine, linked as two players would link them (netcode spike S4,
## docs/milestones/netcode-spike.md): the real game, its main menu's requests, the real WebRTC
## handshake and link (no STUN server: one machine), a sandbox run on both, each seat played by a
## script. What the unit tests cannot cover (the autoloads wired together: NetPlay, the frames
## service, the Tick, Flow, Coop) plays here, and the sessions' own hash checks say whether the
## two processes agreed. `tools/online_pair.sh` starts both and reads their lines.
##
## The main menu adds this node on the user argument `--online`, in a build or checkout that has
## tests/ (as it adds the stress run on `--stress`):
##
##     godot --headless --path . -- --online --online-role=host --ticks=600
##     godot --headless --path . -- --online --online-role=join
##
## The codes go from one process to the other through files under `user://net/` (the two share
## it), which stand for the players' copy and paste. The host plays `--ticks` ticks and leaves; the
## joining process plays until the host is gone. The lines:
##
##     ONLINE <role> <phase> <note>          (every `online_changed`)
##     ONLINE <role> ROW <the counters, JSON>   (the host's, as it leaves)
##     ONLINE <role> LINE <the counters' last line on the screen>
##     ONLINE <role> OK | FAILED: <why>      (then the process quits)

const NetPlayScript := preload("res://net/net_play.gd")
const EventsScript := preload("res://core/events/events.gd")
const FramesScript := preload("res://core/sim/frames.gd")

const HANDOFF: String = "user://net/"
const HOST_CODE: String = "online_runner_host.code"
const JOIN_CODE: String = "online_runner_join.code"
## The host's run, in ticks, and the longest the whole thing may take, in seconds.
const TICKS: int = 600
const PATIENCE: float = 120.0


## A player that reads nothing of the game: it walks a square, sweeps its aim and casts.
class Scripted:
	extends FrameSource
	var steps: int = 0

	func fill_frame(frame: InputFrame, _delta: float) -> void:
		steps += 1
		frame.set_move([Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT, Vector2.UP][(steps / 30) % 4] * 0.5)
		frame.aim = posmod(steps * 300, InputFrame.AIM_STEPS)
		if steps % 40 == 5:
			frame.press(0)
		frame.hold(0, steps % 90 >= 60)


var _hosting: bool = true
var _ticks: int = TICKS
var _play: NetPlayScript
var _events: EventsScript
var _frames: FramesScript
var _waited: float = 0.0
var _answered: bool = false
var _joined: bool = false
var _done: bool = false
var _last_line: String = ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for arg in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		if arg.begins_with("--online-role="):
			_hosting = arg.trim_prefix("--online-role=") != "join"
		elif arg.begins_with("--ticks="):
			_ticks = maxi(arg.trim_prefix("--ticks=").to_int(), 1)
	_play = get_node_or_null(^"/root/NetPlay") as NetPlayScript
	_events = get_node_or_null(^"/root/Events") as EventsScript
	_frames = get_node_or_null(^"/root/Frames") as FramesScript
	if _play == null or _events == null or _frames == null:
		_finish("the NetPlay, Events or Frames autoload is missing")
		return
	# One machine: no STUN server is asked.
	_play.handshake_maker = func() -> NetHandshake: return NetRtc.new(PackedStringArray())
	_events.online_changed.connect(_on_online_changed)
	_events.online_line_changed.connect(func(line: String) -> void: _last_line = line)
	DirAccess.make_dir_recursive_absolute(HANDOFF)
	if _hosting:
		DirAccess.remove_absolute(HANDOFF + HOST_CODE)
		DirAccess.remove_absolute(HANDOFF + JOIN_CODE)
		_events.online_host_requested.emit.call_deferred(0)


func _process(delta: float) -> void:
	if _done:
		return
	_waited += delta
	if _waited > PATIENCE:
		_finish("it took longer than %d seconds (phase %s)" % [PATIENCE, _play.phase])
	elif _hosting and not _answered and _play.phase == NetPlayScript.CODE:
		var answer: String = _handed(JOIN_CODE)
		if answer != "":
			_answered = true
			_events.online_answer_requested.emit(0, answer)
	elif not _hosting and not _joined:
		var code: String = _handed(HOST_CODE)
		if code != "":
			_joined = true
			_events.online_join_requested.emit(0, code)
	elif _hosting and _play.phase == NetPlayScript.PLAYING and _play.session.stats.ticks >= _ticks:
		_host_leaves()


func _on_online_changed(phase: StringName, code: String, note: String) -> void:
	print("ONLINE %s %s %s" % [_role(), phase, note])
	match phase:
		NetPlayScript.CODE:
			if note == "":
				_hand(HOST_CODE if _hosting else JOIN_CODE, code)
		NetPlayScript.PLAYING:
			# This machine's seat plays by script from here.
			_frames.set_source(0 if _hosting else NetHost.SEAT, Scripted.new())
		NetPlayScript.FAILED:
			_finish(note)
		NetPlayScript.ENDED:
			if not _hosting:
				_finish("")


## The host played its ticks: its counters are judged, and the process ends (the link with it).
func _host_leaves() -> void:
	var stats: NetStats = _play.session.stats
	print("ONLINE host ROW %s" % JSON.stringify(stats.row()))
	var why: String = ""
	if _play.session.parted_tick >= 0:
		why = "the two parted at tick %d in %s" % [_play.session.parted_tick, ", ".join(_play.session.parted_areas)]
	elif stats.checks < _ticks / NetChecks.EVERY - 2:
		why = "only %d hash checks came back in %d ticks" % [stats.checks, _ticks]
	elif stats.read_bytes == 0 or stats.stood_in >= stats.ticks:
		why = "the client's frames never arrived"
	_play.session.link.close()
	_finish(why)


func _finish(why: String) -> void:
	if _done:
		return
	_done = true
	if not _hosting and _play != null and why == "":
		# The joining side: it must have played the host's run.
		if _frames.ticks < 60:
			why = "the client's game never ran"
	print("ONLINE %s LINE %s" % [_role(), _last_line])
	print("ONLINE %s %s" % [_role(), "OK" if why == "" else "FAILED: " + why])
	get_tree().quit(0 if why == "" else 1)


func _role() -> String:
	return "host" if _hosting else "join"


func _hand(file_name: String, text: String) -> void:
	var file: FileAccess = FileAccess.open(HANDOFF + file_name + ".part", FileAccess.WRITE)
	if file == null:
		_finish("user://net/ cannot be written")
		return
	file.store_string(text)
	file.close()
	# Whole or not there: the other process never reads half a code.
	DirAccess.rename_absolute(HANDOFF + file_name + ".part", HANDOFF + file_name)


func _handed(file_name: String) -> String:
	if not FileAccess.file_exists(HANDOFF + file_name):
		return ""
	return FileAccess.get_file_as_string(HANDOFF + file_name)
