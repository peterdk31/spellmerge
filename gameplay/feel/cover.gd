extends Node2D
## Ground cover's look (ground cover GC3, docs/milestones/ground-cover.md, rule 6): the tufts of one
## room's cover, swaying in a slow wind. Feel's own script (`Feel.cover()`, the first room's; one a
## piece of the world, `cover_rooms.gd`, connected biomes CB3b), never more of feel.gd.
##
## **The layout** is heard, never asked: `room_built` (Flow, whenever it lays a room out: a run's
## start, each room entered, a restore into another room) works out the room's cover
## (`CoverLayout.of_piece`, from the layout at its place and mirrored with it, its `RoomBase` and the
## registry's cover kinds) and lays its tufts, at the room's place, scattered again over the mirrored
## cells (the art is drawn, never flipped: decision 6); the layout's node is not kept. In the game
## Feel's `cover_rooms.gd` hears it and hands each room's view its layout (`lay`) and its changes
## (`show_state`); a view made with the bus (a test's) hears the first room's itself. A restore into
## the room shown sends nothing and needs nothing: the tufts are still the room's.
##
## **One batch a kind** (made by `Batches.multimesh()`; its box its room's, `Batches.box_of`, so a view
## that does not show the room never draws it), its rows the tufts of every
## cell of that kind, scattered by `CoverTufts` (the editor's preview draws the same ones), drawn by
## `cover.gdshader` with the kind's sheet. The node is at the floor marks' z (`RoomBase.FLOOR_Z + 1`)
## and before the marks' layer in Feel's tree, so the marks lie over the cover and every body (z 0)
## over both.
##
## **A cell's state picks its tufts' frames** through each row's custom data (`show_state`; the
## cover area's changes, heard as `cover_changed`, GC5): a state that draws no frame folds its
## tufts away. An animated state (`CoverState.animation_frames`; docs/STYLE.md, "Smooth") plays its
## frames from when the cell began to show it (`shown_at`, the grid's second channel), once or
## looping, worked out in the shader. The rows are kept
## here and a changed kind's are handed to its batch once, at the frame's `step`, however many of its
## cells changed.
##
## **Bodies bend it and trample it** (GC4; look only, decision 4): each frame `step` takes the bodies
## of the actor table (wizards, enemies, props: everything that stands), keeps the `BODIES` nearest
## the camera's middle and hands them to the shader, which leans the tufts near each away from it.
## The same bodies walk Feel's view grid of when each covered cell was last walked through
## (`walked_at`, its first channel, Feel's clock; the shader's `cell_times` texture): a walked cell's
## tufts lie flat while bodies are in it and its kind's `trample_hold` seconds after, then spring
## back over its `trample_spring` (`flatness`), drawing their state's `trampled_frames` or pressed down. None of it
## is the game's: no cell's state changes, and the simulation never reads it.
##
## Nothing is allocated once a room is laid: a frame sets the wind's time, hands over the bodies only
## when they moved (into one of two arrays sized once, in turn, so the one the batches hold is never
## written), writes the grid's walked cells into its image and hands that over only when one was,
## and hands over the changed rows (`step`).
##
## **It sways in the world's stirs** (docs/milestones/atmosphere.md, E): a tuft leans with the air the
## shots drag past it and is pushed out by a blast's wave and sways back (`cover.gdshader`, from the
## spectacle's `stirs.gd`, handed to every batch by `step`'s `hand_stirs` whenever their version
## changes; the cover knows nothing else of them), as far as
## its state bends, eased on Feel's clock.
##
## **A burning cell gives off embers and smoke** (GC8): a state's `motes`, given off by
## `cover_motes.gd` from every cell showing it (`show_state` tells it), into the spectacle's pool.
##
## Pure view: no state of the game is here, and nothing here is read by the simulation.

const SHADER: Shader = preload("res://gameplay/feel/cover.gdshader")
const BatchesScript := preload("res://core/projectiles/batches.gd")
const ShaderWarmupScript := preload("res://core/projectiles/shader_warmup.gd")
const EventsScript := preload("res://core/events/events.gd")
const ActorsScript := preload("res://core/actors/actors.gd")
const RegistryScript := preload("res://core/registry/registry.gd")
const CoverMotesScript := preload("res://gameplay/feel/cover_motes.gd")
const MotesScript := preload("res://gameplay/feel/mote.gd")
const RampTableScript := preload("res://gameplay/feel/ramp_table.gd")

