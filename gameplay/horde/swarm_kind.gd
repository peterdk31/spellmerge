class_name SwarmKind
extends Resource
## One kind of swarmer (docs/milestones/horde-swarm.md, part S1): an enemy the horde runs in the
## swarm (`swarm.gd`) instead of as a full actor. It names the enemy by its registry id only; every
## number is read from that enemy's `EnemyBase` and its actor scene by `prepare`, never copied by
## hand, so a change to the enemy changes its swarmer too:
##
## - from the `EnemyBase`: health, walking speed, touch damage, and the scene (the full actor a
##   swarmer is promoted to, part S3);
## - from the scene: the hurt circle (its `Hurtbox`'s radius and offset), the body's radius (its
##   collision circle, else its `Mover.body_radius`), the body offset the AI looks from
##   (`Actor.body_offset`), the body sprite (its `Sprite`'s texture and position) and the stray
##   face (its `Face`'s style, resting mood, anchor and glow), for the look (part S2).
##
## The kinds the director knows are the `.tres` files in `swarm_kinds/` (listed in `Swarm.KINDS`).

## The enemy's registry id (`content/enemies/<id>/`).
@export var enemy_id: StringName = &""

## The enemy this kind was prepared from (null until `prepare`).
var enemy: EnemyBase = null
## The full actor scene of the enemy (promotion, S3).
var scene: PackedScene = null
## From the `EnemyBase`.
var health: int = 1
var speed: float = 0.0
var contact_damage: int = 0
## The hurt circle: radius and centre from the feet (the scene's `Hurtbox`).
var hurt_radius: float = 8.0
var hurt_offset: Vector2 = Vector2(0.0, -12.0)
## The body's radius, for spacing and walls (the scene's collision circle).
var body_radius: float = 6.0
## Where the AI looks from (the scene's `Actor.body_offset`).
var body_offset: Vector2 = Vector2(0.0, -12.0)
## The body sprite (the scene's `Sprite`): its texture and its position from the feet.
var texture: Texture2D = null
var sprite_offset: Vector2 = Vector2.ZERO
## The face (the scene's `Face`): style, resting mood, anchor and glow, as `Face`'s enums.
var face_style: int = 0
var face_mood: int = 0
var face_anchor: Vector2 = Vector2.ZERO
var face_glow: Color = Color.WHITE
## True once a face was found in the scene.
var has_face: bool = false


## Reads every number from `data` and its scene (once per `data`; again for another one). Returns
## false when `data` has no scene that makes a Node2D.
func prepare(data: EnemyBase) -> bool:
	if data == null or data.scene == null:
		return false
	if enemy == data:
		return true
	var made: Node = data.scene.instantiate()
	var body := made as Node2D
	if body == null:
		if made != null:
			made.free()
		return false
	enemy = data
	scene = data.scene
	health = maxi(data.max_health, 1)
	speed = data.move_speed
	contact_damage = data.contact_damage
	var actor := body as Actor
	if actor != null:
		body_offset = actor.body_offset
	var found_radius: bool = false
	for child: Node in body.get_children():
		if child is Hurtbox:
			hurt_radius = (child as Hurtbox).radius
			hurt_offset = (child as Hurtbox).offset
		elif child is CollisionShape2D:
			var circle := (child as CollisionShape2D).shape as CircleShape2D
			if circle != null:
				body_radius = circle.radius
				found_radius = true
		elif child is Mover and not found_radius:
			body_radius = (child as Mover).body_radius
		elif child is Face:
			var face := child as Face
			face_style = face.style
			face_mood = face.resting_mood
			face_anchor = face.anchor
			face_glow = face.glow
			has_face = true
		elif child is Sprite2D and child.name == &"Sprite":
			texture = (child as Sprite2D).texture
			sprite_offset = (child as Sprite2D).position
	body.free()
	return true
