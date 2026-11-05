extends "res://tests/support/suite.gd"
## Tails as motes (docs/milestones/spell-spectacle-2.md, S5 step 4; the owner, 2026-11-05: "the
## motes seem to spawn at fixed equal distances along its path ... if only the motes could look
## more like a tail"): with the tails off, the projectile manager's drawing lays every flying
## shot's tail as births of its tail code (SPARK_TAIL + 0 to 2), by distance (`_lay_tail`), and the cards' births are rolled
## anywhere on the path drawn since the last frame. Stepped and drawn by hand, as a held stream
## of atoms: one shot a step from the same point at the same speed.

const ManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const EventsScript := preload("res://core/events/events.gd")
const ActorSeats := preload("res://tests/support/actor_seats.gd")
const ActorsScript := preload("res://core/actors/actors.gd")
const DT: float = 1.0 / 60.0
## An atom's speed, and what it flies in a step.
const SPEED: float = 1100.0
const STEP: float = SPEED * DT
const ORIGIN: Vector2 = Vector2(20.0, 100.0)

var mgr: ManagerScript


func before_each() -> void:
	mgr = own(ManagerScript.new()) as ManagerScript
	mgr.actors = own(ActorSeats.table()) as ActorsScript
	mgr.events = own(EventsScript.new()) as EventsScript
	mgr.set_bounds(Rect2(-100.0, -100.0, 1200.0, 600.0))
	mgr.set_cap(600)
	root.add_child(mgr)
	mgr.spark_motes = true


## The births of the last draw of kind `kind` (SPARK_TAIL: of any tail code), as [x, y, core r,
## tag, kind] each.
func _births_of(kind: int) -> Array[PackedFloat32Array]:
	var found: Array[PackedFloat32Array] = []
	var stride: int = ManagerScript.SPARK_BIRTH_STRIDE
	for n in mgr.spark_birth_count:
		var b: int = n * stride
		var laid: int = int(mgr.spark_births[b + ManagerScript.SPARK_KIND])
		if laid == kind or (kind == ManagerScript.SPARK_TAIL and ManagerScript.is_tail_code(laid)):
			found.append(PackedFloat32Array([mgr.spark_births[b + ManagerScript.SPARK_X], mgr.spark_births[b + ManagerScript.SPARK_Y],
					mgr.spark_births[b + ManagerScript.SPARK_CORE], float(ManagerScript.spark_tag(mgr.spark_births, b)), float(laid)]))
	return found


## Hold a stream for `steps` steps (a shot a step, its tag its number), drawn at `fraction`
## through each step; every birth of `kind` laid, in order.
func _stream(steps: int, fraction: float, kind: int, look: int = 0, core: Color = Color.WHITE) -> Array[PackedFloat32Array]:
	var laid: Array[PackedFloat32Array] = []
	for n in steps:
		var slot: int = mgr.spawn(0, ORIGIN, Vector2(SPEED, 0.0), 0.3, 1.5, ManagerScript.LAYER_ENEMY, 0, n + 1)
		mgr.set_look(slot, look)
		mgr.set_core(slot, core)
		mgr.step(DT)
		mgr.update_draw(fraction)
		laid.append_array(_births_of(kind))
	return laid


## Of `laid` births, the share of BINS bins of where each is in a step's flight (its distance from
## the stream's start, modulo STEP) that the emptiest bin holds, against an even spread.
func _evenness(laid: Array[PackedFloat32Array]) -> float:
	const BINS: int = 6
	var bins: PackedInt32Array = PackedInt32Array()
	bins.resize(BINS)
	for b in laid:
		bins[clampi(int(fposmod(b[0] - ORIGIN.x, STEP) / STEP * BINS), 0, BINS - 1)] += 1
	var least: int = bins[0]
	for count in bins:
		least = mini(least, count)
	return float(least) / (float(laid.size()) / BINS)


## The regression: a held stream's tail births do not line up at the same distances from the staff
## (each shot lays from a phase of its own, its gaps random), and they come about one every
## TAIL_SPACING pixels of every shot's path.
func test_a_held_stream_lays_its_tails_evenly() -> void:
	var laid: Array[PackedFloat32Array] = _stream(40, 0.5, ManagerScript.SPARK_TAIL)
	check(laid.size() > 500, "a stream lays its tails (%d births)" % laid.size())
	check(_evenness(laid) > 0.6, "anywhere along a step's flight, not at fixed distances (the emptiest bin %.2f of even)" % _evenness(laid))
	# Shot 10's tail: one every TAIL_SPACING on average, no gap wider than 1.5 x that (and a frame's
	# end), from where it started to where it was drawn last.
	var xs: PackedFloat32Array = PackedFloat32Array()
	for b in laid:
		if int(b[3]) == 10:
			xs.append(b[0])
	xs.sort()
	check(xs.size() > 50, "shot 10 lays its whole flight (%d)" % xs.size())
	var widest: float = 0.0
	for i in range(1, xs.size()):
		widest = maxf(widest, xs[i] - xs[i - 1])
	check(widest <= ManagerScript.TAIL_SPACING * 1.5 + 0.01, "no gap wider than 1.5 spacings (%.2f)" % widest)
	var mean: float = (xs[-1] - xs[0]) / float(xs.size() - 1)
	check(absf(mean - ManagerScript.TAIL_SPACING) < 0.25, "about one every TAIL_SPACING px (%.2f)" % mean)


