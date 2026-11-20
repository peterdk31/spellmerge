class_name LeftPlayers
extends RefCounted
## What each seat's wizard held as its player left mid-run (the owner, 2026-11-19: "a player who
## leaves and rejoins mid-run keeps their whole inventory"): its cards, staffs and hands, potions and
## coins, as a player loadout (`Inventory.loadout`, core/sim/player_loadout.gd). Flow's state (it
## holds one, as it holds its `LockDoors`): kept as a seat leaves (`keep`), given back once as its
## wizard comes again in the same run (`take`: the seat then holds nothing here, so nothing is given
## twice), and forgotten with the run (`clear`). A loadout carries no mana, so each staff's mana is
## kept beside it (the owner, 2026-11-19: "a rejoining wizard keeps the mana it left with"), by seat
## and staff number (`mana_of`, read before `take`; `Inventory.staff_mana`), and so is what still
## recharged (the owner, 2026-11-20: the recharge travels with the relic, so a rejoining player keeps
## it mid-recharge; `recharges_of`, `Inventory.recharges`): as it left, the time away not counted (the
## relic was in no world then).
##
## The state is the party's bytes (`PartyLoadout.encode_into`), so a snapshot saves and restores it
## as it saves any other bytes; read back strictly (`PartyLoadout.decode_at`).

## The kept loadouts, as one `PartyLoadout`'s bytes (empty: nobody's).
var bytes: PackedByteArray = PackedByteArray()
## The kept staffs' mana: each entry's seat, its staff's number and the mana, by the same index.
var mana_seats: PackedInt32Array = PackedInt32Array()
var mana_numbers: PackedInt32Array = PackedInt32Array()
var mana_values: PackedFloat64Array = PackedFloat64Array()
## The kept recharges: each entry's seat, its item's bag and id, the seconds left and the whole
## cooldown, by the same index, in the order `Inventory.recharges` gave them.
var recharge_seats: PackedInt32Array = PackedInt32Array()
var recharge_bags: Array[StringName] = []
var recharge_ids: Array[StringName] = []
var recharge_left: PackedFloat64Array = PackedFloat64Array()
var recharge_whole: PackedFloat64Array = PackedFloat64Array()


## Seat `seat` left holding `loadout` (null: nothing kept for it), its staffs' mana `mana` (by staff
## number, `Inventory.staff_mana`; a staff not in the loadout is left out) and its items' recharges
## `recharges` (`Inventory.recharges`: [bag, id, left, whole] each).
func keep(seat: int, loadout: PlayerLoadout, mana: Dictionary = {}, recharges: Array = []) -> void:
	var party: PartyLoadout = _party()
	party.put(seat, loadout)
	_store(party)
	_forget_mana(seat)
	_forget_recharges(seat)
	if loadout == null:
		return
	for entry: Array in recharges:
		recharge_seats.append(seat)
		recharge_bags.append(StringName(entry[0]))
		recharge_ids.append(StringName(entry[1]))
		recharge_left.append(float(entry[2]))
		recharge_whole.append(float(entry[3]))
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


## What still recharged of what seat `seat` held as it left (`Inventory.set_recharges`' shape:
## [bag, id, left, whole] each; empty: none kept). Read before `take`.
func recharges_of(seat: int) -> Array:
	var out: Array = []
	for at in recharge_seats.size():
		if recharge_seats[at] == seat:
			out.append([recharge_bags[at], recharge_ids[at], recharge_left[at], recharge_whole[at]])
	return out


## What seat `seat`'s wizard left with (null: nothing kept), and it is kept no more.
func take(seat: int) -> PlayerLoadout:
	var party: PartyLoadout = _party()
	var kept: PlayerLoadout = party.of(seat)
	if kept != null:
		party.put(seat, null)
		_store(party)
	_forget_mana(seat)
	_forget_recharges(seat)
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
	recharge_seats = PackedInt32Array()
	recharge_bags = []
	recharge_ids = []
	recharge_left = PackedFloat64Array()
	recharge_whole = PackedFloat64Array()


func _forget_recharges(seat: int) -> void:
	var at: int = recharge_seats.size() - 1
	while at >= 0:
		if recharge_seats[at] == seat:
			recharge_seats.remove_at(at)
			recharge_bags.remove_at(at)
			recharge_ids.remove_at(at)
			recharge_left.remove_at(at)
			recharge_whole.remove_at(at)
		at -= 1


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
