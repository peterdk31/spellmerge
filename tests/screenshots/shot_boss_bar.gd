extends "res://tests/support/screenshot.gd"
## The boss bar and the entrance banner (boss plan OB16, hud/panels/boss/): the first boss of the
## registry played in a room of its biome that hosts bosses (a pinned run of that room), with one
## protected wizard. `boss_entrance`: its banner (its name and lore line) over play as it enters,
## with the bar at the top; `boss_bar`: the bar once the banner is gone, its health below its first
## mark (the notch dim once passed). It passes with no boss in the registry (decision 28), and says
## so when no room hosts the boss.
##
## godot --path . --script res://tests/screenshots/shot_boss_bar.gd

const BossBannerScript := preload("res://hud/panels/boss/boss_banner.gd")

## Ticks to wait for the boss to show, and the share of its health a hit takes for the second shot.
const SHOW_TICKS: int = 60 * 5
const HURT_SHARE: float = 0.5

var _registry: Node = null
var _flow: Node = null


func _init() -> void:
	# The run is pinned here, in the boss's room.
	pin_room = false


func take() -> void:
	if not need(["Registry", "Flow", "PlayerInput", "Combat", "Hud"]):
		return
	_registry = root.get_node("Registry")
	_flow = root.get_node("Flow")
	root.get_node("PlayerInput").call("add_virtual_device", 0)
	var ids: Array[StringName] = _registry.call("get_ids", &"bosses")
	if ids.is_empty():
		print("SKIP: no boss in the registry")
		return
	var data: EnemyBase = _registry.call("get_resource", &"bosses", ids[0]) as EnemyBase
	var room: RoomBase = _boss_room(data)
	if room == null:
		print("SKIP: no room hosts the boss '%s'" % data.id)
		return
	_flow.set("run_id_to_play", PinnedRun.pin(_registry, room, room.biome, RoomKind.FILL_BOSS))
	_flow.call("start_run", 0)
	var boss: Actor = null
	var wizard: Node = null
	for i in SHOW_TICKS:
		await physics_frame
		boss = _boss_of(data)
		wizard = _flow.call("get_wizard", 0)
		if boss != null and wizard != null:
			break
	if boss == null or wizard == null:
		fail("the boss '%s' did not show" % data.id)
		return
	Downed.of(wizard).protect(3600.0)
	var banner: BossBannerScript = root.get_node("Hud").call("get_boss_banner") as BossBannerScript
	if not await wait_for(func() -> bool: return banner.modulate.a >= 1.0, 120):
		fail("the banner did not show")
		return
	await shot("boss_entrance")
	root.get_node("Combat").call("hit", -1, boss, boss.health.max_health * HURT_SHARE)
	if not await wait_for(func() -> bool: return not banner.visible, 60 * 6):
		fail("the banner did not go")
		return
	await shot("boss_bar")


## A room of `data`'s biomes that hosts a boss kind, or null.
func _boss_room(data: EnemyBase) -> RoomBase:
	var kinds: Array[StringName] = []
	for kind: Resource in _registry.call("get_all", &"room_kinds"):
		if kind is RoomKind and (kind as RoomKind).fill == RoomKind.FILL_BOSS:
			kinds.append((kind as RoomKind).id)
	for room: Resource in _registry.call("get_all", &"rooms"):
		var template := room as RoomBase
		if template == null or not data.biomes.has(template.biome) or String(template.id).begins_with(PinnedRun.PREFIX):
			continue
		for kind: StringName in kinds:
			if template.hosts(kind):
				return template
	return null


## The body of `data` in play, or null.
func _boss_of(data: EnemyBase) -> Actor:
	var world: Node = _flow.get("world")
	return _find(world, data) if world != null else null


func _find(node: Node, data: EnemyBase) -> Actor:
	for child in node.get_children():
		var actor := child as Actor
		if actor != null and actor.data != null and actor.data.id == data.id and not actor.is_leaving():
			return actor
		var deeper: Actor = _find(child, data)
		if deeper != null:
			return deeper
	return null
