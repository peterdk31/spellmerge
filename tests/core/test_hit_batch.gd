extends "res://tests/support/suite.gd"
## The hit batch (core/projectiles/hit_batch.gd, hit batch A1) on its own: entries by caster and spell
## on a target, a shot alone never merged, the body's room counted (charges first, then damage) until
## the pass has killed it, the spent and held lists, and a new pass forgetting the last one's tallies.
## The manager's use of it is held by test_merged_hits.gd and the recordings.

const ALONE: int = 1024

var batch: HitBatch
## The manager's shot flags, as `entry_of` reads them: slot 3's shot hits alone.
var flags: PackedInt32Array = PackedInt32Array()


func before_each() -> void:
	batch = HitBatch.new()
	flags = PackedInt32Array()
	flags.resize(8)
	flags[3] = ALONE
	batch.open(4, 8)


## A first hit of `who`'s spell `spell` on `t` by `shot`, its room told: `health`, `damage` a hit,
## `charges` of a barrier it meets.
func _first(t: int, who: int, spell: int, shot: int, health: float, damage: float, charges: int = 0) -> int:
	var entry: int = batch.add(t, 4, who, spell, shot, 100 + shot, Vector2(shot, 0.0), Vector2.RIGHT, &"bolt", 0, Color.WHITE, 0)
	batch.room.clear()
	batch.room.health = health
	batch.room.damage = damage
	batch.room.charges = charges
	batch.take_room(entry)
	return entry


func test_a_spells_hits_on_a_body_are_one_entry_and_each_caster_and_spell_its_own() -> void:
	var a: int = _first(1, 0, 11, 0, 100.0, 1.0)
	check_equal(batch.entry_of(1, 0, 11, false, flags, ALONE), a, "the same caster and spell adds to it")
	check_equal(batch.entry_of(1, 0, 12, false, flags, ALONE), -1, "another spell is a new one")
	check_equal(batch.entry_of(1, 1, 11, false, flags, ALONE), -1, "another caster is a new one")
	check_equal(batch.entry_of(2, 0, 11, false, flags, ALONE), -1, "another body is a new one")
	batch.count_hit(a)
	var b: int = _first(1, 0, 12, 1, 100.0, 1.0)
	check_equal(batch.entry_of(1, 0, 12, false, flags, ALONE), b, "the second entry on the body is found down its chain")
	check_equal([batch.entries, batch.count[a], batch.count[b], batch.target[b], batch.seq[b]], [2, 2, 1, 1, 101], "two entries, the first standing for two hits")


func test_a_shot_alone_is_never_merged() -> void:
	var alone: int = _first(1, 0, 11, 3, 100.0, 1.0)
	check_equal(batch.entry_of(1, 0, 11, false, flags, ALONE), -1, "no hit adds to a shot alone's entry")
	check_equal(batch.entry_of(1, 0, 11, true, flags, ALONE), -1, "nor does a shot alone add to any")
	var other: int = _first(1, 0, 11, 0, 100.0, 1.0)
	check(other != alone, "a shot of the same spell opens its own entry beside it")
	check_equal(batch.entry_of(1, 0, 11, false, flags, ALONE), other, "and the spell's later hits add to that one")


func test_a_body_is_killed_when_the_counted_damage_reaches_its_health() -> void:
	var a: int = _first(2, 0, 11, 0, 25.0, 10.0)
	check(batch.takes(2), "10 of 25")
	batch.count_hit(a)
	check(batch.takes(2), "20 of 25")
	batch.count_hit(a)
	check(not batch.takes(2), "30 of 25: the pass has killed it")
	check(batch.takes(1), "a body with no entry takes hits")
	check(batch.takes(9), "so does one past the tables")


func test_a_barrier_takes_hits_whole_before_damage_counts() -> void:
	var a: int = _first(2, 0, 11, 0, 15.0, 10.0, 2)
	batch.count_hit(a)
	check(batch.takes(2), "two charges took the first two hits")
	batch.count_hit(a)
	check(batch.takes(2), "the third dealt 10 of 15")
	batch.count_hit(a)
	check(not batch.takes(2), "the fourth killed it")


func test_a_spell_that_does_not_meet_the_barrier_counts_damage_at_once() -> void:
	_first(2, 0, 11, 0, 15.0, 10.0, 2)
	var spared: int = _first(2, 0, 12, 1, 15.0, 10.0, 0)
	check(batch.takes(2), "the first spell's hit took a charge")
	batch.count_hit(spared)
	check(not batch.takes(2), "the spared spell's two hits dealt 20 of 15")


func test_a_new_pass_forgets_the_last_ones_tallies() -> void:
	var a: int = _first(2, 0, 11, 0, 5.0, 10.0)
	check(not batch.takes(2), "killed in this pass")
	batch.empty()
	batch.open(4, 8)
	check(batch.takes(2), "a new pass: alive again")
	check_equal(batch.entry_of(2, 0, 11, false, flags, ALONE), -1, "and its entries are gone")
	check(a == 0 and batch.entries == 0, "the entries start again from 0")


func test_the_spent_and_held_lists_keep_their_order_and_drop_by_the_last() -> void:
	for shot in 3:
		batch.spend(shot, Vector2(shot * 10.0, 0.0))
		batch.hold(shot + 4)
	batch.drop_spent(0)
	batch.drop_held(1)
	check_equal([batch.spent_count(), batch.spent_slot(0), batch.spent_slot(1), batch.spent_at(0)], [2, 2, 1, Vector2(20.0, 0.0)], "the last spent shot took the dropped one's place")
	check_equal([batch.held_count(), batch.held_slot(0), batch.held_slot(1)], [2, 4, 6], "and the last held slot the dropped one's")
	batch.keep_end(11)
	batch.keep_end(12)
	check_equal([batch.ended_count(), batch.ended_tag(1)], [2, 12], "the ends kept in order")
	batch.empty()
	check_equal([batch.entries, batch.spent_count(), batch.held_count(), batch.ended_count()], [0, 0, 0, 0], "all emptied")


func test_the_tables_grow_past_their_first_size() -> void:
	for n in 70:
		_first(n % 4, n, 11, 0, 100.0, 1.0)
	check_equal(batch.entries, 70, "seventy entries")
	check_equal(batch.entry_of(1, 69, 11, false, flags, ALONE), 69, "the last found on its body's chain")
	batch.fit_targets(6)
	check(batch.takes(5), "a target added during the pass has a row")
