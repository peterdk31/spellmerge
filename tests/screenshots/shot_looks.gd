extends SceneTree
## A sheet of the look of shots (staffs B6a), for people and for Claude to look at (it only
## checks that the shots were drawn). The looks come from the real cards (`tint` and
## `look_layer`), packed as the compiler packs them. Needs a display, so it runs only through
## `ci/build/build.sh --quick --screenshots`; saved as user://screenshots/<name>.png and copied
## to build/screenshots/.
##
## `looks_sheet` (1x, as a player sees it):
##   top left    every carrier with every infusion: a row of bolts, a row of runes (plain,
##               fire, frost, storm, void, lightning) and a row of orbit shots (one per player,
##               fire, frost, storm, void)
##   top right   the modifier looks on a fire bolt (bigger, pierce, homing) and the kinds no
##               card has yet (motes, burst, orbiters, glitter); then combined: all five infusions on
##               one bolt, and every kind at once on a bolt, a bigger bolt and a rune
##   bottom      four players firing the same card (a fire bolt), to tell them apart at 1x;
##               the right half through a grey filter, to check the looks read without colour
## `looks_sheet_4x`: the top rows at 4x. `looks_combined_4x`: the combined shots at 4x.

const SHOTS_DIR := "user://screenshots"
const SETTLE_FRAMES := 12
const FLOOR := preload("res://art/tilesets/crypt/floor.svg")
const ManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const ELEMENTS: Array[Resource] = [
	preload("res://content/spells/elements/fire/fire.tres"),
	preload("res://content/spells/elements/frost/frost.tres"),
	preload("res://content/spells/elements/storm/storm.tres"),
	preload("res://content/spells/elements/void/void.tres"),
	preload("res://content/spells/elements/lightning/lightning.tres"),
]
const BIGGER := preload("res://content/spells/modifiers/bigger/bigger.tres")
const PIERCE := preload("res://content/spells/modifiers/pierce/pierce.tres")
const HOMING := preload("res://content/spells/modifiers/homing/homing.tres")
## A bolt's hit radius, and a bigger bolt's (bolt.tres, bigger.tres).
const BOLT_RADIUS: float = 5.0

var _shots: Node = null


