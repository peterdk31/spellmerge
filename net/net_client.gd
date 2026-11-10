class_name NetClient
extends NetSession
## The client's side of an online run (netcode spike S2, docs/milestones/netcode-spike.md): it
## plays the host's run as a live replay (`Frames.play_live`, fed by its `feed`) and sends its
## own seat's frames to the host.
##
## - **Before the run:** whoever holds the session calls `pump` each physics step. It pings the
##   host, and when the host's header arrives it starts the live replay (`started`), unless the
##   header seats this machine nowhere or the frames service refuses it (another build, other
##   content): then the link closes and `problem` says why. From then on the frames service
##   calls the feed.
## - **Every physics step** (the feed): the ticks that arrived are added to the replay, each
##   checked by the replay's decoder, and the seat's frame is sent for the host's tick
##   `tick + delay`, `tick` being the next this machine plays. The host gone, the feed is
##   `closed` and the replay ends once played out.
## - **The input delay `delay`** (`D`, in ticks): given, or when the header arrives worked out
##   from the ping measured until then: the round trip in ticks, the cushion, and one.
## - **`after_tick`**, called after every tick has stepped, hashes the tick's part of the state
##   and sends each whole check to the host, which compares and says when one failed
##   (`NetSession`: `parted_tick`).
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
const DEFAULT_DELAY: int = 6
const MAX_DELAY: int = 60
## A ping that takes longer is not counted.
const MAX_RTT_MS: int = 10000


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
			session.stats.most_ahead = maxi(session.stats.most_ahead, ahead)
			session.stats.ticks_run += run
		return run


## The live replay's feed: its pacing (`cushion`), and `closed` once the host is gone.
var feed: Feed
## The time in milliseconds, for the pings (a test's own; the engine's clock otherwise).
var clock: Callable = Callable()
## This machine's seat.
var seat: int = 1
## The input delay in ticks; below 0 until it is worked out from the ping.
var delay: int = -1
## True once the host's header was taken and the live replay started.
var started: bool = false

## Physics steps pumped.
var _pumps: int = 0
## The replay's next tick when the last frame was sent (-1: none sent).
var _sent_at: int = -1
var _presses: NetPressProbe


func _init(frames_service: FramesScript, over: NetLink, state_areas: Callable = Callable(), on_seat: int = NetHost.SEAT, cushion: int = 2, input_delay: int = -1) -> void:
	super(frames_service, over, state_areas)
	max_read = MAX_READ
	seat = on_seat
	delay = mini(input_delay, MAX_DELAY)
	feed = Feed.new(1 << on_seat, cushion)
	feed.client = weakref(self)
	_presses = NetPressProbe.new(stats, on_seat)


## True while the host's run plays here.
func is_playing() -> bool:
	return started and frames.is_live()


func pump() -> bool:
	if problem == "" and link.is_open() and _pumps % PING_EVERY == 0:
		_send(NetMessage.of_ping(_now()))
	_pumps += 1
	var drained: bool = super()
	# The host gone and everything it sent read: no more ticks will come.
	if drained and not link.is_open():
		feed.closed = true
	return drained


## The seat's frame of this physics step goes to the host (the feed), for the host's tick
## `tick + delay`; `tick` is the next this machine plays.
func send_frame(tick: int, frame: InputFrame) -> void:
	stats.steps += 1
	# The step before ran no tick when the next to play is still the same.
	if tick == _sent_at:
		stats.steps_waited += 1
	_sent_at = tick
	_presses.played(replay, tick, _pumps)
	if problem != "" or not link.is_open():
		return
	var began: int = Time.get_ticks_usec()
	_presses.sent(frame, _pumps)
	_send(NetMessage.of_frame(tick + delay, frame.to_bytes()))
	stats.net_usec += Time.get_ticks_usec() - began


func after_tick() -> void:
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
			if message.tick != replay.tick_count():
				return "tick %d, not %d" % [message.tick, replay.tick_count()]
			return replay.add_tick_bytes(message.body)
		NetMessage.PONG:
			var took: int = (_now() - message.stamp) & 0xffffffff
			if took <= MAX_RTT_MS:
				stats.add_rtt(float(took))
			return ""
		NetMessage.PARTED:
			_part(message.tick, message.names)
			return ""
	return "kind %d is not a host's to send" % message.kind


func _take_header(message: NetMessage) -> String:
	if replay != null:
		return "a second header"
	var run := Replay.new()
	var why: String = run.decode(message.body)
	if why != "":
		return "the header: " + why
	if run.tick_count() != 0:
		return "a header with ticks"
	if run.seats & feed.local_seats == 0:
		return "the host seated nobody on seat %d" % seat
	if delay < 0:
		delay = DEFAULT_DELAY
		if stats.pings > 0:
			delay = clampi(ceili(stats.rtt_smooth_ms / NetStats.TICK_MS) + feed.cushion + 1, 1, MAX_DELAY)
	stats.delay = delay
	feed.replay = run
	# The frames service refuses a run of another build or other content.
	if not frames.play_live(feed):
		feed.replay = null
		return "the host's run is not this game's (its build is %s)" % run.build
	replay = run
	started = true
	return ""


func _refuse(why: String) -> void:
	super(why)
	feed.closed = true


func _now() -> int:
	var ms: float = float(clock.call()) if clock.is_valid() else float(Time.get_ticks_msec())
	return int(ms) & 0xffffffff
