// SPDX-License-Identifier: GPL-3.0-or-later
// Every beam as ONE merged shape (the owner, 2026-11-27: "Beams should merge into each other (like the
// pool)", "Everything merges. Ideally beams should inherit colors from every source after a
// junction"): the vertices and the union of the merged beams' shaders (the plain beam's,
// `shot_beam.gdshaderinc`, and a beam card's own look). Feel draws all the beams of one look shader
// in one draw (gameplay/feel/beam_union.gd, which says what the data texture holds:
// `shot_beam_data.gdshaderinc` reads it).
//
// THE MESH: a quad a piece of a path (its slot in UV.x; BeamUnion cuts a path into pieces of at most
// PIECE_MOST pixels, so each finds few near it), as wide as its beam each side and UNION_ROOM more
// (room for the union's swell), a lead past its beam's ends (the flares), as far past a bend (round
// joins); a slot past `seg_count` folds away. A pixel of it is the beam's own colour where the
// beam's pixels are (opaque) and its light elsewhere (added light): light under an opaque pixel is
// never seen, so one quad draws both, and a pixel is worked out once. Its vertices find the pieces
// near it once (the NEAR_MOST nearest, in order) and hand them to its pixels, which look closer only at those whose quad reaches them.
//
// THE UNION: a pixel works out, for each piece near (and its own), how far it is inside that
// piece's beam: `e`, its distance from the beam's middle (with the beam's own sway) less the
// beam's bands (below 0 inside), cut flat at the beam's ends and round at its bends. The beams'
// ripples and pulses (how far past its bands each one's edge reaches there) are added after the
// union, weighed by nearness as the colours are: a lone beam's edge ripples as its own, and the
// inside of beams that meet is not speckled by the ripples of beams hidden in it. A beam is its nearest piece (a hard union along one beam, so a bend
// never swells); the beams are a soft union, -SOFT x log of the sum of exp(-e / SOFT) (a sum, the
// same in any order and with a far beam left out, as the pools' merge): one distance, so one rim
// round the merged shape, none inside it, and two beams close or crossing melt into one body while
// beams apart keep their own rims, as a single beam's distance is its own. A beam nearly gone
// (BeamUnion.FADE_GIVES) weighs what is left of it in the sum, so it lets go of the others smoothly. Only the piece nearest
// the pixel draws it (of two as near, the first), so no pixel is drawn twice: no doubled light or
// alpha where beams overlap.
//
// THE COLOURS AT A JUNCTION: each beam near weighs exp(-(its e - the nearest's) / SOFT_COLOUR),
// and the pixel takes its colour from them by the rule `beam_mix` (MIX_*): an ordered dither between
// their colours, the blend of their colours snapped to the nearest palette shade, or the nearest
// beam's alone. The beam drawing the pixel is drawn in its own look (its strands, pulses, rift);
// another is its ramp at the pixel's band (`look_neighbour`).
//
// The including file has `shader_type` and `render_mode`, includes `shot_palette.gdshaderinc`,
// `shot_look.gdshaderinc` and `shot_beam_data.gdshaderinc`, then defines its hooks:
//   float look_bands(float swell, float width)   how many pixels each side of its middle its body
//                                                reaches, at `swell` (1 at rest)
//   float look_ripple(float along, float len, float side)   how far past its bands its edge reaches
//                                                `along` it (a ripple, a pulse's bulge), on its `side`
//   float look_off(float kind, float along, float len)   where its middle runs, pushed across (a
//                                                sway, a jag) by its first infusion's look kind
// and, for flat varyings of its own, a macro LOOK_VERTEX(L, b) (a varying is set in vertex() only)
// that sets them for its beam `b` of look `L`;
//   vec3 look_neighbour(float ramp, float kind, int b, float e)   another beam's colour at the
//                                                union's distance `e` (inside: below 0)
//   vec3 look_neighbour_glow(float ramp, float kind, int b)        and its light's colour
// and then includes this, and writes its fragment() from `union_at`.

#include "res://core/projectiles/shot_beam_data.gdshaderinc"