func _initialize() -> void:
	await process_frame
	DirAccess.make_dir_recursive_absolute(SHOTS_DIR)
	_shots = root.get_node_or_null("Projectiles")
	if _shots == null:
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
	_shots.call("set_bounds", Rect2(0, 0, 640, 360))
	_shots.call("set_cap", 200)
	# Carriers by infusion: column 0 is plain.
	for e in 6:
		var x: float = 30.0 + e * 40.0
		var tint: Color = Color.WHITE if e == 0 else ELEMENTS[e - 1].get("tint") as Color
		var look: PackedInt32Array = PackedInt32Array() if e == 0 else PackedInt32Array([int(ELEMENTS[e - 1].get("look_layer"))])
		_bolt(0, Vector2(x, 30.0), BOLT_RADIUS, tint, look)
		var rune: int = _shots.call("spawn", 0, Vector2(x, 80.0), Vector2.ZERO, 600.0, 14.0, 1, 0, 0, ManagerScript.MOTION_STILL) as int
		_dress(rune, tint, look)
	for p in 4:
		var anchor := Vector2(40.0 + p * 60.0, 140.0)
		_shots.call("set_anchor", p, anchor)
		for n in 2:
			var orb: int = _shots.call("spawn_orbit", p, 16.0, n * PI, 0.0001, 600.0, 6.0) as int
			_dress(orb, ELEMENTS[p].get("tint") as Color, PackedInt32Array([int(ELEMENTS[p].get("look_layer"))]))
	# Modifier looks and the kinds no card uses yet, each on a fire bolt.
	var fire: Resource = ELEMENTS[0]
	var fire_tint: Color = fire.get("tint") as Color
	var fire_look: int = int(fire.get("look_layer"))
	var extra: Array[int] = [int(BIGGER.get("look_layer")), int(PIERCE.get("look_layer")), int(HOMING.get("look_layer")),
			ManagerScript.LOOK_MOTES, ManagerScript.LOOK_BURST, ManagerScript.LOOK_ORBITERS, ManagerScript.LOOK_GLITTER]
	for n in extra.size():
		var radius: float = BOLT_RADIUS * (float(BIGGER.get("radius_mult")) if n == 0 else 1.0)
		_bolt(0, Vector2(330.0 + (n % 4) * 70.0, 30.0 + (n / 4) * 50.0), radius, fire_tint, PackedInt32Array([fire_look, extra[n]]))
	# Combined: all five infusions on one bolt, then every kind at once.
	var infusions := PackedInt32Array()
	for element: Resource in ELEMENTS:
		infusions.append(int(element.get("look_layer")))
	_bolt(1, Vector2(330.0, 140.0), BOLT_RADIUS, ELEMENTS[1].get("tint") as Color, infusions)
	var everything := PackedInt32Array()
	for kind in range(1, ManagerScript.LOOK_COUNT):
		everything.append(kind)
	_bolt(2, Vector2(400.0, 140.0), BOLT_RADIUS, ELEMENTS[3].get("tint") as Color, everything)
	_bolt(3, Vector2(470.0, 140.0), BOLT_RADIUS * float(BIGGER.get("radius_mult")), ELEMENTS[0].get("tint") as Color, everything)
	var rune: int = _shots.call("spawn", 0, Vector2(565.0, 140.0), Vector2.ZERO, 600.0, 14.0, 1, 0, 0, ManagerScript.MOTION_STILL) as int
	_dress(rune, ELEMENTS[4].get("tint") as Color, everything)
	# Four players, the same fire bolt, twice: in colour on the left, grey on the right.
	for half in 2:
		for p in 4:
			_bolt(p, Vector2(40.0 + half * 320.0 + p * 60.0, 230.0), BOLT_RADIUS, fire_tint, PackedInt32Array([fire_look]))
			_bolt(p, Vector2(40.0 + half * 320.0 + p * 60.0, 290.0), BOLT_RADIUS, ELEMENTS[4].get("tint") as Color, PackedInt32Array([int(ELEMENTS[4].get("look_layer"))]))
	var grey := ColorRect.new()
	grey.position = Vector2(320.0, 200.0)
	grey.size = Vector2(320.0, 160.0)
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
	if int(_shots.get("drawn")) < 40:
		printerr("SHOT FAILED: only %d shots were drawn" % int(_shots.get("drawn")))
		quit(1)
		return
	var image: Image = root.get_texture().get_image()
	_save(image, "looks_sheet")
	var scale_to_image: Vector2 = Vector2(image.get_size()) / Vector2(root.get_visible_rect().size)
	var crop: Image = image.get_region(Rect2i(Vector2i(Vector2(0.0, 0.0) * scale_to_image), Vector2i(Vector2(320.0, 170.0) * scale_to_image)))
	crop.resize(crop.get_width() * 4, crop.get_height() * 4, Image.INTERPOLATE_NEAREST)
	_save(crop, "looks_sheet_4x")
	var combined: Image = image.get_region(Rect2i(Vector2i(Vector2(310.0, 100.0) * scale_to_image), Vector2i(Vector2(300.0, 80.0) * scale_to_image)))
	combined.resize(combined.get_width() * 4, combined.get_height() * 4, Image.INTERPOLATE_NEAREST)
	_save(combined, "looks_combined_4x")
	quit(0)


## A bolt of `player` that barely moves (the sheet is a still), with a core and layers.
func _bolt(player: int, at: Vector2, radius: float, tint: Color, look: PackedInt32Array) -> void:
	var slot: int = _shots.call("spawn", player, at, Vector2(0.01, 0.0), 600.0, radius) as int
	_dress(slot, tint, look)


func _dress(slot: int, tint: Color, look: PackedInt32Array) -> void:
	_shots.call("set_core", slot, tint)
	_shots.call("set_look", slot, ManagerScript.pack_look(look))


func _save(image: Image, shot_name: String) -> void:
	var path: String = "%s/%s.png" % [SHOTS_DIR, shot_name]
	if image == null or image.save_png(path) != OK:
		printerr("SHOT FAILED: could not save " + path)
		return
	print("SHOT: %s (%dx%d)" % [shot_name, image.get_width(), image.get_height()])
