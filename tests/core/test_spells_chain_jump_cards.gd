extends "res://tests/support/suite.gd"
## A flying chain jump is its carrier fired again from the hit, with every card it has (phase R,
## R1b, docs/milestones/M2-rules.md, rules 2 and 6): homing, bounce, ghost, spiral, linger,
## growth, sticky, return, shield, pierce, arc, magnet and its trigger ride on, one jump fewer,
## and it flies as far as its carrier would.
##
## godot --headless --path . --script res://tests/core/test_spells_chain_jump_cards.gd

const ArenaScript := preload("res://tests/content/spells/combo_arena.gd")
const ManagerScript := preload("res://core/projectiles/projectile_manager.gd")

const BIG: int = 100000


## Casts `cards` at an imp 60 px away with a second one 60 px below it, runs until the first
## chain jump flies, and returns `probe.call(arena, slot)` for it (null when no jump came).
func _on_jump(cards: Array, probe: Callable) -> Variant:
	var arena := ArenaScript.new(root)
	arena.add_imp(Vector2(60.0, 0.0), BIG)
	arena.add_imp(Vector2(60.0, 60.0), BIG)
	var staff: CompiledStaff = arena.install_cards(0, 0, cards)
	var spell: CompiledSpell = staff.casts[0].group.spells[0]
	arena.cast(0, 0)
	var out: Variant = null
	for step in 60:
		arena.run(ArenaScript.STEP)
		var slot: int = _jump_slot(arena, spell)
		if slot >= 0:
			out = probe.call(arena, slot)
			break
	arena.free_all()
	return out


## The live shot of `spell` that is a jump (one jump fewer than the carrier), or -1.
func _jump_slot(arena: ArenaScript, spell: CompiledSpell) -> int:
	var mgr: ManagerScript = arena.projectiles
	for slot in mgr.get_cap():
		if not mgr.is_alive(slot) or arena.spells._profiles.get(mgr.get_tag_of(slot)) != spell:
			continue
		if arena.spells._rec_chain[slot] == spell.chain_jumps - 1:
			return slot
	return -1


func _has(cards: Array, probe: Callable, what: String) -> void:
	var with: Variant = _on_jump(["chain"] + cards + ["bolt"], probe)
	check(with != null, "%s: a jump flies" % what)
	check(with == true, "%s: the jump keeps it" % what)
	check(_on_jump(["chain", "bolt"], probe) == false, "%s: a plain jump has none (the probe tells)" % what)


func test_a_jump_homes() -> void:
	_has(["homing"], func(a: ArenaScript, s: int) -> bool: return a.projectiles._turn[s] > 0.0, "homing")


func test_a_jump_bounces() -> void:
	_has(["bounce"], func(a: ArenaScript, s: int) -> bool: return a.projectiles._bounce[s] > 0, "bounce")


func test_a_jump_is_a_ghost() -> void:
	_has(["ghost"], func(a: ArenaScript, s: int) -> bool: return a.projectiles._flags[s] & ManagerScript.F_GHOST != 0, "ghost")


func test_a_jump_spirals() -> void:
	_has(["spiral"], func(a: ArenaScript, s: int) -> bool: return a.projectiles._flags[s] & ManagerScript.F_WAVE != 0, "spiral")


func test_a_jump_returns() -> void:
	_has(["return"], func(a: ArenaScript, s: int) -> bool: return a.projectiles._flags[s] & ManagerScript.F_RETURN != 0, "return")


func test_a_jump_lingers() -> void:
	_has(["linger"], func(a: ArenaScript, s: int) -> bool: return a.projectiles._linger[s] > 0.0, "linger")


func test_a_jump_grows() -> void:
	_has(["growth"], func(a: ArenaScript, s: int) -> bool: return a.projectiles._growth[s] > 1.0, "growth")


func test_a_jump_sticks() -> void:
	_has(["sticky"], func(a: ArenaScript, s: int) -> bool: return a.projectiles._stick[s] > 0.0, "sticky")


func test_a_jump_shields() -> void:
	_has(["shield"], func(a: ArenaScript, s: int) -> bool: return a.projectiles.get_shield_of(s) > 0, "shield")


func test_a_jump_pierces() -> void:
	_has(["pierce"], func(a: ArenaScript, s: int) -> bool: return a.projectiles._pierce[s] > 0, "pierce")


func test_a_jump_zaps() -> void:
	_has(["arc"], func(a: ArenaScript, s: int) -> bool: return a.spells._rec_arc[s] == 1, "arc")


func test_a_jump_pulls() -> void:
	_has(["magnet"], func(a: ArenaScript, s: int) -> bool: return a.spells._rec_magnet[s] == 1, "magnet")


func test_a_jump_keeps_its_timer() -> void:
	var timed: Callable = func(a: ArenaScript, s: int) -> bool: return a.spells._rec_timed[s] == 1
	check(_on_jump(["timer", "chain", "bolt", "nova"], timed) == true, "a timer bolt's jump runs the timer")


func test_a_jump_flies_as_far_as_its_carrier() -> void:
	var life: Callable = func(a: ArenaScript, s: int) -> float: return a.projectiles._life[s]
	var left: Variant = _on_jump(["chain", "bolt"], life)
	var bolt: FormBase = load("res://content/spells/forms/bolt/bolt.tres") as FormBase
	# It flies at least CHAIN_MIN_SPEED, so it covers the bolt's range in less time.
	var speed: float = maxf(bolt.speed, SpellLimits.CHAIN_MIN_SPEED)
	check(left != null and float(left) * speed > bolt.lifetime * bolt.speed - 30.0, "a bolt's jump flies a bolt's range (%s s)" % [left])
