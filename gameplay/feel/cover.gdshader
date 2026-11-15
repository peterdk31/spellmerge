// SPDX-License-Identifier: GPL-3.0-or-later
shader_type canvas_item;
// world_vertex_coords: the batch sits untransformed at the world's corner, so each tuft's quad is
// placed by its row alone.
render_mode blend_mix, world_vertex_coords;

// Ground cover (gameplay/feel/cover.gd; docs/milestones/ground-cover.md, rule 6): one batch a cover
// kind, one row a tuft, its frame a cell of the kind's sheet (`CoverKind.sheet`, frames side by side
// of `frame_size`). A tuft stands on its foot and sways in a slow wind from it: its tip moves by whole
// pixels (docs/STYLE.md: pixels are hard), its foot never. The wind rolls across the room as a wave,
// two slow sines so it never beats in step; its time is Feel's clock (`view_time`), a look's.
//
// A row (Cover.STRIDE floats):
//   MODEL_MATRIX[0].x   1, or -1 for a tuft drawn mirrored
//   MODEL_MATRIX[3].xy  its foot, in world pixels
//   COLOR.a             1 shown; 0 not drawn (a state that draws no frame: folded away)
//   INSTANCE_CUSTOM     its frame / 255, its sway in pixels at its tip / SWAY_CODE, how far it bends
//                       (0-1, for bodies going through: GC4), where in the sway it starts (0-1)
// The colour and custom data are between 0 and 1 and need no more than bytes.

uniform float frame_count = 1.0;
uniform vec2 frame_size = vec2(16.0, 16.0);
uniform float view_time = 0.0;

// Cover.SWAY_CODE: the most a tuft sways, in pixels.
const float SWAY_CODE = 8.0;
// The wind: its two waves' speeds (radians a second) and how fast each rolls across the room
// (radians a pixel).
const float WIND_SLOW = 0.9;
const float WIND_FAST = 2.1;
const float ROLL_SLOW = 0.011;
const float ROLL_FAST = 0.027;

void vertex() {
	vec2 foot = MODEL_MATRIX[3].xy;
	float flip = MODEL_MATRIX[0].x;
	float frame = floor(INSTANCE_CUSTOM.r * 255.0 + 0.5);
	float sway = INSTANCE_CUSTOM.g * SWAY_CODE;
	float start = INSTANCE_CUSTOM.a * 6.2831853;
	// A vertex's UV is its corner of the unit quad: (0, 0) the top left, (1, 1) the bottom right.
	vec2 corner = UV;
	if (COLOR.a < 0.5) {
		VERTEX = vec2(0.0);
	} else {
		float wind = 0.7 * sin(view_time * WIND_SLOW - foot.x * ROLL_SLOW + start)
			+ 0.3 * sin(view_time * WIND_FAST - foot.y * ROLL_FAST + start * 2.0);
		float tip = 1.0 - corner.y;
		VERTEX = foot + vec2((corner.x - 0.5) * frame_size.x * flip + round(wind * sway * tip), (corner.y - 1.0) * frame_size.y);
	}
	UV = vec2((frame + corner.x) / max(frame_count, 1.0), corner.y);
}

void fragment() {
	COLOR = texture(TEXTURE, UV);
}
