class_name LeftPlayers
extends RefCounted
## What each seat's wizard held as its player left mid-run (the owner, 2026-11-19: "a player who
## leaves and rejoins mid-run keeps their whole inventory"): its cards, staffs and hands, potions and
## coins, as a player loadout (`Inventory.loadout`, core/sim/player_loadout.gd). Flow's state (it
## holds one, as it holds its `LockDoors`): kept as a seat leaves (`keep`), given back once as its
## wizard comes again in the same run (`take`: the seat then holds nothing here, so nothing is given
## twice), and forgotten with the run (`clear`). As a loadout says, a staff's mana is not kept: the
## wizard comes back with every pool full.
##
## The state is the party's bytes (`PartyLoadout.encode_into`), so a snapshot saves and restores it
## as it saves any other bytes; read back strictly (`PartyLoadout.decode_at`).

## The kept loadouts, as one `PartyLoadout`'s bytes (empty: nobody's).
var bytes: PackedByteArray = PackedByteArray()


## Seat `seat` left holding `loadout` (null: nothing kept for it).
func keep(seat: int, loadout: PlayerLoadout) -> void:
	var party: PartyLoadout = _party()
	party.put(seat, loadout)
	_store(party)


## What seat `seat`'s wizard left with (null: nothing kept), and it is kept no more.
func take(seat: int) -> PlayerLoadout:
	var party: PartyLoadout = _party()
	var kept: PlayerLoadout = party.of(seat)
	if kept != null:
		party.put(seat, null)
		_store(party)
	return kept


## True while seat `seat` has something kept.
func has(seat: int) -> bool:
	return _party().of(seat) != null


## Nobody's kept (a run's start and end).
func clear() -> void:
	bytes = PackedByteArray()


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
