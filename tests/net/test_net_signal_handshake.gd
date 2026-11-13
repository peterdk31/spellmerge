extends "res://tests/support/suite.gd"
## The handshake through the room server (online lobby L2, docs/milestones/online-lobby.md;
## `NetSignalHandshake`), on a stepped clock with no network: the sockets are stand-ins
## (tests/net/signal_socket.gd), the inner handshakes too (tests/net/loop_handshake.gd), and the
## test plays the server, by a small relay that does what `server/signal/rooms.js` does, or by
## hand where the server is slow, gone or hostile. A host and a guest come to hold one link by a
## room's five characters; three guests each get their own; nothing connects before it is asked;
## a server that is not reached, does not answer or closes says so; a wrong or full room says
## so; what is no message of the server's, or makes no sense when it comes, ends the handshake;
## a guest's bad code costs the host that guest alone.

const FakeSocket := preload("res://tests/net/signal_socket.gd")
const LoopHandshake := preload("res://tests/net/loop_handshake.gd")

const URL: String = "wss://rooms.test/room"
const ROOM: String = "KQ7RM"
const RELAY_TEXT: String = '{"t":"relay","urls":["turn:turn.example.net:3478?transport=udp","turns:turn.example.net:443?transport=tcp"],"username":"a1b2:c3","credential":"pa+ss/w=rd"}'
const RELAY_URLS: PackedStringArray = ["turn:turn.example.net:3478?transport=udp", "turns:turn.example.net:443?transport=tcp"]
const RELAY_USER: String = "a1b2:c3"
const RELAY_PASS: String = "pa+ss/w=rd"

var _now: int = 0
## The inner handshakes' shared tables: the host's nth guest and the nth joining machine share one.
var _tables: Array[Dictionary] = []
var _host_made: int = 0
var _guest_made: int = 0
var _inner: Array[LoopHandshake] = []
## The relay each inner handshake was made with (null: none), the host's and the joining machines', in the order made.
var _host_relays: Array[NetRelay] = []
var _guest_relays: Array[NetRelay] = []


func before_each() -> void:
	_now = 5000
	_tables.clear()
	_host_made = 0
	_guest_made = 0
	_inner.clear()
	_host_relays.clear()
	_guest_relays.clear()


func _table(at: int) -> Dictionary:
	while _tables.size() <= at:
		_tables.append({})
	return _tables[at]


func _handshake(socket: FakeSocket, hosting: bool) -> NetSignalHandshake:
	var made := NetSignalHandshake.new(URL, socket)
	made.clock = func() -> int: return _now
	made.rtc_maker = func(relay: NetRelay) -> NetHandshake:
		(_host_relays if hosting else _guest_relays).append(relay)
		var inner: LoopHandshake
		if hosting:
			inner = LoopHandshake.new(_table(_host_made))
			_host_made += 1
		else:
			inner = LoopHandshake.new(_table(_guest_made))
			_guest_made += 1
		_inner.append(inner)
		return inner
	return made


## What rooms.js does, for one room: the host's socket, the guests' by id.
class Relay:
	extends RefCounted
	var host: FakeSocket = null
	var guests: Dictionary[int, FakeSocket] = {}
	var waiting: Array[FakeSocket] = []
	## Sent to both before a join is told (none: "").
	var relay_text: String = ""

	func step() -> void:
		if host != null:
			host.accept()
			while true:
				var text: String = host.take_sent()
				if text == "":
					break
				if text == '{"t":"open"}':
					host.arrive('{"t":"room","code":"%s"}' % ROOM)
				elif text.begins_with('{"t":"offer","id":'):
					var id: int = int(text.substr(18, 1))
					if guests.has(id):
						guests[id].arrive('{"t":"offer",' + text.substr(20))
		for socket: FakeSocket in waiting.duplicate():
			socket.accept()
			var text: String = socket.take_sent()
			if text == '{"t":"join","code":"%s"}' % ROOM:
				waiting.erase(socket)
				var id: int = 1
				while guests.has(id):
					id += 1
				guests[id] = socket
				if relay_text != "":
					socket.arrive(relay_text)
					host.arrive(relay_text)
				socket.arrive('{"t":"joined"}')
				host.arrive('{"t":"guest","id":%d}' % id)
			elif text != "":
				socket.arrive('{"t":"no_room"}')
		for id: int in guests.keys():
			var socket: FakeSocket = guests[id]
			while true:
				var text: String = socket.take_sent()
				if text == "":
					break
				if text.begins_with('{"t":"answer",'):
					host.arrive('{"t":"answer","id":%d,' % id + text.substr(14))
				elif text == '{"t":"bye"}':
					guests.erase(id)
					socket.drop()
					host.arrive('{"t":"gone","id":%d}' % id)


