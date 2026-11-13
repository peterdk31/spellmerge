extends NetHandshake
## A handshake inside one process (netcode spike S4): the tests' stand-in for WebRTC's, so Host and
## Join (`NetPlay`) are tested on a stepped clock with no network. Two of them share a `table`;
## the host's code is HOST_CODE and the joining side's JOIN_CODE, each made `making` polls after it
## was asked for, and the link (a loopback's two ends) is there for both once the host took the
## answer. Any other text is refused, as a bad code is. The codes have a real code's prefix and
## alphabet, so the room server's messages carry them too (tests/net/test_net_signal_handshake.gd).

const HOST_CODE: String = "SM1.aG9zdA=="
const JOIN_CODE: String = "SM1.am9pbg=="
## An answer that is a code but that the handshake itself fails on (as WebRTC may).
const BROKEN_CODE: String = "SM1.YnJva2Vu"

## Polls a code takes to make.
var making: int = 2
## Set by a test: it fails with this.
var fails_with: NetWhy = null

var _table: Dictionary
var _hosting: bool = false
var _asked: bool = false
var _polls: int = 0
var _closed: bool = false


## `table`: shared by the two sides (an empty dictionary to begin with).
func _init(table: Dictionary) -> void:
	_table = table


func offer() -> NetWhy:
	_hosting = true
	_asked = true
	_table[&"ends"] = NetLoopback.pair()
	return null


func takes(typed: String) -> bool:
	return typed.strip_edges().begins_with("SM1.")


func take(code: String) -> NetWhy:
	if _hosting:
		if code == BROKEN_CODE:
			fails_with = NetWhy.new(OnlineWhy.BAD_CODE, "the handshake did not take the code")
			return fails_with
		if code != JOIN_CODE:
			return NetWhy.new(OnlineWhy.HOSTS_CODE, "it is not the joining player's code")
		_table[&"answered"] = true
		return null
	if code != HOST_CODE or not _table.has(&"ends"):
		return NetWhy.new(OnlineWhy.JOINERS_CODE, "it is not the host's code")
	_asked = true
	return null


func code() -> String:
	if not _asked or _polls < making:
		return ""
	return HOST_CODE if _hosting else JOIN_CODE


func poll() -> void:
	if _asked:
		_polls += 1


func link() -> NetLink:
	if _closed or not _table.get(&"answered", false):
		return null
	return (_table[&"ends"] as Array[NetLoopback])[0 if _hosting else 1]


func problem() -> NetWhy:
	return fails_with


func close() -> void:
	_closed = true
