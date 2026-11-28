extends "res://tests/support/suite.gd"
## The frame's looks pass (perf plan F4, `Actor.step_all_looks`) draws every body as before, frame
## for frame: two identical fights (staffed strays, the Old Broom's layered body, wizards; casting,
## walking, winding up, hurt), one drawn as the Tick drew it before (each body asks the screen and
## each look reads its staff animation alone), one by the pass, every drawn node of every body
## compared after every frame: its place, turn, size, offset, frame, texture, colour, material and
## glow. The "before" side is each body's `step_looks_due` with each look reading its animation
## alone (`StaffPoses.look_row` outside a pass: `may_play` and `read_look`, which
## tests/core/test_staff_poses.gd checks against the getters). The looks are view only, and Smooth (docs/STYLE.md) holds through them, so none may differ.
const Fixture := preload("res://tests/gameplay/ai/ai_fixture.gd")
const BROOM: EnemyBase = preload("res://content/bosses/old_broom/old_broom.tres")
const STRAYS: Array[EnemyBase] = [
	preload("res://content/enemies/ember_imp/ember_imp.tres"),
	preload("res://content/enemies/splinter/splinter.tres"),
	preload("res://content/enemies/rime_crook/rime_crook.tres"),
	preload("res://content/enemies/bone_scepter/bone_scepter.tres"),
	preload("res://content/enemies/storm_fork/storm_fork.tres"),
]
const DT: float = 1.0 / 60.0
const FRAMES: int = 150

var _worlds: Array[Fixture] = []


func after_each() -> void:
	for world in _worlds:
		world.free_all()
	_worlds.clear()


## A fight: four wizards in the middle, ten strays round them and the Old Broom, all in reach.
func _fight() -> Fixture:
	var world := Fixture.new(root, 4)
	_worlds.append(world)
	for index in 4:
		var wizard: Actor = world.players[index]
		wizard.position = Vector2(200.0 + 40.0 * index, 200.0)
		wizard.health.protect(1.0e9)
		wizard.ticking = false
	var kinds: Array[EnemyBase] = STRAYS.duplicate()
	kinds.append(BROOM)
	for index in 11:
		var data: EnemyBase = kinds[index % kinds.size()] if index < 10 else BROOM
		var body: Actor = data.scene.instantiate() as Actor
		body.data = data
		body.position = Vector2(260.0, 200.0) + Vector2.from_angle(TAU * float(index) / 11.0) * (90.0 + 15.0 * float(index % 3))
		world.wire(body)
		var mind: Node = Fixture.ai(body)
		if mind != null:
			mind.set("profile", null)
		root.add_child(body)
		body.ticking = false
		body.health.protect(1.0e9)
		world.enemies.append(body)
	return world


func _tick(world: Fixture, frame: int) -> void:
	for index in world.players.size():
		var wizard: Actor = world.players[index]
		var next: Vector2 = Vector2(260.0, 200.0) + Vector2.from_angle(float(frame) * 0.05 + TAU * float(index) / 4.0) * 40.0
		wizard.velocity = (next - wizard.position) / DT
		wizard.position = next
		wizard.aim = Vector2.from_angle(float(frame) * 0.11 + float(index))
		wizard.tick_step(DT, true)
	for body in world.enemies:
		if is_instance_valid(body) and body.is_inside_tree():
			body.tick_step(DT, true)
	world.combat.step(DT)
	world.projectiles.step(DT)
	world.spells.call("step", DT)
	world.board.step(DT)


## How every body is drawn now: each canvas node under it, in order.
func _drawn(world: Fixture) -> Array:
	var out: Array = []
	for body in world.players + world.enemies:
		_drawn_under(body, out)
	return out


func _drawn_under(node: Node, out: Array) -> void:
	for child in node.get_children():
		if child is Node2D:
			var item: Node2D = child as Node2D
			# A node made in code is named by the engine (its number differs between the two fights).
			var row: Array = [String(item.name) if not String(item.name).begins_with("@") else item.get_class(), item.position, item.rotation, item.scale, item.visible, item.modulate, item.self_modulate]
			if item is Sprite2D:
				var sprite: Sprite2D = item as Sprite2D
				row.append_array([sprite.offset, sprite.frame, sprite.hframes, sprite.vframes, _texture(sprite.texture), sprite.flip_h])
			var material: ShaderMaterial = item.material as ShaderMaterial
			if material != null:
				row.append_array([material.get_shader_parameter(&"glow_color"), material.get_shader_parameter(&"sprite_glow")])
			else:
				row.append(item.material == null)
			out.append(row)
		_drawn_under(child, out)


## A texture as what it draws: its file, else the page and region it is cut from, else its size.
func _texture(texture: Texture2D) -> Variant:
	if texture == null:
		return null
	if texture.resource_path != "":
		return texture.resource_path
	var atlas: AtlasTexture = texture as AtlasTexture
	if atlas != null:
		return [_texture(atlas.atlas), atlas.region]
	return [texture.get_class(), texture.get_size()]


func test_the_pass_draws_every_body_as_each_asking_did() -> void:
	var before: Fixture = _fight()
	var after: Fixture = _fight()
	var view: Viewport = root.get_viewport()
	var ids := PackedInt32Array()
	var posing: int = 0
	for frame in FRAMES:
		_tick(before, frame)
		_tick(after, frame)
		# Before: each body asked the screen and each look read its staff animation alone.
		var screen: Rect2 = view.get_visible_rect().grow(Actor.ON_SCREEN_MARGIN)
		for body in before.players + before.enemies:
			if is_instance_valid(body) and body.is_inside_tree():
				body.step_looks_due(view, screen)
		var n: int = after.actors.open_ids(ids)
		Actor.step_all_looks(after.actors, ids, n, view)
		var was: Array = _drawn(before)
		var now: Array = _drawn(after)
		check_equal(now.size(), was.size(), "frame %d: as many drawn nodes" % frame)
		for i in mini(was.size(), now.size()):
			if now[i] != was[i]:
				check_equal(now[i], was[i], "frame %d: drawn node %d as before" % [frame, i])
				break
		for body in after.players + after.enemies:
			if after.spells.poses().may_play(body.id):
				posing += 1
	check(posing > 100, "the bodies played staff animations (%d body frames)" % posing)
