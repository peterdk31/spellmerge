class_name FeelView
extends Object
## Feel's view: the camera's shake and kick, this machine's picture and views (the party camera, the
## split screen, the "Effects" row and Auto), the HUD's corners, and a biome's rooms as this machine
## sees and hears them (`_step_rooms`). Methods working on Feel (`feel`), whose members hold all of
## it.

const FeelScript := preload("res://gameplay/feel/feel.gd")
const EffectsAutoScript := preload("res://gameplay/feel/effects_auto.gd")
const PartyCameraScript := preload("res://gameplay/feel/party_camera.gd")
const RoomHearingScript := preload("res://gameplay/feel/room_hearing.gd")
const UnseenRoomsScript := preload("res://gameplay/feel/unseen_rooms.gd")
const UnseenDarkScript := preload("res://gameplay/feel/unseen_dark.gd")
const SplitScreenScript := preload("res://gameplay/feel/split_screen.gd")
const SpectacleScript := preload("res://gameplay/feel/spectacle.gd")
const ProjectileManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const AudioScript := preload("res://core/audio/audio.gd")
const EventsScript := preload("res://core/events/events.gd")
const ActorsScript := preload("res://core/actors/actors.gd")
const FramesScript := preload("res://core/sim/frames.gd")
const SplitBudgetScript := preload("res://gameplay/feel/split_budget.gd")
const EffectsQualityScript := preload("res://gameplay/feel/effects_quality.gd")
const ScreenViewsScript := preload("res://core/display/screen_views.gd")
const UnseenMaskScript := preload("res://gameplay/feel/unseen_mask.gd")
const RoomsViewBoxesScript := preload("res://gameplay/feel/view_boxes.gd")
const InputManagerScript := preload("res://core/input/input_manager.gd")

## Not Feel's own: Feel, the other jobs this one calls and Feel's containers it works on, each
## Feel's own (shared, never a copy), linked by `link`.
const LINKED: Array[StringName] = [&"feel", &"_juiced_frame", &"_juiced_step", &"_juiced_body", &"_juiced_by", &"_juiced_kind", &"_portal_view", &"party_camera", &"effects_auto", &"_one_view", &"_layout_views", &"_hearing", &"_unseen_rooms", &"_rooms_seen_box", &"_reaction_heard"]

var feel: FeelScript = null
var _juiced_frame: PackedInt64Array
var _juiced_step: PackedInt64Array
var _juiced_body: PackedInt64Array
var _juiced_by: PackedInt32Array
var _juiced_kind: Array[StringName]
var _portal_view: PortalView
var party_camera: PartyCameraScript
var effects_auto: EffectsAutoScript
var _one_view: ScreenViewsScript
var _layout_views: ScreenViewsScript
var _hearing: RoomHearingScript
var _unseen_rooms: UnseenRoomsScript
var _rooms_seen_box: RoomsViewBoxesScript
var _reaction_heard: Dictionary


## Takes Feel and its containers and jobs, by the names in LINKED (`Feel._link_jobs`).
func link(owner: FeelScript) -> void:
	feel = owner
	for name: StringName in LINKED:
		if name != &"feel":
			set(name, owner.get(name))


