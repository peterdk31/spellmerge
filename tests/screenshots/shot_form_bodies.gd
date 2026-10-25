extends SceneTree
## A sheet of the bodies of the forms in flight (#244, part 2b), for people and for Claude to
## look at. Needs a display, so it runs only through `ci/build/build.sh --quick --screenshots`;
## saved as user://screenshots/form_bodies.png.
##
## Rows (top to bottom): bolts (fire, frost, storm, void), runes in the four elements, orbit
## shots in the four elements. The right half (storm and void) is drawn in greyscale, so the
## forms are told apart without colour. The sheet is one moment; the clips `form_rune` and
## `form_orbit` show the pulse and the spin.

const SHOTS_DIR := "user://screenshots"
const SETTLE_FRAMES := 12

const FLOOR := preload("res://art/tilesets/crypt/floor.svg")
const ELEMENTS: Array[Resource] = [
	preload("res://content/spells/elements/fire/fire.tres"),
	preload("res://content/spells/elements/frost/frost.tres"),
	preload("res://content/spells/elements/storm/storm.tres"),
	preload("res://content/spells/elements/void/void.tres"),
]


func _initialize() -> void:
	await process_frame
	DirAccess.make_dir_recursive_absolute(SHOTS_DIR)
	var shots: Node = root.get_node_or_null("Projectiles")
	if shots == null:
		printerr("SHOT FAILED: the Projectiles autoload must exist")
		quit(1)
		return
	var floor_sprite := Sprite2D.new()
	floor_sprite.texture = FLOOR
	floor_sprite.centered = false
	floor_sprite.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	floor_sprite.region_enabled = true
	floor_sprite.region_rect = Rect2(0, 0, 640, 360)
	floor_sprite.z_index = -10
	root.add_child(floor_sprite)
	shots.call("set_bounds", Rect2(0, 0, 640, 360))
	shots.call("set_cap", 200)
	# Four columns, one per element.
	for _copy in 1:
		var top: float = 40.0
		for e in 4:
			var tint: Color = ELEMENTS[e].get("tint") as Color
			for p in 4:
				var x: float = 50.0 + e * 150.0 + p * 34.0
				var bolt: int = shots.call("spawn", p, Vector2(x, top), Vector2(0.01, 0.0), 60.0, 6.0) as int
				shots.call("set_core", bolt, tint)
				shots.call("set_shape", bolt, e + 1)
				var rune: int = shots.call("spawn", p, Vector2(x, top + 40.0), Vector2.ZERO, 60.0, 8.0, 1, 0, 0, 1) as int
				shots.call("set_core", rune, tint)
				shots.call("set_shape", rune, e + 1)
			# An anchor is per player, so the orbit row has one player (and element) a column.
			var anchor := Vector2(95.0 + e * 150.0, top + 100.0)
			shots.call("set_anchor", e, anchor)
			for n in 2:
				var orb: int = shots.call("spawn_orbit", e, 16.0, n * PI, 0.0001, 60.0, 6.0) as int
				shots.call("set_core", orb, tint)
	var grey := ColorRect.new()
	grey.position = Vector2(320.0, 0.0)
	grey.size = Vector2(320.0, 360.0)
	var material := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = "shader_type canvas_item;\nuniform sampler2D screen : hint_screen_texture, filter_nearest;\nvoid fragment() { float g = dot(texture(screen, SCREEN_UV).rgb, vec3(0.3, 0.59, 0.11)); COLOR = vec4(vec3(g), 1.0); }\n"
	material.shader = shader
	grey.material = material
	grey.z_index = 100
	root.add_child(grey)
	for i in SETTLE_FRAMES:
		await process_frame
	await RenderingServer.frame_post_draw
	if int(shots.get("drawn")) < 20:
		printerr("SHOT FAILED: the shots were not drawn")
		quit(1)
		return
	var image: Image = root.get_texture().get_image()
	var path: String = "%s/form_bodies.png" % SHOTS_DIR
	if image == null or image.save_png(path) != OK:
		printerr("SHOT FAILED: could not save " + path)
		quit(1)
		return
	print("SHOT: form_bodies (%dx%d)" % [image.get_width(), image.get_height()])
	quit(0)
