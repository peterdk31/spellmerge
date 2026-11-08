// SPDX-License-Identifier: GPL-3.0-or-later
shader_type canvas_item;
// world_vertex_coords: VERTEX is in world space in vertex(), so each quad is placed in the world
// and the trail stands upright on the world's pixels (nothing else moves its vertices).
render_mode blend_premul_alpha, world_vertex_coords;

// A swing's trail (Feel's swing trails, `gameplay/feel/swing_trails.gd`; melee I4, the owner's pick
// A3 "spark scatter"; core/README.md, "The shot shaders"): a brief one-pixel line at the arc's
// reach that follows the staff's tip and cools through the ramp behind it, and its light. The
// sparks it sheds outward as it passes and its card particles are motes (spell spectacle 2, S6
// item 10: Feel's births, `gameplay/feel/births.gd`), not drawn here. Blending is premultiplied:
// its pixels are opaque, its glow added light. The line is in its player's ramp with every fourth
// pixel in its infusion's (`core_override`), so a fire swing reads as fire and as whose.
//
// The sweep: round `swing_origin` (the hand) from `swing_dir` (the aim locked at the cast),
// turning `swing_side` (1 clockwise on screen, -1 back) from -`swing_lean` to +`swing_lean`
// radians in `swing_sweep` seconds from `swing_start` (both in `sim_time`'s seconds), slow, fast,
// slow (`Spells.swing_ease`); only -`swing_half` to +`swing_half` hits, and only that is drawn.
//
// A trail is a mesh of two quads (`SwingTrails.swing_mesh`), each told in its UV which QUAD KIND
// (Q_*) it is:
//   Q_LIGHT     the line's glow, over the square round the hand (added; drawn first)
//   Q_LINE      the line, over the square round the hand (drawn last, on top)
// The line and its light are worked out per pixel from its angle round the hand (when the tip
// passed it), with no loops.

#include "res://core/projectiles/shot_swing.gdshaderinc"
