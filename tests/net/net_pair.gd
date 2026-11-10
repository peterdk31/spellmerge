extends RefCounted
## Machines in one process (netcode spike S2; online lobby L3, docs/milestones/online-lobby.md): a
## host and one to three guest machines, each a scripted fight of the same content
## (tests/core/content_fight.gd, each a world with its own frames service and input layer), their
## sessions (`NetHost`, a `NetClient` each) linked by loopbacks with a conditioner at each end, on
## a clock of physics steps. The session tests and the grid's benchmark run on it.
##
## Every seat is a scripted player (they read nothing of the game). A guest's seats are its own
## (`guest_seats`, a bit each: one guest on seat 1 unless told); the host plays the rest. On the
## host a guest's seats are the session's; on a guest every other machine's seat is the replay's.
## Each machine's state is captured after every tick it runs (`host_run`, `client_runs`: by tick),
## so they are compared tick for tick whatever the links did.
##
##     var pair := NetPair.new(root, ContentFight.CARD, card, 100.0)   # a 100 ms round trip
##     pair.start()
##     pair.run(600)
##     pair.first_parting()   # -1, up to each guest's last tick
##     pair.free_all()
##
## `client`, `client_fight`, `client_link` and `client_run` are the first guest's.

const ContentFight := preload("res://tests/core/content_fight.gd")

const STEP_MS: float = 1000.0 / 60.0
## The steps the sessions are pumped before the run starts (the guests measure their ping).
const WARM_UP: int = 70

var host_fight: ContentFight
var host: NetHost
## Each guest machine: its fight, its session, its end of the link (with its conditioner), the
## host's end of it, its state by tick, the ticks of the host's run it played, and the ticks it
## ran in each step.
var client_fights: Array[ContentFight] = []
var clients: Array[NetClient] = []
var client_links: Array[NetConditioner] = []
var host_links: Array[NetConditioner] = []
var client_runs: Array[Desync] = []
var client_played: PackedInt32Array = PackedInt32Array()
var client_ran: Array[PackedInt32Array] = []
## The first guest's (the spike's pair).
var client_fight: ContentFight:
	get:
		return client_fights[0]
var client: NetClient:
	get:
		return clients[0]
var client_link: NetConditioner:
	get:
		return client_links[0]
var host_link: NetConditioner:
	get:
		return host_links[0]
var client_run: Desync:
	get:
		return client_runs[0]
## Physics steps since the pair was made: the links' clock.
var steps: int = 0
## The host's state after every tick it ran, by tick. Off (`captures`): nothing is captured (the
## benchmark times the sessions, not the capture).
var host_run: Desync = Desync.new()
var captures: bool = true


## Fights of `resource` (a card's or an enemy's, as `kind` says) under `root`, a guest machine for
## each of `guest_seats` (its seats, a bit each), each linked with a round trip of `rtt_ms` (half
## each way), `jitter_ms` more each way at most, and a chance `loss` each way. `delay` is the
## guests' input delay in ticks (below 0: from their ping). `over`: the host's and the one guest's
## ends of a link made elsewhere (a real one: WebRTC's), instead of a loopback's.
func _init(root: Node, kind: StringName, resource: Resource, rtt_ms: float = 0.0, jitter_ms: float = 0.0, loss: float = 0.0, delay: int = -1, link_seed: int = 1, over: Array[NetLink] = [], guest_seats: Array[int] = []) -> void:
	var seats_of: Array[int] = guest_seats.duplicate()
	if seats_of.is_empty():
		seats_of.append(1 << NetHost.SEAT)
	var taken: int = 0
	for seats in seats_of:
		taken |= seats
	# A wizard for every seat up to the highest a guest plays (two at least).
	var wizards: int = 2
	for seat in Replay.SEATS:
		if taken & (1 << seat) != 0:
			wizards = maxi(wizards, seat + 1)
	host_fight = ContentFight.new(root, kind, resource, wizards)
	host = NetHost.new(host_fight.frames, host_fight.input, host_fight.areas)
	# The host's own seats are devices of its machine, so their frames are recorded.
	for seat in wizards:
		if taken & (1 << seat) == 0:
			host_fight.input.add_virtual_device(seat)
	for i in seats_of.size():
		var ends: Array[NetLink] = []
		ends.assign(over if i == 0 and not over.is_empty() else NetLoopback.pair())
		var near: NetConditioner = _conditioned(ends[0], rtt_ms, jitter_ms, loss, link_seed + i * 7)
		var far: NetConditioner = _conditioned(ends[1], rtt_ms, jitter_ms, loss, link_seed + i * 7 + 1000)
		var fight := ContentFight.new(root, kind, resource, wizards)
		# The guest's own devices, joined as its seats; the others are the replay's there.
		for seat in wizards:
			if seats_of[i] & (1 << seat) != 0:
				fight.input.add_virtual_device(seat)
			else:
				fight.frames.set_source(seat, null)
		var session := NetClient.new(fight.frames, far, fight.areas, seats_of[i], 2, delay)
		session.clock = now_ms
		host.add_guest(near, seats_of[i])
		host_links.append(near)
		client_links.append(far)
		client_fights.append(fight)
		clients.append(session)
		client_runs.append(Desync.new())
		client_played.append(0)
		client_ran.append(PackedInt32Array())


