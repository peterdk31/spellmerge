extends "res://tests/support/screenshot.gd"
## Every boss's look, played (boss plan OB9, docs/milestones/boss-old-broom.md, "The broom's data",
## Look): a recorded preview of each pose of its layered body, for the owner to review. Each boss of
## the registry is played alone in a room of its biome that hosts bosses (a pinned run of that room,
## tests/support/pinned_run.gd), against one protected wizard who stands still, so its AI does what
## it does in a fight: the poses are the game's own, read from the body's state (`BodyPose`).
##
## A clip is a run of frames (every EVERY ticks, FRAMES of them) from the first tick its pose
## holds (an idle clip starts again when its pose stops: idle is what it shows between the others);
## the script hurts the boss once the clips before need it (a hit for the hurt pose, below its first
## phase's health for the transition and that phase's poses, then the kill for the remnant). A clip
## is named by its pose (`move` is its own move, `cast` its staff animation; `phase_*` the poses in
## its first phase, if it has one). Each frame is as big as the body's art at rest (its `Sprite` and
## parts) and a margin, round its middle.
## Each clip is saved as a filmstrip, `boss_<id>_<clip>` (2x), and all of a boss's clips as one
## sheet, a row a clip in CLIPS' order, `boss_<id>_sheet` (1x). A boss with no room to stand in, or a
## clip that never comes in its time, is said and skipped; the script fails only when no boss
## shows at all (it passes with no boss in the registry, decision 28).
##
## godot --path . --script res://tests/screenshots/shot_boss_looks.gd

const Pose := BodyPose.Pose

## The clips, in the sheet's order: a name, the pose it starts on (-1: any), the phase it is
## recorded in (-1: the first, before any phase; 0: the data's first phase), whether its pose must
## hold through it, and, for the last, its remnant after the kill.
const CLIPS: Array[Dictionary] = [
	{"name": "idle", "pose": Pose.IDLE, "phase": -1, "hold": true},
	{"name": "windup", "pose": Pose.WINDUP, "phase": -1},
	{"name": "move", "pose": Pose.MOVE, "phase": -1},
	{"name": "wall", "pose": Pose.WALL, "phase": -1},
	{"name": "cast", "pose": Pose.CAST, "phase": -1},
	{"name": "hurt", "pose": Pose.HURT, "phase": -1},
	{"name": "transition", "pose": Pose.TRANSITION, "phase": 0},
	{"name": "phase_idle", "pose": Pose.IDLE, "phase": 0, "hold": true},
	{"name": "phase_windup", "pose": Pose.WINDUP, "phase": 0},
	{"name": "phase_move", "pose": Pose.MOVE, "phase": 0},
	{"name": "death", "pose": -1, "phase": 0},
]
## Frames a clip keeps, and the ticks between two.
const FRAMES: int = 10
const EVERY: int = 3
## The most ticks a stage waits for its clips (each phase), and before the boss shows.
const STAGE_TICKS: int = 60 * 40
const SHOW_TICKS: int = 60 * 5
## The pixels round the body's art at rest in each frame (1x), and the least half a frame is.
const MARGIN: float = 16.0
const LEAST_HALF: Vector2i = Vector2i(24, 24)
## A hit for the hurt pose, as a share of the boss's most health, every PRICK_EVERY ticks until it
## shows.
const PRICK: float = 0.01
const PRICK_EVERY: int = 30
## Ticks the boss may be off the screen before its wizard stands beside it again (the camera
## follows the wizard).
const LOST_TICKS: int = 20
## Where the wizard stands from the boss: in reach of its moves.
const WIZARD_FROM: Vector2 = Vector2(150.0, 0.0)
## The wall clip: from this tick of the first stage, every WALL_EVERY ticks until it comes, the boss
## stands WALL_GAP from the room's right side (its wall a tile thick), its wizard between them.
const WALL_FROM: int = 60 * 6
const WALL_EVERY: int = 60 * 3
const WALL_GAP: float = 140.0
const TILE: float = 32.0

var _registry: Node = null
var _flow: Node = null
## The boss being played: half its frame and the frame's middle from its feet (`_frame_of`).
var _half: Vector2i = LEAST_HALF
var _centre: Vector2 = Vector2.ZERO


func _init() -> void:
	# Each boss's run is pinned here, in its own room.
	pin_room = false


func take() -> void:
	if not need(["Registry", "Flow", "PlayerInput", "Combat", "Projectiles"]):
		return
	_registry = root.get_node("Registry")
	_flow = root.get_node("Flow")
	root.get_node("PlayerInput").call("add_virtual_device", 0)
	var shown: int = 0
	var ids: Array[StringName] = _registry.call("get_ids", &"bosses")
	for id: StringName in ids:
		if await _play(_registry.call("get_resource", &"bosses", id) as EnemyBase):
			shown += 1
	if not ids.is_empty() and shown == 0:
		fail("no boss showed in a room of its biome")


