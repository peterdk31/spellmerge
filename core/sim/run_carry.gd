class_name RunCarry
extends RefCounted
## What a run's start takes along from the play before it (online lobby, docs/milestones/
## online-lobby.md): each seat's staffs, each as the staff it is (its id under `wizard`; empty: the
## run's own staff for that button) and the card ids in its slots (owner, 2026-11-13: a staff
## equipped in the hub and the cards set on it go into the run as they are). A replay carries it in its
## header (core/sim/replay.gd), so every machine that plays the recording starts it with the same
## staffs, though only the machine that made it had them.
##
## The game says what it would take along now (`Frames.set_carry_source`, given by Flow: in the hub,
## every wizard's staffs; anywhere else nothing, since nothing comes back from a run), the frames
## service writes it into the header of a recording it begins, and a run that starts reads it back
## (`Frames.next_run_carry`). Today that is the hub begun anew for a joining machine; later, a
## recording begun anew between a run's rooms.
##
## Kept as plain ids (letters, digits, `_`; empty for an empty slot), read as strictly as an input
## frame's: every count, length and character is checked, and anything else rejects the header.

## Seats, staffs a seat holds, slots a staff holds (StaffBase's range), as the decoder holds them.
const SEATS: int = 4
const STAFFS: int = 4
const MAX_CARDS: int = 64
## The most bytes it takes: every seat with four staffs of MAX_CARDS ids of the longest kind, and
## each staff's own id.
const MAX_BYTES: int = 1 + SEATS * (1 + STAFFS * (1 + MAX_CARDS * (1 + InputFrame.MAX_TEXT) + 1 + InputFrame.MAX_TEXT))

## By seat: the cards of each of its staffs (an Array of `Array[StringName]`); empty for a seat
## that takes nothing along.
var _staffs: Array = [[], [], [], []]
## By seat: the id of each of its staffs (an `Array[StringName]` as long as its row in `_staffs`;
## `&""` for a button that takes the run's own staff).
var _heads: Array = [[], [], [], []]
## Where the last `decode_at` stopped reading (scratch).
var read_to: int = 0


## A carry of `kept`: by seat, each staff's card ids, and `heads`: by seat, each staff's id (what
## Flow's `start_run` takes; none: the run's own staffs). Seats past SEATS, staffs past STAFFS and
## cards past MAX_CARDS are left out, as is any id that is not one.
static func of_kept(kept: Array, heads: Array = []) -> RunCarry:
	var made := RunCarry.new()
	for seat in mini(kept.size(), SEATS):
		if kept[seat] is Array:
			var seat_heads: Array = heads[seat] as Array if seat < heads.size() and heads[seat] is Array else []
			made.set_staffs(seat, kept[seat] as Array, seat_heads)
	return made


## By seat, each staff's card ids (a deep copy): what Flow's `start_run` takes as `kept`.
func as_kept() -> Array:
	var out: Array = []
	for seat in SEATS:
		out.append(staffs_of(seat))
	return out


## By seat, each staff's id (`&""`: the run's own staff): what Flow's `start_run` takes as `heads`.
func as_heads() -> Array:
	var out: Array = []
	for seat in SEATS:
		out.append(heads_of(seat))
	return out


## The ids of seat `seat`'s staffs, one per staff it carries (a copy; empty for none).
func heads_of(seat: int) -> Array[StringName]:
	var out: Array[StringName] = []
	if seat < 0 or seat >= SEATS:
		return out
	out.assign(_heads[seat])
	return out


## Seat `seat`'s staffs, each an `Array[StringName]` of its cards (a copy; empty for none).
func staffs_of(seat: int) -> Array:
	var out: Array = []
	if seat < 0 or seat >= SEATS:
		return out
	for cards: Array[StringName] in _staffs[seat]:
		out.append(cards.duplicate())
	return out


## Seat `seat` takes `staffs` along (each a list of card ids by slot), each the staff of the id
## at its place in `heads` (none, or not an id: the run's own staff for that button). What does not
## fit the limits, or is not an id, is left out.
func set_staffs(seat: int, staffs: Array, heads: Array = []) -> void:
	if seat < 0 or seat >= SEATS:
		return
	var rows: Array = []
	var ids: Array[StringName] = []
	var at: int = 0
	for staff: Variant in staffs.slice(0, STAFFS):
		var row: Array[StringName] = []
		if staff is Array:
			for id: Variant in (staff as Array).slice(0, MAX_CARDS):
				row.append(_id_or_none(id))
		rows.append(row)
		ids.append(_id_or_none(heads[at]) if at < heads.size() else &"")
		at += 1
	_staffs[seat] = rows
	_heads[seat] = ids


