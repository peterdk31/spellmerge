class_name RewardType
extends RefCounted
## What a reward room holds (the owner, 2026-11-19: "make the reward rooms state which card type they
## contain"): an item kind (a row of `ItemKinds.RULES`: a card, a potion, coins), for a card its kind
## (`SpellComponent.kind`) and, for an infusion, its element (the element card's id: an element is a
## card, `ElementBase`). Decided once as the biome is made (`BiomeGenerator`, kept in `BiomeMap` as
## hashed state), shown at the room's mouths and on the held map (gameplay/feel), and every wizard's
## roll there is made among items of it (`RewardRoll`).
##
## **Levels**, narrowest last: ANY (the whole table), ITEM (its item kind's lines), CARD_KIND (cards
## of its kind), ELEMENT (its element's one card). A roll starts at the narrowest level the type has
## and widens a level at a time while that level has nothing left the offer has not (`RewardRoll`).
## Plain data; travels as a row of three names (`to_row`, `from_row`: an event's and the room
## layout's, `LAYOUT_META`).

## The meta a laid room's layout carries its type under, as a row (`to_row`), for the view (Flow's
## `BiomeWorld` sets it, Feel's room hearing reads it).
const LAYOUT_META: StringName = &"reward_type"
## The levels.
const ANY: int = 0
const ITEM: int = 1
const CARD_KIND: int = 2
const ELEMENT: int = 3
## The card kind whose cards are elements (infusions).
const ELEMENT_KIND: StringName = &"element"

## The item kind (empty: any item), the card kind (empty: any) and the element card (empty: any).
var item: StringName = &""
var card_kind: StringName = &""
var element: StringName = &""


static func make(of_item: StringName = &"", of_card_kind: StringName = &"", of_element: StringName = &"") -> RewardType:
	var made := RewardType.new()
	made.item = of_item
	made.card_kind = of_card_kind
	made.element = of_element
	return made


## The type a row (`to_row`) says; any for a row too short.
static func from_row(row: PackedStringArray) -> RewardType:
	if row.size() < 3:
		return RewardType.new()
	return make(StringName(row[0]), StringName(row[1]), StringName(row[2]))


func to_row() -> PackedStringArray:
	return PackedStringArray([String(item), String(card_kind), String(element)])


## The narrowest level it names (ANY for a room of no type).
func narrowest() -> int:
	if item == &"":
		return ANY
	if card_kind == &"":
		return ITEM
	return ELEMENT if element != &"" else CARD_KIND


func is_any() -> bool:
	return item == &""


## True when the table line `entry` may give an item of this type at level `level` (a card line is
## then asked of each card, `card_fits`).
func line_fits(entry: RewardEntry, level: int) -> bool:
	return entry != null and (level < ITEM or entry.kind == item)


## True when card `id` of kind `kind` is of this type at level `level`.
func card_fits(id: StringName, kind: StringName, level: int) -> bool:
	return (level < CARD_KIND or kind == card_kind) and (level < ELEMENT or id == element)


func same_as(other: RewardType) -> bool:
	return other != null and item == other.item and card_kind == other.card_kind and element == other.element
