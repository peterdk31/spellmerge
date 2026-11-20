class_name ItemLooks
extends RefCounted
## How an item looks to people (the owner, 2026-11-19: a reward's card shows the wrapped item's own
## icon, name and description): one answer for every kind, so the Rewards area's choices, a shop's
## shelf and the inventory show an item the same way. A card's are Spells' to say (no script
## outside core/spells reads a card); a staff's its `StaffBase`'s; any other kind's its content's
## (`ItemContent`, or a `RelicBase`: `shown_name`, `description`, `icon`), found in the registry
## folders of its row (`ItemKinds.content_of`). Static only; it keeps nothing.
##
##     var look: Dictionary = ItemLooks.of(ItemKinds.POTION, &"healing", registry, spells)
##     look["name"]   # "Healing Potion"

const SpellsScript := preload("res://core/spells/spells.gd")
const RegistryScript := preload("res://core/registry/registry.gd")


## The look of one `kind` `id`: `name` (its id in words when nothing names it), `icon` (null for
## none) and `description` ("" for none).
static func of(kind: StringName, id: StringName, registry: RegistryScript, spells: SpellsScript) -> Dictionary:
	var look: Dictionary = {"name": "", "icon": null, "description": ""}
	if kind == ItemKinds.CARD:
		if spells != null:
			look["name"] = spells.component_name(id)
			look["icon"] = spells.component_icon(id)
			look["description"] = spells.component_description(id)
	else:
		var content: Resource = content_of(kind, id, registry)
		if content is StaffBase:
			look["name"] = (content as StaffBase).shown_name()
		elif content != null:
			if content.has_method(&"shown_name"):
				look["name"] = str(content.call(&"shown_name"))
			look["icon"] = content.get(&"icon") as Texture2D
			look["description"] = str(content.get(&"description")) if content.get(&"description") != null else ""
	if String(look["name"]) == "":
		look["name"] = String(id).capitalize()
	return look


## The content `kind` `id` is (the first of its row's folders that has it and is of its class), or
## null.
static func content_of(kind: StringName, id: StringName, registry: RegistryScript) -> Resource:
	return ItemKinds.content(kind, id, registry)
