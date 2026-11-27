// SPDX-License-Identifier: GPL-3.0-or-later
shader_type canvas_item;
render_mode blend_premul_alpha, world_vertex_coords;

// A beam card's own look (content/spells/carriers/beam/: `CarrierCard.look_shader`; docs/milestones/card-looks.md;
// the owner, 2026-11-08: "it should glow hot white in the center and then apply the spell colors
// out on each side", "maybe void should have a dark center"). A copy of the plain beam
// (`core/projectiles/shot_beam.gdshaderinc`, which still draws a ray with no beam card: a chain's
// jump, a zap) with its pixels and light drawn its own way: bands across it, a white-hot core
// stepping out through its ramp (light, base, shadow) to a ragged edge on each side. Its flare
// widens the bands and the white with them; it thins to its core as it ends, the edge going
// first. Pulses of light run down it from the staff and push its bands out a pixel as they pass.
// Its colours are its first infusion's; every other infusion on it winds round the core as a
// strand of its own colour, in front of the core and behind it by turns, each moving its own way
// (fire flickers, frost spirals tight, storm sways wide, lightning jags, void is a dark thread,
// mend drifts), and the pulses take turns carrying each infusion's colours (the owner,
// 2026-11-08: "it would be cool if it could take colors from each infusion type"). A beam whose
// first infusion is void turns inside out: a dark rift down the middle, its ramp glowing at the
// lips.
// Every beam drawn with it is ONE merged shape, in one draw (the owner, 2026-11-27: "Beams should
// merge into each other (like the pool)"; `core/projectiles/shot_beam_union.gdshaderinc`, whose
// vertices, quads and data it takes): its bands, rim, light and core come from the union's one
// distance, so beams close or crossing melt into one body with one rim, and where they meet its
// pixels take their colours from every beam near by the rule at a junction. Its own look (its
// strands, its pulses and their colours, void's rift, its sway) is drawn by the piece nearest each
// pixel, in that beam's own coordinates; another beam's colour there is its ramp at the union's
// band (`look_neighbour`). Warmed as a mesh before the first room.

#include "res://core/projectiles/shot_palette.gdshaderinc"
// Every infusion shows as a strand of its own (below), so its look keeps the first's ramp unwoven.
#define LOOK_OWN_INFUSIONS
#include "res://core/projectiles/shot_look.gdshaderinc"
#include "res://core/projectiles/shot_beam_data.gdshaderinc"

// How many pixels each side of its core the beam's bands reach at rest (its swell 1).
const float BANDS = 4.0;
// How fast its pulses run down it (px/s) and how many are on it at once.
const float PULSE_SPEED = 320.0;
const int PULSES = 4;
// The most infusions it is handed (Feel's BEAM_INFUSIONS_MOST, BeamUnion's INFUSIONS_MOST).
const int INFUSIONS = 8;

// The beam's own: whether it is void's dark rift (1: void came first) or a white-hot core (0); its
// first infusion's look kind (0 none: it sways, jags or wavers by it), how many infusions it shows.
varying flat float rift;
varying flat float first_kind;
varying flat float infusion_count;

// ---- The union's hooks (shot_beam_union.gdshaderinc) ----

// How close `along` is to the nearest pulse running down a beam `len` long (1 on it, 0 from
// `reach` pixels off).
float pulse_at(float along, float len, float reach) {
	float gap = len / float(PULSES);
	float d = mod(along - sim_time * PULSE_SPEED, gap);
	return falloff(min(d, gap - d), reach);
}

// Its bands each side of its core: BANDS at rest, swelling and thinning with it, at least one, two
// pixels inside half its width (room for a pulse's bulge and a sparkle past it).
float look_bands(float swell, float width) {
	return clamp(floor(BANDS * swell + 0.25), 1.0, max(width * 0.5 - 3.0, 1.0));
}

// How far past its bands its edge reaches `along` it: a ripple that runs down it, and a pixel more
// where a pulse passes, on its own side each (so the two edges ripple apart).
float look_ripple(float along, float len, float side) {
	float ripple = sin(along * 0.31 + side * 2.1 - sim_time * 23.0) > 0.55 ? 1.0 : 0.0;
	return ripple + floor(pulse_at(along, len, 6.0) * 1.6);
}

// Where the middle of a beam of first kind `kind` runs `along` pixels from the staff, pushed
// across: jagged for lightning, swaying for storm, wavering for fire (its first infusion; the others
// wind as strands).
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

