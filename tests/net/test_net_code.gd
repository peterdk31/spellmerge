extends "res://tests/support/suite.gd"
## The codes two players swap (netcode spike S4, docs/milestones/netcode-spike.md; `NetCode`): a
## code comes back as it was written, through a chat that wrapped it too, and pasted text that is
## not one is refused before anything is used: too long, another prefix, another alphabet, text
## that is not plain, lines that are no description's, a candidate that is none, and thousands of
## changed and random texts.

const SDP: String = "v=0\r\no=rtc 2153666630 0 IN IP4 127.0.0.1\r\ns=-\r\nt=0 0\r\na=group:BUNDLE 0\r\nm=application 9 UDP/DTLS/SCTP webrtc-datachannel\r\nc=IN IP4 0.0.0.0\r\na=mid:0\r\na=setup:actpass\r\na=ice-ufrag:WwBM\r\na=ice-pwd:ostGxmVvAYygMbhNejQ6mc\r\na=fingerprint:sha-256 E3:05:27:39\r\n"
## The least a description holds (what a hostile text must have to get past the lines' form).
const LEAST: String = "o\nv=0\nm=application 9 UDP/DTLS/SCTP webrtc-datachannel\na=ice-ufrag:a\na=ice-pwd:b\na=fingerprint:c\na=setup:actpass"
const CANDIDATE: String = "candidate:1 1 UDP 2114977791 192.168.1.20 59921 typ host"


func _code(type: String = NetCode.OFFER) -> NetCode:
	var code := NetCode.new()
	code.type = type
	code.sdp = SDP
	check(code.add_candidate("0", 0, CANDIDATE), "a candidate is added")
	check(code.add_candidate("0", 0, "a=" + CANDIDATE), "and one written as a line")
	return code


## The text of raw lines, packed as a code is (what a hostile machine could hand over).
func _packed(lines: String) -> String:
	return NetCode.PREFIX + Marshalls.raw_to_base64(lines.to_ascii_buffer())


func test_a_code_comes_back_as_it_was_written() -> void:
	for type: String in [NetCode.OFFER, NetCode.ANSWER]:
		var text: String = _code(type).to_text()
		check(text.begins_with(NetCode.PREFIX) and text.length() < 1000, "%s: a short text (%d)" % [type, text.length()])
		var back := NetCode.new()
		check_equal(back.read(text), "", "%s: read back" % type)
		check_equal([back.type, back.sdp], [type, SDP], "%s: the same description" % type)
		check_equal([back.mids, back.indexes, back.names], [PackedStringArray(["0", "0"]), PackedInt32Array([0, 0]), PackedStringArray([CANDIDATE, "a=" + CANDIDATE])], "%s: the same candidates" % type)


func test_a_code_a_chat_wrapped_is_still_read() -> void:
	var text: String = _code().to_text()
	var wrapped: String = "  " + text.substr(0, 40) + "\r\n" + text.substr(40, 60) + " \n\t" + text.substr(100) + "\n"
	var back := NetCode.new()
	check_equal(back.read(wrapped), "", "white space in it is dropped")
	check_equal(back.sdp, SDP, "the same description")


