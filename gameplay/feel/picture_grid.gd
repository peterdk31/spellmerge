extends RefCounted
## The picture the game is laid out for, and how much bigger the picture it is drawn in is (the
## owner's decision of 2026-11-21, docs/milestones/connected-biomes.md, "The light at a fixed
## resolution"): the one place that says the light's resolution.
##
## - **The light's resolution:** the passes worked out a pixel at a time over the whole picture (the
##   spell light's buffers, its apply rect's light, the mist's billows) are drawn at SIZE a view,
##   however big the picture is drawn, and sampled up into it in whole blocks of `scale_of` pixels
##   each way (docs/STYLE.md, "Pixels stay hard": never blurred). A view of a split screen takes the
##   share of SIZE its share of the screen is.
## - **The cameras' zoom 1** shows SIZE of the world: a picture `scale_of` times bigger draws the same
##   world at that zoom times more (the party camera, the split's views), so a bigger picture is a
##   finer one, not a wider one.
##
## The shipped picture is SIZE (project.godot), so `scale_of` is 1 there and nothing is drawn at
## another size. A benchmark draws 1280 x 720 (tests/benchmark/biome_frames_runner.gd, `--picture=`).

## The picture's size the light is drawn at (a view's share of it), and at which the cameras' zoom
## is 1 (px).
const SIZE: Vector2i = Vector2i(640, 360)


## How many picture pixels each way one pixel of SIZE is in a picture of `picture` px: the largest
## whole number that fits both ways, at least 1.
static func scale_of(picture: Vector2) -> int:
	var across: int = floori(picture.x / float(SIZE.x) + 0.0001)
	var down: int = floori(picture.y / float(SIZE.y) + 0.0001)
	return maxi(mini(across, down), 1)
