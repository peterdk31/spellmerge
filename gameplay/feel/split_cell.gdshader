// SPDX-License-Identifier: GPL-3.0-or-later
shader_type canvas_item;

// One view of the split screen shown in its cell (gameplay/feel/split_screen.gd; connected biomes
// CB6, docs/milestones/connected-biomes.md): a rect over the whole screen, textured with the view,
// that keeps only the pixels nearer its own anchor than any other view's (its Voronoi cell: the
// same cut as `VoronoiCells.fill`, so the cells cover the screen, a pixel in exactly one, ties to
// the lower view) and draws the divider along each bisector, `divider_k` whole pixels across
// (half on each side), in the void's dark. A pixel is either the view's or the divider's: no blur.

// The screen's size (pixels), this view's anchor and up to three others' (screen pixels), how
// many others there are, which of them come before this view (a bit each: ties go to them), and
// the divider's width towards each (whole pixels; 0: none).
uniform vec2 screen_size = vec2(640.0, 360.0);
uniform vec2 own = vec2(0.0);
uniform vec2 other_0 = vec2(0.0);
uniform vec2 other_1 = vec2(0.0);
uniform vec2 other_2 = vec2(0.0);
uniform int others = 0;
uniform int before_mask = 0;
uniform float divider_0 = 0.0;
uniform float divider_1 = 0.0;
uniform float divider_2 = 0.0;
uniform vec4 divider_colour : source_color = vec4(0.05, 0.04, 0.09, 1.0);

void fragment() {
	// The pixel's middle, in screen pixels.
	vec2 p = (floor(UV * screen_size) + 0.5);
	bool line = false;
	for (int k = 0; k < 3; k++) {
		if (k >= others) {
			break;
		}
		vec2 a = k == 0 ? other_0 : (k == 1 ? other_1 : other_2);
		float width = k == 0 ? divider_0 : (k == 1 ? divider_1 : divider_2);
		vec2 normal = a - own;
		float length_of = length(normal);
		if (length_of < 0.0001) {
			continue;
		}
		float side = dot(p - (own + a) * 0.5, normal / length_of);
		bool before = ((before_mask >> k) & 1) != 0;
		if (side > 0.0 || (side == 0.0 && before)) {
			discard;
		}
		if (-side < width * 0.5) {
			line = true;
		}
	}
	COLOR = line ? divider_colour : texture(TEXTURE, UV);
}
