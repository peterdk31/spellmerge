// SPDX-License-Identifier: GPL-3.0-or-later
shader_type canvas_item;
// world_vertex_coords: the batch sits untransformed at the world's corner, so each tuft's quad is
// placed by its row alone.
render_mode blend_mix, world_vertex_coords;

// Ground cover (gameplay/feel/cover.gd; docs/milestones/ground-cover.md, rule 6): one batch a cover
// kind, one row a tuft, its frame a cell of the kind's sheet (`CoverKind.sheet`, frames side by side
// of `frame_size` along its top, the sheet `sheet_size`), the rows in drawing order (cover.gd). A
// tuft stands on its foot and sways in a slow wind from it: its tip moves by whole pixels (docs/STYLE.md: pixels are hard), its foot never. The wind rolls across the room as a wave,
// two slow sines so it never beats in step; its time is Feel's clock (`view_time`), a look's.
//
// Bodies bend it and trample it (GC4, look only: decision 4). Each frame Feel hands over the bodies
// nearest the camera (`bodies`, at most Cover.BODIES, `body_count` of them): a tuft within
// `bend_reach` of one leans its tip away from it and is pressed lower, the nearer the more. Feel's
// view grid of when each cell was last walked through (`trampled`, a float a cell, Feel's clock)
// flattens a cell's tufts while bodies walk it and for `trample_hold` seconds after, then lets them
// spring back over `trample_spring`: a tuft drawing a trampled frame (COLOR.r) swaps to it while
// more than half flat, one with none is pressed down by whole pixels. How far a tuft bends (its
// state's `bend`) scales both; a state that does not bend is never trampled.
//
// A row (Cover.STRIDE floats):
//   MODEL_MATRIX[0].x   1, or -1 for a tuft drawn mirrored
//   MODEL_MATRIX[3].xy  its foot, in world pixels
//   COLOR.r             its trampled frame + 1, / 255; 0 for none (pressed flat instead)
//   COLOR.a             1 shown; 0 not drawn (a state that draws no frame: folded away)
//   INSTANCE_CUSTOM     its frame / 255, its sway in pixels at its tip / SWAY_CODE, how far it bends
//                       (0-1), where in the sway it starts (0-1)
// The colour and custom data are between 0 and 1 and need no more than bytes. The colour is data
// only: the fragment draws the sheet's own colours.

uniform vec2 frame_size = vec2(16.0, 16.0);
uniform vec2 sheet_size = vec2(16.0, 16.0);
uniform float view_time = 0.0;
// The bodies bending it (Cover.BODIES at most) and how many there are.
uniform vec2 bodies[32];
uniform int body_count = 0;
// Cover's bend and trample numbers (Cover.BEND_REACH, BEND_PIXELS, TRAMPLE_HOLD, TRAMPLE_SPRING,
// FLATTEN), set once a batch.
uniform float bend_reach = 14.0;
uniform float bend_pixels = 4.0;
uniform float trample_hold = 0.6;
uniform float trample_spring = 1.5;
uniform float flatten = 0.5;
// Feel's view grid: when each cell (CoverLayout.CELL pixels) was last walked through.
uniform sampler2D trampled : filter_nearest;

// Cover.SWAY_CODE: the most a tuft sways, in pixels.
const float SWAY_CODE = 8.0;
// The wind: its two waves' speeds (radians a second) and how fast each rolls across the room
// (radians a pixel).
const float WIND_SLOW = 0.9;
const float WIND_FAST = 2.1;
const float ROLL_SLOW = 0.011;
const float ROLL_FAST = 0.027;
// CoverLayout.CELL: a cell's side in pixels; Cover.BODIES.
const float CELL = 16.0;
const int BODIES = 32;

void vertex() {
	vec2 foot = MODEL_MATRIX[3].xy;
	float flip = MODEL_MATRIX[0].x;
	float frame = floor(INSTANCE_CUSTOM.r * 255.0 + 0.5);
	float sway = INSTANCE_CUSTOM.g * SWAY_CODE;
	float bend = INSTANCE_CUSTOM.b;
	float start = INSTANCE_CUSTOM.a * 6.2831853;
	float trampled_frame = floor(COLOR.r * 255.0 + 0.5) - 1.0;
	// A vertex's UV is its corner of the unit quad: (0, 0) the top left, (1, 1) the bottom right.
	vec2 corner = UV;
	if (COLOR.a < 0.5) {
		VERTEX = vec2(0.0);
	} else {
		float wind = 0.7 * sin(view_time * WIND_SLOW - foot.x * ROLL_SLOW + start)
			+ 0.3 * sin(view_time * WIND_FAST - foot.y * ROLL_FAST + start * 2.0);
		float tip = 1.0 - corner.y;
		// Away from the bodies beside it, the nearer the more (at most a full bend).
		vec2 push = vec2(0.0);
		for (int i = 0; i < BODIES; i++) {
			if (i >= body_count) {
				break;
			}
			vec2 away = foot - bodies[i];
			float far = length(away);
			if (far < bend_reach) {
				push += (far > 0.5 ? away / far : vec2(flip, 0.0)) * (1.0 - far / bend_reach);
			}
		}
		float pushed = min(length(push), 1.0) * bend;
		vec2 lean = pushed > 0.0 ? normalize(push) * pushed * bend_pixels : vec2(0.0);
		// Walked through lately: flat, then springing back.
		float since = view_time - texelFetch(trampled, ivec2(floor(foot / CELL - vec2(0.0, 0.001))), 0).r;
		float lying = clamp(1.0 - (since - trample_hold) / max(trample_spring, 0.001), 0.0, 1.0) * bend;
		float lower = abs(lean.y) * 0.5;
		if (trampled_frame >= 0.0 && lying > 0.5) {
			frame = trampled_frame;
		} else {
			lower += lying * flatten * frame_size.y;
		}
		VERTEX = foot + vec2((corner.x - 0.5) * frame_size.x * flip + round((wind * sway + lean.x) * tip), (corner.y - 1.0) * frame_size.y + round(lower * tip));
	}
	// Exactly a frame of the sheet's top row, whatever the sheet's size (as the editor draws it).
	UV = (vec2(frame * frame_size.x, 0.0) + corner * frame_size) / max(sheet_size, vec2(1.0));
}

void fragment() {
	COLOR = texture(TEXTURE, UV);
}
