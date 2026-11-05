extends "res://tests/support/suite.gd"
## Mote streams (`gameplay/feel/streams.gd`, a cue's `stream` part): a dash's speed streaks and its
## cards' particles, given off from its caster's anchor back along the way it goes, from its cue
## until its carrier ends. They were the projectile manager's (`follow_caster`) until 2026-11-05;
## these are its tests, moved with it.
##
## godot --headless --path . --script res://tests/gameplay/feel/test_streams.gd

const StreamsScript := preload("res://gameplay/feel/streams.gd")
const BirthsScript := preload("res://gameplay/feel/births.gd")
const ProjectilesScript := preload("res://core/projectiles/projectile_manager.gd")
const EventsScript := preload("res://core/events/events.gd")
const FeelScript := preload("res://gameplay/feel/feel.gd")
const FeelPresetScript := preload("res://gameplay/feel/presets/feel_preset.gd")
const RegistryScript := preload("res://core/registry/registry.gd")
const ActorSeats := preload("res://tests/support/actor_seats.gd")

const DT: float = 1.0 / 60.0

var mgr: ProjectilesScript
var streams: StreamsScript
var births: BirthsScript


func before_each() -> void:
	mgr = own(ProjectilesScript.new()) as ProjectilesScript
	streams = StreamsScript.new()
	births = BirthsScript.new(7)


func _part(kind: String, extra: Dictionary = {}) -> StreamsScript.Part:
	var part: Dictionary = {"part": &"stream", "kind": StringName(kind), "rate": 120.0, "side": 13.0, "ahead": 4.0}
	part.merge(extra, true)
	return StreamsScript.prepare(part)


## Steps the streams `frames` frames from Feel's clock `from`, moving caster `caster`'s anchor by
## `move` each frame; returns the births given off, each [x, y, back x, back y, kind, look, tag].
func _run(caster: int, from: float, frames: int, move: Vector2) -> Array:
	var out: Array = []
	for n in frames:
		mgr.set_anchor(caster, mgr.get_anchor(caster) + move)
		births.clear()
		streams.step(from + float(n + 1) * DT, mgr, births, true)
		for i in births.count:
			var b: int = i * BirthsScript.STRIDE
			out.append([births.rows[b + ProjectilesScript.SPARK_X], births.rows[b + ProjectilesScript.SPARK_Y],
				births.rows[b + ProjectilesScript.SPARK_BACK_X], births.rows[b + ProjectilesScript.SPARK_BACK_Y],
				int(births.rows[b + ProjectilesScript.SPARK_KIND]), int(births.rows[b + ProjectilesScript.SPARK_LOOK]),
				ProjectilesScript.spark_tag(births.rows, b)])
	return out


## A dash's speed streaks: its rate, beside its body, flung back along the way it goes, in its
## caster's colours (look 0), with its spell's tag.
func test_a_dash_path_stream_gives_off_streaks_back_along_its_way() -> void:
	mgr.set_anchor(0, Vector2(100.0, 100.0))
	var tag: int = SpellTag.make(0, 1, 2, 1)
	streams.start(_part("dash_path"), 0, tag, 0, 0, Color.WHITE, mgr.get_anchor(0), Vector2.RIGHT, 0.0)
	streams.step(0.0, mgr, births, true)
	var out: Array = _run(0, 0.0, 30, Vector2(4.0, 0.0))
	check(out.size() >= 45 and out.size() <= 75, "about 120 a second: %d in half a second" % out.size())
	var right: bool = true
	for b: Array in out:
		right = right and b[4] == ProjectilesScript.SPARK_STREAK and b[5] == 0 and b[6] == tag
		right = right and b[2] < -0.9 and absf(b[1] - 100.0) <= 6.5 + 0.01
	check(right, "streaks, beside its body, back along the dash (it goes right), its spell's tag")


