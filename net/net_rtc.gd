class_name NetRtc
extends NetHandshake
## The handshake over WebRTC (netcode spike S4, docs/milestones/netcode-spike.md): a browser's own
## WebRTC or the desktop builds' extension (`NetWebRTC.available()`), through the engine's one
## API. Its codes are `NetCode`s, its link a `NetRtcLink` over one data channel, ordered and
## reliable.
##
## - **Nothing connects anywhere until `offer` or `take`** (a player pressed Host or Join): the
##   peer is made there. From then this machine asks the STUN servers it was given for its
##   address as the internet sees it (the public one in STUN unless told otherwise; they see the
##   address and nothing of the game), and it talks to the machine whose code was pasted. Nothing
##   listens for strangers.
## - **A relay may be given** (a `NetRelay`: a TURN server and its short-lived credential, from
##   whoever hands them out): WebRTC then also gathers an address on it and uses it only where the two
##   machines find no direct way. It sees that the two talk and how much, never what: the channel
##   is encrypted end to end. Codes typed by hand have none.
## - **One code each way:** a machine's code is shown once its candidates are gathered, or
##   GATHER_MS after its description was made with what was gathered by then (a STUN server that
##   does not answer must not hold the code back for ever). Never with no candidate in it: such a
##   code reaches nobody, so with none by then the handshake fails and says so.
## - **The channel is agreed beforehand** (the same id on both sides), so neither side waits for
##   the other to announce it.
## - **A pasted code** is read by `NetCode` (strictly) and must be the kind this side expects
##   before WebRTC sees any of it; a code refused there changes nothing, so the player may paste
##   again. A code WebRTC itself refuses ends the handshake (`problem`): its peer cannot go on.
## - **A link that is never made says why, as far as the two codes tell** (`why_no_link`): a relay
##   that did not get through either, both machines behind one router, a machine that never
##   learnt its address from outside, or two networks with no direct way between them (which only
##   a relay gets through), with the count of each machine's addresses, and whether this
##   machine's code was made before its gathering was done (a STUN answer later than GATHER_MS
##   is in no code). Never an address itself: what is said may be on a shared screen.
## - **A failure is a `NetWhy`:** a name the HUD words and its facts; the words here are the log's.
## - **The clock is given** (milliseconds; the engine's unless told), as the sessions' is.
##
## With `NetRtcLink`, the only script that names the engine's WebRTC classes.

## The public STUN server asked for this machine's address (the owner's decision 3, 2026-11-10).
const STUN: PackedStringArray = ["stun:stun.l.google.com:19302"]
## The data channel both sides open, by id.
const CHANNEL: String = "spellmerge"
const CHANNEL_ID: int = 1
## A code is shown at the latest this long after its description was made.
const GATHER_MS: int = 4000
## The host, given the code that came back, finds the other machine within this long or never.
## (The joining machine has no such limit: its code still has to travel to the host by hand, and
## its player may give up with Cancel.)
const LINK_MS: int = 30000

## The time in milliseconds (a test's own; the engine's clock otherwise).
var clock: Callable = Callable()

var _stun: PackedStringArray
var _relay: NetRelay
var _peer: WebRTCPeerConnection = null
var _channel: WebRTCDataChannel = null
var _hosting: bool = false
## This machine's code as it is gathered, and its text once shown.
var _mine: NetCode = NetCode.new()
var _code: String = ""
## The other machine's code, once taken.
var _theirs: NetCode = null
## When this machine's description was made, and when the other's code was taken (-1: not yet).
## The gathering's state was seen done at an earlier poll (its last candidates are in by now).
var _gathered: bool = false
var _described_at: int = -1
var _taken_at: int = -1
var _link: NetRtcLink = null
var _problem: NetWhy = null
## This machine's code was made at GATHER_MS, before the gathering was done: an address as seen
## from outside that comes after is in no code.
var _late: bool = false


## `stun_servers`: the servers asked for this machine's address (none: only machines on one
## network, or in one process, find each other). `relay`: a relay to link through where there is no
## direct way, or null.
func _init(stun_servers: PackedStringArray = STUN, relay: NetRelay = null) -> void:
	_stun = stun_servers
	_relay = relay


func offer() -> NetWhy:
	if _peer != null:
		return NetWhy.new(OnlineWhy.NOT_NOW, "it has begun already")
	var why: NetWhy = _begin(true)
	if why == null and _peer.create_offer() != OK:
		why = _fail(OnlineWhy.SETUP_FAILED, "WebRTC made no offer")
	return why


