class_name FormBase
extends SpellComponent
## A carrier (bolt, beam, nova, rune, orbit, dash, teleport, ...): what leaves the caster
## and ends a group when a staff is read (docs/milestones/M2-staffs.md). It sets the base
## numbers the infusions and modifiers before it then change. The class keeps its old name,
## `FormBase`, and its kind `&"form"`.

## Staff animations (`staff_pose`): the phases a key can be in, the eases into a key, the moods
## a key can show on the staff's face (its brows), the channels a key moves and the numbers each
## key is packed into for playing (`packed_pose`: phase, at, the CHANNELS, ease, mood).
const POSE_PHASES: Dictionary = {"wind": 0, "strike": 1, "hold": 2, "after": 3}
const POSE_EASES: Dictionary = {"inout": 0, "out": 1, "in": 2}
const POSE_MOODS: Array[StringName] = [&"raised", &"angry", &"furious", &"worried"]
const POSE_CHANNELS: Array[String] = ["turn", "lift", "push", "glow", "stretch", "shake", "land"]
## Where each number is in a packed key, and how many a key has.
const PK_PHASE: int = 0
const PK_AT: int = 1
const PK_CHANNELS: int = 2
const PK_EASE: int = 9
const PK_MOOD: int = 10
const POSE_STRIDE: int = 11
## The ranges of the channels a key may set (`turn` in degrees, `lift`, `push` and `shake` in
## pixels, `glow` and `land` 0 to 1, `stretch` as a share: 0.3 is 30% longer along the aim and thinner
## across).
const POSE_RANGES: Dictionary = {
	"turn": Vector2(-720.0, 720.0), "lift": Vector2(-6.0, 16.0), "push": Vector2(-12.0, 12.0),
	"glow": Vector2(0.0, 1.0), "stretch": Vector2(-0.5, 1.0), "shake": Vector2(0.0, 4.0),
	"land": Vector2(0.0, 1.0),
}


## Damage of one hit before the element and modifiers. It may be below 1 (an atom's speck):
## health is decimal, so a 0.3 hit takes 0.3 of it.
@export var base_damage: float = 1.0
## Mana taken per cast.
@export var mana_cost: float = 0.0
## Seconds before the same player can cast this spell again. There is no separate cast
## time: the cooldown is the cast time.
@export var cooldown: float = 0.5
## Pixels per second. Ignored by STILL and RAY.
@export var speed: float = 0.0
## Seconds a shot lives. For RAY, how long the beam stays on (it hits every `SpellLimits.BEAM_TICK`).
@export var lifetime: float = 1.0
## Hit circle of one shot in pixels. For RAY, the half-width of the beam.
@export var radius: float = 4.0
## Shots per cast before modifiers (a nova has many, a bolt one).
@export var shots: int = 1
## Angle in degrees the shots are spread over (360 for a full ring).
@export_range(0.0, 360.0) var spread: float = 0.0
## What it fires: the id of its carrier (`core/spells/carriers/`, docs/CARRIERS.md): &"atom" (the
## atom, bolt and nova), &"rune",
## &"orbit", &"beam", &"dash", &"teleport", &"swap", &"wall", &"rain", &"decoy",
## &"familiar", &"swing" or &"slam". The carrier decides what every other card does on it.
@export var carrier: StringName = &"atom"
## Extra targets each shot passes through before it ends.
@export var pierce: int = 0
## ORBIT only: distance from the caster in pixels.
@export var orbit_radius: float = 0.0
## RAY and RAIN: how far it reaches in pixels. DASH and TELEPORT: how far the caster
## moves (fixed: speed only changes how long a dash takes).
@export var ray_length: float = 0.0
## SWING: degrees the sweep hits over, centred on the aim.
@export var arc: float = 0.0
## SWING: seconds the staff leans back before it sweeps (none when it chains straight on from
## the last swing, `SpellLimits.SWING_CHAIN`). SLAM: seconds it rises before it strikes.
@export var wind_up: float = 0.0
## How the staff moves when this carrier is cast (its look only; a wizard's own cast, not a payload's):
## keys, each a dictionary, played in order from the staff's pose at the cast (rest, or where the
## last animation had it) and back on the aim after the last. A key says when, as `phase` and `at`:
##   "wind"    `at` 0 to 1 of the carrier's `wind_up`
##   "strike"  `at` 0 to 1 of its strike, the carrier's own working time: a swing's sweep, a slam's
##             ring, a beam's, orbit's, rain's or dash's life (a held one's until its last shot ends);
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
## carrier strikes, a slam's impact; nothing for a carrier that names none); the `ease` into it ("inout", "out" slowing into it, "in" speeding up into it) and a
## `mood` the face shows from then on (POSE_MOODS). Ranges in POSE_RANGES; the validator checks it.
## Example: [{"phase": "after", "at": 0.04, "push": -3, "ease": "out"}, {"phase": "after", "at": 0.2}].
@export var staff_pose: Array[Dictionary] = []

