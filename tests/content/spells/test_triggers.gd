extends "res://tests/support/suite.gd"
## The three triggers in content/spells/triggers/ (M2 part 13): on hit, on expire and timer
## are TriggerBase resources that pass the validator, compile into the numbers they promise,
## and fire the spell they hold through the real spell runtime and projectile manager as their
## names say: on hit where a shot lands, on expire where it ends, a timer every half second at
## most four times. Also a spell three levels deep, the 32-fires-per-step cap, and four players
## at once.
##
## godot --headless --path . --script res://tests/content/spells/test_triggers.gd

const StaffKit := preload("res://tests/support/staff_kit.gd")
const SpellsScript := preload("res://core/spells/spells.gd")
const ManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const EventsScript := preload("res://core/events/events.gd")
const RegistryScript := preload("res://core/registry/registry.gd")

const DT: float = 1.0 / 60.0
const TRIGGERS: Array[StringName] = [&"on_hit", &"on_expire", &"timer"]
## Event, interval, max_fires and complexity from the M2 design.
const EVENTS: Dictionary = {&"on_hit": TriggerBase.Event.HIT, &"on_expire": TriggerBase.Event.EXPIRE, &"timer": TriggerBase.Event.TIMER}
const COMPLEXITY: Dictionary = {&"on_hit": 1, &"on_expire": 1, &"timer": 2}

var _registry: Node
var _spells: SpellsScript
var _mgr: ManagerScript
var _bus: EventsScript
## Every projectile_hit as [player, target, position, tag].
var _hits: Array = []
## tag -> how many of its shots have ended
var _ended: Dictionary = {}


func before_each() -> void:
	_registry = own(RegistryScript.new()) as Node
	_registry.call("scan")
	_bus = own(EventsScript.new()) as EventsScript
	_mgr = own(ManagerScript.new()) as ManagerScript
	_mgr.events = _bus
	_mgr.set_cap(512)
	_spells = own(SpellsScript.new()) as SpellsScript
	_spells.registry = _registry
	_spells.bind(_mgr, _bus)
	_hits.clear()
	_ended.clear()
	_mgr.shot_ended.connect(func(tag: int) -> void: _ended[tag] = _ended.get(tag, 0) + 1)
	_bus.projectile_hit.connect(func(player: int, target: Node, at: Vector2, tag: int) -> void: _hits.append([player, target, at, tag]))


func _trigger(id: StringName) -> TriggerBase:
	return load("res://content/spells/triggers/%s/%s.tres" % [id, id]) as TriggerBase


func _target(position: Vector2, radius: float = 10.0) -> Node2D:
	var node := Node2D.new()
	root.add_child(node)
	node.global_position = position
	own(node)
	_mgr.add_target(node, radius, ManagerScript.LAYER_ENEMY)
	return node


func _tick(steps: int) -> void:
	for i in steps:
		_mgr.step(DT)
		_spells.step(DT)


## The first carrier of the staff for `recipe` (the old recipe shape, see staff_kit.gd).
func _compile(recipe: Dictionary) -> CompiledSpell:
	var spell: CompiledSpell = StaffKit.first(_spells, StaffKit.cards(recipe))
	check(spell != null, "the staff for %s casts" % [recipe])
	return spell


## Builds `recipe` into a staff and casts it from `origin` toward +x. Returns the cast's tag. A
## payload's spells have the next nodes, so `current_tag(player, staff, 1)` is the first one.
func _build_and_cast(player: int, staff: int, recipe: Dictionary, origin: Vector2 = Vector2.ZERO) -> int:
	var tag: int = StaffKit.build(_spells, player, staff, StaffKit.cards(recipe))
	check(_spells.cast_staff(player, staff, origin, Vector2.RIGHT, 100.0) != SpellsScript.REFUSED, "%s is cast" % [recipe])
	return tag


## Shots ever made with `tag` since the test began (alive plus ended).
func _born(tag: int) -> int:
	return _spells.live_shots(tag) + int(_ended.get(tag, 0))


## The slots of the live shots with `tag`.
func _slots(tag: int) -> Array[int]:
	var found: Array[int] = []
	for slot in _mgr.get_cap():
		if _mgr.is_alive(slot) and _mgr.get_tag_of(slot) == tag:
			found.append(slot)
	return found


# --- All three --------------------------------------------------------------