## The cards' births too (the owner's lattice: each was rolled in the first part of the last step,
## so a held stream's lay at the same distances): anywhere on the path drawn since the last frame.
func test_the_cards_births_are_not_at_fixed_distances() -> void:
	var look: int = ManagerScript.pack_look(PackedInt32Array([ManagerScript.LOOK_EMBERS]))
	var laid: Array[PackedFloat32Array] = _stream(60, 0.5, ManagerScript.LOOK_EMBERS, look)
	check(laid.size() > 150, "the stream gives off its embers (%d)" % laid.size())
	check(_evenness(laid) > 0.5, "anywhere along a step's flight (the emptiest bin %.2f of even)" % _evenness(laid))


## Past `tail_births_cap` a frame, the frame lays the most, and the next frame's spacing widens by
## its ask over the most, so every tail thins (none is left whole while others are cut).
func test_a_busy_frame_thins_every_tail() -> void:
	mgr.tail_births_cap = 40
	var counts: PackedInt32Array = PackedInt32Array()
	for n in 12:
		var slot: int = mgr.spawn(0, ORIGIN + Vector2(0.0, float(n) * 4.0), Vector2(SPEED, 0.0), 0.3, 1.5)
		mgr.set_look(slot, 0)
	for n in 6:
		mgr.step(DT)
		mgr.update_draw(1.0)
		counts.append(_births_of(ManagerScript.SPARK_TAIL).size())
	check(counts[0] == 40, "the first frame lays the most (%d)" % counts[0])
	check(mgr.tail_demand > 40 and mgr.tail_spacing > ManagerScript.TAIL_SPACING * 2.0, "it asked for more, so the spacing widens (%d, %.1f)" % [mgr.tail_demand, mgr.tail_spacing])
	var shots: Dictionary = {}
	for b in _births_of(ManagerScript.SPARK_TAIL):
		shots[snappedf(b[1], 1.0)] = true
	check(shots.size() == 12, "a thinned frame lays some of every tail (%d of 12 shots)" % shots.size())


## Every flying shot lays its tail as motes while something takes the births (the owner's pick,
## 2026-11-05: tails are motes); while nothing does, none.
func test_tails_are_laid_while_something_takes_the_births() -> void:
	check(not _stream(5, 0.5, ManagerScript.SPARK_TAIL).is_empty(), "they come")
	mgr.spark_motes = false
	check(_stream(5, 0.5, ManagerScript.SPARK_TAIL).is_empty(), "nothing takes them: none")


## Each shot lays its whole tail in one tail code, picked by its sequence (the owner, 2026-11-05:
## "make the shots randomly pick one"), and a stream's shots use every code.
func test_each_shot_keeps_one_tail_kind_and_a_stream_uses_all() -> void:
	var laid: Array[PackedFloat32Array] = _stream(40, 0.5, ManagerScript.SPARK_TAIL)
	var code_of: Dictionary[int, int] = {}
	var codes: Dictionary[int, bool] = {}
	var one_each: bool = true
	for b in laid:
		var shot: int = int(b[3])
		var code: int = int(b[4])
		codes[code] = true
		if code_of.has(shot) and code_of[shot] != code:
			one_each = false
		code_of[shot] = code
	check(one_each, "every shot's births are of one code")
	check_equal(codes.size(), ManagerScript.TAIL_KINDS, "the stream's shots use all %d codes" % ManagerScript.TAIL_KINDS)
	for code: int in codes:
		check(ManagerScript.is_tail_code(code), "%d is a tail code" % code)


## A shot's code is its sequence's alone, and the codes come about evenly.
func test_the_tail_code_dice() -> void:
	check_equal(ManagerScript.tail_code(77), ManagerScript.tail_code(77), "the same shot, the same code")
	var counts: PackedInt32Array = PackedInt32Array()
	counts.resize(ManagerScript.TAIL_KINDS)
	for seq in 3000:
		var code: int = ManagerScript.tail_code(seq)
		check(ManagerScript.is_tail_code(code), "in range")
		counts[code - ManagerScript.SPARK_TAIL] += 1
	for n in counts:
		check(n > 850 and n < 1150, "about a third each (%s)" % counts)