## Step everything `steps` times, 16 ms each.
func _run(relay: Relay, handshakes: Array[NetSignalHandshake], steps: int = 12) -> void:
	for step in steps:
		_now += 16
		if relay != null:
			relay.step()
		for handshake in handshakes:
			handshake.poll()


## A host with its room open: [the handshake, its socket, the relay].
func _hosted() -> Array:
	var relay := Relay.new()
	relay.host = FakeSocket.new()
	var host: NetSignalHandshake = _handshake(relay.host, true)
	check_equal(_t(host.offer()), "", "the host begins")
	_run(relay, [host], 3)
	check_equal(host.code(), ROOM, "the room's code is the host's code")
	return [host, relay.host, relay]


## A joining machine in the relay's room: [the handshake, its socket].
func _joining(relay: Relay, typed: String = ROOM) -> Array:
	var socket := FakeSocket.new()
	relay.waiting.append(socket)
	var guest: NetSignalHandshake = _handshake(socket, false)
	check_equal(_t(guest.take(typed)), "", "the joining machine takes the room's code")
	return [guest, socket]


func _carries(from: NetLink, to: NetLink, what: String) -> void:
	from.send(PackedByteArray([7, 8, 9]))
	check_equal(to.read(), PackedByteArray([7, 8, 9]), what)


func test_a_host_and_a_guest_hold_one_link_by_the_rooms_code() -> void:
	var hosted: Array = _hosted()
	var host: NetSignalHandshake = hosted[0]
	var relay: Relay = hosted[2]
	var joining: Array = _joining(relay, " kq7rm ")
	var guest: NetSignalHandshake = joining[0]
	var guest_socket: FakeSocket = joining[1]
	check(host.link() == null and guest.link() == null, "no link yet")
	_run(relay, [host, guest])
	check_equal([_t(host.problem()), _t(guest.problem())], ["", ""], "neither failed")
	check(host.link() != null and guest.link() != null, "both hold a link")
	_carries(host.link(), guest.link(), "the host's link reaches the guest's")
	_carries(guest.link(), host.link(), "and back")
	check_equal(guest.code(), "", "the joining machine has no code to hand over")
	check_equal(guest_socket.sent, PackedStringArray(['{"t":"join","code":"KQ7RM"}', '{"t":"answer","code":"%s"}' % LoopHandshake.JOIN_CODE, '{"t":"bye"}']), "what the guest said to the server")
	check_equal(guest_socket.state(), FakeSocket.CLOSED, "the guest's socket is closed: the server's part is done")
	check_equal((hosted[1] as FakeSocket).sent, PackedStringArray(['{"t":"open"}', '{"t":"offer","id":1,"code":"%s"}' % LoopHandshake.HOST_CODE]), "what the host said")
	check_equal((hosted[1] as FakeSocket).state(), FakeSocket.OPEN, "the host's room stays open")
	_run(relay, [host, guest])
	check_equal(_t(host.problem()), "", "the guest's going from the room, once linked, is nothing to the host")
	check_equal(_t(guest.problem()), "", "nor is its own closed socket to the guest")


func test_three_guests_each_get_a_link_of_their_own() -> void:
	var hosted: Array = _hosted()
	var host: NetSignalHandshake = hosted[0]
	var relay: Relay = hosted[2]
	var guests: Array[NetSignalHandshake] = []
	var all: Array[NetSignalHandshake] = [host]
	for at in 3:
		guests.append(_joining(relay)[0])
		all.append(guests[at])
		# One by one, so the nth guest and the host's nth inner handshake are a pair.
		_run(relay, all)
	for at in 3:
		var link: NetLink = host.next_link()
		check(link != null and guests[at].link() != null, "guest %d is linked" % (at + 1))
		_carries(link, guests[at].link(), "the host's link %d reaches guest %d" % [at + 1, at + 1])
	check(host.next_link() == null, "and no fourth")
	check(host.link() != null, "link() is still the first")


