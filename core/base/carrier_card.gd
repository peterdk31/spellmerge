class_name CarrierCard
extends SpellComponent
## A carrier (bolt, beam, rune, dash, teleport, ...): what leaves the caster
## and ends a group when a staff is read (docs/milestones/M2-staffs.md). It sets the base
## numbers the infusions and modifiers before it then change. The class keeps its old name,
## `CarrierCard`, and its kind `&"carrier"`.

## Staff animations (`staff_pose`): the phases a key can be in, the eases into a key, the moods
## a key can show on the staff's face (its brows), the channels a key moves and the numbers each
## key is packed into for playing (`packed_pose`: phase, at, the CHANNELS, ease, mood).
const POSE_PHASES: Dictionary = {"wind": 0, "strike": 1, "hold": 2, "after": 3}
const POSE_EASES: Dictionary = {"inout": 0, "out": 1, "in": 2, "slam": 3}
const POSE_MOODS: Array[StringName] = [&"raised", &"angry", &"furious", &"worried"]
const POSE_CHANNELS: Array[String] = ["turn", "lift", "push", "glow", "stretch", "shake", "land", "hammer"]
## Where each number is in a packed key, and how many a key has.
const PK_PHASE: int = 0
const PK_AT: int = 1
const PK_CHANNELS: int = 2
const PK_EASE: int = 10
const PK_MOOD: int = 11
const POSE_STRIDE: int = 12
## The ranges of the channels a key may set (`turn` in degrees, `lift`, `push` and `shake` in
## pixels, `glow`, `land` and `hammer` 0 to 1, `stretch` as a share: 0.3 is 30% longer along the aim
## and thinner across).
const POSE_RANGES: Dictionary = {
	"turn": Vector2(-720.0, 720.0), "lift": Vector2(-6.0, 16.0), "push": Vector2(-12.0, 12.0),
	"glow": Vector2(0.0, 1.0), "stretch": Vector2(-0.5, 1.0), "shake": Vector2(0.0, 4.0),
	"land": Vector2(0.0, 1.0), "hammer": Vector2(0.0, 1.0),
}


