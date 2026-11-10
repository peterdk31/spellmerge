extends "res://tests/support/suite.gd"
## Two machines over the loopback (netcode spike S2, docs/milestones/netcode-spike.md): two
## scripted fights linked by the sessions on a stepped clock (tests/net/net_pair.gd). The client
## agrees with the host at every tick at round trips of 0 to 200 ms with jitter and loss; the host
## runs every tick on time whatever the link or the client does; a client that stalled catches
## up; a world that is disturbed is caught by the next checks, with its areas; and the replay the
## client received, played offline, is the host's run.
##
## The runner plays it in processes side by side (tests/support/suite.gd, "shards"):
# unit-test-shards: 4

const NetPair := preload("res://tests/net/net_pair.gd")
const ContentFight := preload("res://tests/core/content_fight.gd")
const RegistryScript := preload("res://core/registry/registry.gd")

## Ticks the host runs in a test (six seconds, so six checks).
const TICKS: int = 360
## The card the fights play: a plain shot, cast by both wizards and an enemy.
const CARD: StringName = &"bolt"

var _registry: RegistryScript
var _pair: NetPair


func before_each() -> void:
	_registry = own(RegistryScript.new()) as RegistryScript
	_registry.scan()
	_pair = null


func after_each() -> void:
	if _pair != null:
		_pair.free_all()


func _card() -> SpellComponent:
	for card: Resource in _registry.get_all(&"spells"):
		if card is SpellComponent and (card as SpellComponent).id == CARD:
			return card as SpellComponent
	check(false, "the card %s is there" % CARD)
	return null


func _new_pair(rtt_ms: float = 0.0, jitter_ms: float = 0.0, loss: float = 0.0, delay: int = -1) -> NetPair:
	_pair = NetPair.new(root, ContentFight.CARD, _card(), rtt_ms, jitter_ms, loss, delay)
	return _pair


## A run of TICKS over a link of `rtt_ms`, `jitter_ms` and `loss`: the host on time, the client
## the same at every tick, every check passed.
func _plays_the_same(rtt_ms: float, jitter_ms: float, loss: float) -> void:
	var pair: NetPair = _new_pair(rtt_ms, jitter_ms, loss)
	var label: String = "%d ms, jitter %d, loss %d%%" % [rtt_ms, jitter_ms, roundi(loss * 100.0)]
	check(pair.start(), "%s: the host starts" % label)
	for i in TICKS:
		pair.step()
		check_equal(pair.host_ticks(), i + 1, "%s: the host runs a tick every step (step %d)" % [label, i])
		if pair.host_ticks() != i + 1:
			return
	check(pair.client.started and pair.client.problem == "" and pair.host.guests[0].problem == "", "%s: linked (%s%s)" % [label, pair.client.problem, pair.host.guests[0].problem])
	check(pair.let_client_catch_up(), "%s: the client plays every tick (%d of %d)" % [label, pair.client_ticks(), pair.host_ticks()])
	check_equal(pair.client_run.hashes.size(), TICKS, "%s: every tick captured" % label)
	check_equal(pair.first_parting(), -1, "%s: the client agrees with the host at every tick" % label)
	for problem in pair.host_run.problems:
		check(false, "%s: %s" % [label, problem])
	# The checks: one a second, the last may still be on its way.
	pair.step(true, false)
	check(pair.host.guests[0].stats.checks >= TICKS / NetChecks.EVERY - 1, "%s: the host compared the client's checks (%d)" % [label, pair.host.guests[0].stats.checks])
	check_equal([pair.host.guests[0].stats.mismatches, pair.host.parted_tick, pair.client.parted_tick], [0, -1, -1], "%s: none differed" % label)
	check(pair.host_fight.wizard_casts > 0 and pair.client_fight.wizard_casts == pair.host_fight.wizard_casts, "%s: the fights fought (%d casts)" % [label, pair.host_fight.wizard_casts])
	# The client's seat is played on the host: its presses came back in the host's ticks.
	check(pair.client.stats.presses > 0, "%s: the client's presses came back (%d)" % [label, pair.client.stats.presses])
	var least_ms: float = rtt_ms
	check(pair.client.stats.press_ms() >= least_ms, "%s: a press takes at least the round trip (%.0f ms)" % [label, pair.client.stats.press_ms()])
	# Its input reaches the host's game: every press it sent is in the host's recording, but the
	# last few still on their way (a press sent twice before it came back counts once).
	var recorded: int = _presses_recorded(pair.host.replay, NetHost.SEAT)
	check(recorded >= pair.client.stats.presses_sent - 2 and recorded > 0, "%s: the client's presses are in the host's recording (%d of %d sent)" % [label, recorded, pair.client.stats.presses_sent])
	for ran in pair.client_ran[0]:
		check(ran <= LiveFeed.CATCH_UP, "%s: never more than three ticks a step" % label)
	if loss == 0.0 and jitter_ms == 0.0:
		check_equal(pair.host.guests[0].stats.stood_in, 0, "%s: on a steady link with the delay from its ping, no frame is late" % label)


