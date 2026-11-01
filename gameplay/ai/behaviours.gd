class_name AIBehaviours
extends RefCounted
## Every behaviour an AI weighs (docs/milestones/M2-enemy-ai.md, "Behaviours"), one stateless
## copy each, shared by every AI. A new behaviour is one file in `behaviours/` and one line here.

const LIST: Array[Script] = [
	preload("res://gameplay/ai/behaviours/chase.gd"),
	preload("res://gameplay/ai/behaviours/position.gd"),
	preload("res://gameplay/ai/behaviours/fight.gd"),
	preload("res://gameplay/ai/behaviours/flank.gd"),
	preload("res://gameplay/ai/behaviours/close_in.gd"),
	preload("res://gameplay/ai/behaviours/dodge.gd"),
	preload("res://gameplay/ai/behaviours/guard.gd"),
	preload("res://gameplay/ai/behaviours/evade.gd"),
	preload("res://gameplay/ai/behaviours/open.gd"),
]

static var _all: Array[AIBehaviour] = []


## The shared behaviours, made on first use.
static func all() -> Array[AIBehaviour]:
	if _all.is_empty():
		for script: Script in LIST:
			var made: AIBehaviour = script.new() as AIBehaviour
			made.index = _all.size()
			_all.append(made)
	return _all
