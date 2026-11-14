class_name GroundItem
extends RefCounted
## One item on the ground (items I6, docs/milestones/items.md, "The ground"): a row of the Items
## area (gameplay/items/items.gd). Its number (handed out once a run, never again), where it lies
## and its stack. Not a body: nothing hits, pushes or is blocked by it. State, walked and
## snapshotted member by member (core/sim/README.md); `new()` with no arguments makes a blank one.

## Its number on the ground (`ground_item_changed`, `item_take_requested` name it).
var number: int = -1
## Where it lies, in room pixels.
var at: Vector2 = Vector2.ZERO
## What it is (one copy: no piles on the ground, owner 2026-11-13).
var stack: ItemStack = null
## The name it is shown by while it lies there: a premade staff's own (`StaffItem.shown_name`);
## empty: its content's.
var title: String = ""


## A row numbered `of_number` holding `of_stack` at `where`, shown as `shown` (empty: its content's).
static func make(of_number: int, where: Vector2, of_stack: ItemStack, shown: String = "") -> GroundItem:
	var made := GroundItem.new()
	made.number = of_number
	made.at = where
	made.stack = of_stack
	made.title = shown
	return made
