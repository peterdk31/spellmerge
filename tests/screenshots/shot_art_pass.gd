extends SceneTree
## The part-26 art pass sheet on the crypt floor: all 18 component icons (2x, and 1x as the
## builder shows them), the four element tints against the four player colours with the
## bolt sprite drawn the way the projectile manager draws it, and every vfx sprite at 1x.
## Looked at against docs/STYLE.md. Needs a display, so it runs only through
## `ci/build/build.sh --quick --screenshots`; the shot is saved as
## user://screenshots/art_pass_sheet.png and copied to build/screenshots/.

const SHOTS_DIR := "user://screenshots"
const SETTLE_FRAMES := 10
## The projectile manager's mix of owner colour and white (TINT_STRENGTH).
const TINT_STRENGTH := 0.45

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
const ELEMENT_TINTS: Array[Color] = [
	Color(0.8784, 0.3490, 0.1843, 1), # fire
	Color(0.4980, 0.7529, 0.9412, 1), # frost
	Color(0.9490, 0.7608, 0.1882, 1), # storm
	Color(0.7882, 0.6039, 0.9412, 1), # void
]
const PLAYER_COLORS: Array[Color] = [
	Color("#3b73c9"), Color("#d9477a"), Color("#3f8f4f"), Color("#8a4fc4"),
]
const BOLT := preload("res://art/vfx/fire_bolt.svg")
const VFX: Array[Texture2D] = [
	preload("res://art/vfx/fire_bolt.svg"),
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
	# Rows 3-4: per element, its tint as a swatch, then the bolt mixed as the manager mixes
	# an owner colour and in the full colour; the four player colours the same way.
	for e in ELEMENT_TINTS.size():
		_tint_group(8.0 + e * 76.0, ELEMENT_TINTS[e])
	for p in PLAYER_COLORS.size():
		_tint_group(330.0 + p * 76.0, PLAYER_COLORS[p])
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
	_place(BOLT, 2.0, x + 20.0, 66.0, Color.WHITE.lerp(tint, TINT_STRENGTH))
	_place(BOLT, 2.0, x + 20.0, 94.0, tint)


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
