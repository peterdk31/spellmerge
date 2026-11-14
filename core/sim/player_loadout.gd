class_name PlayerLoadout
extends RefCounted
## The player loadout (items I4, docs/milestones/items.md, "The model"): what a run's start takes
## along for one seat, the whole player (owner, 2026-11-13): its bags, its staffs by number and its
## hands. A replay carries one for each seat that takes something along in its header (`PartyLoadout`,
## core/sim/party_loadout.gd), so every machine that plays the recording starts it with the same
## players, though only the machine that made it had them.
##
## Plain data, with no knowledge of what an item is: the inventory writes its own (`Inventory.
## loadout`) and takes one back (`Inventory.take_loadout`).
##
## - **Bags** (`add_stack`, `bags`, `stack_ids`, `stack_counts`): by bag name, the stacks it holds
##   that are counted, each an id and its copies, in their order.
## - **Staffs** (`add_staff`, `staff_numbers`, `staff_id`, `staff_cards`): every staff owned, in the
##   inventory's order, each its number there, the staff it is (its content id) and its card ids by
##   slot (`&""` an empty slot). A staff's mana is not taken along: a run starts with every pool full.
## - **Hands** (`set_hands`, `hands`, `hand_of`): by hand, the number of the staff on it or NO_STAFF.
##   A staff on no hand is in the staff bag.
##
## **The bytes** (`encode_into`, `decode_at`) are tagged sections: a count, then each section as its
## tag, its length and its payload, every one of SECTIONS once, in order. A later section (a name,
## colours) is a new tag after these, and leaves their bytes as they are. Read as strictly as an
## input frame: every count, length, number and id is checked (an id is letters, digits and `_`,
## never a path), a section it does not know rejects the loadout, and nothing is changed by bytes it
## refuses. What a writer refuses (it returns false) the decoder refuses too: they share the limits.

## No staff: a hand that holds none.
const NO_STAFF: int = -1

## The sections' tags, in the order they are written.
const BAGS: int = 1
const STAFFS: int = 2
const HANDS: int = 3
const SECTIONS: PackedByteArray = [BAGS, STAFFS, HANDS]

## The limits, the writers' and the decoder's: bags, counted stacks in all bags together, copies
## in a stack, staffs owned, a staff's number, the slots of a staff (StaffBase's range), hands.
const MAX_BAGS: int = 8
const MAX_STACKS: int = 512
const MAX_COPIES: int = 0xffff
const MAX_STAFFS: int = 32
const MAX_NUMBER: int = 0xfffe
const MAX_CARDS: int = 64
const MAX_HANDS: int = 8
## The most bytes one takes; a writer refuses what would pass it.
const MAX_BYTES: int = 16384
## A hand with no staff, as its bytes.
const _NO_STAFF_BYTES: int = 0xffff
## The bytes of an empty loadout: the section count, and each section's tag, length and count of none.
const _EMPTY_BYTES: int = 1 + 3 * 4

## The bags that hold something, by name, and beside each its stacks' ids (an `Array[StringName]`)
## and their copies (a PackedInt32Array).
var _bags: Array[StringName] = []
var _stack_ids: Array = []
var _stack_counts: Array = []
var _stacks: int = 0
## The staffs: each one's number, id and cards (an `Array[StringName]`).
var _numbers: PackedInt32Array = PackedInt32Array()
var _staff_ids: Array[StringName] = []
var _staff_cards: Array = []
## By hand: the number of the staff on it, or NO_STAFF.
var _hands: PackedInt32Array = PackedInt32Array()
## How many bytes it takes now (`size`).
var _size: int = _EMPTY_BYTES
## Where the last `decode_at` stopped reading (scratch).
var read_to: int = 0


# --- Writing ----------------------------------------------------------------------------

## Bag `bag` holds `copies` more of `id`, after what it holds. False, and nothing changes, when
## `bag` or `id` is not a name (or is empty), `copies` is not 1 to MAX_COPIES, or a limit is passed.
func add_stack(bag: StringName, id: StringName, copies: int) -> bool:
	if not _is_name(bag) or not _is_name(id) or copies < 1 or copies > MAX_COPIES or _stacks >= MAX_STACKS:
		return false
	var at: int = _bags.find(bag)
	var more: int = _id_bytes(id) + 2
	if at < 0:
		more += _id_bytes(bag) + 2
		if _bags.size() >= MAX_BAGS:
			return false
	if _size + more > MAX_BYTES:
		return false
	if at < 0:
		at = _bags.size()
		_bags.append(bag)
		var ids: Array[StringName] = []
		_stack_ids.append(ids)
		_stack_counts.append(PackedInt32Array())
	var held: Array[StringName] = _stack_ids[at]
	held.append(id)
	var counts: PackedInt32Array = _stack_counts[at]
	counts.append(copies)
	_stack_counts[at] = counts
	_stacks += 1
	_size += more
	return true


