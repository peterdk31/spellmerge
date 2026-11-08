// SPDX-License-Identifier: GPL-3.0-or-later
shader_type canvas_item;
// world_vertex_coords: VERTEX is in the mark layer's own pixels in vertex() (the batch sits
// untransformed at its origin), so each stamp's quad is placed there by its row alone.
render_mode blend_mix, world_vertex_coords;

// Floor marks (gameplay/feel/marks.gd; docs/milestones/spell-spectacle.md, P2): the stamps of one
// frame, drawn once into the room's mark layer, a texture that is never cleared until the room
// ends. A stamp is a quad round its middle; its shape is worked out here from its kind's form
// and numbers at any size, one pixel a line however big. Pixels are hard (docs/STYLE.md): a pixel
// is its colour or nothing, never in between.
//
// Nothing here is a kind or a colour of its own:
// - the kinds are data (`MarkKind`, content/marks), handed over by marks.gd as `kind_form` (form:
//   0 blot, 1 crack, 2 rime, 3 ring, 4 rune, 5 speck; rough; fill; lines) and `kind_colour` (where
//   the body's colour comes from, 0 the floor, 1 what made it and 2 the surface, its shade, 0 base
//   and 1 shadow; the same for the edge);
// - the floor's colours are the room's own art (`floor_ramp`: light, base, shadow;
//   `RoomBase.floor_colors`), and none is drawn while they are unknown (`floor_known` 0);
// - a spell's colours are the shot's own ramp, picked by the shot shaders' `look_of` from its
//   core colour and its caster's ramp, as the motes pick theirs; a source from TABLE_SOURCE on (a
//   settled mote's from a surface) is a row of `ramp_table`, the motes' table;
// - a surface's colours (a dying body's own art, a room's walls) are a row of `ramp_table`, none
//   drawn when it has no such row (`table_rows`).
// Marks stay off the walls: `floor_mask` is the projectile manager's wall grid, one texel a
// `mask_cell` square from the layer's corner, white for a wall.
//
// A row (Marks.DRAW_STRIDE floats; the transform carries data, in full floats on every renderer):
//   MODEL_MATRIX[0].x   its radius (px); 0 for none (folded away)
//   MODEL_MATRIX[0].y   how far it is turned (radians)
//   MODEL_MATRIX[1].x   a seed (0-1)
//   MODEL_MATRIX[3].xy  its middle, in the layer's pixels
//   COLOR               its kind / KIND_CODE, its source / SOURCE_CODE (0-3 a hat ramp, 4 the
//                       enemies', +8 an exact colour; Motes.spell_source; from 16 a table row),
//                       its surface / SOURCE_CODE (a table row; below 16 none)
//   INSTANCE_CUSTOM     the core colour (a spell's)
// The colour and custom data are between 0 and 1 and need no more than bytes.

#include "res://core/projectiles/shot_palette.gdshaderinc"
// A mark is in one infusion's colours, as the mote it is of: its look is never woven.
#define LOOK_OWN_INFUSIONS
#include "res://core/projectiles/shot_look.gdshaderinc"

uniform vec4 kind_form[16];
uniform vec4 kind_colour[16];
uniform vec3 floor_ramp[3];
uniform float floor_known = 0.0;
uniform sampler2D floor_mask : filter_nearest;
uniform vec2 mask_size = vec2(1.0);
uniform float mask_cell = 8.0;
uniform sampler2D ramp_table : filter_nearest;
uniform float table_rows = 0.0;

// Marks.KIND_CODE, SOURCE_CODE, MAX_KINDS; Motes.EXACT_SOURCE.
const float KIND_CODE = 16.0;
const float SOURCE_CODE = 128.0;
const int MAX_KINDS = 16;
const float EXACT_SOURCE = 8.0;
const float TABLE_SOURCE = 16.0;
// A blot's solid share of its radius; a crack's crushed middle; a rime's crystal squares (px).
const float BLOT_CORE = 0.6;
const float CRACK_CRUSH = 0.2;
const float RIME_CELL = 5.0;
// A crack's line bends at a knot this many pixels apart, by up to this many pixels.
const float CRACK_KNOT = 4.0;
const float CRACK_BEND = 4.0;

