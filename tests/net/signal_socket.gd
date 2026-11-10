extends NetSignalSocket
## A socket to no server (online lobby L2): the tests' stand-in for the WebSocket, so the
## handshake through the room server (`NetSignalHandshake`) is tested on a stepped clock with no
## network. The test plays the server: it says when the socket opens, puts messages in with
## `arrive`, reads what was sent from `sent`, and closes it with `drop`.

## The address it was asked to connect to ("" while nothing asked).
var url: String = ""
## Everything sent, in order; `taken` of them were read by the test's server already.
var sent: PackedStringArray = PackedStringArray()
var taken: int = 0
## Set by a test: `open` refuses with this.
var refuses_with: String = ""

var _state: int = CLOSED
var _arrived: PackedStringArray = PackedStringArray()


func open(to: String) -> String:
	if refuses_with != "":
		return refuses_with
	url = to
	_state = CONNECTING
	return ""


func state() -> int:
	return _state


func poll() -> void:
	pass


func send(text: String) -> void:
	if _state == OPEN and text != "":
		sent.append(text)


func read() -> String:
	if _arrived.is_empty():
		return ""
	var text: String = _arrived[0]
	_arrived.remove_at(0)
	return text


func close() -> void:
	_state = CLOSED
	_arrived.clear()


## The server took the connection.
func accept() -> void:
	if _state == CONNECTING:
		_state = OPEN


## The server said `text`.
func arrive(text: String) -> void:
	if _state == OPEN:
		_arrived.append(text)


## The server closed it (what arrived before can still be read).
func drop() -> void:
	_state = CLOSED


## The next message sent that the test's server has not taken yet, "" when there is none.
func take_sent() -> String:
	if taken >= sent.size():
		return ""
	taken += 1
	return sent[taken - 1]
