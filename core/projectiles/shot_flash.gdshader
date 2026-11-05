// SPDX-License-Identifier: GPL-3.0-or-later
shader_type canvas_item;
render_mode blend_premul_alpha;

// Feel's flashes (gameplay/feel/feel.gd, its flash batch and its floor batch; core/README.md, "The
// shot shaders"; docs/milestones/flash-kinds.md), in a square GRID x zoom pixels across, +x along
// their aim, all in the ramp and look of the shot they come from. Blending is premultiplied: a
// pixel is opaque, the glow round it light added to what is below.
//
// **Kinds are data:** each flash kind is a `FlashKind` file (content/flashes), a row of
// `flash_table` (`gameplay/feel/flash_table.gd` writes it; its layout is there): how it is drawn
// (D_*), its metric and salt, and its curves over its life. A row's kind is its table row, in the
// transform's first unused float (MODEL_MATRIX[2].x: full precision, where the custom data may be
// kept as half floats); its age the code beside its kind in the custom data (`coded_age`). So a new
// look is a new file and no edit here.
//   D_SHAPE    the parts its curves draw: a cross, a dotted disc, a fraying ring, a column of light,
//              a star, rays, a ring of dots, a spiral (the last four flash kinds F4)
//   D_CLOUDS   a staff's poof (living staffs H4): bone clouds along the staff (+x) that swell to
//              their biggest at 35% of the flash (where the body changes) and shrink away
//   D_CRACKS   the ground struck (Feel's floor batch, under the bodies): cracks out from the
//              impact, white-hot and cooling to dark stone; their reach is QUAKE_REACH x zoom pixels
// Every kind's glow comes from its curves. Lightning, statuses and explosions have shaders and
// batches of their own.
//
// No particles: a flash's sparks, rubble, dust and card particles are motes, thrown by the
// motes parts of the cue that shows it (content/cues; docs/milestones/spell-spectacle-2.md, S6
// item 3). This shader draws the flash's shape and its light only.
//
// A flash is one instance of a mesh of a few quads (`Feel.flash_mesh`), each told in its UV
// which QUAD KIND (Q_*) and slot it is. The vertex stage puts each quad round what it draws (in
// the flash's own pixels, so they turn with its aim), or folds it away; the fragment stage only
// colours a pixel of its own quad, in a few small modes with no loops:
//   Q_LIGHT     the flash's glow, over its whole square (added; drawn first)
//   Q_CLOUD     one of a poof's bone clouds; the first is on top
//   Q_SHAPE     the flash: a cross, a dotted disc, a fraying ring, a column (drawn last, on top);
//               the cracks
// The instance's square is drawn from the mesh's own corners: a pixel `d` (whole pixels from the
// middle; from where a dash left) is at UV (d + o) / size of the square, as a QuadMesh has it.

#include "res://core/projectiles/shot_palette.gdshaderinc"
#include "res://core/projectiles/shot_look.gdshaderinc"

// The kinds (FlashTable): a row a kind, TEXELS texels, RGBAF.
uniform sampler2D flash_table : filter_nearest;