## It owns the staff `id` under the number `number`, holding `cards` by slot (`&""` an empty
## slot), after the staffs it owns. False, and nothing changes, when the number is taken or out of
## range, `id` is not a name, a card is not an id, or a limit is passed.
func add_staff(number: int, id: StringName, cards: Array[StringName]) -> bool:
	if number < 0 or number > MAX_NUMBER or _numbers.has(number) or not _is_name(id):
		return false
	if _numbers.size() >= MAX_STAFFS or cards.size() > MAX_CARDS:
		return false
	var more: int = 2 + _id_bytes(id) + 1
	for card: StringName in cards:
		if not InputFrame.is_id(String(card)):
			return false
		more += _id_bytes(card)
	if _size + more > MAX_BYTES:
		return false
	_numbers.append(number)
	_staff_ids.append(id)
	_staff_cards.append(cards.duplicate())
	_size += more
	return true


## Its hands are `numbers`: by hand, the number of a staff it owns or NO_STAFF. False, and nothing
## changes, when there are more than MAX_HANDS, a number is no staff's, or one staff is on two.
func set_hands(numbers: PackedInt32Array) -> bool:
	if numbers.size() > MAX_HANDS:
		return false
	for at in numbers.size():
		var number: int = numbers[at]
		if number == NO_STAFF:
			continue
		if not _numbers.has(number) or numbers.find(number) != at:
			return false
	if _size + 2 * (numbers.size() - _hands.size()) > MAX_BYTES:
		return false
	_size += 2 * (numbers.size() - _hands.size())
	_hands = numbers.duplicate()
	return true


# --- Reading ----------------------------------------------------------------------------

## The bags that hold something counted, in the order they were first written.
func bags() -> Array[StringName]:
	return _bags.duplicate()


## The ids of bag `bag`'s stacks, in order (a copy; empty for a bag with none), and beside each
## its copies (`stack_counts`).
func stack_ids(bag: StringName) -> Array[StringName]:
	var at: int = _bags.find(bag)
	var out: Array[StringName] = []
	if at >= 0:
		out.assign(_stack_ids[at])
	return out


func stack_counts(bag: StringName) -> PackedInt32Array:
	var at: int = _bags.find(bag)
	return (_stack_counts[at] as PackedInt32Array).duplicate() if at >= 0 else PackedInt32Array()


## The numbers of the staffs it owns, in the order they were written.
func staff_numbers() -> PackedInt32Array:
	return _numbers.duplicate()


## The id of staff `number` (`&""` for a number it does not own).
func staff_id(number: int) -> StringName:
	var at: int = _numbers.find(number)
	return _staff_ids[at] if at >= 0 else &""


## The cards of staff `number` by slot (a copy; empty for a number it does not own).
func staff_cards(number: int) -> Array[StringName]:
	var at: int = _numbers.find(number)
	var out: Array[StringName] = []
	if at >= 0:
		out.assign(_staff_cards[at])
	return out


## By hand: the number of the staff on it, or NO_STAFF (a copy).
func hands() -> PackedInt32Array:
	return _hands.duplicate()


## The hand staff `number` is on, or -1 (in the staff bag, or not owned).
func hand_of(number: int) -> int:
	return _hands.find(number) if number != NO_STAFF else -1


## True when it holds nothing: no stack, no staff and no hand.
func is_empty() -> bool:
	return _bags.is_empty() and _numbers.is_empty() and _hands.is_empty()


## How many bytes it takes (`encode_into`): never more than MAX_BYTES.
func size() -> int:
	return _size


func copy() -> PlayerLoadout:
	var made := PlayerLoadout.new()
	for at in _bags.size():
		var ids: Array[StringName] = []
		ids.assign(_stack_ids[at])
		made._bags.append(_bags[at])
		made._stack_ids.append(ids)
		made._stack_counts.append((_stack_counts[at] as PackedInt32Array).duplicate())
	made._stacks = _stacks
	made._numbers = _numbers.duplicate()
	made._staff_ids = _staff_ids.duplicate()
	for cards: Array[StringName] in _staff_cards:
		made._staff_cards.append(cards.duplicate())
	made._hands = _hands.duplicate()
	made._size = _size
	return made