## A biome's rooms as this machine sees and hears them (connected biomes CB12): the places heard
## (Audio's ears ask), the music and the bed of the room followed, the mouths, the gather doors'
## wizards and the dark of the unvisited rooms.
func _step_rooms(real_delta: float, seats_here: int) -> void:
	# Feel's numbers and services this reads, once (a read through `feel` is a lookup by name).
	var projectiles: ProjectileManagerScript = feel.projectiles
	var spectacle: SpectacleScript = feel._spectacle
	var audio: AudioScript = feel.audio
	var unseen: UnseenDarkScript = feel._unseen
	var grid: RoomGrid = projectiles.grid() if projectiles != null and is_instance_valid(projectiles) else null
	var table: ActorsScript = feel._actor_table()
	if audio != null and not audio.ears.heard.is_valid():
		# Feel back in the tree after it let go of Audio's ears (`_exit_tree`).
		audio.ears.heard = _hearing.hears
	_hearing.step(table, seats_here, grid)
	if _hearing.in_biome() and _hearing.followed() >= 0:
		if feel._body_sounds != null:
			feel._body_sounds.room_music = _hearing.music()
			feel._body_sounds.room_intensity = _hearing.intensity_of(_hearing.followed())
		if feel._ambience != null:
			feel._ambience.use(_hearing.air())
	if feel._gather_doors != null:
		feel._gather_doors.see(table)
	if feel._mouths != null:
		feel._mouths.step(real_delta, grid)
	if feel._mouth_symbols != null:
		feel._mouth_symbols.step(real_delta, table, seats_here, grid)
	if unseen != null:
		unseen.step(real_delta, grid)
		# An unvisited room is the void (the owner, 2026-11-21): the void's motes drift over its dark.
		if spectacle != null:
			spectacle.set_void_covers(unseen.void_covers())
		# What those rooms hold is not drawn under the dark, nor what lies out of every view (the
		# owner, 2026-11-21).
		_unseen_rooms.step(unseen, grid, _rooms_seen(), spectacle.marks if spectacle != null else null, spectacle.pool.regions if spectacle != null and spectacle.pool != null else null, feel._cover_rooms)
		# What lies there is hidden one by one, so no cover is drawn over them (the owner, 2026-11-21,
		# on #899): what lies on the floor and the rooms' light (the bodies and mists in `step`).
		if spectacle != null and spectacle.light != null:
			spectacle.light.hide_unseen(unseen.mask)
		if unseen.mask.changes != feel._masked_for:
			feel._masked_for = unseen.mask.changes
			for look in feel._masked_looks:
				look.queue_redraw()
	if feel._teleports != null:
		feel._teleports.table = table
		feel._teleports.step(real_delta)
	if feel._void != null:
		feel._void.step(grid, projectiles.bounds() if grid != null else Rect2())
	if feel._tints != null:
		feel._tints.step(real_delta, grid, spectacle.light if spectacle != null else null)
	if feel._party_map != null:
		feel._party_map.input = _input_manager()
		feel._party_map.step(real_delta, table, seats_here, grid, _views_shown().scaled_into(_layout_views, 1.0 / feel._party_map.transform.get_scale().x))


## The looks that draw what lies on a room's floor told where nothing is drawn (the dark's mask).
func _mask_looks() -> void:
	var mask: UnseenMaskScript = feel._unseen.mask
	feel._gather_doors.unseen = mask
	feel._mouths.unseen = mask
	feel._locks.unseen = mask
	feel._runes.unseen = mask
	feel._ground_items.unseen = mask
	feel._coins.unseen = mask
	feel._special_rooms.unseen = mask
	feel._reward_items.unseen = mask
	feel._masked_looks = [feel._gather_doors, feel._mouths, feel._locks, feel._runes, feel._ground_items, feel._coins, feel._special_rooms, feel._reward_items]


## The open portals, read once (`CarrierPortal.read_view`), drawn by the portal look; their motes
## into the spectacle's pool while motes are on.
func _step_portals() -> void:
	var portals: CarrierPortal = CarrierPortal.of(feel.spells as SpellRuntime) if feel.spells is SpellRuntime else null
	if portals != null:
		portals.read_view(_portal_view)
	else:
		_portal_view.portals = 0
		_portal_view.gates = 0
	feel._portal_look.step(_portal_view, feel._actor_table(), feel._spectacle.pool if feel._spectacle.motes_on() else null, feel._clock)


