class_name LightSpot
extends RefCounted
## A light that is part of a room's art (docs/milestones/spell-spectacle.md, P3b): a torch, a
## brazier, a glowing rune on the floor. Room and decal scenes carry no scripts, so a light spot
## is data on a plain node: any Node2D (a `Marker2D` where the light comes from) in the group
## `light_spot` (GROUP), with its numbers as metadata, all optional:
##
##     [node name="Light" type="Marker2D" parent="." groups=["light_spot"]]
##     position = Vector2(16, 10)
##     metadata/light_art = NodePath("../Flame")
##     metadata/light_reach = 56.0
##
## While the "Spell light" setting is on, Feel's spell light draws every such node in the tree into
## its light buffer like a shot's light (gameplay/feel/spell_light.gd), so it lights the floor,
## the walls and the bodies round it in the same steps. Nothing reads it for the game.
##
## Its colour comes from its art, not from a number: the lightest of the most common colours of
## the sprite `light_art` names (`ArtPixels.colours_of`; the first frame of an animated one),
## so a torch with a blue flame lights blue with no edit. `light_tint` overrides it when the art's
## colour reads wrong. A spot does not move once in the tree (room art).
##
## The light painted into the art (a torch's additive glow sprites) is in the group `painted_light`
## (PAINTED): Feel's spell light hides it while it draws the spots' own light, so a torch is not lit
## twice, and shows it again when the setting is off (docs/milestones/spell-spectacle-2.md, S6
## item 12):
##
##     [node name="Glow" type="Sprite2D" parent="." groups=["painted_light"]]

## The group a light spot is in.
const GROUP: StringName = &"light_spot"
## The group of the light painted into a room's art, which the spots' light takes the place of.
const PAINTED: StringName = &"painted_light"
## The metadata keys and what each is when it is missing.
const REACH: StringName = &"light_reach"
const STRENGTH: StringName = &"light_strength"
const FLICKER: StringName = &"light_flicker"
const ART: StringName = &"light_art"
const TINT: StringName = &"light_tint"
## How far its light reaches, in pixels (to where it is gone).
const DEFAULT_REACH: float = 56.0
## How bright it is at its middle (a shot's light is 0.9, `light.gdshader`'s `shot_strength`).
const DEFAULT_STRENGTH: float = 0.7
## How much it flickers: its strength drops by up to this share, a step a few times a second.
const DEFAULT_FLICKER: float = 0.25


static func reach_of(spot: Node) -> float:
	return float(spot.get_meta(REACH, DEFAULT_REACH))


static func strength_of(spot: Node) -> float:
	return float(spot.get_meta(STRENGTH, DEFAULT_STRENGTH))


static func flicker_of(spot: Node) -> float:
	return float(spot.get_meta(FLICKER, DEFAULT_FLICKER))


## The colour of its light: `light_tint` when set, else its art's lightest common colour, white
## when it has no art to read.
static func colour_of(spot: Node) -> Color:
	if spot.has_meta(TINT):
		var tint: Color = spot.get_meta(TINT)
		return Color(tint.r, tint.g, tint.b, 1.0)
	var colours: PackedColorArray = ArtPixels.colours_of(art_of(spot))
	return colours[0] if not colours.is_empty() else Color.WHITE


## The texture its colour is read from (null for none): the `light_art` sprite's, the first frame
## of an animated one.
static func art_of(spot: Node) -> Texture2D:
	var path: NodePath = spot.get_meta(ART, NodePath())
	var node: Node = spot.get_node_or_null(path) if not path.is_empty() else null
	if node is Sprite2D:
		return (node as Sprite2D).texture
	if node is AnimatedSprite2D:
		var sprite := node as AnimatedSprite2D
		var frames: SpriteFrames = sprite.sprite_frames
		if frames != null and frames.has_animation(sprite.animation) and frames.get_frame_count(sprite.animation) > 0:
			return frames.get_frame_texture(sprite.animation, 0)
	return null


## What is wrong with the spot (empty when nothing is): for the content tests.
static func problems(spot: Node) -> PackedStringArray:
	var found := PackedStringArray()
	if not spot is Node2D:
		found.append("a light spot must be a Node2D (it is where the light comes from)")
	for key: StringName in [REACH, STRENGTH, FLICKER]:
		if spot.has_meta(key) and not (typeof(spot.get_meta(key)) in [TYPE_FLOAT, TYPE_INT]):
			found.append("%s must be a number" % key)
	if reach_of(spot) <= 0.0:
		found.append("light_reach must be above 0")
	if strength_of(spot) < 0.0 or strength_of(spot) > 1.0:
		found.append("light_strength must be 0 to 1")
	if flicker_of(spot) < 0.0 or flicker_of(spot) > 1.0:
		found.append("light_flicker must be 0 to 1")
	if spot.has_meta(TINT) and typeof(spot.get_meta(TINT)) != TYPE_COLOR:
		found.append("light_tint must be a colour")
	if not spot.has_meta(TINT) and art_of(spot) == null:
		found.append("needs light_art (a sprite to take its colour from) or light_tint")
	return found