func test_nothing_connects_before_it_is_asked() -> void:
	var socket := FakeSocket.new()
	var made: NetSignalHandshake = _handshake(socket, true)
	made.poll()
	check_equal([socket.url, made.code(), _t(made.problem())], ["", "", ""], "made and polled: nothing")
	check_equal(_t(made.offer()), "", "asked")
	check_equal(socket.url, URL + "?relay=1", "the socket goes to the address it was given, and only there, asking for relays")
	check_equal(_t(made.offer()), "it has begun already", "once")


func test_a_room_code_that_is_none_is_refused_and_may_be_typed_again() -> void:
	var socket := FakeSocket.new()
	var guest: NetSignalHandshake = _handshake(socket, false)
	for wrong: String in ["", "KQ7R", "KQ7R0", LoopHandshake.HOST_CODE]:
		var refused: NetWhy = guest.take(wrong)
		check(refused != null and refused.name == OnlineWhy.BAD_ROOM_CODE and refused.facts == {OnlineWhy.LENGTH: 5} and refused.text.contains("5 letters and digits"), "refused, by name and with a code's length: %s" % wrong)
	check_equal([socket.url, _t(guest.problem())], ["", ""], "nothing connected and nothing failed")
	check_equal(_t(guest.take(ROOM)), "", "a room's code is taken")
	check_equal(_t(guest.take(ROOM)), "a code was given already", "once")
	var host: NetSignalHandshake = _handshake(FakeSocket.new(), true)
	host.offer()
	check(_t(host.take(LoopHandshake.JOIN_CODE)) != "", "a host is given no code by hand")
	check_equal(_t(host.problem()), "", "and is none the worse for it")


func test_a_server_that_is_not_reached_says_so() -> void:
	var refused := FakeSocket.new()
	refused.refuses_with = "this build has no room server's address"
	var made: NetSignalHandshake = _handshake(refused, true)
	check_equal(_t(made.offer()), refused.refuses_with, "no address: said at once")
	check_equal(_t(made.problem()), refused.refuses_with, "and it failed")
	check_equal(made.problem().name, OnlineWhy.NO_SERVER, "by name: no room server")

	var dropped := FakeSocket.new()
	made = _handshake(dropped, true)
	made.offer()
	dropped.drop()
	made.poll()
	check_equal(_t(made.problem()), "the room server could not be reached", "the connection refused")

	var silent := FakeSocket.new()
	made = _handshake(silent, false)
	made.take(ROOM)
	_now += NetSignalHandshake.CONNECT_MS - 1
	made.poll()
	check_equal(_t(made.problem()), "", "still connecting just before the limit")
	_now += 1
	made.poll()
	check_equal([_t(made.problem()), made.problem().name], ["the room server could not be reached", OnlineWhy.NO_SERVER], "and given up at it")
	check_equal(silent.state(), FakeSocket.CLOSED, "its socket closed")


func test_a_server_that_does_not_answer_says_so() -> void:
	for hosting: bool in [true, false]:
		var socket := FakeSocket.new()
		var made: NetSignalHandshake = _handshake(socket, hosting)
		if hosting:
			made.offer()
		else:
			made.take(ROOM)
		socket.accept()
		made.poll()
		check_equal(socket.sent.size(), 1, "it said open or join")
		_now += NetSignalHandshake.CONNECT_MS - 1
		made.poll()
		check_equal(_t(made.problem()), "", "waiting just before the limit")
		_now += 1
		made.poll()
		check_equal([_t(made.problem()), made.problem().name], ["the room server did not answer", OnlineWhy.NO_SERVER], "given up at it (hosting: %s)" % hosting)


