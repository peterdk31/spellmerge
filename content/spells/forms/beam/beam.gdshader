// SPDX-License-Identifier: GPL-3.0-or-later
shader_type canvas_item;
render_mode blend_premul_alpha, world_vertex_coords;

// A beam card's own look (content/spells/forms/beam/: `FormBase.look_shader`; docs/milestones/card-looks.md):
// for now the plain beam (`core/projectiles/shot_beam.gdshader`, which still draws a ray with no beam
// card: a chain's jump, a zap), drawn by its include, so every fix to it reaches the beam card. To
// give the beam a look of its own, replace the include with a copy of it and change that. Feel
// draws each live beam with it on the beam's own material; warmed as a mesh before the first room.

#include "res://core/projectiles/shot_beam.gdshaderinc"