## A run starts (`room_entered`): no reaction was heard and no hit was juiced, so the first ones
## shake and sound (view only since N4: the holds are the game's, `HitStop`).
func _on_room_entered(room_id: StringName, number: int) -> void:
	# A world laid anew (FIRST_ROOM): a biome's later rooms are the same world (connected biomes CB3).
	if number != EventsScript.FIRST_ROOM:
		return
	party_camera.room_entered()
	if feel.split_screen != null:
		feel.split_screen.camera.reset()
	# What held a sound is gone with the last room; the music is the new room's (`body_sounds.gd`).
	if feel.audio != null:
		feel.audio.clear_world()
	if feel._held != null:
		feel._held.clear()
	var room: RoomBase = feel.registry.get_resource(FeelScript.ROOM_FOLDER, room_id) as RoomBase if feel.registry != null else null
	if feel._body_sounds != null:
		feel._body_sounds.room_entered(room.music if room != null else null)
	if feel._spawn_look != null:
		feel._spawn_look.use_room(room)
	if feel._remnants != null:
		feel._remnants.clear()
	_reaction_heard.clear()
	_juiced_frame.fill(0)
	_juiced_step.fill(0)
	_juiced_body.fill(0)
	_juiced_by.fill(0)
	_juiced_kind.fill(&"")


## Back to the main menu (`main_menu_requested`): no room follows, so the room's music fades out under
## the menu (the room's sound hears it itself, `room_ambience.gd`).
func _on_main_menu_requested(_player: int) -> void:
	if feel._body_sounds != null:
		feel._body_sounds.room_entered(null)


## A bit per seat played on this machine (`Frames.seats_here`): whose wizards the party camera
## holds. 0 (everyone's) without the frames service.
func _seats_here() -> int:
	if feel.frames == null or not is_instance_valid(feel.frames):
		feel.frames = null
		var tree: SceneTree = Engine.get_main_loop() as SceneTree
		if tree != null and tree.root != null:
			feel.frames = tree.root.get_node_or_null(^"Frames") as FramesScript
	return feel.frames.seats_here() if feel.frames != null else 0


## The input manager (the "PlayerInput" autoload unless a test set its own), or null.
func _input_manager() -> InputManagerScript:
	if feel.input == null or not is_instance_valid(feel.input):
		feel.input = null
		var tree: SceneTree = Engine.get_main_loop() as SceneTree
		if tree != null and tree.root != null:
			feel.input = tree.root.get_node_or_null(^"PlayerInput") as InputManagerScript
	return feel.input


## The part of the world this machine shows now: the party camera's picture, or while the screen is
## split the box round every view's (`ScreenViews.world_box`).
func _picture() -> Rect2:
	# Feel's numbers and services this reads, once (a read through `feel` is a lookup by name).
	var split_screen: SplitScreenScript = feel.split_screen
	if split_screen != null and split_screen.is_drawing():
		return split_screen.camera.views.world_box()
	return party_camera.visible_rect()


## Where this machine looks from (the cover's nearest bodies, the room's ambience): the picture's
## middle; while split, the middle of the first view's (the box round the views may be the void
## between them). INF with no picture.
func _focus(picture: Rect2) -> Vector2:
	# Feel's numbers and services this reads, once (a read through `feel` is a lookup by name).
	var split_screen: SplitScreenScript = feel.split_screen
	if split_screen != null and split_screen.is_drawing():
		var views: ScreenViewsScript = split_screen.camera.views
		return views.to_screen[0].affine_inverse() * (views.screen * 0.5)
	return picture.get_center() if picture.has_area() else Vector2.INF


## This machine's views now: the split screen's, or the party camera's one picture as one view.
func _views_shown() -> ScreenViewsScript:
	# Feel's numbers and services this reads, once (a read through `feel` is a lookup by name).
	var split_screen: SplitScreenScript = feel.split_screen
	if split_screen != null and split_screen.is_drawing():
		return split_screen.camera.views
	var camera: Camera2D = party_camera.camera if is_instance_valid(party_camera.camera) else null
	var picture: Rect2 = party_camera.visible_rect()
	if camera == null or not picture.has_area():
		_one_view.count = 0
		return _one_view
	var zoom: float = camera.zoom.x
	_one_view.set_single(picture.size * zoom, Transform2D(0.0, Vector2(zoom, zoom), 0.0, -picture.position * zoom), _seats_here())
	return _one_view


## The camera followed now, or null when it is gone (a freed world's).
func _live_camera() -> Camera2D:
	return feel._camera if feel._camera != null and is_instance_valid(feel._camera) else null


