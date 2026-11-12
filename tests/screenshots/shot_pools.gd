extends "res://tests/support/screenshot.gd"
## Pools (the pool card's own `pool.gdshader`, its puddle): one row per infusion
## colour (fire, frost, mend, void, plain), one column per age, from spreading out to standing
## (`pools`, drawn twice as big), and one standing fire pool close up (`pools_close`).

const ActorSeats := preload("res://tests/support/actor_seats.gd")
const ProjectilesScript := preload("res://core/projectiles/projectile_manager.gd")

## The ages shown, in frames of 1/60 s.
const AGES: Array[int] = [1, 6, 14, 30, 60]
const COLUMN := 128
const POOL: Shader = preload("res://content/spells/carriers/pool/pool.gdshader")
const TINTS: Array[Color] = [Color("e0592f"), Color("4fd6dc"), Color("8fd46a"), Color("e08ad8"), Color(0, 0, 0, 0)]


func take() -> void:
	if not need(["Feel", "Events", "Projectiles"]):
		return
	settle_frames = 50
	root.get_node("Feel").set("drive_engine", false)
	var actors: ActorSeats.ActorsScript = ActorSeats.autoload()
	if actors == null:
		fail("there is no Actors autoload")
		return
	var wizard: int = ActorSeats.seat_wizards(actors, 1)[0]
	lay_floor()
	await settle()
	var projectiles: Node = root.get_node("Projectiles")
	var row_h: float = SCREEN.y / TINTS.size()
	var sheet: Image = null
	for column in AGES.size():
		var x: float = COLUMN * column + COLUMN * 0.5
		var tag: int = 7100 + column
		for r in TINTS.size():
			var at := Vector2(x, row_h * r + row_h * 0.5)
			var slot: int = projectiles.call("spawn", wizard, at, Vector2.ZERO, 5.0, 16.0, ProjectilesScript.LAYER_ENEMY, 0, tag, ProjectilesScript.MOTION_STILL)
			if TINTS[r].a > 0.0:
				projectiles.call("set_core", slot, TINTS[r])
			projectiles.call("set_carrier_card", slot, &"pool", projectiles.call("register_body", POOL))
		for i in AGES[column]:
			await process_frame
		var image: Image = await grab()
		if sheet == null:
			sheet = image
		else:
			sheet.blit_rect(image, Rect2i(COLUMN * column, 0, COLUMN, int(SCREEN.y)), Vector2i(COLUMN * column, 0))
		if column == AGES.size() - 1:
			save_crop(image, on_screen(Vector2(x, row_h * 0.5)), "pools_close", Vector2i(56, 36), 6)
		projectiles.call("remove_by_tag", tag)
		await settle()
	sheet.resize(sheet.get_width() * 2, sheet.get_height() * 2, Image.INTERPOLATE_NEAREST)
	save(sheet, "pools")
