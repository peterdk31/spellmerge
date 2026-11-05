extends "res://tests/support/suite.gd"
## The hits' share of the motes' rows (gameplay/feel/hit_shares.gd; the owner, 2026-11-05): a hit's
## motes are one spray, shared by staff, so a lone cast's impacts stay whole beside a Storm's, and a
## crowded staff's hits are a fair random subset that spray whole, never every hit a little.

const HitSharesScript := preload("res://gameplay/feel/hit_shares.gd")
const MotesScript := preload("res://gameplay/feel/mote.gd")
const EventsScript := preload("res://core/events/events.gd")
const FeelScript := preload("res://gameplay/feel/feel.gd")
const FeelPresetScript := preload("res://gameplay/feel/presets/feel_preset.gd")
const RegistryScript := preload("res://core/registry/registry.gd")
const ProjectilesScript := preload("res://core/projectiles/projectile_manager.gd")
const SpectacleScript := preload("res://gameplay/feel/spectacle.gd")
const ActorSeats := preload("res://tests/support/actor_seats.gd")
const ActorsScript := preload("res://core/actors/actors.gd")

const FIRE_LOOK: int = 1 << 0
const LIGHTNING_LOOK: int = 1 << 4
const STEP: float = 1.0 / 60.0
## The hit rows of the default frame (no tails): FRAME_ROWS past the moments'.
const BUDGET: int = MotesScript.FRAME_ROWS - MotesScript.MOMENT_ROWS

var registry: RegistryScript


func before_each() -> void:
	registry = own(RegistryScript.new()) as RegistryScript
	registry.scan()


func _feel() -> Array:
	var bus: EventsScript = own(EventsScript.new()) as EventsScript
	var feel: FeelScript = own(FeelScript.new()) as FeelScript
	var preset := FeelPresetScript.new()
	preset.hit_sound = &""
	feel.events = bus
	feel.registry = registry
	feel.actors = own(ActorSeats.table()) as ActorSeats.ActorsScript
	feel.projectiles = own(ProjectilesScript.new()) as ProjectilesScript
	feel.drive_engine = false
	feel.preset = preset
	root.add_child(feel)
	return [bus, feel]


## One frame of a crowd: `group`'s `hits` hits, each spraying `rows` when let through; returns the
## sprays let through.
func _crowd(shares: HitSharesScript, group: int, hits: int, rows: int) -> int:
	var sprays: int = 0
	for n in hits:
		if shares.opens(group):
			shares.spent(group, rows)
			sprays += 1
	return sprays


func test_a_lone_staff_sprays_whole_beside_a_crowd() -> void:
	var shares := HitSharesScript.new()
	var storm: int = ProjectilesScript.group_of(1, SpellTag.make(1, 0, 0, 0))
	var fireball: int = ProjectilesScript.group_of(0, SpellTag.make(0, 1, 0, 0))
	check(storm != fireball, "two staffs, two groups")
	_crowd(shares, storm, 300, 8)
	check(shares.opens(fireball), "a new staff's hit sprays")
	shares.spent(fireball, 12)
	shares.plan(BUDGET)
	check_equal(shares.chance_of(fireball), 1.0, "the lone staff's hits all spray")
	var level: float = float(BUDGET) - 12.0
	check(is_equal_approx(shares.chance_of(storm), level / (300.0 * 8.0)), "the Storm shares the rest: %f" % shares.chance_of(storm))
	var storm_rows: int = 0
	for frame in 60:
		storm_rows += _crowd(shares, storm, 300, 8) * 8
		check(shares.opens(fireball), "frame %d: the Fireball's hit sprays" % frame)
		shares.spent(fireball, 12)
		shares.plan(BUDGET)
	var mean: float = float(storm_rows) / 60.0
	check(mean > level * 0.8 and mean <= level + 8.0, "the Storm's sprays fill about its share a frame: %.1f of %.1f" % [mean, level])


func test_a_thinned_staff_never_runs_past_its_share() -> void:
	var shares := HitSharesScript.new()
	var storm: int = ProjectilesScript.group_of(3, SpellTag.make(3, 2, 0, 0))
	_crowd(shares, storm, 1000, 6)
	shares.plan(BUDGET)
	var level: float = float(BUDGET)
	for frame in 30:
		# Twice the hits it was planned for: its rolls let more through, its rows stop them.
		var rows: int = _crowd(shares, storm, 2000, 6) * 6
		check(float(rows) < level + 6.0, "frame %d: %d rows, at most its share" % [frame, rows])
		shares.plan(BUDGET)