const ROOM_FOLDER: StringName = &"rooms"
const COVER_FOLDER: StringName = &"cover"
## Floats in a row: the transform (8), the colour (4) and the custom data (4).
const STRIDE: int = 16
## The most a tuft sways at its tip, in pixels (the shader's SWAY_CODE).
const SWAY_CODE: float = 8.0
## The most bodies that bend the cover at once: the nearest the camera's middle (the shader's BODIES).
const BODIES: int = 32
## How near a body bends a tuft, and how far a tuft right at a body leans at its tip, in pixels.
const BEND_REACH: float = 14.0
const BEND_PIXELS: float = 4.0
## How far past a tuft's frame and bend a batch's box reaches (px): its sway and its frame's pixels.
const BOX_PAD: float = 8.0
## Where a body's feet reach from its position, in pixels: it walks every covered cell these points
## lie in, the row just in front of it too, whose tufts stand over the trail (GC9: a one-cell
## trail was hidden by them in dense grass).
const FOOTPRINT: PackedVector2Array = [Vector2(-6.0, -4.0), Vector2(6.0, -4.0), Vector2(-6.0, 10.0), Vector2(6.0, 10.0)]
## The least and the most of FOOTPRINT's offsets each way (`_walk`'s test of a body off the piece).
const FOOT_REACH_LOW: Vector2 = Vector2(-6.0, -4.0)
const FOOT_REACH_HIGH: Vector2 = Vector2(6.0, 10.0)
## Flat, a tuft with no trampled frame is pressed down by this much of its height (how long a walked
## cell lies flat and springs back is its kind's: `CoverKind.trample_hold`, `trample_spring`).
const FLATTEN: float = 0.5
## How far the shots' wake and a blast's push lean a tuft's tip at their fullest, px (the shader's
## STIR_SHOT_PIXELS and STIR_BLAST_PIXELS), times its state's bend.
const STIR_SHOT_PIXELS: float = 2.5
const STIR_BLAST_PIXELS: float = 10.0
## When a cell never walked through was walked (long before any clock).
const NEVER: float = -1.0e6
## `step_with`'s box of the bodies found when it is not told one (every view takes them), and
## `found_box` with no body found.
const EVERYWHERE: Rect2 = Rect2(-1.0e9, -1.0e9, 2.0e9, 2.0e9)
const NOWHERE: Rect2 = Rect2(1.0e9, 1.0e9, 0.0, 0.0)

## The bus and the registry (a test's own view's; null for Feel's views, which `cover_rooms.gd` hands
## their rooms, and in a test that lays a layout itself).
var events: EventsScript = null
var registry: RegistryScript = null

## The cover laid (null before the first room). Read only.
var layout: CoverLayout = null
## The motes its cells give off in the states that name some (burning grass's embers and smoke,
## GC8). Read only, but for its `ramp_table` (Feel's spectacle's, set once).
var motes: CoverMotesScript = CoverMotesScript.new()
## Each laid kind's batch, in the layout's kinds' order (a kind with no sheet has none: null).
var _batches: Array[MultiMeshInstance2D] = []
## Each laid kind's rows (STRIDE floats a tuft), the copy every change is written to, and whether
## they changed since they were last handed to their batch (`step` hands them over).
var _rows: Array[PackedFloat32Array] = []
var _dirty: PackedByteArray = PackedByteArray()
## Batches made for an earlier room and not used by this one, kept to be used again.
var _spare: Array[MultiMeshInstance2D] = []
## Each cell's first tuft's slot (its tufts' place in its kind's cells, in cell order; -1 for none),
## each kind's row of each slot (the rows are in drawing order, `CoverTufts.draw_key`), and the state
## each cell shows.
var _first_slot: PackedInt32Array = PackedInt32Array()
var _slot_row: Array[PackedInt32Array] = []
## Each kind's roll of each slot (`CoverTufts.roll`), kept from laying it, so a cell's change rolls
## nothing again (a whole room catching at once, GC6).
var _slot_rolls: Array[PackedInt64Array] = []
var _shown: PackedInt32Array = PackedInt32Array()
## The kinds a test or a screenshot gave (`use_kinds`); the registry's while null.
var _given: Array[CoverKind] = []
var _use_given: bool = false
## The actor table's open ids (sized once to every actor), and the nearest bodies found this frame:
## where each is and how far from the camera's middle (squared), `_near_count` of them.
var _ids: PackedInt32Array = PackedInt32Array()
var _near_at: PackedVector2Array = PackedVector2Array()
var _near_far: PackedFloat32Array = PackedFloat32Array()
var _near_count: int = 0
## The two arrays the bodies are handed to the batches in, in turn (`_sent` the one they hold), and
## how many were handed over last.
var _send: Array[PackedVector2Array] = []
var _sent: int = 0
var _sent_count: int = 0
## Feel's view grid, a pixel a cell of an image of the layout's size: when each cell was last walked
## through (red) and when it began to show its state (green), Feel's clock (`NEVER` for never); and
## the texture the batches read it by (`cell_times`), handed over when it changed (`_times_dirty`).
var _times: Image = null
var _times_texture: ImageTexture = null
var _times_dirty: bool = false
## Feel's clock at the last `step`: when a change heard since began to show.
var _now: float = 0.0
## The stirs' `version` last handed to the batches (-1: hand them over at the next step).
var _stirs_version: int = -1
## While switched off: true when a `step` held its hand-over back, and the stirs it was told.
var _held: bool = false
var _held_stirs_version: int = -1
var _held_hand_stirs: Callable = Callable()
## True when the bodies handed over (`_send`) changed since the batches were last told them.
var _bodies_held: bool = false
## The box round the bodies found by the last `step` (`found_box`), and, while switched off and out
## of every body's reach, the bodies another view found this frame (`step_with`), taken only when
## shown again (`_bodies_due`; the performance pass, 2026-11-21: 27 views each walked the 32 bodies a
## frame).
var _found_box: Rect2 = NOWHERE
var _due_found: PackedVector2Array = PackedVector2Array()
var _due_count: int = 0
var _bodies_due: bool = false


