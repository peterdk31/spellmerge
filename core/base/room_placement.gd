@tool
class_name RoomPlacement
extends Node2D
## A thing placed in a room's scene (props W8c, docs/milestones/props.md, "W8c: a room foundation"):
## a point, its position where what it holds stands (a prop's or an enemy's feet), and the data of
## what stands there (`placed()`). Found at any depth of a room's scene, in the tree's order, so a
## piece of scene carries its own (`RoomPlaces.read`), and taken out before play (`RoomPlaces.strip`):
## the game makes the real body from the data (gameplay/flow/room_contents.gd).
##
## A kind of placed thing is a class extending this one (tools/: `PropStandIn`, `EnemyStandIn`),
## which shows it in the editor and says what its data is; nothing else changes for a new kind. An
## editor script, so its kinds draw in the editor; nothing of it runs in play but `placed()`.


## The data of what stands here (a `PropBase`, an `EnemyBase`, ...); null: nothing picked yet.
func placed() -> Resource:
	return null