// The most pieces a piece's pixels look at besides their own (its quad's nearest; `near_d`, `near_i`
// in vertex() hold this many).
const int NEAR_MOST = 8;
// How soft the union is (pixels; BeamUnion.SOFT): two beams side by side melt into one body while
// their middles are within about four times this, and keep their own rims further apart.
const float SOFT = 3.0;
// How soon a beam's colour gives way to another's nearer it (pixels).
const float SOFT_COLOUR = 1.5;
// How far past its beam's width a piece's quad reaches (the union swells where beams meet).
const float UNION_ROOM = 1.0;
// A pixel past a beam's end (its flat cut) is this far outside it, and more as it is further.
const float OUTSIDE = 500.0;
// A beam's colour counts at a pixel only this near its edge (pixels outside it).
const float COLOUR_REACH = 2.0;
// A beam this much further in than the nearest adds nothing to the union worth a look (exp(-6) of it).
const float UNION_DEPTH = 12.0;
// The most a look pushes a beam's middle across (lightning's jag; `look_off`), in pixels.
const float SWAY_MOST = 3.0;

// The pixel in the world, its quad's piece and its piece's beam.
varying vec2 world;
varying flat float own;
varying flat float own_beam;
// The pieces near it (-1 for none), four to a vec4 (NEAR_MOST in all).
varying flat vec4 near_a;
varying flat vec4 near_b;

// ---- Vertices ----

// How far `p` is from the piece `a` to `b`.
float to_piece(vec2 p, vec2 a, vec2 b) {
	vec2 ab = b - a;
	float t = clamp(dot(p - a, ab) / max(dot(ab, ab), 0.0001), 0.0, 1.0);
	return length(p - a - ab * t);
}

// How far the piece `s` (its ends a, b in xy, zw) is from the piece `t`: 0 where they cross.
float between_pieces(vec4 s, vec4 t) {
	vec2 r = s.zw - s.xy;
	vec2 q = t.zw - t.xy;
	float den = r.x * q.y - r.y * q.x;
	vec2 w = t.xy - s.xy;
	float u = (w.x * q.y - w.y * q.x) / (abs(den) > 0.0001 ? den : 1.0);
	float v = (w.x * r.y - w.y * r.x) / (abs(den) > 0.0001 ? den : 1.0);
	bool cross = abs(den) > 0.0001 && u >= 0.0 && u <= 1.0 && v >= 0.0 && v <= 1.0;
	float d = min(min(to_piece(s.xy, t.xy, t.zw), to_piece(s.zw, t.xy, t.zw)), min(to_piece(t.xy, s.xy, s.zw), to_piece(t.zw, s.xy, s.zw)));
	return cross ? 0.0 : d;
}

// The `k`th of the near pieces `a`, `b` set to `v`.
void put_near(inout vec4 a, inout vec4 b, int k, float v) {
	vec4 one = vec4(equal(ivec4(k % 4), ivec4(0, 1, 2, 3)));
	if (k < 4) {
		a = mix(a, vec4(v), one);
	} else {
		b = mix(b, vec4(v), one);
	}
}

// The `k`th near piece, or -1.
int near_piece(int k) {
	vec4 v = k < 4 ? near_a : near_b;
	int i = k % 4;
	return int(i == 0 ? v.x : (i == 1 ? v.y : (i == 2 ? v.z : v.w)));
}

