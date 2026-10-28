// SPDX-License-Identifier: GPL-3.0-or-later
shader_type canvas_item;
// world_vertex_coords: the pixel is found on the world's grid, so the flares stand upright.
render_mode blend_premul_alpha, world_vertex_coords;

// A beam (Feel's beams; core/README.md, "The shot shaders"): a white-hot one-pixel core, a rim
// that breathes along it, motes running down it, flares at both ends, a splash where it lands
// and its card particles. Blending is premultiplied: its pixels are opaque, its glow added light.
// Mode 1: a Line2D stretched along its path (UV.x 0-1 along `beam_length` pixels, UV.y across
// `beam_width`); mode 2: a Sprite2D whose region is the beam (UV in texture pixels, 32 across).
// Its core colour is `core_override`, its player and look these (`beam_player` -1, NO_PLAYER, is
// an enemy's beam). `beam_fade` (1 to 0) dissolves it into pixels as it ends; `beam_swell` (1 at
// rest) widens its rim and glow when it flares and narrows them as it thins; `beam_glow` is how
// strongly it glows.

#include "res://core/projectiles/shot_palette.gdshaderinc"
#include "res://core/projectiles/shot_look.gdshaderinc"
#include "res://core/projectiles/shot_particle.gdshaderinc"

uniform vec4 core_override = vec4(1.0);
// Feel's fade of the line (kept with the beam; the beam's own fade is `beam_fade`).
uniform vec4 body_tint = vec4(1.0);
uniform int beam_mode = 1;
uniform float beam_length = 0.0;
uniform float beam_width = 16.0;
uniform int beam_player = 0;
uniform int beam_look = 0;
uniform float beam_fade = 1.0;
uniform float beam_swell = 1.0;
uniform float beam_glow = 1.0;
// Where a beam starts (the staff) and ends in the world, and its way at the end: its flares and
// the splash where it lands are drawn there, upright on the world's pixels.
uniform vec2 beam_start = vec2(-100000.0);
uniform vec2 beam_end = vec2(-100000.0);
uniform vec2 beam_end_dir = vec2(1.0, 0.0);
// How far the beam's quad reaches past each end, so the flares are whole: its line (or region)
// is beam_length + 2 x beam_lead long and starts beam_lead before the staff.
uniform float beam_lead = 0.0;

// The world position of the pixel.
varying vec2 world;

void vertex() {
	vec3 b = vec3(float(beam_look & 255), float((beam_look >> 8) & 255), float((beam_look >> 16) & 255));
	Look L = look_of(core_override.rgb, beam_player < 0 ? ENEMY_PLAYER : float(min(beam_player, 3)), 1.0, b, 0.0, true);
	SET_LOOK(L);
	world = VERTEX;
}

