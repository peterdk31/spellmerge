extends SceneTree
## The part-26 art pass sheet on the crypt floor: all 18 component icons (2x, and 1x as the
## builder shows them), the four element tints against the four player colours, and every
## vfx sprite at 1x. Icon order: bolt beam nova rune orbit | fire frost storm void | split
## pierce homing chain bigger faster | on_hit on_expire timer. The player groups are "as
## shipped": the manager mixes the owner colour with white. The element groups are
## hypothetical: the manager does not tint by element, so they show what the same mix
## would look like. Colours are read from the manager and the element resources.
## Looked at against docs/STYLE.md. Needs a display, so it runs only through
## `ci/build/build.sh --quick --screenshots`; the shot is saved as
## user://screenshots/art_pass_sheet.png and copied to build/screenshots/.

const SHOTS_DIR := "user://screenshots"
const SETTLE_FRAMES := 10
const MANAGER := preload("res://core/projectiles/projectile_manager.gd")

const FLOOR := preload("res://art/tilesets/crypt/floor.svg")
const ICONS: Array[Texture2D] = [
	preload("res://content/spells/forms/bolt/icon.svg"),
	preload("res://content/spells/forms/beam/icon.svg"),
	preload("res://content/spells/forms/nova/icon.svg"),
	preload("res://content/spells/forms/rune/icon.svg"),
	preload("res://content/spells/forms/orbit/icon.svg"),
	preload("res://content/spells/elements/fire/icon.svg"),
	preload("res://content/spells/elements/frost/icon.svg"),
	preload("res://content/spells/elements/storm/icon.svg"),
	preload("res://content/spells/elements/void/icon.svg"),
	preload("res://content/spells/modifiers/split/icon.svg"),
	preload("res://content/spells/modifiers/pierce/icon.svg"),
	preload("res://content/spells/modifiers/homing/icon.svg"),
	preload("res://content/spells/modifiers/chain/icon.svg"),
	preload("res://content/spells/modifiers/bigger/icon.svg"),
	preload("res://content/spells/modifiers/faster/icon.svg"),
	preload("res://content/spells/triggers/on_hit/icon.svg"),
	preload("res://content/spells/triggers/on_expire/icon.svg"),
	preload("res://content/spells/triggers/timer/icon.svg"),
]
const ELEMENTS: Array[Resource] = [
	preload("res://content/spells/elements/fire/fire.tres"),
	preload("res://content/spells/elements/frost/frost.tres"),
	preload("res://content/spells/elements/storm/storm.tres"),
	preload("res://content/spells/elements/void/void.tres"),
]
const BOLT := preload("res://art/vfx/bolt.svg")
const VFX: Array[Texture2D] = [
	preload("res://art/vfx/bolt.svg"),
	preload("res://art/vfx/imp_fireball.svg"),
	preload("res://art/vfx/hit_spark.svg"),
	preload("res://art/vfx/telegraph_dash.svg"),
	preload("res://art/vfx/beam.svg"),
	preload("res://art/vfx/nova_ring.svg"),
	preload("res://art/vfx/rune.svg"),
	preload("res://art/vfx/orbit_orb.svg"),
]


func _initialize() -> void:
	await process_frame
	DirAccess.make_dir_recursive_absolute(SHOTS_DIR)
	var floor_sprite := Sprite2D.new()
	floor_sprite.texture = FLOOR
	floor_sprite.centered = false
	floor_sprite.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	floor_sprite.region_enabled = true
	floor_sprite.region_rect = Rect2(0, 0, 640, 360)
	root.add_child(floor_sprite)
	# Row 1: the 18 icons at 2x; row 2: the same at 1x.
	for i in ICONS.size():
		_place(ICONS[i], 2.0, 8.0 + i * 35.0, 8.0, Color.WHITE)
		_place(ICONS[i], 1.0, 16.0 + i * 35.0, 46.0, Color.WHITE)
	# Rows 3-4: per colour, a swatch, the bolt mixed with white as the manager mixes an owner
	# colour, and the bolt in the full colour. Left: elements (hypothetical); right: players.
	_label("elements (hypothetical): fire frost storm void", 8.0, 336.0)
	_label("players (as shipped): 1 2 3 4", 330.0, 336.0)
	for e in ELEMENTS.size():
		_tint_group(8.0 + e * 76.0, ELEMENTS[e].get("tint"))
	for p in MANAGER.PLAYER_COLORS.size():
		_tint_group(330.0 + p * 76.0, MANAGER.PLAYER_COLORS[p])
	# Rows 5-6: every vfx sprite at 1x, then the first four at 2x.
	var vx: float = 8.0
	for tex: Texture2D in VFX:
		_place(tex, 1.0, vx, 140.0, Color.WHITE)
		vx += tex.get_width() + 8.0
	vx = 8.0
	for tex: Texture2D in VFX.slice(0, 4):
		_place(tex, 2.0, vx, 200.0, Color.WHITE)
		vx += tex.get_width() * 2.0 + 8.0
	await _settle()
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	var path: String = "%s/art_pass_sheet.png" % SHOTS_DIR
	if image == null or image.save_png(path) != OK:
		printerr("SHOT FAILED: could not save " + path)
		quit(1)
		return
	print("SHOT: art_pass_sheet (%dx%d)" % [image.get_width(), image.get_height()])
	quit(0)


func _tint_group(x: float, tint: Color) -> void:
	var swatch := ColorRect.new()
	swatch.position = Vector2(x, 70.0)
	swatch.size = Vector2(16.0, 16.0)
	swatch.color = tint
	root.add_child(swatch)
	_place(BOLT, 2.0, x + 20.0, 66.0, Color.WHITE.lerp(tint, MANAGER.TINT_STRENGTH))
	_place(BOLT, 2.0, x + 20.0, 94.0, tint)


func _label(text: String, x: float, y: float) -> void:
	var label := Label.new()
	label.text = text
	label.position = Vector2(x, y)
	label.add_theme_font_size_override("font_size", 8)
	root.add_child(label)


func _place(texture: Texture2D, scale: float, x: float, y: float, tint: Color) -> void:
	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.centered = false
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.scale = Vector2(scale, scale)
	sprite.position = Vector2(x, y)
	sprite.modulate = tint
	root.add_child(sprite)


func _settle() -> void:
	for i in SETTLE_FRAMES:
		await process_frame