## True when `other` holds the same, in the same order (its bytes are the same).
func equals(other: PlayerLoadout) -> bool:
	if other == null:
		return false
	var mine := PackedByteArray()
	var theirs := PackedByteArray()
	encode_into(mine)
	other.encode_into(theirs)
	return mine == theirs


# --- The bytes --------------------------------------------------------------------------

## Append it to `out` (`size()` bytes): the section count, then each of SECTIONS as its tag, its
## payload's length (16 bits) and its payload.
## - BAGS: the bag count, then each bag's name, its stack count (16 bits) and each stack's id and
##   copies (16 bits).
## - STAFFS: the staff count, then each staff's number (16 bits), its id, its card count and each
##   card's id (an id is its length and its letters; length 0 an empty slot).
## - HANDS: the hand count, then each hand's staff number (16 bits; 0xffff for none).
func encode_into(out: PackedByteArray) -> void:
	out.append(SECTIONS.size())
	for tag in SECTIONS:
		out.append(tag)
		var length_at: int = out.size()
		out.resize(length_at + 2)
		match tag:
			BAGS:
				out.append(_bags.size())
				for at in _bags.size():
					_encode_id(out, _bags[at])
					var ids: Array[StringName] = _stack_ids[at]
					var counts: PackedInt32Array = _stack_counts[at]
					_encode_u16(out, ids.size())
					for stack in ids.size():
						_encode_id(out, ids[stack])
						_encode_u16(out, counts[stack])
			STAFFS:
				out.append(_numbers.size())
				for at in _numbers.size():
					_encode_u16(out, _numbers[at])
					_encode_id(out, _staff_ids[at])
					var cards: Array[StringName] = _staff_cards[at]
					out.append(cards.size())
					for card: StringName in cards:
						_encode_id(out, card)
			HANDS:
				out.append(_hands.size())
				for number in _hands:
					_encode_u16(out, _NO_STAFF_BYTES if number == NO_STAFF else number)
		out.encode_u16(length_at, out.size() - length_at - 2)


## Read it from `bytes` at `at`: "" when it is one whole valid loadout (it then ends at `read_to`),
## else why not (and nothing is changed).
func decode_at(bytes: PackedByteArray, at: int) -> String:
	var read := PlayerLoadout.new()
	var problem: String = read._read(bytes, at)
	if problem != "":
		return problem
	_bags = read._bags
	_stack_ids = read._stack_ids
	_stack_counts = read._stack_counts
	_stacks = read._stacks
	_numbers = read._numbers
	_staff_ids = read._staff_ids
	_staff_cards = read._staff_cards
	_hands = read._hands
	_size = read._size
	read_to = read.read_to
	return ""


## Fill this fresh loadout from `bytes` at `at`, through the writers (so their limits are the
## decoder's): "" when it is whole and valid, else why not.
func _read(bytes: PackedByteArray, at: int) -> String:
	if at < 0 or at >= bytes.size():
		return "the loadout is cut short"
	if bytes[at] != SECTIONS.size():
		return "%d sections, not %d" % [bytes[at], SECTIONS.size()]
	at += 1
	for tag in SECTIONS:
		if at + 3 > bytes.size():
			return "section %d is cut short" % tag
		if bytes[at] != tag:
			return "section %d where section %d belongs" % [bytes[at], tag] if SECTIONS.has(bytes[at]) else "a section it does not know (%d)" % bytes[at]
		var end: int = at + 3 + bytes.decode_u16(at + 1)
		if end > bytes.size():
			return "section %d is cut short" % tag
		at += 3
		var problem: String = ""
		match tag:
			BAGS:
				problem = _read_bags(bytes, at, end)
			STAFFS:
				problem = _read_staffs(bytes, at, end)
			HANDS:
				problem = _read_hands(bytes, at, end)
		if problem != "":
			return problem
		if read_to != end:
			return "section %d: %d bytes left over" % [tag, end - read_to]
		at = end
	read_to = at
	return ""