func test_a_staff_with_room_is_never_thinned() -> void:
	var shares := HitSharesScript.new()
	for actor in 4:
		_crowd(shares, ProjectilesScript.group_of(actor, SpellTag.make(actor, 0, 0, 0)), 2, 8)
	shares.plan(BUDGET)
	for actor in 4:
		check_equal(shares.chance_of(ProjectilesScript.group_of(actor, SpellTag.make(actor, 0, 0, 0))), 1.0, "actor %d's few hits all spray" % actor)
	check_equal(shares.shared_out, 0, "none left out")


func test_the_groups_of_hits() -> void:
	var tag: int = SpellTag.make(5, 3, 7, 1)
	check_equal(SpectacleScript.hit_group(ActorsScript.NONE, tag), ProjectilesScript.group_of(5, tag), "a spell's hit: its caster's staff, from the tag")
	check_equal(SpectacleScript.hit_group(2, 0), ProjectilesScript.group_of(2, 0), "no spell: the caster's first staff")
	check_equal(SpectacleScript.hit_group(ActorsScript.NONE, 0), HitSharesScript.OTHER, "no one's: OTHER")


## The regression (the owner, 2026-11-05): a Storm of wall hits took every hit row of the frame
## first, so a Fireball's impact after them threw nothing. Its impact sprays whole beside the
## Storm now, every frame, and each of the Storm's impacts sprays whole or not at all.
func test_a_fireballs_impact_is_whole_in_a_storm() -> void:
	var made: Array = _feel()
	var bus: EventsScript = made[0]
	var feel: FeelScript = made[1]
	var motes: MotesScript = feel.motes()
	var shots: ProjectilesScript = feel.projectiles
	var storm_tag: int = SpellTag.make(1, 0, 0, 0)
	var fireball_tag: int = SpellTag.make(0, 1, 0, 0)
	# A Fireball's impact in a quiet frame: its whole spray.
	feel.step(STEP)
	shots.impact_look = FIRE_LOOK
	shots.impact_core = Color(1.0, 0.5, 0.2)
	shots.impact_tag = fireball_tag
	var row: int = motes.written
	bus.projectile_impact.emit(0, null, Vector2(300.0, 100.0), Vector2.RIGHT)
	var whole: int = motes.written - row
	check(whole > 0, "a quiet Fireball impact sprays: %d motes" % whole)
	check(whole <= MotesScript.FRESH_ROWS, "and fits the moments' rows a lone staff may take: %d" % whole)
	feel.step(STEP)
	# The Storm: 300 wall hits a frame, the Fireball's one after them.
	var storm_whole: int = -1
	var partial: int = 0
	for frame in 20:
		shots.impact_look = LIGHTNING_LOOK
		shots.impact_core = Color(1.0, 0.9, 0.3)
		shots.impact_tag = storm_tag
		for n in 300:
			row = motes.written
			bus.projectile_impact.emit(1, null, Vector2(float(n), 50.0), Vector2.LEFT)
			var wrote: int = motes.written - row
			if frame == 0 and n == 0:
				storm_whole = wrote
			elif wrote != 0 and wrote != storm_whole:
				partial += 1
		shots.impact_look = FIRE_LOOK
		shots.impact_core = Color(1.0, 0.5, 0.2)
		shots.impact_tag = fireball_tag
		row = motes.written
		bus.projectile_impact.emit(0, null, Vector2(300.0, 100.0), Vector2.RIGHT)
		if frame > 0:
			check_equal(motes.written - row, whole, "frame %d: the Fireball's impact sprays whole" % frame)
		feel.step(STEP)
	check(storm_whole > 0, "a Storm impact sprays")
	check(partial <= 20, "the Storm's impacts spray whole or not at all (at most the frame's last one cut short): %d cut" % partial)
	check(motes.hits.shared_out > 0, "the Storm was thinned by its share")


## A body hit is one hit: its damage's spray (the `hit` cue's sparks) follows its impact's roll.
func test_a_hits_damage_spray_follows_its_impact() -> void:
	var made: Array = _feel()
	var feel: FeelScript = made[1]
	var motes: MotesScript = feel.motes()
	var spectacle: SpectacleScript = feel.spectacle()
	var tag: int = SpellTag.make(0, 0, 0, 0)
	feel.step(STEP)
	spectacle.hold_hit(0, tag, false)
	var row: int = motes.written
	feel.play_cue(&"hit", -1, Vector2(50.0, 50.0), Vector2.RIGHT, 8.0)
	spectacle.end_hit()
	check_equal(motes.written - row, 0, "an impact that did not spray: its damage's sparks do not either")
	spectacle.hold_hit(0, tag, true)
	feel.play_cue(&"hit", -1, Vector2(50.0, 50.0), Vector2.RIGHT, 8.0)
	spectacle.end_hit()
	check(motes.written - row > 0, "one that did: they do")
	check_equal(motes.hits.shared_out, 0, "and neither was a hit of its own")
