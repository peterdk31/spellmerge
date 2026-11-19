extends RefCounted
## The enemies close to this machine's wizards, found once a drawn frame for the cameras (the owner,
## 2026-11-19: "the camera keeps close enemies in view, especially in boss fights"): the party camera
## (`party_camera.gd`) and each Voronoi view (`split_camera.gd`) frame these besides their wizards,
## as far as their widest zoom allows. View only: it reads the actor table and the grid's places and
## nothing in the simulation reads it.
##
## **The rule:** an enemy (an open actor of `TEAM_ENEMIES` whose body is in the tree) is close to a
## seat's wizard (its own body or the actor it drives) when it stands in the same place of the grid
## as that wizard (a room or a bridge; in a world with no places, as a single room or the hub, every
## point is the same place) and either the place is sealed (a fight under way there, a boss's among
## them: every foe of the room is framed) or it is within REACH of the wizard. A foe behind a wall in
## the next room is not framed, nor one across a big open room.
##
## Each foe found keeps its place in the world and a bit for every seat it is close to (`seats_of`),
## so a view frames only its own seats' foes (`box_for`). Nothing is allocated after it is made.

const ActorsScript := preload("res://core/actors/actors.gd")

## How near a wizard a foe must stand to be framed, outside a sealed fight (pixels).
const REACH: float = 384.0
## The most foes kept (the rest are left out: the camera can hold only so many anyway).
const MOST: int = 256

## The foes found: how many, where each stands and the seats it is close to (a bit a seat).
var count: int = 0
var at: PackedVector2Array = PackedVector2Array()
var seats_of: PackedInt32Array = PackedInt32Array()

var _ids: PackedInt32Array = PackedInt32Array()
## By seat: where its wizards stand (own body, driven actor; INF for none) and their places.
var _wizard_at: PackedVector2Array = PackedVector2Array()
var _wizard_place: PackedInt32Array = PackedInt32Array()


func _init() -> void:
	at.resize(MOST)
	seats_of.resize(MOST)
	_ids.resize(ActorsScript.ACTORS)
	_wizard_at.resize(ActorsScript.SEATS * 2)
	_wizard_place.resize(ActorsScript.SEATS * 2)


## Find the foes close to every seat's wizards in `table`, by the places of `grid` (null: one place).
func find(table: ActorsScript, grid: RoomGrid) -> void:
	count = 0
	if table == null:
		return
	var any: bool = false
	for seat in ActorsScript.SEATS:
		for driven in 2:
			var slot: int = seat * 2 + driven
			var id: int = table.actor_of_seat(seat) if driven == 1 else table.home_of_seat(seat)
			var body := table.node_of(id) as Node2D
			if body == null or not body.is_inside_tree() or table.team_of(id) == ActorsScript.TEAM_ENEMIES:
				_wizard_at[slot] = Vector2.INF
				continue
			_wizard_at[slot] = body.global_position
			_wizard_place[slot] = _place_at(grid, body.global_position)
			any = true
	if not any:
		return
	var open: int = table.open_ids(_ids)
	for i in open:
		var id: int = _ids[i]
		if table.team_of(id) != ActorsScript.TEAM_ENEMIES:
			continue
		var body := table.node_of(id) as Node2D
		if body == null or not body.is_inside_tree():
			continue
		var where: Vector2 = body.global_position
		var place: int = _place_at(grid, where)
		var sealed: bool = grid != null and place != RoomGrid.NO_PLACE and grid.is_sealed(place)
		var seats: int = 0
		for slot in ActorsScript.SEATS * 2:
			if not _wizard_at[slot].is_finite() or _wizard_place[slot] != place:
				continue
			if sealed or where.distance_squared_to(_wizard_at[slot]) <= REACH * REACH:
				seats |= 1 << (slot / 2)
		if seats == 0:
			continue
		at[count] = where
		seats_of[count] = seats
		count += 1
		if count == MOST:
			return


## `box` grown to hold every foe close to one of `seats` (a bit a seat; 0: every seat).
func box_for(seats: int, box: Rect2) -> Rect2:
	for i in count:
		if seats == 0 or seats_of[i] & seats != 0:
			box = box.expand(at[i])
	return box


static func _place_at(grid: RoomGrid, point: Vector2) -> int:
	if grid == null or grid.places() == 0:
		return RoomGrid.NO_PLACE
	return grid.place_at(point)
