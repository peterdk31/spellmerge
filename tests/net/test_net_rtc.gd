extends "res://tests/support/suite.gd"
## The real link (netcode spike S4, docs/milestones/netcode-spike.md): two WebRTC peers in this one
## process, on this machine alone (no STUN server), swap their codes as two players would
## (`NetRtc`), and the link they come to hold (`NetRtcLink`) carries messages both ways in order,
## splits and joins the large ones, and closes for both. Then two scripted fights play through it
## (tests/net/net_pair.gd), and the client agrees with the host at every tick.
##
## WebRTC runs on real time (its own threads), so these tests wait in small real steps; what
## arrives when differs from run to run, and the fights must agree whatever it does. Needs the
## WebRTC extension (`ci/build/webrtc.sh`; `tests/net/test_net_webrtc.gd` fails a test run that
## should have it): without it only the refusal is checked.

const NetPair := preload("res://tests/net/net_pair.gd")
const ContentFight := preload("res://tests/core/content_fight.gd")
const RegistryScript := preload("res://core/registry/registry.gd")

## The longest a handshake's step may take here, in milliseconds.
const PATIENCE_MS: int = 15000
const CARD: StringName = &"bolt"
const TICKS: int = 240

var _pair: NetPair


func before_each() -> void:
	_pair = null


func after_each() -> void:
	if _pair != null:
		_pair.free_all()


func _has_webrtc() -> bool:
	if not NetWebRTC.available():
		print("  no WebRTC extension in this checkout (ci/build/webrtc.sh): not checked")
	return NetWebRTC.available()


## Poll `sides` until `done` says so. False when it took longer than PATIENCE_MS.
func _wait(sides: Array[NetRtc], done: Callable) -> bool:
	var began: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - began < PATIENCE_MS:
		for side in sides:
			side.poll()
		if done.call():
			return true
		OS.delay_msec(2)
	return false


## Two machines that swapped their codes: the host's and the client's ends of the link.
func _linked() -> Array[NetLink]:
	var host := NetRtc.new(PackedStringArray())
	var client := NetRtc.new(PackedStringArray())
	var sides: Array[NetRtc] = [host, client]
	check_equal(host.offer(), "", "the host begins")
	check(_wait(sides, func() -> bool: return host.code() != ""), "the host's code is made (%s)" % host.problem())
	check(_candidates(host.code()) > 0, "with an address to reach the host at in it")
	check_equal(client.take(host.code()), "", "the client takes the host's code")
	check(_wait(sides, func() -> bool: return client.code() != ""), "the client's code is made (%s)" % client.problem())
	check(_candidates(client.code()) > 0, "with an address to reach the client at in it")
	check_equal(host.take(client.code()), "", "the host takes the code that came back")
	check(_wait(sides, func() -> bool: return host.link() != null and client.link() != null), "the two find each other (%s%s)" % [host.problem(), client.problem()])
	return [host.link(), client.link()]


## How many candidates the code `text` holds.
func _candidates(text: String) -> int:
	var code := NetCode.new()
	return code.mids.size() if code.read(text) == "" else -1


## Read `link`'s next message, waiting for it.
func _read(link: NetLink) -> PackedByteArray:
	var began: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - began < PATIENCE_MS:
		var bytes: PackedByteArray = link.read()
		if not bytes.is_empty():
			return bytes
		OS.delay_msec(2)
	return PackedByteArray()


func _message(size: int, salt: int) -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.resize(size)
	for at in size:
		bytes[at] = (at * 31 + salt) & 0xff
	return bytes


func test_a_build_without_webrtc_says_so_and_makes_no_peer() -> void:
	if NetWebRTC.available():
		return
	var host := NetRtc.new(PackedStringArray())
	check(host.offer() != "" and host.problem() != "", "Host is refused, in words (%s)" % host.problem())
	check(host.link() == null and host.code() == "", "nothing is made")


