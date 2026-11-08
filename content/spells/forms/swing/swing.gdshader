// SPDX-License-Identifier: GPL-3.0-or-later
shader_type canvas_item;
render_mode blend_premul_alpha, world_vertex_coords;

// A swing card's own look (content/spells/forms/swing/: `FormBase.look_shader`; docs/milestones/card-looks.md):
// for now the plain trail (`core/projectiles/shot_swing.gdshader`, the fallback), drawn by its include,
// so every fix to it reaches the swing card. To give the swing a look of its own, replace the
// include with a copy of it and change that. Feel's swing trails draw each swing's trail with it on
// the trail's own material; warmed as a mesh before the first room.

#include "res://core/projectiles/shot_swing.gdshaderinc"