static func _id_or_none(id: Variant) -> StringName:
	var text: String = str(id)
	return StringName(text) if InputFrame.is_id(text) else &""


## True when no seat takes anything along.
func is_empty() -> bool:
	return seats() == 0


## The seats that take something along (a bit each).
func seats() -> int:
	var mask: int = 0
	for seat in SEATS:
		if not (_staffs[seat] as Array).is_empty():
			mask |= 1 << seat
	return mask


func copy() -> RunCarry:
	var made := RunCarry.new()
	for seat in SEATS:
		made._staffs[seat] = staffs_of(seat)
		made._heads[seat] = heads_of(seat)
	return made


func equals(other: RunCarry) -> bool:
	return other != null and as_kept() == other.as_kept() and as_heads() == other.as_heads()


## Append it to `out` (a replay's header): a byte of the seats that take something along, then for
## each of those its staff count, and for each staff its card count, each card as its length and
## its letters, then the staff's own id the same way (length 0: the run's own staff).
func encode_into(out: PackedByteArray) -> void:
	out.append(seats())
	for seat in SEATS:
		var staffs: Array = _staffs[seat]
		if staffs.is_empty():
			continue
		out.append(staffs.size())
		var heads: Array = _heads[seat]
		for staff in staffs.size():
			var cards: Array[StringName] = staffs[staff]
			out.append(cards.size())
			for id: StringName in cards:
				_encode_id(out, id)
			_encode_id(out, heads[staff] as StringName)


static func _encode_id(out: PackedByteArray, id: StringName) -> void:
	var text: PackedByteArray = String(id).to_ascii_buffer()
	out.append(text.size())
	out.append_array(text)


## Read it from `bytes` at `at`: "" when it is whole and every count, length and id is within its
## limits (it then ends at `read_to`), else why not (and nothing is changed).
func decode_at(bytes: PackedByteArray, at: int) -> String:
	if at < 0 or at >= bytes.size():
		return "the carried staffs are cut short"
	var mask: int = bytes[at]
	at += 1
	if mask >= 1 << SEATS:
		return "carried seats %d" % mask
	var read: Array = [[], [], [], []]
	var read_heads: Array = [[], [], [], []]
	for seat in SEATS:
		if mask & (1 << seat) == 0:
			continue
		if at >= bytes.size():
			return "seat %d's carried staffs are cut short" % seat
		var count: int = bytes[at]
		at += 1
		if count < 1 or count > STAFFS:
			return "seat %d carries %d staffs" % [seat, count]
		for staff in count:
			if at >= bytes.size():
				return "seat %d's staff %d is cut short" % [seat, staff]
			var cards: int = bytes[at]
			at += 1
			if cards > MAX_CARDS:
				return "seat %d's staff %d carries %d cards" % [seat, staff, cards]
			var row: Array[StringName] = []
			# The cards, then the staff's own id (which may be empty).
			for card in cards + 1:
				if at >= bytes.size():
					return "seat %d's staff %d is cut short" % [seat, staff]
				var size: int = bytes[at]
				if size > InputFrame.MAX_TEXT or at + 1 + size > bytes.size():
					return "seat %d's staff %d is cut short" % [seat, staff]
				var text: String = bytes.slice(at + 1, at + 1 + size).get_string_from_ascii()
				if text.length() != size or not InputFrame.is_id(text):
					return "seat %d's staff %d %s not an id" % [seat, staff, "is a staff that is" if card == cards else "holds a card that is"]
				at += 1 + size
				if card == cards:
					(read_heads[seat] as Array).append(StringName(text))
				else:
					row.append(StringName(text))
			(read[seat] as Array).append(row)
	_staffs = read
	for seat in SEATS:
		var ids: Array[StringName] = []
		ids.assign(read_heads[seat])
		_heads[seat] = ids
	read_to = at
	return ""


func _to_string() -> String:
	return "RunCarry(%s, %s)" % [as_kept(), as_heads()]