## A pasted code of this kind starts as `NetCode`'s do.
func takes(typed: String) -> bool:
	return typed.strip_edges().begins_with(NetCode.PREFIX)


func take(code: String) -> NetWhy:
	if _problem != null:
		return _problem
	if _taken_at >= 0:
		return NetWhy.new(OnlineWhy.NOT_NOW, "a code was given already")
	var theirs := NetCode.new()
	var unread: String = theirs.read(code)
	if unread != "":
		return NetWhy.new(OnlineWhy.BAD_CODE, unread)
	if _peer != null and not _hosting:
		return NetWhy.new(OnlineWhy.NOT_NOW, "a code was given already")
	if _hosting and theirs.type != NetCode.ANSWER:
		return NetWhy.new(OnlineWhy.HOSTS_CODE, "this is a host's code; the host needs the code the joining player got back")
	if _hosting and _code == "":
		return NetWhy.new(OnlineWhy.NOT_NOW, "this machine's own code is not made yet")
	if not _hosting and theirs.type != NetCode.OFFER:
		return NetWhy.new(OnlineWhy.JOINERS_CODE, "this is a joining player's code; Join needs the host's")
	if _peer == null:
		var why: NetWhy = _begin(false)
		if why != null:
			return why
	# For an offer the peer makes its answer by itself (`_on_described`).
	if _peer.set_remote_description(theirs.type, theirs.sdp) != OK:
		return _fail(OnlineWhy.BAD_CODE, "WebRTC did not take the code")
	for at in theirs.mids.size():
		# One candidate it cannot use is not the end: the others may do.
		_peer.add_ice_candidate(theirs.mids[at], theirs.indexes[at], theirs.names[at])
	_theirs = theirs
	_taken_at = _now()
	return null


func code() -> String:
	return _code


func poll() -> void:
	if _peer == null or _problem != null or _link != null:
		return
	_peer.poll()
	if _code == "" and _described_at >= 0:
		# The candidates come as signals, handed over by the peer's poll above, while the
		# gathering's state is read as it is now: the last of them may still be on its way when the
		# state says done. So the code is made one poll after the state was first seen done.
		var late: bool = _now() - _described_at >= GATHER_MS
		if _gathered or late:
			if _mine.mids.is_empty():
				if late:
					_fail(OnlineWhy.NO_ADDRESS, "this machine found no network address to be reached at")
				return
			_code = _mine.to_text()
			if _code == "":
				_fail(OnlineWhy.SETUP_FAILED, "this machine's code could not be made")
				return
			_late = not _gathered
		elif _peer.get_gathering_state() == WebRTCPeerConnection.GATHERING_STATE_COMPLETE:
			_gathered = true
	if _channel.get_ready_state() == WebRTCDataChannel.STATE_OPEN:
		_link = NetRtcLink.new(_peer, _channel)
		return
	var state: int = _peer.get_connection_state()
	if state == WebRTCPeerConnection.STATE_FAILED or state == WebRTCPeerConnection.STATE_CLOSED:
		_fail_no_link(false)
	elif _hosting and _taken_at >= 0 and _now() - _taken_at >= LINK_MS:
		_fail_no_link(true)


func link() -> NetLink:
	return _link


func problem() -> NetWhy:
	return _problem


func close() -> void:
	if _problem == null:
		_problem = NetWhy.new(OnlineWhy.NOT_NOW, "given up")
	if _peer != null and _link == null:
		_peer.close()