## The BAGS section's payload, `bytes[at:end]`: "" when read (to `read_to`), else why not.
func _read_bags(bytes: PackedByteArray, at: int, end: int) -> String:
	if at >= end:
		return "the bags are cut short"
	var count: int = bytes[at]
	at += 1
	for bag_at in count:
		var bag: Array = _decode_id(bytes, at, end)
		if bag.is_empty() or (bag[1] as int) + 2 > end:
			return "bag %d is cut short or its name is not an id" % bag_at
		if _bags.has(bag[0]):
			return "the bag %s twice" % bag[0]
		at = bag[1]
		var stacks: int = bytes.decode_u16(at)
		at += 2
		if stacks < 1:
			return "the bag %s holds nothing" % bag[0]
		for stack in stacks:
			var id: Array = _decode_id(bytes, at, end)
			if id.is_empty() or (id[1] as int) + 2 > end:
				return "the bag %s is cut short or holds what is not an id" % bag[0]
			at = (id[1] as int) + 2
			if not add_stack(bag[0], id[0], bytes.decode_u16(at - 2)):
				return "the bag %s: %d of '%s' is past a limit" % [bag[0], bytes.decode_u16(at - 2), id[0]]
	read_to = at
	return ""


## The STAFFS section's payload, as `_read_bags`.
func _read_staffs(bytes: PackedByteArray, at: int, end: int) -> String:
	if at >= end:
		return "the staffs are cut short"
	var count: int = bytes[at]
	at += 1
	for staff in count:
		if at + 2 > end:
			return "staff %d is cut short" % staff
		var number: int = bytes.decode_u16(at)
		var id: Array = _decode_id(bytes, at + 2, end)
		if id.is_empty() or (id[1] as int) >= end:
			return "staff %d is cut short or is not an id" % staff
		at = id[1]
		var slots: int = bytes[at]
		at += 1
		var cards: Array[StringName] = []
		for slot in slots:
			var card: Array = _decode_id(bytes, at, end)
			if card.is_empty():
				return "staff %d is cut short or holds a card that is not an id" % staff
			cards.append(card[0])
			at = card[1]
		if not add_staff(number, id[0], cards):
			return "staff %d (number %d, '%s', %d cards) is past a limit or numbered twice" % [staff, number, id[0], slots]
	read_to = at
	return ""


## The HANDS section's payload, as `_read_bags`.
func _read_hands(bytes: PackedByteArray, at: int, end: int) -> String:
	if at >= end:
		return "the hands are cut short"
	var count: int = bytes[at]
	at += 1
	if at + 2 * count > end:
		return "the hands are cut short"
	var numbers := PackedInt32Array()
	for hand in count:
		var number: int = bytes.decode_u16(at + 2 * hand)
		numbers.append(NO_STAFF if number == _NO_STAFF_BYTES else number)
	if not set_hands(numbers):
		return "the hands %s hold a staff it does not own, or one twice" % numbers
	read_to = at + 2 * count
	return ""


# --- Inside -----------------------------------------------------------------------------

## True for a name: an id that is not empty.
static func _is_name(id: StringName) -> bool:
	return id != &"" and InputFrame.is_id(String(id))


static func _id_bytes(id: StringName) -> int:
	return 1 + String(id).length()


static func _encode_id(out: PackedByteArray, id: StringName) -> void:
	var text: PackedByteArray = String(id).to_ascii_buffer()
	out.append(text.size())
	out.append_array(text)


static func _encode_u16(out: PackedByteArray, value: int) -> void:
	var at: int = out.size()
	out.resize(at + 2)
	out.encode_u16(at, value)


## The id at `at` in `bytes[:end]` and where the next value starts, or [] when there is no valid
## id there (cut short, too long, or a byte that is not a letter, a digit or `_`).
static func _decode_id(bytes: PackedByteArray, at: int, end: int) -> Array:
	if at >= end:
		return []
	var length: int = bytes[at]
	if length > InputFrame.MAX_TEXT or at + 1 + length > end:
		return []
	var raw: PackedByteArray = bytes.slice(at + 1, at + 1 + length)
	for byte in raw:
		var ok: bool = (byte >= 97 and byte <= 122) or (byte >= 65 and byte <= 90) or (byte >= 48 and byte <= 57) or byte == 95
		if not ok:
			return []
	return [StringName(raw.get_string_from_ascii()), at + 1 + length]


func _to_string() -> String:
	var parts := PackedStringArray()
	for at in _bags.size():
		parts.append("%s %s x%s" % [_bags[at], _stack_ids[at], _stack_counts[at]])
	for at in _numbers.size():
		parts.append("staff %d %s %s" % [_numbers[at], _staff_ids[at], _staff_cards[at]])
	return "PlayerLoadout(%s, hands %s)" % [", ".join(parts), _hands]