func test_a_wrong_or_full_or_closed_room_says_so() -> void:
	var said: Dictionary[String, String] = {
		'{"t":"no_room"}': "no room has the code KQ7RM",
		'{"t":"full"}': "the room KQ7RM is full",
		'{"t":"closed"}': "the host closed the room",
	}
	var named: Dictionary[String, Array] = {
		'{"t":"no_room"}': [OnlineWhy.NO_ROOM, {OnlineWhy.ROOM: ROOM}],
		'{"t":"full"}': [OnlineWhy.ROOM_FULL, {OnlineWhy.ROOM: ROOM}],
		'{"t":"closed"}': [OnlineWhy.ROOM_CLOSED, {}],
	}
	for text: String in said:
		var socket := FakeSocket.new()
		var guest: NetSignalHandshake = _handshake(socket, false)
		guest.take(ROOM)
		socket.accept()
		guest.poll()
		socket.arrive(text)
		socket.drop()
		guest.poll()
		check_equal(_t(guest.problem()), said[text], "%s, read though the socket closed with it" % text)
		check_equal([guest.problem().name, guest.problem().facts], named[text], "and by name, with the room's code as its fact")


func test_the_room_closing_ends_the_host_and_leaves_its_links() -> void:
	var hosted: Array = _hosted()
	var host: NetSignalHandshake = hosted[0]
	var relay: Relay = hosted[2]
	var guest: NetSignalHandshake = _joining(relay)[0]
	_run(relay, [host, guest])
	var link: NetLink = host.link()
	check(link != null and link.is_open(), "linked")
	(hosted[1] as FakeSocket).arrive('{"t":"closed"}')
	(hosted[1] as FakeSocket).drop()
	_run(null, [host, guest], 2)
	check_equal(_t(host.problem()), "the room is closed", "the host is told")
	check(host.link() == link and link.is_open(), "the link it handed over is its holder's, still open")
	_carries(link, guest.link(), "and still carries")


func test_what_is_no_message_or_makes_no_sense_ends_the_handshake() -> void:
	var offer: String = '{"t":"offer","code":"%s"}' % LoopHandshake.HOST_CODE
	var answer: String = '{"t":"answer","id":1,"code":"%s"}' % LoopHandshake.JOIN_CODE
	# For a host with its room open, and a guest that has joined: what must end each.
	var for_host: PackedStringArray = ["nonsense", '{"t":"room","code":"ABCDE"}', '{"t":"joined"}', offer, '{"t":"no_room"}', '{"t":"full"}', '{"t":"guest","id":4}', '{"t":"guest","id":1} ']
	var for_guest: PackedStringArray = ["nonsense", '{"t":"joined"}', '{"t":"room","code":"ABCDE"}', '{"t":"guest","id":1}', answer, '{"t":"gone","id":1}', '{"t":"offer","code":"res://x.gd"}']
	for text: String in for_host:
		var hosted: Array = _hosted()
		(hosted[1] as FakeSocket).arrive(text)
		(hosted[0] as NetSignalHandshake).poll()
		check_equal(_t((hosted[0] as NetSignalHandshake).problem()), "the room server said something that is no message of its", "a host sent %s" % text)
		check_equal((hosted[1] as FakeSocket).state(), FakeSocket.CLOSED, "its socket closed")
	for text: String in for_guest:
		var socket := FakeSocket.new()
		var guest: NetSignalHandshake = _handshake(socket, false)
		guest.take(ROOM)
		socket.accept()
		guest.poll()
		socket.arrive('{"t":"joined"}')
		socket.arrive(text)
		guest.poll()
		check_equal(_t(guest.problem()), "the room server said something that is no message of its", "a guest sent %s" % text)
	# Out of order: an offer before the room took the guest, a second offer, a guest named twice,
	# a guest named before the room has its code.
	var early := FakeSocket.new()
	var guest: NetSignalHandshake = _handshake(early, false)
	guest.take(ROOM)
	early.accept()
	guest.poll()
	early.arrive(offer)
	guest.poll()
	check(_t(guest.problem()).contains("no message"), "an offer before joined")
	check_equal(_inner.size(), 0, "and no inner handshake was made for it")

	var twice := FakeSocket.new()
	# The first offer is one the inner handshake takes (a host made it).
	_table(0)[&"ends"] = NetLoopback.pair()
	guest = _handshake(twice, false)
	guest.take(ROOM)
	twice.accept()
	guest.poll()
	twice.arrive('{"t":"joined"}')
	twice.arrive(offer)
	guest.poll()
	check_equal(_t(guest.problem()), "", "the first offer is taken")
	twice.arrive(offer)
	guest.poll()
	check(_t(guest.problem()).contains("no message"), "a second offer")

	var hosted: Array = _hosted()
	(hosted[1] as FakeSocket).arrive('{"t":"guest","id":2}')
	(hosted[1] as FakeSocket).arrive('{"t":"guest","id":2}')
	(hosted[0] as NetSignalHandshake).poll()
	check(_t((hosted[0] as NetSignalHandshake).problem()).contains("no message"), "a guest named twice")

	var roomless := FakeSocket.new()
	var host: NetSignalHandshake = _handshake(roomless, true)
	host.offer()
	roomless.accept()
	host.poll()
	roomless.arrive('{"t":"guest","id":1}')
	host.poll()
	check(_t(host.problem()).contains("no message"), "a guest before the room")