func test_every_trigger_loads_and_matches_its_folder() -> void:
	for id in TRIGGERS:
		var trigger: TriggerBase = _trigger(id)
		check(trigger != null, "%s loads as a TriggerBase" % id)
		if trigger == null:
			continue
		check_equal(trigger.id, id, "%s: the id is the folder name" % id)
		check(trigger.display_name != "", "%s has a name" % id)
		check(trigger.icon != null, "%s has an icon" % id)
		check(trigger.demo, "%s is in the web demo" % id)
		check_equal(trigger.event, EVENTS[id], "%s: the event" % id)
		check_equal(trigger.complexity, COMPLEXITY[id], "%s: complexity from the design table" % id)
		check_equal(trigger.range_problems().size(), 0, "%s: %s" % [id, ", ".join(trigger.range_problems())])


func test_the_timer_waits_half_a_second_and_fires_at_most_four_times() -> void:
	var timer: TriggerBase = _trigger(&"timer")
	check_equal(timer.interval, 0.5, "the timer fires every half second")
	check_equal(timer.max_fires, 4, "and at most four times (its own number; there is no build limit)")
	check_equal(_trigger(&"on_hit").max_fires, 1, "on hit fires once per shot")
	check_equal(_trigger(&"on_expire").max_fires, 1, "on expire fires once per shot")


func test_the_registry_finds_the_three_triggers_and_the_validator_passes_them() -> void:
	var manifest: Dictionary = SpellValidator.load_manifest()
	for id in TRIGGERS:
		var trigger: TriggerBase = _registry.call("get_resource", &"spells", id) as TriggerBase
		check(trigger != null, "the registry finds %s as a trigger" % id)
		if trigger == null:
			continue
		for problem in SpellValidator.check_component(trigger, manifest):
			check(false, SpellValidator.format(problem))


func test_every_trigger_has_its_own_icon() -> void:
	var seen: Dictionary = {}
	for id in TRIGGERS:
		var path: String = _trigger(id).icon.resource_path
		check(not seen.has(path), "%s: the icon %s is not shared" % [id, path])
		seen[path] = true


func test_a_trigger_compiles_into_the_spell_numbers() -> void:
	for id in TRIGGERS:
		var spell: CompiledSpell = _compile({"form": &"bolt", "trigger": id, "held": {"form": &"nova"}})
		var trigger: TriggerBase = _trigger(id)
		check_equal(spell.trigger_event, trigger.event, "%s: the event is compiled" % id)
		check_equal(spell.trigger_interval, trigger.interval, "%s: the interval is compiled" % id)
		check_equal(spell.trigger_max_fires, trigger.max_fires, "%s: max_fires is compiled" % id)
		check(spell.payload != null and spell.payload.spells[0].form_id == &"nova", "%s: the payload is the nova" % id)


func test_a_trigger_with_nothing_after_its_carrier_is_wasted() -> void:
	var staff: CompiledStaff = StaffKit.compile(_spells, [&"on_hit", &"bolt"] as Array[StringName])
	check(staff.casts[0].group.spells[0].payload == null, "nothing to fire")
	check(staff.wasted.has(0), "the trigger is wasted, not refused")


# --- On hit -----------------------------------------------------------------

func test_on_hit_fires_the_held_spell_from_the_hit_point() -> void:
	_target(Vector2(80.0, 0.0))
	_build_and_cast(0, 0, {"form": &"bolt", "trigger": &"on_hit", "held": {"form": &"nova"}})
	_tick(60)
	var held_tag: int = _spells.current_tag(0, 0, 1)
	var bolt_hits: int = 0
	for hit: Array in _hits:
		if SpellTag.node_of(hit[3] as int) == 0:
			bolt_hits += 1
	check_equal(bolt_hits, 1, "the bolt hit once")
	check_equal(_born(held_tag), 8, "and its nova of eight was born")
	check_equal(SpellTag.node_of(held_tag), 1, "at node 1")
	var hit_at: Vector2 = _hits[0][2]
	check(hit_at.x > 50.0 and hit_at.x < 90.0, "the hit was on the target")


func test_on_hit_does_not_fire_without_a_hit() -> void:
	_build_and_cast(0, 0, {"form": &"bolt", "trigger": &"on_hit", "held": {"form": &"nova"}})
	_tick(120)
	check_equal(_born(_spells.current_tag(0, 0, 1)), 0, "a bolt that hits nothing fires nothing")


func test_on_hit_fires_once_per_shot_even_through_a_pierce() -> void:
	_target(Vector2(60.0, 0.0))
	_target(Vector2(110.0, 0.0))
	_target(Vector2(160.0, 0.0))
	_build_and_cast(0, 0, {"form": &"bolt", "modifiers": [&"pierce"], "trigger": &"on_hit", "held": {"form": &"bolt"}})
	_tick(60)
	var from_pierce: int = 0
	for hit: Array in _hits:
		if SpellTag.node_of(hit[3] as int) == 0:
			from_pierce += 1
	check(from_pierce >= 2, "the pierce bolt hit more than one target")
	check_equal(_born(_spells.current_tag(0, 0, 1)), 1, "but fired its held spell once (max_fires 1)")