## The ticks of `replay` in which `seat` pressed a staff.
func _presses_recorded(replay: Replay, seat: int) -> int:
	var frames: Array[InputFrame] = []
	for i in 4:
		frames.append(InputFrame.new())
	var count: int = 0
	for tick in replay.tick_count():
		replay.read_tick(tick, frames)
		if frames[seat].pressed_bits != 0:
			count += 1
	return count


## A command of the client's seat (its builder's) goes to the host in its frame, applies there at
## a tick, and comes back to apply here at the same tick: once on each machine.
func test_a_clients_command_applies_once_on_both_machines_at_the_same_tick() -> void:
	var pair: NetPair = _new_pair(100.0)
	check(pair.start(), "the host starts")
	var heard: Array = []
	var on_host := func(seat: int, staff: int, slot: int, card: StringName) -> void: heard.append(["host", pair.host_ticks() - 1, seat, staff, slot, card])
	var on_client := func(seat: int, staff: int, slot: int, card: StringName) -> void: heard.append(["client", pair.client_ticks(), seat, staff, slot, card])
	# Heard as the simulation hears a command: when its frame's tick starts (`Events.listen`).
	pair.host_fight.fight.bus.call(&"listen", &"staff_change_requested", on_host)
	pair.client_fight.fight.bus.call(&"listen", &"staff_change_requested", on_client)
	pair.run(60)
	heard.clear()
	pair.client_fight.fight.bus.emit_signal(&"staff_change_requested", NetHost.SEAT, 2, 0, CARD)
	check(heard.is_empty(), "nothing applies when it is asked: it goes out in the seat's frame")
	pair.run(60)
	check(pair.let_client_catch_up(), "the client plays every tick")
	check_equal(heard.size(), 2, "it applied once on each machine: %s" % str(heard))
	if heard.size() == 2:
		check_equal([heard[0][0], heard[1][0]], ["host", "client"], "on the host first")
		check_equal(heard[0].slice(1), heard[1].slice(1), "at the same tick, as the client's seat's")
	check_equal(pair.first_parting(), -1, "and the machines agree at every tick")


func test_the_client_agrees_at_every_tick_on_a_perfect_link() -> void:
	_plays_the_same(0.0, 0.0, 0.0)
	check(_pair.client.delay >= 3 and _pair.client.delay <= 5, "the delay of a ping of a step or two: the cushion, one and those (%d)" % _pair.client.delay)


func test_the_client_agrees_at_every_tick_at_50_ms() -> void:
	_plays_the_same(50.0, 0.0, 0.0)


func test_the_client_agrees_at_every_tick_at_100_ms_with_jitter() -> void:
	_plays_the_same(100.0, 20.0, 0.0)


func test_the_client_agrees_at_every_tick_at_150_ms_with_jitter_and_loss() -> void:
	_plays_the_same(150.0, 20.0, 0.05)


func test_the_client_agrees_at_every_tick_at_200_ms_with_jitter_and_loss() -> void:
	_plays_the_same(200.0, 30.0, 0.05)
	check(_pair.host.guests[0].stats.stood_in > 0, "a lossy link makes frames late: the last stood in (%d ticks)" % _pair.host.guests[0].stats.stood_in)
	check(_pair.client.stats.steps_waited > 0, "and the client waited for ticks (%d steps)" % _pair.client.stats.steps_waited)


## The delay given is the delay used, and a delay too short for the link makes every frame late
## while the game still agrees: lateness costs the client's feel, never the run.
func test_a_delay_too_short_makes_frames_late_and_nothing_else() -> void:
	var pair: NetPair = _new_pair(100.0, 0.0, 0.0, 1)
	check(pair.start(), "the host starts")
	pair.run(200)
	check_equal(pair.client.delay, 1, "the delay given")
	check(pair.host.guests[0].stats.late_frames > 150, "nearly every frame arrives after its tick (%d)" % pair.host.guests[0].stats.late_frames)
	check_equal(pair.host_ticks(), 200, "the host ran every tick")
	check(pair.let_client_catch_up(), "the client plays them all")
	check_equal(pair.first_parting(), -1, "and agrees at every tick")