## An infused shot's tail is TAIL_PLAYER_SHARE its caster's colours (a white core), as the tail
## shader's quarter was; a plain shot's is all its own.
func test_a_quarter_of_an_infused_tail_is_its_casters() -> void:
	var laid: Array[PackedFloat32Array] = _stream(20, 0.5, ManagerScript.SPARK_TAIL, 0, Color(0.9, 0.3, 0.2))
	var white: int = 0
	for b in laid:
		if b[2] > 0.99:
			white += 1
	var share: float = float(white) / float(laid.size())
	check(share > 0.17 and share < 0.33, "about a quarter in the caster's colours (%.2f)" % share)


## The dice are the same for the same pair and spread between 0 and 1.
func test_the_tail_dice() -> void:
	check(ManagerScript.tail_hash(12345, 6) == ManagerScript.tail_hash(12345, 6), "the same pair, the same number")
	var total: float = 0.0
	var inside: bool = true
	for n in 2000:
		var h: float = ManagerScript.tail_hash(n / 7, n)
		inside = inside and h >= 0.0 and h < 1.0
		total += h
	check(inside, "between 0 and 1")
	check(absf(total / 2000.0 - 0.5) < 0.03, "about 0.5 on average (%.3f)" % (total / 2000.0))
	check(ManagerScript.tail_hash(-1, -1) >= 0.0, "negative numbers too")


## The owner's Storm and Fireball (2026-11-05: "If i fire the fireball wand while the storm is still
## going, im not getting a tail on the fireball"): the births are shared by staff, not by shot
## (GROUPS), so a Fireball cast through a Storm of another staff keeps its whole tail, and the
## Storm's tails thin. On the Storm's own staff the same shot thins with it.
func test_a_lone_shot_keeps_its_tail_beside_a_crowd_of_another_staff() -> void:
	var own_staff: int = _lone_tail(SpellTag.make(0, 0, 0, 0))
	var path: float = 600.0 * DT * 6.0
	check(float(own_staff) >= 0.8 * path / ManagerScript.TAIL_SPACING, "its own staff: the whole tail (%d births over %.0f px)" % [own_staff, path])
	var storm_group: int = ManagerScript.group_of(0, SpellTag.make(0, 1, 0, 0))
	check(mgr._group_spacing[storm_group] > ManagerScript.TAIL_SPACING * 2.0, "the Storm's tails thin (spacing %.1f)" % mgr._group_spacing[storm_group])
	check(mgr.tail_births <= mgr.tail_births_cap, "and the frame keeps to the most (%d)" % mgr.tail_births)
	before_each()
	var storm_staff: int = _lone_tail(SpellTag.make(0, 1, 0, 0))
	check(storm_staff * 2 < own_staff, "on the Storm's staff it thins with it (%d, against %d)" % [storm_staff, own_staff])


## A Storm of 30 shots of staff 1 flies for five frames, then one shot tagged `tag` (the Fireball);
## the Fireball's tail births over the next six frames.
func _lone_tail(tag: int) -> int:
	mgr.tail_births_cap = 20
	var storm: int = SpellTag.make(0, 1, 0, 0)
	for n in 30:
		var slot: int = mgr.spawn(0, ORIGIN + Vector2(0.0, float(n) * 6.0), Vector2(300.0, 0.0), 3.0, 1.5, ManagerScript.LAYER_ENEMY, 0, storm)
		mgr.set_look(slot, 0)
	for n in 5:
		mgr.step(DT)
		mgr.update_draw(1.0)
	var lone: int = mgr.spawn(0, ORIGIN + Vector2(0.0, 300.0), Vector2(600.0, 0.0), 3.0, 1.5, ManagerScript.LAYER_ENEMY, 0, tag)
	mgr.set_look(lone, 0)
	var laid: int = 0
	for n in 7:
		mgr.step(DT)
		mgr.update_draw(1.0)
		if n == 0:
			continue
		for b in _births_of(ManagerScript.SPARK_TAIL):
			if b[1] > ORIGIN.y + 250.0:
				laid += 1
	return laid


