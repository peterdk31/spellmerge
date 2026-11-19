class_name LeftPlayers
extends RefCounted
## What each seat's wizard held as its player left mid-run (the owner, 2026-11-19: "a player who
## leaves and rejoins mid-run keeps their whole inventory"): its cards, staffs and hands, potions and
## coins, as a player loadout (`Inventory.loadout`, core/sim/player_loadout.gd). Flow's state (it
## holds one, as it holds its `LockDoors`): kept as a seat leaves (`keep`), given back once as its
## wizard comes again in the same run (`take`: the seat then holds nothing here, so nothing is given
## twice), and forgotten with the run (`clear`). A loadout carries no mana, so each staff's mana is
## kept beside it (the owner, 2026-11-19: "a rejoining wizard keeps the mana it left with"), by seat
## and staff number (`mana_of`, read before `take`; `Inventory.staff_mana`).
##
## The state is the party's bytes (`PartyLoadout.encode_into`), so a snapshot saves and restores it
## as it saves any other bytes; read back strictly (`PartyLoadout.decode_at`).

## The kept loadouts, as one `PartyLoadout`'s bytes (empty: nobody's).
var bytes: PackedByteArray = PackedByteArray()
## The kept staffs' mana: each entry's seat, its staff's number and the mana, by the same index.
var mana_seats: PackedInt32Array = PackedInt32Array()
var mana_numbers: PackedInt32Array = PackedInt32Array()
var mana_values: PackedFloat64Array = PackedFloat64Array()


## Seat `seat` left holding `loadout` (null: nothing kept for it), its staffs' mana `mana` (by staff
## number, `Inventory.staff_mana`; a staff not in the loadout is left out).
func keep(seat: int, loadout: PlayerLoadout, mana: Dictionary = {}) -> void:
	var party: PartyLoadout = _party()
	party.put(seat, loadout)
	_store(party)
	_forget_mana(seat)
	if loadout == null:
		return
	# In staff-number order, the same on every machine whatever order the dictionary came in.
	for number: int in loadout.staff_numbers():
		if mana.has(number):
			mana_seats.append(seat)
			mana_numbers.append(number)
			mana_values.append(float(mana[number]))


## The mana each staff kept for seat `seat` held as it left, by staff number (empty: none kept).
func mana_of(seat: int) -> Dictionary:
	var out: Dictionary = {}
	for at in mana_seats.size():
		if mana_seats[at] == seat:
			out[mana_numbers[at]] = mana_values[at]
	return out


## What seat `seat`'s wizard left with (null: nothing kept), and it is kept no more.
func take(seat: int) -> PlayerLoadout:
	var party: PartyLoadout = _party()
	var kept: PlayerLoadout = party.of(seat)
	if kept != null:
		party.put(seat, null)
		_store(party)
	_forget_mana(seat)
	return kept


## True while seat `seat` has something kept.
func has(seat: int) -> bool:
	return _party().of(seat) != null


## Nobody's kept (a run's start and end).
func clear() -> void:
	bytes = PackedByteArray()
	mana_seats = PackedInt32Array()
	mana_numbers = PackedInt32Array()
	mana_values = PackedFloat64Array()


func _forget_mana(seat: int) -> void:
	var at: int = mana_seats.size() - 1
	while at >= 0:
		if mana_seats[at] == seat:
			mana_seats.remove_at(at)
			mana_numbers.remove_at(at)
			mana_values.remove_at(at)
		at -= 1


func _party() -> PartyLoadout:
	var party := PartyLoadout.new()
	if bytes.is_empty():
		return party
	var problem: String = party.decode_at(bytes, 0)
	if problem != "":
		push_warning("LeftPlayers: what the players left with could not be read (%s), so nothing is kept." % problem)
		return PartyLoadout.new()
	return party


func _store(party: PartyLoadout) -> void:
	var out := PackedByteArray()
	if not party.is_empty():
		party.encode_into(out)
	bytes = out
