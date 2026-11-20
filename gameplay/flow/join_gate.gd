class_name JoinGate
extends RefCounted
## Who may join a run part way (the owner, 2026-11-19: "Rejoin only in the hub, or while no player
## has left a biome's start room. Once any player has left the start room, a new or returning player
## can't join until the run ends"): Flow's, as its doors are.
##
## - **Closed** (`closed`): in a biome once any room but the start room was entered (`RoomLife.ENTERED`;
##   a wizard stepping onto a bridge and back closes nothing). The hub, a row run's rooms and a biome
##   whose party is still in its start room are open: a joiner comes in as before (a returning one with
##   what it left with, `LeftPlayers`, #861).
## - **Held** (`held`, a bit a seat; state): a seat that joined while closed has no wizard; it is told
##   so (`join_held`, view only: its corner panel says why) and gets one with everyone else's as the
##   next world is made (the hub, a new run). A held seat that leaves is held no more. A run's end and
##   start clear it.

const SEATS: int = 4

const DERIVED: Array[StringName] = [&"events"]

var events: Node = null
## The seats that joined while the run could not be joined, a bit each.
var held: int = 0


## True when a joiner must wait for the run's end: a biome (`life` of its rooms) whose party has
## entered a room past its start room.
static func closed(life: RoomLife) -> bool:
	if life == null:
		return false
	for room in range(1, life.rooms()):
		if life.has(room, RoomLife.ENTERED):
			return true
	return false


func is_held(seat: int) -> bool:
	return seat >= 0 and seat < SEATS and held & (1 << seat) != 0


## Seat `seat` joined while closed: held, and told so.
func hold(seat: int) -> void:
	if seat < 0 or seat >= SEATS or is_held(seat):
		return
	held |= 1 << seat
	if events != null:
		events.join_held.emit(seat, true)


## Seat `seat` is held no more (it left, or got its wizard).
func release(seat: int) -> void:
	if not is_held(seat):
		return
	held &= ~(1 << seat)
	if events != null:
		events.join_held.emit(seat, false)


## Nobody held (a run's end or start), each said.
func clear() -> void:
	for seat in SEATS:
		release(seat)
	held = 0


## Every seat told as it stands (after a snapshot is restored).
func tell_all() -> void:
	if events == null:
		return
	for seat in SEATS:
		events.join_held.emit(seat, is_held(seat))