## Play `data` in a pinned room of its biome that hosts bosses and record its clips. False when it
## had no room or never showed.
func _play(data: EnemyBase) -> bool:
	var room: RoomBase = _boss_room(data)
	if room == null:
		print("SKIP: no room hosts the boss '%s'" % data.id)
		return false
	_flow.call("stop_run")
	await settle(3)
	_flow.set("run_id_to_play", PinnedRun.pin(_registry, room, room.biome, RoomKind.FILL_BOSS))
	_flow.call("start_run", 0)
	var boss: Actor = null
	var wizard: Node2D = null
	for i in SHOW_TICKS:
		await physics_frame
		boss = _boss_of(data)
		wizard = _flow.call("get_wizard", 0)
		if boss != null and wizard != null:
			break
	if boss == null or wizard == null:
		print("SKIP: the boss '%s' did not show" % data.id)
		return false
	Downed.of(wizard).protect(3600.0)
	_frame_of(boss)
	_face_off(boss, wizard)
	var look := boss.get_node("CreatureLook") as CreatureLook
	var frames: Dictionary = {}
	var started: Dictionary = {}
	var stage: int = 0
	var stage_ticks: int = 0
	var tick: int = 0
	var last_at: Vector2 = boss.global_position
	var lost: int = 0
	while stage < 3:
		await physics_frame
		tick += 1
		stage_ticks += 1
		var alive: bool = is_instance_valid(boss) and not boss.is_leaving()
		if alive:
			last_at = boss.global_position
			lost = 0 if _in_view(last_at) else lost + 1
			if lost > LOST_TICKS:
				_face_off(boss, wizard)
				lost = 0
		var phase: int = boss.phases.current if alive and boss.phases != null else -1
		var pose: int = look.body_pose() if alive else -1
		# One picture a tick, whatever clips take it (a second grab would skip a tick).
		var image: Image = null
		for clip: Dictionary in CLIPS:
			var name: String = clip["name"]
			var kept: Array = frames.get(name, [])
			if kept.size() >= FRAMES:
				continue
			if not started.has(name):
				var wanted: bool = int(clip["phase"]) == phase
				if name == "death":
					wanted = not alive
				elif not alive or int(clip["pose"]) != pose:
					wanted = false
				# Only once the camera shows all of it (it follows the wizard, who may just have moved).
				if not wanted or not _in_view(last_at):
					continue
				started[name] = tick
			elif clip.get("hold", false) and pose != int(clip["pose"]):
				started.erase(name)
				frames.erase(name)
				continue
			if (tick - int(started[name])) % EVERY != 0:
				continue
			if image == null:
				image = await grab()
			kept.append(_crop(image, on_screen(last_at + _centre)))
			frames[name] = kept
		# A wall met: stood near the room's side, its wizard between it and the wall, every few
		# seconds until its move meets the wall.
		if stage == 0 and alive and not started.has("wall") and stage_ticks >= WALL_FROM and stage_ticks % WALL_EVERY == 0:
			_by_the_wall(boss, wizard)
		# Move the fight on when this stage's clips are in, or its time is up.
		if stage == 0 and (_done(frames, 0, 5) and stage_ticks > 60 or stage_ticks > STAGE_TICKS):
			if not started.has("hurt") and alive and stage_ticks % PRICK_EVERY == 0 and _in_view(last_at):
				root.get_node("Combat").call("hit", _id_of(wizard), boss, boss.health.max_health * PRICK)
			if _done(frames, 5, 6) or stage_ticks > STAGE_TICKS + 120:
				stage = 1
				stage_ticks = 0
				if alive:
					_face_off(boss, wizard)
				if alive and boss.phases != null and not boss.phases.list.is_empty():
					var below: float = boss.phases.list[0].health_below
					var left: float = boss.health.health - boss.health.max_health * (below - 0.02)
					if left > 0.0:
						root.get_node("Combat").call("hit", _id_of(wizard), boss, left)
		elif stage == 1 and (_done(frames, 6, 10) or stage_ticks > STAGE_TICKS or not _has_phases(boss, alive)):
			stage = 2
			stage_ticks = 0
			if alive:
				boss.health.protect(0.0)
				root.get_node("Combat").call("hit", _id_of(wizard), boss, boss.health.health + 1.0)
		elif stage == 2:
			if _done(frames, 10, 11) or stage_ticks > 60 * 5:
				stage = 3
	_save(data, frames)
	_flow.call("stop_run")
	await settle(3)
	return true


## Stand `wizard` WIZARD_FROM beside `boss`, on the side the room has room for.
func _face_off(boss: Actor, wizard: Node2D) -> void:
	var room: Rect2 = (root.get_node("Projectiles").call("bounds") as Rect2).grow(-TILE * 2.0)
	var at: Vector2 = boss.global_position + WIZARD_FROM
	if not room.has_point(at):
		at = boss.global_position - WIZARD_FROM
	wizard.global_position = at


