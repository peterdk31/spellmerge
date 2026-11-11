extends "res://tests/support/screenshot.gd"
## Damage numbers on every actor (props W5, docs/milestones/props.md): in the arena, a wizard, an
## enemy, a prop (the benchmark's stand-in) and a boss-sized enemy wearing its own bigger numbers,
## each hit a few times (plain, fire, frost), the wizard healed and the prop invincible (its hit
## struck through). `damage_numbers` shows them all a few frames after the hits, `damage_numbers_4x`
## the enemy and the prop close up.

const ENEMY: EnemyBase = preload("res://content/enemies/bone_husk/bone_husk.tres")
const PROP_SCENE: PackedScene = preload("res://tests/benchmark/prop_stand_in.tscn")


func take() -> void:
	change_scene_to_file("res://hud/menus/main_menu/main_menu.tscn")
	await settle()
	if not need(["PlayerInput", "Flow", "Feel", "Combat"]):
		return
	# Feel ages the numbers by the wall clock; a software-rendered frame is far longer than 1/60 s.
	root.get_node("Feel").set("drive_engine", false)
	var input: Node = root.get_node("PlayerInput")
	var flow: Node = root.get_node("Flow")
	var combat: Node = root.get_node("Combat")
	input.call("add_virtual_device", 0)
	flow.call("start_run", 0)
	for i in 4:
		await settle()
	var wizard: Actor = flow.call("get_wizard", 0) as Actor
	if wizard == null:
		fail("no wizard in the arena")
		return
	# The camera follows the wizard and the wave's banner is below the screen's middle: the rest
	# stands above the wizard.
	var centre: Vector2 = Vector2(320.0, 160.0)
	wizard.global_position = centre + Vector2(-90.0, 50.0)
	var enemy: Actor = _stand(ENEMY.scene.instantiate() as Actor, wizard, centre + Vector2(-30.0, 0.0))
	var prop: Actor = _stand(PROP_SCENE.instantiate() as Actor, wizard, centre + Vector2(30.0, 0.0))
	var boss_body: Actor = ENEMY.scene.instantiate() as Actor
	var boss_numbers := DamageNumbers.new()
	boss_numbers.text_size = 2.0
	boss_numbers.rise = 24.0
	boss_body.add_child(boss_numbers)
	var boss: Actor = _stand(boss_body, wizard, centre + Vector2(100.0, 10.0))
	boss.set_size(2.0)
	await settle()
	combat.call("hit", -1, wizard, 3.0)
	wizard.healed.emit(-1, 2.0)
	combat.call("hit", -1, enemy, 5.0)
	enemy.damaged.emit(-1, 12.5, &"fire")
	prop.health.invincible = true
	combat.call("hit", -1, prop, 8.0)
	combat.call("hit", -1, boss, 24.0)
	boss.damaged.emit(-1, 40.0, &"frost")
	for i in 8:
		await physics_frame
		await process_frame
	await snap(centre + Vector2(0.0, -10.0), "damage_numbers", Vector2i(160, 90), 2)
	await snap(centre + Vector2(0.0, -24.0), "damage_numbers_4x", Vector2i(48, 32), 4)
	flow.call("stop_run")
	await create_timer(0.3).timeout


## `body` (with its data when it is an enemy) beside the wizard in the arena, at `at`, standing:
## nothing steps it, so it stays where it is put.
func _stand(body: Actor, wizard: Actor, at: Vector2) -> Actor:
	if body.scene_file_path == ENEMY.scene.resource_path:
		body.data = ENEMY
	wizard.get_parent().add_child(body)
	body.ticking = false
	body.global_position = at
	return body
