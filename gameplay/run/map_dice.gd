class_name MapDice
extends RefCounted
## A map generator's rolls in one attempt (run generation RG2; connected biomes CB5,
## `BiomeGenerator`): `sim.chance(purpose, key, counter)`, the key the attempt's and a step's
## (`attempt * steps + step`), the counter that step's own count, so one step's rolls never shift
## another's and every attempt rolls afresh.

const DERIVED: Array[StringName] = [&"sim"]

var sim: Sim = null
var purpose: StringName = &""
var attempt: int = 0
var steps: int = 1
var counts: Array[int] = []


func _init(of_sim: Sim, of_purpose: StringName, of_attempt: int, of_steps: int) -> void:
	sim = of_sim
	purpose = of_purpose
	attempt = of_attempt
	steps = of_steps
	counts.resize(of_steps)
	counts.fill(0)


## A roll in [0, 1) of step `step`.
func roll(step: int) -> float:
	var value: float = sim.chance(purpose, attempt * steps + step, counts[step])
	counts[step] += 1
	return value


## A whole number from 0 to `count` - 1 of step `step` (no roll when `count` is 1 or less).
func below(step: int, count: int) -> int:
	if count <= 1:
		return 0
	var value: int = sim.chance_int(purpose, attempt * steps + step, counts[step], count)
	counts[step] += 1
	return value


## An index of `weights` (each at least 0, their sum above 0) by weight, a roll of step `step`; the
## last with a weight when the roll runs past the sum's rounding.
func pick(step: int, weights: PackedFloat32Array) -> int:
	var total: float = 0.0
	for weight: float in weights:
		total += weight
	var left: float = roll(step) * total
	var last: int = -1
	for i in weights.size():
		if weights[i] <= 0.0:
			continue
		last = i
		if left < weights[i]:
			return i
		left -= weights[i]
	return last