## The client's delay follows its ping in the run (S5): the link gets fast, then slow, and the
## real host takes every frame (it closes the link on one for an earlier tick than the one
## before) while the machines agree.
func test_the_delay_follows_a_link_that_changes_in_the_run() -> void:
	var pair: NetPair = _new_pair(200.0, 30.0)
	check(pair.start(), "the host starts")
	pair.run(120)
	var slow: int = pair.client.delay
	check(slow >= 12 + 2 + 1, "the delay of 200 ms (%d)" % slow)
	for link: NetConditioner in [pair.host_link, pair.client_link]:
		link.delay_ms = 10.0
	pair.run(900)
	var fast: int = pair.client.delay
	check(fast <= 8 and pair.client.stats.retunes > 0, "the link fast: the delay falls (%d to %d)" % [slow, fast])
	for link: NetConditioner in [pair.host_link, pair.client_link]:
		link.delay_ms = 150.0
	pair.run(300)
	check(pair.client.delay >= 18 + 2 + 1, "the link slow: the delay rises (%d to %d)" % [fast, pair.client.delay])
	# Until it rose (three slow pings) its frames were late; since, they are on time.
	var stood: int = pair.host.guests[0].stats.stood_in
	pair.run(300)
	check_equal([pair.host.guests[0].problem, pair.client.problem], ["", ""], "the host took every frame")
	check(pair.host.guests[0].stats.stood_in - stood <= 3, "and once the delay rose its frames are on time again (%d ticks stood in)" % (pair.host.guests[0].stats.stood_in - stood))
	check_equal(pair.host_ticks(), 120 + 900 + 600, "the host ran every tick")
	check(pair.let_client_catch_up(), "the client plays them all")
	check_equal(pair.first_parting(), -1, "and agrees at every tick")
	check_equal([pair.host.guests[0].stats.mismatches, pair.host.parted_tick], [0, -1], "every check passed")


func test_the_host_is_on_time_while_the_client_stalls_and_the_client_catches_up() -> void:
	var pair: NetPair = _new_pair(50.0)
	check(pair.start(), "the host starts")
	pair.run(60)
	var behind_before: int = pair.host_ticks() - pair.client_ticks()
	# The client's machine stalls for two seconds (a hidden tab).
	for i in 120:
		pair.step(true, false)
	check_equal(pair.host_ticks(), 180, "the host ran every tick meanwhile")
	check(pair.host.guests[0].stats.stood_in >= 100, "the client's last frame stood in (%d ticks)" % pair.host.guests[0].stats.stood_in)
	check(pair.host_ticks() - pair.client_ticks() >= 120, "the client is two seconds behind")
	var steps_needed: int = 0
	while pair.host_ticks() - pair.client_ticks() > behind_before + pair.client.feed.cushion and steps_needed < 400:
		pair.step()
		steps_needed += 1
	check(steps_needed >= 40 and steps_needed <= 70, "it catches up at three ticks a step, the host running on (%d steps)" % steps_needed)
	pair.run(30)
	check(pair.let_client_catch_up(), "the client plays every tick")
	check_equal(pair.first_parting(), -1, "and agrees at every tick, the stall's too")
	check_equal(pair.host.guests[0].stats.mismatches, 0, "no check differed")


func test_the_host_plays_on_when_the_link_closes_and_the_clients_run_ends() -> void:
	var pair: NetPair = _new_pair(50.0)
	check(pair.start(), "the host starts")
	pair.run(90)
	pair.client_link.close()
	for i in 60:
		pair.step()
	check_equal(pair.host_ticks(), 150, "the host ran every tick")
	check(pair.host.is_running(), "its run goes on")
	check(pair.client.feed.closed and not pair.client.is_playing(), "the client's run ended")
	check(pair.client_ticks() >= 80 and pair.client_ticks() < 150, "having played what arrived (%d ticks)" % pair.client_ticks())
	check_equal(pair.first_parting(), -1, "and agreed as far as it played")
	check(not pair.client_fight.frames.is_playing(), "the client's frames service plays nothing more")


