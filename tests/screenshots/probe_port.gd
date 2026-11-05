extends SceneTree
## Flash kinds F2's port check (docs/milestones/flash-kinds.md): every kind the flash shader drew
## from code, drawn by the shader before F2 (`old_shot_flash.gdshader`, its kind coded beside its
## age) and by the new one (its kind's table row), at the same ages, zooms, aims, ramps and looks;
## the two images are compared pixel by pixel. Run on a display, in the compatibility renderer:
##   xvfb-run godot --path . --rendering-driver opengl3 --script res://tests/screenshots/probe_port.gd
## (on a display: it draws offscreen, so its window shows only the background). F2's result: 4,752
## cases, every pixel the same. Not a screenshot sheet (no `shot_` name): deleted after F2.

const FeelScript := preload("res://gameplay/feel/feel.gd")
const BatchesScript := preload("res://core/projectiles/batches.gd")
const ManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const FlashTableScript := preload("res://gameplay/feel/flash_table.gd")
const OLD_SHADER: Shader = preload("res://tests/screenshots/old_shot_flash.gdshader")
const NEW_SHADER: Shader = preload("res://core/projectiles/shot_flash.gdshader")
const ActorsScript := preload("res://core/actors/actors.gd")
const FIRE: Resource = preload("res://content/spells/elements/fire/fire.tres")
## Each ported kind and its code in the old shader (KIND_* before F2), and the old POOF look bit.
const OLD_CODES: Dictionary = {&"rise": 1, &"fall": 2, &"quake": 3, &"burst": 4, &"ring_out": 5, &"ring_in": 6,
	&"rune_burst": 7, &"cast": 8, &"spray": 11, &"puff": 12, &"poof": 12}
const POOF: int = 1 << 21
## The ported kinds' files.
const KINDS: Dictionary = {
	&"rise": preload("res://content/flashes/rise.tres"),
	&"fall": preload("res://content/flashes/fall.tres"),
	&"quake": preload("res://content/flashes/quake.tres"),
	&"burst": preload("res://content/flashes/burst.tres"),
	&"ring_out": preload("res://content/flashes/ring_out.tres"),
	&"ring_in": preload("res://content/flashes/ring_in.tres"),
	&"rune_burst": preload("res://content/flashes/rune_burst.tres"),
	&"cast": preload("res://content/flashes/cast.tres"),
	&"spray": preload("res://content/flashes/spray.tres"),
	&"puff": preload("res://content/flashes/puff.tres"),
	&"poof": preload("res://content/flashes/poof.tres"),
}
const CELL: int = 100
const SIZE: int = 2000


func _initialize() -> void:
	var kinds: Array[FlashKind] = []
	for id: StringName in OLD_CODES:
		kinds.append(KINDS[id] as FlashKind)
	var table := ImageTexture.create_from_image(FlashTableScript.image_of(kinds))
	# Every case: [kind row, age code (n / 128: exact in half floats either way), zoom, aim, ramp, look].
	var cases: Array = []
	for row in kinds.size():
		for n in range(3, 57, 3):
			for zoom: int in [1, 2, 4]:
				for aim: Vector2 in [Vector2.RIGHT, Vector2.from_angle(0.6)]:
					for ramp: int in [1, ActorsScript.RAMP_ENEMY]:
						for fire: bool in [false, true]:
							cases.append([row, float(n) / 128.0, zoom, aim, ramp, fire])
	var per_image: int = (SIZE / CELL) * (SIZE / CELL)
	var differ: int = 0
	var pixels: int = 0
	var worst: float = 0.0
	var differing_kinds: Dictionary = {}
	var start: int = 0
	while start < cases.size():
		var batch: Array = cases.slice(start, start + per_image)
		var old_image: Image = await _draw(batch, kinds, table, true)
		var new_image: Image = await _draw(batch, kinds, table, false)
		for y in SIZE:
			for x in SIZE:
				var a: Color = old_image.get_pixel(x, y)
				var b: Color = new_image.get_pixel(x, y)
				if a.r8 + a.g8 + a.b8 + b.r8 + b.g8 + b.b8 > 0:
					pixels += 1
				if a != b:
					differ += 1
					worst = maxf(worst, maxf(maxf(absf(a.r - b.r), absf(a.g - b.g)), absf(a.b - b.b)))
					var cell: int = (y / CELL) * (SIZE / CELL) + x / CELL
					if cell < batch.size():
						differing_kinds[kinds[batch[cell][0]].id] = int(differing_kinds.get(kinds[batch[cell][0]].id, 0)) + 1
		start += per_image
	print("PORT: %d cases, %d lit pixels, %d differ (worst %.4f a channel) %s" % [cases.size(), pixels, differ, worst, differing_kinds])
	quit(0 if differ == 0 else 1)


func _draw(batch: Array, kinds: Array[FlashKind], table: Texture2D, old: bool) -> Image:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(SIZE, SIZE)
	viewport.transparent_bg = false
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var node := MultiMeshInstance2D.new()
	var mm: MultiMesh = BatchesScript.multimesh()
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = FeelScript.flash_mesh()
	mm.instance_count = batch.size()
	var buffer := PackedFloat32Array()
	buffer.resize(batch.size() * 16)
	var columns: int = SIZE / CELL
	for i in batch.size():
		var c: Array = batch[i]
		var kind: FlashKind = kinds[c[0]]
		var zoom: int = c[2]
		var dir: Vector2 = c[3]
		var d: float = 24.0 * zoom
		var at := Vector2((i % columns) * CELL + CELL / 2, (i / columns) * CELL + CELL / 2)
		var look: int = ManagerScript.pack_look(PackedInt32Array([int(FIRE.get("look_layer"))])) if c[5] else 0
		if old and kind.id == &"poof":
			look |= POOF
		var data: Color = ManagerScript.look_color(c[4], zoom, look)
		var code: int = OLD_CODES[kind.id] if old else FeelScript.FLASH_TABLE_CODE
		var tint: Color = FIRE.get("tint") as Color if c[5] else Color.WHITE
		var row: PackedFloat32Array = [dir.x * d, dir.y * d, 0.0 if old else float(c[0]), at.x, dir.y * d, -dir.x * d, 0.0, at.y,
			data.r, data.g, data.b, data.a, tint.r, tint.g, tint.b, 1.0 - (float(code) + float(c[1])) / 16.0]
		for k in 16:
			buffer[i * 16 + k] = row[k]
	mm.buffer = buffer
	node.multimesh = mm
	var material := ShaderMaterial.new()
	material.shader = OLD_SHADER if old else NEW_SHADER
	if not old:
		material.set_shader_parameter(&"flash_table", table)
	node.material = material
	viewport.add_child(node)
	for f in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = viewport.get_texture().get_image()
	viewport.queue_free()
	return image