## `staff_pose` packed into numbers for playing (POSE_STRIDE a key), made once.
var _packed_pose: PackedFloat32Array = PackedFloat32Array()
var _pose_packed: bool = false
## Knockback of one hit in pixels per second; 0 for the usual `SpellLimits.KNOCKBACK`.
@export var knockback: float = 0.0
## How this carrier looks as it is cast (staffs B6b; `gameplay/feel` reads it, and an empty one
## gets the plain muzzle flash). Keys, all optional (CAST_LOOK_KEYS): the flash on the wizard's
## staff, its `seconds` and `size` (0.5 is the plain one, up to 1.5), and a ring with it when `ring`
## is true, gathering in for a negative `grow`, else flashing out; and `cue`, the id of a cue
## (`content/cues`) Feel plays where the carrier shows itself (`form_shown`, whoever casts it: a
## nova's ring, a rain's telegraph, where a teleport leaves, each end of a swap's trade, a decoy or
## familiar appearing), as big as the event's `length`.
@export var cast_look: Dictionary = {}
## How it looks where it ends or hits (IMPACT_LOOK_KEYS): the flare's `size` (an empty one gets the
## wall spark) and `ring`, and `cue`, a cue Feel plays where it ends on no body: a shot's end, as big
## as its `radius`, and where a carrier with no shot ends (`carrier_ended`: a teleport or dash
## landing, a rain falling, a slam's strike, a decoy or familiar going), as big as that event says.
## A new carrier brings its looks in its own `.tres`; Feel's preset has none of them.
@export var impact_look: Dictionary = {}
## What its shots are drawn as: `&""` for their motion's own body (a flying shot a bolt with its
## tail, a still one a rune's diamond, an orbiting one an orbit shot), or a still body of its own for
## a still shot: `&"stone"`, a standing ward stone (a wall's). One of SHOT_BODIES; a body its shots'
## motion does not draw is left out. A new body is a kind in the shot shaders (core/README.md, "The
## shot shaders") and a name here.
@export var shot_body: StringName = &""
const SHOT_BODIES: Array[StringName] = [&"", &"stone"]
## The keys each look may have (`look_problems`).
const CAST_LOOK_KEYS: Array[String] = ["seconds", "size", "ring", "grow", "cue"]
const IMPACT_LOOK_KEYS: Array[String] = ["size", "ring", "cue"]


func kind() -> StringName:
	return &"form"


## What is wrong with its looks, one line each (empty when nothing is): a key no look reads, or a
## cue that is no name.
func look_problems() -> PackedStringArray:
	var found := PackedStringArray()
	for pair: Array in [["cast_look", cast_look, CAST_LOOK_KEYS], ["impact_look", impact_look, IMPACT_LOOK_KEYS]]:
		var look: Dictionary = pair[1]
		for key: Variant in look.keys():
			if not (pair[2] as Array[String]).has(str(key)):
				found.append("%s: %s has the key '%s', which nothing reads (%s)" % [id, pair[0], key, pair[2]])
		if look.has("cue") and typeof(look["cue"]) != TYPE_STRING_NAME:
			found.append("%s: %s's cue should be a cue id (&\"name\")" % [id, pair[0]])
	if not SHOT_BODIES.has(shot_body):
		found.append("%s: shot_body '%s' is not one of %s" % [id, shot_body, SHOT_BODIES])
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


## True for the carriers that read a payload of their own, as a trigger does (a rain; a familiar
## casts only what its triggers give it, rules R4 F3).
func carries_payload() -> bool:
	return Carriers.of(carrier).has(Carrier.CARRIES_PAYLOAD)


func ranges() -> Dictionary:
	var limits: Dictionary = super()
	limits.merge({
		"base_damage": Vector2(0.05, 200),
		"mana_cost": Vector2(0.0, 100.0),
		"cooldown": Vector2(0.0, 10.0),
		"speed": Vector2(0.0, 2000.0),
		"lifetime": Vector2(0.05, 20.0),
		"radius": Vector2(1.0, 64.0),
		"shots": Vector2(1, 24),
		"spread": Vector2(0.0, 360.0),
		"pierce": Vector2(0, 16),
		"orbit_radius": Vector2(0.0, 256.0),
		"ray_length": Vector2(0.0, 1024.0),
		"arc": Vector2(0.0, 360.0),
		"wind_up": Vector2(0.0, 2.0),
		"knockback": Vector2(0.0, 2000.0),
	})
	return limits


## The ranges, and a carrier id that names no carrier.
func range_problems() -> PackedStringArray:
	var problems: PackedStringArray = super()
	if not Carriers.exists(carrier):
		problems.append("carrier: %s is no carrier (one of %s)" % [carrier, ", ".join(Carriers.ids())])
	return problems
