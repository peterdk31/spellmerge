extends "res://tests/support/suite.gd"
## Staff animations (`FormBase.staff_pose`, played by `Spells.poses().staff_pose` and the rest): keys in
## the carrier's own time (wind-up, strike, a hold that repeats while the strike lasts, after),
## every channel, the strike ending with the carrier's last shot, a new cast starting from where
## the staff is, and the aim it turns from. Every real carrier has one. Cards are made in code and
## played in the combo arena with the real runtime.
##
## godot --headless --path . --script res://tests/core/test_staff_poses.gd

const ArenaScript := preload("res://tests/content/spells/combo_arena.gd")

var arena: ArenaScript


func before_each() -> void:
	arena = ArenaScript.new(root)
	arena.spells.set_aim(0, Vector2.ZERO, Vector2.RIGHT)


func after_each() -> void:
	arena.free_all()


## A form card of the carrier `carrier` with `keys` as its staff animation, in the registry as `id`.
func _card(id: StringName, carrier: StringName, keys: Array[Dictionary], lifetime: float = 0.3) -> FormBase:
	var form := FormBase.new()
	form.id = id
	form.display_name = String(id)
	form.complexity = 1
	form.carrier = carrier
	form.base_damage = 1
	form.speed = 100.0
	form.ray_length = 100.0
	form.lifetime = lifetime
	form.cooldown = 0.05
	form.staff_pose = keys
	(arena.registry.get("_resources")[&"spells"] as Dictionary)[id] = form
	return form


func _cast(id: StringName) -> void:
	arena.install_cards(0, 0, [id])
	check(arena.cast(0, 0), "%s is cast" % id)
	# The cast's carrier is launched on the next step.
	arena.run(1.0 / 60.0)


func test_every_channel_follows_its_keys_and_it_ends_on_the_aim() -> void:
	_card(&"posed", &"bolt", [{"phase": "after", "at": 0.1, "turn": -40, "lift": 4, "push": -3, "glow": 0.5, "stretch": 0.3, "shake": 1.0, "ease": "out", "mood": "raised"}, {"phase": "after", "at": 0.3}] as Array[Dictionary])
	_cast(&"posed")
	arena.run(0.1)
	var pose: Vector3 = arena.spells.poses().staff_pose(0)
	check(absf(rad_to_deg(pose.x) + 40.0) < 4.0 and absf(pose.y - 4.0) < 0.5 and absf(pose.z + 3.0) < 0.5, "at its first key: %s" % pose)
	check(absf(arena.spells.poses().staff_glow(0) - 0.5) < 0.05, "glowing")
	check(absf(arena.spells.poses().staff_stretch(0) - 0.3) < 0.03, "stretched")
	check(absf(arena.spells.poses().staff_shake(0) - 1.0) < 0.1, "shaking")
	check_equal(arena.spells.poses().staff_mood(0), &"raised", "with its mood")
	arena.run(0.3)
	check_equal(arena.spells.poses().staff_pose_dir(0), Vector2.ZERO, "then over")
	check_equal(arena.spells.poses().staff_glow(0), 0.0, "and dark")


func test_a_hold_repeats_while_a_held_beam_lasts_and_ends_with_it() -> void:
	_card(&"held", &"beam", [{"phase": "hold", "at": 0.1, "glow": 1.0}, {"phase": "hold", "at": 0.2, "glow": 0.0}, {"phase": "after", "at": 0.1}] as Array[Dictionary], 1.0)
	_cast(&"held")
	var glows: Array[float] = []
	for n in 50:
		arena.run(1.0 / 60.0)
		glows.append(arena.spells.poses().staff_glow(0))
	var peaks: int = 0
	for n in range(1, glows.size() - 1):
		if glows[n] > 0.9 and glows[n] >= glows[n - 1] and glows[n] >= glows[n + 1]:
			peaks += 1
	check(peaks >= 3, "it pulses round and round through the beam's life: %d peaks" % peaks)
	arena.run(1.0)
	check_equal(arena.spells.poses().staff_pose_dir(0), Vector2.ZERO, "and is over after the beam")


func test_a_new_cast_starts_from_where_the_staff_is() -> void:
	_card(&"up", &"bolt", [{"phase": "after", "at": 0.1, "lift": 10}, {"phase": "after", "at": 0.5, "lift": 10}, {"phase": "after", "at": 0.6}] as Array[Dictionary])
	_card(&"down", &"bolt", [{"phase": "after", "at": 0.2, "lift": -4}, {"phase": "after", "at": 0.4}] as Array[Dictionary])
	_cast(&"up")
	arena.run(0.2)
	check(absf(arena.spells.poses().staff_pose(0).y - 10.0) < 0.5, "up")
	arena.install_cards(0, 1, [&"down"])
	arena.cast(0, 1)
	arena.run(1.0 / 60.0)
	check(arena.spells.poses().staff_pose(0).y > 8.0, "the next cast starts from up there, no jump: %s" % arena.spells.poses().staff_pose(0))


func test_it_turns_with_the_live_aim_unless_its_carrier_locks_the_aim() -> void:
	_card(&"loose", &"bolt", [{"phase": "after", "at": 0.4, "lift": 2}, {"phase": "after", "at": 0.5}] as Array[Dictionary])
	_cast(&"loose")
	arena.spells.set_aim(0, Vector2.ZERO, Vector2.DOWN)
	arena.run(0.1)
	check_equal(arena.spells.poses().staff_pose_dir(0), Vector2.DOWN, "a bolt's staff follows the aim")
	arena.install_cards(0, 1, [&"swing"])
	arena.spells.set_aim(0, Vector2.ZERO, Vector2.RIGHT)
	arena.cast(0, 1)
	arena.run(1.0 / 60.0)
	arena.spells.set_aim(0, Vector2.ZERO, Vector2.DOWN)
	arena.run(0.05)
	check(arena.spells.poses().staff_pose_dir(0).is_equal_approx(Vector2.RIGHT), "a swing's keeps the aim of its cast")


func test_every_carrier_moves_the_staff() -> void:
	for id: StringName in arena.registry.call("get_ids", &"spells"):
		var card: Resource = arena.registry.call("get_resource", &"spells", id)
		if card is FormBase:
			check(not (card as FormBase).staff_pose.is_empty(), "%s has a staff animation" % id)