## Its cards: each try a layer of its look kept at a shot's rate for it; fire's embers from its feet
## (`feet_layers`, `below`).
func test_a_spell_stream_gives_off_its_cards_and_embers_from_its_feet() -> void:
	mgr.set_anchor(1, Vector2(100.0, 200.0))
	var tag: int = SpellTag.make(1, 2, 3, 1)
	var look: int = ProjectilesScript.pack_look(PackedInt32Array([ProjectilesScript.LOOK_EMBERS]))
	streams.start(_part("spell", {"rate": 60.0, "side": 10.0, "ahead": 0.0, "feet_layers": [1, 2], "below": 8.0}), 1, tag, 1, look, Color.RED, mgr.get_anchor(1), Vector2.RIGHT, 0.0)
	streams.step(0.0, mgr, births, true)
	var out: Array = _run(1, 0.0, 120, Vector2(2.0, 0.0))
	# 120 tries at the embers' shot rate (0.45): about 54.
	check(out.size() >= 30 and out.size() <= 80, "at a shot's rate for embers: %d in 120 tries" % out.size())
	var feet: bool = true
	for b: Array in out:
		feet = feet and b[4] == ProjectilesScript.LOOK_EMBERS and b[5] == look and b[6] == tag
		feet = feet and b[1] > 205.0 and b[2] < -0.9
	check(feet, "embers, from its feet, back along the dash, with its look and tag")
	var plain := StreamsScript.new()
	plain.start(_part("spell"), 2, 0, 2, 0, Color.WHITE, Vector2(10.0, 10.0), Vector2.RIGHT, 0.0)
	mgr.set_anchor(2, Vector2(10.0, 10.0))
	births.clear()
	plain.step(0.0, mgr, births, true)
	plain.step(1.0, mgr, births, true)
	check_equal(births.count, 0, "a dash with no cards gives off no cards")


## Before it moves it goes the cue's way (a dash starts where it stands); then the way it moves.
func test_it_goes_the_cues_way_until_it_moves() -> void:
	mgr.set_anchor(0, Vector2(50.0, 50.0))
	streams.start(_part("dash_path"), 0, 0, 0, 0, Color.WHITE, mgr.get_anchor(0), Vector2.LEFT, 0.0)
	streams.step(0.0, mgr, births, true)
	var still: Array = _run(0, 0.0, 10, Vector2.ZERO)
	check(not still.is_empty() and still.all(func(b: Array) -> bool: return b[2] > 0.9), "standing, back against the cue's way (left)")
	var moving: Array = _run(0, 10.0 * DT, 10, Vector2(0.0, 5.0))
	check(not moving.is_empty() and moving.all(func(b: Array) -> bool: return b[3] < -0.9), "moving down, back up")


## It ends when its carrier ends (its caster and tag only), when its caster has no anchor, or after
## its seconds; a new one of the same part for the same caster takes over; none starts with no
## anchor.
func test_it_lasts_until_its_carrier_ends() -> void:
	var part: StreamsScript.Part = _part("dash_path", {"seconds": 1.0})
	streams.start(part, 0, 5, 0, 0, Color.WHITE, Vector2.INF, Vector2.RIGHT, 0.0)
	check_equal(streams.count, 0, "no anchor: no stream")
	mgr.set_anchor(0, Vector2(10.0, 10.0))
	streams.start(part, 0, 5, 0, 0, Color.WHITE, mgr.get_anchor(0), Vector2.RIGHT, 0.0)
	streams.start(part, 0, 6, 0, 0, Color.WHITE, mgr.get_anchor(0), Vector2.RIGHT, 0.0)
	check_equal(streams.count, 1, "a new dash takes over")
	streams.end(0, 5)
	check(streams.is_streaming(0), "the end of the dash before ends nothing")
	streams.end(0, 6)
	check(not streams.is_streaming(0), "its own carrier's end ends it")
	streams.start(part, 0, 7, 0, 0, Color.WHITE, mgr.get_anchor(0), Vector2.RIGHT, 0.0)
	streams.step(0.5, mgr, births, true)
	check(streams.is_streaming(0), "within its seconds")
	streams.step(1.0, mgr, births, true)
	check(not streams.is_streaming(0), "past them it ends")
	streams.start(part, 0, 8, 0, 0, Color.WHITE, mgr.get_anchor(0), Vector2.RIGHT, 1.0)
	mgr.clear_anchor(0)
	streams.step(1.1, mgr, births, true)
	check(not streams.is_streaming(0), "its caster's anchor gone, it ends")


