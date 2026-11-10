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
## - **One code each way:** a machine's code is shown once its candidates are gathered, or
##   GATHER_MS after its description was made with what was gathered by then (a STUN server that
##   does not answer must not hold the code back for ever). Never with no candidate in it: such a
##   code reaches nobody, so with none by then the handshake fails and says so.
## - **The channel is agreed beforehand** (the same id on both sides), so neither side waits for
##   the other to announce it.
## - **A pasted code** is read by `NetCode` (strictly) and must be the kind this side expects
##   before WebRTC sees any of it; a code refused there changes nothing, so the player may paste
##   again. A code WebRTC itself refuses ends the handshake (`problem`): its peer cannot go on.
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
var _peer: WebRTCPeerConnection = null
var _channel: WebRTCDataChannel = null
var _hosting: bool = false
## This machine's code as it is gathered, and its text once shown.
var _mine: NetCode = NetCode.new()
var _code: String = ""
## When this machine's description was made, and when the other's code was taken (-1: not yet).
## The gathering's state was seen done at an earlier poll (its last candidates are in by now).
var _gathered: bool = false
var _described_at: int = -1
var _taken_at: int = -1
var _link: NetRtcLink = null
var _problem: String = ""


## `stun_servers`: the servers asked for this machine's address (none: only machines on one
## network, or in one process, find each other).
func _init(stun_servers: PackedStringArray = STUN) -> void:
	_stun = stun_servers


func offer() -> String:
	if _peer != null:
		return "it has begun already"
	var why: String = _begin(true)
	if why == "" and _peer.create_offer() != OK:
		why = _fail("WebRTC made no offer")
	return why


## A pasted code of this kind starts as `NetCode`'s do.
func takes(typed: String) -> bool:
	return typed.strip_edges().begins_with(NetCode.PREFIX)


func take(code: String) -> String:
	if _problem != "":
		return _problem
	if _taken_at >= 0:
		return "a code was given already"
	var theirs := NetCode.new()
	var why: String = theirs.read(code)
	if why != "":
		return why
	if _peer != null and not _hosting:
		return "a code was given already"
	if _hosting and theirs.type != NetCode.ANSWER:
		return "this is a host's code; the host needs the code the joining player got back"
	if _hosting and _code == "":
		return "this machine's own code is not made yet"
	if not _hosting and theirs.type != NetCode.OFFER:
		return "this is a joining player's code; Join needs the host's"
	if _peer == null:
		why = _begin(false)
		if why != "":
			return why
	# For an offer the peer makes its answer by itself (`_on_described`).
	if _peer.set_remote_description(theirs.type, theirs.sdp) != OK:
		return _fail("WebRTC did not take the code")
	for at in theirs.mids.size():
		# One candidate it cannot use is not the end: the others may do.
		_peer.add_ice_candidate(theirs.mids[at], theirs.indexes[at], theirs.names[at])
	_taken_at = _now()
	return ""


func code() -> String:
	return _code


func poll() -> void:
	if _peer == null or _problem != "" or _link != null:
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
					_fail("this machine found no network address to be reached at")
				return
			_code = _mine.to_text()
			if _code == "":
				_fail("this machine's code could not be made")
				return
		elif _peer.get_gathering_state() == WebRTCPeerConnection.GATHERING_STATE_COMPLETE:
			_gathered = true
	if _channel.get_ready_state() == WebRTCDataChannel.STATE_OPEN:
		_link = NetRtcLink.new(_peer, _channel)
		return
	var state: int = _peer.get_connection_state()
	if state == WebRTCPeerConnection.STATE_FAILED or state == WebRTCPeerConnection.STATE_CLOSED:
		_fail("the two machines could not reach each other")
	elif _hosting and _taken_at >= 0 and _now() - _taken_at >= LINK_MS:
		_fail("the two machines did not find each other in time")


func link() -> NetLink:
	return _link


func problem() -> String:
	return _problem


func close() -> void:
	if _problem == "":
		_problem = "given up"
	if _peer != null and _link == null:
		_peer.close()


## The peer and its channel made. "" or why not.
func _begin(hosting: bool) -> String:
	if not NetWebRTC.available():
		return _fail("this build has no WebRTC (a desktop build gets it from ci/build/webrtc.sh)")
	_hosting = hosting
	_peer = WebRTCPeerConnection.new()
	var servers: Array[Dictionary] = []
	if not _stun.is_empty():
		servers.append({"urls": _stun})
	if _peer.initialize({"iceServers": servers}) != OK:
		return _fail("WebRTC did not start")
	_peer.session_description_created.connect(_on_described)
	_peer.ice_candidate_created.connect(_on_candidate)
	_channel = _peer.create_data_channel(CHANNEL, {"negotiated": true, "id": CHANNEL_ID})
	if _channel == null:
		return _fail("WebRTC made no data channel")
	return ""


## This machine's description is made (the host's offer; the answer to the host's).
func _on_described(type: String, sdp: String) -> void:
	if _described_at >= 0 or _peer.set_local_description(type, sdp) != OK:
		_fail("WebRTC did not take its own description")
		return
	_mine.type = type
	_mine.sdp = sdp
	_described_at = _now()


func _on_candidate(mid: String, index: int, name: String) -> void:
	# After the code was shown a candidate reaches nobody.
	if _code == "":
		_mine.add_candidate(mid, index, name)


func _fail(why: String) -> String:
	if _problem == "":
		_problem = why
		if _peer != null and _link == null:
			_peer.close()
	return why


func _now() -> int:
	return int(clock.call()) if clock.is_valid() else Time.get_ticks_msec()
