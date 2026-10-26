extends "res://tests/support/screenshot.gd"
## The art of every card and the spell sprites on the crypt floor (`cards_sheet`), to look at
## against docs/STYLE.md. One row per kind (form, element, modifier, trigger, multicast), each
## card's 16x16 icon at 3x with the same icon at 1x beside it, as the builder shows it. The
## cards are the ones the registry found, so a new card adds itself. The bottom row is every
## sprite in art/vfx/ at 2x, with each again at 1x under it.

const KINDS: Array[StringName] = [&"form", &"element", &"modifier", &"trigger", &"multicast"]
const CELL := Vector2(72.0, 58.0)
## Where the cards start, right of the kind names.
const LEFT: float = 70.0
const VFX_TOP: float = 248.0
const VFX: Array[Texture2D] = [
	preload("res://art/vfx/bolt.svg"),
	preload("res://art/vfx/imp_fireball.svg"),
	preload("res://art/vfx/hit_spark.svg"),
	preload("res://art/vfx/telegraph_dash.svg"),
	preload("res://art/vfx/beam.svg"),
	preload("res://art/vfx/nova_ring.svg"),
	preload("res://art/vfx/rune.svg"),
	preload("res://art/vfx/orbit_orb.svg"),
]


func take() -> void:
	if not need(["Registry"]):
		return
	settle_frames = 10
	lay_floor()
	var by_kind: Dictionary = {}
	for card: Resource in root.get_node("Registry").call("get_all", &"spells"):
		if card is SpellComponent and (card as SpellComponent).icon != null:
			var kind: StringName = (card as SpellComponent).kind()
			if not by_kind.has(kind):
				by_kind[kind] = []
			(by_kind[kind] as Array).append(card)
	var kinds: Array[StringName] = []
	for kind: StringName in KINDS + by_kind.keys():
		if by_kind.has(kind) and not kinds.has(kind):
			kinds.append(kind)
	if kinds.is_empty():
		fail("the registry found no cards")
		return
	var per_row: int = floori((SCREEN.x - LEFT) / CELL.x)
	var y: float = 8.0
	for kind in kinds:
		label(String(kind), Vector2(8.0, y + 16.0))
		var cards: Array = by_kind[kind]
		for at in cards.size():
			if at > 0 and at % per_row == 0:
				y += CELL.y
			var icon: Texture2D = (cards[at] as SpellComponent).icon
			var x: float = LEFT + (at % per_row) * CELL.x
			place(icon, 3.0, Vector2(x, y))
			place(icon, 1.0, Vector2(x + 52.0, y + 32.0))
		y += CELL.y
	if y > VFX_TOP:
		fail("the cards run into the vfx row: split the sheet in two")
		return
	label("vfx", Vector2(8.0, VFX_TOP + 24.0))
	var x: float = LEFT
	for sprite: Texture2D in VFX:
		place(sprite, 2.0, Vector2(x, VFX_TOP))
		place(sprite, 1.0, Vector2(x + 16.0, VFX_TOP + 68.0))
		x += CELL.x
	await shot("cards_sheet")