// Its own varyings for its beam `b`, set in the union's vertex() (a varying is set there only): its
// first infusion's kind, how many it shows, whether it is a rift, and for a tint no palette material
// holds (mend's green) a ramp made from the tint itself.
#define LOOK_VERTEX(L, b) vec4 kinds = beam_texel(b, B_KIND); first_kind = kinds.z; infusion_count = min(kinds.x, float(INFUSIONS)); rift = first_kind == L_PULL ? 1.0 : 0.0; if (L.plain < 0.5 && int(kinds.y + 0.5) >= RAMP_OWN) { vec3 own_tint = beam_texel(b, B_CORE).rgb; lo = own_tint * 0.55; mid = own_tint; hi = mix(own_tint, vec3(1.0), 0.35); hot = mix(own_tint, vec3(1.0), 0.7); glow = mix(mid, hi, 0.35); }

// Another beam's colour at the union's distance `e`: its band counted in from the edge in its ramp
// (shadow, base, light, white-hot, then the core's bone), a rift's the other way round.
vec3 look_neighbour(float ramp, float kind, int b, float e) {
	float band = floor(-e);
	vec3 shade = band > 3.5 ? BONE_LIGHT : ramp_shade(ramp, b, int(clamp(band, 0.0, 3.0)));
	vec3 rift_shade = band < 0.5 ? ramp_shade(ramp, b, 2) : (band < 1.5 ? ramp_shade(ramp, b, 1) : (band < 2.5 ? ramp_shade(ramp, b, 0) : OUTLINE));
	return kind == L_PULL ? rift_shade : shade;
}

// Another beam's light.
vec3 look_neighbour_glow(float ramp, float kind, int b) {
	return mix(ramp_shade(ramp, b, 1), ramp_shade(ramp, b, 2), 0.35);
}

#include "res://core/projectiles/shot_beam_union.gdshaderinc"

// ---- Its own look ----

// Infusion `i` of this beam: rgb its tint, alpha its look kind / 255.
vec4 infusion_of(int i) {
	return beam_texel(int(own_beam + 0.5), B_INFUSIONS + clamp(i, 0, INFUSIONS - 1));
}

// Infusion `i`'s look kind (its card's `look_layer`).
float infusion_kind(int i) {
	return floor(infusion_of(i).a * 255.0 + 0.5);
}

// Infusion `i`'s shade `k` (0 shadow, 1 base, 2 light), from its tint (a palette colour) as a
// reaction's exact colour is made (`look_of`, EXACT).
vec3 infusion_shade(int i, int k) {
	vec3 c = infusion_of(i).rgb;
	return k == 0 ? c * 0.55 : (k == 1 ? c : mix(c, vec3(1.0), 0.35));
}

// The infusion the pulse nearest `along` carries: the pulses take turns, the first infusion's own
// (-1: the beam's ramp) and then each other's, so every infusion runs down it in turn.
float pulse_infusion(float along, float len) {
	float gap = len / float(PULSES);
	float k = floor((along - sim_time * PULSE_SPEED) / gap + 0.5);
	float turn = mod(k, max(infusion_count, 1.0));
	return turn < 0.5 ? -1.0 : turn;
}

// How a strand of look kind `kind` winds round the core: its turns a pixel, its speed, its reach
// as a share of the bands. Embers (fire) flicker, flecks (frost) spiral tight, gusts (storm) sway
// wide, a dark heart (void) threads, rising motes (mend) drift; sparks (lightning) jag, worked
// out apart; any other kind winds its own way, picked from its number.
vec3 strand_style(float kind) {
	vec3 own_style = vec3(0.12 + 0.3 * hash_seeded(kind, 1.0, 57.0, 0.0), 3.0 + 9.0 * hash_seeded(kind, 2.0, 57.0, 0.0), 0.8);
	own_style = kind == L_EMBERS ? vec3(0.21, 10.0, 0.9) : own_style;
	own_style = kind == L_FLECKS ? vec3(0.42, 5.0, 0.8) : own_style;
	own_style = kind == L_GUSTS ? vec3(0.085, 14.0, 1.15) : own_style;
	own_style = kind == L_PULL ? vec3(0.26, 7.0, 0.75) : own_style;
	own_style = kind == L_SPARKS ? vec3(0.0, 0.0, 0.85) : own_style;
	own_style = kind == L_MOTES ? vec3(0.12, 3.0, 0.7) : own_style;
	return own_style;
}

