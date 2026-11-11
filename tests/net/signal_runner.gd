extends SceneTree
## The handshake through a real room server (online lobby L2, docs/milestones/online-lobby.md):
## a host and a joining machine in this one process, each with a real WebSocket to the server
## `tools/online_signal.sh` started on this machine (`server/signal/local.js`, the same rooms as
## the deployed one) and a real WebRTC peer (no STUN server: one machine). What the unit tests
## stand in for plays here: the engine's WebSocket against the server's, the server's messages
## read by `NetSignal`, real codes through it. Not a unit test: it needs Node and the server.
##
##     godot --headless --path . --script res://tests/net/signal_runner.gd -- --signal=ws://127.0.0.1:8787/room
##
## Prints `SIGNAL OK` or `SIGNAL FAILED: <why>`, and quits. With a relay the server hands over:
## `--relay=given` also needs each inner handshake to have been given one (local.js
## `--fake-relay`), `--relay=used` each machine's code to hold an address on it (the deployed
## server with its TURN key: the credential works). Either way it prints what it saw of the relay.

const PATIENCE_STEPS: int = 1800

var _url: String = ""
## "", "given" or "used" (above).
var _want_relay: String = ""
## Every inner handshake made, and the relay it was given.
var _rtcs: Array[NetRtc] = []
var _relays: Array[NetRelay] = []


func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--signal="):
			_url = argument.trim_prefix("--signal=")
		elif argument.begins_with("--relay="):
			_want_relay = argument.trim_prefix("--relay=")
	await process_frame
	var why: String = await _play()
	print("SIGNAL OK" if why == "" else "SIGNAL FAILED: %s" % why)
	quit(0 if why == "" else 1)


func _made() -> NetSignalHandshake:
	var made := NetSignalHandshake.new(_url)
	made.rtc_maker = func(relay: NetRelay) -> NetHandshake:
		var rtc := NetRtc.new(PackedStringArray(), relay)
		_rtcs.append(rtc)
		_relays.append(relay)
		return rtc
	return made


func _play() -> String:
	if not NetWebRTC.available():
		return "this build has no WebRTC"
	var host: NetSignalHandshake = _made()
	var why: String = host.offer()
	if why != "":
		return "the host: %s" % why
	var guest: NetSignalHandshake = null
	# A machine that names a room nobody opened is told so.
	var stranger: NetSignalHandshake = _made()
	why = stranger.take("ZZZZZ")
	if why != "":
		return "the stranger: %s" % why
	for step in PATIENCE_STEPS:
		await physics_frame
		host.poll()
		stranger.poll()
		if host.problem() != "":
			return "the host: %s" % host.problem()
		if guest == null and host.code() != "":
			print("SIGNAL room %s" % host.code())
			guest = _made()
			# As a player types it.
			why = guest.take(" %s " % host.code().to_lower())
			if why != "":
				return "the guest: %s" % why
		if guest == null:
			continue
		guest.poll()
		if guest.problem() != "":
			return "the guest: %s" % guest.problem()
		if host.link() == null or guest.link() == null:
			continue
		if stranger.problem() != "no room has the code ZZZZZ":
			return "the stranger was told: %s" % stranger.problem()
		why = await _talk(host.link(), guest.link())
		return why if why != "" else _relay_seen()
	return "no link in time (room %s, stranger: %s)" % [host.code(), stranger.problem()]


## What was seen of the relay, printed; "" or why it is not what `--relay` wants.
func _relay_seen() -> String:
	var given: int = 0
	var addresses: PackedStringArray = []
	for at in _rtcs.size():
		given += 0 if _relays[at] == null else 1
		var code := NetCode.new()
		addresses.append(str(code.relay_count()) if code.read(_rtcs[at].code()) == "" else "?")
	print("SIGNAL relay given to %d of %d; relay addresses in each code: %s" % [given, _rtcs.size(), ", ".join(addresses)])
	if _want_relay != "" and given != _rtcs.size():
		return "a relay was wanted and not given to every machine"
	if _want_relay == "used" and (addresses.has("0") or addresses.has("?")):
		return "a relay was given but a machine gathered no address on it"
	return ""


## The two links carry a message each way.
func _talk(host: NetLink, guest: NetLink) -> String:
	host.send(PackedByteArray([1, 2, 3]))
	guest.send(PackedByteArray([4, 5]))
	var to_guest: PackedByteArray = PackedByteArray()
	var to_host: PackedByteArray = PackedByteArray()
	for step in 300:
		await physics_frame
		if to_guest.is_empty():
			to_guest = guest.read()
		if to_host.is_empty():
			to_host = host.read()
		if not to_guest.is_empty() and not to_host.is_empty():
			break
	if to_guest != PackedByteArray([1, 2, 3]) or to_host != PackedByteArray([4, 5]):
		return "the link carried %s and %s" % [to_guest, to_host]
	return ""
