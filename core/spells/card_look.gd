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
## The streams of motes its still shots give off while they stand (`CarrierCard.look_motes`, one
## `CardMoteStream` each; empty for none), in its `shape`. Shared with the card: never change them.
var motes: Array[CardMoteStream] = []
## The shape of its still look, in its hit size as drawn (`CarrierCard.look_shape`), and the seconds
## it takes to open and the seconds of its end it fades over (`look_open`, `look_fade`): what its
## shader draws by (`ProjectileManager.set_body_shape`) and its motes leave by. Its card's, from
## `from_card` (the card holds the defaults); nothing for a look of no card, which has no motes.
var shape: Vector2 = Vector2.ZERO
var open: float = 0.0
var fade: float = 0.0

## The look of a card with none of its own, or of an id that is no carrier card: drawn plain, lit
## as any. Shared.
static var PLAIN: CardLook = CardLook.new()


## The whole look of the carrier card `card`, made in one piece (Spells makes one per card and
## shares it): nothing is set on it after.
static func from_card(card: CarrierCard) -> CardLook:
	var look := of(card.look_shader, card.look_light_intensity, card.look_light_reach)
	look.motes = card.look_motes
	look.shape = card.look_shape
	look.open = card.look_open
	look.fade = card.look_fade
	return look


## A look of a shader and light only (no still motes; a test's stand-in for a card's).
static func of(look_shader: Shader, intensity: float, reach: float) -> CardLook:
	var look := CardLook.new()
	look.shader = look_shader
	look.light_intensity = intensity
	look.light_reach = reach
	return look
