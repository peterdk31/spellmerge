class_name ReactionTable
extends Resource
## The element reactions (`content/spells/reactions.tres`, M2 part 8): one ReactionRow
## per pair of a status already on a target and the element of the hit. Data, so a new
## element is new files plus rows here. It has no `id` field, so the registry skips it;
## `gameplay/combat` loads it by its literal path.

@export var rows: Array[ReactionRow] = []


## The row for a hit of `element_id` on a target with `status_id`, or null when the two
## do not react.
func find(status_id: StringName, element_id: StringName) -> ReactionRow:
	for row in rows:
		if row != null and row.status_id == status_id and row.element_id == element_id:
			return row
	return null
