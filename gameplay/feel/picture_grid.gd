extends RefCounted
## The picture the game is laid out for, and how much bigger the picture it is drawn in is (the
## owner's decisions of 2026-11-21, docs/milestones/connected-biomes.md, "The light at a fixed
## resolution", and 2026-11-22, "One pass": nothing is drawn at SIZE for the light any more; the light
## and the mist are worked out a world pixel at a time where they are drawn).
##
## - **The cameras' zoom 1** shows SIZE of the world: a picture `scale_of` times bigger draws the same
##   world at that zoom times more (the party camera, the split's views), so a bigger picture is a
##   finer one, not a wider one. (The cameras rest at `PartyCamera.MAX_ZOOM`, 0.8, since
##   2026-11-23: 800 x 450 of the world in SIZE.)
##
## The shipped picture is SIZE (project.godot), so `scale_of` is 1 there and nothing is drawn at
## another size. A benchmark draws 1280 x 720 (bench/biome_frames_runner.gd, `--picture=`).

## The picture's size at which the cameras' zoom is 1 (px; a view's share of it).
const SIZE: Vector2i = Vector2i(640, 360)


## How many picture pixels each way one pixel of SIZE is in a picture of `picture` px: the largest
## whole number that fits both ways, at least 1.
static func scale_of(picture: Vector2) -> int:
	var across: int = floori(picture.x / float(SIZE.x) + 0.0001)
	var down: int = floori(picture.y / float(SIZE.y) + 0.0001)
	return maxi(mini(across, down), 1)
