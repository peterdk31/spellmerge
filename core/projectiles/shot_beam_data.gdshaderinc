// SPDX-License-Identifier: GPL-3.0-or-later
// The beams' data as the merged beams' shaders read it (Feel's BeamUnion, gameplay/feel/beam_union.gd:
// keep the two equal; `shot_beam_union.gdshaderinc` draws with it), and the colours a beam is drawn
// in at a junction. Include `shot_palette.gdshaderinc` and `shot_look.gdshaderinc` first; a look
// includes this, defines its own hooks (see `shot_beam_union.gdshaderinc`), then the union.

#ifndef SHOT_BEAM_DATA_INC
#define SHOT_BEAM_DATA_INC

// Texels a row of `beam_data`; a beam's row (B_*), then from row `beam_rows` its pieces, SEGS_A_ROW
// to a row of SEG_TEXELS each (S_*). BeamUnion's ROW, B_*, SEG_TEXELS and S_*.
const int ROW = 16;
const int B_ENDS = 0;
const int B_SHAPE = 1;
const int B_CORE = 2;
const int B_LOOK = 3;
const int B_KIND = 4;
const int B_INFUSIONS = 5;
const int SEG_TEXELS = 4;
const int SEGS_A_ROW = 4;
const int S_ENDS = 0;
const int S_SHAPE = 1;
const int S_WHO = 2;
const int S_WIDTH = 3;
// A piece's flags (BeamUnion's F_*): its beam's first and last piece, a cut of a straight piece before
// it and after it (a pixel past one is the next piece's own).
const float F_FIRST = 1.0;
const float F_LAST = 2.0;
const float F_CUT_BEFORE = 4.0;
const float F_CUT_AFTER = 8.0;
// A beam's ramp at a junction (BeamUnion's RAMP_*): a palette material, a player's ramp from
// RAMP_PLAYER (the enemies' last), or its own tint.
const int RAMP_PLAYER = 8;
const int RAMP_OWN = 16;
// The colour rules at a junction (BeamUnion's MIX_*).
const int MIX_DITHER = 0;
const int MIX_SNAP = 1;
const int MIX_NEAREST = 2;

// Every beam and piece drawn this frame, and where the pieces start; how many pieces.
uniform sampler2D beam_data : filter_nearest;
uniform int beam_rows = 0;
uniform int seg_count = 0;
// The colour rule where beams meet (MIX_*).
uniform int beam_mix = 0;
// How far the quads of a beam's first and last pieces reach past its ends, so the flares are whole.
uniform float beam_lead = 8.0;

// Texel `k` of piece `s` (0 to `seg_count` - 1, inside the texture).
vec4 seg_texel(int s, int k) {
	return texelFetch(beam_data, ivec2((s % SEGS_A_ROW) * SEG_TEXELS + k, beam_rows + s / SEGS_A_ROW), 0);
}

// Texel `k` of beam `b`'s row.
vec4 beam_texel(int b, int k) {
	return texelFetch(beam_data, ivec2(k, b), 0);
}

// Shade `k` (0 shadow, 1 base, 2 light, 3 white-hot) of the ramp `ramp` (RAMP_*) of beam `b`, as
// `look_of` draws a beam's: a palette material's shades (white-hot its light whitened), a player's
// ramp (white-hot bone), or the beam's own tint's.
vec3 ramp_shade(float ramp, int b, int k) {
	int r = int(ramp + 0.5);
	vec3 lo_ = vec3(0.0);
	vec3 mid_ = vec3(0.0);
	vec3 hi_ = vec3(0.0);
	vec3 hot_ = BONE_LIGHT;
	if (r >= RAMP_OWN) {
		vec3 c = beam_texel(b, B_CORE).rgb;
		lo_ = c * 0.55;
		mid_ = c;
		hi_ = mix(c, vec3(1.0), 0.35);
		hot_ = mix(c, vec3(1.0), 0.7);
	} else if (r >= RAMP_PLAYER) {
		int pi = clamp(r - RAMP_PLAYER, 0, 4);
		lo_ = P_SHADOW[pi];
		mid_ = P_BASE[pi];
		hi_ = P_LIGHT[pi];
	} else {
		int m = clamp(r, 0, MATERIALS - 1);
		lo_ = SHADES[m * 3];
		mid_ = SHADES[m * 3 + 1];
		hi_ = SHADES[m * 3 + 2];
		hot_ = mix(hi_, vec3(1.0), 0.5);
	}
	return k <= 0 ? lo_ : (k == 1 ? mid_ : (k == 2 ? hi_ : hot_));
}

// A 4 x 4 ordered dither's threshold (0 to 1) at the art pixel `q`.
const float BAYER[16] = float[](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
float bayer4(vec2 q) {
	ivec2 i = ivec2(mod(floor(q), 4.0));
	return (BAYER[i.x + i.y * 4] + 0.5) / 16.0;
}

// The palette's shade nearest `c`: the materials', the players' ramps, bone and the outline.
vec3 palette_snap(vec3 c) {
	vec3 best = BONE_LIGHT;
	float near = distance(c, BONE_LIGHT);
	for (int i = 0; i < MATERIALS * 3; i++) {
		float d = distance(c, SHADES[i]);
		if (d < near) {
			near = d;
			best = SHADES[i];
		}
	}
	for (int i = 0; i < 5; i++) {
		float d0 = distance(c, P_SHADOW[i]);
		float d1 = distance(c, P_BASE[i]);
		float d2 = distance(c, P_LIGHT[i]);
		best = d0 < near ? P_SHADOW[i] : best;
		near = min(near, d0);
		best = d1 < near ? P_BASE[i] : best;
		near = min(near, d1);
		best = d2 < near ? P_LIGHT[i] : best;
		near = min(near, d2);
	}
	return distance(c, OUTLINE) < near ? OUTLINE : best;
}

#endif