varying flat vec2 k_centre;
varying flat float k_radius;
varying flat vec2 k_turn;
varying flat float k_seed;
varying flat vec4 k_form;
varying flat vec4 k_body;
varying flat vec4 k_edge;
varying vec2 k_px;

// Shade `shade` (0 base, 1 shadow) of the ramp table's row for `source`; alpha 0 for none.
vec4 mark_table(float source, float shade) {
	float row = source - TABLE_SOURCE;
	if (row < 0.0 || row >= table_rows) {
		return vec4(0.0);
	}
	return vec4(texelFetch(ramp_table, ivec2(shade < 0.5 ? 2 : 3, int(row)), 0).rgb, 1.0);
}

// Shade `shade` (0 base, 1 shadow) from `from` (0 the floor, 1 what made it, the spell of `source`
// with the core colour `c` or its table row, 2 the surface's table row); its alpha is 0 when it
// is not known.
vec4 mark_shade(float from, float shade, float source, float surface, vec3 c, float s) {
	if (from < 0.5) {
		return vec4(shade < 0.5 ? floor_ramp[1] : floor_ramp[2], floor_known);
	}
	if (from > 1.5) {
		return mark_table(surface, shade);
	}
	if (source >= TABLE_SOURCE) {
		return mark_table(source, shade);
	}
	bool exact = source >= EXACT_SOURCE;
	Look L = look_of(c, mod(source, EXACT_SOURCE), 1.0, vec3(0.0, 0.0, exact ? 128.0 : 0.0), s, false);
	return vec4(shade < 0.5 ? L.mid : L.lo, 1.0);
}

// A number in [0, 1) for this stamp from three numbers.
float mark_hash(float a, float b, float c) {
	return hash_seeded(a, b, c, k_seed * 97.0);
}

// How far in from its radius a ragged rim is at the angle `a` (0-1, times `rough`).
float mark_rim(float a) {
	float s = k_seed * TAU * 7.0;
	return 0.5 + 0.22 * sin(3.0 * a + s) + 0.16 * sin(5.0 * a + s * 1.7) + 0.12 * sin(11.0 * a + s * 2.3);
}

// 1 the body, 2 the edge, 0 nothing: a ragged patch, solid in its middle with pin-holes, its
// rim speckled, a few specks just past it.
int mark_blot(vec2 q, float r, float h) {
	float edge = k_radius * (1.0 - k_form.y * mark_rim(atan(q.y, q.x)));
	if (r > edge) {
		return (r < edge + 2.0 && h < 0.12 * k_form.z) ? 2 : 0;
	}
	float u = r / max(edge, 1.0);
	if (u < BLOT_CORE) {
		return h < 0.1 * u ? 0 : 1;
	}
	float t = (u - BLOT_CORE) / (1.0 - BLOT_CORE);
	float body = (1.0 - t) * 0.75;
	if (h < body) {
		return 1;
	}
	return h < body + k_form.z * 0.6 * (1.0 - 0.5 * t) ? 2 : 0;
}

// How far line `line` is bent across itself `along` pixels from its start.
float mark_jag(float along, float line) {
	float i = floor(along / CRACK_KNOT);
	float f = along / CRACK_KNOT - i;
	float a0 = mark_hash(i, line, 3.0) - 0.5;
	float a1 = mark_hash(i + 1.0, line, 3.0) - 0.5;
	return mix(a0, a1, f) * 2.0 * k_form.y * min(along * 0.35, CRACK_BEND);
}

// True when the point `q` is on line `line` from `from` at `angle`, `len` long, `width` pixels
// from its middle at most.
bool mark_on_line(vec2 q, vec2 from, float angle, float len, float line, float width) {
	vec2 dir = vec2(cos(angle), sin(angle));
	vec2 rel = q - from;
	float along = dot(rel, dir);
	if (along < 0.0 || along > len) {
		return false;
	}
	float across = dot(rel, vec2(-dir.y, dir.x));
	return abs(across - mark_jag(along, line)) <= width;
}

