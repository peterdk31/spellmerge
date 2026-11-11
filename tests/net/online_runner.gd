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
##
## **A room** (online lobby L2, docs/milestones/online-lobby.md; `tools/online_room.sh`): with
## `--signal=<the room server's address>` the two go the players' other way. The host presses
## Play (the hub, two players of its own), opens the room at the altar and hands over the room's
## code; the joining process, with two players of its own, joins by it through the room server
## and is put into the host's hub. The four walk onto the teleporter stone, the host's first
## player starts the run with A, and they fight it; back in the hub they do it again. The host
## passes when every hash check agreed, the joining machine held two seats and a run was started
## from the stone.
##
##     godot --headless --path . -- --online --online-role=host --signal=ws://127.0.0.1:8787/room --ticks=1500
##     godot --headless --path . -- --online --online-role=join --signal=ws://127.0.0.1:8787/room

const NetPlayScript := preload("res://net/net_play.gd")
const EventsScript := preload("res://core/events/events.gd")
const FramesScript := preload("res://core/sim/frames.gd")

const HANDOFF: String = "user://net/"
const HOST_CODE: String = "online_runner_host.code"
const ROOM_CODE: String = "online_runner_room.code"
## A room: the players each machine brings unless told (`--players=`).
const OWN_PLAYERS: int = 2
const HUB_ROOM: String = "res://content/rooms/hub/hub.tres"
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


## A player in a room: it walks onto the hub's stone and waits there, casting now and then; in a
## run it walks a square and fights as `Scripted` does. It reads where its wizard stands (the
## game's own copy of it here), and nothing else of the game.
class Walker:
	extends FrameSource
	var runner: Node = null
	var seat: int = 0
	var steps: int = 0

	func fill_frame(frame: InputFrame, _delta: float) -> void:
		steps += 1
		frame.aim = posmod(steps * 300 + seat * 2000, InputFrame.AIM_STEPS)
		var wizard: Node2D = runner.call(&"wizard_of", seat) as Node2D
		if bool(runner.get(&"in_hub")) and wizard != null:
			var to: Vector2 = (runner.get(&"stone") as Vector2) + Vector2(-24.0 + 16.0 * seat, 8.0) - wizard.position
			if to.length() > 6.0:
				frame.set_move(to.normalized())
			if steps % 120 == 30 + seat * 11:
				frame.press(1)
			return
		# Told to lose its runs (`--runs`): it stands and casts nothing, so the party is soon back
		# in the hub.
		if bool(runner.get(&"loses_runs")):
			return
		frame.set_move([Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT, Vector2.UP][(steps / 30) % 4] * 0.5)
		if steps % 40 == 5:
			frame.press(1)
		frame.hold(1, steps % 90 >= 60)


## A room: true while the party is in the hub, and its stone's middle.
var in_hub: bool = false
var stone: Vector2 = Vector2.ZERO
## A room: true when the party is to lose its runs, so it comes back to the hub and starts the
## next (`--runs=N`: the host passes only with N runs started from the stone, each after the
## first in a recording begun anew).
var loses_runs: bool = false
var _runs_wanted: int = 1

var _hosting: bool = true
## The room server's address ("": by hand, the codes through files).
var _signal: String = ""
var _input: Node = null
var _flow: Node = null
var _opened: bool = false
var _handed_room: bool = false
## A room: the runs started from the stone, the most seats the joining machine held at once, and
## the wizards last counted in the hub.
var _runs: int = 0
var _most_seats: int = 0
var _hub_wizards: int = 0
var _walkers: Array[Walker] = [null, null, null, null]
var _played: int = 0
## A room: this machine's players, and (the host's) the wizards of the whole party: its own and
## every joining machine's (`--party=`; twice its own unless told).
var _players: int = OWN_PLAYERS
var _party: int = 0
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
		elif arg.begins_with("--signal="):
			_signal = arg.trim_prefix("--signal=")
		elif arg.begins_with("--runs="):
			_runs_wanted = maxi(arg.trim_prefix("--runs=").to_int(), 1)
			loses_runs = _runs_wanted > 1
		elif arg.begins_with("--players="):
			_players = clampi(arg.trim_prefix("--players=").to_int(), 1, Replay.SEATS)
		elif arg.begins_with("--party="):
			_party = clampi(arg.trim_prefix("--party=").to_int(), 2, Replay.SEATS)
	if _party == 0:
		_party = mini(_players * 2, Replay.SEATS)
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
	if _signal != "":
		_ready_room()
	elif _hosting:
		DirAccess.remove_absolute(HANDOFF + HOST_CODE)
		DirAccess.remove_absolute(HANDOFF + JOIN_CODE)
		_events.online_host_requested.emit.call_deferred(0)


## A room: the handshake goes through the room server at `_signal` (one machine: no STUN server),
## this machine's players are seated, and the host presses Play.
func _ready_room() -> void:
	_input = get_node_or_null(^"/root/PlayerInput")
	_flow = get_node_or_null(^"/root/Flow")
	var room: RoomBase = load(HUB_ROOM) as RoomBase
	if _input == null or _flow == null or room == null:
		_finish("the PlayerInput or Flow autoload, or the hub, is missing")
		return
	stone = HubRules.area_of(room.places(), HubRules.ROLE_RUN_START).get_center()
	_play.room_handshake_maker = func() -> NetHandshake:
		var through := NetSignalHandshake.new(_signal)
		through.rtc_maker = func(relay: NetRelay) -> NetHandshake: return NetRtc.new(PackedStringArray(), relay)
		return through
	_events.start_stone_changed.connect(_on_stone)
	for player in _players:
		_input.call(&"add_virtual_device", player)
	if _hosting:
		DirAccess.remove_absolute(HANDOFF + ROOM_CODE)
		_events.room_entered.connect(_on_room_entered)
		_events.hub_requested.emit.call_deferred(0)


