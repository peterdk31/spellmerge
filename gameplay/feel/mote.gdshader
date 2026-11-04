// SPDX-License-Identifier: GPL-3.0-or-later
shader_type canvas_item;
// world_vertex_coords: VERTEX is in world space in vertex(), so each quad is placed in the world
// and the mote stands on the world's pixels (nothing else moves its vertices).
render_mode blend_premul_alpha, world_vertex_coords;

// Motes (gameplay/feel/mote.gd; docs/milestones/spell-spectacle.md, P1): single pixels (or a 2x2
// chunk) thrown from a point, with no game logic. A mote's whole flight comes from its row,
// written once by the CPU, its kind's numbers and the time since its birth: it flies with drag,
// rises or falls by a fake height, lands, bounces once, lies still, and cools step by step
// through its ramp's shades (no partial alpha; docs/STYLE.md), then is gone. Blending is
// premultiplied: the pixel is opaque, the glow round a hot one light added to what is below.
//
// Nothing here is a kind or a colour of its own:
// - the kinds' numbers are data (`MoteKind`, content/motes), handed over by mote.gd as
//   `kind_motion` (gravity, drag, bounce, glow), `kind_sway` (sway, its rate, first shade, how
//   far its shape reaches from its pixel in any frame and any way it turns: `Motes.reach_of`) and
//   `kind_shape` (frames, how they play: 0 life, 1 loop, 2 pick; frames a second; 1 when it turns
//   with its flight), and their shapes as `shape_atlas`: SHAPE_SIZE squares, a kind's frames
//   along its row, each pixel 0 none, 0.5 its shade, 1 the shade hotter;
// - a spell's ramp is the shot's own, picked by the shot shaders' `look_of` from its core colour
//   and its caster's ramp; any other ramp (a room's walls) is a row of `ramp_table` (white-hot,
//   light, base, shadow across).
//
// A row (Motes.DRAW_STRIDE floats; the batch sits untransformed at the origin, so the transform
// carries data, in full floats on every renderer):
//   MODEL_MATRIX[0].xy  its velocity along the floor (px/s)
//   MODEL_MATRIX[1].x   its birth, on `sim_time`'s clock (s)
//   MODEL_MATRIX[1].y   its height's velocity, up (px/s)
//   MODEL_MATRIX[3].xy  its ground point at birth (it is drawn there, raised by its height)
//   COLOR               its source / SOURCE_CODE (0-3 a hat ramp, 4 the enemies', +8 an exact
//                       colour; from 16 a row of the ramp table), its kind / KIND_CODE, its
//                       life / LIFE_MAX, its height at birth / HEIGHT_MAX
//   INSTANCE_CUSTOM     the core colour (a spell's), a seed (0-1)
// The colour and custom data are between 0 and 1 and need no more than bytes: a renderer may
// keep them as half floats or bytes.
//
// `mote_flight` is `Motes.flight` line for line.

#include "res://core/projectiles/shot_palette.gdshaderinc"
#include "res://core/projectiles/shot_look.gdshaderinc"

uniform vec4 kind_motion[16];
uniform vec4 kind_sway[16];
uniform vec4 kind_shape[16];
uniform sampler2D ramp_table : filter_nearest;
uniform sampler2D shape_atlas : filter_nearest;

// Motes.LIFE_MAX, SOURCE_CODE, KIND_CODE, HEIGHT_MAX, MAX_KINDS, EXACT_SOURCE, TABLE_SOURCE;
// MoteKind.SHAPE_SIZE.
const float LIFE_MAX = 4.0;
const float SOURCE_CODE = 128.0;
const float KIND_CODE = 16.0;
const float HEIGHT_MAX = 63.75;
const int MAX_KINDS = 16;
const int SHAPE_SIZE = 5;
const float EXACT_SOURCE = 8.0;
const float TABLE_SOURCE = 16.0;
// How far a hot mote's glow reaches past its shape.
const float GLOW_REACH = 2.0;
// How far before now its way is read, to turn its shape (s).
const float TURN_LOOK = 0.03;

// The mote's pixel (its shape's middle), its shade and the shade hotter, its glow, its shape (the
// atlas's square: kind's row, frame's column), the way it is turned (cos, sin; 1, 0 unturned),
// and the world pixel drawn.
varying flat vec2 m_at;
varying flat vec3 m_rgb;
varying flat vec3 m_hot;
varying flat float m_glow;
varying flat vec2 m_cell;
varying flat vec2 m_turn;
varying vec2 m_px;

// Where a mote of kind `k` is `t` seconds after its birth at the ground point `from` with the
// velocity `vel`, the height `h0` and the height's velocity `vz`: its ground point (xy) and its
// height (z). A falling kind lands, bounces once and then lies still.
vec3 mote_flight(vec2 from, vec2 vel, float h0, float vz, float t, int k, float s) {
	float g = kind_motion[k].x;
	float land = 1.0e9;
	float rest = 1.0e9;
	float rebound = 0.0;
	if (g > 0.0) {
		land = (vz + sqrt(vz * vz + 2.0 * g * max(h0, 0.0))) / g;
		rebound = (g * land - vz) * kind_motion[k].z;
		rest = land + 2.0 * rebound / g;
	}
	float tm = min(max(t, 0.0), rest);
	float h = 0.0;
	if (tm < land) {
		h = h0 + vz * tm - 0.5 * g * tm * tm;
	} else if (tm < rest) {
		float q = tm - land;
		h = rebound * q - 0.5 * g * q * q;
	}
	float drag = kind_motion[k].y;
	float along = drag > 0.0 ? (1.0 - exp(-drag * tm)) / drag : tm;
	vec2 ground = from + vel * along;
	float phase = s * 6.2832;
	ground.x += kind_sway[k].x * (sin(tm * kind_sway[k].y + phase) - sin(phase));
	return vec3(ground, max(h, 0.0));
}

