extends "res://tests/support/suite.gd"
## The beams between their hits walk their rays together (`CarrierBeam.walk_together`, #972: a beam
## split four times is 81 beams): a run plays the same, tick for tick, as each beam walking alone, in
## GDScript and with the native kernel. Real cards in the combo arena (Spells, the projectile
## manager, Combat), a staff cast again and again as its aim swings: split beams plain and with
## homing, pierce, bounce, spiral, growth, shield, storm's zaps, through a portal, fire on the floor's cover, hold, two players'
## beams side by side, blasts where they end, among imps that soon die (their rows leave the targets'
## grid mid-step), with walls and without; casts overlap, so beams of other ages hit and end between
## them. The state of Spells, the manager and Combat is hashed every tick (`SimHash.of`).
const ArenaScript := preload("res://tests/content/spells/combo_arena.gd")
const NativeScript := preload("res://core/native/native.gd")

const DT: float = 1.0 / 60.0
const TICKS: int = 100
## The builds: each player's cards, and the room (walls, floor).
const BUILDS: Array[Dictionary] = [
	{"cards": [["plus_two", "plus_two", "plus_two", "beam"]]},
	{"cards": [["fire", "plus_two", "plus_two", "beam"]], "floor": true},
	{"cards": [["homing", "plus_two", "plus_two", "beam"]], "walls": true},
	{"cards": [["pierce", "pierce", "plus_two", "plus_two", "beam"]], "walls": true},
	{"cards": [["bounce", "plus_two", "beam"]], "walls": true},
	{"cards": [["spiral", "plus_two", "plus_two", "beam"]]},
	{"cards": [["storm", "plus_two", "plus_two", "beam"]]},
	{"cards": [["frost", "growth", "plus_two", "beam"]], "walls": true},
	{"cards": [["hold", "plus_two", "plus_two", "beam"]], "walls": true},
	{"cards": [["plus_two", "plus_two", "beam"], ["fire", "plus_two", "beam"]], "floor": true, "walls": true},
	{"cards": [["blast", "plus_two", "plus_two", "beam"]]},
	{"cards": [["blast", "plus_two", "beam"], ["plus_two", "plus_two", "beam"]], "walls": true},
	{"cards": [["shield", "plus_two", "plus_two", "beam"], ["plus_two", "beam"]]},
	{"cards": [["plus_two", "plus_two", "beam"], ["portal"]], "walls": true},
]


## The hash of each tick of `build`, its beams walking together or not, natively or not; and the most
## beams on at once.
func _play(build: Dictionary, native: bool, together: bool) -> Array:
	var arena := ArenaScript.new(root)
	arena.projectiles.native = native
	arena.projectiles.set_cap(4096)
	var beams: CarrierBeam = CarrierBeam.of(arena.spells)
	beams.walk_together = together
	if build.get("floor", false):
		arena.use_floor()
	if build.get("walls", false):
		arena.add_wall(Rect2(150.0, -40.0, 20.0, 60.0))
		arena.add_wall(Rect2(60.0, 50.0, 80.0, 16.0))
	for n in 8:
		arena.add_imp(Vector2(70.0 + n * 22.0, -70.0 + n * 20.0), 1.0 + 2.0 * n)
	var cards: Array = build["cards"]
	for player in cards.size():
		arena.place_caster(player, Vector2(0.0, 30.0 * player))
		arena.install_cards(player, 0, cards[player])
	var hashes := PackedInt64Array()
	var most: int = 0
	for tick in TICKS:
		if tick % 7 == 0:
			for player in cards.size():
				arena.cast(player, 0, Vector2.from_angle(0.35 * sin(float(tick) * 0.07 + player)))
		arena.run(DT)
		most = maxi(most, beams.beam_count())
		hashes.append(SimHash.of(arena.spells) ^ (SimHash.of(arena.projectiles) * 31) ^ (SimHash.of(arena.combat) * 7))
	arena.free_all()
	return [hashes, most]


func test_beams_walking_together_play_as_each_alone() -> void:
	var native: bool = NativeScript.loaded()
	if not native:
		check(OS.get_environment("SPELLMERGE_NATIVE") != "required", "SPELLMERGE_NATIVE=required, but the native module is not loaded")
	for build: Dictionary in BUILDS:
		var alone: Array = _play(build, false, false)
		check(alone[1] >= 3, "%s: a fan of beams (%d on at once)" % [build["cards"], alone[1]])
		var ways: Array = [[false, true]]
		if native:
			ways.append([true, false])
			ways.append([true, true])
		for way: Array in ways:
			var played: Array = _play(build, way[0], way[1])
			var first: int = -1
			for tick in TICKS:
				if played[0][tick] != alone[0][tick]:
					first = tick
					break
			check(first < 0, "%s, %s, %s: plays as each beam alone in GDScript (first tick that differs: %d)" % [build["cards"], "native" if way[0] else "GDScript", "together" if way[1] else "alone", first])