void vertex() {
	int slot = int(floor(UV.x));
	vec2 corner = vec2(fract(UV.x) > 0.5 ? 1.0 : 0.0, fract(UV.y) > 0.5 ? 1.0 : 0.0);
	bool shown = slot < seg_count;
	int s = clamp(slot, 0, max(seg_count - 1, 0));
	vec4 ends = seg_texel(s, S_ENDS);
	vec4 who = seg_texel(s, S_WHO);
	float half_width = seg_texel(s, S_WIDTH).x * 0.5 + UNION_ROOM;
	int b = int(who.x + 0.5);
	vec4 core_row = beam_texel(b, B_CORE);
	vec4 look_row = beam_texel(b, B_LOOK);
	Look L = look_of(core_row.rgb, core_row.a < -0.5 ? ENEMY_PLAYER : min(core_row.a, 3.0), 1.0, look_row.xyz, 0.0, true);
	SET_LOOK(L);
#ifdef LOOK_VERTEX
	LOOK_VERTEX(L, b);
#endif
	// Its quad: from its start to its end, a lead past its beam's ends, as wide as its beam each
	// side and UNION_ROOM more, its beam's width past a bend (round joins).
	vec2 A = ends.xy;
	vec2 B = ends.zw;
	float len = length(B - A);
	vec2 way = len > 0.001 ? (B - A) / len : vec2(1.0, 0.0);
	vec2 side = vec2(-way.y, way.x);
	bool first = flag_set(who.y, F_FIRST);
	bool last = flag_set(who.y, F_LAST);
	// A pixel past a cut of a straight piece is the next piece's: a quad reaches a pixel past one only.
	float back = first ? beam_lead : (flag_set(who.y, F_CUT_BEFORE) ? 1.0 : half_width);
	float on = last ? beam_lead : (flag_set(who.y, F_CUT_AFTER) ? 1.0 : half_width);
	vec2 along_corner = mix(A - way * back, B + way * on, corner.x);
	vec2 at = along_corner + side * mix(-half_width, half_width, corner.y);
	VERTEX = shown ? at : vec2(-1.0e6);
	world = VERTEX;
	own = float(s);
	own_beam = float(b);
	// The pieces near: the NEAR_MOST nearest whose quad may reach its own (never its own beam's next
	// piece past a cut of a straight piece: a pixel past one is that piece's own), then put in order
	// (a beam's pieces one after another, as its pixels gather them).
	float near_d[8];
	int near_i[8];
	int found = 0;
	float ext = half_width + (first || last ? beam_lead : 0.0);
	if (shown) {
		for (int j = 0; j < seg_count; j++) {
			vec4 there_who = seg_texel(j, S_WHO);
			bool own_beam_j = int(there_who.x + 0.5) == b;
			bool cut_next = own_beam_j && ((j == s - 1 && flag_set(who.y, F_CUT_BEFORE)) || (j == s + 1 && flag_set(who.y, F_CUT_AFTER)));
			if (j != s && !cut_next) {
				bool there_end = flag_set(there_who.y, F_FIRST) || flag_set(there_who.y, F_LAST);
				float reach = ext + seg_texel(j, S_WIDTH).x * 0.5 + UNION_ROOM + (there_end ? beam_lead : 0.0);
				float d = between_pieces(ends, seg_texel(j, S_ENDS));
				if (d <= reach) {
					// Kept if there is room, or in place of the furthest kept.
					int put_at = found;
					if (found >= NEAR_MOST) {
						put_at = 0;
						for (int k = 1; k < NEAR_MOST; k++) {
							put_at = near_d[k] > near_d[put_at] ? k : put_at;
						}
						put_at = d < near_d[put_at] ? put_at : -1;
					} else {
						found++;
					}
					if (put_at >= 0) {
						near_d[put_at] = d;
						near_i[put_at] = j;
					}
				}
			}
		}
	}
	// In order of their index.
	for (int k = 1; k < NEAR_MOST; k++) {
		for (int m = k; m > 0; m--) {
			if (m < found && near_i[m] < near_i[m - 1]) {
				int swap = near_i[m];
				near_i[m] = near_i[m - 1];
				near_i[m - 1] = swap;
			}
		}
	}
	vec4 na = vec4(-1.0);
	vec4 nb = vec4(-1.0);
	for (int k = 0; k < NEAR_MOST; k++) {
		if (k < found) {
			put_near(na, nb, k, float(near_i[k]));
		}
	}
	near_a = na;
	near_b = nb;
}

// ---- Fragments ----