func test_a_disturbed_world_is_caught_by_the_checks_with_its_areas() -> void:
	var pair: NetPair = _new_pair(50.0)
	check(pair.start(), "the host starts")
	pair.run(100)
	check_equal(pair.host.parted_tick, -1, "nothing parted yet")
	# The client's world is changed behind the game's back: its own wizard moved.
	var moved: Actor = pair.client_fight.fight.players[1]
	moved.position += Vector2(40.0, -25.0)
	var disturbed_at: int = pair.client_ticks()
	pair.run(2 * NetChecks.EVERY + 30)
	check(pair.host.parted_tick >= disturbed_at, "the host sees it (tick %d)" % pair.host.parted_tick)
	check(pair.host.parted_tick <= disturbed_at + 2 * NetChecks.EVERY, "within two checks of the tick it happened (%d after %d)" % [pair.host.parted_tick, disturbed_at])
	check(not pair.host.parted_areas.is_empty(), "with the areas that differ: %s" % ", ".join(pair.host.parted_areas))
	check(pair.host.parted_areas.has(SimHash.BODY_PREFIX + str(moved.id)), "the moved wizard's body among them")
	check_equal(pair.client.parted_tick, pair.host.parted_tick, "and the client is told the tick")
	check_equal(pair.client.parted_areas, pair.host.parted_areas.slice(0, NetMessage.MAX_PARTED), "and the areas")
	check(pair.first_parting() >= disturbed_at, "the harness agrees: they part from that tick (%d)" % pair.first_parting())
	check(pair.host.is_running() and pair.client.is_playing(), "both play on: the spike does not mend it")


func test_the_replay_the_client_received_played_offline_is_the_hosts_run() -> void:
	var pair: NetPair = _new_pair(100.0, 20.0, 0.05)
	check(pair.start(), "the host starts")
	pair.run(240)
	check(pair.let_client_catch_up(), "the client plays every tick")
	var received: Replay = pair.client.replay
	check(received != null and received.tick_count() == 240, "the client holds the run it was sent")
	if received == null:
		return
	check_equal(received.to_bytes(), pair.host.replay.to_bytes(), "byte for byte the host's recording")
	# Played as a replay file in a third world, nothing linked.
	var offline := ContentFight.new(root, ContentFight.CARD, _card())
	var replay: Replay = Replay.from_bytes(received.to_bytes())
	check(replay != null and offline.frames.play(replay), "it plays as a replay file")
	var run := Desync.new()
	for i in 240:
		offline.step()
		run.capture(offline.areas())
	check_equal(Desync.first_parting(pair.host_run, run), -1, "and is the host's run at every tick")
	offline.frames.stop_playing()
	offline.free_all()


## Online lobby L2: a machine joins a run the host has played alone for a while (the hub). It
## plays the recording from its first tick, far faster than it was made, and then live.
func test_a_machine_that_joins_a_run_under_way_catches_up_and_agrees_at_every_tick() -> void:
	var pair: NetPair = _new_pair(50.0)
	# Nobody plays the host's second seat until the other machine is given it.
	pair.host_fight.frames.set_source(NetHost.SEAT, null)
	var replay: Replay = pair.host_fight.frames.record(&"sandbox_requested", 0, 0x5e55)
	var alone: int = 900
	for i in alone:
		pair.step(true, false)
	check_equal(pair.host_ticks(), 0, "the host played alone: no run is begun with the other machine")
	check_equal(replay.tick_count(), alone, "fifteen seconds of it, recorded")
	# The other machine asks for a seat for its player, and the host joins it to the run.
	pair.client.link.send(NetMessage.of_seat_ask(0))
	for i in 8:
		pair.step()
		pair.host.pump()
	check_equal(pair.host.guest_seats(), 1 << NetHost.SEAT, "it is given the free seat")
	check(pair.host.begin(replay), "and joined to the run under way")
	# However slow this machine is under the test's own captures: a step's time is never short.
	pair.client.burst_usec = 1 << 40
	var steps_needed: int = 0
	while pair.host_ticks() - pair.client_ticks() > 12 and steps_needed < 600:
		pair.step()
		steps_needed += 1
	check(steps_needed < alone / LiveFeed.CATCH_UP / 2, "it caught up far sooner than at three ticks a step (%d steps)" % steps_needed)
	pair.run(240)
	check(not pair.client.is_catching_up(), "and paces as ever from there")
	check(pair.let_client_catch_up(), "it plays every tick")
	check_equal(pair.first_parting(), -1, "and agrees at every tick: those before it came, and those it plays in")
	var totals: NetStats = pair.host.totals()
	check(totals.checks >= 2 and totals.mismatches == 0, "the checks since it joined passed (%d)" % totals.checks)
	check(pair.client.stats.presses > 0, "its presses are in the host's ticks")
	check(pair.client_fight.wizard_casts > 0 and pair.host_fight.wizard_casts > 0, "both fights fought")