// Strand `i` (of `n`, look kind `kind`) at `along`: how far across it is (x), whether it is in
// front of the core (y > 0) and how steep it runs (z, pixels across a pixel along), within
// `reach` pixels.
vec3 strand_at(float kind, float i, float n, float along, float reach) {
	float phase = 6.2832 * i / max(n, 1.0);
	vec3 style = strand_style(kind);
	float r = reach * style.z;
	if (kind == L_SPARKS) {
		// Jagged: a fresh zigzag every few frames, in front or behind by turns.
		float seg = 5.0;
		float jf = floor(sim_time * 15.0);
		float k = floor(along / seg);
		float o0 = (hash(k, jf, 51.0 + i) * 2.0 - 1.0) * r;
		float o1 = (hash(k + 1.0, jf, 51.0 + i) * 2.0 - 1.0) * r;
		return vec3(mix(o0, o1, fract(along / seg)), hash(k, jf, 53.0 + i) - 0.5, (o1 - o0) / seg);
	}
	float a = along * style.x - sim_time * style.y + phase;
	// Embers' reach flickers.
	r = kind == L_EMBERS ? r * (0.75 + 0.25 * hash(floor(sim_time * 20.0), floor(along / 9.0), 55.0)) : r;
	return vec3(r * sin(a), cos(a), r * style.x * cos(a));
}

// A flare's heart and arm for a beam: this beam's own colours, another's from its ramp (void's
// dark heart and its light round it).
vec3 flare_heart(float kind) {
	return kind == L_PULL ? OUTLINE : BONE_LIGHT;
}

vec3 flare_arm(float beam, float ramp, float kind) {
	bool mine_beam = abs(beam - own_beam) < 0.5;
	vec3 own_arm = mix(hot, VOID_LIGHT, rift);
	vec3 other_arm = kind == L_PULL ? VOID_LIGHT : ramp_shade(ramp, int(beam + 0.5), 3);
	return mine_beam ? own_arm : other_arm;
}

vec3 flare_rim(float beam, float ramp) {
	return abs(beam - own_beam) < 0.5 ? hi : ramp_shade(ramp, int(beam + 0.5), 2);
}

