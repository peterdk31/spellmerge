class_name PhaseLook
extends Resource
## How a boss looks in one of its phases (docs/milestones/M2-enemy-ai.md, "The enemy's data"): the
## body's sprite, the face and the size change; the scene stays.

## The body sprite (null: keep).
@export var texture: Texture2D = null
## The face style (`Face.Style` as a number; -1: keep).
@export var face_style: int = -1
## The eyes' glow (alpha 0: keep).
@export var glow: Color = Color(0.0, 0.0, 0.0, 0.0)
## The body's scale (0: keep).
@export var size: float = 0.0
