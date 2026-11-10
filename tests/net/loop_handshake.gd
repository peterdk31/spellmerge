extends NetHandshake
## A handshake inside one process (netcode spike S4): the tests' stand-in for WebRTC's, so Host and
## Join (`NetPlay`) are tested on a stepped clock with no network. Two of them share a `table`;
## the host's code is HOST_CODE and the joining side's JOIN_CODE, each made `making` polls after it
## was asked for, and the link (a loopback's two ends) is there for both once the host took the
## answer. Any other text is refused, as a bad code is.

const HOST_CODE: String = "the host's code"
const JOIN_CODE: String = "the joining player's code"
## An answer that is a code but that the handshake itself fails on (as WebRTC may).
const BROKEN_CODE: String = "a code the handshake breaks on"

## Polls a code takes to make.
var making: int = 2
## Set by a test: it fails with this.
var fails_with: String = ""

var _table: Dictionary
var _hosting: bool = false
var _asked: bool = false
var _polls: int = 0
var _closed: bool = false


## `table`: shared by the two sides (an empty dictionary to begin with).
func _init(table: Dictionary) -> void:
	_table = table


func offer() -> String:
	_hosting = true
	_asked = true
	_table[&"ends"] = NetLoopback.pair()
	return ""


func take(code: String) -> String:
	if _hosting:
		if code == BROKEN_CODE:
			fails_with = "the handshake did not take the code"
			return fails_with
		if code != JOIN_CODE:
			return "it is not the joining player's code"
		_table[&"answered"] = true
		return ""
	if code != HOST_CODE or not _table.has(&"ends"):
		return "it is not the host's code"
	_asked = true
	return ""


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


func problem() -> String:
	return fails_with


func close() -> void:
	_closed = true
