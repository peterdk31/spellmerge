class_name GroundLoadout
extends RefCounted
## What lies on a room's ground, as a run's start takes it along (items I6; owner, 2026-11-14: "The
## hub should only refresh the rack when a host starts it or when a party returns to it from a
## run"). The room it lies in (`room`) and each item: its kind and id, the name it is shown by, its
## copies, its cards by slot, the mana it keeps and where it lies. Plain data that knows no item:
## the Items area writes it (gameplay/items) and lays it again.
##
## The game says what lies on the ground now (`Frames.set_ground_source`, given by the Items area),
## the frames service writes it into the header of a recording it begins (core/sim/replay.gd), and a
## run that starts reads it back (`Frames.next_run_ground`). A run whose room is that room (the hub
## begun anew for a joining machine) lays exactly that; any other start (a host starting the hub, a
## party back from a run, a run of waves) lays its room's own placements, so the rack is fresh then.
##
## The bytes: the room's id, a u16 count of items, then each item: its kind and id, its name (a
## byte of length, plain text), its copies (u16), where it lies (two 32-bit floats), its mana (a
## 64-bit float) and its cards (a byte of count, then the ids). Read as strictly as a frame: plain
## ids, plain text, every count within the limits the writers hold to as well; nothing is changed by
## bytes it refuses.

## The most items, the most cards an item holds, the longest name, and the most bytes in all.
const MAX_ITEMS: int = 128
const MAX_CARDS: int = 64
const MAX_TITLE: int = 48
const MAX_COPIES: int = 0xffff
const MAX_BYTES: int = 16384

## The room it lies in (`&""`: none: nothing is taken along).
var room: StringName = &""
## By item: its kind, id, name, copies, place, mana and cards (card ids by slot).
var _kinds: Array[StringName] = []
var _ids: Array[StringName] = []
var _titles: PackedStringArray = PackedStringArray()
var _counts: PackedInt32Array = PackedInt32Array()
var _places: PackedVector2Array = PackedVector2Array()
var _manas: PackedFloat64Array = PackedFloat64Array()
var _cards: Array = []
## Where the last `decode_at` stopped reading (scratch).
var read_to: int = 0
## Its size in bytes (`size`): kept by the writers.
var _size: int = 0


func _init() -> void:
	_size = _empty_size()


## Lies in the room `room_id` (a plain id; `&""`: none). Returns false, changing nothing, for an id
## that is not one or would pass MAX_BYTES.
func set_room(room_id: StringName) -> bool:
	if room_id != &"" and not InputFrame.is_id(String(room_id)):
		return false
	var grown: int = _size - _id_bytes(room) + _id_bytes(room_id)
	if grown > MAX_BYTES:
		return false
	room = room_id
	_size = grown
	return true


## One more item: `copies` of `kind` `id`, shown as `title`, holding `cards` (by slot), keeping
## `mana`, lying at `at`. Returns false, adding nothing, for what the decoder would refuse.
func add_item(kind: StringName, id: StringName, title: String, copies: int, at: Vector2, mana: float, cards: Array[StringName]) -> bool:
	if _ids.size() >= MAX_ITEMS or not _is_name(kind) or not _is_name(id):
		return false
	if copies < 1 or copies > MAX_COPIES or cards.size() > MAX_CARDS or not _is_title(title):
		return false
	if not is_finite(at.x) or not is_finite(at.y) or not is_finite(mana):
		return false
	var bytes: int = _id_bytes(kind) + _id_bytes(id) + 1 + title.length() + 2 + 8 + 8 + 1
	for card: StringName in cards:
		if card != &"" and not InputFrame.is_id(String(card)):
			return false
		bytes += _id_bytes(card)
	if _size + bytes > MAX_BYTES:
		return false
	_kinds.append(kind)
	_ids.append(id)
	_titles.append(title)
	_counts.append(copies)
	_places.append(at)
	_manas.append(mana)
	_cards.append(cards.duplicate())
	_size += bytes
	return true


## How many items lie there.
func count() -> int:
	return _ids.size()


func kind_of(item: int) -> StringName:
	return _kinds[item]


func id_of(item: int) -> StringName:
	return _ids[item]


func title_of(item: int) -> String:
	return _titles[item]


func copies_of(item: int) -> int:
	return _counts[item]


func place_of(item: int) -> Vector2:
	return _places[item]


func mana_of(item: int) -> float:
	return _manas[item]


func cards_of(item: int) -> Array[StringName]:
	var out: Array[StringName] = []
	out.assign(_cards[item])
	return out


## Its size in bytes.
func size() -> int:
	return _size


func copy() -> GroundLoadout:
	var made := GroundLoadout.new()
	made.set_room(room)
	for item in count():
		made.add_item(_kinds[item], _ids[item], _titles[item], _counts[item], _places[item], _manas[item], cards_of(item))
	return made


func equals(other: GroundLoadout) -> bool:
	if other == null or other.room != room or other.count() != count():
		return false
	for item in count():
		if other._kinds[item] != _kinds[item] or other._ids[item] != _ids[item] or other._titles[item] != _titles[item]:
			return false
		if other._counts[item] != _counts[item] or other._places[item] != _places[item] or other._manas[item] != _manas[item]:
			return false
		if other.cards_of(item) != cards_of(item):
			return false
	return true


