// SPDX-License-Identifier: GPL-3.0-or-later
shader_type canvas_item;

// One view of the split screen shown in its cell (gameplay/feel/split_screen.gd; connected biomes
// CB6, docs/milestones/connected-biomes.md): a rect over the whole screen, textured with the view,
// that keeps only the pixels nearer its own anchor than any other view's (its Voronoi cell: the
// same cut as `VoronoiCells.fill`, so the cells cover the screen, a pixel in exactly one, ties to
// the lower view) and draws the divider along each bisector, `divider_k` whole pixels across
// (counted along the line's steeper axis; the lower view's side takes the odd one), in the
// void's dark. A pixel is either the view's or the divider's: no blur. `SplitScreen.divider_pixels`
// is this rule on the CPU, for the tests.

// The screen's size (pixels), this view's anchor and up to four others' (screen pixels: the other
// views', and the equal split's blank quarter's, a site no view owns), how
// many others there are, which of them come before this view (a bit each: ties go to them), and
// the divider's width towards each (whole pixels; 0: none).
uniform vec2 screen_size = vec2(640.0, 360.0);
// Where the rect's top left is on the screen (screen pixels): a view draws only its cell's box
// (`SplitScreen.view_box`), so `screen_size` is the rect's size and this its corner.
uniform vec2 cell_origin = vec2(0.0);
uniform vec2 own = vec2(0.0);
uniform vec2 other_0 = vec2(0.0);
uniform vec2 other_1 = vec2(0.0);
uniform vec2 other_2 = vec2(0.0);
uniform vec2 other_3 = vec2(0.0);
uniform int others = 0;
uniform int before_mask = 0;
uniform float divider_0 = 0.0;
uniform float divider_1 = 0.0;
uniform float divider_2 = 0.0;
uniform float divider_3 = 0.0;
uniform vec4 divider_colour : source_color = vec4(0.05, 0.04, 0.09, 1.0);

void fragment() {
	// The pixel's middle, in screen pixels.
	vec2 p = (floor(UV * screen_size) + 0.5) + cell_origin;
	bool line = false;
	for (int k = 0; k < 4; k++) {
		if (k >= others) {
			break;
		}
		vec2 a = k == 0 ? other_0 : (k == 1 ? other_1 : (k == 2 ? other_2 : other_3));
		float width = k == 0 ? divider_0 : (k == 1 ? divider_1 : (k == 2 ? divider_2 : divider_3));
		vec2 normal = a - own;
		float length_of = length(normal);
		if (length_of < 0.0001) {
			continue;
		}
		vec2 unit = normal / length_of;
		float side = dot(p - (own + a) * 0.5, unit);
		bool before = ((before_mask >> k) & 1) != 0;
		if (side > 0.0 || (side == 0.0 && before)) {
			discard;
		}
		// Whole pixels from the line along its steeper axis (pixel middles are one apart there, so
		// the first pixel on this side is within 1, the second within 2, ...): this side draws its
		// share of the divider, the lower view the odd pixel, so the line is always `width` across.
		float steps = -side / max(abs(unit.x), abs(unit.y));
		float share = before ? floor(width * 0.5) : ceil(width * 0.5);
		// This side's pixels lie at `steps` d, d + 1, ...: from 0 on the side owning ties, past 0 on
		// the other.
		if (before ? steps <= share : steps < share) {
			line = true;
		}
	}
	COLOR = line ? divider_colour : texture(TEXTURE, UV);
}
