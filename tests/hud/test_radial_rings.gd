extends "res://tests/support/suite.gd"
## Tests for the radial builder's ring styles (owner, 2026-10-30; hud/builder/rings/): the zoom
## ring (held still it locks a fan where turning picks at a quarter of the speed; a sweep or
## letting go unlocks it; past the fan's edge it slides) and the kinds ring (one sector per kind;
## resting on it, Hold, or pushing further out, Depth, unwraps the kind's cards). Real wizards,
## registry and spell runtime, as in test_radial_builder.gd; every real card is found by the
## registry's own scan.
##
## godot --headless --path . --script res://tests/hud/test_radial_rings.gd

const EventsScript := preload("res://core/events/events.gd")
const InputManagerScript := preload("res://core/input/input_manager.gd")
const UIFocusScript := preload("res://core/ui_focus/ui_focus.gd")
const RegistryScript := preload("res://core/registry/registry.gd")
const SpellsScript := preload("res://core/spells/spells.gd")
const WizardFixture := preload("res://tests/gameplay/player/wizard_fixture.gd")
const HudScript := preload("res://hud/panels/panels.gd")
const RadialScript := preload("res://hud/builder/radial_builder.gd")
const PauseMenuScript := preload("res://hud/menus/pause/pause_menu.gd")
const RingZoomScript := preload("res://hud/builder/rings/ring_zoom.gd")
const RingKindsScript := preload("res://hud/builder/rings/ring_kinds.gd")
## Loaded when needed, not preloaded: this scene is also the "Hud" autoload.
const HUD_SCENE_PATH: String = "res://hud/panels/panels.tscn"
const NO_SAVE: String = "user://test_no_save.cfg"

const STEP: float = 0.0625
const START: Array = [[&"dash"], [&"fire", &"bolt"], [], []]

var _registry: RegistryScript
var _bus: EventsScript
var _input: InputManagerScript
var _focus: UIFocusScript
var _spells: SpellsScript
var _hud: HudScript
var _world: WizardFixture
var _players: Array[Actor] = []
var _rumbles: Array = []


func before_each() -> void:
	_world = WizardFixture.new(root)
	_registry = own(_world.registry) as RegistryScript
	_bus = own(_world.bus) as EventsScript
	_input = own(_world.input) as InputManagerScript
	_input.vibrator = func(device: int, weak: float, strong: float, seconds: float) -> void: _rumbles.append([device, weak, strong, seconds])
	_focus = own(UIFocusScript.new()) as UIFocusScript
	_focus.input = _input
	_focus.events = _bus
	_focus._ready()
	own(_world.projectiles)
	_spells = own(_world.spells) as SpellsScript
	own(_world.combat)
	own(_world.table)
	_players.clear()
	_rumbles.clear()
	_hud = own((load(HUD_SCENE_PATH) as PackedScene).instantiate()) as HudScript
	_hud.events = _bus
	_hud.save = SaveFile.new(NO_SAVE)
	_hud.ui_focus = _focus
	_hud.input = _input
	_hud.spells = _spells
	root.add_child(_hud)


## One player with a virtual device and a wizard, in a room, with the radial on ring `ring`; open.
func _open(ring: PauseMenuScript.Ring) -> RadialScript:
	_hud.call("_on_builder_options_changed", true, ring, true)
	_input.add_virtual_device(0)
	var player := own(_world.wizard(0, Vector2.ZERO, START, _registry.get_resource(&"wizard", &"dev") as StaffBase)) as Actor
	_players.append(player)
	_bus.player_joined.emit(0)
	_bus.room_entered.emit(&"test_room")
	_input.send_virtual(0, &"back", 1.0)
	_input.send_virtual(0, &"back", 0.0)
	_frame()
	var radial: RadialScript = _hud.get_radial(0)
	check(radial.is_open(), "B opens the radial")
	return radial


func _frame() -> void:
	_hud.poll()
	_focus.poll()
	_hud.get_radial(0).step(STEP)
	for player in _players:
		player.step(STEP)


func _frames(count: int) -> void:
	for _at in count:
		_frame()


## Push the right stick toward `direction` so that menu_tilt reads `tilt` (0 to 1).
func _push(direction: Vector2, tilt: float) -> void:
	_input.send_virtual_aim(0, direction.normalized() * (InputManagerScript.DEADZONE + tilt * (1.0 - InputManagerScript.DEADZONE)))


func _let_go() -> void:
	_input.send_virtual_aim(0, Vector2.ZERO)
	_frame()


func _real_cards() -> Array[StringName]:
	var cards: Array[StringName] = []
	for id: StringName in _registry.get_ids(&"spells"):
		if _registry.get_resource(&"spells", id) is SpellComponent:
			cards.append(id)
	check(cards.size() >= 20, "the registry found the cards (%d)" % cards.size())
	return cards