func test_a_guests_bad_code_costs_the_host_that_guest_alone() -> void:
	var hosted: Array = _hosted()
	var host: NetSignalHandshake = hosted[0]
	var socket: FakeSocket = hosted[1]
	var relay: Relay = hosted[2]
	# Guest 1, played by hand: it answers with a code the inner handshake breaks on.
	socket.arrive('{"t":"guest","id":1}')
	_run(null, [host], 4)
	check(socket.sent[-1].begins_with('{"t":"offer","id":1,'), "guest 1 was offered")
	socket.arrive('{"t":"answer","id":1,"code":"%s"}' % LoopHandshake.BROKEN_CODE)
	_run(null, [host], 2)
	check_equal(_t(host.problem()), "", "the host goes on")
	# An answer for nobody, and a guest gone that was never there, are nothing.
	socket.arrive('{"t":"answer","id":1,"code":"%s"}' % LoopHandshake.JOIN_CODE)
	socket.arrive('{"t":"answer","id":3,"code":"%s"}' % LoopHandshake.JOIN_CODE)
	socket.arrive('{"t":"gone","id":1}')
	socket.arrive('{"t":"gone","id":3}')
	_run(null, [host], 2)
	check_equal(_t(host.problem()), "", "nothing")
	check(host.link() == null, "and no link came of it")
	# The next guest takes the freed id and links.
	socket.taken = socket.sent.size()
	_guest_made = 1
	var guest: NetSignalHandshake = _joining(relay)[0]
	_run(relay, [host, guest])
	check(host.link() != null and guest.link() != null, "another guest links after it")


func test_an_answer_before_the_offer_went_out_is_not_taken() -> void:
	var hosted: Array = _hosted()
	var host: NetSignalHandshake = hosted[0]
	var socket: FakeSocket = hosted[1]
	socket.arrive('{"t":"guest","id":1}')
	socket.arrive('{"t":"answer","id":1,"code":"%s"}' % LoopHandshake.JOIN_CODE)
	host.poll()
	check_equal(_t(host.problem()), "", "no fault of the room's")
	_run(null, [host], 6)
	check(host.link() == null, "but no link without an answer to the offer that was sent")


func test_a_guest_gone_before_its_link_is_let_go() -> void:
	var hosted: Array = _hosted()
	var host: NetSignalHandshake = hosted[0]
	var socket: FakeSocket = hosted[1]
	socket.arrive('{"t":"guest","id":1}')
	_run(null, [host], 4)
	socket.arrive('{"t":"gone","id":1}')
	socket.arrive('{"t":"guest","id":1}')
	_run(null, [host], 4)
	check_equal(_t(host.problem()), "", "the id is given again with no fault")
	check_equal(_inner.size(), 2, "a new inner handshake for the new guest")
	var offers: int = 0
	for text: String in socket.sent:
		offers += 1 if text.begins_with('{"t":"offer","id":1,') else 0
	check_equal(offers, 2, "and its own offer")


