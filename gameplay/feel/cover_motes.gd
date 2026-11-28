extends RefCounted
## The motes ground cover gives off (ground cover GC8, docs/milestones/ground-cover.md, rule 6):
## burning grass's embers and smoke. A cover state names its streams (`CoverState.motes`, each a
## `MoteSource` read as if a cell were its node: its place round the cell's middle, its rate a
## cell's), and every cell Feel shows in that state gives them off, so a fire's motes follow the
## fire with no source of their own. Feel's cover (`cover.gd`) owns it: `lay` with each room's
## layout, `show` with each cell's change, `give_off` each frame.
##
## The cells of a state with motes are kept in a packed list a state (and each cell's place in it,
## so a change moves it at once); a frame gives off each stream's rate times its cells, from cells
## picked at random, at most `MOST_A_FRAME` motes in all, and none from a cell farther than
## `VIEW_MARGIN` from the view: a whole room burning costs what a screen of motes does. A frame
## allocates nothing; a cell's change may grow its state's list (a change, not a frame).
##
## A frame walks only the streams whose state some cell shows (`_live`, in the streams' order, kept
## by `show` as a state's list fills or empties): a biome's rooms at rest hold hundreds of streams
## and no cell giving off (perf plan F3, 2026-11-28: 476 streams in 28 rooms walked a frame, 0.56 ms).
## A stream whose list is empty at a frame owes nothing from then, as the walk set it (`_dropped`:
## one that empties and fills again between two frames, a fire moving on, keeps what it owed).
##
## A stream that cannot be given off (a problem in its data, a mask, which needs art a cell has not,
## a standing source, or a start or a stop, which a cell that changes state has no clock for) says
## so each time a room is laid, naming its kind and state, and the others go on. A box's `spacing`
## snaps round the cell's middle, not the world's grid.
##
## Pure view: its dice are its own and it runs on Feel's clock; nothing here is read by the game.

const MotesScript := preload("res://gameplay/feel/mote.gd")
const MotePlaces := preload("res://gameplay/feel/mote_places.gd")
const RampTableScript := preload("res://gameplay/feel/ramp_table.gd")

## The longest frame it gives off for (s): a frame after a stall gives off no more.
const LONGEST_FRAME: float = 0.1
## How far past the view a cell still gives off (px), as a world's source (`source_motes.gd`).
const VIEW_MARGIN: float = 64.0
## The most motes all the cover gives off in one frame (a whole room catching at once).
const MOST_A_FRAME: int = 48


## One stream of one state: its source, where round a cell it leaves from, its ramps' rows.
class Stream:
	var look: MoteSource = null
	var place: MotePlaces.Place = null
	var sources: PackedInt32Array = PackedInt32Array()
	## The group of cells it gives off from (`_cells`), and motes owed (a part of one).
	var group: int = 0
	var owed: float = 0.0
	var warned: bool = false
	## Left `_live` since the last frame (listed in `_dropped`).
	var dropped: bool = false
	var named: String = ""
	## Whether its kind is flat (the floor's), so the effects' row's `flat_share` scales its rate.
	var flat: bool = false


## The ramp table the streams' colours are rows of (the spectacle's; null: no motes).
var ramp_table: RampTableScript = null
## The share of a flat kind's streams given off (the effects' row, EffectsQuality.floor_motes: none at
## Low); tufted kinds' streams give off in full.
var flat_share: float = 1.0
## Motes given off, all told (for tests).
var given: int = 0

var _layout: CoverLayout = null
var _streams: Array[Stream] = []
## Each group's cells (a state of a kind with streams), and each cell's group and place in it (-1).
var _cells: Array[PackedInt32Array] = []
var _group_of_cell: PackedInt32Array = PackedInt32Array()
var _place_of_cell: PackedInt32Array = PackedInt32Array()
## The group of each kind's states: `_group_of_state[kind][state]` (-1: a state with no streams).
var _group_of_state: Array[PackedInt32Array] = []
## The streams whose group has cells, by their index in `_streams`, in that order (`_find_live`).
var _live: PackedInt32Array = PackedInt32Array()
## The streams that left `_live` since the last frame (`_settle_dropped`), each once.
var _dropped: PackedInt32Array = PackedInt32Array()
## Its dice's seed: the same every run, so what it draws is the same picture every time a run is
## played (a new generator starts at a random seed; screenshots compare runs byte for byte).
const DICE_SEED: int = 0xC0E1
var _rng := FeelDice.seeded(DICE_SEED)
var _last: float = -1.0


