extends NetHandshake
## A room inside one process (online lobby L2): the tests' stand-in for the handshake through the
## room server, so the altar and Join online (`NetPlay`) are tested on a stepped clock with no
## network. The handshakes of one test share a `table`. The host's `offer` opens the room, whose
## code is ROOM once `making` polls have passed; a joining machine `take`s that code and has a
## link to the host (a loopback's end) from its next poll; the host is handed the other end by
## `next_link`, one for every machine that joined. The room stays open until the host's `close`.

const ROOM: String = "KQ7RM"

## Polls the room's code takes to make.
var making: int = 2
## Set by a test: it fails with this.
var fails_with: NetWhy = null

var _table: Dictionary
var _hosting: bool = false
var _polls: int = 0
var _mine: NetLink = null
var _closed: bool = false


## `table`: shared by the room's handshakes (an empty dictionary to begin with).
func _init(table: Dictionary) -> void:
	_table = table


func offer() -> NetWhy:
	_hosting = true
	_table[&"open"] = true
	_table[&"waiting"] = [] as Array[NetLink]
	return null


func take(typed: String) -> NetWhy:
	if _hosting:
		return NetWhy.new(OnlineWhy.NOT_NOW, "the room's server brings the other machine's code")
	if typed.strip_edges().to_upper() != ROOM:
		return NetWhy.new(OnlineWhy.BAD_ROOM_CODE, "a room's code is 5 letters and digits", {OnlineWhy.LENGTH: 5})
	if not _table.get(&"open", false):
		fails_with = NetWhy.new(OnlineWhy.NO_ROOM, "no room has the code %s" % ROOM, {OnlineWhy.ROOM: ROOM})
		return null
	var ends: Array[NetLoopback] = NetLoopback.pair()
	(_table[&"waiting"] as Array[NetLink]).append(ends[0])
	_mine = ends[1]
	return null


func code() -> String:
	return ROOM if _hosting and _polls >= making and not _closed else ""


func poll() -> void:
	_polls += 1
	if _hosting and not _closed and not _table.get(&"open", false):
		fails_with = NetWhy.new(OnlineWhy.ROOM_CLOSED, "the room is closed")


func link() -> NetLink:
	return _mine if not _hosting and _polls > 0 and not _closed else null


func next_link() -> NetLink:
	if not _hosting:
		return super()
	var waiting: Array[NetLink] = _table[&"waiting"]
	if _closed or _polls < making or waiting.is_empty():
		return null
	return waiting.pop_front()


func problem() -> NetWhy:
	return fails_with


func close() -> void:
	_closed = true
	if _hosting:
		_table[&"open"] = false