func _conditioned(end: NetLink, rtt_ms: float, jitter_ms: float, loss: float, link_seed: int) -> NetConditioner:
	var link := NetConditioner.new(end, now_ms, link_seed)
	link.delay_ms = rtt_ms * 0.5
	link.jitter_ms = jitter_ms
	link.loss = loss
	return link


## The links' clock: the steps, in milliseconds.
func now_ms() -> float:
	return steps * STEP_MS


## The sessions pumped for a while (the pings), then the host starts its run. False when it could
## not.
func start(run_seed: int = 0x5e55) -> bool:
	for i in WARM_UP:
		steps += 1
		host.pump()
		for session in clients:
			session.pump()
	return host.start(&"sandbox_requested", 0, run_seed) != null


## One physics step of every machine (or some of them: a machine that stalls), the host first.
## `guests`: which guests step (a bit each, by their order), when `client_steps`.
func step(host_steps: bool = true, client_steps: bool = true, guests: int = 0x0f) -> void:
	steps += 1
	# The links are the network's, not a machine's: what is due moves on while a machine stalls.
	for i in clients.size():
		host_links[i].is_open()
		client_links[i].is_open()
	if host_steps:
		host_fight.physics_step(_after_host_tick)
	if not client_steps:
		return
	for i in clients.size():
		if guests & (1 << i) == 0:
			continue
		# Until the host's header arrives the guest's game has not begun (in the game: the menu).
		if not clients[i].started:
			clients[i].pump()
		client_ran[i].append(client_fights[i].physics_step(_after_client_tick.bind(i)) if clients[i].started else 0)


func run(count: int) -> void:
	for i in count:
		step()


## Steps until every guest has played every tick the host made, at most `most` steps (the host
## stands meanwhile). True when they have.
func let_client_catch_up(most: int = 600) -> bool:
	for i in most:
		if _caught_up():
			return true
		step(false, true)
	return _caught_up()


func _caught_up() -> bool:
	for i in clients.size():
		if client_played[i] < host_ticks():
			return false
	return true


func host_ticks() -> int:
	return host.replay.tick_count() if host.replay != null else 0


## The ticks of the host's run the first guest has played (its fight ticks on by itself once the
## run has ended, as the game would; those are not counted or captured).
func client_ticks() -> int:
	return client_played[0]


func _after_host_tick() -> void:
	host.after_tick()
	if captures:
		host_run.capture(host_fight.areas())


func _after_client_tick(i: int) -> void:
	if not clients[i].is_playing():
		return
	client_played[i] += 1
	clients[i].after_tick()
	if captures:
		client_runs[i].capture(client_fights[i].areas())


## The first tick the host and any guest both ran at which they differ, or -1 (a guest may have
## run fewer).
func first_parting() -> int:
	var first: int = -1
	for i in clients.size():
		var at: int = parting_of(i)
		if at >= 0 and (first < 0 or at < first):
			first = at
	return first


## The first tick the host and guest `i` both ran at which they differ, or -1.
func parting_of(i: int) -> int:
	var theirs: Desync = client_runs[i]
	for tick in mini(host_run.hashes.size(), theirs.hashes.size()):
		if host_run.hashes[tick] != theirs.hashes[tick]:
			return tick
	return -1


func free_all() -> void:
	host.stop()
	for fight in client_fights:
		fight.frames.stop_playing()
	host_fight.free_all()
	for fight in client_fights:
		fight.free_all()
