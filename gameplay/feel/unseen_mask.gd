extends RefCounted
## Where nothing of the world is drawn because nobody has seen it yet (the owner, 2026-11-21, on
## #899: what stands in an unvisited room is hidden one by one, not covered): the rectangles
## `unseen_dark.gd` would once have covered whole in the void's black, each unvisited room's
## (its reveal not begun) and each secret room's hidden bridge's (`UnseenDark.covered_of`). Over
## them only the void shows, its motes drifting about.
##
## The one question every look asks of what it draws (`hides`: a point in one of them) and the count
## of the times they changed (`changes`), so a look that draws once and keeps it (the items on the
## ground, a rune's crack) draws again only then. The dark writes it (`lay`); a look reads it, and
## knows nothing of rooms, the party's map or the dark. View only: nothing in the game reads it.

## The rectangles hidden now (non-empty ones only). Read only.
var rects: Array[Rect2] = []
## How many times they changed. Read only.
var changes: int = 0


## Whether world point `at` lies where nothing is drawn now.
func hides(at: Vector2) -> bool:
	for rect in rects:
		if rect.has_point(at):
			return true
	return false


## Whether nothing is hidden now (every look draws all it has).
func is_empty() -> bool:
	return rects.is_empty()


## The hidden rectangles from `covers` (one a place, an empty one for a place not hidden), written in
## place: nothing is made unless more are hidden than ever before.
func lay(covers: Array[Rect2]) -> void:
	var at: int = 0
	for cover in covers:
		if not cover.has_area():
			continue
		if at < rects.size():
			rects[at] = cover
		else:
			rects.append(cover)
		at += 1
	rects.resize(at)
	changes += 1