## Damage of one hit before the element and modifiers. It may be below 1 (an atom's speck):
## health is decimal, so a 0.3 hit takes 0.3 of it.
@export var base_damage: float = 1.0
## Mana taken per cast.
@export var mana_cost: float = 0.0
## Seconds the staff is busy after this carrier leaves (its wind-down; docs/milestones/
## cast-timing.md): a cast's wind-down is its own group's carriers' and multicast cards' added up;
## a payload's adds nothing, as no staff waits on it.
@export var wind_down: float = 0.5
## Pixels per second. Ignored by STILL and RAY.
@export var speed: float = 0.0
## Seconds a shot lives. For RAY, how long the beam stays on (it hits every `SpellLimits.BEAM_TICK`).
@export var lifetime: float = 1.0
## Hit circle of one shot in pixels. For RAY, the half-width of the beam.
@export var radius: float = 4.0
## Shots per cast before modifiers (a bolt has one; split and other cards add more).
@export var shots: int = 1
## Angle in degrees the shots are spread over (360 for a full ring).
@export_range(0.0, 360.0) var spread: float = 0.0
## What it fires: the id of its carrier (`core/spells/carriers/`, docs/CARRIERS.md): &"atom" (the
## atom and bolt), &"rune",
## &"beam", &"dash", &"teleport", &"swap", &"wall", &"decoy",
## &"familiar", &"swing" or &"slam". The carrier decides what every other card does on it.
@export var carrier: StringName = &"atom"
## Extra targets each shot passes through before it ends.
@export var pierce: int = 0
## RAY: how far it reaches in pixels. DASH and TELEPORT: how far the caster
## moves (fixed: speed only changes how long a dash takes).
@export var ray_length: float = 0.0
## SWING: degrees the sweep hits over, centred on the aim.
@export var arc: float = 0.0
## Seconds a cast of it winds up before it leaves (docs/milestones/cast-timing.md): the staff's
## pose winds, the aim follows the caster, then the carrier leaves and strikes at once. A swing
## leans back, a slam rises; most carriers have none. A payload winds up where its trigger fired.
@export var wind_up: float = 0.0
## How the staff moves when this carrier is cast (its look only; a wizard's own cast, not a payload's):
## keys, each a dictionary, played in order from the staff's pose at the cast (rest, or where the
## last animation had it) and back on the aim after the last. A key says when, as `phase` and `at`:
##   "wind"    `at` 0 to 1 of the carrier's `wind_up`
##   "strike"  `at` 0 to 1 of its strike, the carrier's own working time: a swing's sweep, a slam's
##             ring, a beam's or dash's life (a held one's until its last shot ends);
##             the others have none, so their strike keys pass at once
##   "hold"    `at` in seconds; these keys repeat for as long as the strike lasts (a held beam
##             straining), each round from the last of them
##   "after"   `at` in seconds after the strike
## and where the staff is then, every channel it leaves out at rest (0): `turn` (degrees off the aim
## locked at the cast: for a swing the way it swings, a backhand the other way; for the others
## negative lifts the head toward the top of the screen whichever way it faces), `lift` (pixels up
## off its hover; its shadow stays on the floor), `push` (pixels along the aim; negative draws it
## back), `glow` (0 to 1: light round the staff in its infusion's colour, else its player's),
## `stretch` (longer along the aim and thinner across, negative squashed), `shake` (pixels of
## jitter) and `land` (0 to 1: how far the staff is moved so its drawn tip lies on the point its
## carrier strikes, a slam's impact; nothing for a carrier that names none), `hammer` (0 to 1: how far
## the staff's head has turned into a hammer's, which grows out of it and goes back into it; a
## wizard's staff only, `StaffLook`; as big as its cards grew the spell, so a bigger card grows it); the
## `ease` into it ("inout", "out" slowing into it, "in" speeding up into it, "slam" barely moving at
## first and then whipping into it: a heavy blow coming down) and a
## `mood` the face shows from then on (POSE_MOODS). Ranges in POSE_RANGES; the validator checks it.
## Example: [{"phase": "after", "at": 0.04, "push": -3, "ease": "out"}, {"phase": "after", "at": 0.2}].
@export var staff_pose: Array[Dictionary] = []