## The motes of `layout`'s cover (null: none), every cell at rest.
func lay(layout: CoverLayout) -> void:
	_layout = layout
	_streams.clear()
	_cells.clear()
	_group_of_state.clear()
	_live = PackedInt32Array()
	_dropped = PackedInt32Array()
	_group_of_cell = PackedInt32Array()
	_place_of_cell = PackedInt32Array()
	if layout == null:
		return
	for kind: CoverKind in layout.kinds:
		var groups := PackedInt32Array()
		for state: CoverState in kind.states:
			var group: int = -1
			if state != null:
				for look: MoteSource in state.motes:
					var named: String = "%s: %s" % [kind.id, state.state_id]
					var stream: Stream = _stream_of(look, named)
					if stream == null:
						continue
					if group < 0:
						group = _cells.size()
						_cells.append(PackedInt32Array())
					stream.group = group
					stream.flat = kind.look == CoverKind.Look.FLAT
					_streams.append(stream)
			groups.append(group)
		_group_of_state.append(groups)
	_group_of_cell.resize(layout.cells.size())
	_group_of_cell.fill(-1)
	_place_of_cell.resize(layout.cells.size())
	_place_of_cell.fill(-1)
	if _cells.is_empty():
		return
	for cell in layout.cells.size():
		if layout.cells[cell] != 0:
			show(cell, 0)


## Cell `cell` shows state `state` of its kind (its index in `CoverKind.states`) from now.
func show(cell: int, state: int) -> void:
	if _layout == null or _cells.is_empty() or cell < 0 or cell >= _group_of_cell.size() or _layout.cells[cell] == 0:
		return
	var states: PackedInt32Array = _group_of_state[_layout.cells[cell] - 1]
	var group: int = states[state] if state >= 0 and state < states.size() else -1
	var was: int = _group_of_cell[cell]
	if was == group:
		return
	if was >= 0:
		# The last cell of the group takes its place.
		var list: PackedInt32Array = _cells[was]
		_cells[was] = PackedInt32Array()
		var at: int = _place_of_cell[cell]
		var last: int = list[list.size() - 1]
		list[at] = last
		_place_of_cell[last] = at
		list.resize(list.size() - 1)
		_cells[was] = list
		if list.is_empty():
			_find_live()
	_group_of_cell[cell] = group
	_place_of_cell[cell] = -1
	if group >= 0:
		var list: PackedInt32Array = _cells[group]
		_cells[group] = PackedInt32Array()
		_place_of_cell[cell] = list.size()
		list.append(cell)
		_cells[group] = list
		if list.size() == 1:
			_find_live()


## The streams whose group has cells into `_live`, in the streams' order; the others listed in
## `_dropped`, to owe nothing at the next frame if still without a cell. Only when a group fills or
## empties.
func _find_live() -> void:
	_live.resize(0)
	for index in _streams.size():
		var stream: Stream = _streams[index]
		if not _cells[stream.group].is_empty():
			_live.append(index)
		elif not stream.dropped:
			stream.dropped = true
			_dropped.append(index)


## At a frame's start: the streams dropped since the last that still have no cell owe nothing (what
## the walk of every stream set them to while they had none).
func _settle_dropped() -> void:
	if _dropped.is_empty():
		return
	for index in _dropped:
		var stream: Stream = _streams[index]
		stream.dropped = false
		if _cells[stream.group].is_empty():
			stream.owed = 0.0
	_dropped.resize(0)


## How many cells give off the motes of state `state` of the layout's kind `kind_id` (for tests).
func cells_giving_off(kind_id: StringName, state: int) -> int:
	if _layout == null:
		return 0
	for index in _layout.kinds.size():
		if _layout.kinds[index].id == kind_id and index < _group_of_state.size():
			var states: PackedInt32Array = _group_of_state[index]
			var group: int = states[state] if state >= 0 and state < states.size() else -1
			return _cells[group].size() if group >= 0 else 0
	return 0


