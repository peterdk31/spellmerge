extends Node
## Flow, the M1 slice (autoload `Flow`): starts the arena, spawns the fixed wave,
## announces `room_entered` and `room_cleared`, and restarts the room when every
## player is down. M3 replaces it with the real room sequence, door voting and
## run lifecycle.
##
## Starting: the main menu sends `play_requested(player)` and nothing else. Flow
## asks `core/registry` for the room (`rooms` / `arena_01`), the enemy and the
## bolt, builds one `Node2D` world (room scene, a wizard for every joined player,
## the wave, a camera) and makes it the current scene, so the menu goes away. The
## whole thing is built in the same frame, far inside the 10 seconds allowed.
##
## Players: one wizard for every player slot that has a device (`core/input`), so
## 1-4 players. The keyboard joins slot 0 if the Play button was pressed with the
## mouse and nobody is joined there. Joining mid-run arrives with `coop` (part 17).
##
## The wave is fixed and sized for four players (WAVE); `difficulty` scales it in
## M3. `room_cleared` is sent when the last enemy of the wave has died.
##
## Restart: when every wizard is down, a timer of RESTART_DELAY seconds runs, then
## a fresh world replaces the old one: new wizards at full health, a new wave, no
## projectiles left, and the bolt's cooldowns reset (the registry hands out one
## shared bolt resource, so a new run must forget its cooldowns).
##
## All timing runs in step(delta), so tests drive it with fixed deltas.

const EventsScript := preload("res://core/events/events.gd")
const RegistryScript := preload("res://core/registry/registry.gd")
const InputManagerScript := preload("res://core/input/input_manager.gd")
const ProjectileManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const CombatScript := preload("res://gameplay/combat/combat.gd")
const AiScript := preload("res://gameplay/ai/ai.gd")
const PlayerScript := preload("res://gameplay/player/player.gd")
const WizardScene: PackedScene = preload("res://content/wizard/base/wizard.tscn")

const PLAYER_SLOTS: int = 4
## Registry folders and ids of the M1 content.
const ROOM_FOLDER: StringName = &"rooms"
const ROOM_ID: StringName = &"arena_01"
const ENEMY_FOLDER: StringName = &"enemies"
const ENEMY_ID: StringName = &"ember_imp"
const SPELL_FOLDER: StringName = &"spells"
const SPELL_ID: StringName = &"bolt"
## The wave, sized for four players: one enemy per entry, placed at the room's
## enemy spawn with that index (wrapped if the room has fewer). An index used
## again puts the enemy a step further along the diagonal.
const WAVE: Array[int] = [0, 1, 2, 3, 4, 5, 0, 3]
const WAVE_REPEAT_OFFSET: Vector2 = Vector2(14.0, 14.0)
## Seconds from the last wizard going down until the room restarts (under 3).
const RESTART_DELAY: float = 2.0
## Hit circle of a wizard for enemy contact, in pixels.
const PLAYER_RADIUS: float = 6.0
## Extra room around the room scene where projectiles may still fly, in pixels.
const PROJECTILE_MARGIN: float = 32.0
## Name of the world node.
const WORLD_NAME: String = "Arena"

enum State { IDLE, RUNNING, CLEARED }

## The services. Only tests set these, before adding the node; otherwise the
## autoloads are used.
var events: EventsScript = null
var registry: RegistryScript = null
var input: InputManagerScript = null
var combat: CombatScript = null
var projectiles: ProjectileManagerScript = null
## Where the world goes. Only tests set this; otherwise the world becomes the
## current scene (the main menu is freed).
var world_parent: Node = null

var state: State = State.IDLE
## The world of the run in progress (null before the first Play).
var world: Node2D = null
## The id of the room of the run in progress.
var room_id: StringName = &""

var _starter: int = 0
var _enemies: Array[Node] = []
var _wizards: Array[Node2D] = []
var _downed: Array[bool] = [false, false, false, false]
var _restart_left: float = -1.0


