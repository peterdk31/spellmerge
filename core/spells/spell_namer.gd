class_name SpellNamer
extends RefCounted
## Builds the name of a cast from its cards (staffs E1; docs/milestones/M2-staffs.md, "The
## builder"): long, funny and meant to be read out loud. The words come from the cards
## (`SpellComponent.name_words`), so a new card brings its own and no shared list changes.
##
## `[multicast-]adjectives infusions Noun of [Sudden] Payloads`, for example
## "Twice-Seeking Firefrost Bolt of Sudden Novas" for `double · homing · fire · frost · bolt ·
## on hit · nova`. A plain bolt is "Bolt". Modifiers are adjectives (the first three), infusions
## fuse into one word, a trigger's word and the plural of its payload follow "of", and a
## multicast card is a hyphenated prefix. The name depends only on the cards the cast read, in
## order, so the same cards always give the same name; a card with several words has one picked
## by its own id alone (so editing other cards never rewords it), except in a plain carrier,
## which always gets the card's first word. A name is kept short: see the limits below.

## Adjectives from modifiers kept in one carrier's name; the rest still work, they just are not
## said, so a name stays something a person can read out in one breath.
const MAX_ADJECTIVES: int = 3
## Multicast prefixes kept in one group's name.
const MAX_PREFIXES: int = 2
## Carriers said in one group, and how many levels of payload are said below the cast; the rest
## still work, the name ends "and more" or stops at "of ...".
const MAX_CARRIERS: int = 3
const MAX_DEPTH: int = 2
## The longest name, in characters: a longer one is cut at a word and ends "...".
const MAX_LENGTH: int = 90
## What cards that landed on the caster or on a payload's origin are called, in place of a noun.
const CASTER_NOUN: String = "Aura"
const POINT_NOUN: String = "Flare"

## id -> SpellComponent (or null for an unknown id).
var _lookup: Callable


func _init(lookup: Callable) -> void:
	_lookup = lookup


## The name of `cast`, whose slots index `cards` (the card ids of the staff). Empty for a cast
## that fires nothing.
func name_cast(cast: CompiledCast, _cards: Array[StringName]) -> String:
	if cast.group == null or cast.group.is_empty():
		return ""
	return _shorten(_group_name(cast.group, false, 0))


## `text` cut at a word to MAX_LENGTH, ending "...".
static func _shorten(text: String) -> String:
	if text.length() <= MAX_LENGTH:
		return text
	var cut: String = text.left(MAX_LENGTH - 3)
	var space: int = cut.rfind(" ")
	if space > 0:
		cut = cut.left(space)
	return cut + "..."


## The names of a group's carriers joined with "and", behind the group's multicast prefix.
## `plural` is true for a payload: "Novas".
func _group_name(group: CompiledGroup, plural: bool, depth: int) -> String:
	var pieces: PackedStringArray = PackedStringArray()
	for spell in group.spells.slice(0, MAX_CARRIERS):
		var parts: PackedStringArray = _spell_parts(spell, depth)
		pieces.append((_pluralize(parts[0]) if plural else parts[0]) + parts[1])
	if pieces.is_empty():
		return ""
	if group.spells.size() > MAX_CARRIERS:
		pieces.append("more")
	var prefix: String = _prefix(group)
	if prefix != "":
		pieces[0] = prefix + "-" + pieces[0]
	return " and ".join(pieces)


## A carrier's name in two parts: the head ("Seeking Firefrost Bolt") and the tail of what it
## carries (" of Sudden Novas", or "").
func _spell_parts(spell: CompiledSpell, depth: int) -> PackedStringArray:
	var carries: bool = (spell.payload != null and not spell.payload.is_empty()) \
			or (spell.own_payload != null and not spell.own_payload.is_empty())
	var plain: bool = spell.element_ids.is_empty() and spell.modifier_ids.is_empty() and not carries
	var words: PackedStringArray = PackedStringArray()
	for id: StringName in spell.modifier_ids.slice(0, MAX_ADJECTIVES):
		words.append(_word(id, plain))
	var fused: String = ""
	for id: StringName in spell.element_ids:
		var word: String = _word(id, plain)
		fused += word if fused == "" else word.to_lower()
	if fused != "":
		words.append(fused)
	if spell.form_id != &"":
		words.append(_word(spell.form_id, plain))
	else:
		words.append(CASTER_NOUN if spell.fallback == CompiledSpell.FALLBACK_CASTER else POINT_NOUN)
	var tail: PackedStringArray = PackedStringArray()
	if depth >= MAX_DEPTH:
		return PackedStringArray([" ".join(words), ""])
	if spell.own_payload != null and not spell.own_payload.is_empty():
		tail.append(_group_name(spell.own_payload, true, depth + 1))
	if spell.payload != null and not spell.payload.is_empty():
		var said: String = _group_name(spell.payload, true, depth + 1)
		var trigger: String = _word(spell.trigger_id, false) if spell.trigger_id != &"" else ""
		tail.append(trigger + " " + said if trigger != "" else said)
	var suffix: String = " of " + " and ".join(tail) if not tail.is_empty() else ""
	return PackedStringArray([" ".join(words), suffix])


## The multicast words of a group, joined with hyphens ("Rapid-Twice"), or "".
func _prefix(group: CompiledGroup) -> String:
	var words: PackedStringArray = PackedStringArray()
	for id: StringName in group.multicast_ids.slice(0, MAX_PREFIXES):
		words.append(_word(id, false))
	return "-".join(words)


## One word of card `id`: its first when `plain`, else the one its id picks. A card with
## no `name_words` says its display name.
func _word(id: StringName, plain: bool) -> String:
	var card: SpellComponent = _lookup.call(id) as SpellComponent
	if card == null:
		return String(id).capitalize()
	var words: PackedStringArray = card.name_words
	if words.is_empty():
		return card.display_name if card.display_name != "" else String(id).capitalize()
	return words[0 if plain else _hash(String(id)) % words.size()]


## The plural of the last word of `text`: Bolt -> Bolts, Fox -> Foxes, Fly -> Flies.
static func _pluralize(text: String) -> String:
	if text == "":
		return text
	var last: String = text.right(1).to_lower()
	var before: String = text.right(2).left(1).to_lower() if text.length() > 1 else ""
	if last == "y" and not "aeiou".contains(before):
		return text.left(text.length() - 1) + "ies"
	if last in ["s", "x", "z"] or text.ends_with("ch") or text.ends_with("sh"):
		return text + "es"
	return text + "s"


## A hash that never changes between runs or builds (djb2), unlike `String.hash` which Godot
## may change between versions.
static func _hash(text: String) -> int:
	var h: int = 5381
	for i in text.length():
		h = (h * 33 + text.unicode_at(i)) & 0x7fffffff
	return h