## Cover drawn at `z` (Feel's MARK_Z).
func _init(z: int) -> void:
	top_level = true
	z_index = z
	_ids.resize(ActorsScript.ACTORS)
	_near_at.resize(BODIES)
	_near_far.resize(BODIES)
	for buffer in 2:
		var bodies := PackedVector2Array()
		bodies.resize(BODIES)
		_send.append(bodies)


func _ready() -> void:
	ShaderWarmupScript.want(SHADER, ShaderWarmupScript.BATCH)
	if not visibility_changed.is_connected(_on_visibility_changed):
		visibility_changed.connect(_on_visibility_changed)
	if events != null and not events.room_built.is_connected(_on_room_built):
		events.room_built.connect(_on_room_built)
	if events != null and not events.cover_changed.is_connected(_on_cover_changed):
		events.cover_changed.connect(_on_cover_changed)


## Lay the cover with `kinds` instead of the registry's from the next room on (tests and
## screenshots, before the game has cover of its own); null: the registry's again.
func use_kinds(kinds: Variant) -> void:
	_use_given = kinds != null
	_given = [] as Array[CoverKind]
	if kinds != null:
		for kind: CoverKind in kinds as Array:
			_given.append(kind)


## The cover kinds a room's cover is worked out with: the registry's that can be drawn
## (`CoverSketch.usable`, as the editor takes them).
func kinds() -> Array[CoverKind]:
	if _use_given:
		return _given
	var found: Array[CoverKind] = []
	if registry != null:
		for item: Resource in registry.get_all(COVER_FOLDER):
			if item is CoverKind and CoverSketch.usable(item as CoverKind):
				found.append(item as CoverKind)
			elif item is CoverKind:
				push_warning("Cover: the cover kind '%s' is left out: %s" % [(item as CoverKind).id, "; ".join((item as CoverKind).problems())])
	return found


## A room was laid out (`room_built`): the first room's cover, from its layout as built.
func _on_room_built(room_id: StringName, number: int, layout_root: Node) -> void:
	if number == EventsScript.FIRST_ROOM:
		lay(laid_from(room_id, layout_root))


## The cover of the piece `room_id` laid as `layout_root` (at its place, mirrored with it), with this
## view's kinds.
func laid_from(room_id: StringName, layout_root: Node) -> CoverLayout:
	var room: RoomBase = registry.get_resource(ROOM_FOLDER, room_id) as RoomBase if registry != null else null
	return CoverLayout.of_piece(layout_root, room, kinds())


## The cover area's changes (`cover_changed`, GC5): the first room's cells show their new states.
func _on_cover_changed(room: int, cells: PackedInt32Array, states: PackedInt32Array) -> void:
	if room == EventsScript.FIRST_ROOM:
		show_states(cells, states)


## Each of `cells` shows its state of `states` (a `cover_changed`'s).
func show_states(cells: PackedInt32Array, states: PackedInt32Array) -> void:
	for at in mini(cells.size(), states.size()):
		show_state(cells[at], states[at])