# --- On expire --------------------------------------------------------------

func test_on_expire_fires_where_the_shot_ended() -> void:
	_build_and_cast(0, 0, {"form": &"bolt", "trigger": &"on_expire", "held": {"form": &"bolt"}})
	var held_tag: int = _spells.current_tag(0, 0, 1)
	_tick(60)
	check_equal(_born(held_tag), 0, "nothing fires while the shot lives")
	_tick(30)
	check_equal(_born(held_tag), 1, "one held shot once the bolt's 1.2 s are up")
	var shots: Array[int] = _slots(held_tag)
	check_equal(shots.size(), 1, "and it is flying")
	if not shots.is_empty():
		check(_mgr.get_position_of(shots[0]).x > 200.0, "from far along the bolt's path")
		check(_mgr.get_velocity_of(shots[0]).normalized().is_equal_approx(Vector2.RIGHT), "the way the bolt was going")


func test_on_expire_at_a_wall_fires_in_front_of_it() -> void:
	var walls: Array[Rect2] = [Rect2(100.0, -50.0, 50.0, 100.0)]
	_mgr.set_walls(walls)
	_build_and_cast(0, 0, {"form": &"bolt", "trigger": &"on_expire", "held": {"form": &"nova"}})
	_tick(40)
	var held_tag: int = _spells.current_tag(0, 0, 1)
	check_equal(_born(held_tag), 8, "the nova fired when the bolt reached the wall")
	for slot in _slots(held_tag):
		check(_mgr.get_position_of(slot).x < 105.0, "and started on this side of it")


func test_on_expire_does_not_fire_when_the_shot_hit_something() -> void:
	_target(Vector2(60.0, 0.0))
	_build_and_cast(0, 0, {"form": &"bolt", "trigger": &"on_expire", "held": {"form": &"nova"}})
	_tick(120)
	check_equal(_hits.size(), 1, "the bolt hit the target")
	check_equal(_born(_spells.current_tag(0, 0, 1)), 0, "a shot that ends on a hit does not expire")


# --- Timer ------------------------------------------------------------------

func test_a_timer_fires_every_half_second_four_times_and_no_more() -> void:
	_build_and_cast(0, 0, {"form": &"rune", "trigger": &"timer", "held": {"form": &"bolt"}})
	var held_tag: int = _spells.current_tag(0, 0, 1)
	_tick(29)
	check_equal(_born(held_tag), 0, "nothing before half a second")
	_tick(3)
	check_equal(_born(held_tag), 1, "the first fire at 0.5 s")
	_tick(30)
	check_equal(_born(held_tag), 2, "the second at 1.0 s")
	_tick(60)
	check_equal(_born(held_tag), 4, "the fourth at 2.0 s")
	_tick(300)
	check_equal(_born(held_tag), 4, "and never a fifth, though the rune lives on")


func test_a_timer_fires_from_where_its_shot_is() -> void:
	_build_and_cast(0, 0, {"form": &"rune", "trigger": &"timer", "held": {"form": &"bolt"}}, Vector2(100.0, 50.0))
	_tick(32)
	var shots: Array[int] = _slots(_spells.current_tag(0, 0, 1))
	check_equal(shots.size(), 1, "one held shot")
	if not shots.is_empty():
		var at: Vector2 = _mgr.get_position_of(shots[0])
		check(at.distance_to(Vector2(100.0, 50.0)) < 20.0, "close to the rune that fired it")


func test_a_timer_stops_when_the_shot_ends() -> void:
	# A bolt lives 1.2 s: its timer fires at 0.5 s and 1.0 s only.
	_build_and_cast(0, 0, {"form": &"bolt", "trigger": &"timer", "held": {"form": &"bolt"}})
	_tick(200)
	check_equal(_born(_spells.current_tag(0, 0, 1)), 2, "two fires in the bolt's 1.2 s")


# --- Depth, the cap, four players --------------------------------------------