// The pixel at `P` of the merged shape `u`, drawn by this quad's piece `me`, `pulse_e` the infusion
// of the pulse nearest: its colour, or alpha 0.
vec4 beam_pixel(Union u, Piece me, vec2 P, float pulse_e) {
	float len = me.len;
	float at = floor(me.along);
	float x = me.x;
	float xs = me.xs;
	float side = me.side;
	float edge = me.edge;
	float pulse = pulse_at(me.along, len, 6.0);
	// Its band, counted in from the merged shape's edge: 0 its edge (shadow), 1 base, 2 light, 3
	// white-hot, more the core. A rift counts the other way round: lips bright, the dark at its
	// middle. Whole bands (ART2): every band keeps its world width; only the core is an art pixel thin.
	float band = floor(-u.e);
	vec3 shade = band < 0.5 ? lo : (band < 1.5 ? mid : (band < 2.5 ? hi : (band < 3.5 ? hot : BONE_LIGHT)));
	vec3 rift_shade = band < 0.5 ? hi : (band < 1.5 ? mid : (band < 2.5 ? lo : OUTLINE));
	vec3 inner = mix(shade, rift_shade, rift);
	// A pulse of another infusion colours the outer bands it passes in that infusion's ramp.
	int pe = int(max(pulse_e, 0.0));
	inner = pulse_e >= 0.0 && pulse > 0.3 && band < 2.5 ? infusion_shade(pe, int(band)) : inner;
	// The core's middle pixel is always white-hot (or void's darkest), however thin the beam.
	inner = x < 0.5 ? mix(BONE_LIGHT, OUTLINE, rift) : inner;
	// The other infusions wind round it as strands, one pixel each (wider where it runs steep): in
	// front its base (light outside the white-hot), behind it hidden by the core and dark at the
	// edges. Void's is a dark thread.
	float reach = max(edge - 1.0, 1.0);
	float strands = max(infusion_count - 1.0, 0.0);
	for (int i = 1; i < INFUSIONS; i++) {
		if (float(i) >= infusion_count) {
			break;
		}
		float kind = infusion_kind(i);
		vec3 s = strand_at(kind, float(i - 1), strands, me.along, reach);
		bool hit = abs(xs / ART_DETAIL - s.x) <= 0.25 + 0.5 * abs(s.z);
		bool front = s.y > 0.0;
		vec3 strand_shade = infusion_shade(i, front ? (band < 2.5 ? 2 : 1) : 0);
		strand_shade = kind == L_PULL ? (front ? OUTLINE : infusion_shade(i, 1)) : strand_shade;
		inner = hit && x <= edge && (front || band < 2.5) ? strand_shade : inner;
	}
	vec4 colour = vec4(0.0);
	// As it ends it falls apart into pixels, its edge first, its core last.
	float fade = me.fade;
	bool kept = hash(at, x + side * 17.0 + 7.0, 42.0) < fade * 1.4 - (x / max(edge, 1.0)) * (1.0 - fade);
	if (kept) {
		if (u.e <= 0.0) {
			// Where beams meet, its colour from every beam near (the rule at a junction).
			colour = vec4(union_colour(u, inner), 1.0);
		} else if (u.e <= 1.0 / ART_DETAIL && me.e < OUTSIDE && mod(at * 7.0 + side * 5.0 + floor(sim_time * 30.0) * 13.0, 11.0) < 1.5) {
			// Sparkles a pixel past the edge, re-rolled every other frame, in the pulse's colours.
			colour = vec4(pulse_e >= 0.0 ? infusion_shade(pe, 2) : mix(hi, VOID_LIGHT, rift), 1.0);
		}
	}
	// Flares at each beam's staff and where it lands, upright crosses that flicker a pixel:
	// white-hot at the heart (void's dark), its light round it.
	float flick = mod(floor(sim_time * 30.0), 2.0);
	vec2 ds = u.start_d;
	vec2 de = u.end_d;
	float sr = 1.0 + flick;
	float er = 2.0 + flick + floor(0.5 * u.end_bands - 1.0);
	if (u.start_beam >= 0.0 && ((ds.x == 0.0 && abs(ds.y) <= sr) || (ds.y == 0.0 && abs(ds.x) <= sr))) {
		colour = vec4(ds == vec2(0.0) ? flare_heart(u.start_kind) : flare_arm(u.start_beam, u.start_ramp, u.start_kind), 1.0);
	}
	if (u.end_beam >= 0.0 && u.end_fade > 0.3 && ((de.x == 0.0 && abs(de.y) <= er) || (de.y == 0.0 && abs(de.x) <= er))) {
		float m = abs(de.x) + abs(de.y);
		colour = vec4(m < 1.5 ? flare_heart(u.end_kind) : (m < er ? flare_arm(u.end_beam, u.end_ramp, u.end_kind) : flare_rim(u.end_beam, u.end_ramp)), 1.0);
	}
	return colour;
}

// The light at `P`: a soft band round the merged shape as wide as its bands and more, and the
// beams' ends near, in the glow of every beam near; this beam's pulses, each in its infusion's light.
vec3 beam_light(Union u, Piece me, vec2 P, float pulse_e) {
	float a = max(u.e + u.bands, 0.0);
	float lit = 0.5 * falloff(a, 3.0 + 1.5 * u.bands);
	lit += u.end_beam >= 0.0 ? 0.6 * falloff(length(u.end_d), 7.0 + u.end_bands) : 0.0;
	lit += u.start_beam >= 0.0 ? 0.4 * falloff(length(u.start_d), 5.0) : 0.0;
	vec3 pulse_glow = pulse_e >= 0.0 ? infusion_shade(int(pulse_e), 2) : glow;
	return union_glow(u, glow) * lit + pulse_glow * 0.45 * u.own_w * pulse_at(me.along, me.len, 6.0) * falloff(a, 3.0 + u.bands);
}

// The light's strength after the beam's fade, glow, flicker and void's dimming.
float light_scale(Piece me) {
	float k = me.fade * beam_texel(int(own_beam + 0.5), B_LOOK).w;
	if (first_kind == L_SPARKS) {
		k *= 0.55 + 0.9 * hash(floor(sim_time * 20.0), 0.0, 21.0);
	}
	if (rift > 0.5) {
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
		float pulse_e = pulse_infusion(me.along, me.len);
		colour = beam_pixel(u, me, P, pulse_e);
		if (colour.a < 0.5) {
			colour = vec4(beam_light(u, me, P, pulse_e) * light_scale(me) * glow_strength, 0.0);
		}
	}
	COLOR = colour;
}