# --- Zoom ---------------------------------------------------------------------------------

## Two neighbours of one kind on the ring, after the first card: [a, b].
func _neighbours(radial: RadialScript) -> Array[StringName]:
	var entries: Array[Dictionary] = radial.ring_entries()
	check_equal(entries[2]["kind"], entries[1]["kind"], "two neighbours of one kind")
	return [entries[1]["id"], entries[2]["id"]]


func test_zoom_locks_when_held_still_and_turning_picks_slower() -> void:
	var radial: RadialScript = _open(PauseMenuScript.Ring.ZOOM)
	var zoom: RingZoomScript = radial.ring_picker as RingZoomScript
	var pair: Array[StringName] = _neighbours(radial)
	var at: float = RadialScript.angle_of(radial.direction_to(pair[0]))
	var width: float = angle_difference(at, RadialScript.angle_of(radial.direction_to(pair[1])))
	_push(radial.direction_to(pair[0]), 1.0)
	_frame()
	check_equal(radial.pointed_id(), pair[0], "the plain ring picks first")
	check(not zoom.is_locked(), "not locked at once")
	_frame()
	check(zoom.is_locked(), "locked after %.2f s held still" % RingZoomScript.LOCK_TIME)
	check_equal(radial.pointed_id(), pair[0], "locking keeps the card")
	# One card further on the ring takes 1 / GAIN times the turn.
	_push(RadialScript.direction_of(at + width * 0.5), 1.0)
	_frame()
	check_equal(radial.pointed_id(), pair[0], "half a card's turn stays on it in the fan")
	_push(RadialScript.direction_of(at + width / RingZoomScript.GAIN), 1.0)
	_frame()
	check(zoom.is_locked(), "a steady turn keeps the lock")
	check_equal(radial.pointed_id(), pair[1], "a card's width over the gain picks the neighbour")


func test_zoom_unlocks_on_a_sweep_and_on_letting_go() -> void:
	var radial: RadialScript = _open(PauseMenuScript.Ring.ZOOM)
	var zoom: RingZoomScript = radial.ring_picker as RingZoomScript
	var nova: Vector2 = radial.direction_to(&"nova")
	_push(nova, 1.0)
	_frames(3)
	check(zoom.is_locked(), "locked on the nova")
	var far: Vector2 = nova.rotated(2.0)
	_push(far, 1.0)
	_frame()
	check(not zoom.is_locked(), "a fast sweep unlocks")
	check(radial.pointed_id() != &"nova", "and the plain ring picks where the stick is now")
	_frames(3)
	check(zoom.is_locked(), "held still again, it locks again")
	_let_go()
	check(not zoom.is_locked(), "letting go unlocks")
	check_equal(radial.pointed_id(), &"", "and drops the card")
	_push(nova, 0.6)
	_frames(4)
	check(not zoom.is_locked(), "a half push never locks")


func test_zoom_slides_past_the_fan_edge() -> void:
	var radial: RadialScript = _open(PauseMenuScript.Ring.ZOOM)
	var zoom: RingZoomScript = radial.ring_picker as RingZoomScript
	var start: float = RadialScript.angle_of(radial.direction_to(&"nova"))
	_push(RadialScript.direction_of(start), 1.0)
	_frames(3)
	check(zoom.is_locked(), "locked")
	# Turn steadily to past the fan's edge (slow enough to keep the lock).
	var turned: float = 0.0
	while turned < RingZoomScript.FAN_HALF + 0.2:
		turned += 0.25
		_push(RadialScript.direction_of(start + turned), 1.0)
		_frame()
	check(zoom.is_locked(), "a steady turn keeps the lock")
	var edge: StringName = radial.pointed_id()
	check(edge != &"nova", "the fan's edge is further on")
	_frames(8)
	check(radial.pointed_id() != edge, "held past the edge, the fan slides on (%s, then %s)" % [edge, radial.pointed_id()])


func test_zoom_picks_every_real_card() -> void:
	var radial: RadialScript = _open(PauseMenuScript.Ring.ZOOM)
	var zoom: RingZoomScript = radial.ring_picker as RingZoomScript
	for id in _real_cards():
		_let_go()
		_push(radial.direction_to(id), 1.0)
		_frames(3)
		check(zoom.is_locked(), "%s: locked" % id)
		check_equal(radial.pointed_id(), id, "%s: picked through the fan" % id)


# --- Kinds --------------------------------------------------------------------------------

