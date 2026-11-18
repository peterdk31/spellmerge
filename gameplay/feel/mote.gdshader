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
//   `kind_table`, a row a kind (up to MAX_KINDS), four texels across: its motion (gravity, drag,
//   bounce, glow), its sway (sway, its rate, first shade, how far its shape reaches from its pixel
//   in any frame and any way it turns: `Motes.reach_of`), its shape (frames, how they play: 0
//   life, 1 loop, 2 pick; frames a second; 1 when it turns with its flight) and its light (x: 1
//   for a kind drawn only where light falls, `MoteKind.lit_only`; y: its darkest shade drawn,
//   `lit_darkest`), and their shapes as
//   `shape_atlas`: SHAPE_SIZE squares, a kind's frames along its row, each pixel 0 none, 0.5 its
//   shade, 1 the shade hotter;
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
//
// A lit-only kind (docs/milestones/atmosphere.md, B: a room's dust in the air) reads the spell
// light's light buffer (`light_buffer`, the same view smaller, as light_apply.gdshader reads it)
// under each of its pixels: below the first of `lit_steps` it is not drawn (the dark), above each
// step it is a shade brighter (shadow, base, light, white-hot), in the light's hue. Its life does
// not cool it: it comes in through its shades and goes out through them (its brightest at the
// middle of its life, `shade_from`), the dimmer of the two winning, so it never pops; a shade
// darker than its `lit_darkest` is not drawn. With no light buffer (`light_on` off: the "Spell
// light" setting off) it is not drawn.

#include "res://core/projectiles/shot_palette.gdshaderinc"
// A mote is in one infusion's colours (`Motes.set_infusions` picks it): its look is never woven.
#define LOOK_OWN_INFUSIONS
#include "res://core/projectiles/shot_look.gdshaderinc"

uniform sampler2D kind_table : filter_nearest;
uniform sampler2D ramp_table : filter_nearest;
uniform sampler2D shape_atlas : filter_nearest;
// The spell light's buffer (Motes.set_light), for the lit-only kinds; `light_on` false: none.
uniform sampler2D light_buffer : filter_linear, repeat_disable;
uniform bool light_on = false;
// The light's brightest channel from which a lit-only mote shows in its shadow, base, light and
// white-hot shade; and how much it takes the light's hue (0 none, 1 all of it).
uniform vec4 lit_steps = vec4(0.015, 0.04, 0.09, 0.2);
uniform float lit_hue = 0.6;

// Motes.LIFE_MAX, SOURCE_CODE, KIND_CODE, HEIGHT_MAX, MAX_KINDS, EXACT_SOURCE, TABLE_SOURCE;
// MoteKind.SHAPE_SIZE.
const float LIFE_MAX = 4.0;
const float SOURCE_CODE = 128.0;
const float KIND_CODE = 255.0;
const float HEIGHT_MAX = 63.75;
const int MAX_KINDS = 256;
const int SHAPE_SIZE = 5;
const float EXACT_SOURCE = 8.0;
const float TABLE_SOURCE = 16.0;
// How far a hot mote's glow reaches past its shape.
const float GLOW_REACH = 2.0;
// How far before now its way is read, to turn its shape (s).
const float TURN_LOOK = 0.03;
// How much quicker than its half life a lit-only mote comes into its first shade (and goes out of
// it): 2 is in its brightest from a quarter of its life to three quarters.
const float RISE_SPEED = 2.0;

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
// A lit-only mote: 1 (else 0), the shade its life allows now (0 white-hot ... 3 shadow), its
// darkest shade drawn, and its base and shadow shades (m_hot and m_rgb are then its white-hot and
// light ones).
varying flat float m_lit;
varying flat float m_life_shade;
varying flat float m_darkest;
varying flat vec3 m_mid;
varying flat vec3 m_lo;