## Show `laid`, a room's cover, every cell in its kind's first state (at rest).
func lay(laid: CoverLayout) -> void:
	layout = laid
	for batch in _batches:
		if batch != null:
			batch.multimesh.instance_count = 0
			batch.visible = false
			# A spare holds none of this room's arrays or grid (so they stay written in place).
			var spare_material := batch.material as ShaderMaterial
			spare_material.set_shader_parameter(&"bodies", PackedVector2Array())
			spare_material.set_shader_parameter(&"body_count", 0)
			spare_material.set_shader_parameter(&"cell_times", null)
			_spare.append(batch)
	_batches.clear()
	_rows.clear()
	_slot_row.clear()
	_slot_rolls.clear()
	_first_slot.resize(laid.cells.size())
	_first_slot.fill(-1)
	_shown.resize(laid.cells.size())
	_shown.fill(0)
	_dirty.resize(laid.kinds.size())
	_dirty.fill(0)
	_times = Image.create_empty(maxi(laid.columns, 1), maxi(laid.rows, 1), false, Image.FORMAT_RGF)
	# Shown since the room was laid: a loop then steps evenly (a time from `NEVER` would lose the
	# shader's float precision).
	_times.fill(Color(NEVER, _now, 0.0, 1.0))
	_times_texture = ImageTexture.create_from_image(_times)
	_times_dirty = false
	_sent_count = -1
	_stirs_version = -1
	for index in laid.kinds.size():
		_rows.append(PackedFloat32Array())
		_slot_row.append(PackedInt32Array())
		_slot_rolls.append(PackedInt64Array())
		_batches.append(_lay_kind(index))
	motes.lay(laid)


## The batch of the kind `kind_id` in the room laid (null for none, or a kind with no sheet).
func batch_of(kind_id: StringName) -> MultiMeshInstance2D:
	if layout == null:
		return null
	for index in layout.kinds.size():
		if layout.kinds[index].id == kind_id:
			return _batches[index]
	return null


## The rows of the kind `kind_id` in the room laid, as its batch draws them after the next `step`
## (STRIDE floats a tuft: its transform, colour and custom data; empty for none). Read only.
func rows_of(kind_id: StringName) -> PackedFloat32Array:
	if layout == null:
		return PackedFloat32Array()
	for index in layout.kinds.size():
		if layout.kinds[index].id == kind_id:
			return _rows[index]
	return PackedFloat32Array()


## Every batch of the room laid, in its kinds' order (null for a kind with no sheet).
func batches() -> Array[MultiMeshInstance2D]:
	return _batches


## The state cell `cell` shows (its index in its kind's states; 0 at rest).
func shown_state(cell: int) -> int:
	return _shown[cell] if cell >= 0 and cell < _shown.size() else 0


## The cell of the layout's grid the shader reads a tuft's walk from, for its foot `foot` (world
## pixels) on a grid whose corner is `origin` (`CoverLayout.origin`): the cell it stands in, a foot on
## a cell's bottom edge its own (`CoverTufts.foot` puts a foot 1 to `CELL` pixels below its cell's
## top). The shader's expression, mirrored.
static func foot_cell(foot: Vector2, origin: Vector2 = Vector2.ZERO) -> Vector2i:
	var at: Vector2 = (foot - origin) / float(CoverLayout.CELL) - Vector2(0.0, 0.001)
	return Vector2i(floori(at.x), floori(at.y))


## When cell `cell` was last walked through (Feel's clock; `NEVER` for never, or no such cell).
func walked_at(cell: int) -> float:
	if layout == null or _times == null or cell < 0 or cell >= layout.cells.size():
		return NEVER
	return _times.get_pixel(cell % layout.columns, cell / layout.columns).r


## When cell `cell` began to show the state it shows (Feel's clock at the `step` before the change was
## heard, or before the room was laid; `NEVER` for no such cell): an animated state plays from here.
## A restore re-tells a cell whose state this view showed otherwise (the cover area's
## `rebuild_derived`), so its animation plays again from the restore: look only.
func shown_at(cell: int) -> float:
	if layout == null or _times == null or cell < 0 or cell >= layout.cells.size():
		return NEVER
	return _times.get_pixel(cell % layout.columns, cell / layout.columns).g


## The frame of its kind's sheet a tuft of roll `rolled` draws `age` seconds after its cell began to
## show `state` (-1 for none), as the shader works it out: an animated state's tuft steps through its
## frames at its fps, once (holding the last) or looping from its own place (`CoverTufts.phase`).
static func frame_at(state: CoverState, rolled: int, age: float) -> int:
	var first: int = CoverTufts.frame(rolled, state.frames)
	var count: int = state.animation_frames
	if first < 0 or count <= 1:
		return first
	var stepped: int = floori(maxf(age, 0.0) * float(state.animation_fps))
	if state.animation_loops:
		return first + (stepped + roundi(CoverTufts.phase(rolled) * 255.0)) % count
	return first + mini(stepped, count - 1)


