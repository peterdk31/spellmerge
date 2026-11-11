class_name NetClient
extends NetSession
## The client's side of an online run (netcode spike S2, docs/milestones/netcode-spike.md): it
## plays the host's run as a live replay (`Frames.play_live`, fed by its `feed`) and sends its
## own seats' frames to the host.
##
## - **Before the run:** whoever holds the session calls `pump` each physics step. It pings the
##   host, and when the host's header arrives it starts the live replay (`started`), unless the
##   frames service refuses it (another build, other content): then the link closes and
##   `problem` says why. (Which seats are this machine's is the host's lobby's to say, not the
##   header's: a run joined a while in seated it later.) From then on the frames service
##   calls the feed.
## - **Every physics step** (the feed): the ticks that arrived are added to the replay, each
##   checked by the replay's decoder, and each of this machine's seats' frames is sent (a FRAME
##   each, all for one host tick) for the host's tick `tick + delay`, `tick` being the next this
##   machine plays. The host gone, the feed is `closed` and the replay ends once played out.
## - **The input delay `delay`** (`D`, in ticks) is `NetDelay`'s: given, and then never moved,
##   or following the ping through the run. This tells it each ping answered and each frame
##   sent. A frame is never for an earlier host tick than the one before it (the host refuses
##   that): while the delay falls and this machine waits for ticks, its frames keep the last's.
## - **`after_tick`**, called after every tick has stepped, hashes the tick's part of the state
##   and sends each whole check to the host, which compares and says when one failed
##   (`NetSession`: `parted_tick`).
##
## - **Seats** (online lobby L2, docs/milestones/online-lobby.md): with an input layer given,
##   the host gives this machine's players their seats. `seat_devices` takes over the layer's
##   joining (`join_asker`): a device that would join is given the lowest of this machine's
##   player numbers and asked for (SEAT_ASK); the host's LOBBY says which seat each player
##   holds, and the device is seated there (`join_as`) as soon as the seat is free here (while
##   this machine still catches up, somebody who left since may sit on it). A seat is this
##   machine's (the feed's `local_seats`) while its device sits on it. A player who leaves (the
##   device's LEAVE, in its frame) is taken off by the host, whose next LOBBY frees the number.
##   With no input layer (Host and Join by code's tests, the measured grid) the seats it is made
##   with are its own, as the host's lobby then says too.
## - **The host's run begun anew** (a party back in its hub): a second header is the next
##   recording's. It and the ticks that follow are kept until this machine has played the one
##   before to its end (its game then asked for the same start, between the same two ticks);
##   then the next is played (`Frames.play_live` again) and the host is told (RUN), so what was
##   sent before is known to be of the recording before.
## - **Catching up** on a run joined a while in: while more than FAR ticks wait, each step runs
##   as many as fit the time a step has (`pace`), not the usual three.
##
## What the host sends is untrusted: only a host's kinds are taken (one header, the ticks in
## order), at most MAX_READ messages a step, and anything else closes the link.
##
##     var client := NetClient.new(Frames, link, Tick.state_areas)
##     ...  # each physics step until client.started: client.pump()
##     ...  # after every tick: client.after_tick()

## The most messages read in one physics step (a client that fell behind takes ten seconds of
## ticks a step).
const MAX_READ: int = 600
## A ping every this many physics steps.
const PING_EVERY: int = 30
## The input delay when none is given and no ping came back in time, and the most it is set to.
const DEFAULT_DELAY: int = NetDelay.DEFAULT
const MAX_DELAY: int = NetDelay.MOST
## A ping that takes longer is not counted.
const MAX_RTT_MS: int = 10000
## More ticks than this waiting: this machine catches up (it joined a run a while in).
const FAR: int = 120
## Catching up: the ticks a step starts with, the most it runs, and the time a step's ticks may
## take (microseconds) before fewer are run, or more.
const BURST_START: int = 8
const BURST_MOST: int = 480
const BURST_USEC: int = 9000
## The most recordings of the host's that wait to be played (it began its run anew while this
## machine was still behind).
const MAX_NEXTS: int = 4

const InputManagerScript := preload("res://core/input/input_manager.gd")
const _NO_DEVICE: int = InputManagerScript.NO_DEVICE