// A piece at a pixel: whether its quad reaches the pixel (`reaches`; nothing else is worked out when
// not) and whether the pixel is past a cut of its straight piece (`beyond`: the next piece's own);
// how far inside its beam's bands it is (`e`, below 0 inside; OUTSIDE and more past its beam's
// ends), the same less its fade's share (`ord`: which piece draws the pixel), and the beam's numbers
// there: along it, across it (in art pixels, `xs`; `x` in world pixels from its middle), its side,
// edge (its bands and its ripple there), bands, ripple, length, fade, swell, the beam, its flags,
// ramp and kind, the piece's ends and the longer axis's share of its way (`cheb`).
struct Piece {
	bool reaches;
	bool beyond;
	float e;
	float ord;
	float along;
	float xs;
	float x;
	float side;
	float edge;
	float bands;
	float ripple;
	float len;
	float fade;
	float swell;
	float beam;
	float flags;
	float ramp;
	float kind;
	float cheb;
	vec2 a;
	vec2 b;
};

// A quick look at piece `s` at the pixel `P` (four texels, no look hooks): its order (`ord`) give
// or take its sway, or OUTSIDE where it is past its beam's ends or its quad does not reach.
float quick_ord(int s, vec2 P) {
	vec4 ends = seg_texel(s, S_ENDS);
	vec4 shape = seg_texel(s, S_SHAPE);
	vec4 wide = seg_texel(s, S_WIDTH);
	float span = length(ends.zw - ends.xy);
	vec2 way = span > 0.001 ? (ends.zw - ends.xy) / span : vec2(1.0, 0.0);
	vec2 d = P - ends.xy;
	float t = dot(d, way);
	float cheb = max(abs(way.x), abs(way.y));
	float x = abs(dot(d, vec2(-way.y, way.x))) / max(cheb, 0.5);
	float over = t < 0.0 ? -t : max(t - span, 0.0);
	x = over > 0.0 ? length(vec2(x, over)) : x;
	// Past its beam's ends it is outside; past a bend, round (as `piece_at`).
	vec4 who = seg_texel(s, S_WHO);
	bool cut = (t < 0.0 && flag_set(who.y, F_FIRST)) || (t > span && flag_set(who.y, F_LAST));
	bool reaches = x <= wide.x * 0.5 + UNION_ROOM + beam_lead + 2.0;
	return reaches && !cut ? x - look_bands(shape.z, wide.x) + shape.w : OUTSIDE;
}

Piece piece_at(int s, vec2 P, bool own_piece) {
	Piece p;
	vec4 ends = seg_texel(s, S_ENDS);
	vec4 who = seg_texel(s, S_WHO);
	float width = seg_texel(s, S_WIDTH).x;
	p.a = ends.xy;
	p.b = ends.zw;
	p.beam = who.x;
	p.flags = who.y;
	p.ramp = who.z;
	p.kind = who.w;
	bool first = flag_set(p.flags, F_FIRST);
	bool last = flag_set(p.flags, F_LAST);
	float span = length(p.b - p.a);
	vec2 way = span > 0.001 ? (p.b - p.a) / span : vec2(1.0, 0.0);
	vec2 d = P - p.a;
	float t = dot(d, way);
	float across = dot(d, vec2(-way.y, way.x));
	// Its quad: a beam's width and UNION_ROOM each side, a lead past its beam's ends, as far past a bend.
	float half_width = width * 0.5 + UNION_ROOM;
	float over = t < 0.0 ? -t : max(t - span, 0.0);
	float reach_end = (t < 0.0 ? first : last) ? beam_lead : half_width;
	p.reaches = abs(across) <= half_width + 1.0 && over <= reach_end + 1.0;
	p.beyond = (flag_set(p.flags, F_CUT_BEFORE) && t < 0.0) || (flag_set(p.flags, F_CUT_AFTER) && t >= span);
	p.e = OUTSIDE;
	p.ord = OUTSIDE;
	if (!p.reaches) {
		return p;
	}
	vec4 shape = seg_texel(s, S_SHAPE);
	vec4 wide = seg_texel(s, S_WIDTH);
	p.along = shape.x + t;
	p.len = max(shape.y, 1.0);
	p.swell = shape.z;
	p.fade = wide.z;
	p.cheb = max(abs(way.x), abs(way.y));
	float off = look_off(p.kind, p.along, p.len);
	// Its lane across in art pixels: a line an art pixel fine, one a step of the longer axis.
	p.xs = floor((across - off) * ART_DETAIL / max(p.cheb, 0.5) + 0.5);
	p.side = p.xs < 0.0 ? 1.0 : 0.0;
	p.x = abs(p.xs) / ART_DETAIL;
	// Round past a bend: as far as the bend's point.
	p.x = over > 0.0 ? length(vec2(p.x, over)) : p.x;
	p.bands = look_bands(p.swell, width);
	// Another beam's ripple shows only on its own edge, which its own pieces draw: not worked out here.
	p.ripple = own_piece ? look_ripple(p.along, p.len, p.side) : 0.0;
	p.edge = p.bands + p.ripple;
	bool cut = (first && t < 0.0) || (last && t > span);
	p.e = cut ? OUTSIDE + p.x : p.x - p.bands;
	// A fading beam gives way (`shape.w`, BeamUnion's `give_of`): only once it is nearly gone, so a
	// lone beam keeps its own shape while it dissolves into pixels, and lets go of the others smoothly.
	p.ord = cut ? p.e : p.e + shape.w;
	return p;
}

