extends "res://tests/support/suite.gd"
## The links (netcode spike S2, docs/milestones/netcode-spike.md): the loopback hands one end's
## messages to the other in order and closes for both; the conditioner makes them late (delay,
## jitter, loss as a resend that holds back what is behind it), never out of order, the same on
## every run of one seed, on the clock it is given.

var _now: float = 0.0


func before_each() -> void:
	_now = 0.0


func _bytes(value: int) -> PackedByteArray:
	return PackedByteArray([value & 0xff, value >> 8])


func _value(bytes: PackedByteArray) -> int:
	return bytes[0] | (bytes[1] << 8)


func _clock() -> float:
	return _now


func test_the_loopback_hands_over_in_order_both_ways() -> void:
	var ends: Array[NetLoopback] = NetLoopback.pair()
	check(ends[0].is_open() and ends[1].is_open(), "open")
	for i in 5:
		ends[0].send(_bytes(i))
	ends[1].send(_bytes(100))
	for i in 5:
		check_equal(_value(ends[1].read()), i, "message %d, in order" % i)
	check(ends[1].read().is_empty(), "then nothing")
	check_equal(_value(ends[0].read()), 100, "and the other way")
	ends[0].send(PackedByteArray())
	check(ends[1].read().is_empty(), "an empty message is nothing")


func test_the_loopback_closes_for_both_and_keeps_what_arrived() -> void:
	var ends: Array[NetLoopback] = NetLoopback.pair()
	ends[0].send(_bytes(1))
	ends[0].close()
	check(not ends[0].is_open() and not ends[1].is_open(), "closed for both")
	ends[0].send(_bytes(2))
	ends[1].send(_bytes(3))
	check_equal(_value(ends[1].read()), 1, "what arrived before it closed is still read")
	check(ends[1].read().is_empty() and ends[0].read().is_empty(), "nothing sent after it closed arrives")


func test_the_loopback_closes_when_nobody_reads() -> void:
	var ends: Array[NetLoopback] = NetLoopback.pair()
	for i in NetLoopback.MAX_WAITING:
		ends[0].send(_bytes(i))
	check(ends[0].is_open(), "full, still open")
	ends[0].send(_bytes(0))
	check(not ends[0].is_open(), "one more closes it")
	var one: NetLoopback = NetLoopback.pair()[0]
	one.send(_bytes(1))
	check(not one.is_open(), "an end whose other end is gone closes")


func test_the_conditioner_delays_by_its_clock() -> void:
	var ends: Array[NetLoopback] = NetLoopback.pair()
	var slow := NetConditioner.new(ends[0], _clock)
	slow.delay_ms = 50.0
	slow.send(_bytes(1))
	_now = 20.0
	slow.send(_bytes(2))
	_now = 49.0
	check(slow.is_open() and ends[1].read().is_empty(), "nothing before its delay")
	_now = 50.0
	slow.read()
	check_equal(_value(ends[1].read()), 1, "the first at 50 ms")
	check(ends[1].read().is_empty(), "the second not yet")
	_now = 70.0
	slow.read()
	check_equal(_value(ends[1].read()), 2, "the second at 70 ms")
	ends[1].send(_bytes(9))
	check_equal(_value(slow.read()), 9, "what the other end sends is read through it at once")


func test_the_conditioner_keeps_the_order_under_jitter_and_loss() -> void:
	var ends: Array[NetLoopback] = NetLoopback.pair()
	var slow := NetConditioner.new(ends[0], _clock, 7)
	slow.delay_ms = 30.0
	slow.jitter_ms = 40.0
	slow.loss = 0.05
	slow.resend_ms = 150.0
	var sent_at: Dictionary[int, float] = {}
	var arrived_at: Dictionary[int, float] = {}
	var order: Array[int] = []
	for step in 600:
		_now = step * 1000.0 / 60.0
		if step < 300:
			slow.send(_bytes(step))
			sent_at[step] = _now
		slow.read()
		while true:
			var bytes: PackedByteArray = ends[1].read()
			if bytes.is_empty():
				break
			order.append(_value(bytes))
			arrived_at[_value(bytes)] = _now
	check_equal(order.size(), 300, "every message arrives: none is lost for good")
	var sorted: Array[int] = order.duplicate()
	sorted.sort()
	check_equal(order, sorted, "in the order sent")
	var late: int = 0
	var held_back: int = 0
	var on_time: int = 0
	for value in order:
		var took: float = arrived_at[value] - sent_at[value]
		check(took >= 30.0 - 0.001, "message %d never before its delay (%.1f ms)" % [value, took])
		if took >= 150.0:
			late += 1
		elif took > 30.0 + 40.0 + 17.0:
			held_back += 1
		else:
			on_time += 1
	check(late > 0, "a lost one is sent again after the resend time (%d that late)" % late)
	check(held_back > 0, "those behind a lost one waited for it (%d)" % held_back)
	check(on_time > 50, "and the rest took the delay and their jitter (%d)" % on_time)


func test_the_conditioner_is_the_same_for_one_seed() -> void:
	var runs: Array = []
	for seed_of: int in [3, 3, 4]:
		var ends: Array[NetLoopback] = NetLoopback.pair()
		var slow := NetConditioner.new(ends[0], _clock, seed_of)
		slow.delay_ms = 10.0
		slow.jitter_ms = 60.0
		slow.loss = 0.1
		var arrivals: Array[int] = []
		for step in 200:
			_now = step * 1000.0 / 60.0
			if step < 100:
				slow.send(_bytes(step))
			slow.read()
			while not ends[1].read().is_empty():
				arrivals.append(step)
		runs.append(arrivals)
	check_equal(runs[0], runs[1], "one seed: the same arrivals")
	check(runs[0] != runs[2], "another seed: others")


func test_closing_the_conditioner_loses_what_was_on_its_way() -> void:
	var ends: Array[NetLoopback] = NetLoopback.pair()
	var slow := NetConditioner.new(ends[0], _clock)
	slow.delay_ms = 50.0
	slow.send(_bytes(1))
	slow.close()
	_now = 100.0
	check(not slow.is_open() and not ends[1].is_open(), "closed for both")
	check(ends[1].read().is_empty(), "and the message on its way is gone")
	check_equal(slow.waiting(), 0, "nothing waits")
