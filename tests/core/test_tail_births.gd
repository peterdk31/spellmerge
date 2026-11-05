extends "res://tests/support/suite.gd"
## Tails as motes (docs/milestones/spell-spectacle-2.md, S5 step 4; the owner, 2026-11-05: "the
## motes seem to spawn at fixed equal distances along its path ... if only the motes could look
## more like a tail"): with the tails off, the projectile manager's drawing lays every flying
## shot's tail as births of SPARK_TAIL, by distance (`_lay_tail`), and the cards' births are rolled
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
	mgr.set_tails_enabled(false)


## The births of the last draw of kind `kind`, as [x, y, core r, tag] each.
func _births_of(kind: int) -> Array[PackedFloat32Array]:
	var found: Array[PackedFloat32Array] = []
	var stride: int = ManagerScript.SPARK_BIRTH_STRIDE
	for n in mgr.spark_birth_count:
		var b: int = n * stride
		if int(mgr.spark_births[b + ManagerScript.SPARK_KIND]) == kind:
			found.append(PackedFloat32Array([mgr.spark_births[b + ManagerScript.SPARK_X], mgr.spark_births[b + ManagerScript.SPARK_Y],
					mgr.spark_births[b + ManagerScript.SPARK_CORE], float(ManagerScript.spark_tag(mgr.spark_births, b))]))
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


## No tail births with the tails on, or with the "Tail motes" switch at Off; on again, they come.
func test_tails_on_or_switched_off_lay_none() -> void:
	mgr.set_tail_motes(0)
	check(_stream(5, 0.5, ManagerScript.SPARK_TAIL).is_empty(), "Tail motes: Off lays none")
	mgr.set_tail_motes(2)
	check(not _stream(5, 0.5, ManagerScript.SPARK_TAIL).is_empty(), "B lays them")
	mgr.set_tails_enabled(true)
	check(_stream(5, 0.5, ManagerScript.SPARK_TAIL).is_empty(), "the tails on lay none")


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
