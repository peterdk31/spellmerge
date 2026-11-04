extends RefCounted
## Spectacle by card (docs/milestones/spell-spectacle-2.md, S2): the mote kinds and floor marks a
## shot's spell sheds, worked out from its cards. The spectacle owns one and asks it at every hit,
## end, wall, trail birth and cue.
##
## A shot's tag (every shot carries one; `core/spells/spell_tag.gd`) gives its spell's cards as plain
## ids (`Spells.cards_of`: its form, its infusions and its modifiers; nothing here reads a spell's
## fields), and `Spells.profile` which spell it is now. Each
## card's kinds are those that name it by id (`MoteKind.cards`, `MarkKind.cards`), else those that
## name its look layer (`look_layers`, today's rule); a spell's are its cards' together, and with
## none at all a shot sheds layer 0's motes. So a card gets motes and marks of its own with one new
## file naming it, nothing is packed into the shot (the look bits stay how a shot is drawn), and a
## card no kind names sheds exactly what its look layer sheds.
##
## Worked out once per spell and kept by its tag with the spell it was worked out for: a staff's
## build generation is a ring of 8, so after 8 rebuilds a tag can name another spell, and an entry
## is used only while `profile(tag)` is still the same spell. The entries are dropped once there are
## CACHE_MOST. A shot with no spell (an enemy's attack, a test's), and every shot while no kind
## names a card, sheds by its look as before, with no lookup at all. In a fight most hits in a
## frame are of a few spells, so a spell is checked against `profile` once a frame (`new_frame`),
## and each answer is kept for the rest of the frame by its tag and look: a hit of a tag and look
## seen this frame is one lookup (about as dear as `kinds_of_look` was).

const MotesScript := preload("res://gameplay/feel/mote.gd")
const MarksScript := preload("res://gameplay/feel/marks.gd")

## The registry folder the cards are in, and the most spells kept.
const SPELL_FOLDER: StringName = &"spells"
const CACHE_MOST: int = 512
## The look layers' bits of a packed look (layer n is bit n - 1).
const LAYER_BITS: int = (1 << MotesScript.LOOK_LAYERS) - 1


## One spell's kinds on one side (its motes, or its marks).
class SideKinds:
	## No card of the spell is named by any kind: its look's kinds, as for any shot.
	var plain: bool = true
	## The kinds that name its cards by id, all of them and by the cards' look layers.
	var own: PackedInt32Array = PackedInt32Array()
	var own_by_layer: Dictionary[int, PackedInt32Array] = {}
	## The look layers every card of which a kind names by id: their layers' kinds are not its.
	var cover: int = 0
	## Its kinds for a look's layer bits, and a trail birth's for a layer, once worked out.
	var looks: Dictionary[int, PackedInt32Array] = {}
	var layers: Dictionary[int, PackedInt32Array] = {}


## One spell's entry: the spell it was worked out for, and its two sides.
class Entry:
	var spell: Object = null
	## The frame it was last checked against `profile` (CardKinds' `_frame`).
	var frame: int = -1
	var motes: SideKinds = null
	var marks: SideKinds = null


## The spell runtime (anything with `profile(tag)`, only compared, and `cards_of(tag)`), and the
## registry the cards' look layers are read from (anything with `get_resource(folder, id)`); null
## for none (by look only).
var spells: Object = null
var registry: Object = null

var _motes: MotesScript = null
var _marks: MarksScript = null
## Whether any mote kind names a card (else every shot sheds its look's, asking nothing).
var _card_motes: bool = false
## `motes_of`'s answers this frame, by its tag and look (one int: `motes_of`).
var _seen: Dictionary = {}
## Frames so far (`new_frame`).
var _frame: int = 0
var _entries: Dictionary[int, Entry] = {}
## A card's look layer (0 for none: a form), read once.
var _layers: Dictionary[StringName, int] = {}


## The motes are `motes` from now on (null for none): what was worked out for the old ones goes.
func use_motes(motes: MotesScript) -> void:
	_motes = motes
	_card_motes = motes != null and motes.has_card_kinds()
	_entries.clear()
	_seen.clear()


## The floor marks are `marks` from now on (null for none).
func use_marks(marks: MarksScript) -> void:
	_marks = marks
	_entries.clear()


## Forget every spell worked out (a new registry or spell runtime).
func clear() -> void:
	_entries.clear()
	_layers.clear()
	_seen.clear()


## A new frame: the last answer kept is not used again (a staff rebuilt since may have taken its
## tag).
func new_frame() -> void:
	if not _seen.is_empty():
		_seen.clear()
	_frame += 1


## The mote kinds a shot of the tag `tag` and the look `look` sheds: its spell's cards' (above), or
## its look's (`Motes.kinds_of_look`) when it has no spell or no card of it is named. Kept: read
## it, never change it.
func motes_of(tag: int, look: int) -> PackedInt32Array:
	if not _card_motes or tag == 0:
		return _motes.kinds_of_look(look)
	# A tag is below 2^25 and a look's layers below 2^21: one int for both.
	var key: int = tag | ((look & LAYER_BITS) << 25)
	var seen: Variant = _seen.get(key)
	if seen != null:
		return seen
	var found: PackedInt32Array
	var entry: Entry = _entry(tag)
	if entry == null or entry.motes.plain:
		found = _motes.kinds_of_look(look)
	else:
		var bits: int = look & LAYER_BITS
		var known: Variant = entry.motes.looks.get(bits)
		if known == null:
			known = _look_kinds(entry.motes, bits, _motes, true)
			entry.motes.looks[bits] = known
		found = known
	_seen[key] = found
	return found