func test_kinds_hold_opens_a_kind_after_resting_on_it() -> void:
	var radial: RadialScript = _open(PauseMenuScript.Ring.KINDS_HOLD)
	var kinds: RingKindsScript = radial.ring_picker as RingKindsScript
	_push(kinds.kind_direction(radial, &"modifier"), 1.0)
	_frames(3)
	check_equal(kinds.pointed_kind(radial), &"modifier", "the stick points at the modifiers")
	check_equal(kinds.open_kind(radial), &"", "not open before %.2f s" % RingKindsScript.HOLD_TIME)
	check_equal(radial.pointed_id(), &"", "and no card yet")
	_frame()
	check_equal(kinds.open_kind(radial), &"modifier", "resting opens them")
	check_equal(_spells.component_kind(radial.pointed_id()), &"modifier", "the stick picks a modifier at once")
	_push(kinds.kind_direction(radial, &"modifier"), 0.2)
	_frame()
	check_equal(kinds.open_kind(radial), &"modifier", "easing off keeps the kind (Hold)")
	_let_go()
	check_equal(kinds.open_kind(radial), &"", "letting go goes back to the kinds")
	check_equal(radial.pointed_id(), &"", "and drops the card")
	_push(kinds.kind_direction(radial, &"modifier"), 0.3)
	_frames(6)
	check_equal(kinds.open_kind(radial), &"", "under half a push never opens")


func test_kinds_hold_picks_every_real_card() -> void:
	var radial: RadialScript = _open(PauseMenuScript.Ring.KINDS_HOLD)
	var kinds: RingKindsScript = radial.ring_picker as RingKindsScript
	for id in _real_cards():
		_let_go()
		_push(kinds.kind_direction(radial, _spells.component_kind(id)), 1.0)
		_frames(4)
		_push(kinds.card_direction(radial, id), 1.0)
		_frame()
		check_equal(radial.pointed_id(), id, "%s: picked in its kind" % id)


func test_kinds_depth_points_with_half_a_push_and_opens_further_out() -> void:
	var radial: RadialScript = _open(PauseMenuScript.Ring.KINDS_DEPTH)
	var kinds: RingKindsScript = radial.ring_picker as RingKindsScript
	var way: Vector2 = kinds.kind_direction(radial, &"element")
	_push(way, 0.45)
	_frames(6)
	check_equal(kinds.pointed_kind(radial), &"element", "half a push points at the elements")
	check_equal(kinds.open_kind(radial), &"", "without opening them, however long")
	_push(way, 0.8)
	_frame()
	check_equal(kinds.open_kind(radial), &"element", "pushing further opens them")
	check_equal(_spells.component_kind(radial.pointed_id()), &"element", "and picks an element")
	_push(way, 0.6)
	_frame()
	check_equal(kinds.open_kind(radial), &"element", "between the two marks it stays open")
	_push(way, 0.45)
	_frame()
	check_equal(kinds.open_kind(radial), &"", "easing back goes back to the kinds")
	check_equal(radial.pointed_id(), &"", "and drops the card")
	_push(kinds.kind_direction(radial, &"form"), 1.0)
	_frame()
	check_equal(kinds.open_kind(radial), &"form", "a flick out opens a kind at once")


func test_kinds_depth_picks_every_real_card() -> void:
	var radial: RadialScript = _open(PauseMenuScript.Ring.KINDS_DEPTH)
	var kinds: RingKindsScript = radial.ring_picker as RingKindsScript
	for id in _real_cards():
		_let_go()
		_push(kinds.kind_direction(radial, _spells.component_kind(id)), 1.0)
		_frame()
		_push(kinds.card_direction(radial, id), 1.0)
		_frame()
		check_equal(radial.pointed_id(), id, "%s: picked in its kind" % id)


func test_past_the_ends_of_a_kind_the_nearer_end_card_is_picked() -> void:
	var radial: RadialScript = _open(PauseMenuScript.Ring.KINDS_DEPTH)
	var kinds: RingKindsScript = radial.ring_picker as RingKindsScript
	var way: Vector2 = kinds.kind_direction(radial, &"form")
	_push(way, 1.0)
	_frame()
	var forms: Array[Dictionary] = radial.ring_entries().filter(func(entry: Dictionary) -> bool: return entry["kind"] == &"form")
	var first: StringName = forms[0]["id"]
	var last: StringName = forms[forms.size() - 1]["id"]
	var behind: float = RadialScript.angle_of(way) + PI
	_push(RadialScript.direction_of(behind - 0.2), 1.0)
	_frame()
	check_equal(radial.pointed_id(), last, "just past the last card's end")
	_push(RadialScript.direction_of(behind + 0.2), 1.0)
	_frame()
	check_equal(radial.pointed_id(), first, "just past the first card's end")
