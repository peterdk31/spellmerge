extends "res://tests/support/screenshot.gd"
## Barriers' bubbles (gameplay/feel/barriers.gd: the mote shell, the owner's pick of 2026-11-06),
## round a wizard each, sent as combat sends them (`barrier_changed`), a column per moment:
## one, two and four charges; just after a block from the right (2 frames), the gap closing (12
## frames) and closed (40); the last charge bursting (3 frames); one running out (6 frames into its
## fade); then the size following the body: a small thing (hurt circle 2 px) and a boss's (32 px),
## two charges each; and shots with shield charges (the same rule): a still shot of two charges and
## a wall of five stones (a capsule round its row), in a player's ramp. `barriers` is the sheet, `barriers_4x` its first four columns enlarged. Mote
## throws are random, so two runs differ in their motes.

const WIZARD: Texture2D = preload("res://content/wizard/base/wizard_idle.svg")
const COLUMN: float = 56.0
const TOP: float = 70.0
## A wizard's hurt circle (content/wizard/base/wizard.tscn) and its middle above the feet.
const HURT: float = 8.0
const BODY: Vector2 = Vector2(0.0, -12.0)
## Each column: [charges given, then a change [charges, way] or [] for none, frames after it].
const COLUMNS: Array = [
	[1, [], 20], [2, [], 20], [4, [], 20],
	[2, [1, Vector2.LEFT], 2], [2, [1, Vector2.LEFT], 12], [2, [1, Vector2.LEFT], 40],
	[1, [0, Vector2.LEFT], 3], [1, [0, Vector2.ZERO], 6],
]


func take() -> void:
	if not need(["Feel", "Events", "Projectiles", "Actors"]):
		return
	var feel: Node = root.get_node("Feel")
	var events: Node = root.get_node("Events")
	var projectiles: Node = root.get_node("Projectiles")
	feel.set("drive_engine", false)
	feel.set("shake_enabled", false)
	lay_floor()
	await settle()
	var latest: int = 0
	for column: Array in COLUMNS:
		latest = maxi(latest, column[2] as int)
	for c in COLUMNS.size():
		var feet := Vector2(40.0 + c * COLUMN, TOP)
		var sprite: Sprite2D = place(WIZARD, 1.0, feet - Vector2(16.0, 28.0))
		sprite.region_enabled = true
		sprite.region_rect = Rect2(0.0, 0.0, 32.0, 32.0)
		projectiles.call("set_anchor", c, feet + BODY)
		events.emit_signal(&"barrier_changed", c, COLUMNS[c][0] as int, 30.0, 0, Vector2.ZERO, HURT)
	# The size follows the body: a small thing's and a boss's, below.
	for i in 2:
		var hurt: float = 2.0 if i == 0 else 32.0
		var middle := Vector2(60.0 + i * 120.0, 160.0)
		projectiles.call("set_anchor", 20 + i, middle)
		events.emit_signal(&"barrier_changed", 20 + i, 2, 30.0, 0, Vector2.ZERO, hurt)
	# Shots with shield charges: a still shot and a wall, a player's.
	var table: Node = root.get_node("Actors")
	var mine: int = table.call("open", 0, 0) as int
	projectiles.call("set_bounds", Rect2(Vector2.ZERO, SCREEN))
	var shot: int = projectiles.call("spawn", mine, Vector2(300.0, 160.0), Vector2.ZERO, 30.0, 4.0, 1, 0, 0, 1) as int
	projectiles.call("set_shield", shot, 2)
	var wall: int = projectiles.call("spawn", mine, Vector2(380.0, 160.0), Vector2.ZERO, 30.0, 4.0, 1, 0, 0, 1) as int
	projectiles.call("set_solid", wall, Vector2.UP, 5, 9.0)
	projectiles.call("set_shield", wall, 1)
	# Every shell up a while, then each column's change so many frames before the grab.
	for i in 20:
		feel.call("step", 1.0 / 60.0)
		await process_frame
	for left in range(latest, 0, -1):
		for c in COLUMNS.size():
			var change: Array = COLUMNS[c][1] as Array
			if not change.is_empty() and int(COLUMNS[c][2]) == left:
				var charges: int = int(change[0])
				events.emit_signal(&"barrier_changed", c, charges, 30.0 if charges > 0 else 0.0, 0, change[1] as Vector2, HURT)
		feel.call("step", 1.0 / 60.0)
		await process_frame
	var image: Image = await grab()
	save(image, "barriers")
	save_crop(image, Vector2(40.0 + 1.5 * COLUMN, TOP - 12.0), "barriers_4x", Vector2i(int(2.0 * COLUMN), 28))
