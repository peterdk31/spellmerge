extends RefCounted
## A scrolling window over a list of rows (M2, before a twelfth element or modifier). The quick
## view's and the overlay's drop lists show at most `QUICK_MAX_LINES` / `OVERLAY_MAX_LINES` lines
## at once; a longer list sits in a clipping `Control` (the window) and the list inside it slides
## up and down to keep the row UIFocus points at in view. Every row stays a visible control, so
## UIFocus walks all of them as before; only the list moves.
##
## The maths is here, static and free of layout, so it is the same for every player and a test
## can check it without a frame.

## The most lines of a list shown at once. The quick view has one row per line (11 fit its
## quarter of the screen); the overlay has two rows per line (6 lines).
const QUICK_MAX_LINES: int = 11
const OVERLAY_MAX_LINES: int = 6


## A clipping window of `width` that holds `content`. The content is placed by `apply`, so it
## must not be a container's child.
static func make_window(window_name: String, content: Control, width: float) -> Control:
	var window := Control.new()
	window.name = window_name
	window.clip_contents = true
	window.mouse_filter = Control.MOUSE_FILTER_IGNORE
	window.custom_minimum_size = Vector2(width, 0.0)
	window.add_child(content)
	return window


## The line the window starts at so `focused_line` is in view, moving as little as possible from
## `first_line`. `visible_lines` is how many lines fit; `total_lines` how many there are.
static func first_line_for(focused_line: int, first_line: int, visible_lines: int, total_lines: int) -> int:
	var last_first: int = maxi(total_lines - visible_lines, 0)
	var first: int = clampi(first_line, 0, last_first)
	if focused_line < first:
		first = focused_line
	elif focused_line >= first + visible_lines:
		first = focused_line - visible_lines + 1
	return clampi(first, 0, last_first)


## Size the window for `lines` lines of `step` px (at most `max_lines`) and slide `content` so
## line `first_line` is at the top.
static func apply(window: Control, content: Control, step: float, lines: int, max_lines: int, first_line: int) -> void:
	window.custom_minimum_size.y = float(mini(lines, max_lines)) * step
	content.position = Vector2(0.0, -float(first_line) * step)
