extends RefCounted
## The oracle of a body's room (hit batch A0, docs/milestones/hit-batch.md, "A body's room, asked
## once a body"): a word-for-word copy of Combat's answer to `hit_room_asked` as it was on 2026-11-17
## (`Combat._on_hit_room_asked`), before A2 splits it into a body's room and a spell's damage. A2's
## new answers are held to it: at every entry, the same health, damage and charges, to the bit.
##
## It reads Combat's own members, as the copy it is; never change it to follow Combat. Its own test,
## tests/gameplay/combat/test_hit_room_oracle.gd, checks it against Combat's live answer until A2.
const CombatScript := preload("res://gameplay/combat/combat.gd")
const ActorsScript := preload("res://core/actors/actors.gd")


## Fill `room` (cleared first) as Combat answered `hit_room_asked(caster, target, tag, shot, room)`.
static func answer(combat: CombatScript, target: Node, tag: int, shot: int, room: HitRoom) -> void:
	if room == null:
		return
	room.clear()
	if target == null or not is_instance_valid(target) or combat.spells == null:
		return
	var row: int = combat._row_of_node(target)
	if row == ActorsScript.NONE or not combat._can_hurt(row):
		return
	if combat._body[row] == CombatScript.BODY_ACTOR and (combat._nodes[row] as Actor).health != null and (combat._nodes[row] as Actor).health.invincible:
		return
	var health: float = combat.health_of(target)
	if health < 0.0:
		return
	room.health = health
	var profile: HitProfile = combat.spells.hit_profile(tag, shot)
	if profile == null or profile.heal > 0:
		return
	var damage: float = profile.damage * combat._power_of(tag)
	var at: int = row * CombatScript.STATUS_COUNT
	if combat._status_left[at + CombatScript.ST_HEX] > 0.0:
		damage += damage * combat._status_power[at + CombatScript.ST_HEX] / 100.0
	if damage <= 0.0:
		return
	room.damage = damage
	var spell_before: int = combat._hit_spell
	combat._hit_spell = tag
	if combat._blocks(row):
		room.charges = combat._shield[row]
	combat._hit_spell = spell_before