func _ready() -> void:
	if events == null:
		events = get_node_or_null("/root/Events") as EventsScript
	if registry == null:
		registry = get_node_or_null("/root/Registry") as RegistryScript
	if input == null:
		input = get_node_or_null("/root/PlayerInput") as InputManagerScript
	if combat == null:
		combat = get_node_or_null("/root/Combat") as CombatScript
	if projectiles == null:
		projectiles = get_node_or_null("/root/Projectiles") as ProjectileManagerScript
	if events == null:
		push_warning("Flow: the Events autoload is missing, so the game cannot be started.")
		return
	events.play_requested.connect(_on_play_requested)
	events.enemy_died.connect(_on_enemy_died)
	events.player_downed.connect(_on_player_downed)
	events.player_revived.connect(_on_player_revived)


func _process(delta: float) -> void:
	step(delta)


## Advance the restart timer by `delta` seconds.
func step(delta: float) -> void:
	if _restart_left < 0.0:
		return
	_restart_left -= delta
	if _restart_left <= 0.0:
		_restart_left = -1.0
		start_run(_starter)


## True while a restart is counting down.
func is_restarting() -> bool:
	return _restart_left >= 0.0


## Enemies of the wave still alive.
func enemies_left() -> int:
	return _enemies.size()


## The wizard of player `index` in the current world, or null.
func get_wizard(index: int) -> Node2D:
	for wizard: Node2D in _wizards:
		if is_instance_valid(wizard) and (wizard as PlayerScript).index == index:
			return wizard
	return null


## Build the world and start the run now, replacing any run in progress. Returns
## false (and starts nothing) when content is missing or no player has a device.
func start_run(requester: int) -> bool:
	var room: RoomBase = registry.get_resource(ROOM_FOLDER, ROOM_ID) as RoomBase if registry != null else null
	var enemy_data: EnemyBase = registry.get_resource(ENEMY_FOLDER, ENEMY_ID) as EnemyBase if registry != null else null
	var bolt: SpellBase = registry.get_resource(SPELL_FOLDER, SPELL_ID) as SpellBase if registry != null else null
	if room == null or room.scene == null or enemy_data == null or enemy_data.scene == null or bolt == null:
		push_warning("Flow: the room, the enemy or the bolt is missing from the registry, so no run starts.")
		return false
	_ensure_joined(requester)
	var players: Array[int] = _joined_players()
	if players.is_empty():
		push_warning("Flow: no player has joined a device, so no run starts.")
		return false
	_starter = requester
	_restart_left = -1.0
	_clear_run()
	bolt.reset_cooldowns()
	if projectiles != null:
		projectiles.clear()
		var bounds := Rect2(Vector2.ZERO, _room_size(room)).grow(PROJECTILE_MARGIN)
		projectiles.set_bounds(bounds)
	var new_world := Node2D.new()
	new_world.name = WORLD_NAME
	new_world.add_child(room.scene.instantiate())
	_add_camera(new_world, room)
	_spawn_players(new_world, room, players, bolt)
	_spawn_wave(new_world, room, enemy_data)
	world = new_world
	room_id = room.id
	state = State.RUNNING
	_show_world(new_world)
	if events != null:
		events.room_entered.emit(room.id)
	return true


## End the run in progress and free its world. Flow is idle again, so the next
## `play_requested` starts a run. Nothing shows a menu yet; M3's run area will.
func stop_run() -> void:
	_restart_left = -1.0
	_clear_run()
	state = State.IDLE


func _on_play_requested(player: int) -> void:
	if state != State.IDLE:
		return
	start_run(player)


func _on_enemy_died(_player: int, enemy: Node, _position: Vector2) -> void:
	var at: int = _enemies.find(enemy)
	if at < 0:
		return
	_enemies.remove_at(at)
	if _enemies.is_empty() and state == State.RUNNING:
		state = State.CLEARED
		_restart_left = -1.0
		if events != null:
			events.room_cleared.emit(room_id)


func _on_player_downed(player: int) -> void:
	if player < 0 or player >= PLAYER_SLOTS:
		return
	_downed[player] = true
	if state == State.RUNNING and _all_down():
		_restart_left = RESTART_DELAY