func test_text_that_is_no_code_is_refused() -> void:
	var good: String = _code().to_text()
	var code := NetCode.new()
	var refused: Dictionary[String, String] = {
		"nothing": "",
		"another prefix": "XX1." + good.substr(4),
		"no prefix": good.substr(4),
		"the prefix alone": NetCode.PREFIX,
		"cut short": good.substr(0, good.length() - 3),
		"a character no code has": good.substr(0, 20) + "!" + good.substr(21),
		"padding in the middle": good.substr(0, 20) + "=" + good.substr(21),
		"too long": NetCode.PREFIX + "A".repeat(NetCode.MAX_CHARS),
		"far too long": "A".repeat(NetCode.MAX_CHARS * 3),
		"neither offer nor answer": _packed("x\nv=0"),
		"no description": _packed("o"),
		"a description that starts otherwise": _packed("o\ns=-\nv=0"),
		"a line that is no description's": _packed(LEAST + "\nhello"),
		"a line with an upper-case key": _packed(LEAST + "\nA=1"),
		"an empty line": _packed(LEAST + "\n\ns=-"),
		"a control character": _packed(LEAST + "\ns=\u0007"),
		"a tab in a description": _packed(LEAST + "\ns=a\tb"),
		"a line too long": _packed(LEAST + "\ns=" + "a".repeat(NetCode.MAX_LINE)),
		"too many lines": _packed(LEAST + "\ns=-".repeat(NetCode.MAX_LINES)),
		"a description after a candidate": _packed(LEAST + "\n~0\t0\t%s\ns=-" % CANDIDATE),
		"a candidate with two fields": _packed(LEAST + "\n~0\t0"),
		"a candidate that is none": _packed(LEAST + "\n~0\t0\tsomething else"),
		"a candidate's index no number": _packed(LEAST + "\n~0\tx\t%s" % CANDIDATE),
		"a candidate's index too high": _packed(LEAST + "\n~0\t99\t%s" % CANDIDATE),
		"a candidate's media id no id": _packed(LEAST + "\n~../x\t0\t%s" % CANDIDATE),
		"a description with nothing of a data channel": _packed("o\nv=0\ns=-"),
		"no ice-ufrag": _packed(LEAST.replace("a=ice-ufrag:a\n", "")),
		"no fingerprint": _packed(LEAST.replace("a=fingerprint:c\n", "")),
		"media that is no data channel": _packed(LEAST.replace("m=application", "m=audio")),
		"two media lines": _packed(LEAST + "\nm=application 9 UDP/DTLS/SCTP webrtc-datachannel"),
		"a candidate with a host's name": _packed(LEAST + "\n~0\t0\tcandidate:1 1 UDP 2114977791 example.com 59921 typ host"),
		"a candidate with no address": _packed(LEAST + "\n~0\t0\tcandidate:1 1 UDP 2114977791 999.1.1.1 59921 typ host"),
		"a candidate's port past the last": _packed(LEAST + "\n~0\t0\tcandidate:1 1 UDP 2114977791 10.0.0.1 70000 typ host"),
		"a candidate of no kind": _packed(LEAST + "\n~0\t0\tcandidate:1 1 UDP 2114977791 10.0.0.1 5000 typ other"),
		"a candidate cut short": _packed(LEAST + "\n~0\t0\tcandidate:garbage"),
		"a candidate over another transport": _packed(LEAST + "\n~0\t0\tcandidate:1 1 SCTP 2114977791 10.0.0.1 5000 typ host"),
		"too many candidates": _packed(LEAST + ("\n~0\t0\t%s" % CANDIDATE).repeat(NetCode.MAX_CANDIDATES + 1)),
	}
	for what: String in refused:
		check(code.read(refused[what]) != "", "%s is refused" % what)
		check_equal([code.type, code.sdp, code.mids.size()], ["", "", 0], "%s: and nothing of it is kept" % what)
	check_equal(code.read(_packed(LEAST)), "", "the least a description holds is read")
	for address: String in ["10.0.0.1", "fe80::1c2a:3bff:fe4d:5e6f", "2f3b0a1c-9d4e-4f5a-8b6c-7d8e9f0a1b2c.local"]:
		check_equal(code.read(_packed(LEAST + "\n~0\t0\tcandidate:1 1 udp 2114977791 %s 59921 typ srflx raddr 0.0.0.0 rport 0" % address)), "", "a candidate at %s is read" % address)
	check_equal(code.read(good), "", "a code is still read after")


func test_a_code_that_would_be_refused_is_not_made() -> void:
	var code := NetCode.new()
	check_equal(code.to_text(), "", "no description: no code")
	code.type = NetCode.OFFER
	code.sdp = SDP
	check(not code.add_candidate("0", 0, "not a candidate"), "what is no candidate is left out")
	check(not code.add_candidate("", 0, CANDIDATE), "and one with no media id")
	check(not code.add_candidate("0", 0, CANDIDATE + "\n~0\t0\t" + CANDIDATE), "and one that holds a line break")
	for i in NetCode.MAX_CANDIDATES + 4:
		code.add_candidate("0", 0, CANDIDATE)
	check_equal(code.mids.size(), NetCode.MAX_CANDIDATES, "no more candidates than a code may hold")
	check(code.to_text() != "", "it is still a code")
	code.type = "something else"
	check_equal(code.to_text(), "", "neither an offer nor an answer: no code")
	code.type = NetCode.OFFER
	code.sdp = SDP + "a=x\r\n".repeat(NetCode.MAX_LINES)
	check_equal(code.to_text(), "", "a description too long: no code")


