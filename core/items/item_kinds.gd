class_name ItemKinds
extends RefCounted
## The kinds of item (items I3, docs/milestones/items.md, "The model"): one table answers the same
## questions for each kind, so the bags, the ground and the menus never name a kind. A new kind is a
## row here and its own code.
##
## - `bag`: the bag that holds it (`BAGS`, in the inventory's order).
## - `stacks`: whether copies of one id share one stack (a count) or each is a stack of its own.
## - `content`: the registry folders its ids are found in (core/registry), and `type`: the class a
##   resource there must be to be one of it (`is_content`).
## - `actions`: what can be done with one held (`can`). Whether one is used is not a kind's: its
##   content has a use (`usable`, `use_of`).
## - `premade`: the registry folders its premade items are found in (`premade_of`: the hub's rack,
##   a `StaffItem`; items I6), apart from its content.
## - `ids` (only for a kind that shares its bag with another, the currency's coins, keys and rerolls): the ids
##   it has, so a stack named by its bag and id alone is known to be of it (`kind_in(bag, id)`).
##
##     var bag: StringName = ItemKinds.bag_of(ItemKinds.CARD)   # &"cards"
##     if ItemKinds.stacks(stack.kind): ...

const RegistryScript := preload("res://core/registry/registry.gd")

const STAFF: StringName = &"staff"
const CARD: StringName = &"card"
const RELIC: StringName = &"relic"
const POTION: StringName = &"potion"
const COIN: StringName = &"coin"
const KEY: StringName = &"key"
const REROLL: StringName = &"reroll"
const SIGIL: StringName = &"sigil"

## The bags, in the order the inventory shows them (owner, 2026-11-13: Staffs, Cards, Relics, Potions;
## the currency after them, connected biomes CB10's follow-up, the owner's of 2026-11-19: the coins
## and the keys, "a currency bag (along with coins)"; the sigils before the currency, staff-language L4).
const BAGS: Array[StringName] = [&"staffs", &"cards", &"relics", &"potions", &"sigils", &"currency"]

## What can be done with one held.
const DROP: StringName = &"drop"
const DROP_ONE: StringName = &"drop_one"
const HAND: StringName = &"hand"

## One row a kind (see the class doc). A premade staff (`StaffItem`, `items`) is a staff of the
## `wizard` folder with its cards, so a stack's id is always its content's. A relic is a
## `RelicBase` (connected biomes CB10: its run stat changes, `RunStats`; no relic file exists yet).
## A potion is a `PotionBase` (content/potions), drunk from the bag (its content has a use, not its
## row: `usable`; the player controller's `bag_use_requested`); coins are a `CoinBase` (content/coins), one stack the player spends in a
## shop (the owner, 2026-11-19: every reward is an item, and coins are a stacked one); a key is a
## `KeyBase` (content/keys), one stack beside the coins in the currency bag, spent at a treasure
## room's door (the owner, 2026-11-19: "Keys are also just inventory items"); a reroll is a
## `RerollBase` (content/rerolls), one stack beside them, the reward reroll, spent by X in the
## reward picker (the owner, 2026-11-19); a sigil is a `SigilBase` (content/sigils), kept in its bag
## until put on a staff in the inventory menu (staff-language L4). Everything is dropped
## (the owner, 2026-11-19: "Everything is droppable"): a coin or a key one copy at a time, as a potion,
## lying as any item, taken by A into the taker's own bag (a dropped coin is not shared: only the
## coins a foe dies with are, gameplay/rewards).
const RULES: Dictionary = {
	&"staff": {"bag": &"staffs", "stacks": false, "content": [&"wizard"], "type": &"StaffBase", "actions": [&"drop", &"hand"], "premade": [&"items"]},
	&"card": {"bag": &"cards", "stacks": true, "content": [&"spells"], "type": &"SpellComponent", "actions": [&"drop_one"], "premade": []},
	&"relic": {"bag": &"relics", "stacks": false, "content": [&"relics"], "type": &"RelicBase", "actions": [&"drop"], "premade": []},
	&"potion": {"bag": &"potions", "stacks": true, "content": [&"potions"], "type": &"PotionBase", "actions": [&"drop"], "premade": []},
	&"coin": {"bag": &"currency", "stacks": true, "content": [&"coins"], "type": &"CoinBase", "actions": [&"drop"], "premade": [], "ids": [&"coin"]},
	&"key": {"bag": &"currency", "stacks": true, "content": [&"keys"], "type": &"KeyBase", "actions": [&"drop"], "premade": [], "ids": [&"key"]},
	&"sigil": {"bag": &"sigils", "stacks": true, "content": [&"sigils"], "type": &"SigilBase", "actions": [&"drop"], "premade": []},
	&"reroll": {"bag": &"currency", "stacks": true, "content": [&"rerolls"], "type": &"RerollBase", "actions": [&"drop"], "premade": [], "ids": [&"reward_reroll"]},
}
## The class of a kind with none of its own yet.
const NO_CLASS: StringName = &"Resource"