func test_a_spell_three_levels_deep_fires_all_the_way_down() -> void:
	# The bolt hits the first target; the nova it fires hits the ring of targets round it;
	# each of those fires a bolt (depth 2).
	var center := Vector2(60.0, 0.0)
	_target(center)
	for n in 8:
		_target(center + Vector2.from_angle(TAU * n / 8.0 + 0.2) * 40.0, 4.0)
	var recipe: Dictionary = {
		"form": &"bolt", "trigger": &"on_hit",
		"held": {"form": &"nova", "trigger": &"on_hit", "held": {"form": &"bolt"}},
	}
	var spell: CompiledSpell = _compile(recipe)
	check_equal(spell.chain_length(), 3, "bolt, on hit, nova, on hit, bolt: three spells deep")
	_build_and_cast(0, 0, recipe)
	_tick(90)
	var depth_1: int = _born(_spells.current_tag(0, 0, 1))
	var depth_2: int = _born(_spells.current_tag(0, 0, 2))
	check_equal(depth_1, 8, "the nova of depth 1 was born")
	check(depth_2 >= 1, "and at least one bolt of depth 2 after it: %d" % depth_2)
	check(depth_2 <= 8, "no more than one per nova shot (max_fires 1): %d" % depth_2)
	check_equal(SpellTag.node_of(_spells.current_tag(0, 0, 2)), 2, "the last level is depth 2")


func test_payloads_nest_as_deep_as_the_cards_go() -> void:
	var deep: Dictionary = {
		"form": &"bolt", "trigger": &"on_hit",
		"held": {"form": &"bolt", "trigger": &"on_expire", "held": {"form": &"bolt", "trigger": &"timer", "held": {"form": &"bolt"}}},
	}
	var spell: CompiledSpell = _compile(deep)
	check(spell != null and spell.chain_length() == 4, "four levels compile: there is no depth limit any more")


func test_the_three_triggers_mix_at_three_levels() -> void:
	# bolt -(on hit)-> rune -(timer)-> bolt: the rune is dropped where the bolt landed and then throws bolts.
	var victim: Node2D = _target(Vector2(60.0, 0.0))
	_build_and_cast(0, 0, {
		"form": &"bolt", "trigger": &"on_hit",
		"held": {"form": &"rune", "trigger": &"timer", "held": {"form": &"bolt"}},
	})
	for step in 60:
		_tick(1)
		if not _hits.is_empty():
			break
	# The target dies, so the rune (which does not pierce) is not used up on it.
	_mgr.remove_target(victim)
	_tick(150)
	check_equal(_born(_spells.current_tag(0, 0, 1)), 1, "the rune was dropped on the hit")
	check_equal(_born(_spells.current_tag(0, 0, 2)), 4, "it threw four bolts in 2 s")


func test_the_fire_cap_holds_with_the_real_triggers() -> void:
	for n in 24:
		_target(Vector2.from_angle(TAU * n / 24.0) * 40.0, 3.0)
	var hold: Dictionary = {"form": &"nova", "modifiers": [&"split"], "trigger": &"on_hit", "held": {"form": &"bolt"}}
	check_equal(_compile(hold).shots, 24, "the nova is 24 shots")
	_build_and_cast(0, 0, hold)
	_build_and_cast(0, 1, hold)
	_tick(40)
	var fired: int = _born(_spells.current_tag(0, 0, 1)) + _born(_spells.current_tag(0, 1, 1))
	check_equal(fired, SpellLimits.MAX_FIRES_PER_STEP, "the player fired the cap from 48 hits in one step")
	check_equal(_spells.fires_dropped, 48 - SpellLimits.MAX_FIRES_PER_STEP, "the rest were dropped, not queued")
	_tick(10)
	check_equal(_born(_spells.current_tag(0, 0, 1)) + _born(_spells.current_tag(0, 1, 1)), fired, "nothing fired later")


func test_every_trigger_works_for_all_four_players_at_once() -> void:
	for index in TRIGGERS.size():
		var id: StringName = TRIGGERS[index]
		_spells.clear()
		_mgr.clear()
		_hits.clear()
		_ended.clear()
		# Each player has a row of their own, 400 px apart, and each trigger its own column.
		var form: StringName = &"rune" if id == &"timer" else &"bolt"
		for player in 4:
			var origin := Vector2(-900.0 + 300.0 * index, -900.0 + 400.0 * player)
			if id == &"on_hit":
				_target(origin + Vector2(80.0, 0.0))
			_build_and_cast(player, 0, {"form": form, "trigger": id, "held": {"form": &"bolt"}}, origin)
		_tick(100)
		for player in 4:
			var held_tag: int = _spells.current_tag(player, 0, 1)
			var expected: int = 1
			if id == &"timer":
				expected = 3
			elif id == &"on_expire":
				expected = 1
			check_equal(_born(held_tag), expected, "%s: player %d's held spell fired %d time(s)" % [id, player, expected])
			check_equal(SpellTag.player_of(held_tag), player, "%s: and carries player %d's tag" % [id, player])
		_spells.clear()
