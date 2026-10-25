extends SceneTree
## A sheet of the real shot drawing, for people and for Claude to look at (it only checks
## that the shots were drawn). Needs a display, so it runs only through
## `ci/build/build.sh --quick --screenshots`; the shot is saved as
## user://screenshots/element_shots.png and copied to build/screenshots/.
##
## Left: bolts, one row per player (1-4) and one column per element (fire, frost, storm,
## void, plain arcane). The bone body shows the player, the core shows the element. Below:
## a rune and an orbit orb per player, each with another element. Right: a beam and a nova
## ring per player, drawn by `feel` from `form_shown`.

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
	var feel: Node = root.get_node_or_null("Feel")
	var events: Node = root.get_node_or_null("Events")
	if shots == null or feel == null or events == null:
		printerr("SHOT FAILED: the Projectiles, Feel and Events autoloads must exist")
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
	var tints: Array[Color] = []
	for element: Resource in ELEMENTS:
		tints.append(element.get("tint") as Color)
	tints.append(Color.WHITE)
	shots.call("set_bounds", Rect2(0, 0, 640, 360))
	shots.call("set_cap", 200)
	# Shots hardly move: the sheet is a still.
	for p in 4:
		for e in tints.size():
			var slot: int = shots.call("spawn", p, Vector2(40.0 + e * 44.0, 36.0 + p * 30.0), Vector2(0.01, 0.0), 60.0, 6.0) as int
			shots.call("set_core", slot, tints[e])
			shots.call("set_shape", slot, e + 1 if e < 4 else 0)
		var anchor := Vector2(40.0 + p * 76.0, 250.0)
		var rune: int = shots.call("spawn", p, anchor, Vector2.ZERO, 60.0, 8.0, 1, 0, 0, 1) as int
		shots.call("set_core", rune, tints[p])
		shots.call("set_anchor", p, anchor + Vector2(0.0, 60.0))
		var orb: int = shots.call("spawn_orbit", p, 24.0, 0.0, 0.0001, 60.0, 6.0) as int
		shots.call("set_core", orb, tints[(p + 1) % 4])
	# A strip in greyscale, to see that the four read without colour: one bolt per element.
	var grey := ColorRect.new()
	grey.position = Vector2(0.0, 168.0)
	grey.size = Vector2(250.0, 40.0)
	var material := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = "shader_type canvas_item;\nuniform sampler2D screen : hint_screen_texture, filter_nearest;\nvoid fragment() { float g = dot(texture(screen, SCREEN_UV).rgb, vec3(0.3, 0.59, 0.11)); COLOR = vec4(vec3(g), 1.0); }\n"
	material.shader = shader
	grey.material = material
	grey.z_index = 100
	root.add_child(grey)
	for e in 4:
		var slot: int = shots.call("spawn", 0, Vector2(60.0 + e * 52.0, 188.0), Vector2(0.01, 0.0), 60.0, 6.0) as int
		shots.call("set_core", slot, tints[e])
		shots.call("set_shape", slot, e + 1)
	var preset: Resource = feel.get("preset") as Resource
	preset.set("beam_seconds", 60.0)
	preset.set("nova_seconds", 60.0)
	for p in 4:
		events.call("emit_signal", "form_shown", p, &"beam", Vector2(290.0, 30.0 + p * 28.0), Vector2.RIGHT, 300.0, tints[p])
	for p in 4:
		events.call("emit_signal", "form_shown", p, &"nova", Vector2(350.0 + p * 76.0, 250.0), Vector2.RIGHT, 0.0, tints[3 - p])
	# Show the rings half grown.
	var left: PackedFloat32Array = feel.get("_form_left") as PackedFloat32Array
	for i in left.size():
		left[i] = left[i] * 0.8
	feel.set("_form_left", left)
	for i in SETTLE_FRAMES:
		await process_frame
	await RenderingServer.frame_post_draw
	if int(shots.get("drawn")) < 20:
		printerr("SHOT FAILED: the shots were not drawn")
		quit(1)
		return
	var image: Image = root.get_texture().get_image()
	var path: String = "%s/element_shots.png" % SHOTS_DIR
	if image == null or image.save_png(path) != OK:
		printerr("SHOT FAILED: could not save " + path)
		quit(1)
		return
	print("SHOT: element_shots (%dx%d)" % [image.get_width(), image.get_height()])
	quit(0)
