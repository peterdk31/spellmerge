class_name CardLook
extends RefCounted
## A carrier card's look as the area that draws it reads it (docs/milestones/card-looks.md): its
## own shader (null: the area's plain one) and how bright and how far it lights the room, times the
## spell light's own. Spells hands these out (`Spells.look_of`), one per card, made once and shared,
## so an area that draws a card never reads the card itself. Read only: never change one you are
## given.

## Not state: `PLAIN` is a shared constant look, never changed (core/sim/README.md, "Steps").
const DERIVED: Array[StringName] = [&"PLAIN"]

## The shader that draws it, or null for the drawing area's plain one.
var shader: Shader = null
## How bright and how far it lights the room (spell light), times the light's own: 1 as any shot.
var light_intensity: float = 1.0
var light_reach: float = 1.0
## The motes its still shots give off while they stand (`FormBase.look_motes`: a MoteKind id, empty
## for none), how many a second each shot gives off, and from where (`look_motes_from`: 0 the oval of
## its hit size, 1 along its piece of a row).
var motes: StringName = &""
var mote_rate: float = 0.0
var motes_from: int = 0

## The look of a card with none of its own, or of an id that is no carrier card: drawn plain, lit
## as any. Shared.
static var PLAIN: CardLook = CardLook.new()


static func of(look_shader: Shader, intensity: float, reach: float) -> CardLook:
	var look := CardLook.new()
	look.shader = look_shader
	look.light_intensity = intensity
	look.light_reach = reach
	return look
