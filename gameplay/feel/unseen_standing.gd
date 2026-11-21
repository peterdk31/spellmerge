extends RefCounted
## What stands where nobody has seen yet is not drawn (the owner, 2026-11-21, on #899: hide what
## stands in an unvisited room one by one, so no cover need be drawn over it): each body (a foe, a
## prop, a decoy: any open body of the actor table) whose feet are where the mask hides
## (`unseen_mask.gd`), and each room's floor mist (the spectacle's) whose room is. From the frame the
## room's reveal begins they are drawn again, as they stand, under its opening blocks. A body's
## shadow and its carried light go with it (both draw only a body drawn in its tree; Feel steps this
## before them). A player's own body (a seat's wizard, or a body a seat drives) is never hidden: a
## wizard walking in over a bridge's end inside the room's rectangle (still the bridge's place
## until it passes the mouth) stays drawn, never popping out for the frames before the reveal.
##
## View only: it sets `visible` (no member of any simulation script, and nothing in the game reads
## it) and reads the bodies' places. It shows again only what it hid, so a body another look hides
## (the intro's wizard) is left as that look has it; a body made again (a restore) is a new node,
## drawn until the next frame finds it. Nothing is made a frame.

const ActorsScript := preload("res://core/actors/actors.gd")
const UnseenMaskScript := preload("res://gameplay/feel/unseen_mask.gd")
const MistScript := preload("res://gameplay/feel/mist.gd")

## By actor id: the instance id of the body it hid (0: none).
var _hid: PackedInt64Array = PackedInt64Array()
## How many bodies it has hidden now.
var _hidden_count: int = 0
var _ids: PackedInt32Array = PackedInt32Array()
## The mask's changes and the mists' count the mists were switched for (-1: not yet).
var _mists_laid: int = -1
var _mists_count: int = -1


func _init() -> void:
	_hid.resize(ActorsScript.ACTORS)
	_ids.resize(ActorsScript.ACTORS)


## Once a frame: the bodies of `table` (null: none) and the mists `first` and `later` (each may be
## null or empty) hidden where `mask` hides, and shown again where it no longer does.
func step(mask: UnseenMaskScript, table: ActorsScript, first: MistScript, later: Array[MistScript]) -> void:
	if mask == null:
		return
	_step_bodies(mask, table)
	var mists: int = later.size() + (1 if first != null else 0)
	if mask.changes == _mists_laid and mists == _mists_count:
		return
	_mists_laid = mask.changes
	_mists_count = mists
	if first != null:
		_switch_mist(mask, first)
	for mist in later:
		_switch_mist(mask, mist)


func _step_bodies(mask: UnseenMaskScript, table: ActorsScript) -> void:
	if table == null or (mask.is_empty() and _hidden_count == 0):
		return
	var open: int = table.open_ids(_ids)
	for at in open:
		var id: int = _ids[at]
		var body := table.node_of(id) as Node2D
		if body == null or not body.is_inside_tree():
			continue
		if _hid[id] != 0 and _hid[id] != body.get_instance_id():
			# The body it hid went and the id is another's now (a restore made it again): not its own.
			_hid[id] = 0
			_hidden_count -= 1
		var mine: bool = _hid[id] != 0
		var hide: bool = not mask.is_empty() and not _is_players(table, id) and mask.hides(body.global_position)
		if hide and not mine:
			if body.visible:
				body.visible = false
				_hid[id] = body.get_instance_id()
				_hidden_count += 1
		elif mine and not hide:
			body.visible = true
			_hid[id] = 0
			_hidden_count -= 1
	if mask.is_empty() and _hidden_count != 0:
		# A body it hid that went (freed, or its id handed to another) is no longer its to show.
		_hid.fill(0)
		_hidden_count = 0


## Whether body `id` is a player's: a seat drives it, or it is a seat's own wizard.
static func _is_players(table: ActorsScript, id: int) -> bool:
	if table.seat_of(id) != ActorsScript.NONE:
		return true
	for seat in ActorsScript.SEATS:
		if table.home_of_seat(seat) == id:
			return true
	return false


func _switch_mist(mask: UnseenMaskScript, mist: MistScript) -> void:
	# By its room's corner (its place's own; the mist may be laid wider than its room).
	if is_instance_valid(mist):
		mist.set_unseen(mask.hides(mist.room_origin + Vector2.ONE))


## Whether it hides body `id` now (for tests).
func hides_body(id: int) -> bool:
	return id >= 0 and id < _hid.size() and _hid[id] != 0