## The live replay's feed: the session itself, held weakly (the frames service holds the feed,
## the session holds the frames service).
class Feed:
	extends LiveFeed
	var client: WeakRef = null

	func pump() -> void:
		var session: NetClient = client.get_ref() as NetClient if client != null else null
		if session != null:
			session.pump()

	func send(tick: int, frame: InputFrame) -> void:
		var session: NetClient = client.get_ref() as NetClient if client != null else null
		if session != null:
			session.send_frame(tick, frame)

	func ticks_to_run(ahead: int) -> int:
		var run: int = super(ahead)
		var session: NetClient = client.get_ref() as NetClient if client != null else null
		if session != null:
			run = session.pace(ahead, run)
			session.stats.most_ahead = maxi(session.stats.most_ahead, ahead)
			session.stats.ticks_run += run
		return run


## One of this machine's players: a device the host is asked to seat.
class Player:
	extends RefCounted
	var device: int = 0
	## The seat the host gave (-1: none yet), and whether the device was seated on it here.
	var seat: int = -1
	var sat: bool = false
	## Which ask it was (0 to 255, then round again).
	var asked: int = 0


## The live replay's feed: its pacing (`cushion`), and `closed` once the host is gone.
var feed: Feed
## Catching up: the time a step's ticks may take, in microseconds (a test's own; BURST_USEC).
var burst_usec: int = BURST_USEC
## This machine's seats (a bit each): the ones it was made with, or those its devices sit on by
## the host's word.
var seats: int:
	get:
		return feed.local_seats
## The input layer whose devices the host seats (null: the one seat it was made with is its own).
var input: InputManagerScript = null
## The input delay in ticks; below 0 until it is worked out from the ping.
var delay: int:
	get:
		return _delay.ticks
## True once the host's header was taken and the live replay started.
var started: bool = false

## Physics steps pumped.
var _pumps: int = 0
## The replay's next tick when the last frame was sent (-1: none sent).
var _sent_at: int = -1
## The host's tick the last frame was sent for (they never go back).
var _last_for: int = 0
var _delay: NetDelay
## One probe a seat this machine has played (null for the others).
var _presses: Array[NetPressProbe] = [null, null, null, null]
## The physics step the frames' tick was last worked out in (once a step, for all its seats).
var _framed_at: int = -1
## This machine's players, by their number (0 to 3; null: no such player).
var _players: Array[Player] = [null, null, null, null]
## The asks sent (0 to 255, then round again).
var _asks: int = 0
## The host's recordings that follow the one played, in order (the run began anew): each is
## played once the one before is played out. And the headers taken.
var _nexts: Array[Replay] = []
var _headers: int = 0
## Catching up: the ticks a step runs now (0: not catching up), when its ticks began, and how
## many of them are still to step.
var _burst: int = 0
var _burst_began: int = 0
var _burst_left: int = 0
var _burst_took: int = 0


## `on_seats`: this machine's seats, a bit each (seat 0 is the host's: never one of them), when
## no input layer is given. `input_layer`: the layer whose devices the host seats (see the top);
## with it `on_seats` is not used.
func _init(frames_service: FramesScript, over: NetLink, state_areas: Callable = Callable(), on_seats: int = 1 << NetHost.SEAT, cushion: int = 2, input_delay: int = -1, input_layer: InputManagerScript = null) -> void:
	super(frames_service, over, state_areas)
	max_read = MAX_READ
	input = input_layer
	_delay = NetDelay.new(input_delay, cushion)
	feed = Feed.new(on_seats & 0x0e if input == null else 0, cushion)
	feed.client = weakref(self)


## Take over the seating of this machine's devices (see the top): every device that sits on a
## seat (a bot's virtual one too) leaves it and is asked for, as is every real one that joins
## from now on; with none, the keyboard is asked for (a menu may be worked with the mouse by nobody who has joined). Call it
## once the link is open, in a menu (nobody plays yet).
func seat_devices() -> void:
	if input == null or input.join_asker.is_valid():
		return
	var seated: Array[int] = []
	for player in InputManagerScript.MAX_PLAYERS:
		var device: int = input.device_of(player)
		if device != _NO_DEVICE:
			seated.append(device)
			input.leave(player)
	input.join_asker = ask
	if seated.is_empty():
		seated.append(InputManagerScript.KEYBOARD)
	for device in seated:
		ask(device)


## Give the seating back to the input layer: whoever holds the session calls it when the session
## is over (its run ended, the link was refused, it was given up). Its devices stay where they
## sit. With `rejoin` (no run came of it), those this session took off their seats, or asked
## for, join again as they would by themselves.
func release_devices(rejoin: bool = false) -> void:
	if input == null or input.join_asker != Callable(self, &"ask"):
		return
	input.join_asker = Callable()
	if not rejoin:
		return
	for player in _players:
		if player == null or input.player_of(player.device) != InputManagerScript.NO_PLAYER:
			continue
		if InputManagerScript.is_virtual(player.device):
			input.add_virtual_device(player.device - InputManagerScript.VIRTUAL_BASE)
		else:
			input.join(player.device)


