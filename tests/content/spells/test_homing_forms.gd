extends "res://tests/support/suite.gd"
## Homing on every form card in the registry, so a new form (or a change to one, or to the Homing
## card) cannot get it wrong unseen. `StaffCompiler.homing_steers` and `homing_range` are the one
## rule: a form homing steers must turn onto a target off its line anywhere it can reach (a
## bolt's flight, a beam's length), and on a form it cannot steer the Homing card must be listed
## as wasted and change nothing.
##
## godot --headless --path . --script res://tests/content/spells/test_homing_forms.gd

const StaffKit := preload("res://tests/support/staff_kit.gd")
const SpellsScript := preload("res://core/spells/spells.gd")
const ManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const EventsScript := preload("res://core/events/events.gd")
const RegistryScript := preload("res://core/registry/registry.gd")

const DT: float = 1.0 / 60.0
## How far off the aim the target stands, in degrees: well off a plain shot's line, and inside a
## homing beam's bend (SpellLimits.INSTANT_HOMING_ANGLE).
const OFF_AIM: float = 20.0
## The share of a form's reach the target stands at: near its end, where a short search misses.
const FAR: float = 0.85

var _registry: Node
var _spells: SpellsScript
var _mgr: ManagerScript
var _bus: EventsScript
## Every target hit, in order.
var _hit: Array = []
## Every move asked of a wizard, as [player, mode, to].
var _moves: Array = []


func before_each() -> void:
	_registry = own(RegistryScript.new()) as Node
	_registry.call("scan")
	_bus = own(EventsScript.new()) as EventsScript
	_mgr = own(ManagerScript.new()) as ManagerScript
	_mgr.events = _bus
	_spells = own(SpellsScript.new()) as SpellsScript
	_spells.registry = _registry
	_spells.bind(_mgr, _bus)
	_hit.clear()
	_moves.clear()
	_bus.projectile_hit.connect(func(_player: int, target: Node, _at: Vector2, _tag: int) -> void: _hit.append(target))
	_bus.caster_move_requested.connect(func(player: int, mode: StringName, to: Vector2, _seconds: float, _tag: int) -> void: _moves.append([player, mode, to]))


func _forms() -> Array[FormBase]:
	var forms: Array[FormBase] = []
	for card: Resource in _registry.call("get_all", &"spells"):
		if card is FormBase:
			forms.append(card as FormBase)
	return forms


## How far a form gets: a beam, a dash or a teleport its length, a shot in flight its speed for
## its life.
static func _reach(form: FormBase) -> float:
	return form.ray_length if form.ray_length > 0.0 else form.speed * form.lifetime


## Forms that move their caster instead of hitting: their homing shows in the move asked for.
static func _moves_caster(form: FormBase) -> bool:
	return form.motion == FormBase.Motion.DASH or form.motion == FormBase.Motion.TELEPORT


## Casts `cards` for `player` from the origin to the right, runs it out, and says whether
## `target` was hit.
func _hits(player: int, cards: Array[StringName], target: Node2D, seconds: float) -> bool:
	_hit.clear()
	StaffKit.build(_spells, player, 0, cards)
	check(_spells.cast_staff(player, 0, Vector2.ZERO, Vector2.RIGHT, 100.0) != SpellsScript.REFUSED, "%s is cast" % [cards])
	for i in ceili(seconds / DT):
		_mgr.step(DT)
		_spells.step(DT)
	return _hit.has(target)


func test_there_are_forms_of_both_kinds() -> void:
	var steered: int = 0
	var not_steered: int = 0
	for form in _forms():
		if StaffCompiler.homing_steers(form.motion):
			steered += 1
		else:
			not_steered += 1
	check(steered >= 2 and not_steered >= 1, "the registry has forms homing steers (%d) and forms it does not (%d)" % [steered, not_steered])


func test_a_homing_form_reaches_a_target_off_its_line_near_the_end_of_its_reach() -> void:
	for form in _forms():
		if not StaffCompiler.homing_steers(form.motion):
			continue
		before_each()
		var at: Vector2 = Vector2.from_angle(deg_to_rad(OFF_AIM)) * _reach(form) * FAR
		var target := Node2D.new()
		root.add_child(target)
		own(target)
		target.global_position = at
		_mgr.add_target(target, 8.0, ManagerScript.LAYER_ENEMY)
		var seconds: float = form.lifetime + 0.2
		if _moves_caster(form):
			_check_move(form, at)
			continue
		# A lone shot on its line misses it, so a hit below is the homing's doing.
		if form.shots == 1 and form.spread <= 0.0:
			check(not _hits(0, [form.id] as Array[StringName], target, seconds), "a plain %s misses a target %s px off at %s degrees" % [form.id, roundi(at.length()), OFF_AIM])
		check(_hits(1, [&"homing", form.id] as Array[StringName], target, seconds), "a homing %s turns onto a target %s px off at %s degrees" % [form.id, roundi(at.length()), OFF_AIM])


## A homing teleport is sent at the target; a homing dash hands the wizard the turn rate and
## reach it turns with as it goes (the wizard's turning is tested in test_player_caster.gd).
func _check_move(form: FormBase, at: Vector2) -> void:
	_moves.clear()
	_spells.set_aim(1, Vector2.ZERO, Vector2.RIGHT)
	StaffKit.build(_spells, 1, 0, [&"homing", form.id] as Array[StringName])
	check(_spells.cast_staff(1, 0, Vector2.ZERO, Vector2.RIGHT, 100.0) != SpellsScript.REFUSED, "a homing %s is cast" % form.id)
	check_equal(_moves.size(), 1, "a homing %s asks for one move" % form.id)
	if _moves.size() != 1:
		return
	if form.motion == FormBase.Motion.TELEPORT:
		var to: Vector2 = _moves[0][2]
		check(absf(to.angle_to(at)) < 0.01, "a homing %s blinks straight at a target %s px off at %s degrees: %s" % [form.id, roundi(at.length()), OFF_AIM, to])
	else:
		var homing: Homing = _spells.move_homing(1)
		check(homing.homes() and homing.reach >= at.length(), "a homing %s turns the wizard toward a target %s px off (reach %s)" % [form.id, roundi(at.length()), homing.reach])


func test_homing_on_a_form_it_cannot_steer_is_wasted_and_changes_nothing() -> void:
	for form in _forms():
		if StaffCompiler.homing_steers(form.motion):
			continue
		var staff: CompiledStaff = StaffKit.compile(_spells, [&"homing", form.id] as Array[StringName])
		check(staff.wasted.has(0), "homing on a %s is listed as wasted" % form.id)
		var plain: CompiledSpell = StaffKit.first(_spells, [form.id] as Array[StringName])
		var homing: CompiledSpell = StaffKit.first(_spells, [&"homing", form.id] as Array[StringName])
		check_equal(homing.homing_range, 0.0, "a %s does not home" % form.id)
		check_equal(homing.damage, plain.damage, "nor does the wasted card cut a %s's damage" % form.id)
		check_equal(homing.look, plain.look, "nor change a %s's look" % form.id)


func test_the_compiled_range_is_the_rule_for_each_form() -> void:
	var reach: float = (_registry.call("get_resource", &"spells", &"homing") as ModifierBase).behaviour_reach
	for form in _forms():
		var spell: CompiledSpell = StaffKit.first(_spells, [&"homing", form.id] as Array[StringName])
		check_equal(spell.homing_range, StaffCompiler.homing_range(form.motion, form.ray_length, reach), "a homing %s looks as far as the rule says" % form.id)
