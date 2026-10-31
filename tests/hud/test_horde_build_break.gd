extends "res://tests/support/suite.gd"
## The horde's build break with a real wizard (docs/milestones/horde.md; owner, 2026-10-31): the
## game is paused for everyone until every player is ready, and meanwhile a seat opens its
## builder with B, builds, and the change really reaches its wizard's staff; then it says ready
## on its horde box. The HUD, the builders, the focus service and the input run while the tree
## is paused; the builder's requests are events the player's controller answers at once. The
## real registry and spell runtime and the 20-slot dev staff, as in test_radial_builder.gd.
##
## godot --headless --path . --script res://tests/hud/test_horde_build_break.gd

const EventsScript := preload("res://core/events/events.gd")
const InputManagerScript := preload("res://core/input/input_manager.gd")
const UIFocusScript := preload("res://core/ui_focus/ui_focus.gd")
const RegistryScript := preload("res://core/registry/registry.gd")
const WizardFixture := preload("res://tests/gameplay/player/wizard_fixture.gd")
const HudScript := preload("res://hud/panels/panels.gd")
const RadialScript := preload("res://hud/builder/radial_builder.gd")
const HordePanelScript := preload("res://hud/panels/horde/horde_panel.gd")
const HordePickScript := preload("res://hud/panels/horde/horde_pick.gd")
## Loaded when needed, not preloaded: this scene is also the "Hud" autoload.
const HUD_SCENE_PATH: String = "res://hud/panels/panels.tscn"
## A save no test writes, so a Hud never reads the real `user://save.cfg`.
const NO_SAVE: String = "user://test_no_save.cfg"

const STEP: float = 0.0625
const START: Array = [[&"dash"], [&"fire", &"bolt"], [], []]

var _world: WizardFixture
var _focus: UIFocusScript
var _hud: HudScript
var _horde: HordePanelScript
var _wizard: Actor
var _readies: Array[int] = []


func before_each() -> void:
	_world = WizardFixture.new(root)
	_focus = UIFocusScript.new()
	_focus.input = _world.input
	_focus.events = _world.bus
	_focus._ready()
	_readies.clear()
	_world.bus.horde_ready_requested.connect(func(seat: int) -> void: _readies.append(seat))
	_hud = (load(HUD_SCENE_PATH) as PackedScene).instantiate() as HudScript
	_hud.events = _world.bus
	_hud.save = SaveFile.new(NO_SAVE)
	_hud.ui_focus = _focus
	_hud.input = _world.input
	_hud.spells = _world.spells
	root.add_child(_hud)
	# The radial builder, every card on the ring, push (the defaults).
	_hud.call("_on_builder_options_changed", true, 0, true)
	_horde = _hud.get_horde()
	_horde.set_process(false)
	_wizard = _world.wizard(0, Vector2.ZERO, START, _world.registry.get_resource(&"wizard", &"dev") as StaffBase)
	_world.bus.player_joined.emit(0)
	_world.bus.room_entered.emit(&"horde")
	_world.bus.horde_started.emit(null)


func after_each() -> void:
	paused = false
	_hud.free()
	_focus.free()
	_world.free_all()


func _tap(action: StringName) -> void:
	_world.input.send_virtual(0, action, 1.0)
	_world.input.send_virtual(0, action, 0.0)


## One paused frame of what runs while paused: the HUD (menus, builders, the horde boxes) and the
## focus service. The wizard is not stepped: it stands still with the rest of the game.
func _frame() -> void:
	_hud.poll()
	_focus.poll()
	_hud.get_radial(0).step(STEP)
	_horde.poll()


## The break as the director starts it: the tree paused, then the events.
func _start_break() -> void:
	paused = true
	_world.bus.horde_break_changed.emit(true)
	_world.bus.horde_ready_changed.emit(0, false)
	_frame()


func test_the_hud_and_its_builders_run_while_paused() -> void:
	_start_break()
	check(paused, "the break pauses the game")
	check(_hud.can_process() and _hud.get_radial(0).can_process() and _horde.can_process(), "the HUD, the builder and the horde boxes run while paused")
	check(not _wizard.can_process(), "the wizard stands still")
	check_equal(_focus.process_mode, Node.PROCESS_MODE_ALWAYS, "the focus service runs while paused")
	check_equal(_world.input.process_mode, Node.PROCESS_MODE_ALWAYS, "and so does the input")


func test_a_staff_change_in_the_break_reaches_the_wizard() -> void:
	_start_break()
	check_equal(_horde.get_pick(0).mode(), HordePickScript.Mode.PROMPT, "no offer: the seat builds, then says ready")
	_tap(&"back")
	_frame()
	var radial: RadialScript = _hud.get_radial(0)
	check(radial.is_open(), "B opens the builder while the game is paused")
	check(not _horde.get_pick(0).visible, "the horde box hides behind it")
	var direction: Vector2 = radial.direction_to(&"nova")
	check(direction != Vector2.ZERO, "nova is on the ring")
	_world.input.send_virtual_aim(0, direction)
	_frame()
	_tap(&"staff_2")
	_frame()
	var cards: Array[StringName] = _wizard.caster.cards_of(1)
	check_equal(cards.slice(0, 3), [&"fire", &"bolt", &"nova"] as Array[StringName], "the wizard's staff changed during the pause")
	check(_readies.is_empty(), "building says nothing about ready")
	_world.input.send_virtual_aim(0, Vector2.ZERO)
	_tap(&"back")
	_frame()
	check(not radial.is_open(), "B closes the builder")
	check(paused, "the game stays paused")
	check(_horde.get_pick(0).visible, "the ready prompt shows again")
	_frame()
	_tap(&"accept")
	_frame()
	check_equal(_readies, [0] as Array[int], "A on the prompt says ready")