## `staff_pose` packed into numbers for playing (POSE_STRIDE a key), made once.
var _packed_pose: PackedFloat32Array = PackedFloat32Array()
var _pose_packed: bool = false
## Knockback of one hit in pixels per second; 0 for the usual `SpellLimits.KNOCKBACK`.
@export var knockback: float = 0.0
## The cues this carrier plays at its moments (`content/cues/`, by id; `gameplay/feel` plays them,
## docs/milestones/spell-spectacle-2.md, S6 2), so how a carrier looks is cue files, not keys of its
## own: `cast_cue` on its caster's staff when a seat casts it (`spell_cast`: the flash, a ring with
## it, the camera kicked back; `cast` when not given); `shown_cue` where the carrier shows itself
## (`carrier_shown`, whoever casts it: where a teleport leaves, each
## end of a swap's trade, a decoy or familiar appearing), as big as the event's `length`; `impact_cue`
## where its shots strike, on a body or a wall (`projectile_impact`: the flare in the shot's colours
## and cards; `impact` when not given), as big as its `radius`; and `end_cue` where a carrier with no
## shot ends (`carrier_ended`: a teleport or dash landing, a slam's strike, a decoy or
## familiar going), as big as that event says; `wind_cue` while a cast of it winds up (`cast_winding`:
## an enemy's telegraph, only for a caster not on the players' team; its `size` the wind-up's
## seconds; `wind`, a lane along the aim, when not given; docs/milestones/cast-timing.md, T6b).
## Empty plays nothing there. A new carrier names its cues in its own `.tres`; Feel's preset has none
## of them.
@export var cast_cue: StringName = &"cast"
@export var shown_cue: StringName = &""
@export var impact_cue: StringName = &"impact"
@export var end_cue: StringName = &""
@export var wind_cue: StringName = &"wind"
## The shader that draws its carrier's look, whichever area draws it (`Carrier.look_drawer`;
## docs/milestones/card-looks.md): null for that area's plain one in core (a flying shot a bolt's
## head, a still one the plain still quad), or a canvas-item shader of the card's own, in its folder.
## For a still carrier it draws one quad a shot (each stone of a solid one) from the projectile
## manager's instance data (a wall's `stone.gdshader`, a pool's `pool.gdshader`: copy
## `carriers/pool/pool.gdshader`); for one that flies or orbits it places a shot's head from its
## instance as `shot_head.gdshader` does (include `core/projectiles/shot_head.gdshaderinc`, as the
## bolt's `bolt.gdshader` does, or copy it). The manager gives it
## a pair of batches of its own (`ProjectileManager.register_body`; every card may have its own) and
## the shader warm-up compiles it before the first room (core/README.md, "The shot shaders").
@export var look_shader: Shader = null
## How bright its carrier lights the room (Feel's spell light), times what that area gives any
## shot of its size (docs/milestones/card-looks.md, phase 1b): 1 as today, 0 lights nothing, at most
## 2. A plain number, like the speed curve: the atom's is lower than the bolt's.
@export var look_light_intensity: float = 1.0
## How far its carrier's light reaches, times what its size gives (a shot's `SHOT_REACH` and zoom,
## a still one's quad): 1 as today, from 0.25 to 2.
@export var look_light_reach: float = 1.0
## The motes its carrier's still shots give off all the time while they stand (the owner,
## 2026-11-09: "use motes for everything you can", the world's magic building blocks): one
## `CardMoteStream` a stream (its kind, rate, where it leaves from in `look_shape`, how high, from
## when, how far apart), as many as its look needs (a rune's drips and the motes rising off its
## ring). Fewer while it comes and as it goes (`look_open`, `look_fade`). Feel gives them off
## (`gameplay/feel/still_motes.gd`) in the shot's colours, its infusions in turn, a share of them its
## infusions' own kinds. Empty for none.
@export var look_motes: Array[CardMoteStream] = []
## The shape of a still card's look, in its hit size as drawn (`ProjectileManager.STILL_HIT` of its
## quad): an oval's half width and half depth (a pool, seen at a slant), or a piece's half span of
## its row and its seam's depth below its middle (a wall). Its look shader reads it as the uniform
## `look_shape` (`ProjectileManager.set_body_shape`) and its motes leave from it, so the two never
## part.
@export var look_shape: Vector2 = Vector2(1.0, 1.0)
## Seconds a still card's look takes to open once placed, and the seconds of its end it fades over
## (at most `ProjectileManager.STILL_START` and `STILL_END`: its still clock tells no more). Its look
## shader reads them as the uniform `look_clock` (x open, y fade) when it draws its own coming and
## going by them (a wall's seam), and its motes come in and thin with them.
@export var look_open: float = 0.3
@export var look_fade: float = 0.8
## The old names of renamed look fields this card was loaded with (`_set`), each still taken (a
## `shot_shader` is its `look_shader`), and named by `look_problems` so the card is fixed.
var _renamed: PackedStringArray = PackedStringArray()


func kind() -> StringName:
	return &"carrier"


## A field this card's `.tres` sets that no longer exists: `shot_shader`, renamed `look_shader`
## (docs/milestones/card-looks.md), is taken as it and remembered for `look_problems`, so a card
## written before the rename (or a branch) never loads clean and draws plain in silence.
func _set(property: StringName, value: Variant) -> bool:
	if property == &"shot_shader":
		look_shader = value as Shader
		if not _renamed.has("shot_shader"):
			_renamed.append("shot_shader")
		return true
	return false


## Its cues and how big its impact cue plays, for looks (`gameplay/feel`, which reads no spell
## field): [cast_cue, shown_cue, impact_cue, end_cue, radius, wind_cue]. A new Array each call.
func look_cues() -> Array:
	return [cast_cue, shown_cue, impact_cue, end_cue, radius, wind_cue]


