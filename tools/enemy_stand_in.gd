@tool
class_name EnemyStandIn
extends Node2D
## An enemy standing in a room's scene (props W8a/W8b; the training and shooting dummies): add one
## under the scene's `Dummies` (Add Child Node, "EnemyStandIn"), pick its `enemy` and move it where
## it stands. In the editor it shows the enemy's own scene there (its scripts do not run in the
## editor, so it is its art as placed). The game never shows it: Flow takes `Dummies` out of the
## room (`RoomPlaces.strip`) and stands the real enemy at its place, from `enemy`.
##
## An editor script (the owner's decision of 2026-11-11), so it lives in tools/.

## The enemy that stands here.
@export var enemy: EnemyBase = null:
	set(value):
		enemy = value
		_show_in_editor()


func _ready() -> void:
	_show_in_editor()


## Show the enemy's scene as a part of this node's own (internal, so the scene never saves it).
## The editor calls it; a test may too.
func show_body() -> void:
	for child in get_children(true):
		if child.get_meta(&"stand_in_part", false):
			remove_child(child)
			child.queue_free()
	if enemy == null or enemy.scene == null:
		return
	var body: Node = enemy.scene.instantiate()
	body.set_meta(&"stand_in_part", true)
	add_child(body, false, Node.INTERNAL_MODE_BACK)


func _show_in_editor() -> void:
	if Engine.is_editor_hint() and is_inside_tree():
		show_body()