// Shade `shade` (0 white-hot ... 3 shadow) of the ramp of `source` (with the core colour `c`).
vec3 mote_shade(float source, vec3 c, float s, int shade) {
	if (source >= TABLE_SOURCE) {
		return texelFetch(ramp_table, ivec2(shade, int(source - TABLE_SOURCE)), 0).rgb;
	}
	// The shot's own ramp, as the shot shaders pick it.
	bool exact = source >= EXACT_SOURCE;
	Look L = look_of(c, mod(source, EXACT_SOURCE), 1.0, vec3(0.0, 0.0, exact ? 128.0 : 0.0), s, false);
	return shade == 0 ? L.hot : (shade == 1 ? L.hi : (shade == 2 ? L.mid : L.lo));
}

void vertex() {
	vec2 vel = MODEL_MATRIX[0].xy;
	float born = MODEL_MATRIX[1].x;
	float vz = MODEL_MATRIX[1].y;
	vec2 from = MODEL_MATRIX[3].xy;
	float source = floor(COLOR.r * SOURCE_CODE + 0.5);
	int k = clamp(int(floor(COLOR.g * KIND_CODE + 0.5)), 0, MAX_KINDS - 1);
	float life = COLOR.b * LIFE_MAX;
	float h0 = COLOR.a * HEIGHT_MAX;
	float s = INSTANCE_CUSTOM.a;
	float t = sim_time - born;
	bool alive = life > 0.0 && t >= 0.0 && t < life;
	VERTEX = vec2(0.0);
	m_px = vec2(0.0);
	m_at = vec2(0.0);
	m_rgb = vec3(0.0);
	m_hot = vec3(0.0);
	m_glow = 0.0;
	m_cell = vec2(0.0);
	m_turn = vec2(1.0, 0.0);
	// An unused row has no life: folded away, with none of the work below.
	if (alive) {
		vec3 at = mote_flight(from, vel, h0, vz, t, k, s);
		vec2 seen = at.xy - vec2(0.0, at.z);
		vec2 pixel = floor(seen);
		// Cooling: evenly from its first shade down to shadow over its life.
		float shade_from = kind_sway[k].z;
		int shade = int(min(shade_from + floor(t / life * (4.0 - shade_from)), 3.0));
		// Its frame: through them over its life, round them, or its own.
		vec4 shape = kind_shape[k];
		float frames = max(shape.x, 1.0);
		float frame = shape.y < 0.5 ? floor(t / life * frames) : (shape.y < 1.5 ? floor(t * shape.z + s * frames) : floor(s * frames));
		frame = mod(clamp(frame, 0.0, 1.0e6), frames);
		// Turned with its way (8 ways), read over the last moment; at rest, the way it was thrown.
		vec2 turn = vec2(1.0, 0.0);
		float reach = float(SHAPE_SIZE / 2);
		if (shape.w > 0.5) {
			vec3 before = mote_flight(from, vel, h0, vz, t - TURN_LOOK, k, s);
			vec2 way = seen - (before.xy - vec2(0.0, before.z));
			if (dot(way, way) < 0.0025) {
				way = vel;
			}
			float angle = round(atan(way.y, way.x) / 0.7854) * 0.7854;
			turn = vec2(cos(angle), sin(angle));
			reach += 1.0;
		}
		float lit = shade <= 1 ? kind_motion[k].w * glow_strength : 0.0;
		// A glowing mote's quad holds its glow (as far from its pixel for every shape); one
		// with none only its shape's pixels (P1c: most motes are a pixel or two, and their
		// fragments were most of their cost).
		reach = lit > 0.0 ? reach + GLOW_REACH : kind_sway[k].w;
		vec2 corner = vec2(UV.x > 0.5 ? 1.0 : 0.0, UV.y > 0.5 ? 1.0 : 0.0);
		vec2 p = mix(pixel - reach, pixel + 1.0 + reach, corner);
		VERTEX = p;
		m_px = p;
		m_at = pixel;
		m_rgb = mote_shade(source, INSTANCE_CUSTOM.rgb, s, shade);
		m_hot = mote_shade(source, INSTANCE_CUSTOM.rgb, s, max(shade - 1, 0));
		m_glow = lit;
		m_cell = vec2(frame, float(k)) * float(SHAPE_SIZE);
		m_turn = turn;
	}
}

void fragment() {
	vec2 d = floor(m_px) - m_at;
	// The shape's pixel this one is: turned back by its way, to the nearest pixel.
	vec2 q = round(vec2(m_turn.x * d.x + m_turn.y * d.y, -m_turn.y * d.x + m_turn.x * d.y));
	float half_size = float(SHAPE_SIZE / 2);
	float mark = 0.0;
	if (abs(q.x) <= half_size && abs(q.y) <= half_size) {
		mark = texelFetch(shape_atlas, ivec2(m_cell + q + half_size), 0).r;
	}
	if (mark > 0.75) {
		COLOR = vec4(m_hot, 1.0);
	} else if (mark > 0.25) {
		COLOR = vec4(m_rgb, 1.0);
	} else {
		// The glow round a hot mote: light added, no alpha.
		COLOR = vec4(m_rgb * m_glow * 0.5 * falloff(length(d), half_size + GLOW_REACH), 0.0);
	}
}
