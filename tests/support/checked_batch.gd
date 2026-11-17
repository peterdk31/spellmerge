extends HitBatch
## A hit batch that holds itself to the oracle (hit batch A2, docs/milestones/hit-batch.md): at every
## entry's first hit it works out the body's room as the batch does (`take_room`, from Combat's two
## answers, each asked once a pass and again after an event), then asks the oracle
## (tests/support/hit_room_oracle.gd, Combat's one answer before A2) at that same moment, and keeps
## every entry where the two differ in health, damage or the barrier's charges.
##
## A test hands it to a manager in place of its own (`_hit_batch`), with the Combat that answers.
const Oracle := preload("res://tests/support/hit_room_oracle.gd")
const ManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const CombatScript := preload("res://gameplay/combat/combat.gd")

var combat: CombatScript
var manager: ManagerScript
## Entries checked, and each one that differed.
var checked: int = 0
## Rooms and spells' damage asked again within a pass, after an event moved the count.
var asked_again: int = 0
var differ: Array[String] = []
## How many entries the oracle answered with each shape: unknown, health only (no damage), damage,
## charges.
var shapes: Dictionary = {}
var _told: Oracle.Answer = Oracle.Answer.new()


func keep_room(t: int, sent: int) -> void:
	if _room_pass[t] == _pass:
		asked_again += 1
	super(t, sent)


func keep_damage(spell: int, sent: int) -> void:
	if not _spell_key.is_empty() and _spell_pass[_spell_find(spell)] == _pass:
		asked_again += 1
	super(spell, sent)


func take_room(entry: int, spell_damage: float) -> void:
	super(entry, spell_damage)
	var t: int = target[entry]
	Oracle.answer(combat, manager._targets[t], tag[entry], slot[entry], _told)
	checked += 1
	var shape: String = "unknown" if _told.health == INF else ("health only" if _told.damage <= 0.0 else ("charges" if _told.charges > 0 else "damage"))
	shapes[shape] = int(shapes.get(shape, 0)) + 1
	var meets: bool = _blocks[entry] != 0
	if _health[t] != _told.health or _damage[entry] != _told.damage or meets != (_told.charges > 0) or (meets and _charges[t] != _told.charges):
		differ.append("entry %d (tag %d): batch %s/%s/%s/%d, oracle %s/%s/%d" % [entry, tag[entry], _health[t], _damage[entry], meets, _charges[t], _told.health, _told.damage, _told.charges])