// The merged shape at a pixel: its distance (`e`, below 0 inside), whether this quad's piece draws
// the pixel (`mine`), how wide its bands are there (weighed by nearness), this beam's share of the
// colour (`own_w`), the two other beams nearest (`o1_*`, `o2_*`: the beam, -1 for none, its ramp,
// kind and share) and the dither's pick among them and this beam (`pick`: 0 this beam, 1 or 2); the
// nearest beam start and end (their flares): how far (in whole world pixels), the beam (-1 when none
// is near), its ramp, bands, kind and (an end's) fade.
struct Union {
	float e;
	bool mine;
	float bands;
	float own_w;
	float o1_beam;
	float o1_ramp;
	float o1_kind;
	float o1_w;
	float o2_beam;
	float o2_ramp;
	float o2_kind;
	float o2_w;
	int pick;
	vec2 start_d;
	float start_beam;
	float start_ramp;
	float start_bands;
	float start_kind;
	vec2 end_d;
	float end_beam;
	float end_ramp;
	float end_bands;
	float end_kind;
	float end_fade;
};

// A beam's nearest piece at the pixel, as `union_at` gathers it: its beam, distance, order,
// bands, ripple, ramp and kind.
struct Near {
	float beam;
	float e;
	float ord;
	float bands;
	float ripple;
	float ramp;
	float kind;
};

// What `union_at` sums over the beams: the soft union, the colours' weights and the weighed bands
// and ripples.
struct Sums {
	float soft;
	float w;
	float bands;
	float ripple;
};

Near near_of(Piece q) {
	Near g;
	g.beam = q.beam;
	g.e = q.e;
	g.ord = q.ord;
	g.bands = q.bands;
	g.ripple = q.ripple;
	g.ramp = q.ramp;
	g.kind = q.kind;
	return g;
}

// Beam `g` counted in: the union's sum, and its colour's weight (only near the body), its own beam's
// to `u.own_w`, another's kept when it is one of the two heaviest.
void count_beam(Near g, float own_beam_id, inout Sums sums, inout Union u) {
	sums.soft += exp(-g.ord / SOFT);
	if (g.e < COLOUR_REACH + g.ripple) {
		float w = exp(-g.ord / SOFT_COLOUR);
		sums.w += w;
		sums.bands += w * g.bands;
		sums.ripple += w * g.ripple;
		if (g.beam == own_beam_id) {
			u.own_w += w;
		} else if (w > u.o1_w) {
			u.o2_beam = u.o1_beam;
			u.o2_ramp = u.o1_ramp;
			u.o2_kind = u.o1_kind;
			u.o2_w = u.o1_w;
			u.o1_beam = g.beam;
			u.o1_ramp = g.ramp;
			u.o1_kind = g.kind;
			u.o1_w = w;
		} else if (w > u.o2_w) {
			u.o2_beam = g.beam;
			u.o2_ramp = g.ramp;
			u.o2_kind = g.kind;
			u.o2_w = w;
		}
	}
}

