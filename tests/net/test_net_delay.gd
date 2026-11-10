extends "res://tests/support/suite.gd"
## The client's input delay (netcode spike S5, docs/milestones/netcode-spike.md; net/net_delay.gd)
## by itself, told round trips and frames sent: a delay given never moves; one not given starts
## from the pings so far, takes the middle one of the last five, rises at once, falls only past
## two ticks and then a tick every four frames, stops where the ping asks, and counts each move.


## A round trip, in milliseconds, that asks for a delay of `ticks` (with the cushion of 2).
func _asking(ticks: int) -> float:
	return (ticks - 3) * NetDelay.TICK_MS - 8.0


## A delay started after one ping asking for `ticks`.
func _started_at(ticks: int) -> NetDelay:
	var delay := NetDelay.new()
	delay.add_rtt(_asking(ticks))
	delay.start()
	return delay


## `count` pings answered in the run, each asking for `ticks`.
func _pongs(delay: NetDelay, count: int, ticks: int) -> void:
	for i in count:
		delay.add_rtt(_asking(ticks))
		delay.retune()


## `count` frames sent. Returns the delay of each.
func _frames(delay: NetDelay, count: int) -> PackedInt32Array:
	var sent := PackedInt32Array()
	for i in count:
		sent.append(delay.step())
	return sent


func test_a_delay_given_never_moves() -> void:
	var delay := NetDelay.new(4)
	check_equal([delay.ticks, delay.given], [4, true], "given")
	delay.add_rtt(300.0)
	check_equal(delay.start(), 4, "at the start")
	_pongs(delay, 6, 30)
	_frames(delay, 40)
	_pongs(delay, 6, 1)
	check_equal([delay.ticks, delay.step(), delay.retunes], [4, 4, 0], "whatever the ping")
	check_equal(NetDelay.new(500).ticks, NetDelay.MOST, "never more than the most")
	check_equal(NetDelay.new(0).start(), 0, "none is a delay given too")


func test_it_starts_from_the_pings_so_far() -> void:
	var delay := NetDelay.new()
	check_equal([delay.ticks, delay.given], [-1, false], "not known before the start")
	check_equal(delay.start(), NetDelay.DEFAULT, "no ping answered: the default")
	delay = NetDelay.new()
	_pongs(delay, 4, 12)
	check_equal([delay.ticks, delay.step(), delay.retunes], [-1, -1, 0], "and not worked out before it")
	check_equal(delay.start(), 12, "then from the pings until then")
	delay = NetDelay.new()
	delay.add_rtt(100.5)
	check_equal(delay.start(), 7 + 2 + 1, "one: its round trip in ticks, rounded up, the cushion and one")
	check_equal(NetDelay.new(-1, 5).cushion, 5, "the cushion it is made with")
	delay = NetDelay.new(-1, 5)
	delay.add_rtt(100.5)
	check_equal(delay.start(), 7 + 5 + 1, "counts")
	delay = NetDelay.new()
	delay.add_rtt(_asking(9))
	delay.add_rtt(_asking(20))
	check_equal(delay.start(), 20, "of two the longer")
	delay = NetDelay.new()
	delay.add_rtt(60000.0)
	check_equal(delay.start(), NetDelay.MOST, "never more than the most")
	delay = NetDelay.new()
	delay.add_rtt(0.0)
	check_equal(delay.start(), 2 + 1, "a ping of nothing: the cushion and one")


func test_the_middle_one_of_the_last_five_pings_counts() -> void:
	var delay := NetDelay.new()
	check_equal(delay.rtt_ms(), 0.0, "none measured")
	for ms: float in [50.0, 900.0, 40.0]:
		delay.add_rtt(ms)
	check_equal(delay.rtt_ms(), 50.0, "of three")
	delay.add_rtt(60.0)
	check_equal(delay.rtt_ms(), 60.0, "of four the longer of the middle two")
	delay.add_rtt(10.0)
	check_equal(delay.rtt_ms(), 50.0, "of five")
	for ms: float in [70.0, 80.0]:
		delay.add_rtt(ms)
	# The last five: 40, 60, 10, 70, 80.
	check_equal(delay.rtt_ms(), 60.0, "the oldest are forgotten")


## A run that started before a ping came back (or on one bad ping) is not moved by one or two
## pings: the middle one means nothing yet.
func test_it_is_not_moved_in_the_run_before_three_pings() -> void:
	var delay := NetDelay.new()
	delay.start()
	_pongs(delay, 2, NetDelay.MOST)
	check_equal([delay.ticks, delay.retunes], [NetDelay.DEFAULT, 0], "two slow pings: the default still")
	_pongs(delay, 1, 12)
	# Of 60, 60 and 12 the middle one.
	check_equal([delay.ticks, delay.retunes], [NetDelay.MOST, 1], "the third: by the middle one")


func test_it_rises_at_once_and_never_past_the_most() -> void:
	var delay: NetDelay = _started_at(5)
	_pongs(delay, 2, 5)
	_pongs(delay, 2, 15)
	check_equal([delay.ticks, delay.retunes], [5, 0], "two slow pings of five: not moved")
	_pongs(delay, 1, 15)
	check_equal([delay.ticks, delay.step(), delay.retunes], [15, 15, 1], "the third: up, at once")
	_frames(delay, 20)
	check_equal(delay.ticks, 15, "and it stays up")
	_pongs(delay, 5, 6)
	_pongs(delay, 3, 500)
	check_equal([delay.ticks, delay.retunes], [NetDelay.MOST, 3], "up from a fall, to the most")


func test_a_ping_that_moves_a_little_leaves_it() -> void:
	var delay: NetDelay = _started_at(9)
	_pongs(delay, 5, 8)
	_frames(delay, 20)
	check_equal([delay.ticks, delay.retunes], [9, 0], "a ping a tick shorter: not moved")
	_pongs(delay, 5, 7)
	_frames(delay, 20)
	check_equal([delay.ticks, delay.retunes], [7, 1], "two ticks shorter: it falls to it")
	_pongs(delay, 5, 8)
	check_equal([delay.ticks, delay.retunes], [8, 2], "a tick longer: up")


func test_it_falls_a_tick_every_four_frames() -> void:
	var delay: NetDelay = _started_at(12)
	_pongs(delay, 3, 9)
	check_equal(delay.ticks, 12, "nothing falls until a frame is sent")
	check_equal(_frames(delay, 14), PackedInt32Array([12, 12, 12, 11, 11, 11, 11, 10, 10, 10, 10, 9, 9, 9]), "a tick every LOWER_EVERY frames, to what the ping asks for")
	check_equal(delay.retunes, 1, "one fall")


func test_a_fall_stops_where_the_ping_asks_and_counts_once() -> void:
	var delay: NetDelay = _started_at(40)
	_pongs(delay, 3, 10)
	_frames(delay, 4 * NetDelay.LOWER_EVERY)
	check_equal([delay.ticks, delay.retunes], [36, 1], "falling")
	# The ping asks for a tick less than the delay now: no further.
	_pongs(delay, 3, 35)
	_frames(delay, 40)
	check_equal([delay.ticks, delay.retunes], [36, 1], "within a tick of what the ping asks: it stays")
	_pongs(delay, 3, 30)
	_frames(delay, 2 * NetDelay.LOWER_EVERY)
	_pongs(delay, 3, 20)
	check_equal([delay.ticks, delay.retunes], [34, 2], "a fall whose end moves is one fall")
	_frames(delay, 100)
	check_equal([delay.ticks, delay.retunes], [20, 2], "to its new end")
	delay.start()
	check_equal([delay.ticks, delay.retunes], [20, 0], "a new run counts from nothing")