const float GRID = 24.0;
// How a kind is drawn (FlashTable.DRAW_CODES).
const float D_SHAPE = 0.0;
const float D_CLOUDS = 1.0;
const float D_CRACKS = 2.0;
// The curves, in the table's order (FlashTable.CURVES), and the segments of each.
const int C_ARM = 0;
const int C_DISC = 1;
const int C_RING = 2;
const int C_COLUMN_WIDTH = 3;
const int C_COLUMN_TOP = 4;
const int C_COLUMN_FOOT = 5;
const int C_COLUMN_LENGTH = 6;
const int C_COLUMN_DOTTED = 7;
const int C_GLOW = 8;
const int C_GLOW_RING = 9;
const int C_GLOW_RING_REACH = 10;
const int C_GLOW_MIDDLE = 11;
const int C_GLOW_MIDDLE_REACH = 12;
const int C_FIRST = 13;
const int C_SECOND = 14;
const int C_STAR = 15;
const int C_RAYS = 16;
const int C_RAYS_INNER = 17;
const int C_DOTS = 18;
const int C_SPIRAL = 19;
const int C_SPIRAL_TURN = 20;
const int SEGMENTS = 4;
// The head texels of a row (its draw, metric, salt and spiral gap; its star's points, rays, dots
// and spiral arms), before its curves.
const int HEADS = 2;
// A quake's reach per zoom in pixels, its cracks, and how flat the floor is seen (y over x).
const float QUAKE_REACH = 8.0;
const float QUAKE_CRACKS = 7.0;
const float QUAKE_FLAT = 0.6;
// The quad kinds (FLASH_Q_* in gameplay/feel/feel.gd), in UV.y, and the slots of each.
const float Q_LIGHT = 0.0;
const float Q_CLOUD = 3.0;
const float Q_SHAPE = 4.0;
// The fragment's modes.
const float M_LIGHT = 0.0;
const float M_CLOUD = 2.0;
const float M_SHAPE = 3.0;
const float M_CRACK = 4.0;

// What the vertex stage hands a pixel (by mode; see `fragment`): where it is in the flash's
// pixels, the mode, five numbers and three colours.
varying vec2 px;
varying flat float mode;
varying flat vec4 v0;
varying flat vec4 v1;
varying flat vec4 v2;
varying flat vec4 v3;
varying flat vec4 v4;
varying flat vec4 c0;
varying flat vec4 c1;
varying flat vec4 c2;

// ---- Vertices ----

// Curve `c` of the kind in table row `row` at the age `a` and zoom `z` (FlashTable.value_at): the
// last of its segments started, `t` its way from its start to its end, eased by its way (0 linear,
// 1 out, 2 in, 3 hold), its pixels plus its steps of the zoom.
float curve(int row, int c, float a, float z) {
	int x = HEADS + c * SEGMENTS * 2;
	vec4 head = texelFetch(flash_table, ivec2(x, row), 0);
	vec4 values = texelFetch(flash_table, ivec2(x + 1, row), 0);
	for (int n = 1; n < SEGMENTS; n++) {
		vec4 next = texelFetch(flash_table, ivec2(x + n * 2, row), 0);
		if (next.x <= a) {
			head = next;
			values = texelFetch(flash_table, ivec2(x + n * 2 + 1, row), 0);
		}
	}
	float t = clamp((a - head.x) / max(head.y - head.x, 0.000001), 0.0, 1.0);
	float e = head.z > 2.5 ? 0.0 : (head.z > 1.5 ? t * t : (head.z > 0.5 ? 1.0 - (1.0 - t) * (1.0 - t) : t));
	return mix(values.x, values.z, e) + mix(values.y, values.w, e) * z;
}

// The shade `n` of look `L` (FlashTable.SHADE_CODES: 0 white-hot, 1 light, 2 base, 3 shadow; below
// 0 none, black).
vec3 shade_of(Look L, float n) {
	return n < -0.5 ? vec3(0.0) : (n < 0.5 ? L.hot : (n < 1.5 ? L.hi : (n < 2.5 ? L.mid : L.lo)));
}