## Stand `boss` near the room's right wall and `wizard` between them, so its next move meets the wall.
func _by_the_wall(boss: Actor, wizard: Node2D) -> void:
	var room: Rect2 = root.get_node("Projectiles").call("bounds")
	var at := Vector2(room.end.x - TILE - WALL_GAP, boss.global_position.y)
	boss.global_position = at
	wizard.global_position = at + Vector2(WALL_GAP * 0.5, 0.0)


## The frame for `boss`: its `Sprite`'s and parts' art at rest, in its own space, and MARGIN round it.
func _frame_of(boss: Actor) -> void:
	var bounds := Rect2()
	var found: bool = false
	var sprites: Array[Node] = [boss.get_node_or_null("Sprite")]
	var parts: Array[BodyPart] = []
	BodyPart.parts_of(boss.get_node_or_null("Sprite"), parts)
	sprites.append_array(parts)
	for node: Node in sprites:
		var sprite := node as Sprite2D
		if sprite == null or sprite.texture == null:
			continue
		var art: Rect2 = (boss.global_transform.affine_inverse() * sprite.global_transform) * sprite.get_rect()
		bounds = art if not found else bounds.merge(art)
		found = true
	if not found:
		bounds = Rect2(-Vector2(LEAST_HALF), Vector2(LEAST_HALF * 2))
	bounds = bounds.grow(MARGIN)
	_centre = bounds.get_center().round()
	_half = Vector2i((bounds.size * 0.5).ceil()).max(LEAST_HALF)


## True when the boss has a phase to show (alive, with phases).
func _has_phases(boss: Actor, alive: bool) -> bool:
	return alive and boss.phases != null and not boss.phases.list.is_empty()


## True when the frame round the body at `at` is all on the screen.
func _in_view(at: Vector2) -> bool:
	var view: Rect2 = root.get_visible_rect().grow_individual(-_half.x, -_half.y, -_half.x, -_half.y)
	return view.has_point(on_screen(at + _centre))


## True when every clip from `from` to before `to` (CLIPS' indices) has its frames.
func _done(frames: Dictionary, from: int, to: int) -> bool:
	for index in range(from, to):
		if (frames.get(CLIPS[index]["name"], []) as Array).size() < FRAMES:
			return false
	return true


## The frame round the screen point `at`, at 1x.
func _crop(image: Image, at: Vector2) -> Image:
	var scale_to_image: Vector2 = Vector2(image.get_size()) / Vector2(root.get_visible_rect().size)
	var size: Vector2i = Vector2i(Vector2(_half * 2) * scale_to_image)
	var middle := Vector2i(at * scale_to_image)
	var corner: Vector2i = (middle - size / 2).clamp(Vector2i.ZERO, image.get_size() - size)
	var crop: Image = image.get_region(Rect2i(corner, size))
	crop.resize(_half.x * 2, _half.y * 2, Image.INTERPOLATE_NEAREST)
	return crop


## Each clip's filmstrip (2x) and the boss's sheet (1x, a row a clip; a clip that never came is a
## dark row).
func _save(data: EnemyBase, frames: Dictionary) -> void:
	var cell: Vector2i = _half * 2
	var gap: int = 2
	var sheet := Image.create((cell.x + gap) * FRAMES, (cell.y + gap) * CLIPS.size(), false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.05, 0.05, 0.07))
	for row in CLIPS.size():
		var name: String = CLIPS[row]["name"]
		var kept: Array = frames.get(name, [])
		if kept.size() < FRAMES:
			print("MISSING: the boss '%s' showed %d of %d frames of '%s'" % [data.id, kept.size(), FRAMES, name])
		if kept.is_empty():
			continue
		var film := Image.create((cell.x + gap) * kept.size(), cell.y, false, Image.FORMAT_RGBA8)
		film.fill(Color(0.05, 0.05, 0.07))
		for column in kept.size():
			var frame: Image = kept[column]
			frame.convert(Image.FORMAT_RGBA8)
			film.blit_rect(frame, Rect2i(Vector2i.ZERO, cell), Vector2i(column * (cell.x + gap), 0))
			sheet.blit_rect(frame, Rect2i(Vector2i.ZERO, cell), Vector2i(column * (cell.x + gap), row * (cell.y + gap)))
		film.resize(film.get_width() * 2, film.get_height() * 2, Image.INTERPOLATE_NEAREST)
		save(film, "boss_%s_%s" % [data.id, name])
	save(sheet, "boss_%s_sheet" % data.id)


## A room of the boss's biome that hosts a room kind filled by a boss (the first by id), or null.
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
	for node: Node in _all_actors():
		var actor := node as Actor
		if actor != null and actor.data != null and actor.data.id == data.id and not actor.is_leaving():
			return actor
	return null


func _all_actors() -> Array[Node]:
	var found: Array[Node] = []
	var world: Node = _flow.get("world")
	if world != null:
		_collect(world, found)
	return found


func _collect(node: Node, into: Array[Node]) -> void:
	for child in node.get_children():
		if child is Actor:
			into.append(child)
		_collect(child, into)


func _id_of(body: Node2D) -> int:
	return int(body.get("id"))
