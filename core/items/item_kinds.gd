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
## - `actions`: what can be done with one held (`can`).
## - `premade`: the registry folders its premade items are found in (`premade_of`: the hub's rack,
##   a `StaffItem`; items I6), apart from its content.
##
##     var bag: StringName = ItemKinds.bag_of(ItemKinds.CARD)   # &"cards"
##     if ItemKinds.stacks(stack.kind): ...

const STAFF: StringName = &"staff"
const CARD: StringName = &"card"
const RELIC: StringName = &"relic"
const POTION: StringName = &"potion"

## The bags, in the order the inventory shows them (owner, 2026-11-13: Staffs, Cards, Relics, Potions).
const BAGS: Array[StringName] = [&"staffs", &"cards", &"relics", &"potions"]

## What can be done with one held.
const DROP: StringName = &"drop"
const DROP_ONE: StringName = &"drop_one"
const HAND: StringName = &"hand"
const USE: StringName = &"use"

## One row a kind (see the class doc). A premade staff (`StaffItem`, `items`) is a staff of the
## `wizard` folder with its cards, so a stack's id is always its content's. Relics and potions do
## nothing yet, and their bags stay empty: with no class of their own (`type` a plain Resource)
## nothing is one of them on the ground (`stack_of`).
const RULES: Dictionary = {
	&"staff": {"bag": &"staffs", "stacks": false, "content": [&"wizard"], "type": &"StaffBase", "actions": [&"drop", &"hand"], "premade": [&"items"]},
	&"card": {"bag": &"cards", "stacks": true, "content": [&"spells"], "type": &"SpellComponent", "actions": [&"drop_one"], "premade": []},
	&"relic": {"bag": &"relics", "stacks": false, "content": [&"relics"], "type": &"Resource", "actions": [&"drop"], "premade": []},
	&"potion": {"bag": &"potions", "stacks": true, "content": [], "type": &"Resource", "actions": [&"drop", &"use"], "premade": []},
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


## The kind a bag holds (`&""` for no bag).
static func kind_in(bag: StringName) -> StringName:
	for kind: StringName in RULES:
		if bag_of(kind) == bag:
			return kind
	return &""


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
	if resource is StaffItem:
		return (resource as StaffItem).stack()
	for kind: StringName in RULES:
		if StringName(_row(kind).get("type", NO_CLASS)) == NO_CLASS or not is_content(kind, resource):
			continue
		var id: StringName = StringName(str(resource.get(&"id")))
		if id == &"":
			return null
		if resource is StaffBase:
			return ItemStack.of_staff(resource as StaffBase)
		var made := ItemStack.new()
		made.kind = kind
		made.id = id
		return made
	return null


## True when one held of `kind` can be `action`ed (DROP, DROP_ONE, HAND, USE).
static func can(kind: StringName, action: StringName) -> bool:
	return (_row(kind).get("actions", []) as Array).has(action)


static func _row(kind: StringName) -> Dictionary:
	return RULES.get(kind, {}) as Dictionary
