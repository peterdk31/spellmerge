extends "res://tests/support/suite.gd"
## The staff swap (living staffs H4; a cue since S6 item 9, docs/milestones/spell-spectacle-2.md):
## `staff_shown` plays the cue `staff_swap` at the new staff's tip, along the aim, following the
## body, in the colour and cards of the new staff's first spell; a followed cue's flash moves with
## its body frame by frame exactly as the old poof's did, and ends when the body goes; the live cue
## shows something at StaffLook's swap of the body and face.
##
## godot --headless --path . --script res://tests/gameplay/feel/test_feel_poof.gd

const EventsScript := preload("res://core/events/events.gd")
const FeelScript := preload("res://gameplay/feel/feel.gd")
const FeelPresetScript := preload("res://gameplay/feel/presets/feel_preset.gd")
const RegistryScript := preload("res://core/registry/registry.gd")

const STEP: float = 1.0 / 60.0
const STAFF: int = 2


## The real cues, and one made in the test in place of a real one.
class CuesRegistry:
	extends RegistryScript
	var extra: CueBase = null

	func get_resource(folder: StringName, id: StringName) -> Resource:
		if extra != null and folder == &"cues" and id == extra.id:
			return extra
		return super(folder, id)


## The spell runtime as Feel asks it about a staff: its current build's first spell.
class FakeSpells:
	extends Node
	var spell: CompiledSpell = CompiledSpell.new()
	var asked: Array = []

	func current_tag(actor: int, slot: int, _node: int = 0) -> int:
		asked.append([actor, slot])
		return 77

	func profile(tag: int) -> CompiledSpell:
		return spell if tag == 77 else null


var _bus: EventsScript
var _feel: FeelScript
var _registry: CuesRegistry


func before_each() -> void:
	_bus = own(EventsScript.new()) as EventsScript
	_feel = own(FeelScript.new()) as FeelScript
	_feel.events = _bus
	_feel.drive_engine = false
	_feel.preset = FeelPresetScript.new()
	_registry = own(CuesRegistry.new()) as CuesRegistry
	_registry.scan()
	_feel.registry = _registry
	root.add_child(_feel)


func _staff() -> Actor:
	var body := own(Actor.new()) as Actor
	body.id = 5
	body.hand_offset = Vector2(0.0, -12.0)
	body.aim = Vector2.UP
	body.position = Vector2(50.0, 60.0)
	root.add_child(body)
	body.set_physics_process(false)
	return body


func _swap_cue(parts: Array[Dictionary]) -> void:
	var cue := CueBase.new()
	cue.id = FeelScript.STAFF_SWAP
	cue.parts = parts
	_registry.extra = cue
	(_feel.get("_cue_cache") as Dictionary).clear()


func test_a_staff_shown_plays_staff_swap_at_the_tip_following_the_body() -> void:
	_swap_cue([{"effect": &"burst", "zoom": 1, "seconds": 0.2}])
	var body := _staff()
	var tip: Vector2 = body.muzzle_position()
	_bus.staff_shown.emit(body.id, body, STAFF)
	var shown: Dictionary = _feel.effect_info(FeelScript.KIND_BURST)
	check(not shown.is_empty(), "its flash shows")
	if shown.is_empty():
		return
	check_equal(shown["at"], tip.round(), "at the new staff's tip")
	check_equal(shown["dir"], Vector2.UP, "along the aim")
	# Frame by frame, the body walking: the flash stays on the tip it was played at.
	var frames: int = 0
	while not _feel.effect_info(FeelScript.KIND_BURST).is_empty():
		body.position += Vector2(1.5, -0.5)
		_feel.step(STEP)
		frames += 1
		var info: Dictionary = _feel.effect_info(FeelScript.KIND_BURST)
		if not info.is_empty():
			check_equal(info["at"], (tip + Vector2(1.5, -0.5) * frames).round(), "on the tip at frame %d" % frames)
		if frames > 60:
			break
	check(absi(frames - roundi(0.2 / STEP)) <= 1, "for its seconds (%d frames)" % frames)


