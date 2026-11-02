class_name ReactionTable
extends Resource
## The element reactions (`content/spells/reactions.tres`, M2 part 8): one ReactionRow
## per pair of a status already on a target and the element of the hit. Data, so a new
## element is new files plus rows here. It has no `id` field, so the registry skips it;
## `gameplay/combat` loads it by its literal path.

@export var rows: Array[ReactionRow] = []

## The rows by element, then by status (the first row of each pair), and how many rows that was
## built from: Combat looks up a reaction on every elemental hit (performance, 2026-11-02: a walk
## of every row's properties was a quarter of Combat's own time a hit). A row added or removed, or
## another array of rows, is seen; a row is not edited once the table has been searched.
var _by_element: Dictionary = {}
var _indexed: int = -1
var _indexed_rows: Array[ReactionRow] = []

const NONE: Dictionary = {}


## The row for a hit of `element_id` on a target with `status_id`, or null when the two
## do not react.
func find(status_id: StringName, element_id: StringName) -> ReactionRow:
	return for_element(element_id).get(status_id) as ReactionRow


## Every reaction a hit of `element_id` can set off, by the status it needs on the target
## (empty for an element that reacts with nothing). Read only.
func for_element(element_id: StringName) -> Dictionary:
	if _indexed != rows.size() or not is_same(_indexed_rows, rows):
		_index()
	return _by_element.get(element_id, NONE)


func _index() -> void:
	_by_element = {}
	for row in rows:
		if row == null:
			continue
		var by_status: Dictionary = _by_element.get(row.element_id, {})
		if not by_status.has(row.status_id):
			by_status[row.status_id] = row
		_by_element[row.element_id] = by_status
	_indexed = rows.size()
	_indexed_rows = rows
