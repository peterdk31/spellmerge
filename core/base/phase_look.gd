class_name PhaseLook
extends Resource
## How a boss looks in one of its phases (docs/milestones/M2-enemy-ai.md, "The enemy's data"): the
## body's sprite, the face and the size change; the scene stays.

## The body sprite (null: keep).
@export var texture: Texture2D = null
## The face style (`Face.Style` as a number; -1: keep).
@export var face_style: int = -1
## The row of the face's own art it shows from this phase on (`Face.art_row`, a face with a
## `FaceArt`: boss plan OB9, an angrier face for a later phase; -1: keep).
@export var face_row: int = -1
## The eyes' glow (alpha 0: keep).
@export var glow: Color = Color(0.0, 0.0, 0.0, 0.0)
## The body's scale (0: keep).
@export var size: float = 0.0
## A layered body's parts' art from this phase on (boss plan OB8): a texture by the part's node
## name (a `BodyPart` under the body's `Sprite`); a part not named keeps its art.
@export var parts: Dictionary[StringName, Texture2D] = {}
## Motes the body gives off from this phase on, following it (boss plan OB8: the burning head's
## sparks), from the part named `motes_on` (empty: the body's `Sprite`); null keeps the last.
@export var motes: MoteSource = null
@export var motes_on: StringName = &""
## A sound held while this phase lasts (boss plan OB15: the burning bristles' loop), looping from
## the body as it goes, until the next phase or the body is gone (Feel; empty: none, and the last
## phase's ends).
@export var sound: StringName = &""
## The cue played from the body as this phase starts (boss plan OB15: the broom's ignition; Feel,
## drawn only; empty: none).
@export var cue: StringName = &""