## The device `device` wants to play: it becomes one of this machine's players and the host is
## asked for a seat. Nothing happens for one that asks or plays already, or with four players.
func ask(device: int) -> void:
	var free: int = -1
	for number in _players.size():
		if _players[number] == null:
			free = number if free < 0 else free
		elif _players[number].device == device:
			return
	if free < 0:
		return
	var player := Player.new()
	player.device = device
	_asks = (_asks + 1) & 0xff
	player.asked = _asks
	_players[free] = player
	# With the host gone the ask reaches nobody; the player is still this session's to give back.
	if problem == "" and link.is_open():
		_send(NetMessage.of_seat_ask(free))


## How many ticks this step, with `ahead` there and `usual` what the feed would run: `usual`,
## but while this machine is far behind (it joined a run a while in) as many as fit a step's
## time, found by doubling while the last step's ticks were done early and halving when late.
func pace(ahead: int, usual: int) -> int:
	if ahead <= FAR:
		_burst = 0
		return usual
	if _burst == 0:
		_burst = BURST_START
	elif _burst_left > 0:
		pass  # The last step's ticks did not all run (the game stood): as before.
	elif _burst_took < burst_usec:
		_burst = mini(_burst * 2, BURST_MOST)
	elif _burst_took > burst_usec * 2:
		_burst = maxi(_burst / 2, 1)
	var run: int = mini(_burst, ahead - feed.cushion)
	_burst_left = run
	_burst_began = Time.get_ticks_usec()
	return run


## True while this machine catches up on a run it joined a while in.
func is_catching_up() -> bool:
	return _burst > 0


## True while the host's run plays here.
func is_playing() -> bool:
	return started and frames.is_live()


func pump() -> bool:
	if problem == "" and link.is_open() and _pumps % PING_EVERY == 0:
		_send(NetMessage.of_ping(_now()))
	_pumps += 1
	var drained: bool = super()
	_play_next()
	_seat_players()
	# The host gone and everything it sent read: no more ticks will come.
	if drained and not link.is_open():
		feed.closed = true
	return drained


## A seat's frame of this physics step goes to the host (the feed calls it once a seat of this
## machine's, in a step), for the host's tick `tick + delay` (never an earlier one than the frames
## before); `tick` is the next this machine plays. The step's first works out the host's tick for
## all of them.
func send_frame(tick: int, frame: InputFrame) -> void:
	var seat: int = frame.seat
	if seat < 0 or seat >= Replay.SEATS or feed.local_seats & (1 << seat) == 0:
		return
	if _presses[seat] == null:
		_presses[seat] = NetPressProbe.new(stats, seat)
	# Once a step, whatever seats this machine holds: the step's counters, and the host's tick
	# its frames are for.
	var first: bool = _framed_at != _pumps
	if first:
		_framed_at = _pumps
		stats.steps += 1
		# The step before ran no tick when the next to play is still the same.
		if tick == _sent_at:
			stats.steps_waited += 1
		_sent_at = tick
	_presses[seat].played(replay, tick, _pumps)
	if problem != "" or not link.is_open():
		return
	var began: int = Time.get_ticks_usec()
	_presses[seat].sent(frame, _pumps)
	if first:
		_last_for = maxi(tick + _delay.step(), _last_for)
		_count_delay()
	_send(NetMessage.of_frame(_last_for, frame.to_bytes()))
	stats.net_usec += Time.get_ticks_usec() - began


func after_tick() -> void:
	if _burst_left > 0:
		_burst_left -= 1
		if _burst_left == 0:
			_burst_took = Time.get_ticks_usec() - _burst_began
	if not is_playing() or not areas.is_valid():
		return
	var tick: int = frames.play_tick() - 1
	var check: Dictionary[String, int] = _check(tick)
	if check.is_empty() or problem != "" or not link.is_open():
		return
	_send(NetMessage.of_hashes(tick, check))
	stats.checks += 1


func _take(message: NetMessage) -> String:
	match message.kind:
		NetMessage.HEADER:
			return _take_header(message)
		NetMessage.TICK:
			if replay == null:
				return "a tick before the header"
			# Of the newest recording there is: the one played, or the last that follows it.
			var into: Replay = replay if _nexts.is_empty() else _nexts.back()
			if message.tick != into.tick_count():
				return "tick %d, not %d" % [message.tick, into.tick_count()]
			return into.add_tick_bytes(message.body)
		NetMessage.PONG:
			var took: int = (_now() - message.stamp) & 0xffffffff
			if took <= MAX_RTT_MS:
				stats.add_rtt(float(took))
				_delay.add_rtt(float(took))
				if started:
					_delay.retune()
				_count_delay()
			return ""
		NetMessage.PARTED:
			_part(message.tick, message.names)
			return ""
		NetMessage.LOBBY:
			_take_lobby(message)
			return ""
	return "kind %d is not a host's to send" % message.kind