## How flat cell `cell`'s tufts lie at Feel's clock `now` before their state's bend scales it (0
## standing, 1 flat), as the shader works it out: flat while walked and its kind's `trample_hold`
## seconds after, springing back over its `trample_spring`; 0 for a cell of no cover.
func flatness(cell: int, now: float) -> float:
	if layout == null or cell < 0 or cell >= layout.cells.size() or layout.cells[cell] == 0:
		return 0.0
	var kind: CoverKind = layout.kinds[layout.cells[cell] - 1]
	return clampf(1.0 - (now - walked_at(cell) - kind.trample_hold) / maxf(kind.trample_spring, 0.001), 0.0, 1.0)


## The bodies handed to the shader by the last `step`, nearest the camera's middle first or not (in
## the order found), `body_count()` of them. Read only.
func bodies() -> PackedVector2Array:
	return _send[_sent]


func body_count() -> int:
	return maxi(_sent_count, 0)


## Once a frame, at Feel's clock `now`: the wind's time; the bodies of `table` (the actor table; null
## for none) nearest `focus` (the middle of the camera's picture; `Vector2.INF`: the first found)
## handed to the shader, and the cells they stand in walked; and the rows of each kind changed since
## the last frame handed to its batch; and the motes of the states that give some off, into `pool`
## (Feel's spectacle's; null: the particles are off) from the cells near `view` (the camera's
## picture; empty: everywhere); and the world's stirs handed to the batches by `hand_stirs` (taking a
## ShaderMaterial; the spectacle's `Stirs.hand_to`; none: not handed) whenever their `stirs_version`
## is not the one handed last.
func step(now: float, table: ActorsScript = null, focus: Vector2 = Vector2.INF, pool: MotesScript = null, view: Rect2 = Rect2(), stirs_version: int = -1, hand_stirs: Callable = Callable()) -> void:
	_bodies_due = false
	_find_bodies(table, focus)
	_draw_frame(now, pool, view, stirs_version, hand_stirs)


## `step` with the bodies another view found this frame (`found`, `count` of them: Feel's first
## room's `bodies()`, so a frame gathers them once for every room; `box` round them, its
## `found_box()`), the rest as `step`. A view switched off whose cells no body found reaches walks
## none and takes none of them: it takes them only when shown again (`_on_visibility_changed`), so
## it draws then as if it had taken them every frame.
func step_with(found: PackedVector2Array, count: int, now: float, pool: MotesScript = null, view: Rect2 = Rect2(), stirs_version: int = -1, hand_stirs: Callable = Callable(), box: Rect2 = EVERYWHERE) -> void:
	if not is_visible_in_tree() and not _reached_by(box):
		# Held as it is: the one the batches of the finding view hold, which it never writes.
		_due_found = found
		_due_count = count
		_bodies_due = true
		_draw_idle(now, pool, view, stirs_version, hand_stirs)
		return
	_bodies_due = false
	_take_found(found, count)
	_draw_frame(now, pool, view, stirs_version, hand_stirs)


## The bodies found by the last `step` (`step_with`'s, its own), at most BODIES.
func _take_found(found: PackedVector2Array, count: int) -> void:
	_near_count = mini(count, mini(found.size(), BODIES))
	for at in _near_count:
		_near_at[at] = found[at]


## The box round the bodies the last `step` found (NOWHERE with none), for `step_with`.
func found_box() -> Rect2:
	return _found_box


## True when a body in `box` (`found_box`'s) could walk one of the layout's cells (`_walk`'s test).
func _reached_by(box: Rect2) -> bool:
	if layout == null:
		return false
	var low: Vector2 = _walk_low()
	var high: Vector2 = _walk_high()
	return not (box.end.x < low.x or box.end.y < low.y or box.position.x > high.x or box.position.y > high.y)


## The corners of the box a body's position lies in when its footprint may touch the layout's cells.
func _walk_low() -> Vector2:
	return layout.origin - FOOT_REACH_HIGH - Vector2.ONE


func _walk_high() -> Vector2:
	return layout.origin + Vector2(float(layout.columns * CoverLayout.CELL), float(layout.rows * CoverLayout.CELL)) - FOOT_REACH_LOW + Vector2.ONE


