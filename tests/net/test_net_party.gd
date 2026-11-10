extends "res://tests/support/suite.gd"
## Up to four machines over the loopback (online lobby L3, docs/milestones/online-lobby.md): a host
## and up to three guest machines, each a scripted fight linked by the sessions on a stepped clock
## (tests/net/net_pair.gd). One player on each of four machines (1+1+1+1) and a guest with two
## seats between two with one (1+2+1), over links of different round trips with jitter and loss:
## every guest the same as the host at every tick, the host on time, every guest's checks passed
## and its presses in the host's recording. A guest gone mid-run: its seats leave on every machine
## at the same tick and the others play on, in step. A guest that sends another's seat is closed
## alone.
##
## The runner plays it in processes side by side (tests/support/suite.gd, "shards"):
# unit-test-shards: 3

const NetPair := preload("res://tests/net/net_pair.gd")
const ContentFight := preload("res://tests/core/content_fight.gd")
const RegistryScript := preload("res://core/registry/registry.gd")

## Ticks the host runs in a test (five seconds, so five checks).
const TICKS: int = 300
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


func _party(guest_seats: Array[int], rtt_ms: float, jitter_ms: float, loss: float) -> NetPair:
	_pair = NetPair.new(root, ContentFight.CARD, _card(), rtt_ms, jitter_ms, loss, -1, 3, [], guest_seats)
	return _pair


## A run of TICKS: the host on time, every guest the same at every tick, every check passed, every
## guest's seats played on the host.
func _plays_the_same(guest_seats: Array[int], rtt_ms: float, jitter_ms: float, loss: float) -> void:
	var pair: NetPair = _party(guest_seats, rtt_ms, jitter_ms, loss)
	var label: String = "%s at %d ms, jitter %d, loss %d%%" % [str(guest_seats), rtt_ms, jitter_ms, roundi(loss * 100.0)]
	check(pair.start(), "%s: the host starts" % label)
	check_equal(pair.host.replay.seats, 0b1111, "%s: every seat seated" % label)
	for i in TICKS:
		pair.step()
		if pair.host_ticks() != i + 1:
			check_equal(pair.host_ticks(), i + 1, "%s: the host runs a tick every step (step %d)" % [label, i])
			return
	check(pair.let_client_catch_up(), "%s: every guest plays every tick" % label)
	pair.step(true, false)
	for g in pair.clients.size():
		var client: NetClient = pair.clients[g]
		var guest: NetGuest = pair.host.guests[g]
		var who: String = "%s, guest %d" % [label, g]
		check(client.started and client.problem == "" and guest.problem == "", "%s: linked (%s%s)" % [who, client.problem, guest.problem])
		check_equal(pair.client_runs[g].hashes.size(), TICKS, "%s: every tick captured" % who)
		check_equal(pair.parting_of(g), -1, "%s: the same as the host at every tick" % who)
		check(guest.stats.checks >= TICKS / NetChecks.EVERY - 1, "%s: the host compared its checks (%d)" % [who, guest.stats.checks])
		check_equal([guest.stats.mismatches, guest.parted_tick, client.parted_tick], [0, -1, -1], "%s: none differed" % who)
		check(client.stats.presses > 0, "%s: its presses came back (%d)" % [who, client.stats.presses])
		for seat in Replay.SEATS:
			if guest_seats[g] & (1 << seat) != 0:
				check(_presses_recorded(pair.host.replay, seat) > 0, "%s: seat %d's presses are in the host's recording" % [who, seat + 1])
	for problem in pair.host_run.problems:
		check(false, "%s: %s" % [label, problem])
	check(pair.host_fight.wizard_casts > 0, "%s: the fights fought" % label)


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


func test_one_player_on_each_of_four_machines() -> void:
	_plays_the_same([1 << 1, 1 << 2, 1 << 3] as Array[int], 120.0, 15.0, 0.03)


func test_a_guest_with_two_seats_between_two_with_one() -> void:
	_plays_the_same([1 << 1, (1 << 2) | (1 << 3)] as Array[int], 80.0, 10.0, 0.02)
	_pair.free_all()
	_pair = null
	# The two-seat guest in the middle of the order, as the plan's 1+2+1 has it.
	_plays_the_same([1 << 3, (1 << 1) | (1 << 2)] as Array[int], 40.0, 5.0, 0.0)


