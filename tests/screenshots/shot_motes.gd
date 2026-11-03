extends "res://tests/support/screenshot.gd"
## Screenshots of motes (gameplay/feel/mote.gd; docs/milestones/spell-spectacle.md, P1a): a burst
## of each kind on the crypt floor (ember, spark, chip, shard, ash, splinter, then a wall hit's
## chips and sparks as Feel throws them), at 0.05, 0.3, 0.8 and 1.8 s after they were thrown, one
## row each, at 2x (`motes_kinds`). The pool runs on a clock of its own, so every row is the same
## burst at that moment.

const MotesScript := preload("res://gameplay/feel/mote.gd")
const TIMES: Array[float] = [0.05, 0.3, 0.8, 1.8]
const ROW_TOP: int = 120
const ROW_HEIGHT: int = 110
const COLUMN: float = 80.0
const BORN: float = 1.0


func take() -> void:
	lay_floor()
	var motes: MotesScript = MotesScript.new(8192, 0)
	root.add_child(motes)
	motes.step(BORN)
	var y: float = 200.0
	var x: float = 60.0
	motes.burst(MotesScript.EMBER, Vector2(x, y), Vector2.UP, 30, Vector2(10.0, 40.0), 360.0, Vector2(10.0, 30.0), Vector2(0.8, 2.0), MotesScript.RAMP_FIRE)
	x += COLUMN
	motes.burst(MotesScript.SPARK, Vector2(x, y), Vector2.UP, 30, Vector2(60.0, 160.0), 360.0, Vector2(20.0, 70.0), Vector2(0.2, 0.6), MotesScript.RAMP_SPARK, 6.0)
	x += COLUMN
	motes.burst(MotesScript.CHIP, Vector2(x, y), Vector2.UP, 30, Vector2(20.0, 80.0), 360.0, Vector2(40.0, 100.0), Vector2(1.5, 2.5), MotesScript.RAMP_STONE, 6.0)
	x += COLUMN
	motes.burst(MotesScript.SHARD, Vector2(x, y), Vector2.UP, 30, Vector2(20.0, 80.0), 360.0, Vector2(40.0, 100.0), Vector2(1.5, 2.5), MotesScript.RAMP_ICE, 6.0)
	x += COLUMN
	motes.burst(MotesScript.ASH, Vector2(x, y), Vector2.UP, 30, Vector2(5.0, 25.0), 360.0, Vector2(10.0, 30.0), Vector2(1.5, 2.5), MotesScript.RAMP_STONE, 10.0)
	x += COLUMN
	motes.burst(MotesScript.SPLINTER, Vector2(x, y), Vector2.UP, 30, Vector2(20.0, 80.0), 360.0, Vector2(40.0, 100.0), Vector2(1.5, 2.5), MotesScript.RAMP_WOOD, 6.0)
	x += COLUMN
	# A bolt of player 1 ending on a wall to its right, as Feel throws it.
	motes.burst(MotesScript.CHIP, Vector2(x, y), Vector2.LEFT, 10, Vector2(30.0, 110.0), 150.0, Vector2(20.0, 80.0), Vector2(1.0, 2.5), MotesScript.RAMP_STONE, 4.0)
	motes.burst(MotesScript.SPARK, Vector2(x, y), Vector2.LEFT, 4, Vector2(80.0, 180.0), 110.0, Vector2(10.0, 50.0), Vector2(0.15, 0.35), 0, 4.0)
	var sheet := Image.create_empty(int(SCREEN.x), ROW_HEIGHT * TIMES.size(), false, Image.FORMAT_RGBA8)
	for i in TIMES.size():
		motes.step(BORN + TIMES[i])
		await settle(3)
		var image: Image = await grab()
		image.convert(Image.FORMAT_RGBA8)
		var scale_to_image: float = float(image.get_width()) / SCREEN.x
		var region: Image = image.get_region(Rect2i(0, int(ROW_TOP * scale_to_image), image.get_width(), int(ROW_HEIGHT * scale_to_image)))
		region.resize(int(SCREEN.x), ROW_HEIGHT, Image.INTERPOLATE_NEAREST)
		sheet.blit_rect(region, Rect2i(Vector2i.ZERO, region.get_size()), Vector2i(0, ROW_HEIGHT * i))
	sheet.resize(sheet.get_width() * 2, sheet.get_height() * 2, Image.INTERPOLATE_NEAREST)
	save(sheet, "motes_kinds")
