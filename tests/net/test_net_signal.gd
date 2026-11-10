extends "res://tests/support/suite.gd"
## What the game and the room server say to each other (online lobby L2,
## docs/milestones/online-lobby.md; `NetSignal`): each of the server's messages is read as it is
## written, the game's own are written as the server takes them, and text that is none of the
## server's forms is refused whole: another order, a space, a key more, a code that is no room's
## or no machine's, and thousands of changed and random texts.

const NET_CODE: String = "SM1.aG9zdA=="


func test_each_message_of_the_servers_is_read() -> void:
	var m := NetSignal.new()
	var forms: Dictionary[String, Array] = {
		'{"t":"room","code":"KQ7RM"}': [NetSignal.ROOM, "KQ7RM", 0],
		'{"t":"guest","id":1}': [NetSignal.GUEST, "", 1],
		'{"t":"guest","id":3}': [NetSignal.GUEST, "", 3],
		'{"t":"answer","id":2,"code":"%s"}' % NET_CODE: [NetSignal.ANSWER, NET_CODE, 2],
		'{"t":"gone","id":3}': [NetSignal.GONE, "", 3],
		'{"t":"joined"}': [NetSignal.JOINED, "", 0],
		'{"t":"offer","code":"%s"}' % NET_CODE: [NetSignal.OFFER, NET_CODE, 0],
		'{"t":"no_room"}': [NetSignal.NO_ROOM, "", 0],
		'{"t":"full"}': [NetSignal.FULL, "", 0],
		'{"t":"closed"}': [NetSignal.CLOSED, "", 0],
	}
	for text: String in forms:
		check(m.read(text), "%s is read" % text)
		check_equal([m.kind, m.code, m.id], forms[text], "%s: what it holds" % text)
	for kind: StringName in NetSignal.FOR_HOST + NetSignal.FOR_GUEST:
		var tried: bool = false
		for text: String in forms:
			tried = tried or forms[text][0] == kind
		check(tried, "%s is tried" % kind)


func test_a_code_of_the_longest_kind_is_read() -> void:
	var m := NetSignal.new()
	var long: String = NetCode.PREFIX + "A".repeat(NetCode.MAX_CHARS - NetCode.PREFIX.length())
	check(m.read('{"t":"offer","code":"%s"}' % long) and m.code == long, "a code of NetCode's most characters")
	check(not m.read('{"t":"offer","code":"%sA"}' % long), "one more is refused")
	check(NetSignal.offer(1, long).length() <= NetSignal.MAX_CHARS, "and it fits a message to the server")


func test_text_that_is_no_message_is_refused_and_nothing_is_held() -> void:
	var m := NetSignal.new()
	var refused: PackedStringArray = [
		"",
		"{}",
		"closed",
		'{"t":"closed"',
		'{"t":"closed"} ',
		' {"t":"closed"}',
		'{"t": "closed"}',
		'{"t":"closed","more":1}',
		'{"t":"Closed"}',
		'{"t":"open"}',
		'{"t":"bye"}',
		'{"t":"join","code":"KQ7RM"}',
		'{"code":"KQ7RM","t":"room"}',
		'{"t":"room"}',
		'{"t":"room","code":""}',
		'{"t":"room","code":"KQ7R"}',
		'{"t":"room","code":"KQ7RMM"}',
		'{"t":"room","code":"kq7rm"}',
		'{"t":"room","code":"KQ7R0"}',
		'{"t":"room","code":"KQ7R\\u004d"}',
		'{"t":"room","code":"KQ7RM","id":1}',
		'{"t":"room","code":"KQ"}"}',
		'{"t":"room","code":"KQ7RMxx',
		'{"t":"room","code":"KQ7RM"]',
		'{"t":"guest","id":1x',
		'{"t":"gone","id":2]',
		'{"t":"offer","code":"SM1.aG9zXX',
		'{"t":"answer","id":1,"code":"SM1.aG9zXX',
		'{"t":"guest"}',
		'{"t":"guest","id":0}',
		'{"t":"guest","id":4}',
		'{"t":"guest","id":-1}',
		'{"t":"guest","id":01}',
		'{"t":"guest","id":1.0}',
		'{"t":"guest","id":"1"}',
		'{"t":"guest","id":1,"code":"%s"}' % NET_CODE,
		'{"t":"gone","id":11}',
		'{"t":"offer"}',
		'{"t":"offer","code":""}',
		'{"t":"offer","code":"SM1."}',
		'{"t":"offer","code":"SM1.=="}',
		'{"t":"offer","code":"XX1.aG9zdA=="}',
		'{"t":"offer","code":"SM1.aG9z dA=="}',
		'{"t":"offer","code":"SM1.aG9z\\"dA=="}',
		'{"t":"offer","code":"SM1.aG9z","id":1}',
		'{"t":"offer","code":"SM1.aG9z"}{"t":"offer","code":"SM1.aG9z"}',
		'{"t":"offer","id":1,"code":"%s"}' % NET_CODE,
		'{"t":"offer","code":"SM1.aG=9zdA"}',
		'{"t":"offer","code":"SM1.aG9zd==="}',
		'{"t":"answer","code":"%s"}' % NET_CODE,
		'{"t":"answer","id":4,"code":"%s"}' % NET_CODE,
		'{"t":"answer","id":12,"code":"%s"}' % NET_CODE,
		'{"t":"answer","id":1,"code":"res://x"}',
		'{"t":"answer","id":1,"code":"%s","more":"x"}' % NET_CODE,
		'{"t":"closed"}' + " ".repeat(NetSignal.MAX_CHARS),
	]
	for text: String in refused:
		check(m.read('{"t":"room","code":"KQ7RM"}'), "a good one first")
		check(not m.read(text), "refused: %s" % text.substr(0, 60))
		check_equal([m.kind, m.code, m.id], [&"", "", 0], "nothing is held of %s" % text.substr(0, 60))