// The union at `P` (the pixel in the world), and this quad's piece there (`me`).
Union union_at(vec2 P, out Piece me) {
	Union u;
	vec2 cell = floor(P);
	me = piece_at(int(own), P, true);
	u.e = OUTSIDE;
	u.mine = me.reaches && !me.beyond;
	u.bands = me.bands;
	u.own_w = 0.0;
	u.o1_beam = -1.0;
	u.o1_ramp = 0.0;
	u.o1_kind = 0.0;
	u.o1_w = 0.0;
	u.o2_beam = -1.0;
	u.o2_ramp = 0.0;
	u.o2_kind = 0.0;
	u.o2_w = 0.0;
	u.pick = 0;
	u.start_beam = -1.0;
	u.end_beam = -1.0;
	u.start_d = vec2(1.0e4);
	u.end_d = vec2(1.0e4);
	u.start_ramp = 0.0;
	u.end_ramp = 0.0;
	u.start_bands = 0.0;
	u.end_bands = 0.0;
	u.start_kind = 0.0;
	u.end_kind = 0.0;
	u.end_fade = 0.0;
	if (!u.mine) {
		return u;
	}
	Sums sums;
	sums.soft = 0.0;
	sums.w = 0.0;
	sums.bands = 0.0;
	sums.ripple = 0.0;
	// This quad's beam (its other pieces only bring it nearer), and the other beam gathered now (a
	// beam's pieces come one after another in the list).
	Near mine_g = near_of(me);
	Near g = mine_g;
	bool gathering = false;
	if (flag_set(me.flags, F_FIRST)) {
		u.start_d = cell - floor(me.a);
		u.start_beam = me.beam;
		u.start_ramp = me.ramp;
		u.start_bands = me.bands;
		u.start_kind = me.kind;
	}
	if (flag_set(me.flags, F_LAST)) {
		u.end_d = cell - floor(me.b);
		u.end_beam = me.beam;
		u.end_ramp = me.ramp;
		u.end_bands = me.bands;
		u.end_kind = me.kind;
		u.end_fade = me.fade;
	}
	for (int k = 0; k < NEAR_MOST; k++) {
		int j = near_piece(k);
		if (j < 0 || j >= seg_count) {
			break;
		}
		// A quick look first: a piece clearly nearer draws the pixel (so this quad is done), and one far
		// further in adds nothing (but its beam's ends, which may flare here).
		float quick = quick_ord(j, P);
		float slack = (SWAY_MOST + 1.0) * 1.5;
		if (quick < me.ord - slack) {
			u.mine = false;
			break;
		}
		float flags = seg_texel(j, S_WHO).y;
		bool ends_here = flag_set(flags, F_FIRST) || flag_set(flags, F_LAST);
		if (quick > me.ord + UNION_DEPTH + slack && !ends_here) {
			continue;
		}
		Piece q = piece_at(j, P, false);
		if (q.reaches) {
			// Drawn by the nearest piece: of two as near, the first (one past a cut draws nothing).
			if (!q.beyond && (q.ord < me.ord || (q.ord == me.ord && j < int(own)))) {
				u.mine = false;
				break;
			}
			// A beam is its nearest piece: a piece of a beam gathered only brings it nearer.
			if (q.beam == me.beam) {
				if (q.ord < mine_g.ord) {
					mine_g = near_of(q);
				}
			} else if (gathering && q.beam == g.beam) {
				if (q.ord < g.ord) {
					g = near_of(q);
				}
			} else {
				if (gathering) {
					count_beam(g, me.beam, sums, u);
				}
				g = near_of(q);
				gathering = true;
			}
			// The nearest beam start and end round the pixel (their flares and lights).
			vec2 ds = cell - floor(q.a);
			vec2 de = cell - floor(q.b);
			if (flag_set(q.flags, F_FIRST) && dot(ds, ds) < dot(u.start_d, u.start_d)) {
				u.start_d = ds;
				u.start_beam = q.beam;
				u.start_ramp = q.ramp;
				u.start_bands = q.bands;
				u.start_kind = q.kind;
			}
			if (flag_set(q.flags, F_LAST) && dot(de, de) < dot(u.end_d, u.end_d)) {
				u.end_d = de;
				u.end_beam = q.beam;
				u.end_ramp = q.ramp;
				u.end_bands = q.bands;
				u.end_kind = q.kind;
				u.end_fade = q.fade;
			}
		}
	}
	if (!u.mine) {
		return u;
	}
	count_beam(mine_g, me.beam, sums, u);
	if (gathering) {
		count_beam(g, me.beam, sums, u);
	}
	// The soft union of the beams (each weighed by its fade), less the beams' ripples by their shares.
	float union_e = sums.soft > 0.0 ? -SOFT * log(sums.soft) : OUTSIDE;
	u.bands = sums.w > 0.0 ? sums.bands / sums.w : me.bands;
	u.e = union_e - (sums.w > 0.0 ? sums.ripple / sums.w : me.ripple);
	// The shares of this beam and the two others nearest, and the dither's pick among them: a
	// threshold an art pixel, their shares stacked in the beams' order.
	float total = u.own_w + u.o1_w + u.o2_w;
	if (total <= 0.0) {
		u.own_w = 1.0;
		return u;
	}
	u.own_w /= total;
	u.o1_w /= total;
	u.o2_w /= total;
	float t = bayer4(P * ART_DETAIL);
	float below0 = (u.o1_beam >= 0.0 && u.o1_beam < me.beam ? u.o1_w : 0.0) + (u.o2_beam >= 0.0 && u.o2_beam < me.beam ? u.o2_w : 0.0);
	float below1 = (u.o1_beam > me.beam ? u.own_w : 0.0) + (u.o2_beam >= 0.0 && u.o2_beam < u.o1_beam ? u.o2_w : 0.0);
	float below2 = (u.o2_beam > me.beam ? u.own_w : 0.0) + (u.o1_beam < u.o2_beam ? u.o1_w : 0.0);
	u.pick = t >= below1 && t < below1 + u.o1_w ? 1 : (t >= below2 && t < below2 + u.o2_w ? 2 : 0);
	return u;
}

