class_name StaffCode
extends RefCounted
## Staff codes (staffs D2; docs/milestones/M2-staffs.md, "The sandbox"): a staff's cards as one
## short line of text, to copy and paste so builds can be shared in Discussions.
##
## `sm1:double,fire,bolt,-,nova`: the version tag, then the card ids by slot, `-` for an empty
## slot (empty slots at the end are left off). A code is only card ids: `parse` accepts nothing
## else, checks every id with the caller's `known` test (the registry), and never runs or loads
## anything from the text. A bad code gives an `error` in words and no cards.

const PREFIX: String = "sm1:"
const SEPARATOR: String = ","
const EMPTY: String = "-"
const NO_CARD: StringName = &""
## The longest code taken, in characters, and the most slots it may name: far above any staff,
## so a pasted wall of text is refused before it is read.
const MAX_LENGTH: int = 600
const MAX_SLOTS: int = 40
## The longest card id taken.
const MAX_ID_LENGTH: int = 40


## The code of `cards` (card ids by slot, `&""` for an empty slot).
static func encode(cards: Array[StringName]) -> String:
	var last: int = -1
	for slot in cards.size():
		if cards[slot] != NO_CARD:
			last = slot
	var parts: PackedStringArray = PackedStringArray()
	for slot in last + 1:
		parts.append(EMPTY if cards[slot] == NO_CARD else String(cards[slot]))
	return PREFIX + SEPARATOR.join(parts)


## Read `text`: `{"ok": true, "cards": Array[StringName], "error": ""}` or `{"ok": false,
## "cards": [], "error": reason}`. `known` is a Callable (id: StringName) -> bool. The cards
## are padded with empty slots to `slots` when it is above 0, and a code with more cards than
## that is refused. Spaces and line breaks round the code are ignored; the prefix is not case
## sensitive and ids are written in lower case.
static func parse(text: String, known: Callable, slots: int = 0) -> Dictionary:
	var body: String = text.strip_edges()
	if body.length() > MAX_LENGTH:
		return _fail("That code is too long.")
	if not body.to_lower().begins_with(PREFIX):
		return _fail("That is not a staff code (it starts with \"%s\")." % PREFIX)
	body = body.substr(PREFIX.length())
	var cards: Array[StringName] = []
	if not body.strip_edges().is_empty():
		var parts: PackedStringArray = body.split(SEPARATOR)
		if parts.size() > MAX_SLOTS:
			return _fail("That code has too many cards.")
		for part in parts:
			var word: String = part.strip_edges()
			if word == EMPTY:
				cards.append(NO_CARD)
				continue
			if not _is_id(word):
				return _fail("That code has something that is not a card name.")
			if not known.call(StringName(word)):
				return _fail("Unknown card: %s." % word)
			cards.append(StringName(word))
	if slots > 0:
		if cards.size() > slots:
			return _fail("That staff has only %d slots." % slots)
		while cards.size() < slots:
			cards.append(NO_CARD)
	return {"ok": true, "cards": cards, "error": ""}


static func _fail(reason: String) -> Dictionary:
	var none: Array[StringName] = []
	return {"ok": false, "cards": none, "error": reason}


## True for a card id: lower-case letters, digits and underscores only.
static func _is_id(word: String) -> bool:
	if word.is_empty() or word.length() > MAX_ID_LENGTH:
		return false
	for i in word.length():
		var c: int = word.unicode_at(i)
		var ok: bool = (c >= 97 and c <= 122) or (c >= 48 and c <= 57) or c == 95
		if not ok:
			return false
	return true