## A command of a guest's second seat goes to the host in that seat's frame and comes back to
## apply on every machine at the same tick, once each.
func test_a_second_seats_command_applies_once_on_every_machine_at_the_same_tick() -> void:
	var pair: NetPair = _party([1 << 1, (1 << 2) | (1 << 3)] as Array[int], 60.0, 0.0, 0.0)
	check(pair.start(), "the host starts")
	var heard: Array = []
	var fights: Array = [pair.host_fight]
	fights.append_array(pair.client_fights)
	for m in fights.size():
		var on := func(seat: int, staff: int, slot: int, card: StringName) -> void: heard.append([m, (pair.host_ticks() - 1) if m == 0 else int(pair.client_played[m - 1]), seat, staff, slot, card])
		(fights[m] as ContentFight).fight.bus.call(&"listen", &"staff_change_requested", on)
	pair.run(60)
	heard.clear()
	pair.client_fights[1].fight.bus.emit_signal(&"staff_change_requested", 3, 2, 0, CARD)
	pair.run(60)
	check(pair.let_client_catch_up(), "every guest plays every tick")
	check_equal(heard.size(), 3, "it applied once on each machine: %s" % str(heard))
	if heard.size() == 3:
		var where: Array = heard.map(func(entry: Array) -> int: return entry[0])
		where.sort()
		check_equal(where, [0, 1, 2], "on the host and both guests")
		check(heard[1].slice(1) == heard[0].slice(1) and heard[2].slice(1) == heard[0].slice(1), "at the same tick, as seat 4's")
	check_equal(pair.first_parting(), -1, "and every machine agrees at every tick")


## A guest gone mid-run: its seats leave on the host, and the LEAVE in the host's ticks takes
## them off the other guests' games at the same tick; the others play on, the same.
func test_a_guest_gone_leaves_its_seats_and_the_others_play_on() -> void:
	var pair: NetPair = _party([1 << 1, (1 << 2) | (1 << 3)] as Array[int], 60.0, 0.0, 0.0)
	check(pair.start(), "the host starts")
	pair.run(120)
	pair.host_links[1].close()
	pair.run(120)
	check(pair.host.guests[1].is_gone(), "the host saw the second guest go")
	check(not pair.host_fight.input.is_joined(2) and not pair.host_fight.input.is_joined(3), "its seats left the host's game")
	check(pair.host_fight.input.is_joined(1) and pair.host.guests[0].hears(), "the first guest plays on")
	# Only the first guest still plays the host's run; the second's replay ended.
	for i in 300:
		if pair.client_played[0] >= pair.host_ticks():
			break
		pair.step(false, true, 0b01)
	check_equal(pair.client_played[0], pair.host_ticks(), "the first guest played every tick")
	check_equal(pair.parting_of(0), -1, "the same as the host at every tick, the leave included")
	check(pair.clients[0].problem == "" and pair.host.guests[0].stats.mismatches == 0, "its checks passed")
	check_equal(pair.client_fights[0].frames.joined_seats(), [0, 1] as Array[int], "on its game too the two seats left")
	check(_left_at(pair.host.replay, 2) > 0 and _left_at(pair.host.replay, 3) > 0, "both seats' leaves are in the host's recording")
	check(not pair.clients[1].is_playing(), "the gone guest's replay ended")


## The tick at which `seat` left in `replay`, or -1.
func _left_at(replay: Replay, seat: int) -> int:
	var frames: Array[InputFrame] = []
	for i in 4:
		frames.append(InputFrame.new())
	for tick in replay.tick_count():
		replay.read_tick(tick, frames)
		for command: Array in frames[seat].commands:
			if command[0] == InputFrame.LEAVE:
				return tick
	return -1


## A guest that sends a frame for a seat another guest plays is closed, alone: the other guests and
## the host play on, in step.
func test_a_guest_sending_another_guests_seat_is_closed_alone() -> void:
	var pair: NetPair = _party([1 << 1, 1 << 2, 1 << 3] as Array[int], 40.0, 0.0, 0.0)
	check(pair.start(), "the host starts")
	pair.run(60)
	var frame := InputFrame.new()
	frame.seat = 3
	frame.held_bits = 0b0001
	pair.client_links[0].send(NetMessage.of_frame(pair.host_ticks() + 2, frame.to_bytes()))
	pair.run(120)
	check(pair.host.guests[0].problem.contains("a frame of seat 3"), "the first guest is closed (%s)" % pair.host.guests[0].problem)
	for g in [1, 2]:
		check(pair.host.guests[g].hears() and pair.host.guests[g].problem == "", "guest %d plays on" % g)
	for i in 300:
		if pair.client_played[1] >= pair.host_ticks() and pair.client_played[2] >= pair.host_ticks():
			break
		pair.step(false, true, 0b110)
	for g in [1, 2]:
		check_equal(pair.client_played[g], pair.host_ticks(), "guest %d played every tick" % g)
		check_equal(pair.parting_of(g), -1, "guest %d the same as the host at every tick" % g)
	check(not pair.host_fight.input.is_joined(1), "the closed guest's seat left")
	check(pair.host_fight.input.is_joined(3), "seat 4 is still the third guest's")