func test_two_machines_swap_codes_and_hold_a_link() -> void:
	if not _has_webrtc():
		return
	var ends: Array[NetLink] = _linked()
	if ends[0] == null or ends[1] == null:
		return
	check(ends[0].is_open() and ends[1].is_open(), "open at both ends")
	# In order both ways, the small and the large: one past a packet, and the largest a session sends.
	var sizes: Array[int] = [1, 9, NetRtcLink.CHUNK, NetRtcLink.CHUNK + 1, NetRtcLink.CHUNK * 3, NetMessage.MAX_BYTES]
	for i in sizes.size():
		ends[0].send(_message(sizes[i], i))
		ends[1].send(_message(sizes[i], i + 100))
	for i in sizes.size():
		check(_read(ends[1]) == _message(sizes[i], i), "to the client: message %d of %d bytes, whole and in order" % [i, sizes[i]])
		check(_read(ends[0]) == _message(sizes[i], i + 100), "to the host: message %d of %d bytes" % [i, sizes[i]])
	check(ends[0].read().is_empty() and ends[1].read().is_empty(), "and nothing more")
	ends[0].send(PackedByteArray())
	ends[0].send(_message(5, 7))
	check(_read(ends[1]) == _message(5, 7), "an empty message is nothing")
	# Closed by one, closed for both; what arrived before is still read.
	ends[1].send(_message(3, 9))
	check(_read(ends[0]) == _message(3, 9), "the last message arrives")
	ends[0].close()
	var began: int = Time.get_ticks_msec()
	while ends[1].is_open() and Time.get_ticks_msec() - began < PATIENCE_MS:
		OS.delay_msec(2)
	check(not ends[0].is_open() and not ends[1].is_open(), "closed for both")
	ends[1].send(_message(4, 1))
	check(ends[0].read().is_empty(), "nothing sent after it closed arrives")


func test_a_message_too_large_closes_the_link() -> void:
	if not _has_webrtc():
		return
	var ends: Array[NetLink] = _linked()
	if ends[0] == null:
		return
	ends[0].send(_message(NetMessage.MAX_BYTES + 1, 0))
	check(not ends[0].is_open(), "a message past the limit is not sent: the link closes")
	ends[1].close()


## What a hostile peer could put on the channel: each closes the link, and nothing of it is read.
func test_packets_out_of_form_close_the_link() -> void:
	if not _has_webrtc():
		return
	var whole: PackedByteArray = PackedByteArray([0, 7, 7])
	var bad: Dictionary[String, Array] = {
		"a text packet": [whole, true],
		"an empty packet": [PackedByteArray(), false],
		"a mark alone": [PackedByteArray([0]), false],
		"a mark that is none": [PackedByteArray([2, 7]), false],
		"a packet past a chunk": [_message(NetRtcLink.CHUNK + 2, 0), false],
	}
	for what: String in bad:
		var ends: Array[NetLink] = _linked()
		if ends[0] == null or ends[1] == null:
			return
		var link: NetRtcLink = ends[0] as NetRtcLink
		check(link.take_packet(whole, false) and link.is_open(), "%s: a packet in form is taken first" % what)
		check(not link.take_packet(bad[what][0], bad[what][1]), "%s is refused" % what)
		check(not link.is_open(), "%s closes the link" % what)
		check(not link.take_packet(whole, false), "%s: and nothing is taken after" % what)
		ends[1].close()
	# A message that never ends, and messages nobody reads.
	var ends: Array[NetLink] = _linked()
	if ends[0] == null or ends[1] == null:
		return
	var endless: NetRtcLink = ends[0] as NetRtcLink
	var part: PackedByteArray = _message(NetRtcLink.CHUNK + 1, 0)
	part[0] = 1
	var taken: int = 0
	while endless.take_packet(part, false) and taken < 1000:
		taken += 1
	check(taken == NetMessage.MAX_BYTES / NetRtcLink.CHUNK and not endless.is_open(), "a message past the largest closes the link (after %d packets)" % taken)
	var unread: NetRtcLink = ends[1] as NetRtcLink
	var big: PackedByteArray = _message(NetRtcLink.CHUNK + 1, 0)
	big[0] = 0
	taken = 0
	while unread.take_packet(big, false) and taken < 100000:
		taken += 1
	check(taken == NetRtcLink.MAX_WAITING_BYTES / NetRtcLink.CHUNK and not unread.is_open(), "messages nobody reads close it at its byte limit (after %d)" % taken)
	check(unread.read().size() == NetRtcLink.CHUNK, "what arrived whole before is still read")


func test_a_code_of_the_wrong_side_or_no_code_is_refused_and_another_may_be_given() -> void:
	if not _has_webrtc():
		return
	var host := NetRtc.new(PackedStringArray())
	var client := NetRtc.new(PackedStringArray())
	var other_host := NetRtc.new(PackedStringArray())
	var sides: Array[NetRtc] = [host, client, other_host]
	check(client.take("hello") != "", "what is no code is refused")
	check_equal(client.problem(), "", "and the client may still be given one")
	check_equal(host.offer(), "", "the host begins")
	check(host.offer() != "", "but not twice")
	check(host.take("SM1.AAAA") != "", "the host refuses what is no code")
	check_equal(other_host.offer(), "", "another host begins")
	check(_wait(sides, func() -> bool: return host.code() != "" and other_host.code() != ""), "the hosts' codes are made")
	check(host.take(other_host.code()) != "", "a host refuses a host's code")
	check_equal(client.take(host.code()), "", "the client takes the host's code after its refusals")
	check(client.take(host.code()) != "", "but only one")
	check(_wait(sides, func() -> bool: return client.code() != ""), "the client's code is made")
	var other_client := NetRtc.new(PackedStringArray())
	check(other_client.take(client.code()) != "" and other_client.problem() == "", "a joining machine refuses a joining machine's code")
	check_equal(other_client.take(other_host.code()), "", "and takes a host's after")
	sides.append(other_client)
	check_equal(host.take(client.code()), "", "the host takes the client's code after its refusals")
	check(host.take(client.code()) != "", "but only one")
	check(_wait(sides, func() -> bool: return host.link() != null and client.link() != null), "and they find each other (%s%s)" % [host.problem(), client.problem()])
	for side in sides:
		side.close()
		if side.link() != null:
			side.link().close()


