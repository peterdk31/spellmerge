extends RefCounted
## Made-up cards for the radial builder's tests and screenshots: any number of them, so a ring
## of 0, 1, 2 or hundreds of cards can be checked long before the game has that many. Each card
## is a real card class (carrier, modifier, infusion, trigger, multicast) with plain numbers and
## a real icon, behind a stand-in registry that `Spells` reads like the real one.
##
##     const FakeCards := preload("res://tests/support/fake_cards.gd")
##     var registry: Node = FakeCards.registry(300)       # card_000 .. card_299, kinds in turn
##     spells.registry = registry
##     events.bag_changed.emit(0, FakeCards.ids(300))

## The kinds in the order the cards take them: card 0 a carrier, card 1 a modifier, and so on.
const KINDS: Array[StringName] = [&"form", &"modifier", &"element", &"trigger", &"multicast"]
const ICONS: Array[Texture2D] = [
	preload("res://content/spells/forms/bolt/icon.svg"),
	preload("res://content/spells/modifiers/split/icon.svg"),
	preload("res://content/spells/elements/fire/icon.svg"),
	preload("res://content/spells/triggers/on_hit/icon.svg"),
	preload("res://content/spells/forms/nova/icon.svg"),
]


## A registry stand-in with the two questions `Spells` asks.
class FakeRegistry:
	extends Node
	var items: Dictionary = {}

	func get_resource(_folder: StringName, id: StringName) -> Resource:
		return items.get(id)

	func get_lore(_about: StringName, _id: StringName) -> String:
		return ""


## The id of made-up card number `at`.
static func id(at: int) -> StringName:
	return StringName("card_%03d" % at)


## The ids of the first `count` made-up cards, in order.
static func ids(count: int) -> Array[StringName]:
	var out: Array[StringName] = []
	for at in count:
		out.append(id(at))
	return out


## A registry holding `count` made-up cards; with `kind` set every card is of that kind,
## otherwise the kinds take turns (KINDS).
static func registry(count: int, kind: StringName = &"") -> FakeRegistry:
	var made := FakeRegistry.new()
	for at in count:
		var card_kind: StringName = kind if kind != &"" else KINDS[at % KINDS.size()]
		var card: SpellComponent = _card(card_kind, at)
		card.id = id(at)
		card.display_name = "Card %d" % (at + 1)
		card.icon = ICONS[KINDS.find(card_kind)]
		made.items[card.id] = card
	return made


static func _card(kind: StringName, at: int) -> SpellComponent:
	match kind:
		&"form":
			var form := FormBase.new()
			form.base_damage = 1 + at % 9
			form.mana_cost = 2.0 + float(at % 7)
			form.cooldown = 0.25
			form.speed = 200.0
			return form
		&"modifier":
			var modifier := ModifierBase.new()
			modifier.damage_mult = 1.25
			modifier.mana_mult = 1.5
			return modifier
		&"element":
			var element := ElementBase.new()
			element.status_id = &"burn"
			element.status_duration = 2.0
			return element
		&"trigger":
			var trigger := TriggerBase.new()
			trigger.event = TriggerBase.Event.HIT
			return trigger
	var multicast := MulticastBase.new()
	multicast.extra_draws = 1
	return multicast