## Every kind, in the table's order.
static func kinds() -> Array[StringName]:
	var out: Array[StringName] = []
	for kind: StringName in RULES:
		out.append(kind)
	return out


## True when `kind` is a row of the table.
static func has(kind: StringName) -> bool:
	return RULES.has(kind)


## The bag that holds `kind` (`&""` for no kind).
static func bag_of(kind: StringName) -> StringName:
	return StringName(_row(kind).get("bag", &""))


## The kind of the item `id` in bag `bag` (`&""` for no bag): the bag's one kind, or, in a bag of
## several (the currency), the one whose `ids` holds `id` (its first kind for an id none holds, or
## none given).
static func kind_in(bag: StringName, id: StringName = &"") -> StringName:
	var first: StringName = &""
	for kind: StringName in RULES:
		if bag_of(kind) != bag:
			continue
		if first == &"":
			first = kind
		if id != &"" and (_row(kind).get("ids", []) as Array).has(id):
			return kind
	return first


## Every kind bag `bag` holds, in the table's order.
static func kinds_in(bag: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	for kind: StringName in RULES:
		if bag_of(kind) == bag:
			out.append(kind)
	return out


## True when copies of one id of `kind` share one stack.
static func stacks(kind: StringName) -> bool:
	return bool(_row(kind).get("stacks", false))


## The registry folders the ids of `kind` are found in.
static func content_of(kind: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	for folder: Variant in _row(kind).get("content", []):
		out.append(StringName(folder))
	return out


## True when `resource` (found in one of `content_of(kind)`) is one of `kind`: its class is the
## row's `type`, or extends it.
static func is_content(kind: StringName, resource: Resource) -> bool:
	if resource == null or not has(kind):
		return false
	var type: StringName = StringName(_row(kind).get("type", &""))
	var script: Script = resource.get_script() as Script
	while script != null:
		if script.get_global_name() == type:
			return true
		script = script.get_base_script()
	return resource.is_class(String(type))


## The registry folders the premade items of `kind` are found in (the hub's rack).
static func premade_of(kind: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	for folder: Variant in _row(kind).get("premade", []):
		out.append(StringName(folder))
	return out


## One of what `resource` is, as a stack (what lies where a room places it, items I6): a premade
## staff its staff with its cards (`StaffItem.stack`), a staff empty, a card one copy; null for
## anything that is no kind's (a kind with no class of its own included).
static func stack_of(resource: Resource) -> ItemStack:
	var kind: StringName = kind_of(resource)
	if kind == &"":
		return null
	if resource is StaffItem:
		return (resource as StaffItem).stack()
	if resource is StaffBase:
		return ItemStack.of_staff(resource as StaffBase)
	var made := ItemStack.new()
	made.kind = kind
	made.id = StringName(str(resource.get(&"id")))
	return made


## The kind `resource` is one of as `stack_of` would make it (`&""`: no kind's), without making
## the stack.
static func kind_of(resource: Resource) -> StringName:
	if resource is StaffItem:
		return STAFF if (resource as StaffItem).staff != null else &""
	for kind: StringName in RULES:
		if StringName(_row(kind).get("type", NO_CLASS)) == NO_CLASS or not is_content(kind, resource):
			continue
		return kind if StringName(str(resource.get(&"id"))) != &"" else &""
	return &""


## True when one held of `kind` can be `action`ed (DROP, DROP_ONE, HAND). Whether one is used is
## whether its own content has a use, never its kind's (`usable`).
static func can(kind: StringName, action: StringName) -> bool:
	return (_row(kind).get("actions", []) as Array).has(action)


## True when the item `id` of `bag` is usable: it has a use (`ItemContent.use_of`, an `ItemUse`; the
## owner, 2026-11-20: usable exactly when it has a use). Only such an item is used from the bag or
## bound to a d-pad arm. An item `registry` has no content of, one with no use (a coin, a passive
## relic) or of a kind that has none (a staff, a card), is not.
static func usable(bag: StringName, id: StringName, registry: RegistryScript) -> bool:
	return use_of(bag, id, registry) != null


## The use of the item `id` of `bag` (`ItemContent.use_of`), or null for none.
static func use_of(bag: StringName, id: StringName, registry: RegistryScript) -> ItemUse:
	var found := content(kind_in(bag, id), id, registry) as ItemContent
	return found.use_of() if found != null else null


## The content `kind` `id` is (the first of its row's folders that has it and is of its class), or
## null.
static func content(kind: StringName, id: StringName, registry: RegistryScript) -> Resource:
	if registry == null or id == &"":
		return null
	for folder: StringName in content_of(kind):
		var found: Resource = registry.get_resource(folder, id)
		if found != null and is_content(kind, found):
			return found
	return null


static func _row(kind: StringName) -> Dictionary:
	return RULES.get(kind, {}) as Dictionary
