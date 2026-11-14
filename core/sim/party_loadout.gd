class_name PartyLoadout
extends RefCounted
## What a run's start takes along from the play before it (items I4, docs/milestones/items.md; in
## place of `RunCarry`): for each seat that takes something along, its player loadout
## (`PlayerLoadout`, core/sim/player_loadout.gd: its bags, its staffs and its hands). A seat with none
## starts with what its run's mode gives; a seat with an empty loadout starts with nothing.
##
## The game says what it would take along now (`Frames.set_party_source`, given by Flow: in the
## hub, every wizard's loadout; anywhere else nothing, since nothing comes back from a run), the
## frames service writes it into the header of a recording it begins (core/sim/replay.gd), and a run
## that starts reads it back (`Frames.next_run_party`). Today that is the hub begun anew for a
## joining machine; later, a recording begun anew between a run's rooms.
##
## The bytes: a byte of the seats that take something along (a bit each), then each of those seats'
## loadout. Read as strictly as the loadout itself, and nothing is changed by bytes it refuses.

const SEATS: int = 4
## The most bytes it takes: the seats' byte and every seat's loadout at its most.
const MAX_BYTES: int = 1 + SEATS * PlayerLoadout.MAX_BYTES

## By seat: its loadout, or null for a seat that takes nothing along.
var _loadouts: Array[PlayerLoadout] = [null, null, null, null]
## Where the last `decode_at` stopped reading (scratch).
var read_to: int = 0


## Seat `seat` takes `loadout` along (a copy of it; null: nothing). A seat outside the four is none.
func put(seat: int, loadout: PlayerLoadout) -> void:
	if seat >= 0 and seat < SEATS:
		_loadouts[seat] = loadout.copy() if loadout != null else null


## What seat `seat` takes along (a copy), or null for a seat that takes nothing.
func of(seat: int) -> PlayerLoadout:
	if seat < 0 or seat >= SEATS or _loadouts[seat] == null:
		return null
	return _loadouts[seat].copy()


## The seats that take something along (a bit each).
func seats() -> int:
	var mask: int = 0
	for seat in SEATS:
		if _loadouts[seat] != null:
			mask |= 1 << seat
	return mask


## True when no seat takes anything along.
func is_empty() -> bool:
	return seats() == 0


func copy() -> PartyLoadout:
	var made := PartyLoadout.new()
	for seat in SEATS:
		made.put(seat, _loadouts[seat])
	return made


func equals(other: PartyLoadout) -> bool:
	if other == null or other.seats() != seats():
		return false
	for seat in SEATS:
		if _loadouts[seat] != null and not _loadouts[seat].equals(other._loadouts[seat]):
			return false
	return true


## Append it to `out` (a replay's header): the seats' byte, then each of those seats' loadout.
func encode_into(out: PackedByteArray) -> void:
	out.append(seats())
	for seat in SEATS:
		if _loadouts[seat] != null:
			_loadouts[seat].encode_into(out)


## Read it from `bytes` at `at`: "" when it is whole and every loadout is valid (it then ends at
## `read_to`), else why not (and nothing is changed).
func decode_at(bytes: PackedByteArray, at: int) -> String:
	if at < 0 or at >= bytes.size():
		return "the players' loadouts are cut short"
	var mask: int = bytes[at]
	at += 1
	if mask >= 1 << SEATS:
		return "loadouts of seats %d" % mask
	var read: Array[PlayerLoadout] = [null, null, null, null]
	for seat in SEATS:
		if mask & (1 << seat) == 0:
			continue
		var loadout := PlayerLoadout.new()
		var problem: String = loadout.decode_at(bytes, at)
		if problem != "":
			return "seat %d's loadout: %s" % [seat, problem]
		read[seat] = loadout
		at = loadout.read_to
	_loadouts = read
	read_to = at
	return ""


func _to_string() -> String:
	return "PartyLoadout(%s)" % [_loadouts]