void vertex() {
	int row = int(MODEL_MATRIX[2].x + 0.5);
	vec4 kind_head = texelFetch(flash_table, ivec2(0, row), 0);
	float draw = kind_head.x;
	float a = coded_age(coded_code(INSTANCE_CUSTOM.a));
	Look L = look_from_color(COLOR, INSTANCE_CUSTOM.rgb, float(INSTANCE_ID % 61) * 1.618, true);
	float z = L.zoom;
	float s = L.seed;
	bool poof = draw == D_CLOUDS;
	bool quake = draw == D_CRACKS;
	// The square in pixels, and where its pixel 0 is.
	vec2 size = vec2(GRID) * z;
	vec2 o = size * 0.5;
	// The mesh's vertex: its slot and corner in UV.x (slot + 0.25 or 0.75), its quad kind and
	// corner in UV.y (kind + 0.25 or 0.75).
	float slot = floor(UV.x);
	float quad = floor(UV.y);
	vec2 corner = vec2(fract(UV.x) > 0.5 ? 1.0 : 0.0, fract(UV.y) > 0.5 ? 1.0 : 0.0);
	vec2 q_lo = vec2(0.0);
	vec2 q_hi = vec2(0.0);
	bool shown = false;
	float m = M_SHAPE;
	vec4 a0 = vec4(0.0);
	vec4 a1 = vec4(0.0);
	vec4 a2 = vec4(0.0);
	vec4 a3 = vec4(-1.0);
	vec4 a4 = vec4(-1.0, 0.0, 0.0, 0.0);
	vec4 k0 = vec4(0.0);
	vec4 k1 = vec4(0.0);
	vec4 k2 = vec4(0.0);
	if (quad == Q_LIGHT || quad == Q_SHAPE) {
		// The flash and its light, from the kind's curves: a1 the light's two falloffs (how bright,
		// how far: x of the distance from a0.y, y of the distance), a0.x its metric (1 a diamond, 2
		// flat on the floor); a0.yzw the cross's arms, the dotted disc's and the ring's reach (below
		// 0 for none); a2 a column: its half width (below 0 for none), top, foot, and 1 when it is
		// dotted.
		float metric = kind_head.y;
		float salt = kind_head.z;
		float arm = round(curve(row, C_ARM, a, z));
		float disc = curve(row, C_DISC, a, z);
		float ring = curve(row, C_RING, a, z);
		float wide = curve(row, C_COLUMN_WIDTH, a, z);
		vec4 column = vec4(-1.0, 0.0, 0.0, 0.0);
		if (wide >= 0.0) {
			// The most it is long, from its foot (a falling streak), below 0 for none.
			float top = curve(row, C_COLUMN_TOP, a, z);
			float foot = curve(row, C_COLUMN_FOOT, a, z);
			float longest = curve(row, C_COLUMN_LENGTH, a, z);
			column = vec4(floor(wide + 0.5), longest >= 0.0 ? max(foot - longest, top) : top, foot, curve(row, C_COLUMN_DOTTED, a, z));
		}
		float k = curve(row, C_GLOW, a, z);
		vec4 lit = vec4(curve(row, C_GLOW_RING, a, z), curve(row, C_GLOW_RING_REACH, a, z), curve(row, C_GLOW_MIDDLE, a, z), curve(row, C_GLOW_MIDDLE_REACH, a, z));
		vec3 first = shade_of(L, curve(row, C_FIRST, a, z));
		vec3 second = shade_of(L, curve(row, C_SECOND, a, z));
		// The F4 parts: a star's reach, the rays' outer and inner ends, the dots' radius (a3); the
		// spiral's reach, its turn, its gap (times the zoom), and the counts packed (points + 16 rays + 512 arms; the
		// dots' count in a1.w). At most 15 points (FlashKind.MAX_POINTS 12) and 31 rays (MAX_RAYS).
		vec4 counts = texelFetch(flash_table, ivec2(1, row), 0);
		float rays = curve(row, C_RAYS, a, z);
		a3 = vec4(curve(row, C_STAR, a, z), rays, rays >= 0.0 ? curve(row, C_RAYS_INNER, a, z) : 0.0, curve(row, C_DOTS, a, z));
		float spiral = curve(row, C_SPIRAL, a, z);
		a4 = vec4(spiral, spiral >= 0.0 ? curve(row, C_SPIRAL_TURN, a, z) : 0.0, kind_head.w * z, counts.x + counts.y * 16.0 + counts.w * 512.0);
		bool more = a3.x >= 0.0 || a3.y > a3.z || a3.w >= 0.0 || a4.x >= 0.0;
		shown = (quad == Q_LIGHT || arm >= 0.0 || disc >= 0.0 || ring >= 0.0 || column.x >= 0.0 || quake || more);
		q_lo = -o;
		q_hi = size - o;
		if (quad == Q_LIGHT) {
			// A column's light is round its line (metric 3), not round the middle.
			bool lined = column.x >= 0.0;
			m = M_LIGHT;
			a0 = vec4(lined ? 3.0 : metric, ring < 0.0 || lined ? 0.0 : ring, k * (bit_set(L.bits, L_PULL) ? 0.6 : 1.0), 0.0);
			a1 = lit;
			a2 = column;
			k0 = vec4(L.glow, 1.0);
		} else if (quake) {
			// The cracks: their reach, the age and seed, and the ramp they cool down.
			m = M_CRACK;
			a0 = vec4(QUAKE_REACH * z, a, s, 0.0);
			a2 = vec4(L.lo, 0.0);
			k0 = vec4(L.hot, 1.0);
			k1 = vec4(L.hi, 1.0);
			k2 = vec4(L.mid, 1.0);
		} else {
			m = M_SHAPE;
			a0 = vec4(metric, arm, disc, ring);
			// The dots' count, plus 128 when they are pluses (from zoom 2).
			a1 = vec4(salt, a, s, counts.z + (z >= 2.0 ? 128.0 : 0.0));
			a2 = column;
			k0 = vec4(first, 1.0);
			k1 = vec4(second, 1.0);
			k2 = vec4(L.mid, 1.0);
		}
	} else if (quad == Q_CLOUD && poof) {
		// A staff's poof: four bone clouds along the staff, biggest at 35%, dotted as they go.
		float swell = a < 0.35 ? a / 0.35 : 1.0 - (a - 0.35) / 0.65;
		vec2 c = vec2((slot - 1.5) * 6.0, (hash_seeded(slot, 17.0, 31.0, s) - 0.5) * 3.0) * z * 0.5;
		float reach = (2.5 + 1.5 * hash_seeded(slot, 18.0, 31.0, s)) * swell * z * 0.5 + 0.5;
		shown = true;
		m = M_CLOUD;
		q_lo = floor(c - reach) - 1.0;
		q_hi = floor(c + reach) + 2.0;
		a0 = vec4(c, reach, a < 0.7 ? 0.0 : 1.0);
	}
	// Nothing outside the square, as one quad over it would have it.
	q_lo = max(q_lo, -o);
	q_hi = min(q_hi, size - o);
	shown = shown && all(lessThan(q_lo, q_hi));
	vec2 p = mix(q_lo, q_hi, corner);
	vec2 uv = (p + o) / size;
	// Folded away when there is nothing to draw.
	VERTEX = shown ? vec2(uv.x - 0.5, 0.5 - uv.y) : vec2(0.0);
	px = p;
	mode = m;
	v0 = a0;
	v1 = a1;
	v2 = a2;
	v3 = a3;
	v4 = a4;
	c0 = k0;
	c1 = k1;
	c2 = k2;
}

