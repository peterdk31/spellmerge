class_name LaunchLook
extends RefCounted
## What every shot of one launch is drawn as, handed to the projectile manager in one piece
## (`ProjectileManager.set_looks`): its core colour, its packed look kinds (`pack_look`), the card it
## is (its impacts are told as it), the card body it is drawn by (`register_body`; 0 for its motion's
## own) and how bright and how far it lights the room (its card's `look_light_intensity` and
## `look_light_reach`; docs/milestones/card-looks.md). Spells fills one and reuses it for every
## launch, so a launch allocates nothing; the manager copies what it needs into its slots.

## The core colour (a shot's first infusion's tint; white for a plain shot).
var core: Color = Color.WHITE
## The packed look kinds (`ProjectileManager.pack_look`; 0 for none).
var look: int = 0
## The id of the card it is (`&""` for none).
var carrier_card: StringName = &""
## The card body it is drawn by (`ProjectileManager.register_body`; 0 for its motion's own).
var body: int = 0
## How bright and how far it lights the room, times the shot light's own (1 as a plain shot).
var light_intensity: float = 1.0
var light_reach: float = 1.0
