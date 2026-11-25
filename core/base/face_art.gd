class_name FaceArt
extends Resource
## A face of its own (boss plan OB9, docs/milestones/boss-old-broom.md, "The broom's data", Look):
## the eye and brow sheets a `Face` draws in place of the shared ones (art/faces/eyes@2x.svg and
## brows.svg), for a body that should not wear a player's or a stray's eyes (a boss). The sheets
## keep the shared layout, at any frame size: the eyes sheet has ten columns (nine looks,
## (y + 1) × 3 + x + 1, then the blink) and a row a look of the face (`Face.art_row`: a phase may
## show another, `PhaseLook.face_row`); the brows sheet a column a mood (`Face.Mood`) and the same
## rows (a sheet with fewer rows shows its last). Read-only data, shared like a card; it lives with
## the body that wears it (its scene), so deleting that body's folder deletes it too.

## The eyes and brows sheets.
@export var eyes: Texture2D = null
@export var brows: Texture2D = null
## Every frame of both sheets, in pixels.
@export var frame: Vector2i = Vector2i(16, 8)
## Where, in a frame, the left eye's top-left pixel (the face's `anchor`) is: in the eyes sheet's
## frames, and in the brows sheet's (its brows drawn above that row).
@export var eyes_origin: Vector2 = Vector2(1.0, 1.0)
@export var brows_origin: Vector2 = Vector2(1.0, 5.0)

## The eyes sheet's columns: nine looks and the blink (Face.BLINK_COLUMN + 1), and the brows
## sheet's: a column a mood (Face.Mood).
const EYE_COLUMNS: int = 10
const BROW_COLUMNS: int = 5


## What keeps it from being drawn, one line each (empty when it is fine): a sheet missing, a frame
## size below 1, or a sheet too narrow for its columns or not a whole number of frames. A `Face`
## with art that has problems draws the shared sheets instead.
func problems() -> PackedStringArray:
	var found := PackedStringArray()
	if frame.x < 1 or frame.y < 1:
		found.append("its frame is %s; at least 1x1." % frame)
		return found
	for pair: Array in [[eyes, "eyes", EYE_COLUMNS], [brows, "brows", BROW_COLUMNS]]:
		var sheet: Texture2D = pair[0]
		if sheet == null:
			found.append("it has no %s sheet." % pair[1])
			continue
		var size := Vector2i(sheet.get_width(), sheet.get_height())
		if size.x % frame.x != 0 or size.y % frame.y != 0 or size.y < frame.y:
			found.append("its %s sheet is %s, not whole %s frames." % [pair[1], size, frame])
		elif size.x / frame.x < int(pair[2]):
			found.append("its %s sheet has %d columns; at least %d." % [pair[1], size.x / frame.x, pair[2]])
	return found