func test_a_joining_machine_gives_up_after_a_while_and_a_host_lets_a_slow_guest_go() -> void:
	var socket := FakeSocket.new()
	var guest: NetSignalHandshake = _handshake(socket, false)
	guest.take(ROOM)
	socket.accept()
	guest.poll()
	socket.arrive('{"t":"joined"}')
	guest.poll()
	_now += NetSignalHandshake.JOIN_MS - 1
	guest.poll()
	check_equal(_t(guest.problem()), "", "waiting for the host's offer just before the limit")
	_now += 1
	guest.poll()
	check_equal([_t(guest.problem()), guest.problem().name], ["the host's machine was not found in time", OnlineWhy.HOST_NOT_FOUND], "given up at it")

	var hosted: Array = _hosted()
	var host: NetSignalHandshake = hosted[0]
	(hosted[1] as FakeSocket).arrive('{"t":"guest","id":1}')
	_run(null, [host], 4)
	_now += NetSignalHandshake.GUEST_MS
	host.poll()
	check_equal(_t(host.problem()), "", "the room goes on")
	(hosted[1] as FakeSocket).arrive('{"t":"guest","id":1}')
	host.poll()
	check_equal(_t(host.problem()), "", "and the slow guest's id is free again")


func test_giving_up_closes_the_socket_and_what_was_on_its_way() -> void:
	var hosted: Array = _hosted()
	var host: NetSignalHandshake = hosted[0]
	var socket: FakeSocket = hosted[1]
	socket.arrive('{"t":"guest","id":1}')
	_run(null, [host], 4)
	host.close()
	check_equal([socket.state(), _t(host.problem())], [FakeSocket.CLOSED, "given up"], "closed")
	var sent: int = socket.sent.size()
	socket.arrive('{"t":"guest","id":2}')
	_run(null, [host], 4)
	check_equal([socket.sent.size(), _inner.size(), host.code()], [sent, 1, ROOM], "and nothing more is said or made")


func test_a_machine_that_cannot_link_fails_at_the_first_guest() -> void:
	var socket := FakeSocket.new()
	var host := NetSignalHandshake.new(URL, socket)
	host.clock = func() -> int: return _now
	# The base handshake links nothing (as a build without WebRTC).
	host.rtc_maker = func(_relay: NetRelay) -> NetHandshake: return NetHandshake.new()
	host.offer()
	socket.accept()
	host.poll()
	socket.arrive('{"t":"room","code":"KQ7RM"}')
	socket.arrive('{"t":"guest","id":1}')
	host.poll()
	check_equal([_t(host.problem()), host.problem().name], ["this build cannot link two machines", OnlineWhy.CANNOT_LINK], "said as the inner handshake says it")
	check_equal(socket.state(), FakeSocket.CLOSED, "and the room is closed")


func test_a_guest_that_leaves_the_server_once_it_answered_still_links() -> void:
	# The joining machine holds its link a moment before the host holds its own, and leaves the
	# server at once: the host hears it gone while it is still linking with it.
	var hosted: Array = _hosted()
	var host: NetSignalHandshake = hosted[0]
	var socket: FakeSocket = hosted[1]
	socket.arrive('{"t":"guest","id":1}')
	_run(null, [host], 4)
	check(socket.sent[-1].begins_with('{"t":"offer","id":1,'), "guest 1 was offered")
	var guest := LoopHandshake.new(_table(0))
	check_equal(_t(guest.take(LoopHandshake.HOST_CODE)), "", "the joining machine's inner handshake takes the offer")
	socket.arrive('{"t":"answer","id":1,"code":"%s"}' % LoopHandshake.JOIN_CODE)
	socket.arrive('{"t":"gone","id":1}')
	socket.arrive('{"t":"guest","id":1}')
	_run(null, [host], 4)
	check_equal(_t(host.problem()), "", "gone from the server after its answer, and its id given to the next: no fault")
	var link: NetLink = host.next_link()
	check(link != null and link.is_open(), "the host holds its link to it all the same")
	check(host.next_link() == null, "once")


