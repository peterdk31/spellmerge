extends RefCounted
## Two machines in one process (netcode spike S2, docs/milestones/netcode-spike.md): two scripted
## fights of the same content (tests/core/content_fight.gd, each a world with its own frames
## service and input layer), one the host's and one the client's, their sessions (`NetHost`,
## `NetClient`) linked by a loopback with a conditioner at each end, on a clock of physics steps.
## The session tests and the grid's benchmark both run on it.
##
## The host's seat 0 and the client's seat 1 are scripted players (they read nothing of the game);
## on the host seat 1 is the session's, on the client seat 0 is the replay's. Each machine's state
## is captured after every tick it runs (`host_run`, `client_run`: by tick), so the two are
## compared tick for tick whatever the link did.
##
##     var pair := NetPair.new(root, ContentFight.CARD, card, 100.0)   # a 100 ms round trip
##     pair.start()
##     pair.run(600)
##     Desync.first_parting(pair.host_run, pair.client_run)   # -1, up to the client's last tick
##     pair.free_all()

const ContentFight := preload("res://tests/core/content_fight.gd")

const STEP_MS: float = 1000.0 / 60.0
## The steps both sessions are pumped before the run starts (the client measures its ping).
const WARM_UP: int = 70

var host_fight: ContentFight
var client_fight: ContentFight
var host: NetHost
var client: NetClient
## Each machine's end of the link, with its conditioner.
var host_link: NetConditioner
var client_link: NetConditioner
## Physics steps since the pair was made: the link's clock.
var steps: int = 0
## Each machine's state after every tick it ran, by tick. Off (`captures`): nothing is captured
## (the benchmark times the sessions, not the capture).
var host_run: Desync = Desync.new()
var client_run: Desync = Desync.new()
var captures: bool = true
## The ticks the client ran in each of its steps since the start.
var client_ran: PackedInt32Array = PackedInt32Array()
var _client_played: int = 0


## Two fights of `resource` (a card's or an enemy's, as `kind` says) under `root`, linked with a
## round trip of `rtt_ms` (half each way), `jitter_ms` more each way at most, and a chance `loss`
## each way. `delay` is the client's input delay in ticks (below 0: from its ping).
## `over`: the host's and the client's ends of a link made elsewhere (a real one: WebRTC's), instead
## of a loopback's.
func _init(root: Node, kind: StringName, resource: Resource, rtt_ms: float = 0.0, jitter_ms: float = 0.0, loss: float = 0.0, delay: int = -1, link_seed: int = 1, over: Array[NetLink] = []) -> void:
	host_fight = ContentFight.new(root, kind, resource)
	client_fight = ContentFight.new(root, kind, resource)
	var ends: Array[NetLink] = over
	if ends.is_empty():
		ends.assign(NetLoopback.pair())
	host_link = _conditioned(ends[0], rtt_ms, jitter_ms, loss, link_seed)
	client_link = _conditioned(ends[1], rtt_ms, jitter_ms, loss, link_seed + 1000)
	# The host's own seat is a device of its machine, so its frames are recorded.
	host_fight.input.add_virtual_device(0)
	host = NetHost.new(host_fight.frames, host_fight.input, host_link, host_fight.areas)
	# The client's own device, joined as its seat; seat 0 is the replay's there.
	client_fight.input.add_virtual_device(NetHost.SEAT)
	client_fight.frames.set_source(0, null)
	client = NetClient.new(client_fight.frames, client_link, client_fight.areas, NetHost.SEAT, 2, delay)
	client.clock = now_ms


func _conditioned(end: NetLink, rtt_ms: float, jitter_ms: float, loss: float, link_seed: int) -> NetConditioner:
	var link := NetConditioner.new(end, now_ms, link_seed)
	link.delay_ms = rtt_ms * 0.5
	link.jitter_ms = jitter_ms
	link.loss = loss
	return link


## The link's clock: the steps, in milliseconds.
func now_ms() -> float:
	return steps * STEP_MS


## Both sessions pumped for a while (the pings), then the host starts its run. False when it
## could not.
func start(run_seed: int = 0x5e55) -> bool:
	for i in WARM_UP:
		steps += 1
		host.pump()
		client.pump()
	return host.start(&"sandbox_requested", 0, run_seed) != null


## One physics step of both machines (or one of them: a machine that stalls), the host first.
func step(host_steps: bool = true, client_steps: bool = true) -> void:
	steps += 1
	# The link is the network's, not a machine's: what is due moves on while a machine stalls.
	host_link.is_open()
	client_link.is_open()
	if host_steps:
		host_fight.physics_step(_after_host_tick)
	if client_steps:
		# Until the host's header arrives the client's game has not begun (in the game: the menu).
		if not client.started:
			client.pump()
		client_ran.append(client_fight.physics_step(_after_client_tick) if client.started else 0)


func run(count: int) -> void:
	for i in count:
		step()


## Steps until the client has played every tick the host made, at most `most` steps (the host
## stands meanwhile). True when it has.
func let_client_catch_up(most: int = 600) -> bool:
	for i in most:
		if client_ticks() >= host_ticks():
			return true
		step(false, true)
	return client_ticks() >= host_ticks()


func host_ticks() -> int:
	return host.replay.tick_count() if host.replay != null else 0


## The ticks of the host's run the client has played (its fight ticks on by itself once the run
## has ended, as the game would; those are not counted or captured).
func client_ticks() -> int:
	return _client_played


func _after_host_tick() -> void:
	host.after_tick()
	if captures:
		host_run.capture(host_fight.areas())


func _after_client_tick() -> void:
	if not client.is_playing():
		return
	_client_played += 1
	client.after_tick()
	if captures:
		client_run.capture(client_fight.areas())


## The first tick both machines ran at which they differ, or -1 (the client may have run fewer).
func first_parting() -> int:
	for tick in mini(host_run.hashes.size(), client_run.hashes.size()):
		if host_run.hashes[tick] != client_run.hashes[tick]:
			return tick
	return -1


func free_all() -> void:
	host.stop()
	client_fight.frames.stop_playing()
	host_fight.free_all()
	client_fight.free_all()