## The mote kinds a trail birth of look layer `layer` gives off for a shot of the tag `tag`: its
## spell's cards' of that layer (`Motes.kinds_of_layer` when it has none of its own). Kept.
func layer_motes(tag: int, layer: int) -> PackedInt32Array:
	if not _card_motes or tag == 0:
		return _motes.kinds_of_layer(layer)
	var entry: Entry = _entry(tag)
	if entry == null or entry.motes.plain:
		return _motes.kinds_of_layer(layer)
	var found: Variant = entry.motes.layers.get(layer)
	if found == null:
		var kinds := PackedInt32Array()
		if layer <= 0 or (entry.motes.cover >> (layer - 1)) & 1 == 0:
			kinds = _add(kinds, _motes.kinds_named_by_layer(layer))
		if entry.motes.own_by_layer.has(layer):
			kinds = _add(kinds, entry.motes.own_by_layer[layer])
		found = kinds if not kinds.is_empty() else _motes.kinds_of_layer(layer)
		entry.motes.layers[layer] = found
	return found


## The floor marks of the cards of a shot of the tag `tag` and the look `look` (for a cue's mark
## part with `"cards": true`): its spell's cards' (above), or its look's (`Marks.kinds_of_look`).
## Empty for none. Kept.
func marks_of(tag: int, look: int) -> PackedInt32Array:
	if _marks == null:
		return PackedInt32Array()
	if not _marks.has_card_kinds():
		return _marks.kinds_of_look(look)
	var entry: Entry = _entry(tag)
	if entry == null or entry.marks.plain:
		return _marks.kinds_of_look(look)
	var bits: int = look & LAYER_BITS
	var found: Variant = entry.marks.looks.get(bits)
	if found == null:
		found = _look_kinds(entry.marks, bits, _marks, false)
		entry.marks.looks[bits] = found
	return found


## The spells worked out and kept (for tests).
func kept() -> int:
	return _entries.size()


## The entry of the spell of `tag`, worked out the first time (and again when the tag names
## another spell now); null for a tag with no spell.
func _entry(tag: int) -> Entry:
	if tag == 0 or spells == null:
		return null
	var entry: Entry = _entries.get(tag)
	if entry != null and entry.frame == _frame:
		return entry
	var spell: Object = spells.profile(tag)
	if spell == null:
		return null
	if entry != null and entry.spell == spell:
		entry.frame = _frame
		return entry
	if _entries.size() >= CACHE_MOST:
		_entries.clear()
	entry = Entry.new()
	entry.spell = spell
	entry.frame = _frame
	var cards: Array[StringName] = spells.cards_of(tag)
	entry.motes = _side(cards, _motes)
	entry.marks = _side(cards, _marks)
	_entries[tag] = entry
	return entry


## The side of a spell of the cards `cards` on `kinds` (the motes or the marks; null for none).
func _side(cards: Array[StringName], kinds: Object) -> SideKinds:
	var side := SideKinds.new()
	if kinds == null:
		return side
	var named: int = 0
	var unnamed: int = 0
	for card in cards:
		var layer: int = _layer_of(card)
		var bit: int = (1 << (layer - 1)) if layer > 0 else 0
		var own: PackedInt32Array = kinds.kinds_of_card(card)
		if own.is_empty():
			unnamed |= bit
			continue
		named |= bit
		side.own = _add(side.own, own)
		side.own_by_layer[layer] = _add(side.own_by_layer.get(layer, PackedInt32Array()), own)
	side.plain = side.own.is_empty()
	side.cover = named & ~unnamed
	return side


## A not plain side's kinds for the look layer bits `bits`: the kinds of each layer not covered (in
## layer order, as `kinds_of_look`), then its own; layer 0's motes when that is none (`zero`).
static func _look_kinds(side: SideKinds, bits: int, kinds: Object, zero: bool) -> PackedInt32Array:
	var found := PackedInt32Array()
	var open: int = bits & ~side.cover
	for layer in range(1, MotesScript.LOOK_LAYERS + 1):
		if (open >> (layer - 1)) & 1 == 1:
			found = _add(found, kinds.kinds_named_by_layer(layer))
	found = _add(found, side.own)
	if found.is_empty() and zero:
		found = _add(found, kinds.kinds_named_by_layer(0))
	return found


## The look layer of the card `id` (an element's or a modifier's `look_layer`; 0 for a form, or a
## card the registry does not know).
func _layer_of(id: StringName) -> int:
	var known: Variant = _layers.get(id)
	if known != null:
		return known
	var layer: int = 0
	if registry != null:
		var card: Resource = registry.get_resource(SPELL_FOLDER, id)
		if card != null:
			var value: Variant = card.get(&"look_layer")
			if value != null:
				layer = clampi(int(value), 0, MotesScript.LOOK_LAYERS)
	_layers[id] = layer
	return layer


## `into` with each of `kinds` not in it yet appended.
static func _add(into: PackedInt32Array, kinds: PackedInt32Array) -> PackedInt32Array:
	for k in kinds:
		if not into.has(k):
			into.append(k)
	return into