// 1 the body, 2 the edge, 0 nothing: jagged lines out of a crushed middle, each forking once.
int mark_crack(vec2 q, float r, float h) {
	if (r < k_radius * CRACK_CRUSH) {
		return h < 0.5 ? 1 : (h < 0.7 ? 2 : 0);
	}
	int n = int(k_form.w);
	for (int i = 0; i < 8; i++) {
		if (i >= n) {
			break;
		}
		float fi = float(i);
		float angle = (fi + mark_hash(fi, 1.0, 5.0) * 0.7) * TAU / float(n);
		float len = k_radius * (0.55 + 0.45 * mark_hash(fi, 2.0, 5.0));
		float width = r < k_radius * 0.45 ? 1.0 : 0.6;
		if (mark_on_line(q, vec2(0.0), angle, len, fi, width)) {
			return 1;
		}
		float fork_at = len * (0.4 + 0.25 * mark_hash(fi, 3.0, 5.0));
		vec2 dir = vec2(cos(angle), sin(angle));
		vec2 fork = dir * fork_at + vec2(-dir.y, dir.x) * mark_jag(fork_at, fi);
		float turn = (mark_hash(fi, 4.0, 5.0) < 0.5 ? -1.0 : 1.0) * (0.45 + 0.3 * mark_hash(fi, 5.0, 5.0));
		if (mark_on_line(q, fork, angle + turn, (len - fork_at) * 0.6, fi + 10.0, 0.6)) {
			return 1;
		}
	}
	return 0;
}

// 1 the body, 2 the edge, 0 nothing: a ragged patch of film specks thinning out to its rim,
// strewn with small crosses.
int mark_rime(vec2 pixel, vec2 q, float r, float h) {
	float edge = k_radius * (1.0 - k_form.y * mark_rim(atan(q.y, q.x)));
	if (r > edge) {
		return 0;
	}
	float u = r / max(edge, 1.0);
	vec2 cell = floor(pixel / RIME_CELL);
	vec2 at = cell * RIME_CELL + 1.0 + floor(vec2(mark_hash(cell.x, cell.y, 11.0), mark_hash(cell.x, cell.y, 13.0)) * (RIME_CELL - 2.0));
	if (mark_hash(cell.x, cell.y, 17.0) < k_form.z * (1.0 - 0.7 * u)) {
		vec2 d = abs(pixel - at);
		if ((d.x < 0.5 && d.y < 1.5) || (d.y < 0.5 && d.x < 1.5)) {
			return 2;
		}
	}
	return h < 0.45 * (1.0 - u) + 0.08 ? 1 : 0;
}

// 1 the body, 2 the edge, 0 nothing: a ragged band round the rim, specks thrown in and out of it.
int mark_ring(vec2 q, float r, float h) {
	float rim = k_radius * (1.0 - 0.5 * k_form.y * mark_rim(atan(q.y, q.x)));
	float band = max(2.0, k_radius * 0.14);
	float off = abs(r - rim);
	if (off < band * 0.5) {
		return h < 0.88 ? 1 : 0;
	}
	if (off < band * 1.6) {
		return h < k_form.z * 0.45 * (1.0 - (off - band * 0.5) / (band * 1.1)) ? 2 : 0;
	}
	return 0;
}