## Append it to `out` (a replay's header).
func encode_into(out: PackedByteArray) -> void:
	_encode_id(out, room)
	_encode_u16(out, count())
	for item in count():
		_encode_id(out, _kinds[item])
		_encode_id(out, _ids[item])
		var title: PackedByteArray = _titles[item].to_ascii_buffer()
		out.append(title.size())
		out.append_array(title)
		_encode_u16(out, _counts[item])
		var at: int = out.size()
		out.resize(at + 16)
		out.encode_float(at, _places[item].x)
		out.encode_float(at + 4, _places[item].y)
		out.encode_double(at + 8, _manas[item])
		var cards: Array = _cards[item]
		out.append(cards.size())
		for card: StringName in cards:
			_encode_id(out, card)


## Read it from `bytes` at `at`: "" when it is whole and valid (it then ends at `read_to`), else
## why not (and nothing is changed).
func decode_at(bytes: PackedByteArray, at: int) -> String:
	var end: int = bytes.size()
	var read := GroundLoadout.new()
	var room_id: Array = _decode_id(bytes, at, end, true)
	if room_id.is_empty():
		return "the ground's room is not an id"
	read.set_room(room_id[0])
	at = room_id[1]
	if at + 2 > end:
		return "the ground is cut short"
	var items: int = bytes.decode_u16(at)
	at += 2
	if items > MAX_ITEMS:
		return "%d items on the ground" % items
	for item in items:
		var kind: Array = _decode_id(bytes, at, end, false)
		if kind.is_empty():
			return "item %d's kind is not an id" % item
		var id: Array = _decode_id(bytes, kind[1], end, false)
		if id.is_empty():
			return "item %d's id is not an id" % item
		at = id[1]
		if at >= end or bytes[at] > MAX_TITLE or at + 1 + bytes[at] > end:
			return "item %d's name is cut short or too long" % item
		var raw: PackedByteArray = bytes.slice(at + 1, at + 1 + bytes[at])
		for byte in raw:
			if byte < 32 or byte > 126:
				return "item %d's name is not plain text" % item
		at += 1 + raw.size()
		if at + 2 + 16 + 1 > end:
			return "item %d is cut short" % item
		var copies: int = bytes.decode_u16(at)
		var place := Vector2(bytes.decode_float(at + 2), bytes.decode_float(at + 6))
		var mana: float = bytes.decode_double(at + 10)
		at += 18
		var card_count: int = bytes[at]
		at += 1
		if card_count > MAX_CARDS:
			return "item %d holds %d cards" % [item, card_count]
		var cards: Array[StringName] = []
		for slot in card_count:
			var card: Array = _decode_id(bytes, at, end, true)
			if card.is_empty():
				return "item %d's card %d is not an id" % [item, slot]
			cards.append(card[0])
			at = card[1]
		if not read.add_item(kind[0], id[0], raw.get_string_from_ascii(), copies, place, mana, cards):
			return "item %d is out of range" % item
	room = read.room
	_kinds = read._kinds
	_ids = read._ids
	_titles = read._titles
	_counts = read._counts
	_places = read._places
	_manas = read._manas
	_cards = read._cards
	_size = read._size
	read_to = at
	return ""


# --- Inside -----------------------------------------------------------------------------

static func _is_name(id: StringName) -> bool:
	return id != &"" and InputFrame.is_id(String(id))


static func _is_title(title: String) -> bool:
	if title.length() > MAX_TITLE:
		return false
	for at in title.length():
		var code: int = title.unicode_at(at)
		if code < 32 or code > 126:
			return false
	return true


static func _id_bytes(id: StringName) -> int:
	return 1 + String(id).length()


static func _empty_size() -> int:
	return 1 + 2


static func _encode_id(out: PackedByteArray, id: StringName) -> void:
	var text: PackedByteArray = String(id).to_ascii_buffer()
	out.append(text.size())
	out.append_array(text)


static func _encode_u16(out: PackedByteArray, value: int) -> void:
	var at: int = out.size()
	out.resize(at + 2)
	out.encode_u16(at, value)


## The id at `at` in `bytes[:end]` and where the next value starts (`empty_ok`: `&""` is one), or []
## when there is no valid id there.
static func _decode_id(bytes: PackedByteArray, at: int, end: int, empty_ok: bool) -> Array:
	if at >= end:
		return []
	var length: int = bytes[at]
	if length > InputFrame.MAX_TEXT or at + 1 + length > end or (length == 0 and not empty_ok):
		return []
	var raw: PackedByteArray = bytes.slice(at + 1, at + 1 + length)
	for byte in raw:
		var ok: bool = (byte >= 97 and byte <= 122) or (byte >= 65 and byte <= 90) or (byte >= 48 and byte <= 57) or byte == 95
		if not ok:
			return []
	return [StringName(raw.get_string_from_ascii()), at + 1 + length]


func _to_string() -> String:
	return "GroundLoadout(%s, %d items)" % [room, count()]