// A beam (beam mode): its pixel at `along` pixels from the staff and `across` from its middle,
// `cheb` the longer axis's share of its way on screen (so a line is one pixel per step of that
// axis, as the mockup draws it, never two), `P` the pixel in the world.
vec4 beam(float along, float across, float cheb, vec2 P) {
	float len = max(beam_length, 1.0);
	float at = floor(along);
	float jf = floor(sim_time * 30.0);
	// Where its middle runs: jagged for lightning, swaying for storm, wavering for fire.
	float off = 0.0;
	if (has_layer(L_SPARKS)) {
		float seg = 6.0;
		float k = floor(along / seg);
		float o0 = k < 0.5 ? 0.0 : (hash(k, jf, 41.0) - 0.5) * 6.0;
		float o1 = (k + 1.0) * seg >= len ? 0.0 : (hash(k + 1.0, jf, 41.0) - 0.5) * 6.0;
		off = mix(o0, o1, fract(along / seg));
	} else if (has_layer(L_GUSTS)) {
		off = sin(along * 0.11 - sim_time * 18.0) * 1.6;
	} else if (has_layer(L_EMBERS)) {
		off = sin(along * 0.55 - sim_time * 36.0) * 0.7;
	}
	float x = floor((across - off) / max(cheb, 0.5) + 0.5);
	vec4 colour = vec4(0.0);
	// As it ends it falls apart into pixels.
	bool kept = hash(at, x + 7.0, 42.0) < beam_fade * 1.4;
	float rim = 1.0 + floor(0.5 * beam_swell + 0.25);
	if (kept && along >= 0.0 && along <= len) {
		if (x == 0.0) {
			colour = vec4(has_layer(L_PULL) ? OUTLINE : hot, 1.0);
		} else if (abs(x) <= rim && sin(along * 0.23 - sim_time * 27.0) > -0.25) {
			// The rim breathes along it.
			colour = vec4(hi, 1.0);
		} else if (abs(x) == rim + 1.0 && x * (mod(at, 2.0) - 0.5) > 0.0 && mod(at * 7.0 + floor(sim_time * 30.0) * 13.0, 11.0) < 2.0) {
			// Sparkles a pixel out, re-rolled every other frame.
			colour = vec4(mid, 1.0);
		}
	}
	// Flares at the staff and where it lands, upright crosses that flicker a pixel.
	float flick = mod(floor(sim_time * 30.0), 2.0);
	vec2 ds = floor(P) - floor(beam_start);
	vec2 de = floor(P) - floor(beam_end);
	float sr = 1.0 + flick;
	float er = 2.0 + flick;
	vec3 flare = has_layer(L_PULL) ? VOID_LIGHT : hot;
	if ((ds.x == 0.0 && abs(ds.y) <= sr) || (ds.y == 0.0 && abs(ds.x) <= sr)) {
		colour = vec4(ds == vec2(0.0) ? flare : hi, 1.0);
	}
	if (beam_fade > 0.3 && ((de.x == 0.0 && abs(de.y) <= er) || (de.y == 0.0 && abs(de.x) <= er))) {
		colour = vec4(de == vec2(0.0) ? flare : hi, 1.0);
	}
	// A splash where it lands: sparks thrown back off the end, cooling.
	float lit = 0.0;
	vec2 back = -normalize(beam_end_dir + vec2(0.0001, 0.0));
	for (int n = 0; n < 6; n++) {
		float i = float(n);
		float life = 0.1 + 0.12 * hash(i, 0.0, 49.0);
		float t = sim_time / life + hash(i, 1.0, 49.0);
		float cyc = floor(t);
		float a = fract(t);
		float ang = atan(back.y, back.x) + (hash(i, cyc, 50.0) - 0.5) * 2.4;
		vec2 pos = beam_end + vec2(cos(ang), sin(ang)) * (40.0 + 60.0 * hash(i, cyc, 51.0)) * (0.9 * (1.0 - pow(0.9, a * life * 60.0)) / 0.1 / 60.0);
		float r = length(floor(P) - floor(pos));
		lit += 0.9 * (1.0 - 0.75 * a) * (0.16 * falloff(r, 2.5) + 0.07 * falloff(r, 7.0)) * beam_fade;
		if (colour.a == 0.0 && beam_fade > 0.3 && r < 0.5) {
			colour = vec4(ramp(a), 1.0);
		}
	}
	// Its cards, given off along it.
	if (colour.a == 0.0 && emit_count() > 0.5) {
		float count = min(4.0 + 2.0 * emit_count(), float(MAX_PARTICLES));
		for (int n = 0; n < MAX_PARTICLES; n++) {
			if (float(n) >= count) {
				break;
			}
			float i = float(n);
			float t = sim_time * (2.5 + 1.5 * hash(i, 0.0, 45.0)) + hash(i, 0.0, 46.0);
			float cyc = floor(t);
			float look = emitter(int(min(floor(hash(i, cyc, 47.0) * emit_count()), emit_count() - 1.0)));
			vec2 from = vec2(len * hash(i, cyc, 48.0), off);
			vec4 p = particle(look, from, fract(t), i, cyc, vec2(along, across), 1.0);
			if (p.a > 0.0) {
				colour = p;
			}
		}
	}
	if (colour.a > 0.0) {
		return colour;
	}
	lit += 0.45 * falloff(abs(across - off), 3.0 + 3.0 * beam_swell) + 0.6 * falloff(length(floor(P) - floor(beam_end)), 7.0) + 0.4 * falloff(length(floor(P) - floor(beam_start)), 5.0);
	// Motes of light running down it from the staff.
	for (int n = 0; n < 4; n++) {
		float pos = mod(sim_time * 320.0 + float(n) * len / 4.0, len);
		lit += 0.35 * falloff(abs(along - pos), 5.0) * falloff(abs(across - off), 4.0);
	}
	lit *= beam_fade * beam_glow;
	if (has_layer(L_SPARKS)) {
		lit *= 0.55 + 0.9 * hash(floor(sim_time * 20.0), 0.0, 21.0);
	}
	if (has_layer(L_PULL)) {
		lit *= 0.6;
	}
	return vec4(glow * lit * glow_strength, 0.0);
}

// The longer axis's share of the way `along` grows on screen (1 for a level or upright beam,
// 0.71 for a diagonal one).
float cheb_of(float along) {
	vec2 g = vec2(dFdx(along), dFdy(along));
	float l = length(g);
	return l > 0.0001 ? max(abs(g.x), abs(g.y)) / l : 1.0;
}

void fragment() {
	if (beam_mode == 2) {
		float along = UV.x / TEXTURE_PIXEL_SIZE.x - beam_lead;
		COLOR = beam(along, UV.y / TEXTURE_PIXEL_SIZE.y - 0.5 / TEXTURE_PIXEL_SIZE.y, cheb_of(along), world);
	} else {
		float along = UV.x * (beam_length + 2.0 * beam_lead) - beam_lead;
		COLOR = beam(along, (UV.y - 0.5) * beam_width, cheb_of(along), world);
	}
}
