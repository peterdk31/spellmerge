extends RefCounted
## What a cue is played with (`Feel.play_cue`), handed to each of its parts' players (the table
## of `Feel.add_cue_part`): who set it off and their ramp, where, which way, how big, in which
## colour and cards, on whom, the colours of what broke, and the spell it is of. Feel keeps one
## per depth of cues played inside a cue's part and fills it for every cue, so playing a cue
## allocates nothing (docs/milestones/spell-spectacle-2.md, S1).

const ActorsScript := preload("res://core/actors/actors.gd")

## The actor that set it off (`ActorsScript.NONE` for none), and its ramp (`Feel._ramp_of`).
var caster: int = ActorsScript.NONE
var ramp: int = 0
## Where it plays, and its way: the cue's direction made unit length (right when it has none).
var at: Vector2 = Vector2.ZERO
var aim: Vector2 = Vector2.RIGHT
## How big: the pixels a part's `reach` is times (the seconds a `lasts_size` part lasts).
var size: float = 0.0
## The colour of its element (as `Feel.show_effect`'s `core`) and its cards (a packed look).
var tint: Color = Color.WHITE
var look: int = 0
## The actor it plays on (`hold_target`), and the shot it was sent by (-1 for none).
var target: int = ActorsScript.NONE
var shot: int = -1
## The ramp-table source of what broke, for the surface kinds and marks (a dying body's art;
## -1: the room's walls).
var surface: int = -1
## The tag of the spell it is of (its cards' motes and marks, `card_kinds.gd`; 0 for none).
var tag: int = 0


## The way a part (a Dictionary with an optional `way`, `CueBase.WAYS`) points: along the cue's
## way, against it, right or up.
func way_of(part: Dictionary) -> Vector2:
	match StringName(part.get("way", "aim")):
		&"back":
			return -aim
		&"right":
			return Vector2.RIGHT
		&"up":
			return Vector2.UP
	return aim
