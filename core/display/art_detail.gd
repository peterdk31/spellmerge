class_name ArtDetail
extends RefCounted
## How finely a texture is drawn: the one rule for mixed art while the game is redrawn at 2x detail
## (the owner's decision of 2026-11-21, confirmed 2026-11-25; docs/STYLE.md, "The picture and the
## art's detail"; art/README.md, "Redrawing a sprite at 64x64").
##
## The world keeps its 32-unit tiles. Today's art has one art pixel a world unit (detail 1); a sprite
## redrawn at 64 x 64 for a 32-unit cell has two art pixels a world unit each way (detail 2) and is
## drawn at half its size, so it stands exactly where and as big as the art it replaces, its finer
## pixels showing one picture pixel each in the 1280 x 720 picture (PictureGrid,
## core/display/picture_grid.gd). Everything that measures a sprite (its frames, offsets, origins,
## grips) measures it in its own art pixels; everything that places it in the world, in world units.
##
## **How a texture says it:** its file's name ends in `@2x` before the extension
## (`head@2x.svg`, `eyes@2x.png`). Nothing else is needed: no import option, no list. A texture made
## in the game from art (a `TexturePage` region, a page of copied sheets) carries its source's
## detail with `mark`; a region of an atlas (an `AtlasTexture`) has its atlas's unless marked.
##
## **How a drawing takes it:** a Sprite2D's node scale is `draw_scale(texture)` (times any pose
## scale of its own), its `offset` and frame sizes stay in the texture's pixels, and its strips and
## frame counts (`hframes`, `vframes`) are as they were; `fit` sets it. A draw call with a rect sizes
## it `size_of(texture)`. A MultiMesh batch's quad is `size_of` its frame (`quad_size`). A look that
## rounds a place to whole pixels rounds it to its art's pixels (`snap`): a 2x sprite moves by half
## world units, which are whole pixels of the 1280 picture.

## The end of a file's base name that says its art has 2 art pixels a world unit.
const SUFFIX_2X: String = "@2x"
## The metadata a texture made in the game carries its detail under (`mark`).
const META: StringName = &"art_detail"


## Art pixels a world unit each way, of `texture` (1 for none): its mark (`mark`), else 2 when its
## file is named `<name>@2x.<ext>`, else its atlas's (an `AtlasTexture`), else 1.
static func of(texture: Texture2D) -> int:
	if texture == null:
		return 1
	if texture.has_meta(META):
		return maxi(int(texture.get_meta(META)), 1)
	if texture.resource_path.get_file().get_basename().ends_with(SUFFIX_2X):
		return 2
	var atlas := texture as AtlasTexture
	if atlas != null and atlas.atlas != null:
		return of(atlas.atlas)
	return 1


## Mark `texture` (one made in the game: a page's region, a copy) as drawn at `detail` art pixels a
## world unit; returns it.
static func mark(texture: Texture2D, detail: int) -> Texture2D:
	if texture != null:
		texture.set_meta(META, maxi(detail, 1))
	return texture


## The node scale that draws `texture` at its size in the world (`Vector2.ONE` at detail 1).
static func draw_scale(texture: Texture2D) -> Vector2:
	return Vector2.ONE / float(of(texture))


## `texture`'s size in the world (world units; its pixel size at detail 1).
static func size_of(texture: Texture2D) -> Vector2:
	return texture.get_size() / float(of(texture)) if texture != null else Vector2.ZERO


## A frame of `frame_px` art pixels of `texture`, in world units (a MultiMesh batch's quad).
static func quad_size(texture: Texture2D, frame_px: Vector2) -> Vector2:
	return frame_px / float(of(texture))


## A length in world units measured in `texture`'s art pixels (an origin, a grip, an offset).
static func to_art(texture: Texture2D, world: Vector2) -> Vector2:
	return world * float(of(texture))


## Show `sprite`'s texture at its size in the world, times `pose` (a stretch of its look's own).
static func fit(sprite: Sprite2D, pose: Vector2 = Vector2.ONE) -> void:
	sprite.scale = pose * draw_scale(sprite.texture)


## `point` (world units) on the nearest whole art pixel of art of `detail`: whole world units at 1,
## halves at 2 (a whole pixel of the 1280 x 720 picture at zoom 1).
static func snap(point: Vector2, detail: int) -> Vector2:
	var by: float = float(maxi(detail, 1))
	return (point * by).round() / by