## The joining machine waits as long as its player does (its code travels to the host by hand);
## the host, once given that code, gives up when the other machine is not found in time.
func test_only_the_host_given_the_answer_runs_out_of_time() -> void:
	if not _has_webrtc():
		return
	var now: Array[int] = [0]
	var clock: Callable = func() -> int: return now[0]
	var host := NetRtc.new(PackedStringArray())
	var client := NetRtc.new(PackedStringArray())
	host.clock = clock
	client.clock = clock
	var sides: Array[NetRtc] = [host, client]
	check_equal(host.offer(), "", "the host begins")
	check(_wait(sides, func() -> bool: return host.code() != ""), "the host's code is made")
	check_equal(client.take(host.code()), "", "the client takes it")
	check(_wait(sides, func() -> bool: return client.code() != ""), "the client's code is made")
	# An hour passes before the host's player pastes the answer.
	now[0] += 3600 * 1000
	client.poll()
	host.poll()
	check_equal([client.problem(), host.problem()], ["", ""], "an hour later both still wait")
	# The client's machine is gone by then: the host is given its code and finds nobody.
	client.close()
	check_equal(host.take(client.code()), "", "the host takes the answer")
	now[0] += NetRtc.LINK_MS - 1
	host.poll()
	var early: String = host.problem()
	now[0] += 2
	host.poll()
	check(host.problem() != "", "past its time the host gives up, in words (%s)" % host.problem())
	check(early == "" or early == host.problem(), "and not before, unless WebRTC itself said so")
	host.close()


func test_two_fights_through_the_real_link_agree_at_every_tick() -> void:
	if not _has_webrtc():
		return
	var ends: Array[NetLink] = _linked()
	if ends[0] == null or ends[1] == null:
		return
	var registry: RegistryScript = own(RegistryScript.new()) as RegistryScript
	registry.scan()
	var card: SpellComponent = null
	for found: Resource in registry.get_all(&"spells"):
		if found is SpellComponent and (found as SpellComponent).id == CARD:
			card = found as SpellComponent
	_pair = NetPair.new(root, ContentFight.CARD, card, 0.0, 0.0, 0.0, -1, 1, ends)
	# The warm-up pings cross a real wire: give them real time.
	for i in NetPair.WARM_UP:
		_pair.steps += 1
		_pair.host.pump()
		_pair.client.pump()
		OS.delay_msec(1)
	check(_pair.host.start(&"sandbox_requested", 0, 0x5e55) != null, "the host starts")
	for i in TICKS:
		_pair.step()
		OS.delay_msec(2)
	check_equal(_pair.host_ticks(), TICKS, "the host ran a tick every step")
	check(_pair.client.started, "the client took the header (%s)" % _pair.client.problem)
	var began: int = Time.get_ticks_msec()
	while _pair.client_ticks() < _pair.host_ticks() and Time.get_ticks_msec() - began < PATIENCE_MS:
		_pair.step(false, true)
		OS.delay_msec(2)
	check_equal(_pair.client_ticks(), TICKS, "the client played every tick")
	check_equal(_pair.first_parting(), -1, "the client agrees with the host at every tick")
	check_equal([_pair.host.problem, _pair.client.problem], ["", ""], "neither side refused the link")
	# The client's checks cross the wire too.
	began = Time.get_ticks_msec()
	while _pair.host.stats.checks < TICKS / NetChecks.EVERY - 1 and Time.get_ticks_msec() - began < PATIENCE_MS:
		_pair.host.pump()
		OS.delay_msec(2)
	check(_pair.host.stats.checks >= TICKS / NetChecks.EVERY - 1, "the host compared the client's checks (%d)" % _pair.host.stats.checks)
	check_equal([_pair.host.stats.mismatches, _pair.host.parted_tick], [0, -1], "none differed")
	check(_pair.client.stats.presses > 0 and _pair.host_fight.wizard_casts > 0, "the fights fought, the client's presses in them")