// Where a mote of a kind of the motion `motion` and the sway `sway` (its `kind_table` row) is `t`
// seconds after its birth at the ground point `from` with the velocity `vel`, the height `h0` and
// the height's velocity `vz`: its ground point (xy) and its height (z). A falling kind lands,
// bounces once and then lies still.
vec3 mote_flight(vec2 from, vec2 vel, float h0, float vz, float t, vec4 motion, vec4 sway, float s) {
	float g = motion.x;
	float land = 1.0e9;
	float rest = 1.0e9;
	float rebound = 0.0;
	if (g > 0.0) {
		land = (vz + sqrt(vz * vz + 2.0 * g * max(h0, 0.0))) / g;
		rebound = (g * land - vz) * motion.z;
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
	float drag = motion.y;
	float along = drag > 0.0 ? (1.0 - exp(-drag * tm)) / drag : tm;
	vec2 ground = from + vel * along;
	float phase = s * 6.2832;
	ground.x += sway.x * (sin(tm * sway.y + phase) - sin(phase));
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
	m_lit = 0.0;
	m_life_shade = 3.0;
	m_darkest = 3.0;
	m_mid = vec3(0.0);
	m_lo = vec3(0.0);
	vec4 light_of = alive ? texelFetch(kind_table, ivec2(3, k), 0) : vec4(0.0);
	bool lit_only = light_of.x > 0.5;
	// A lit-only mote with no light to read is not drawn.
	alive = alive && (light_on || !lit_only);
	// An unused row has no life: folded away, with none of the work below.
	if (alive) {
		vec4 motion = texelFetch(kind_table, ivec2(0, k), 0);
		vec4 sway = texelFetch(kind_table, ivec2(1, k), 0);
		vec4 shape = texelFetch(kind_table, ivec2(2, k), 0);
		vec3 at = mote_flight(from, vel, h0, vz, t, motion, sway, s);
		vec2 seen = at.xy - vec2(0.0, at.z);
		vec2 pixel = floor(seen);
		// Cooling: evenly from its first shade down to shadow over its life.
		float shade_from = sway.z;
		int shade = int(min(shade_from + floor(t / life * (4.0 - shade_from)), 3.0));
		// Its frame: through them over its life, round them, or its own.
		float frames = max(shape.x, 1.0);
		float frame = shape.y < 0.5 ? floor(t / life * frames) : (shape.y < 1.5 ? floor(t * shape.z + s * frames) : floor(s * frames));
		frame = mod(clamp(frame, 0.0, 1.0e6), frames);
		// Turned with its way (8 ways), read over the last moment; at rest, the way it was thrown.
		vec2 turn = vec2(1.0, 0.0);
		float reach = float(SHAPE_SIZE / 2);
		if (shape.w > 0.5) {
			vec3 before = mote_flight(from, vel, h0, vz, t - TURN_LOOK, motion, sway, s);
			vec2 way = seen - (before.xy - vec2(0.0, before.z));
			if (dot(way, way) < 0.0025) {
				way = vel;
			}
			float angle = round(atan(way.y, way.x) / 0.7854) * 0.7854;
			turn = vec2(cos(angle), sin(angle));
			reach += 1.0;
		}
		float lit = shade <= 1 ? motion.w * glow_strength : 0.0;
		// A glowing mote's quad holds its glow (as far from its pixel for every shape); one
		// with none only its shape's pixels (P1c: most motes are a pixel or two, and their
		// fragments were most of their cost).
		reach = lit > 0.0 ? reach + GLOW_REACH : sway.w;
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
		if (lit_only) {
			// In through its shades and out again: its first shade at the middle of its life.
			float rise = min((1.0 - abs(2.0 * t / life - 1.0)) * RISE_SPEED, 1.0);
			m_lit = 1.0;
			m_darkest = light_of.y;
			m_life_shade = clamp(3.0 - floor(rise * (4.0 - shade_from)), shade_from, 3.0);
			m_hot = mote_shade(source, INSTANCE_CUSTOM.rgb, s, 0);
			m_rgb = mote_shade(source, INSTANCE_CUSTOM.rgb, s, 1);
			m_mid = mote_shade(source, INSTANCE_CUSTOM.rgb, s, 2);
			m_lo = mote_shade(source, INSTANCE_CUSTOM.rgb, s, 3);
		}
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
	if (m_lit > 0.5) {
		// Lit only: as bright as the light under it, no brighter than its life allows.
		if (mark <= 0.25) {
			discard;
		}
		vec3 shine = texture(light_buffer, SCREEN_UV).rgb;
		float most = max(shine.r, max(shine.g, shine.b));
		// In the dark (below the first step) it is not drawn, a highlight neither.
		if (most < lit_steps.x) {
			discard;
		}
		float step_of = most >= lit_steps.w ? 0.0 : (most >= lit_steps.z ? 1.0 : (most >= lit_steps.y ? 2.0 : 3.0));
		// A highlight ("o") is a shade hotter than its light.
		step_of -= mark > 0.75 ? 1.0 : 0.0;
		float shade = max(max(step_of, m_life_shade), 0.0);
		if (shade > m_darkest + 0.5) {
			discard;
		}
		vec3 rgb = shade < 0.5 ? m_hot : (shade < 1.5 ? m_rgb : (shade < 2.5 ? m_mid : m_lo));
		COLOR = vec4(rgb * mix(vec3(1.0), shine / max(most, 0.0001), lit_hue), 1.0);
	} else if (mark > 0.75) {
		COLOR = vec4(m_hot, 1.0);
	} else if (mark > 0.25) {
		COLOR = vec4(m_rgb, 1.0);
	} else {
		// The glow round a hot mote: light added, no alpha.
		COLOR = vec4(m_rgb * m_glow * 0.5 * falloff(length(d), half_size + GLOW_REACH), 0.0);
	}
}
