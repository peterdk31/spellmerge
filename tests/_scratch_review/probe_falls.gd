extends "res://tests/support/suite.gd"
const ContentFight := preload("res://tests/core/content_fight.gd")
const RegistryScript := preload("res://core/registry/registry.gd")

func test_probe() -> void:
	var reg: RegistryScript = own(RegistryScript.new()) as RegistryScript
	reg.scan()
	var holes: Array[Rect2] = [Rect2(80.0, -120.0, 40.0, 320.0), Rect2(-24.0, 24.0, 16.0, 16.0)]
	var targets: Array = [[ContentFight.ENEMY, reg.get_resource(&"enemies", &"ember_imp")]]
	for card: Resource in reg.get_all(&"spells"):
		if card.id in [&"dash", &"teleport", &"pull"]:
			targets.append([ContentFight.CARD, card])
	for t in targets:
		var fell: Array = [0, 0, 0]
		var fight := ContentFight.new(root, t[0], t[1], 2, holes)
		fight.fight.bus.body_fell.connect(func(_a: Node) -> void: fell[0] += 1)
		fight.fight.bus.body_returned.connect(func(_a: Node, _b: Vector2) -> void: fell[1] += 1)
		fight.fight.bus.enemy_died.connect(func(_k: int, _e: Node, _p: Vector2, _s: int) -> void: fell[2] += 1)
		for i in 300:
			fight.step()
		print("FALLS ", t[1].id, " fell=", fell[0], " returned=", fell[1], " died=", fell[2])
		fight.free_all()
	check(true, "ok")