## The parts of the world drawn this frame, for what lies out of every view (`unseen_rooms.gd`): the
## split's views' boxes (`ScreenViews`, laid this frame), else the party camera's picture where it
## was put this frame (`PartyCamera.visible_rect`): the viewport's canvas transform follows the
## camera only after this frame's process, a frame late, and on a long pan a room at the leading
## edge would come in a frame after its place on screen. Without a party camera, the spectacle's.
func _rooms_seen() -> RoomsViewBoxesScript:
	# Feel's numbers and services this reads, once (a read through `feel` is a lookup by name).
	var spectacle: SpectacleScript = feel._spectacle
	if spectacle == null:
		return null
	var split: ScreenViews = ScreenViews.on(feel.get_viewport()) if feel.is_inside_tree() else null
	if split != null and split.is_split():
		return spectacle.view_boxes()
	var box: Rect2 = party_camera.visible_rect()
	if not box.has_area():
		return spectacle.view_boxes()
	_rooms_seen_box.set_one(box)
	return _rooms_seen_box


## How this machine's screen splits (`SplitScreenSetting`: DYNAMIC, the Voronoi split, or EQUAL,
## equal panes; the pause menu's "Split screen", `split_screen_changed`). View only.
func set_split_mode(mode: int) -> void:
	feel.split_mode = SplitScreenSetting.snap(mode)
	if feel.split_screen != null:
		feel.split_screen.camera.set_equal(feel.split_mode == SplitScreenSetting.EQUAL)


## The "Effects" setting's `mode` (`EffectsSetting`; the pause menu's "Effects", `effects_changed`):
## AUTO lets the watcher choose the row from the drawn frames' times, starting at HIGH; LOW, MEDIUM
## and HIGH draw that row. Taken in one frame (the owner's exception to "Smooth", 2026-11-22). View only.
func set_effects_mode(mode: int) -> void:
	feel.effects_mode = EffectsSetting.snap(mode)
	if feel.effects_mode == EffectsSetting.AUTO:
		effects_auto.reset()
		feel._floor_wait = 0.0
		_draw_effects_row(effects_auto.level)
	else:
		_draw_effects_row(EffectsQualityScript.of_setting(feel.effects_mode))


## The effects drawn at `row` from now on, and the HUD told (`effects_row_changed`: its menu shows
## Auto's row).
func _draw_effects_row(row: EffectsQualityScript.Level) -> void:
	# Feel's numbers and services this reads, once (a read through `feel` is a lookup by name).
	var spectacle: SpectacleScript = feel._spectacle
	spectacle.set_effects_quality(row)
	if feel._cover_rooms != null:
		feel._cover_rooms.set_floor_quality(spectacle.quality.floor_motes, spectacle.quality.floor_shimmer)
	if feel.events != null:
		feel.events.effects_row_changed.emit(EffectsQualityScript.setting_of(row))


## The watcher stepped by this drawn frame (`real_delta` seconds), its row drawn when it changes while
## the setting is Auto. One ladder while split: the split screen's budget (`split_budget.gd`, faster
## to act) takes its fallbacks first and Auto drops a row only once the budget is on its last rung;
## while the budget has a fallback taken, frames fast long enough for a rise have the budget give
## a rung back instead (a try: the budget taking it again soon makes the next wait longer). With one
## picture the budget's rung changes nothing drawn, so it holds nothing.
func _step_effects(real_delta: float) -> void:
	# Feel's numbers and services this reads, once (a read through `feel` is a lookup by name).
	var split_screen: SplitScreenScript = feel.split_screen
	feel._floor_wait -= real_delta
	if feel._floor_wait <= 0.0:
		# The display (a window moved to another screen) or the frame cap may change: read again a second.
		feel._floor_wait = 1.0
		var shortest: float = shortest_frame()
		effects_auto.set_floor(shortest)
		if split_screen != null:
			split_screen.budget.set_floor(shortest)
	if feel.effects_mode != EffectsSetting.AUTO:
		return
	var split: bool = split_screen != null and split_screen.views().size() > 1
	var budget: SplitBudgetScript = split_screen.budget if split_screen != null else null
	var rung: int = budget.rung if split else 0
	if split and rung > feel._rung_seen:
		effects_auto.failed_try()
	var last_rung: int = SplitBudgetScript.RUNG_MOTES.size() - 1
	if effects_auto.step(real_delta, split and rung > 0, split and rung < last_rung):
		_draw_effects_row(effects_auto.level)
	if effects_auto.rise_blocked:
		effects_auto.rise_blocked = false
		if split:
			budget.give_back()
	feel._rung_seen = budget.rung if split else 0


