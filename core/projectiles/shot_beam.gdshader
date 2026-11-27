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
// Every beam drawn with it is one merged shape, in one draw (`shot_beam_union.gdshaderinc`; Feel's
// BeamUnion, gameplay/feel/beam_union.gd, hands it every beam's path, colours, fade and swell in
// one data texture): one rim round beams that meet, none inside, each pixel drawn once.
// A beam's core colour, player and look come from its row; its fade (1 to 0) dissolves it into
// pixels as it ends, its swell (1 at rest) widens its rim and glow when it flares and narrows them
// as it thins, its glow is how strongly it glows.

#include "res://core/projectiles/shot_beam.gdshaderinc"