## What is wrong with its looks, one line each (empty when nothing is): a look shader that is not
## a canvas-item shader, one its carrier never draws, an old field name, motes never given off. Whether the cues it names exist is the registry's to say
## (tests/content/spells/test_carrier_looks.gd).
func look_problems() -> PackedStringArray:
	var found := PackedStringArray()
	for name: String in _renamed:
		found.append("%s: `%s` was renamed `look_shader`: rename it in the card's .tres" % [id, name])
	if look_shader != null and look_shader.get_mode() != Shader.MODE_CANVAS_ITEM:
		found.append("%s: look_shader '%s' is not a canvas_item shader" % [id, look_shader.resource_path])
	if look_shader != null and Carriers.exists(carrier) and Carriers.of(carrier).look_drawer() == Carrier.LOOK_NONE:
		found.append("%s: look_shader '%s' is never drawn: its carrier `%s` has no look of its own (Carrier.look_drawer)" % [id, look_shader.resource_path, carrier])
	if not look_motes.is_empty() and Carriers.exists(carrier) and (Carriers.of(carrier).look_drawer() != Carrier.LOOK_STILL or look_shader == null):
		found.append("%s: look_motes are never given off: only a still carrier's shots drawn by a look_shader of the card's own give them off" % id)
	for stream: CardMoteStream in look_motes:
		if stream == null:
			found.append("%s: an empty look mote stream" % id)
		else:
			found.append_array(stream.problems(id))
	if look_shape.x <= 0.0 or look_shape.y < 0.0:
		found.append("%s: look_shape %s has no size: its width must be above 0 and its depth not below" % [id, look_shape])
	if look_open < 0.0 or look_fade < 0.0:
		found.append("%s: look_open %s and look_fade %s are seconds, never below 0" % [id, look_open, look_fade])
	return found


## True when its staff animation lands the staff on the point its carrier strikes (a key with a
## `land`): what the alignment checks cast (docs/CARRIERS.md, "Lining a staff animation up with its
## look").
func lands() -> bool:
	for key: Dictionary in staff_pose:
		if float(key.get("land", 0.0)) > 0.0:
			return true
	return false


## `staff_pose` as numbers, POSE_STRIDE a key (phase, at, the POSE_CHANNELS, ease, mood: 0 for
## none, else 1 + its place in POSE_MOODS), made the first time it is asked for. A key with a
## name it does not know packs as rest (the validator reports it).
func packed_pose() -> PackedFloat32Array:
	if _pose_packed:
		return _packed_pose
	_pose_packed = true
	_packed_pose = pack_pose(staff_pose)
	return _packed_pose


static func pack_pose(keys: Array[Dictionary]) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(keys.size() * POSE_STRIDE)
	for n in keys.size():
		var key: Dictionary = keys[n]
		var at: int = n * POSE_STRIDE
		out[at + PK_PHASE] = float(POSE_PHASES.get(key.get("phase", "after"), POSE_PHASES["after"]))
		out[at + PK_AT] = float(key.get("at", 0.0))
		for c in POSE_CHANNELS.size():
			out[at + PK_CHANNELS + c] = float(key.get(POSE_CHANNELS[c], 0.0))
		out[at + PK_EASE] = float(POSE_EASES.get(key.get("ease", "inout"), 0))
		out[at + PK_MOOD] = float(POSE_MOODS.find(StringName(str(key.get("mood", "")))) + 1)
	return out


func ranges() -> Dictionary:
	var limits: Dictionary = super()
	limits.merge({
		"base_damage": Vector2(0.05, 200),
		"mana_cost": Vector2(0.0, 100.0),
		"wind_down": Vector2(0.0, 10.0),
		"speed": Vector2(0.0, 2000.0),
		"lifetime": Vector2(0.05, 20.0),
		"radius": Vector2(1.0, 64.0),
		"shots": Vector2(1, 24),
		"spread": Vector2(0.0, 360.0),
		"pierce": Vector2(0, 16),
		"ray_length": Vector2(0.0, 1024.0),
		"arc": Vector2(0.0, 360.0),
		"wind_up": Vector2(0.0, 2.0),
		"knockback": Vector2(0.0, 2000.0),
		"look_light_intensity": Vector2(0.0, 2.0),
		"look_light_reach": Vector2(0.25, 2.0),
	})
	return limits


## The ranges, and a carrier id that names no carrier.
func range_problems() -> PackedStringArray:
	var problems: PackedStringArray = super()
	if not Carriers.exists(carrier):
		problems.append("carrier: %s is no carrier (one of %s)" % [carrier, ", ".join(Carriers.ids())])
	return problems
