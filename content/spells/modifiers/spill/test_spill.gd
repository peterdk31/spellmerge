extends "res://tests/support/suite.gd"
## The Spill card (content/spells/modifiers/spill/; docs/milestones/oil-spill.md): the next carrier
## splashes wide where it lands. Every touch of the floor it makes where it lands is its strength
## wider (a shot's end, a blast, a pulse, a pool); a carrier that only passes over the floor (a dash, a
## swing, a beam, a slam) touches that wide where it lands; one that makes a body or a gate (a decoy,
## a familiar, a portal) lands nothing (wasted). With no infusion nothing touches the floor, so Spill
## alone is wasted. Played on every carrier card the registry finds, with Fire on it.
const ArenaScript := preload("res://tests/content/spells/combo_arena.gd")
const RegistryScript := preload("res://core/registry/registry.gd")


func _card() -> ModifierBase:
	return load("res://content/spells/modifiers/spill/spill.tres") as ModifierBase


func test_the_card() -> void:
	var card: ModifierBase = _card()
	check(card != null, "spill.tres loads as a ModifierBase")
	if card == null:
		return
	check_equal(card.id, &"spill", "its id is its folder")
	check_equal(card.behaviour, ModifierBase.Behaviour.SPILL, "its behaviour")
	check_equal(card.behaviour_strength, 32.0, "32 px wider")
	check_equal(ModifierBase.stacks(ModifierBase.Behaviour.SPILL), ModifierBase.Stack.ADD, "more cards add")
	check(card.range_problems().is_empty(), "inside every range: %s" % [card.range_problems()])
	check(card.icon != null and card.icon.get_width() == 64, "a 64-px icon")
	check(card.description.length() <= 60, "its builder line fits")


func test_alone_it_is_wasted_with_an_infusion_it_is_kept() -> void:
	check(not StaffCompiler.card_works(_card(), &"atom"), "alone on a bolt it does nothing: nothing touches the floor")
	var arena := ArenaScript.new(root)
	var alone: CompiledStaff = arena.spells.compile_staff([&"spill", &"bolt"] as Array[StringName], ArenaScript.plain_staff(2))
	check(alone.wasted.has(0), "listed as wasted alone")
	var infused: CompiledStaff = arena.spells.compile_staff([&"fire", &"spill", &"bolt"] as Array[StringName], ArenaScript.plain_staff(3))
	check(not infused.wasted.has(1), "kept with Fire")
	var portal: CompiledStaff = arena.spells.compile_staff([&"fire", &"spill", &"portal"] as Array[StringName], ArenaScript.plain_staff(3))
	check(portal.wasted.has(1), "a portal lands nothing")
	arena.free_all()


## The widest floor touch (`floor_touched`) of a cast of `cards`, cast by player 0 along +x with an
## imp ahead to hit, the moves and the bodies a cast asks for answered.
func _widest(cards: Array) -> float:
	var arena := ArenaScript.new(root)
	arena.answer_moves()
	arena.add_entities()
	arena.add_imp(Vector2(70.0, 0.0))
	var widest: Array[float] = [-1.0]
	arena.bus.floor_touched.connect(func(_c: int, _e: StringName, _at: Vector2, radius: float, _t: int) -> void: widest[0] = maxf(widest[0], radius))
	arena.install_cards(0, 0, cards)
	arena.cast(0, 0)
	# Long enough for a rune's or a wall's life to end.
	arena.run(10.5)
	arena.free_all()
	return widest[0]


func test_on_every_carrier_it_lands_wide_where_it_is_kept() -> void:
	var registry := own(RegistryScript.new()) as RegistryScript
	registry.scan()
	var compiler := ArenaScript.new(root)
	var tried: int = 0
	for card: Resource in registry.get_all(&"spells"):
		if not card is CarrierCard:
			continue
		var id: StringName = (card as CarrierCard).id
		var built: CompiledStaff = compiler.spells.compile_staff([&"fire", &"spill", id] as Array[StringName], ArenaScript.plain_staff(3))
		var kept: bool = not built.wasted.has(1)
		var without: float = _widest([&"fire", id])
		var with: float = _widest([&"fire", &"spill", id])
		if kept:
			tried += 1
			check(with >= maxf(without, 0.0) + 31.9, "%s with Spill lands 32 px wider (%s, without %s)" % [id, with, without])
		else:
			check_equal(with, without, "%s: wasted, and nothing changes" % id)
	compiler.free_all()
	check(tried >= 10, "played on the carriers (%d)" % tried)


## Regression (the review): a pulling shot spent by its hit touches the floor where it arrives (its
## end touch waits for the arrival), as wide as its own end, and wider with Spill.
func test_a_pulling_shot_touches_where_it_arrives() -> void:
	var plain: float = _widest([&"fire", &"pull", &"bolt"])
	check(plain > 0.0, "a fire pull bolt touches the floor (%s)" % plain)
	var spilt: float = _widest([&"fire", &"spill", &"pull", &"bolt"])
	check(spilt >= plain + 31.9, "Spill widens it (%s, without %s)" % [spilt, plain])


func test_two_spills_add() -> void:
	var one: float = _widest([&"fire", &"spill", &"bolt"])
	var two: float = _widest([&"fire", &"spill", &"spill", &"bolt"])
	check(is_equal_approx(two - one, 32.0), "a second card adds 32 px (%s, %s)" % [one, two])
