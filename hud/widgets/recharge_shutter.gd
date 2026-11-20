extends RefCounted
## How an item recharging after a use is drawn (the owner, 2026-11-20: an active relic's cooldown, on
## the corner panel's d-pad cross and the inventory's ring): a dark shutter over its icon, its
## height the part of the cooldown still left in whole pixel rows, sinking a row at a time as it
## recharges until the icon is whole again. **Smooth** (docs/STYLE.md): it steps by whole rows (an
## 8-pixel icon in 8 steps, a 16-pixel one in 16), never a fade or a partial pixel; a widget steps
## its drawn rows toward `rows` of what it was told (`item_recharging`, the simulation's own count at
## each sixteenth) a row a frame, so the shutter drops in over its rows too. Static only.
##
##     RechargeShutter.draw(self, icon_rect, drawn_rows)

## The shutter's colour: solid, so the rows are hard edges (no transparency, no fade).
const SHADE: Color = Color("#14121f")
## Its lower edge, one pixel, so a sinking shutter reads as one.
const EDGE: Color = Color("#7fd6f5")


## How many of `side` pixel rows are still shut with `left` seconds of `whole` left (0: ready).
static func rows(left: float, whole: float, side: int) -> int:
	if left <= 0.0 or whole <= 0.0:
		return 0
	return clampi(ceili(float(side) * minf(left / whole, 1.0) - 0.000001), 1, side)


## Draw `shut` rows of shutter over `rect` (an icon's, whole pixels) on `canvas`.
static func draw(canvas: CanvasItem, rect: Rect2, shut: int) -> void:
	shut = mini(shut, int(rect.size.y))
	if shut <= 0:
		return
	canvas.draw_rect(Rect2(rect.position, Vector2(rect.size.x, shut)), SHADE)
	canvas.draw_rect(Rect2(rect.position + Vector2(0.0, shut - 1), Vector2(rect.size.x, 1.0)), EDGE)