## The cards' particles too: a lone ember shot of one staff keeps its embers whole beside a crowd of
## another staff's that is over the pool, which thins.
func test_a_lone_shot_keeps_its_particles_beside_a_crowd_of_another_staff() -> void:
	mgr.tail_births_cap = 0
	mgr.tailless_particle_cap = 60
	var drift: int = ManagerScript.pack_look(PackedInt32Array([ManagerScript.LOOK_DRIFT]))
	var embers: int = ManagerScript.pack_look(PackedInt32Array([ManagerScript.LOOK_EMBERS]))
	for n in 60:
		var slot: int = mgr.spawn(0, ORIGIN + Vector2(float(n % 10) * 8.0, float(n / 10) * 8.0), Vector2(1.0, 0.0), 5.0, 1.5, ManagerScript.LAYER_ENEMY, 0, SpellTag.make(0, 1, 0, 0))
		mgr.set_look(slot, drift)
	var fireball: int = SpellTag.make(0, 0, 0, 0)
	var lone: int = mgr.spawn(0, ORIGIN + Vector2(0.0, 300.0), Vector2(1.0, 0.0), 5.0, 1.5, ManagerScript.LAYER_ENEMY, 0, fireball)
	mgr.set_look(lone, embers)
	var laid: int = 0
	var crowd: int = 0
	for n in 120:
		mgr.step(DT)
		mgr.update_draw(1.0)
		laid += _births_of(ManagerScript.LOOK_EMBERS).size()
		crowd += _births_of(ManagerScript.LOOK_DRIFT).size()
	check(mgr.particle_share < 0.2, "the pool is over its count (%.2f)" % mgr.particle_share)
	check_equal(mgr._group_share[ManagerScript.group_of(0, fireball)], 1.0, "the lone shot's staff is given all it asks for")
	var whole: float = 120.0 * ManagerScript.SPARK_RATES[ManagerScript.LOOK_EMBERS]
	check(float(laid) > 0.7 * whole and float(laid) < 1.3 * whole, "its embers at their whole rate (%d of about %.0f)" % [laid, whole])
	var crowd_whole: float = 60.0 * 120.0 * ManagerScript.SPARK_RATES[ManagerScript.LOOK_DRIFT]
	check(float(crowd) < 0.2 * crowd_whole, "the crowd's thin (%d of %.0f)" % [crowd, crowd_whole])


## The fair level: asks under it are given whole, the rest share what is left alike; INF when all fit.
func test_the_fair_level() -> void:
	check_equal(ManagerScript.fair_level(PackedFloat32Array([1.0, 2.0, 3.0]), 10.0), INF, "all fit")
	check_equal(ManagerScript.fair_level(PackedFloat32Array([5.0, 300.0]), 40.0), 35.0, "a small ask whole, the big one the rest")
	check_equal(ManagerScript.fair_level(PackedFloat32Array([100.0, 100.0, 100.0, 100.0]), 40.0), 10.0, "even asks share alike")
	check_equal(ManagerScript.fair_level(PackedFloat32Array([2.0, 12.0, 50.0]), 30.0), 16.0, "levels past the small asks")
	check_equal(ManagerScript.fair_level(PackedFloat32Array(), 30.0), INF, "no asks")


## A shot's group is its caster's staff (a spell's tag), the caster's first for any other shot.
func test_a_shots_group_is_its_casters_staff() -> void:
	check_equal(ManagerScript.group_of(3, SpellTag.make(3, 2, 17, 5)), 3 * ManagerScript.GROUP_STAFFS + 2, "the caster's staff")
	check_equal(ManagerScript.group_of(3, SpellTag.make(3, 2, 40, 1)), ManagerScript.group_of(3, SpellTag.make(3, 2, 17, 5)), "every spell of one staff, payloads too")
	check(ManagerScript.group_of(3, SpellTag.make(3, 1, 0, 0)) != ManagerScript.group_of(3, SpellTag.make(3, 2, 0, 0)), "two staffs, two groups")
	check(ManagerScript.group_of(2, SpellTag.make(2, 1, 0, 0)) != ManagerScript.group_of(3, SpellTag.make(3, 1, 0, 0)), "two casters, two groups")
	check_equal(ManagerScript.group_of(5, 1000), 5 * ManagerScript.GROUP_STAFFS, "a shot of no spell: its caster's first")
	var slot: int = mgr.spawn(1, ORIGIN, Vector2(10.0, 0.0), 1.0, 1.5, ManagerScript.LAYER_ENEMY, 0, SpellTag.make(1, 3, 0, 0))
	var group: int = ManagerScript.group_of(1, SpellTag.make(1, 3, 0, 0))
	check_equal(mgr._group_count[group], 1, "a spawn joins its group")
	check(slot >= 0, "spawned")
	check_equal(mgr.remove_by_tag(SpellTag.make(1, 3, 0, 0)), 1, "ended")
	check_equal(mgr._group_count[group], 0, "and leaves it when it ends")
	check_equal(mgr._group_live, 0, "no group is left live")
