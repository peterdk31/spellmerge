extends "res://tests/support/suite.gd"
## Death remnants (boss plan OB8, gameplay/feel/remnants.gd): a dead layered body's parts
## (`BodyPart`s under its `Sprite`) are copied as they were drawn and fly apart from its middle, up
## and down to the floor at its feet, each as far as its `fling`; they bounce, lie, fade and go; a
## new room clears them; the pool never grows. Through Feel's `enemy_died`, a layered body leaves
## a remnant and breaks each part into a share of its motes, a body of one sprite breaks as before.
## Bodies made here (decision 28).
##
## godot --headless --path . --script res://tests/gameplay/feel/test_remnants.gd

const EventsScript := preload("res://core/events/events.gd")
const FeelScript := preload("res://gameplay/feel/feel.gd")
const FeelPresetScript := preload("res://gameplay/feel/presets/feel_preset.gd")
const RegistryScript := preload("res://core/registry/registry.gd")
const ProjectilesScript := preload("res://core/projectiles/projectile_manager.gd")
const ActorSeats := preload("res://tests/support/actor_seats.gd")
const RemnantsScript := preload("res://gameplay/feel/remnants.gd")
const MotesScript := preload("res://gameplay/feel/mote.gd")

const STEP: float = 1.0 / 60.0


func _art(size: Vector2i) -> Texture2D:
	var image := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	image.fill(Color("b27a4a"))
	return ImageTexture.create_from_image(image)


## A body at `at` (its feet) whose `Sprite` holds a head with a handle on it (a layered body), or,
## not `layered`, shows one sprite of art.
func _body(at: Vector2, layered: bool = true) -> Node2D:
	var body := own(Node2D.new()) as Node2D
	body.position = at
	var sprite := Sprite2D.new()
	sprite.name = "Sprite"
	body.add_child(sprite)
	if layered:
		var head := BodyPart.new()
		head.name = "Head"
		head.texture = _art(Vector2i(24, 8))
		head.position = Vector2(0.0, -4.0)
		head.fling = 2.0
		sprite.add_child(head)
		var handle := BodyPart.new()
		handle.name = "Handle"
		handle.texture = _art(Vector2i(4, 16))
		handle.position = Vector2(0.0, -6.0)
		handle.offset = Vector2(0.0, -8.0)
		handle.rotation = 0.3
		handle.fling = 0.5
		head.add_child(handle)
	else:
		sprite.texture = _art(Vector2i(16, 16))
		sprite.position = Vector2(0.0, -8.0)
	root.add_child(body)
	return body


func _remnants() -> RemnantsScript:
	var remnants: RemnantsScript = own(RemnantsScript.new()) as RemnantsScript
	root.add_child(remnants)
	return remnants


func test_the_parts_fly_apart_land_lie_and_fade() -> void:
	var remnants := _remnants()
	var body := _body(Vector2(200.0, 100.0))
	var head := body.get_node("Sprite/Head") as BodyPart
	var handle := body.get_node("Sprite/Head/Handle") as BodyPart
	check(remnants.leave(body.get_node("Sprite") as Sprite2D, Vector2(200.0, 88.0), 100.0), "a layered body leaves a remnant")
	check_equal(remnants.count(), 2, "a piece a part")
	var head_piece: Sprite2D = remnants.piece(0)
	var handle_piece: Sprite2D = remnants.piece(1)
	check(head_piece.texture == head.texture and handle_piece.texture == handle.texture, "each its part's art")
	check(head_piece.global_position.is_equal_approx(head.global_position), "where it was drawn")
	check(is_equal_approx(handle_piece.rotation, handle.global_rotation) and handle_piece.offset == handle.offset, "turned as it was, its art placed alike")
	check(head_piece.z_index == RemnantsScript.FLY_Z and handle_piece.z_index == RemnantsScript.FLY_Z, "flying over the bodies")
	body.free()
	check(is_equal_approx(remnants.height_of(0), 4.0) and is_equal_approx(remnants.height_of(1), 10.0), "each starts at its height over the feet")
	var highest: float = 0.0
	var steps: int = 0
	while not (remnants.is_lying(0) and remnants.is_lying(1)) and steps < 600:
		remnants.step(STEP)
		highest = maxf(highest, remnants.height_of(0))
		steps += 1
	check(highest > 20.0, "the head flew up (%.1f px)" % highest)
	check(remnants.is_lying(0) and remnants.is_lying(1), "both landed")
	check(is_zero_approx(remnants.height_of(0)) and is_zero_approx(remnants.height_of(1)), "on the floor")
	check(head_piece.global_position.is_equal_approx(remnants.ground_of(0).round()), "drawn where it lies")
	var feet := Vector2(200.0, 100.0)
	check(remnants.ground_of(0).distance_to(feet) > remnants.ground_of(1).distance_to(feet), "the head (fling 2) farther than the handle (0.5)")
	check(remnants.ground_of(0).y > feet.y, "the head out from the middle, below it (%s)" % remnants.ground_of(0))
	check(remnants.ground_of(0).distance_to(feet) < 160.0, "not far off (%s)" % remnants.ground_of(0))
	check_equal(head_piece.z_index, RemnantsScript.LIE_Z, "lying on the floor, under the bodies")
	remnants.step(RemnantsScript.LIE + RemnantsScript.FADE * 0.5)
	check(head_piece.modulate.a < 1.0 and head_piece.visible, "fading")
	remnants.step(RemnantsScript.FADE)
	check_equal(remnants.count(), 0, "then gone")