func _take_header(message: NetMessage) -> String:
	var run := Replay.new()
	var why: String = run.decode(message.body)
	if why != "":
		return "the header: " + why
	if run.tick_count() != 0:
		return "a header with ticks"
	if replay != null:
		# The host's run began anew: played once the one before is played out.
		if _nexts.size() >= MAX_NEXTS:
			return "%d recordings waiting" % _nexts.size()
		_nexts.append(run)
		return ""
	_delay.start()
	_count_delay()
	feed.replay = run
	# The frames service refuses a run of another build or other content.
	if not frames.play_live(feed):
		feed.replay = null
		return "the host's run is not this game's (its build is %s)" % run.build
	replay = run
	started = true
	_headers = 1
	return ""


## The recording played is played out and the host's next one is here: it is played from its
## first tick, and the host told. (This machine's game asked for that start itself, at the last
## tick of the one before, and has waited since.)
func _play_next() -> void:
	if _nexts.is_empty() or not started or problem != "" or not frames.is_live() or frames.play_tick() < replay.tick_count():
		return
	var run: Replay = _nexts.pop_front()
	feed.replay = run
	if not frames.play_live(feed):
		feed.replay = replay
		_refuse("the host's next run is not this game's (its build is %s)" % run.build)
		return
	replay = run
	_headers += 1
	checks = NetChecks.new(checks.every)
	# The ticks are counted anew: the frames' tags and the presses timed start over.
	_last_for = 0
	_sent_at = -1
	for seat in Replay.SEATS:
		_presses[seat] = null
	_send(NetMessage.of_run(_headers))


## The host's word on the seats: which of this machine's players holds which. A player with a
## seat keeps its number; one whose ask was answered with none, or whose seat was taken back,
## is no player any more (its device may ask again).
func _take_lobby(message: NetMessage) -> void:
	if input == null:
		# The seats it was made with: the host's word on them is all there is to take.
		feed.local_seats = 0
		for at in Replay.SEATS:
			if message.holders[at] != NetMessage.NOBODY:
				feed.local_seats |= 1 << at
		return
	for number in _players.size():
		var player: Player = _players[number]
		if player == null:
			continue
		var given: int = message.holders.find(number)
		if given >= 0 and (player.seat < 0 or player.seat == given):
			player.seat = given
		elif player.seat >= 0 or ((message.answered - player.asked) & 0xff) < 128:
			# Its seat was taken back (or moved, which the host never does), or its ask was
			# answered with none.
			_let_go(number)
	_seat_players()


## This machine's player `number` is none any more: its seat is not this machine's, and its
## device, if it still sits there, leaves.
func _let_go(number: int) -> void:
	var player: Player = _players[number]
	_players[number] = null
	if player == null or not player.sat:
		return
	feed.local_seats &= ~(1 << player.seat)
	if input.device_of(player.seat) == player.device:
		input.leave(player.seat)


## Each player the host gave a seat is seated on it, once the seat is free here; a seat is this
## machine's while its device sits on it.
func _seat_players() -> void:
	if input == null:
		return
	for player in _players:
		# Seated once, the seat stays this machine's until the host takes it back: a player's
		# leave is built into a frame while it still is.
		if player == null or player.seat < 0 or player.sat:
			continue
		# The seat is this machine's before its device joins: the join is heard and sent. While
		# somebody still sits on it here the join is refused, and tried again the next step.
		var bit: int = 1 << player.seat
		feed.local_seats |= bit
		var joined: bool
		if InputManagerScript.is_virtual(player.device):
			# A bot's: its virtual device is the seat's own.
			joined = input.add_virtual_device(player.seat) != _NO_DEVICE
			if joined:
				player.device = InputManagerScript.virtual_device_id(player.seat)
		else:
			joined = input.join_as(player.device, player.seat) != InputManagerScript.NO_PLAYER
		if not joined:
			feed.local_seats &= ~bit
			continue
		player.sat = true


## The delay's numbers into the counters.
func _count_delay() -> void:
	stats.delay = _delay.ticks
	stats.retunes = _delay.retunes
	stats.rtt_mid_ms = _delay.rtt_ms()


func _refuse(why: String) -> void:
	super(why)
	feed.closed = true


func _now() -> int:
	return int(_now_ms()) & 0xffffffff