## Why two machines whose codes were `mine` and `theirs` (null: not there yet) made no link, as
## far as the codes tell: NO_LINK with its cause and how many addresses each code held (on its
## own network, as seen from outside it, and on a relay). No address is named. `in_time`: nothing
## came within the time allowed (false: WebRTC tried and failed). `late`: this machine's code was
## made before its gathering was done (GATHER_MS), so an address from outside that came after is
## in no code.
static func why_no_link(mine: NetCode, theirs: NetCode, in_time: bool = false, late: bool = false) -> NetWhy:
	var words: String = "the two machines did not find each other in time" if in_time else "the two machines could not reach each other"
	var facts: Dictionary = {OnlineWhy.CAUSE: OnlineWhy.CAUSE_UNKNOWN, OnlineWhy.IN_TIME: in_time, OnlineWhy.LATE: late}
	if mine == null or theirs == null:
		return NetWhy.new(OnlineWhy.NO_LINK, words, facts)
	var my_seen: PackedStringArray = mine.seen_at()
	var their_seen: PackedStringArray = theirs.seen_at()
	var cause: StringName = OnlineWhy.CAUSE_TWO_NETWORKS
	if mine.relay_count() > 0 or theirs.relay_count() > 0:
		cause = OnlineWhy.CAUSE_RELAY
	elif my_seen.is_empty():
		cause = OnlineWhy.CAUSE_HIDDEN_HERE
	elif their_seen.is_empty():
		cause = OnlineWhy.CAUSE_HIDDEN_THERE
	else:
		for address: String in my_seen:
			if their_seen.has(address):
				cause = OnlineWhy.CAUSE_ONE_NETWORK
				break
	facts[OnlineWhy.CAUSE] = cause
	facts[OnlineWhy.MINE_OWN] = mine.own_count()
	facts[OnlineWhy.MINE_OUTSIDE] = my_seen.size()
	facts[OnlineWhy.MINE_RELAY] = mine.relay_count()
	facts[OnlineWhy.THEIRS_OWN] = theirs.own_count()
	facts[OnlineWhy.THEIRS_OUTSIDE] = their_seen.size()
	facts[OnlineWhy.THEIRS_RELAY] = theirs.relay_count()
	words += ": %s%s (addresses: this machine %d own, %d outside, %d relay; the other %d own, %d outside, %d relay)" % [cause, ", this machine's code made before its gathering was done" if late else "", mine.own_count(), my_seen.size(), mine.relay_count(), theirs.own_count(), their_seen.size(), theirs.relay_count()]
	return NetWhy.new(OnlineWhy.NO_LINK, words, facts)


## No link came (`in_time`: within the time allowed; false: WebRTC gave up), said with what the
## two codes tell once both are there.
func _fail_no_link(in_time: bool) -> void:
	var both: bool = _theirs != null and _code != ""
	_keep(why_no_link(_mine if both else null, _theirs if both else null, in_time, _late))


## The peer and its channel made. null or why not.
func _begin(hosting: bool) -> NetWhy:
	if not NetWebRTC.available():
		return _fail(OnlineWhy.CANNOT_LINK, "this build has no WebRTC (a desktop build gets it from ci/build/webrtc.sh)")
	_hosting = hosting
	_peer = WebRTCPeerConnection.new()
	var servers: Array[Dictionary] = []
	# Each list a plain Array: the desktop extension refuses any other (a PackedStringArray
	# fails its `initialize`).
	if not _stun.is_empty():
		servers.append({"urls": Array(_stun)})
	if _relay != null and not _relay.urls.is_empty():
		servers.append({"urls": Array(_relay.urls), "username": _relay.username, "credential": _relay.credential})
	if _peer.initialize({"iceServers": servers}) != OK:
		return _fail(OnlineWhy.SETUP_FAILED, "WebRTC did not start")
	_peer.session_description_created.connect(_on_described)
	_peer.ice_candidate_created.connect(_on_candidate)
	_channel = _peer.create_data_channel(CHANNEL, {"negotiated": true, "id": CHANNEL_ID})
	if _channel == null:
		return _fail(OnlineWhy.SETUP_FAILED, "WebRTC made no data channel")
	return null


## This machine's description is made (the host's offer; the answer to the host's).
func _on_described(type: String, sdp: String) -> void:
	if _described_at >= 0 or _peer.set_local_description(type, sdp) != OK:
		_fail(OnlineWhy.SETUP_FAILED, "WebRTC did not take its own description")
		return
	_mine.type = type
	_mine.sdp = sdp
	_described_at = _now()


func _on_candidate(mid: String, index: int, name: String) -> void:
	# After the code was shown a candidate reaches nobody.
	if _code == "":
		_mine.add_candidate(mid, index, name)


func _fail(named: StringName, in_words: String) -> NetWhy:
	return _keep(NetWhy.new(named, in_words))


## The handshake failed for `why` (the first reason stands).
func _keep(why: NetWhy) -> NetWhy:
	if _problem == null:
		_problem = why
		if _peer != null and _link == null:
			_peer.close()
	return why


func _now() -> int:
	return int(clock.call()) if clock.is_valid() else Time.get_ticks_msec()