## The host is in its hub: a wizard of its opens the room at the altar (once).
func _on_room_entered(_room_id: StringName) -> void:
	if not _opened:
		_opened = true
		_events.online_open_requested.emit.call_deferred(0)


## Where the party is; and with all four on the lit stone, the host's first player presses A.
func _on_stone(_standing: int, wizards: int, lit: bool) -> void:
	in_hub = wizards > 0
	_hub_wizards = wizards
	if _hosting and lit and wizards == _party and _play.phase == NetPlayScript.PLAYING:
		_runs += 1
		_events.run_requested.emit(0)


## This machine's wizard on `seat`, or null (a `Walker` asks).
func wizard_of(seat: int) -> Node2D:
	return _flow.call(&"get_wizard", seat) as Node2D


## A room: each seat this machine plays gets its scripted player (the host's own two; the seats
## the host gave the joining machine).
func _seat_walkers() -> void:
	var mine: int = 0
	if _hosting:
		mine = (1 << _players) - 1
	elif _play.session is NetClient:
		mine = (_play.session as NetClient).feed.local_seats
		var held: int = 0
		for seat in Replay.SEATS:
			held += 1 if mine & (1 << seat) != 0 else 0
		_most_seats = maxi(_most_seats, held)
	for seat in Replay.SEATS:
		if mine & (1 << seat) != 0 and _walkers[seat] == null:
			_walkers[seat] = Walker.new()
			_walkers[seat].runner = self
			_walkers[seat].seat = seat
			_frames.set_source(seat, _walkers[seat])


func _process(delta: float) -> void:
	if _done:
		return
	_waited += delta
	if _waited > PATIENCE * (4.0 if loses_runs else 1.0):
		_finish("it took longer than %d seconds (phase %s)" % [PATIENCE, _play.phase])
	elif _signal != "":
		_process_room()
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
	elif _hosting and _play.phase == NetPlayScript.PLAYING and (_play.session as NetHost).stats.ticks >= _ticks:
		_host_leaves()


## A room: the code handed over, the joining machine joining by it, the seats played, and the
## host leaving once its ticks are played.
func _process_room() -> void:
	_seat_walkers()
	if not _hosting and not _joined:
		var room_code: String = _handed(ROOM_CODE)
		if room_code != "":
			_joined = true
			_events.online_join_requested.emit(0, room_code)
	elif _hosting and _play.phase == NetPlayScript.PLAYING and _room_done():
		_most_seats = 0
		var theirs: int = (_play.session as NetHost).guest_seats()
		for seat in Replay.SEATS:
			_most_seats += 1 if theirs & (1 << seat) != 0 else 0
		_host_leaves()


## A room's host is done: its ticks are played (counted through every recording), and with
## `--runs` the runs were started and the last has played a while.
func _room_done() -> bool:
	_played += 1
	if loses_runs:
		return _runs >= _runs_wanted and (_play.session as NetHost).stats.ticks >= 240 and in_hub == false
	return (_play.session as NetHost).stats.ticks >= _ticks


func _on_online_changed(phase: StringName, code: String, note: String) -> void:
	print("ONLINE %s %s %s" % [_role(), phase, note])
	if _signal != "":
		match phase:
			NetPlayScript.CODE:
				if not _handed_room:
					_handed_room = true
					_hand(ROOM_CODE, code)
			NetPlayScript.FAILED:
				_finish(note)
			NetPlayScript.ENDED:
				if not _hosting:
					_finish("")
		return
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
	var host: NetHost = _play.session as NetHost
	var stats: NetStats = host.totals()
	print("ONLINE host ROW %s" % JSON.stringify(stats.row()))
	var why: String = ""
	if host.parted_tick >= 0:
		why = "the two parted at tick %d in %s" % [host.parted_tick, ", ".join(host.parted_areas)]
	elif stats.checks < _ticks / NetChecks.EVERY - 2:
		why = "only %d hash checks came back in %d ticks" % [stats.checks, _ticks]
	elif stats.read_bytes == 0 or stats.stood_in >= stats.ticks:
		why = "the client's frames never arrived"
	elif _signal != "" and _most_seats != _party - _players:
		why = "the joining machines hold %d seats, not %d" % [_most_seats, _party - _players]
	elif _signal != "" and _runs < _runs_wanted:
		why = "%d run(s) started from the stone, not %d (%d wizards in the hub)" % [_runs, _runs_wanted, _hub_wizards]
	if _signal != "":
		print("ONLINE host ROOM %d run(s) from the stone, %d seats on %d joining machine(s)" % [_runs, _most_seats, host.guests.size()])
	for guest in host.guests:
		guest.link.close()
	_finish(why)


func _finish(why: String) -> void:
	if _done:
		return
	_done = true
	if not _hosting and _play != null and why == "":
		# The joining side: it must have played the host's run.
		if _frames.ticks < 60:
			why = "the client's game never ran"
		elif _signal != "" and _most_seats != _players:
			why = "this machine held %d seats, not %d" % [_most_seats, _players]
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
