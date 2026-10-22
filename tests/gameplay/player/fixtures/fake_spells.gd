extends "res://core/spells/spells.gd"
## Test stand-in for the spell runtime (not content): every recipe compiles, `cast` records who
## fired from where and keeps a cooldown per player and slot, and nothing is spawned. It lets
## the player tests run the wizard on its own, with `cost` and `cooldown_time` set per test.

## Mana a cast takes, and seconds before the same player and slot may cast again.
var cost: float = 1.0
var cooldown_time: float = 0.0
## One entry per cast that fired.
var fired_players: Array[int] = []
var fired_slots: Array[int] = []
var origins: Array[Vector2] = []
var directions: Array[Vector2] = []
## [player, slot] for every install, in order.
var installed: Array[Vector2i] = []

var _left: PackedFloat32Array = PackedFloat32Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
var _has: PackedByteArray = PackedByteArray([0, 0, 0, 0, 0, 0, 0, 0])


func compile(recipe: Dictionary) -> CompiledSpell:
	var spell := CompiledSpell.new()
	spell.valid = recipe.has("form")
	spell.reason = "" if spell.valid else "A spell needs a form."
	spell.description = "A fake spell."
	return spell


func install(player: int, slot: int, _spell: CompiledSpell) -> int:
	installed.append(Vector2i(player, slot))
	_has[player * 2 + slot] = 1
	return 1


func cast(player: int, slot: int, origin: Vector2, direction: Vector2, mana: float) -> float:
	var at: int = player * 2 + slot
	if _has[at] == 0 or _left[at] > 0.0 or mana < cost:
		return REFUSED
	_left[at] = cooldown_time
	fired_players.append(player)
	fired_slots.append(slot)
	origins.append(origin)
	directions.append(direction)
	return cost


func step(delta: float) -> void:
	for at in _left.size():
		_left[at] = maxf(_left[at] - delta, 0.0)
