extends RefCounted
## The ramp table (docs/milestones/spell-spectacle.md, P1 and P2): colours other than a spell's,
## as rows of four shades (white-hot, light, base, shadow) in a small texture that the motes'
## and the floor marks' shaders both read. A row is a set of colours from the room's or a body's
## own art (a wall's, `RoomBase.surface_colors`; a dying body's, `ArtPixels.colours_of`), named
## by its source, TABLE_SOURCE plus its row. Feel holds one table and hands it to both, so a mote
## that lands and the mark it leaves name the same row.
##
## A new set of colours takes the next row, the oldest when all ROWS are taken; the same colours
## keep their row.

## Rows, and shades a row.
const ROWS: int = 64
const SHADES: int = 4
## The source of row 0 (Motes.TABLE_SOURCE): below it a source is a spell's.
const TABLE_SOURCE: int = 16

var _image: Image = null
var _texture: ImageTexture = null
var _rows: Dictionary = {}
var _next: int = 0


func _init() -> void:
	_image = Image.create_empty(SHADES, ROWS, false, Image.FORMAT_RGBA8)
	_texture = ImageTexture.create_from_image(_image)


## The texture the shaders read (SHADES across, ROWS down).
func texture() -> ImageTexture:
	return _texture


## The source of `colours` (light, base, shadow; a fourth first is the white-hot, else the
## light): its row, written the first time; -1 for none.
func source(colours: PackedColorArray) -> int:
	if colours.is_empty():
		return -1
	var shades: PackedColorArray = colours if colours.size() >= SHADES else PackedColorArray([colours[0]]) + colours
	if _rows.has(shades):
		return TABLE_SOURCE + int(_rows[shades])
	var row: int = _next
	_next = (_next + 1) % ROWS
	for key: Variant in _rows.keys():
		if int(_rows[key]) == row:
			_rows.erase(key)
	_rows[shades] = row
	for shade in SHADES:
		_image.set_pixel(shade, row, shades[mini(shade, shades.size() - 1)])
	_texture.update(_image)
	return TABLE_SOURCE + row


## The colour of shade `index` (0 white-hot ... 3 shadow) of the row of the source `from`.
func shade(from: int, index: int) -> Color:
	return _image.get_pixel(index, from - TABLE_SOURCE)
