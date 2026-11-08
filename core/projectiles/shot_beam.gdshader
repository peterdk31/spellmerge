// SPDX-License-Identifier: GPL-3.0-or-later
shader_type canvas_item;
// world_vertex_coords: VERTEX is in world space in vertex(), so each quad is placed in the world
// and the flares stand upright on the world's pixels (nothing else moves its vertices).
render_mode blend_premul_alpha, world_vertex_coords;

// A beam (Feel's beams; core/README.md, "The shot shaders"): a white-hot one-pixel core, a rim
// that breathes along it, motes of light running down it and flares at both ends. The splash
// where it lands and its card particles are motes (spell spectacle 2, S6 item 10: Feel's births,
// `gameplay/feel/births.gd`), not drawn here. Blending is premultiplied: its pixels are opaque,
// its glow added light.
// Its path is `beam_path` (`beam_points` points: x, y and how far along the beam each is), cut
// where it got (`beam_length` pixels); a short beam is a path of two points. Its core colour is
// `core_override`, its player and look these (`beam_player` -1, NO_PLAYER, is an enemy's beam).
// `beam_fade` (1 to 0) dissolves it into pixels as it ends; `beam_swell` (1 at rest) widens its
// rim and glow when it flares and narrows them as it thins; `beam_glow` is how strongly it glows.
//
// A beam is a mesh of small quads (`Feel.beam_mesh`; the owner, 2026-10-29), each told in its UV
// which QUAD KIND (Q_*) and slot it is. The vertex stage puts a piece's quad round it, or folds it
// away; the fragment stage only colours a pixel of its own quad:
//   Q_PIECE_LIGHT  the glow round piece `slot` of the path (and its motes, and the ends' light)
//   Q_PIECE        the beam's pixels along piece `slot` (core, rim, sparkles) and the flares
// A piece's quads reach a beam's width each side of it and BEAM_LEAD past the beam's ends, and
// a pixel belongs to the piece whose side of the bend it is on, so a bent beam is one line.

#include "res://core/projectiles/shot_beam.gdshaderinc"