## The shortest frame this machine draws (seconds; 0: none known): the display's refresh and the
## frame cap (`Engine.max_fps`), so Auto never counts a 50 Hz display's frames as slow. View only.
static func shortest_frame() -> float:
	var shortest: float = 0.0
	var refresh: float = DisplayServer.screen_get_refresh_rate()
	if refresh > 1.0:
		shortest = 1.0 / refresh
	if Engine.max_fps > 0:
		shortest = maxf(shortest, 1.0 / float(Engine.max_fps))
	return shortest


## Tell the HUD where each seat's corner panel and menus sit now (`hud_corners_changed`), once a
## change: the equal split's panes move them (the owner, 2026-11-20). View only.
func _tell_hud_corners() -> void:
	# Feel's numbers and services this reads, once (a read through `feel` is a lookup by name).
	var split_screen: SplitScreenScript = feel.split_screen
	if split_screen.camera.corners_version == feel._corners_sent or feel.events == null:
		return
	feel._corners_sent = split_screen.camera.corners_version
	feel.events.hud_corners_changed.emit(split_screen.camera.corners)


## Whether `at` (world) is in this machine's picture, or within SHAKE_REACH pixels of its edge: only
## what happens there shakes or kicks the camera (owner, 2026-11-13: each machine's camera holds its
## own wizards, so a teammate's fight on another machine's picture must not shake this one). True
## with no place (`Vector2.INF`) or before the party camera has a picture.
func _in_picture(at: Vector2) -> bool:
	# Feel's numbers and services this reads, once (a read through `feel` is a lookup by name).
	var split_screen: SplitScreenScript = feel.split_screen
	if at == Vector2.INF:
		return true
	# While split: in a view's cell, or within SHAKE_REACH of it (not the void between views).
	if split_screen != null and split_screen.is_drawing():
		return split_screen.camera.views.view_showing(at, FeelScript.SHAKE_REACH) >= 0
	var picture: Rect2 = _picture()
	return not picture.has_area() or picture.grow(FeelScript.SHAKE_REACH).has_point(at)


## Shake the screen by `amount` (trauma, 0 to 1; its pixels are its square times `max_shake_pixels`):
## it raises the shake to `amount` and never adds to it (owner, 2026-11-07: a storm's hits each adding
## theirs kept the screen at its most), so a stream of small shakes holds at one's, and a bigger
## moment (a blast, a swing) still shows bigger.
func _shake(amount: float) -> void:
	feel._trauma = maxf(feel._trauma, minf(amount, 1.0))


## Follow the current camera: when it changed, the old one is put back at rest. Looked for once a
## step (every hit asks; `_reset_camera` looks again at once).
func _refresh_camera() -> void:
	if not feel.is_inside_tree() or feel._camera_step == feel._steps:
		return
	feel._camera_step = feel._steps
	var current: Camera2D = feel.get_viewport().get_camera_2d()
	if current == feel._camera:
		return
	if feel._camera != null and is_instance_valid(feel._camera):
		feel._camera.offset = Vector2.ZERO
	feel._camera = current


func _apply_camera() -> void:
	if feel._camera != null and is_instance_valid(feel._camera):
		feel._camera.offset = feel.shake_offset


func _reset_camera() -> void:
	feel.shake_offset = Vector2.ZERO
	feel._camera_step = -1
	_refresh_camera()
	_apply_camera()
