class_name PropBody
extends RefCounted
## A prop's body made from its data (props W6, docs/milestones/props.md, "What a prop is made of"):
## the data's `scene` (for every prop the one shared scene, content/props/base/prop.tscn: an actor of
## the world's team with no controller and no Mover, with Health, Hurtbox, Footprint, Caster and
## `Reactions`), filled in from its `PropBase` before it is added. A new prop is data and art, no
## scene of its own.
##
##     var barrel: Actor = PropBody.make(Registry.get_resource(&"props", &"barrel") as PropBase)
##     barrel.position = where
##     room.add_child(barrel)
##
## Only the components are written, never the actor's own code: the actor stays the kit's, and what a
## prop does is its `Reactions`'. A body made again from a snapshot is the scene with its saved state,
## so nothing here runs for it.


## A new body of `data` (not yet in the tree): its scene, with its health, hurt shape, ground,
## staffs and states; null when its scene is none or no actor (`PropBase.problems` names it).
static func make(data: PropBase) -> Actor:
	var body: Actor = data.scene.instantiate() as Actor if data.scene != null else null
	if body == null:
		push_warning("PropBody: %s has no actor scene." % data.id)
		return null
	body.name = String(data.id).to_pascal_case() if data.id != &"" else "Prop"
	fill(body, data)
	return body


## Write `data` into the components of `body` (the shared scene, or a body of the same parts),
## before it is added: a component it lacks is left out.
static func fill(body: Actor, data: PropBase) -> void:
	body.body_offset = data.offset
	body.hand_offset = data.offset
	var hurt_box: Vector2 = Vector2.ZERO
	for child in body.get_children():
		if child is Health:
			var health := child as Health
			health.max_health = data.max_health
			health.invincible = data.invincible
		elif child is Hurtbox:
			var hurtbox := child as Hurtbox
			hurtbox.radius = data.radius
			hurtbox.size = data.size
			hurtbox.offset = data.offset
			hurt_box = data.size if hurtbox.is_box() else Vector2.ZERO
		elif child is Reactions:
			(child as Reactions).prop = data
	for child in body.get_children():
		if child is Footprint:
			_fill_ground(child as Footprint, data, hurt_box)
		elif child is Caster:
			_fill_staffs(child as Caster, data)


## Its ground: the data's own, else the base of its hurt box, else the scene's.
static func _fill_ground(footprint: Footprint, data: PropBase, hurt_box: Vector2) -> void:
	if data.has_footprint():
		footprint.radius = data.footprint_radius
		footprint.size = data.footprint_size
		footprint.offset = data.footprint_offset
	elif hurt_box != Vector2.ZERO:
		footprint.fit_base(hurt_box, data.offset)


## Its staffs (a prop with none keeps the scene's Caster empty: a snapshot makes the body again from
## the scene, Caster and all).
static func _fill_staffs(caster: Caster, data: PropBase) -> void:
	if not data.staffs.is_empty():
		caster.hold_staffs(data.staffs)