func test_a_code_tells_its_own_addresses_from_those_seen_from_outside() -> void:
	var code := NetCode.new()
	code.type = NetCode.OFFER
	code.sdp = SDP
	check_equal([code.own_count(), code.seen_at()], [0, PackedStringArray()], "no candidate: none of either")
	code.add_candidate("0", 0, CANDIDATE)
	code.add_candidate("0", 0, "a=candidate:2 1 UDP 2114977791 0123abcd-4567-89ab-cdef-0123456789ab.local 59922 typ host")
	code.add_candidate("0", 0, "candidate:3 1 UDP 1677729535 203.0.113.7 59921 typ srflx raddr 0.0.0.0 rport 0")
	code.add_candidate("0", 0, "a=candidate:4 1 UDP 8331263 198.51.100.9 3478 typ relay raddr 203.0.113.7 rport 59921")
	check_equal(code.own_count(), 2, "the host candidates are its own network's, a browser's made-up name too")
	check_equal(code.seen_at(), PackedStringArray(["203.0.113.7"]), "a STUN server's answer is where it is seen from outside")
	check_equal(code.relay_count(), 1, "a relay's address is counted apart (one relay's may be every machine's)")
	code.add_candidate("0", 0, "candidate:5 1 UDP 1845501695 203.0.113.8 61000 typ prflx raddr 192.168.1.20 rport 59921")
	check_equal(code.seen_at(), PackedStringArray(["203.0.113.7", "203.0.113.8"]), "so is where the other machine saw it")
	var back := NetCode.new()
	check_equal(back.read(code.to_text()), "", "read back")
	check_equal([back.own_count(), back.seen_at(), back.relay_count()], [2, code.seen_at(), 1], "the same of the code as the other machine reads it")


## A machine of many networks fills the code with its own addresses before the relay's come
## (they come last): the relay's must still get in, or the one address that always works is lost.
func test_a_full_code_still_takes_a_relays_address() -> void:
	var code := NetCode.new()
	code.type = NetCode.OFFER
	code.sdp = SDP
	code.add_candidate("0", 0, "candidate:1 1 UDP 1677729535 203.0.113.7 59921 typ srflx raddr 0.0.0.0 rport 0")
	for at in NetCode.MAX_CANDIDATES - 1:
		check(code.add_candidate("0", 0, "candidate:2 1 UDP 2114977791 192.168.1.%d 59921 typ host" % (at + 1)), "an own address")
	check(not code.add_candidate("0", 0, "candidate:3 1 UDP 2114977791 192.168.2.1 59921 typ host"), "full: one more of its own is left out")
	check(not code.add_candidate("0", 0, "candidate:4 1 UDP 1677729535 203.0.113.8 59921 typ srflx raddr 0.0.0.0 rport 0"), "and one seen from outside")
	check(code.add_candidate("0", 0, "candidate:5 1 UDP 8331263 198.51.100.9 3478 typ relay raddr 203.0.113.7 rport 59921"), "a relay's is taken")
	check_equal([code.mids.size(), code.own_count(), code.seen_at().size(), code.relay_count()], [NetCode.MAX_CANDIDATES, NetCode.MAX_CANDIDATES - 2, 1, 1], "in the place of the last of its own; the one from outside stays")
	var back := NetCode.new()
	check_equal(back.read(code.to_text()), "", "and the code is still one")
	check_equal(back.relay_count(), 1, "with the relay in it")
	var relays := NetCode.new()
	for at in NetCode.MAX_CANDIDATES:
		relays.add_candidate("0", 0, "candidate:5 1 UDP 8331263 198.51.100.%d 3478 typ relay raddr 0.0.0.0 rport 0" % (at + 1))
	check(not relays.add_candidate("0", 0, "candidate:5 1 UDP 8331263 198.51.100.99 3478 typ relay raddr 0.0.0.0 rport 0"), "with no own address to give up, it is left out")


func test_changed_and_random_texts_never_pass_as_another_code() -> void:
	var good: String = _code().to_text()
	var alphabet: String = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=.~ \n"
	var random := RandomNumberGenerator.new()
	random.seed = 0x5e55
	var code := NetCode.new()
	var taken: int = 0
	for i in 3000:
		var text: String = good
		if i % 3 == 0:
			text = NetCode.PREFIX
			for n in random.randi_range(0, 200):
				text += alphabet[random.randi_range(0, alphabet.length() - 1)]
		else:
			for n in random.randi_range(1, 4):
				var at: int = random.randi_range(0, text.length() - 1)
				text = text.substr(0, at) + alphabet[random.randi_range(0, alphabet.length() - 1)] + text.substr(at + 1)
		if code.read(text) != "":
			check_equal([code.type, code.sdp, code.mids.size()], ["", "", 0], "text %d refused: nothing kept" % i)
			continue
		taken += 1
		# What is taken is still only what a code may hold: plain lines within the limits.
		check(code.sdp.begins_with("v=0\r\n") and code.sdp.length() <= NetCode.MAX_LINES * (NetCode.MAX_LINE + 2), "text %d taken: a description" % i)
		check(code.mids.size() <= NetCode.MAX_CANDIDATES, "text %d taken: its candidates within the limit" % i)
		for name in code.names:
			check(name.contains("candidate:") and not name.contains("\n"), "text %d taken: a candidate is one" % i)
	check(taken < 3000, "most are refused (%d taken)" % taken)