## The poof as the old code drew it (before S6 item 9) against the same look as a followed cue's
## flash: the same rows, frame by frame, while the body moves and turns.
func test_a_followed_flash_moves_as_the_old_poof_did() -> void:
	var body := _staff()
	var ramp: int = int(_feel.call("_ramp_of", -1))
	var offset: Vector2 = body.hand_offset + body.aim * 4.0
	var old: int = _feel.show_effect(FeelScript.KIND_PUFF, body.global_position + offset, body.aim, Color.WHITE, ramp, FeelScript.POOF, 2, FeelScript.POOF_SECONDS, 0.0, body)
	var offsets: PackedVector2Array = _feel.get("_effect_offset") as PackedVector2Array
	offsets[old] = offset
	_feel.set("_effect_offset", offsets)
	_swap_cue([{"effect": &"poof", "zoom": 2, "bare": true}])
	_feel.play_cue(FeelScript.STAFF_SWAP, -1, body.global_position + offset, body.aim, 0.0, Color.WHITE, 0, -1, -1, -1, 0, true, Color(0.0, 0.0, 0.0, 0.0), body)
	var new: int = (old + 1) % _feel.effect_slots
	for frame in roundi(FeelScript.POOF_SECONDS / STEP) + 2:
		for field: String in ["_effect_at", "_effect_dir", "_effect_core", "_effect_ramp", "_effect_zoom", "_effect_look", "_effect_seconds", "_effect_age", "_effect_offset", "_effect_kind"]:
			var values: Variant = _feel.get(field)
			check_equal(values[new], values[old], "%s at frame %d" % [field, frame])
		check_equal((_feel.get("_effect_follow") as Array)[new], (_feel.get("_effect_follow") as Array)[old], "following at frame %d" % frame)
		body.position += Vector2(2.0, 1.0)
		body.aim = body.aim.rotated(0.3)
		_feel.step(STEP)


func test_a_followed_flash_ends_when_its_body_goes() -> void:
	_swap_cue([{"effect": &"burst", "zoom": 1, "seconds": 1.0}])
	var body := _staff()
	_bus.staff_shown.emit(body.id, body, STAFF)
	check(not _feel.effect_info(FeelScript.KIND_BURST).is_empty(), "it shows")
	body.free()
	_feel.step(STEP)
	check(_feel.effect_info(FeelScript.KIND_BURST).is_empty(), "and goes with the body")


func test_it_is_in_the_new_staffs_colour_and_cards() -> void:
	_swap_cue([{"effect": &"burst", "zoom": 1}])
	var spells := own(FakeSpells.new()) as FakeSpells
	spells.spell.tint = Color(0.2, 0.6, 1.0)
	spells.spell.look = 0b10010
	_feel.spells = spells
	var body := _staff()
	_bus.staff_shown.emit(body.id, body, STAFF)
	check_equal(spells.asked, [[body.id, STAFF]], "asked for the build of the staff put on show")
	var shown: Dictionary = _feel.effect_info(FeelScript.KIND_BURST)
	check(not shown.is_empty() and shown["core"] == Color(0.2, 0.6, 1.0), "in its spell's colour")
	check(not shown.is_empty() and shown["look"] == 0b10010, "with its cards")


## The live cue (one of the looks the owner picks from: staff_swap, staff_swap_b, staff_swap_c)
## shows a flash at the moment StaffLook swaps the body and face (SWAP_AT of POOF_TIME), and each
## look is a sound cue.
func test_the_looks_show_at_the_swap() -> void:
	var swap: float = StaffLook.POOF_TIME * StaffLook.SWAP_AT
	for id: StringName in [&"staff_swap", &"staff_swap_b", &"staff_swap_c"]:
		var cue: CueBase = _feel.cue_of(id)
		check(cue != null, "%s exists" % id)
		if cue == null:
			continue
		check(cue.problems().is_empty(), "%s is a sound cue: %s" % [id, cue.problems()])
		# A flash or a light that lasts past the swap (motes fly free from the press).
		var at_swap: bool = false
		for part: Dictionary in cue.parts:
			var type: StringName = StringName(part.get("part", "effect"))
			if type != &"motes" and float(part.get("seconds", 0.2)) >= swap - STEP:
				at_swap = true
		check(at_swap, "%s shows something at the swap" % id)