func _on_player_revived(player: int, _reviver: int) -> void:
	if player < 0 or player >= PLAYER_SLOTS:
		return
	_downed[player] = false
	if _restart_left >= 0.0 and not _all_down():
		_restart_left = -1.0


func _all_down() -> bool:
	if _wizards.is_empty():
		return false
	for wizard: Node2D in _wizards:
		if is_instance_valid(wizard) and not _downed[(wizard as PlayerScript).index]:
			return false
	return true


## The Play button may be pressed with the mouse by nobody who has joined: the
## keyboard then takes slot 0.
func _ensure_joined(requester: int) -> void:
	if input == null or requester != 0 or input.is_joined(0):
		return
	input.join(InputManagerScript.KEYBOARD)


func _joined_players() -> Array[int]:
	var players: Array[int] = []
	if input == null:
		return players
	for index in PLAYER_SLOTS:
		if input.is_joined(index):
			players.append(index)
	return players


func _room_size(room: RoomBase) -> Vector2:
	var size := Vector2(640.0, 360.0)
	for point: Vector2 in room.player_spawns:
		size = size.max(point + Vector2(32.0, 32.0))
	for point: Vector2 in room.enemy_spawns:
		size = size.max(point + Vector2(32.0, 32.0))
	for point: Vector2 in room.doors:
		size = size.max(point + Vector2(32.0, 32.0))
	return size


func _add_camera(parent: Node2D, room: RoomBase) -> void:
	var camera := Camera2D.new()
	camera.position = _room_size(room) * 0.5
	parent.add_child(camera)


func _spawn_players(parent: Node2D, room: RoomBase, players: Array[int], bolt: SpellBase) -> void:
	_wizards.clear()
	for index in PLAYER_SLOTS:
		_downed[index] = false
	for index: int in players:
		var wizard := WizardScene.instantiate() as PlayerScript
		wizard.index = index
		wizard.spell = bolt
		if index < room.player_spawns.size():
			wizard.position = room.player_spawns[index]
		parent.add_child(wizard)
		_wizards.append(wizard)
		if combat != null:
			combat.register_player(index, wizard, PLAYER_RADIUS)


func _spawn_wave(parent: Node2D, room: RoomBase, data: EnemyBase) -> void:
	_enemies.clear()
	if room.enemy_spawns.is_empty():
		push_warning("Flow: the room has no enemy spawns, so the wave is empty.")
		return
	var uses: Dictionary = {}
	for entry: int in WAVE:
		var spawn: int = entry % room.enemy_spawns.size()
		var times: int = uses.get(spawn, 0)
		uses[spawn] = times + 1
		var enemy := data.scene.instantiate() as AiScript
		if enemy == null:
			push_warning("Flow: the enemy scene has no AI script on its root, so it is skipped.")
			continue
		enemy.data = data
		enemy.position = room.enemy_spawns[spawn] + WAVE_REPEAT_OFFSET * float(times)
		parent.add_child(enemy)
		_enemies.append(enemy)


## Forget the old run: wizards leave `Combat` (the enemies do it themselves when
## they leave the tree) and the old world is freed.
func _clear_run() -> void:
	if combat != null:
		for index in PLAYER_SLOTS:
			combat.unregister_player(index)
	_wizards.clear()
	_enemies.clear()
	if world != null and is_instance_valid(world):
		_detach(world)
	world = null


## Put the world in the tree. Without `world_parent` it becomes the current scene
## and whatever scene was current (the main menu) goes away.
func _show_world(new_world: Node2D) -> void:
	if world_parent != null:
		world_parent.add_child(new_world)
		return
	var tree: SceneTree = get_tree()
	if tree == null:
		return
	var old: Node = tree.current_scene
	tree.root.add_child(new_world)
	tree.current_scene = new_world
	if old != null and old != new_world:
		_detach(old)


## Take a node out of the tree now (so its enemies and wizards stop at once) and free it.
func _detach(node: Node) -> void:
	var parent: Node = node.get_parent()
	if parent != null:
		parent.remove_child(node)
	node.queue_free()
