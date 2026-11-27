// SPDX-License-Identifier: GPL-3.0-or-later
// The drawing of `shot_beam.gdshader` (read it for what this draws), in an include so a card's own
// look that starts from it (`CarrierCard.look_shader`; docs/milestones/card-looks.md) includes it
// and keeps every fix to it, until the card replaces the include with code of its own. The including
// file has `shader_type` and `render_mode`. Every beam drawn with it is one merged shape
// (`shot_beam_union.gdshaderinc`, whose vertices, quads and data it takes).

#include "res://core/projectiles/shot_palette.gdshaderinc"
#include "res://core/projectiles/shot_look.gdshaderinc"
#include "res://core/projectiles/shot_beam_data.gdshaderinc"

// ---- The union's hooks (shot_beam_union.gdshaderinc) ----

// Its rim each side of its core: one pixel, and one more as it swells.
float look_bands(float swell, float width) {
	return 1.0 + floor(0.5 * swell + 0.25);
}

// Its edge: its rim, all along it (nothing past it).
float look_ripple(float along, float len, float side) {
	return 0.0;
}

// Where the middle of a beam of first kind `kind` runs `along` pixels from the staff, pushed across:
// jagged for lightning, swaying for storm, wavering for fire.
float look_off(float kind, float along, float len) {
	float jf = floor(sim_time * 30.0);
	float off = 0.0;
	if (kind == L_SPARKS) {
		float seg = 6.0;
		float k = floor(along / seg);
		float o0 = k < 0.5 ? 0.0 : (hash(k, jf, 41.0) - 0.5) * 6.0;
		float o1 = (k + 1.0) * seg >= len ? 0.0 : (hash(k + 1.0, jf, 41.0) - 0.5) * 6.0;
		off = mix(o0, o1, fract(along / seg));
	} else if (kind == L_GUSTS) {
		off = sin(along * 0.11 - sim_time * 18.0) * 1.6;
	} else if (kind == L_EMBERS) {
		off = sin(along * 0.55 - sim_time * 36.0) * 0.7;
	}
	return off;
}

// Another beam's colour inside the union: its light, its white-hot at the core.
vec3 look_neighbour(float ramp, float kind, int b, float e) {
	return ramp_shade(ramp, b, e < -1.5 ? 3 : 2);
}

vec3 look_neighbour_glow(float ramp, float kind, int b) {
	return mix(ramp_shade(ramp, b, 1), ramp_shade(ramp, b, 2), 0.35);
}

#include "res://core/projectiles/shot_beam_union.gdshaderinc"

// ---- Its own look ----

// The pixel at `P` of the merged shape `u`, drawn by this quad's piece `me`: a white-hot core an art
// pixel thin, a rim that breathes along it, sparkles a pixel out and flares at each beam's ends.
vec4 beam_pixel(Union u, Piece me, vec2 P) {
	float at = floor(me.along);
	vec4 colour = vec4(0.0);
	// As it ends it falls apart into pixels.
	bool kept = hash(at, me.xs + 7.0, 42.0) < me.fade * 1.4;
	if (kept) {
		if (u.e <= 0.0 && me.xs == 0.0) {
			colour = vec4(union_colour(u, has_layer(L_PULL) ? OUTLINE : hot), 1.0);
		} else if (u.e <= 0.0 && sin(me.along * 0.23 - sim_time * 27.0) > -0.25) {
			// The rim breathes along it.
			colour = vec4(union_colour(u, hi), 1.0);
		} else if (u.e > 0.0 && u.e <= 1.0 / ART_DETAIL && me.e < OUTSIDE && me.xs * (mod(at, 2.0) - 0.5) > 0.0 && mod(at * 7.0 + floor(sim_time * 30.0) * 13.0, 11.0) < 2.0) {
			// Sparkles a pixel out, re-rolled every other frame.
			colour = vec4(mid, 1.0);
		}
	}
	// Flares at each beam's staff and where it lands, upright crosses that flicker a pixel.
	float flick = mod(floor(sim_time * 30.0), 2.0);
	vec2 ds = u.start_d;
	vec2 de = u.end_d;
	float sr = 1.0 + flick;
	float er = 2.0 + flick;
	vec3 flare = has_layer(L_PULL) ? VOID_LIGHT : hot;
	if (u.start_beam >= 0.0 && ((ds.x == 0.0 && abs(ds.y) <= sr) || (ds.y == 0.0 && abs(ds.x) <= sr))) {
		colour = vec4(ds == vec2(0.0) ? flare : hi, 1.0);
	}
	if (u.end_beam >= 0.0 && u.end_fade > 0.3 && ((de.x == 0.0 && abs(de.y) <= er) || (de.y == 0.0 && abs(de.x) <= er))) {
		colour = vec4(de == vec2(0.0) ? flare : hi, 1.0);
	}
	return colour;
}

// How much of the beams' light reaches `P`: round the merged shape's middle, at the ends near, and
// this beam's motes of light running down it from the staff.
float beam_light(Union u, Piece me) {
	float a = max(u.e + u.bands, 0.0);
	float lit = 0.45 * falloff(a, 3.0 + 3.0 * me.swell);
	lit += u.end_beam >= 0.0 ? 0.6 * falloff(length(u.end_d), 7.0) : 0.0;
	lit += u.start_beam >= 0.0 ? 0.4 * falloff(length(u.start_d), 5.0) : 0.0;
	for (int n = 0; n < 4; n++) {
		float pos = mod(sim_time * 320.0 + float(n) * me.len / 4.0, me.len);
		lit += 0.35 * u.own_w * falloff(abs(me.along - pos), 5.0) * falloff(a, 4.0);
	}
	return lit;
}

// The light's strength after the beam's fade, glow, flicker and void's dimming.
float light_scale(Piece me) {
	float k = me.fade * beam_texel(int(own_beam + 0.5), B_LOOK).w;
	if (has_layer(L_SPARKS)) {
		k *= 0.55 + 0.9 * hash(floor(sim_time * 20.0), 0.0, 21.0);
	}
	if (has_layer(L_PULL)) {
		k *= 0.6;
	}
	return k;
}

void fragment() {
	// Each art pixel once: the union at its middle, drawn only by the piece nearest it.
	vec4 colour = vec4(0.0);
	vec2 P = art_centre(world);
	Piece me;
	Union u = union_at(P, me);
	if (u.mine) {
		// Its pixels where it has them, its light (added) elsewhere: light under them is never seen.
		colour = beam_pixel(u, me, P);
		if (colour.a < 0.5) {
			colour = vec4(union_glow(u, glow) * beam_light(u, me) * light_scale(me) * glow_strength, 0.0);
		}
	}
	COLOR = colour;
}