## A frame switched off with no body in reach (`step_with`): the clock, the changed cells' times and
## the motes, as `_draw_frame`; nothing walked and the bodies left for when it is shown.
func _draw_idle(now: float, pool: MotesScript, view: Rect2, stirs_version: int, hand_stirs: Callable) -> void:
	_now = now
	if _times_dirty:
		_times_dirty = false
		_times_texture.update(_times)
	motes.give_off(now, pool, view)
	_held_stirs_version = stirs_version
	_held_hand_stirs = hand_stirs
	_held = true


## The frame's look once the bodies are found (`step`).
func _draw_frame(now: float, pool: MotesScript, view: Rect2, stirs_version: int, hand_stirs: Callable) -> void:
	_now = now
	if layout != null:
		_walk(now)
	if _times_dirty:
		_times_dirty = false
		_times_texture.update(_times)
	motes.give_off(now, pool, view)
	_held_stirs_version = stirs_version
	_held_hand_stirs = hand_stirs
	# The bodies found are taken every frame, shown or not: the other rooms' views and the mist
	# read them (`bodies`) from the first room's view, which may be switched off.
	_take_bodies()
	# A view switched off (a room nobody has entered, a place out of every view: unseen_rooms.gd)
	# draws nothing, so its batches are handed nothing a frame (the performance pass, 2026-11-21:
	# a biome's every room was told the clock and the bodies each frame); the view grid above is
	# kept walked, and the frame it is shown it is handed this frame's (`_on_visibility_changed`).
	if not is_visible_in_tree():
		_held = true
		return
	_hand_batches()


## The bodies found (`_near_at`) into the array handed over next, when they differ from the last.
func _take_bodies() -> void:
	if not _bodies_moved():
		return
	_sent = 1 - _sent
	# Taken out while it is written, so the write is in place (as `show_state`'s rows).
	var bodies_now: PackedVector2Array = _send[_sent]
	_send[_sent] = PackedVector2Array()
	for at in _near_count:
		bodies_now[at] = _near_at[at]
	_send[_sent] = bodies_now
	_sent_count = _near_count
	_bodies_held = true


## Hand the batches what changed: the clock, the stirs, the bodies found and the rows written
## (the frame's last `step`'s).
func _hand_batches() -> void:
	_held = false
	var stirred: bool = _held_hand_stirs.is_valid() and _held_stirs_version != _stirs_version
	if stirred:
		_stirs_version = _held_stirs_version
	var moved: bool = _bodies_held
	_bodies_held = false
	for index in _batches.size():
		var batch: MultiMeshInstance2D = _batches[index]
		if batch == null:
			continue
		var material := batch.material as ShaderMaterial
		material.set_shader_parameter(&"view_time", _now)
		if stirred:
			_held_hand_stirs.call(material)
		if moved:
			material.set_shader_parameter(&"bodies", _send[_sent])
			material.set_shader_parameter(&"body_count", _sent_count)
		if _dirty[index] != 0:
			_dirty[index] = 0
			batch.multimesh.buffer = _rows[index]


## Shown again after a frame or more off: handed what the frame's `step` held back, before it is
## drawn, so it draws as if it had been handed every frame.
func _on_visibility_changed() -> void:
	if _held and is_visible_in_tree():
		if _bodies_due:
			_bodies_due = false
			_take_found(_due_found, _due_count)
			_take_bodies()
		_hand_batches()


## The bodies of `table` nearest `focus`, at most `BODIES`, into `_near_at` (in the order found: by
## actor id, a nearer one taking the place of the farthest kept once they are full).
func _find_bodies(table: ActorsScript, focus: Vector2) -> void:
	_near_count = 0
	_found_box = NOWHERE
	if table == null:
		return
	var open: int = table.open_ids(_ids)
	var farthest: int = 0
	for n in open:
		var body := table.node_of(_ids[n]) as Node2D
		if body == null or not body.is_inside_tree():
			continue
		var at: Vector2 = body.global_position
		var far: float = at.distance_squared_to(focus) if focus.is_finite() else 0.0
		if _near_count < BODIES:
			_near_at[_near_count] = at
			_near_far[_near_count] = far
			if far > _near_far[farthest]:
				farthest = _near_count
			_near_count += 1
			continue
		if far >= _near_far[farthest]:
			continue
		_near_at[farthest] = at
		_near_far[farthest] = far
		for k in BODIES:
			if _near_far[k] > _near_far[farthest]:
				farthest = k
	if _near_count > 0:
		var low: Vector2 = _near_at[0]
		var high: Vector2 = low
		for at in range(1, _near_count):
			low = low.min(_near_at[at])
			high = high.max(_near_at[at])
		_found_box = Rect2(low, high - low)