func test_a_body_of_one_sprite_leaves_none_and_a_room_clears_them() -> void:
	var remnants := _remnants()
	var plain := _body(Vector2(100.0, 100.0), false)
	check(not remnants.leave(plain.get_node("Sprite") as Sprite2D, Vector2(100.0, 92.0), 100.0), "no parts: no remnant")
	check_equal(remnants.count(), 0, "nothing left")
	for i in RemnantsScript.MOST:
		var body := _body(Vector2(10.0 * i, 50.0))
		remnants.leave(body.get_node("Sprite") as Sprite2D, Vector2(10.0 * i, 40.0), 50.0)
		body.free()
	check_equal(remnants.count(), RemnantsScript.MOST, "the pool fills")
	check_equal(remnants.get_child_count(), RemnantsScript.MOST, "and never grows")
	# Full: the oldest pieces give way, fresh (flying, whole).
	for i in RemnantsScript.MOST:
		remnants.step(STEP * 10.0)
	var last := _body(Vector2(500.0, 50.0))
	remnants.leave(last.get_node("Sprite") as Sprite2D, Vector2(500.0, 40.0), 50.0)
	last.free()
	check_equal(remnants.count(), RemnantsScript.MOST, "still full, never more")
	var fresh: int = 0
	for i in remnants.count():
		var piece: Sprite2D = remnants.piece(i)
		if not remnants.is_lying(i) and piece.global_position.distance_to(Vector2(500.0, 46.0)) < 12.0:
			fresh += 1
			check(piece.modulate.a == 1.0 and piece.z_index == RemnantsScript.FLY_Z and piece.visible, "a fresh piece is whole and flying")
	check_equal(fresh, 2, "the new body's two pieces took the oldest places")
	remnants.clear()
	check_equal(remnants.count(), 0, "a new room clears them")


func test_the_pieces_are_drawn_in_the_parts_order() -> void:
	var remnants := _remnants()
	var body := _body(Vector2(200.0, 100.0))
	var handle := body.get_node("Sprite/Head/Handle") as BodyPart
	handle.show_behind_parent = true
	remnants.leave(body.get_node("Sprite") as Sprite2D, Vector2(200.0, 88.0), 100.0)
	var head_piece: Sprite2D = null
	var handle_piece: Sprite2D = null
	for i in remnants.count():
		if remnants.piece(i).texture == handle.texture:
			handle_piece = remnants.piece(i)
		else:
			head_piece = remnants.piece(i)
	check(handle_piece != null and head_piece != null, "both left")
	check(handle_piece.get_index() < head_piece.get_index(), "the part behind its parent is drawn under it")
	body.free()


func test_feel_leaves_a_layered_body_s_remnant_when_it_dies() -> void:
	var registry: RegistryScript = own(RegistryScript.new()) as RegistryScript
	registry.scan()
	var bus: EventsScript = own(EventsScript.new()) as EventsScript
	var feel: FeelScript = own(FeelScript.new()) as FeelScript
	var preset := FeelPresetScript.new()
	preset.hit_sound = &""
	feel.events = bus
	feel.registry = registry
	feel.actors = own(ActorSeats.table()) as ActorSeats.ActorsScript
	feel.projectiles = own(ProjectilesScript.new()) as ProjectilesScript
	feel.drive_engine = false
	feel.preset = preset
	root.add_child(feel)
	var motes: MotesScript = feel.motes()
	var body := _body(Vector2(150.0, 120.0))
	var before: int = motes.next_row()
	bus.enemy_died.emit(0, body, Vector2(150.0, 120.0), -1)
	check_equal(feel.remnants().count(), 2, "its parts fly apart")
	check(feel.spectacle().broken_from() == (body.get_node("Sprite/Head/Handle") as BodyPart).texture, "each part broke into motes, the last its handle")
	check(motes.next_row() > before, "motes shed")
	body.free()
	var plain := _body(Vector2(250.0, 120.0), false)
	bus.enemy_died.emit(0, plain, Vector2(250.0, 120.0), -1)
	check_equal(feel.remnants().count(), 2, "a body of one sprite leaves no remnant")
	check(feel.spectacle().broken_from() == (plain.get_node("Sprite") as Sprite2D).texture, "it breaks as before")
	plain.free()
	bus.room_entered.emit(&"arena_01")
	check_equal(feel.remnants().count(), 0, "a new room clears the remnant")
	# Killed mid-squash, its Sprite showing a strip of its own (a hurt pose): still layered, and its
	# pieces fly at its rest scale.
	var squashed := _body(Vector2(300.0, 120.0))
	(squashed.get_node("Sprite") as Sprite2D).texture = _art(Vector2i(8, 8))
	bus.damage_dealt.emit(0, squashed, 1, Vector2.ZERO)
	feel.step(STEP)
	check((squashed.get_node("Sprite") as Sprite2D).scale != Vector2.ONE, "squashed when it is killed")
	bus.enemy_died.emit(0, squashed, Vector2(300.0, 120.0), -1)
	check_equal(feel.remnants().count(), 2, "a layered body leaves its remnant whatever its Sprite shows")
	for i in feel.remnants().count():
		check(feel.remnants().piece(i).scale.is_equal_approx(Vector2.ONE), "piece %d at the rest scale (%s)" % [i, feel.remnants().piece(i).scale])
	squashed.free()