// ---- Fragments ----
// Small on purpose (core/README.md, "The shot shaders"): a pixel only colours itself from what
// its quad's vertices worked out. No loops, no look kinds.

void fragment() {
	vec2 d = floor(px);
	vec4 colour = vec4(0.0);
	// Its distance from the middle: round, a diamond's (v0.x 1), on a floor seen flat (v0.x 2) or
	// from a column's line (v0.x 3: the light round one, v2 its top and foot).
	float r = v0.x > 2.5 ? length(vec2(d.x, max(v2.y - d.y, 0.0) + max(d.y - v2.z, 0.0))) : (v0.x > 1.5 ? length(vec2(d.x, d.y / QUAKE_FLAT)) : (v0.x > 0.5 ? abs(d.x) + abs(d.y) : length(d)));
	if (mode < M_LIGHT + 0.5) {
		// The light: v0.z x (v1.x falloff from the ring at v0.y over v1.y, v1.z falloff over v1.w).
		float lit = v0.z * (v1.x * falloff(abs(r - v0.y), v1.y) + v1.z * falloff(r, v1.w));
		colour = vec4(c0.rgb * lit * glow_strength, 0.0);
	} else if (mode < M_CLOUD + 0.5) {
		// A bone cloud round v0.xy of reach v0.z, lit from the top-left: light on that side,
		// shadow on the far rim; dotted (v0.w) as it goes.
		vec2 c = v0.xy;
		float reach = v0.z;
		float q = length(d - c);
		if (q <= reach && (v0.w < 0.5 || mod(d.x + d.y, 2.0) == 0.0)) {
			vec2 side = (d - c) / max(reach, 1.0);
			colour = vec4(side.x + side.y < -0.5 ? BONE_LIGHT : (q > reach - 1.0 && side.x + side.y > 0.3 ? BONE_SHADOW : BONE_BASE), 1.0);
		}
	} else if (mode < M_SHAPE + 0.5) {
		// The flash: a dotted disc of reach v0.z in c0, a ring at v0.w in c1 fraying with the age
		// v1.y (its hash salt v1.x, seed v1.z; a flat one a little thicker, so its top and bottom
		// stay whole), a column v2 (white-hot c0 down its middle, dotted when v2.w is 1), a cross
		// of arms v0.y (white-hot c0 in the middle).
		if (v0.z >= 0.0 && r <= v0.z && mod(d.x + d.y, 2.0) == 0.0) {
			colour = c0;
		}
		float bucket = floor(atan(d.y, d.x) * v0.w / 2.0);
		if (v0.w >= 0.0 && abs(r - v0.w) < (v0.x > 1.5 ? 0.85 : 0.5) && hash_seeded(bucket, floor(v1.y * 8.0), v1.x, v1.z) > v1.y * 0.7) {
			colour = c1;
		}
		// The F4 parts (flash kinds), round (whatever the metric): their way round from +x, and the
		// whole pixel's distance.
		float turn = atan(d.y, d.x);
		float round_r = length(d);
		// A ring of mod(v1.w, 128) dots at radius v3.w: the nearest dot's pixel, a plus from zoom 2
		// (v1.w 128 or more).
		if (v3.w >= 0.0) {
			float n = max(mod(v1.w, 128.0), 1.0);
			float at = round(turn / 6.2832 * n) / n * 6.2832;
			vec2 dot_at = round(vec2(cos(at), sin(at)) * v3.w);
			vec2 off = abs(d - dot_at);
			if (off.x + off.y <= (v1.w >= 128.0 ? 1.0 : 0.0)) {
				colour = c1;
			}
		}
		// A spiral out to v4.x, turned v4.y turns, coils v4.z px apart, of (v4.w / 512) arms: the
		// pixel's coil (its distance in coils less its way round in turns) is near a whole one.
		if (v4.x >= 0.0 && round_r <= v4.x && round_r >= 1.0) {
			float arms = floor(v4.w / 512.0);
			float u = (round_r / v4.z - (turn / 6.2832 - v4.y)) * arms;
			if (abs(fract(u + 0.5) - 0.5) * v4.z / arms < 0.5) {
				colour = round_r < v4.x * 0.34 ? c0 : c1;
			}
		}
		// mod(v4.w, 16) rays from v3.z out to v3.y, a pixel wide, white-hot near their inner end.
		if (v3.y > v3.z) {
			float n = max(floor(mod(v4.w, 512.0) / 16.0), 1.0);
			float at = round(turn / 6.2832 * n) / n * 6.2832;
			float along = round_r * cos(turn - at);
			if (abs(round_r * sin(turn - at)) < 0.5 && along >= v3.z && along <= v3.y) {
				colour = along < v3.z + 2.0 ? c0 : c1;
			}
		}
		// A star of mod(v4.w, 16) points out to v3.x: its reach narrows between the points.
		if (v3.x >= 0.0) {
			float n = max(mod(v4.w, 16.0), 2.0);
			float sharp = pow(abs(cos(turn * n * 0.5)), 6.0);
			float reach = v3.x * (0.22 + 0.78 * sharp);
			if (round_r <= max(reach, 0.5)) {
				colour = round_r <= max(v3.x * 0.3, 0.5) ? c0 : c1;
			}
		}
		// A column narrows and frays into its top third; across, white-hot in its middle, then c1,
		// its rim c2.
		float span = max(v2.z - v2.y, 1.0);
		float up = clamp((d.y - v2.y) / (span * 0.35), 0.0, 1.0);
		float half_w = floor(v2.x * (0.35 + 0.65 * up) + 0.5);
		bool frayed = up < 1.0 && hash_seeded(d.y, floor(v1.y * 12.0), 34.0, v1.z) > up + 0.25;
		if (v2.x >= 0.0 && abs(d.x) <= half_w && d.y >= v2.y && d.y <= v2.z && !frayed && (v2.w < 0.5 || mod(d.y, 2.0) == 0.0)) {
			float e = abs(d.x);
			colour = e <= max(floor(half_w * 0.4), 0.0) ? c0 : (e < half_w || half_w < 1.0 ? c1 : c2);
		}
		if (v0.y >= 0.0 && ((d.x == 0.0 && abs(d.y) <= v0.y) || (d.y == 0.0 && abs(d.x) <= v0.y))) {
			colour = d.x == 0.0 && d.y == 0.0 ? c0 : c1;
		}
	} else {
		// A quake's cracks, on a floor seen flat: the crack nearest the pixel's way (one of
		// QUAKE_CRACKS round about, each turned and as long as its hash says, v0.x at most), its
		// line measured in whole pixels, jagged every 4 px, 2 px wide near the middle with a dark
		// rim (cut into the floor), dotted at the tip. They open at once, white-hot (c0), cool
		// from the tips in through c1, c2, v2 to dark stone, and crumble away.
		float s = v0.z;
		float a = v0.y;
		vec2 e = vec2(d.x, d.y / QUAKE_FLAT);
		float k = floor(atan(e.y, e.x) / 6.2832 * QUAKE_CRACKS + 0.5);
		float way = (k + (hash_seeded(k, 50.0, 31.0, s) - 0.5) * 0.5) * 6.2832 / QUAKE_CRACKS;
		vec2 u = vec2(cos(way), sin(way) * QUAKE_FLAT);
		float flat_len = length(u);
		u /= flat_len;
		float along = dot(d, u);
		float reach = v0.x * flat_len * (0.6 + 0.4 * hash_seeded(k, 51.0, 31.0, s)) * min(a / 0.04, 1.0);
		float rung = max(along, 0.0) / 4.0;
		float jag = mix(hash_seeded(k, floor(rung), 52.0, s), hash_seeded(k, floor(rung) + 1.0, 52.0, s), fract(rung)) - 0.5;
		float side = abs(u.x * d.y - u.y * d.x - jag * min(along, 10.0) * 0.5);
		float wide = along < reach * 0.4 ? 1.0 : 0.6;
		bool inside = along > 1.5 && along <= reach && (along < reach * 0.8 || mod(d.x + d.y, 2.0) == 0.0);
		bool crack = inside && side < wide;
		bool rim = inside && !crack && side < wide + 1.0 && along < reach * 0.6;
		bool kept = a < 0.7 || hash_seeded(d.x, d.y, 53.0, s) > (a - 0.7) / 0.3;
		float heat = a * 1.5 + along / max(reach, 1.0) * 0.4;
		vec3 rgb = heat < 0.12 ? c0.rgb : (heat < 0.3 ? c1.rgb : (heat < 0.5 ? c2.rgb : (heat < 0.7 ? v2.rgb : STONE_SHADOW)));
		colour = kept && crack ? vec4(rgb, 1.0) : (kept && rim ? vec4(STONE_SHADOW, 1.0) : vec4(0.0));
	}
	COLOR = colour;
}