## The covered cells under the bodies found (their `FOOTPRINT`), walked at `now`; the grid marked
## to be handed over when one was.
func _walk(now: float) -> void:
	# A body whose footprint lies wholly off this piece's cells walks none of them: passed by with
	# one test (a biome's every piece hears every body found; the performance pass, 2026-11-20). The
	# box is a pixel wider than FOOTPRINT's reach each way, so no foot on a cell is passed by.
	var low: Vector2 = _walk_low()
	var high: Vector2 = _walk_high()
	for at in _near_count:
		var body: Vector2 = _near_at[at]
		if body.x < low.x or body.y < low.y or body.x > high.x or body.y > high.y:
			continue
		for foot in FOOTPRINT:
			var cell: int = layout.cell_of(_near_at[at] + foot)
			if cell < 0 or layout.cells[cell] == 0:
				continue
			var x: int = cell % layout.columns
			var y: int = cell / layout.columns
			var times: Color = _times.get_pixel(x, y)
			times.r = now
			_times.set_pixel(x, y, times)
			_times_dirty = true


## True when the bodies found differ from the ones handed over last.
func _bodies_moved() -> bool:
	if _near_count != _sent_count:
		return true
	var held: PackedVector2Array = _send[_sent]
	for at in _near_count:
		if held[at] != _near_at[at]:
			return true
	return false


## Show cell `cell` in state `state` of its kind (its index in `CoverKind.states`): its tufts draw
## that state's frames with its sway and bend, or fold away when it draws none.
func show_state(cell: int, state: int) -> void:
	if layout == null or cell < 0 or cell >= layout.cells.size() or layout.cells[cell] == 0:
		return
	var index: int = layout.cells[cell] - 1
	var kind: CoverKind = layout.kinds[index]
	if state < 0 or state >= kind.states.size() or kind.states[state] == null:
		return
	motes.show(cell, state)
	if _first_slot[cell] < 0:
		return
	_shown[cell] = state
	var x: int = cell % layout.columns
	var y: int = cell / layout.columns
	var times: Color = _times.get_pixel(x, y)
	times.g = _now
	_times.set_pixel(x, y, times)
	_times_dirty = true
	# Taken out while it is written, so the write is in place (a copy-on-write array held twice
	# would be copied).
	var rows: PackedFloat32Array = _rows[index]
	_rows[index] = PackedFloat32Array()
	var slot_row: PackedInt32Array = _slot_row[index]
	var slot_rolls: PackedInt64Array = _slot_rolls[index]
	var first: int = _first_slot[cell]
	var look: CoverState = kind.states[state]
	for tuft in kind.tufts_per_cell:
		_write_look(rows, slot_row[first + tuft] * STRIDE, kind, look, slot_rolls[first + tuft])
	_rows[index] = rows
	_dirty[index] = 1


