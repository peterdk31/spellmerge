@tool
class_name RoomPreview
extends Node2D
## A node of a room's scene that only the editor draws (ground cover GC3,
## docs/milestones/ground-cover.md, rule 7): it shows something the game works out from the room
## (the whole room's ground cover: `CoverPreview`, tools/), so what is moved in the editor is seen
## as the game will show it. It places nothing and means nothing to the game: `RoomPlaces.read`
## passes over it, and it is taken out before play as placements and zones are
## (`RoomPlaces.strip`), so the room shown never holds it. A kind of preview extends this one.


## True for a preview that draws the room's ground cover (`CoverPreview`): the cover fields then
## leave their tufts to it.
func draws_cover() -> bool:
	return false