## Give off the motes owed since the last call, at Feel's clock `now`, into `pool` (null: none, the
## particles are off), from the cells within VIEW_MARGIN of `view` (an empty one: everywhere).
func give_off(now: float, pool: MotesScript, view: Rect2 = Rect2()) -> void:
	var dt: float = clampf(now - _last, 0.0, LONGEST_FRAME) if _last >= 0.0 else 0.0
	_last = now
	_settle_dropped()
	var near: Rect2 = view.grow(VIEW_MARGIN) if view.has_area() else Rect2()
	var budget: int = MOST_A_FRAME
	if near.has_area() and _layout != null and not near.intersects(_layout.rect(), true):
		_owe_far(dt, pool)
		return
	for index in _live:
		var stream: Stream = _streams[index]
		var cells: PackedInt32Array = _cells[stream.group]
		if pool == null or ramp_table == null or cells.is_empty():
			stream.owed = 0.0
			continue
		var k: int = pool.kind_index(stream.look.kind)
		if k < 0:
			if not stream.warned:
				stream.warned = true
				push_warning("Cover %s gives off nothing: '%s' is no mote kind (content/motes)." % [stream.named, stream.look.kind])
			continue
		if stream.sources.is_empty():
			for ramp: PackedColorArray in stream.look.ramps():
				stream.sources.append(ramp_table.source(ramp))
		# Owed no more than a frame's budget, so a long fire does not save motes up.
		stream.owed = minf(stream.owed + _rate_of(stream) * float(cells.size()) * dt, float(MOST_A_FRAME))
		while stream.owed >= 1.0 and budget > 0:
			stream.owed -= 1.0
			var cell: int = cells[_rng.randi() % cells.size()]
			var middle: Vector2 = _layout.cell_rect(cell).get_center()
			if near.has_area() and not near.has_point(middle):
				continue
			budget -= 1
			_throw(stream, k, middle, pool)


## A frame with every cell farther than VIEW_MARGIN from the view (`give_off`): no mote is given
## off and none is rolled, each stream keeping only the part of a mote it owes, as if every mote owed
## had been rolled and passed by (the performance pass, 2026-11-21: a biome's rooms out of sight
## rolled their fires' motes each frame). Only the dice's order differs, and they are the view's.
func _owe_far(dt: float, pool: MotesScript) -> void:
	for index in _live:
		var stream: Stream = _streams[index]
		var cells: PackedInt32Array = _cells[stream.group]
		if pool == null or ramp_table == null or cells.is_empty():
			stream.owed = 0.0
			continue
		var owed: float = minf(stream.owed + _rate_of(stream) * float(cells.size()) * dt, float(MOST_A_FRAME))
		stream.owed = owed - floorf(owed)


## A cell's rate of `stream` (a second), its flat kind's share taken.
func _rate_of(stream: Stream) -> float:
	return stream.look.rate * (flat_share if stream.flat else 1.0)


## One mote of kind `k` off `stream`, round the middle `middle` of a cell, into `pool`.
func _throw(stream: Stream, k: int, middle: Vector2, pool: MotesScript) -> void:
	var look: MoteSource = stream.look
	stream.place.pick(_rng, look)
	var ramp: int = stream.sources[_rng.randi() % stream.sources.size()]
	var height: float = look.height if look.height > 0.0 else -1.0
	var at: Vector2 = middle + stream.place.at
	var shown: Vector2 = at - Vector2(0.0, look.height) if look.height > 0.0 else at
	pool.throw_part(k, shown, stream.place.way, ramp, Color.WHITE, 1, look.reach, look.spread, 1.0, false, true, Vector2.ZERO, 1.0, 0, height)
	given += 1


## The stream of `look` (a state's, `named` its kind and state), its place read round a cell's
## middle; null, with a warning, for one that cannot be given off.
func _stream_of(look: MoteSource, named: String) -> Stream:
	if look == null:
		return null
	var problems: PackedStringArray = stream_problems(look)
	if not problems.is_empty():
		push_warning("Cover %s gives off nothing: %s." % [named, "; ".join(problems)])
		return null
	var stream := Stream.new()
	stream.look = look
	stream.named = named
	stream.place = MotePlaces.make(look.from)
	if not stream.place.read(look, null, Transform2D.IDENTITY, PackedVector2Array()):
		push_warning("Cover %s gives off nothing: it has nowhere to leave from (a line of no length)." % named)
		return null
	return stream


## What is wrong with `look` as a cover state's stream, one line each (empty when nothing): its own
## problems as a source with no art, and a mask or a standing source, which need art a cell has not.
static func stream_problems(look: MoteSource) -> PackedStringArray:
	# A mask's own problem (no art named) is said below, in a cell's words.
	var mask: bool = look.from == MoteSource.From.MASK
	var found: PackedStringArray = look.problems(mask)
	if mask:
		found.append("a cover state's motes cannot leave from a mask (a cell has no art)")
	if look.stand:
		found.append("a cover state's motes cannot stand")
	if look.start > 0.0 or look.stop > 0.0:
		found.append("a cover state's motes have no start or stop (they last while the cell is in the state)")
	return found