// The pixel's colour by the rule at a junction, `own_colour` this beam's own colour there.
vec3 union_colour(Union u, vec3 own_colour) {
	vec3 c = own_colour;
	if (beam_mix == MIX_DITHER && u.pick == 1) {
		c = look_neighbour(u.o1_ramp, u.o1_kind, int(u.o1_beam + 0.5), u.e);
	} else if (beam_mix == MIX_DITHER && u.pick == 2) {
		c = look_neighbour(u.o2_ramp, u.o2_kind, int(u.o2_beam + 0.5), u.e);
	} else if (beam_mix == MIX_SNAP && u.own_w < 0.999) {
		vec3 blend = own_colour * u.own_w;
		blend += u.o1_w > 0.0 ? u.o1_w * look_neighbour(u.o1_ramp, u.o1_kind, int(u.o1_beam + 0.5), u.e) : vec3(0.0);
		blend += u.o2_w > 0.0 ? u.o2_w * look_neighbour(u.o2_ramp, u.o2_kind, int(u.o2_beam + 0.5), u.e) : vec3(0.0);
		c = palette_snap(blend);
	}
	return c;
}

// The light's colour where beams meet: this beam's glow and the others' by their shares.
vec3 union_glow(Union u, vec3 own_glow) {
	vec3 c = own_glow * u.own_w;
	c += u.o1_w > 0.0 ? u.o1_w * look_neighbour_glow(u.o1_ramp, u.o1_kind, int(u.o1_beam + 0.5)) : vec3(0.0);
	c += u.o2_w > 0.0 ? u.o2_w * look_neighbour_glow(u.o2_ramp, u.o2_kind, int(u.o2_beam + 0.5)) : vec3(0.0);
	return beam_mix == MIX_NEAREST ? own_glow : c;
}
