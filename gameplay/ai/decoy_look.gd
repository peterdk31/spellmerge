class_name DecoyLook
extends ActorLook
## A decoy's look (`Entities`): a copy of its caster's body, the `Sprite` and its `Hat` copied when
## it is placed (`copy_look`), drawn by the shots' sprite shader part fallen apart in its caster's
## colour with a glow (`tint`), so it never reads as a second wizard; never see-through (the glow
## look, 2026-10-27). A copy of a living staff (a head sheet of `StaffLook.DIRECTIONS` columns)
## turns to the way the decoy aims, as the staff it copies does.

## How far the copy has fallen apart (`shot_sprite.gdshader`'s dissolve) and how bright its glow is.
const DISSOLVE: float = 0.3
const GLOW: float = 0.6

var sprite: Sprite2D = null
var hat: Sprite2D = null


func _init() -> void:
	sprite = Sprite2D.new()
	sprite.name = "Sprite"
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.material = _material()
	add_child(sprite)
	hat = Sprite2D.new()
	hat.name = "Hat"
	hat.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	hat.material = _material()
	sprite.add_child(hat)


func step(_delta: float) -> void:
	if sprite.texture != null and sprite.hframes == StaffLook.DIRECTIONS:
		var column: int = StaffLook.direction_of(actor.aim)
		if sprite.frame_coords.x != column:
			sprite.frame_coords = Vector2i(column, sprite.frame_coords.y)


func _material() -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = SPRITE_SHADER
	material.set_shader_parameter(&"core_override", Color.WHITE)
	material.set_shader_parameter(&"dissolve", DISSOLVE)
	material.set_shader_parameter(&"sprite_glow", GLOW)
	return material


## Turn the copy to `colour` (its caster's).
func tint(colour: Color) -> void:
	(sprite.material as ShaderMaterial).set_shader_parameter(&"dissolve_color", colour)
	(hat.material as ShaderMaterial).set_shader_parameter(&"dissolve_color", colour)


## Look like `body` does now (its `Sprite`, and a `Sprite/Hat` if it has one); plain when it has
## none.
func copy_look(body: Node2D) -> void:
	var from: Sprite2D = body.get_node_or_null("Sprite") as Sprite2D if body != null else null
	_copy(sprite, from)
	_copy(hat, from.get_node_or_null("Hat") as Sprite2D if from != null else null)


func _copy(to: Sprite2D, from: Sprite2D) -> void:
	to.texture = from.texture if from != null else null
	if from == null:
		return
	to.hframes = from.hframes
	to.vframes = from.vframes
	to.frame = from.frame
	to.flip_h = from.flip_h
	to.position = from.position
	to.offset = from.offset
	to.centered = from.centered