func test_a_joining_machine_hands_its_link_over_once_by_next_link() -> void:
	var hosted: Array = _hosted()
	var host: NetSignalHandshake = hosted[0]
	var guest: NetSignalHandshake = _joining(hosted[2])[0]
	check(guest.next_link() == null, "none before it is linked")
	_run(hosted[2], [host, guest])
	var link: NetLink = guest.next_link()
	check(link != null and link == guest.link(), "the link, as whoever holds several machines asks for it")
	check(guest.next_link() == null, "once")



func _is_the_relay(relay: NetRelay) -> bool:
	return relay != null and relay.urls == RELAY_URLS and relay.username == RELAY_USER and relay.credential == RELAY_PASS


func test_a_relay_the_server_hands_over_goes_to_the_inner_handshakes() -> void:
	var hosted: Array = _hosted()
	var host: NetSignalHandshake = hosted[0]
	var relay: Relay = hosted[2]
	relay.relay_text = RELAY_TEXT
	var guest: NetSignalHandshake = _joining(relay)[0]
	_run(relay, [host, guest])
	check(host.link() != null and guest.link() != null, "both hold a link")
	check(_host_relays.size() == 1 and _is_the_relay(_host_relays[0]), "the host's inner handshake was given the relay")
	check(_guest_relays.size() == 1 and _is_the_relay(_guest_relays[0]), "and the guest's")
	# A join past the server's limit comes with none: the host keeps the last for it.
	relay.relay_text = ""
	var second: NetSignalHandshake = _joining(relay)[0]
	_run(relay, [host, guest, second])
	check(second.link() != null, "the second guest is linked")
	check(_host_relays.size() == 2 and _is_the_relay(_host_relays[1]), "the host's second inner handshake with the last relay")
	check(_guest_relays.size() == 2 and _guest_relays[1] == null, "the second guest's with none")


func test_no_relay_from_the_server_means_none_is_given() -> void:
	var hosted: Array = _hosted()
	var guest: NetSignalHandshake = _joining(hosted[2])[0]
	_run(hosted[2], [hosted[0], guest])
	check(guest.link() != null, "linked")
	check_equal([_host_relays, _guest_relays], [[null] as Array[NetRelay], [null] as Array[NetRelay]], "each inner handshake with no relay")


## The server's form and the game's may drift apart one day: that must cost the relay, not the room.
func test_a_relay_out_of_form_is_no_relay_and_the_machines_still_link() -> void:
	var hosted: Array = _hosted()
	var host: NetSignalHandshake = hosted[0]
	var relay: Relay = hosted[2]
	relay.relay_text = '{"t":"relay","urls":["turn:a.b:53?transport=udp"],"username":"u","credential":"p","new":1}'
	var guest: NetSignalHandshake = _joining(relay)[0]
	_run(relay, [host, guest])
	check_equal([_t(host.problem()), _t(guest.problem())], ["", ""], "neither failed")
	check(host.link() != null and guest.link() != null, "both hold a link")
	check_equal([_host_relays, _guest_relays], [[null] as Array[NetRelay], [null] as Array[NetRelay]], "with no relay")


func test_a_relay_out_of_its_place_ends_the_handshake() -> void:
	# The host: before its room is given.
	var socket := FakeSocket.new()
	var host: NetSignalHandshake = _handshake(socket, true)
	host.offer()
	socket.accept()
	host.poll()
	socket.arrive(RELAY_TEXT)
	host.poll()
	check_equal(_t(host.problem()), "the room server said something that is no message of its", "a relay before the room")
	# A joining machine: after it was told it is in.
	var guest_socket := FakeSocket.new()
	var guest: NetSignalHandshake = _handshake(guest_socket, false)
	guest.take(ROOM)
	guest_socket.accept()
	guest.poll()
	guest_socket.arrive('{"t":"joined"}')
	guest.poll()
	check_equal(_t(guest.problem()), "", "in the room")
	guest_socket.arrive(RELAY_TEXT)
	guest.poll()
	check_equal(_t(guest.problem()), "the room server said something that is no message of its", "a relay after joined")


## What a handshake said went wrong, in its words for the log ("": nothing).
func _t(why: NetWhy) -> String:
	return why.text if why != null else ""