## The batch of the layout's kind `index`, its rows the tufts of its cells at rest; null for a kind
## with no sheet or no state.
func _lay_kind(index: int) -> MultiMeshInstance2D:
	var kind: CoverKind = layout.kinds[index]
	if kind.sheet == null or kind.states.is_empty() or kind.states[0] == null:
		return null
	var cells: int = 0
	for cell in layout.cells.size():
		if layout.cells[cell] == index + 1:
			cells += 1
	var per_cell: int = kind.tufts_per_cell
	var tufts: int = cells * per_cell
	var kind_key: int = CoverLayout.name_hash(kind.id)
	# The tufts in cell order (their slots), then the order they are drawn in, by their feet.
	var feet := PackedVector2Array()
	feet.resize(tufts)
	var rolls := PackedInt64Array()
	rolls.resize(tufts)
	var keys := PackedInt64Array()
	keys.resize(tufts)
	var slot: int = 0
	for cell in layout.cells.size():
		if layout.cells[cell] != index + 1:
			continue
		_first_slot[cell] = slot
		for tuft in per_cell:
			rolls[slot] = CoverTufts.roll(layout, kind_key, cell, tuft)
			feet[slot] = CoverTufts.foot(layout, cell, tuft, per_cell, rolls[slot])
			# Keyed by its foot in the room (a biome's room may lie anywhere in the world).
			keys[slot] = CoverTufts.draw_key(feet[slot] - layout.origin, slot)
			slot += 1
	keys.sort()
	var slot_row := PackedInt32Array()
	slot_row.resize(tufts)
	var rows := PackedFloat32Array()
	rows.resize(tufts * STRIDE)
	var rest: CoverState = kind.states[0]
	for row in tufts:
		var at_slot: int = CoverTufts.slot_of(keys[row])
		slot_row[at_slot] = row
		var foot: Vector2 = feet[at_slot]
		var at: int = row * STRIDE
		rows[at] = -1.0 if CoverTufts.mirrored(rolls[at_slot]) else 1.0
		rows[at + 1] = 0.0
		rows[at + 2] = 0.0
		rows[at + 3] = foot.x
		rows[at + 4] = 0.0
		rows[at + 5] = 1.0
		rows[at + 6] = 0.0
		rows[at + 7] = foot.y
		_write_look(rows, at, kind, rest, rolls[at_slot])
	_slot_row[index] = slot_row
	_slot_rolls[index] = rolls
	var row: int = tufts
	var batch: MultiMeshInstance2D = _batch()
	batch.name = "Cover_%s" % kind.id
	batch.texture = kind.sheet
	var material := batch.material as ShaderMaterial
	material.set_shader_parameter(&"frame_size", Vector2(kind.frame_size))
	material.set_shader_parameter(&"sheet_size", Vector2(kind.sheet.get_size()))
	material.set_shader_parameter(&"cell_times", _times_texture)
	# Its view grid's texels are cells from the grid's corner in the world (connected biomes CB3b).
	material.set_shader_parameter(&"cell_origin", layout.origin)
	material.set_shader_parameter(&"body_count", 0)
	material.set_shader_parameter(&"trample_hold", kind.trample_hold)
	material.set_shader_parameter(&"trample_spring", kind.trample_spring)
	batch.multimesh.instance_count = row
	if row > 0:
		batch.multimesh.buffer = rows
	# Its tufts stand only in its room, so a view that does not show the room never draws them (the
	# performance pass, 2026-11-20): its box is the room's, grown by a tuft's frame and its bend.
	batch.multimesh.custom_aabb = BatchesScript.box_of(Rect2(layout.origin, layout.size), float(maxi(kind.frame_size.x, kind.frame_size.y)) + BEND_PIXELS + BOX_PAD)
	batch.visible = true
	_rows[index] = rows
	return batch


## A batch to lay a kind in: a spare one, or a new one.
func _batch() -> MultiMeshInstance2D:
	if not _spare.is_empty():
		return _spare.pop_back()
	var multimesh: MultiMesh = BatchesScript.multimesh()
	multimesh.use_colors = true
	multimesh.use_custom_data = true
	multimesh.mesh = _quad()
	var batch := MultiMeshInstance2D.new()
	batch.multimesh = multimesh
	batch.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var material := ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter(&"bend_reach", BEND_REACH)
	material.set_shader_parameter(&"bend_pixels", BEND_PIXELS)
	material.set_shader_parameter(&"flatten", FLATTEN)
	batch.material = material
	add_child(batch)
	return batch


## Write a tuft's look in `state` of `kind` into the row at `at` of `rows`: its colour (its trampled
## frame; how many frames it plays, and how fast and whether they loop; shown, or not drawn, alpha 0,
## when the state draws no frame) and its custom data (its first frame, its sway, its bend, where its
## sway starts).
static func _write_look(rows: PackedFloat32Array, at: int, kind: CoverKind, state: CoverState, rolled: int) -> void:
	var frame: int = CoverTufts.frame(rolled, state.frames)
	var trampled: int = CoverTufts.frame(rolled, state.trampled_frames)
	rows[at + 8] = float(trampled + 1) / 255.0
	rows[at + 9] = float(clampi(state.animation_frames, 1, 255)) / 255.0
	rows[at + 10] = float(clampi(state.animation_fps, 1, 127) + (128 if state.animation_loops else 0)) / 255.0
	rows[at + 11] = 1.0 if frame >= 0 else 0.0
	rows[at + 12] = float(maxi(frame, 0)) / 255.0
	rows[at + 13] = clampf(kind.sway * state.sway / SWAY_CODE, 0.0, 1.0)
	rows[at + 14] = clampf(state.bend, 0.0, 1.0)
	rows[at + 15] = CoverTufts.phase(rolled)


## One quad: the shader places its corners (a vertex's UV is its corner).
static func _quad() -> ArrayMesh:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector2Array([Vector2.ZERO, Vector2.RIGHT, Vector2.ONE, Vector2.DOWN])
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2.ZERO, Vector2.RIGHT, Vector2.ONE, Vector2.DOWN])
	arrays[Mesh.ARRAY_COLOR] = PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