// 1 the body, 2 the edge, 0 nothing: a circle at the rim and one inside it, one pixel wide, with
// `lines` strokes between them, each a tick out from the inner circle with a hook at its end.
int mark_rune(vec2 q, float r, float h) {
	float outer = k_radius - 1.0;
	float inner = k_radius * 0.62;
	if (abs(r - outer) < 0.6) {
		return h < 0.9 ? 1 : 0;
	}
	if (abs(r - inner) < 0.6) {
		return h < 0.7 ? 2 : 0;
	}
	if (r < inner || r > outer) {
		return 0;
	}
	int n = int(k_form.w);
	float a = atan(q.y, q.x);
	for (int i = 0; i < 8; i++) {
		if (i >= n) {
			break;
		}
		float fi = float(i);
		float at = (fi + 0.5 * mark_hash(fi, 1.0, 7.0)) * TAU / float(n);
		float len = (outer - inner) * (0.45 + 0.4 * mark_hash(fi, 2.0, 7.0));
		vec2 dir = vec2(cos(at), sin(at));
		vec2 from = dir * inner;
		vec2 rel = q - from;
		float along = dot(rel, dir);
		float across = dot(rel, vec2(-dir.y, dir.x));
		if (along >= 0.0 && along <= len && abs(across) < 0.6) {
			return 1;
		}
		// The hook: a stroke across the tick's end, to one side.
		float side = mark_hash(fi, 3.0, 7.0) < 0.5 ? -1.0 : 1.0;
		float hook = max(2.0, len * 0.4);
		if (abs(along - len) < 0.6 && across * side >= 0.0 && abs(across) <= hook) {
			return 1;
		}
	}
	return 0;
}

void vertex() {
	float radius = MODEL_MATRIX[0].x;
	float turn = MODEL_MATRIX[0].y;
	float s = MODEL_MATRIX[1].x;
	vec2 centre = MODEL_MATRIX[3].xy;
	int k = clamp(int(floor(COLOR.r * KIND_CODE + 0.5)), 0, MAX_KINDS - 1);
	float source = floor(COLOR.g * SOURCE_CODE + 0.5);
	float surface = floor(COLOR.b * SOURCE_CODE + 0.5);
	vec2 corner = vec2(UV.x > 0.5 ? 1.0 : 0.0, UV.y > 0.5 ? 1.0 : 0.0);
	// An empty row has no radius: folded away.
	float reach = radius > 0.0 ? radius + 3.0 : 0.0;
	VERTEX = mix(centre - reach, centre + reach, corner);
	k_px = VERTEX;
	k_centre = centre;
	k_radius = radius;
	k_turn = vec2(cos(turn), sin(turn));
	k_seed = s;
	k_form = kind_form[k];
	k_body = mark_shade(kind_colour[k].x, kind_colour[k].y, source, surface, INSTANCE_CUSTOM.rgb, s);
	k_edge = mark_shade(kind_colour[k].z, kind_colour[k].w, source, surface, INSTANCE_CUSTOM.rgb, s);
}

void fragment() {
	vec2 pixel = floor(k_px);
	// Off the floor (a wall's cell, or past the layer): nothing.
	vec2 cell = floor(pixel / mask_cell);
	if (any(lessThan(cell, vec2(0.0))) || any(greaterThanEqual(cell, mask_size)) || texelFetch(floor_mask, ivec2(cell), 0).r > 0.5) {
		discard;
	}
	vec2 d = pixel + 0.5 - k_centre;
	vec2 q = vec2(k_turn.x * d.x + k_turn.y * d.y, -k_turn.y * d.x + k_turn.x * d.y);
	float r = length(q);
	float h = mark_hash(pixel.x, pixel.y, 7.0);
	int part = 0;
	if (k_form.x < 0.5) {
		part = mark_blot(q, r, h);
	} else if (k_form.x < 1.5) {
		part = mark_crack(q, r, h);
	} else if (k_form.x < 2.5) {
		part = mark_rime(pixel, q, r, h);
	} else if (k_form.x < 3.5) {
		part = mark_ring(q, r, h);
	} else if (k_form.x < 4.5) {
		part = mark_rune(q, r, h);
	} else {
		part = all(equal(pixel + 0.5, k_centre + 0.5)) ? 1 : 0;
	}
	vec4 c = part == 1 ? k_body : (part == 2 ? k_edge : vec4(0.0));
	if (c.a < 0.5) {
		discard;
	}
	COLOR = vec4(c.rgb, 1.0);
}
