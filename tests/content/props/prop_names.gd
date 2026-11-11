extends RefCounted
## The names a prop's triggers may use, as `PropBase.problems` takes them (props W6): the elements
## (the registry's element cards), Combat's statuses and the reaction table's reactions.

const CombatScript := preload("res://gameplay/combat/combat.gd")


static func known(registry: Node) -> Dictionary:
	var elements := PackedStringArray()
	for item: Variant in registry.call("get_all", "spells"):
		if item is ElementBase:
			elements.append(String((item as ElementBase).id))
	var statuses := PackedStringArray()
	for status: StringName in CombatScript.STATUSES:
		statuses.append(String(status))
	var reactions := PackedStringArray()
	for row: ReactionRow in CombatScript.REACTIONS.rows:
		if not reactions.has(String(row.reaction_id)):
			reactions.append(String(row.reaction_id))
	return {&"element": elements, &"status": statuses, &"reaction": reactions}