## Nothing given off while motes are off, and no birth past the frame's most.
func test_it_gives_off_nothing_while_motes_are_off() -> void:
	mgr.set_anchor(0, Vector2(10.0, 10.0))
	streams.start(_part("dash_path", {"rate": 100000.0}), 0, 0, 0, 0, Color.WHITE, mgr.get_anchor(0), Vector2.RIGHT, 0.0)
	streams.step(0.0, mgr, births, false)
	streams.step(0.05, mgr, births, false)
	check_equal(births.count, 0, "motes off: none")
	streams.step(0.1, mgr, births, true)
	check_equal(births.count, BirthsScript.MOST, "a flood stops at the frame's most")


## A stream part's checks (`CueBase.problems`).
func test_a_stream_part_is_checked() -> void:
	var cue := CueBase.new()
	cue.id = &"test"
	var good: Array[Dictionary] = [{"part": &"stream", "kind": &"dash_path", "rate": 60.0}]
	cue.parts = good
	check(cue.problems().is_empty(), "a good one: %s" % [cue.problems()])
	for bad: Dictionary in [{"part": &"stream", "kind": &"dust"}, {"part": &"stream", "rate": 0.0}, {"part": &"stream", "side": -1.0},
			{"part": &"stream", "feet_layers": [0]}, {"part": &"stream", "below": 40.0}, {"part": &"stream", "count": 3}]:
		var parts: Array[Dictionary] = [bad]
		cue.parts = parts
		check(not cue.problems().is_empty(), "caught: %s" % [bad])


## Feel plays it: a dash's `form_shown` plays `dash_start`, whose stream parts follow the dasher
## until its `carrier_ended`, and give off its streaks into the motes meanwhile.
func test_a_dash_streams_from_its_start_to_its_landing() -> void:
	var bus := own(EventsScript.new()) as EventsScript
	var feel := own(FeelScript.new()) as FeelScript
	feel.events = bus
	feel.actors = own(ActorSeats.table(4)) as ActorSeats.ActorsScript
	feel.drive_engine = false
	feel.preset = FeelPresetScript.new()
	feel.preset.hit_sound = &""
	var registry := own(RegistryScript.new()) as RegistryScript
	registry.scan()
	feel.registry = registry
	root.add_child(feel)
	feel.projectiles = mgr
	mgr.set_anchor(2, Vector2(40.0, 40.0))
	var cue: CueBase = registry.get_resource(&"cues", &"dash_start") as CueBase
	var streams_in: int = cue.parts.filter(func(p: Dictionary) -> bool: return p.get("part") == &"stream").size()
	check_equal(streams_in, 2, "dash_start has its streaks and its cards")
	bus.form_shown.emit(2, &"dash", Vector2(40.0, 40.0), Vector2.RIGHT, 80.0, Color.WHITE, 0)
	check(feel.spectacle().streams.is_streaming(2), "its start starts its streams")
	var before: int = feel.motes().births
	for n in 20:
		mgr.set_anchor(2, Vector2(40.0 + 4.0 * float(n + 1), 40.0))
		feel.step(DT)
	check(feel.motes().births > before, "its streaks are thrown as motes (%d)" % (feel.motes().births - before))
	bus.carrier_ended.emit(2, &"dash", Vector2(120.0, 40.0), Vector2.RIGHT, 1.0, Color.WHITE, 0)
	check(not feel.spectacle().streams.is_streaming(2), "its landing ends them")