func test_the_games_messages_are_written_as_the_server_takes_them() -> void:
	check_equal(NetSignal.open(), '{"t":"open"}', "open")
	check_equal(NetSignal.bye(), '{"t":"bye"}', "bye")
	check_equal(NetSignal.join("KQ7RM"), '{"t":"join","code":"KQ7RM"}', "join")
	check_equal(NetSignal.offer(2, NET_CODE), '{"t":"offer","id":2,"code":"%s"}' % NET_CODE, "offer")
	check_equal(NetSignal.answer(NET_CODE), '{"t":"answer","code":"%s"}' % NET_CODE, "answer")
	check_equal(NetSignal.join('KQ7R"'), "", "no room code: nothing is written")
	check_equal(NetSignal.join("kq7rm"), "", "lower case is not the server's")
	check_equal([NetSignal.offer(0, NET_CODE), NetSignal.offer(4, NET_CODE)], ["", ""], "no guest's id")
	check_equal([NetSignal.offer(1, 'SM1.a"b'), NetSignal.answer("hello"), NetSignal.answer("")], ["", "", ""], "no machine's code")


func test_a_real_code_of_net_code_passes() -> void:
	var made := NetCode.new()
	made.type = NetCode.OFFER
	made.sdp = "v=0\r\nm=application 9 UDP/DTLS/SCTP webrtc-datachannel\r\na=setup:actpass\r\na=ice-ufrag:WwBM\r\na=ice-pwd:ostGxmVvAYygMbhNejQ6mc\r\na=fingerprint:sha-256 E3:05\r\n"
	check(made.add_candidate("0", 0, "candidate:1 1 UDP 2114977791 192.168.1.20 59921 typ host"), "a candidate")
	var text: String = made.to_text()
	check(text != "" and NetSignal.is_net_code(text), "NetCode's own text is a machine's code here")
	var m := NetSignal.new()
	check(m.read('{"t":"offer","code":"%s"}' % text), "and crosses in an offer")
	check_equal(NetCode.new().read(m.code), "", "and is read by NetCode as it was")


func test_a_typed_room_code_is_tidied() -> void:
	check_equal(NetSignal.typed_room_code("KQ7RM"), "KQ7RM", "as it is")
	check_equal(NetSignal.typed_room_code(" kq7 rm\n"), "KQ7RM", "spaces dropped, capitals made")
	check_equal(NetSignal.typed_room_code("kq-7rm"), "KQ7RM", "a dash too")
	for wrong: String in ["", "KQ7R", "KQ7RMM", "KQ7R0", "KQ7RO", "KQ7R!", "K".repeat(200), "SM1.aG9zdA=="]:
		check_equal(NetSignal.typed_room_code(wrong), "", "no room code: %s" % wrong.substr(0, 20))
	check_equal(NetSignal.ALPHABET.length(), 27, "27 characters")
	for hard: String in ["0", "O", "1", "I", "L", "5", "S", "U", "V"]:
		check(not NetSignal.ALPHABET.contains(hard), "%s is in no code" % hard)


func test_a_fuzz_of_changed_and_random_texts() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261110
	var good: PackedStringArray = [
		'{"t":"room","code":"KQ7RM"}',
		'{"t":"guest","id":1}',
		'{"t":"answer","id":2,"code":"%s"}' % NET_CODE,
		'{"t":"gone","id":3}',
		'{"t":"joined"}',
		'{"t":"offer","code":"%s"}' % NET_CODE,
		'{"t":"closed"}',
	]
	var m := NetSignal.new()
	var taken: int = 0
	for round in 6000:
		var text: String = good[rng.randi() % good.size()]
		match rng.randi() % 4:
			0:
				var at: int = rng.randi() % text.length()
				text = text.substr(0, at) + char(rng.randi_range(1, 300)) + text.substr(at + 1)
			1:
				text = text.substr(0, rng.randi() % text.length())
			2:
				var at: int = rng.randi() % text.length()
				text = text.substr(0, at) + char(rng.randi_range(32, 126)) + text.substr(at)
			3:
				text = ""
				for at in rng.randi_range(0, 60):
					text += char(rng.randi_range(1, 300))
		if not m.read(text):
			check_equal([m.kind, m.code, m.id], [&"", "", 0], "a refused text leaves nothing")
			continue
		# What is taken all the same (a changed character that is still of the form) holds only
		# what the forms allow.
		taken += 1
		check((NetSignal.FOR_HOST + NetSignal.FOR_GUEST).has(m.kind), "a kind of the server's")
		check(m.id >= 0 and m.id <= NetSignal.MAX_GUESTS, "an id within the room")
		check(m.code == "" or NetSignal.is_room_code(m.code) or NetSignal.is_net_code(m.code), "a code of one of the two forms")
		check(not m.code.contains('"') and not m.code.contains("\\"), "nothing escaped")
	check(taken < 600, "hardly any changed text is still a message (%d of 6000)" % taken)
